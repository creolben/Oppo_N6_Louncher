package com.launcher.chronofold.mylauncher

import android.content.Context
import android.content.ComponentName
import android.content.Intent
import android.app.SearchManager
import android.content.pm.ApplicationInfo
import android.content.pm.LauncherApps
import android.content.pm.PackageManager
import android.content.pm.ResolveInfo
import android.content.pm.ShortcutInfo
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Rect
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.Drawable
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.media.MediaMetadata
import android.media.session.MediaController
import android.media.session.MediaSessionManager
import android.media.session.PlaybackState
import android.net.Uri
import android.os.BatteryManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.Process
import android.os.UserHandle
import android.os.VibrationAttributes
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.media.AudioAttributes
import android.provider.Settings
import android.content.BroadcastReceiver
import android.content.IntentFilter
import android.os.Bundle
import android.view.WindowManager
import android.app.KeyguardManager
import android.app.WallpaperManager
import android.app.role.RoleManager
import android.hardware.biometrics.BiometricPrompt
import android.hardware.fingerprint.FingerprintManager
import android.os.CancellationSignal
import android.os.PowerManager
import android.provider.MediaStore
import androidx.annotation.NonNull
import com.tom_roush.pdfbox.android.PDFBoxResourceLoader
import com.tom_roush.pdfbox.pdmodel.PDDocument
import com.tom_roush.pdfbox.pdmodel.encryption.InvalidPasswordException
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.android.FlutterActivityLaunchConfigs.BackgroundMode
import io.flutter.embedding.android.RenderMode
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.concurrent.Executors

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
class MainActivity : FlutterActivity() {
    companion object {
        private const val TAG = "ChronoFold"

        /** Request code for the single in-flight `pickPdf` document dialog. */
        private const val REQUEST_PICK_PDF = 0x5046

        /** Text extraction stops after this many pages. */
        private const val MAX_EXTRACT_PAGES = 30

        /** Unpinned shortcuts shown per app; pinned ones are always kept. */
        private const val MAX_UNPINNED_SHORTCUTS = 5

        /** Longest edge a shortcut icon is sent at, in dp. */
        private const val MAX_SHORTCUT_ICON_DP = 64

        /** Wallpaper blur behind full-screen surfaces, in dp. */
        private const val WINDOW_BLUR_DP = 24
    }

    /**
     * A PDF path received from [ShareReceiverActivity] that Dart has not yet
     * consumed.
     *
     * Kept until `takePendingSharedPdf` clears it, so a cold start can pull it
     * after the engine is ready even when the `onSharedPdf` push raced Dart's
     * handler installation.
     */
    private var pendingSharedPdfPath: String? = null

    /** Off-main-thread executor for PDF parsing and picked-file copying. */
    private val pdfExecutor = Executors.newSingleThreadExecutor()

    /**
     * Off-main-thread executor for shortcut queries.
     *
     * Resolving a package's shortcuts and rasterising their icons is real work
     * that must not run on the frame the dialog opens on.
     */
    private val shortcutExecutor = Executors.newSingleThreadExecutor()

    /** The Flutter result waiting on the one in-flight `pickPdf` dialog. */
    private var pendingPdfPickResult: MethodChannel.Result? = null

    /** Main-looper handler for platform callbacks that must reach Dart. */
    private val mainHandler = Handler(Looper.getMainLooper())

    /**
     * Off-main-thread executor for wallpaper offset reports. The call is a
     * binder round trip to WindowManager and arrives once per camera frame
     * while the galaxy pans, so it is coalesced to the newest pair and kept
     * off the UI thread the way Launcher3 keeps its own offset interpolator.
     */
    private val wallpaperExecutor = Executors.newSingleThreadExecutor()

    @Volatile private var pendingWallpaperX = Float.NaN
    @Volatile private var pendingWallpaperY = Float.NaN
    @Volatile private var wallpaperReportQueued = false

    /**
     * The wallpaper-colour listener, so a wallpaper change re-tints the status
     * bar and the scrims while the launcher is running. Registered in
     * [onCreate] and removed in [onDestroy].
     */
    private var wallpaperColorsListener: WallpaperManager.OnColorsChangedListener? = null

    /** Whether PDFBoxResourceLoader has been initialized for this process. */
    private var pdfBoxInitialized = false

    /**
     * Whether the keyguard required authentication when the panel last went
     * off. Only an unlock that follows a genuinely locked keyguard is handed to
     * the launcher: a wake that merely dismissed an already-open keyguard is
     * not an authentication and must not clear the overlay.
     */
    private var keyguardWasLocked = false
    private var screenReceiver: BroadcastReceiver? = null
    private var packageReceiver: BroadcastReceiver? = null

    /**
     * The shared channel surface. Created once per engine in
     * [configureFlutterEngine] and disposed in [onDestroy]; null before the
     * engine attaches.
     */
    private var lockSurface: LockSurfaceChannels? = null

    /**
     * Whether MainActivity is the resumed activity.
     *
     * The screen receiver registered in [onCreate] is unregistered only in
     * [onDestroy], so it keeps firing for the entire time another app is in
     * front of the launcher. Without this the launcher answered screen events
     * that had nothing to do with it — see [foreignTaskForeground].
     */
    private var launcherResumed = false

    /**
     * Whether the launcher has deliberately handed the screen to another app
     * and has not yet come back.
     *
     * This is the difference between "the screen went off on the launcher" and
     * "the screen went off inside the app the launcher opened", and answering
     * both the same way is what produced a fingerprint prompt on the way back:
     * the launcher re-raised its own lock surface and re-asserted
     * `showWhenLocked` while it was paused behind a foreign task, so returning
     * from that app landed on a keyguard-occluding launcher with a lock panel
     * mounted, and the next touch went to the platform bouncer.
     *
     * Paired with [pausedForForeignTask] rather than read alone, so a transient
     * resume between the start request and the target actually appearing cannot
     * be mistaken for the user coming back.
     */
    private var foreignTaskForeground = false
    private var pausedForForeignTask = false

    /** True once a foreign task is genuinely in front of the launcher. */
    private val foreignTaskOwnsScreen: Boolean
        get() = foreignTaskForeground && pausedForForeignTask

    /**
     * Records that the launcher is about to send the user into another app.
     *
     * Every external `startActivity` in this class goes through here, including
     * the settings/uninstall/browser handoffs that do not use the return
     * bridge: they background the launcher just as thoroughly as an app launch.
     */
    private fun markForeignTaskHandoff() {
        foreignTaskForeground = true
        pausedForForeignTask = false
    }

    /** What differs from the lock activity; everything else is shared. */
    private val lockSurfaceHost = object : LockSurfaceChannels.Host {
        override fun isForeground(): Boolean = launcherResumed && !foreignTaskOwnsScreen

        override fun onForeignHandoff() = markForeignTaskHandoff()

        override fun onForeignHandoffFailed() {
            foreignTaskForeground = false
            pausedForForeignTask = false
        }

        override fun onFinishLock() {
            // The launcher's panel is cleared by Dart, not by finishing the
            // home activity; only the lock activity finishes here.
        }

        override fun setOverlayWhenLocked(enabled: Boolean) {
            this@MainActivity.setOverlayWhenLocked(enabled)
        }

        override fun startTarget(intent: Intent, options: Bundle?, onStarted: (Boolean) -> Unit) {
            // A plain start. The window behind the departing app is the
            // system wallpaper (HomeTheme shows it through the transparent
            // Flutter surface), which is exactly what ColorOS's own close
            // animation lands on, so no native cover surface is needed.
            onStarted(lockSurface?.startActivityQuietly(intent, options) ?: false)
        }

        override fun onUnhandledMethod(call: MethodCall, result: MethodChannel.Result): Boolean =
            handleMainOnlyMethod(call, result)
    }
    /**
     * The Flutter surface is transparent so the system wallpaper (shown by
     * HomeTheme's `windowShowWallpaper`) is the launcher's backdrop. Flutter
     * clears the window background itself in this mode, so nothing here
     * paints a colour behind the engine.
     */
    override fun getBackgroundMode(): BackgroundMode = BackgroundMode.transparent

    /**
     * Keep the SurfaceView renderer. FlutterActivity's default for a
     * transparent background is a TextureView, which costs an extra GPU copy
     * every frame of a 120Hz galaxy; a SurfaceView with a transparent pixel
     * format composes directly over the wallpaper layer instead.
     */
    override fun getRenderMode(): RenderMode = RenderMode.surface

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        registerWallpaperColorsListener()
        // ColorOS owns the lock screen. The launcher starts as an ordinary home
        // app that does NOT draw over the keyguard, which is the only
        // arrangement where the platform's own lock screen is the thing
        // standing between a locked device and its contents.
        //
        // Occluding the keyguard is opt-in, and only Dart asks for it — see
        // `setLockScreenOverlayEnabled`. Asserting it here (or in the manifest)
        // meant the launcher was drawn over the keyguard from process start,
        // before any preference had been read, so a surface that authenticates
        // nobody was the first thing on a locked screen.
        setOverlayWhenLocked(false)

        // A cold boot starts a process while the keyguard is already locked,
        // and no ACTION_SCREEN_OFF will ever arrive for that lock — the
        // screen never went off inside this process — so keyguardWasLocked
        // stayed false and the first USER_PRESENT was dropped: the lock
        // panel mounted by the Dart cold-start check then remained over an
        // unlocked device until a swipe cleared it. Record the state here,
        // in onCreate, the one point that runs for the genuine process
        // start a cold boot is. The write is deliberately one-way (true
        // only): the activity is recreated on rotation/unfold, and that
        // recreation must not clobber the pending lock an intervening
        // SCREEN_OFF has already recorded, while a start that begins
        // unlocked leaves the flag exactly as it was — false. onResume was
        // considered and rejected: it fires on every foreground return,
        // which is exactly the window USER_PRESENT arrives in, so a read
        // there could replace the flag with a keyguard answer that no
        // longer describes the lock session the flag exists to carry.
        val keyguardAtStart = getSystemService(Context.KEYGUARD_SERVICE) as? KeyguardManager
        if (keyguardAtStart?.isKeyguardLocked == true ||
            keyguardAtStart?.isDeviceLocked == true
        ) {
            keyguardWasLocked = true
        }

        screenReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                val keyguard = getSystemService(Context.KEYGUARD_SERVICE) as? KeyguardManager
                when (intent?.action) {
                    Intent.ACTION_SCREEN_OFF -> {
                        keyguardWasLocked = keyguard?.isKeyguardLocked == true ||
                            keyguard?.isDeviceLocked == true
                        // A screen-off that happens inside an app the launcher
                        // opened is not the launcher's lock event. Reporting it
                        // as one mounted the cosmic panel and re-asserted
                        // `showWhenLocked` on a paused activity, so closing that
                        // app returned to a keyguard-occluding launcher and the
                        // platform asked for a fingerprint.
                        //
                        // MainActivity stays out of it: the platform keyguard
                        // is what locked the device, and the separate lock
                        // activity raised here is the surface that
                        // authenticates the user back in.
                        if (foreignTaskOwnsScreen) {
                            // The launcher must NOT re-assert showWhenLocked
                            // or mount its own panel here — raising the HOME
                            // task over the keyguard sent the user back to the
                            // launcher instead of their app. A separate
                            // LockActivity in its own task is raised instead,
                            // so finishing it reveals exactly what was
                            // underneath; MainActivity's Dart is not told about
                            // this screen-off at all.
                            android.util.Log.d(
                                "ChronoFold",
                                "CF_LOCK: screen off over foreign task; raising lock activity",
                            )
                            raiseLockActivityOverForeignTask()
                            return
                        }
                        runOnUiThread {
                            lockSurface?.invokeAppsMethod("lockScreen", null)
                        }
                    }
                    Intent.ACTION_SCREEN_ON -> {
                        // `screenOn` arms the lock panel's fingerprint reader.
                        // Arming it from behind a foreign task is a biometric
                        // session the user never asked for, and on a device
                        // where the system draws the sensor affordance it is a
                        // prompt appearing out of nowhere.
                        if (foreignTaskOwnsScreen) return
                        runOnUiThread {
                            lockSurface?.invokeAppsMethod("screenOn", null)
                        }
                    }
                    Intent.ACTION_USER_PRESENT -> {
                        if (keyguardWasLocked) {
                            keyguardWasLocked = false
                            if (foreignTaskOwnsScreen) return
                            runOnUiThread {
                                lockSurface?.invokeAppsMethod("userPresent", null)
                            }
                        }
                    }
                }
            }
        }
        val filter = IntentFilter().apply {
            addAction(Intent.ACTION_SCREEN_OFF)
            addAction(Intent.ACTION_SCREEN_ON)
            addAction(Intent.ACTION_USER_PRESENT)
        }
        registerReceiver(screenReceiver, filter)

        // Dynamic package change receiver (install, uninstall, update)
        packageReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                runOnUiThread {
                    lockSurface?.invokeAppsMethod("onPackagesChanged", null)
                }
            }
        }
        val pkgFilter = IntentFilter().apply {
            addAction(Intent.ACTION_PACKAGE_ADDED)
            addAction(Intent.ACTION_PACKAGE_REMOVED)
            addAction(Intent.ACTION_PACKAGE_REPLACED)
            addDataScheme("package")
        }
        registerReceiver(packageReceiver, pkgFilter)

        // A cold start through ShareReceiverActivity carries the PDF path in
        // the launch intent. Consume it here, after the engine is configured:
        // the push reaches Dart when it is listening, and the retained pending
        // path covers the case where Dart has not bound its handler yet.
        handleSharedPdfExtra(intent)
    }
    override fun onPause() {
        launcherResumed = false
        if (foreignTaskForeground) {
            pausedForForeignTask = true
        }
        // The reader is deliberately NOT cancelled here. Dart owns that
        // decision, and it tracks whether a session is live; cancelling behind
        // its back leaves it believing it holds a reader that no longer exists,
        // which is a dead sensor rather than a spurious prompt. The
        // `launcherResumed` guard in startFingerprintScan is what keeps a
        // background arm from happening in the first place.
        super.onPause()
    }

    override fun onResume() {
        super.onResume()
        launcherResumed = true
        // A wallpaper/theme change resumes the activity; re-read the Material
        // You palette so the launcher re-colours without a restart.
        lockSurface?.pushSystemPaletteIfChanged()
        // Back in front: the handoff is over, so ordinary screen events belong
        // to the launcher again.
        if (foreignTaskForeground && pausedForForeignTask) {
            foreignTaskForeground = false
            pausedForForeignTask = false
        }
    }

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        // The window token exists from here on. Centre the wallpaper at once:
        // the previous wallpaper target (the stock launcher, paged) may have
        // left it scrolled to one side, and the galaxy reports its own pan
        // only once the camera moves.
        reportWallpaperOffsets(0.5f, 0.5f)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        if (intent.hasCategory(Intent.CATEGORY_HOME) || intent.action == Intent.ACTION_MAIN) {
            runOnUiThread {
                lockSurface?.invokeAppsMethod("onHomePressed", null)
            }
        }
        // A warm hand-off from ShareReceiverActivity reuses this activity
        // (NEW_TASK | CLEAR_TOP | SINGLE_TOP), so the path arrives here.
        handleSharedPdfExtra(intent)
    }
    override fun onDestroy() {
        // Everything the shared surface acquired (sensors, the media session
        // callback, the apps channel handler) is released here.
        mainHandler.removeCallbacksAndMessages(null)
        unregisterWallpaperColorsListener()
        wallpaperExecutor.shutdown()
        lockSurface?.dispose()
        lockSurface = null
        // An open picker dies with the activity: answer as a cancel so the
        // Dart future resolves (it maps null to "no import").
        pendingPdfPickResult?.success(null)
        pendingPdfPickResult = null
        pdfExecutor.shutdown()
        shortcutExecutor.shutdown()
        screenReceiver?.let { unregisterReceiver(it) }
        packageReceiver?.let { unregisterReceiver(it) }
        super.onDestroy()
    }

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val surface = LockSurfaceChannels(
            this,
            flutterEngine.dartExecutor.binaryMessenger,
            lockSurfaceHost,
        )
        // Publish before configuring: a method can arrive as soon as the
        // handler is installed, and the extras reach back through lockSurface.
        lockSurface = surface
        surface.configure()
    }

    /**
     * The launcher-only channel methods. Everything the lock activity also
     * needs lives in [LockSurfaceChannels]; this is the remainder, kept on the
     * apps channel so Dart sees one method namespace.
     */
    private fun handleMainOnlyMethod(call: MethodCall, result: MethodChannel.Result): Boolean {
        when (call.method) {
            "getAppShortcuts" -> {
                val packageName = call.argument<String>("packageName")
                if (packageName.isNullOrBlank()) {
                    result.error("INVALID_ARGS", "packageName is required", null)
                } else {
                    fetchAppShortcuts(packageName, result)
                }
            }
            "startAppShortcut" -> {
                val packageName = call.argument<String>("packageName")
                val id = call.argument<String>("id")
                if (packageName.isNullOrBlank() || id.isNullOrBlank()) {
                    result.error("INVALID_ARGS", "packageName and id are required", null)
                } else {
                    result.success(
                        startAppShortcut(packageName, id, readSourceBounds(call)),
                    )
                }
            }
            "performHaptic" -> {
                performHaptic(call.argument<String>("type"))
                result.success(true)
            }
            "openAppInfo" -> {
                val packageName = call.argument<String>("packageName")
                if (packageName != null) {
                    openAppInfo(packageName)
                    result.success(true)
                } else {
                    result.error("INVALID_ARGS", "packageName is required", null)
                }
            }
            "startWebSearch" -> {
                val query = call.argument<String>("query")
                if (query.isNullOrBlank()) {
                    result.error("INVALID_ARGS", "query is required", null)
                } else {
                    result.success(startWebSearch(query))
                }
            }
            "openWebUrl" -> {
                val url = call.argument<String>("url")
                if (url.isNullOrBlank()) {
                    result.error("INVALID_ARGS", "url is required", null)
                } else {
                    result.success(openWebUrl(url))
                }
            }
            "getWebSearchHandlers" -> {
                result.success(describeWebSearchHandoff())
            }
            "uninstallApp" -> {
                val packageName = call.argument<String>("packageName")
                if (packageName != null) {
                    uninstallApplication(packageName)
                    result.success(true)
                } else {
                    result.error("INVALID_ARGS", "packageName is required", null)
                }
            }
            "isDefaultLauncher" -> {
                result.success(isDefaultLauncher())
            }
            "requestDefaultLauncher" -> {
                requestDefaultLauncher()
                result.success(true)
            }
            "openHomeSettings" -> {
                // ACTION_HOME_SETTINGS is not resolvable on every OEM build.
                // Fall back to the top-level Settings screen so the button
                // always does something, and report the real start result
                // rather than a blind success.
                val homeIntent = Intent(Settings.ACTION_HOME_SETTINGS)
                homeIntent.flags = Intent.FLAG_ACTIVITY_NEW_TASK
                var opened = lockSurface?.startActivityQuietly(homeIntent) ?: false
                if (!opened) {
                    val settingsIntent = Intent(Settings.ACTION_SETTINGS)
                    settingsIntent.flags = Intent.FLAG_ACTIVITY_NEW_TASK
                    opened = lockSurface?.startActivityQuietly(settingsIntent) ?: false
                }
                result.success(opened)
            }
            "isCosmicWallpaperActive" -> {
                result.success(isCosmicWallpaperActive())
            }
            "openCosmicLiveWallpaperPreview" -> {
                result.success(openCosmicLiveWallpaperPreview())
            }
            "getFilesDirPath" -> {
                result.success(applicationContext.filesDir.absolutePath)
            }
            "getExternalFilesDirPath" -> {
                // /sdcard/Android/data/<pkg>/files: writable by adb shell and
                // this app only, so it is the drop box for settings imports.
                result.success(applicationContext.getExternalFilesDir(null)?.absolutePath)
            }
            "requestMediaAccess" -> {
                // The standard system setting page: only the user can grant
                // notification access, and this is the one place the platform
                // lets them. Every external start goes through the handoff
                // marker so the launcher knows the screen is not its own while
                // the user is away.
                val intent = Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS)
                intent.flags = Intent.FLAG_ACTIVITY_NEW_TASK
                result.success(lockSurface?.startActivityQuietly(intent) ?: false)
            }
            "getWallpaperTone" -> {
                result.success(readWallpaperTone())
            }
            "setWallpaperOffsets" -> {
                val x = (call.argument<Number>("x") ?: 0.5f).toFloat()
                val y = (call.argument<Number>("y") ?: 0.5f).toFloat()
                reportWallpaperOffsets(x, y)
                result.success(true)
            }
            "setWindowBlur" -> {
                result.success(setWindowBackgroundBlur(call.argument<Boolean>("enabled") ?: false))
            }
            "hasOverlayAccess" -> {
                result.success(hasOverlayAccess())
            }
            "requestOverlayAccess" -> {
                requestOverlayAccess()
                result.success(true)
            }
            "isAccessibilityEnabled" -> {
                // The connected-instance check is the honest answer: the
                // service may be installed and still disabled, and a disabled
                // service must never look like it can perform anything.
                result.success(isAccessibilityEnabled())
            }
            "openAccessibilitySettings" -> {
                // The user owns this grant, so this is a quiet handoff to the
                // system page — never a request dialog inside the launcher.
                result.success(openAccessibilitySettings())
            }
            "performGlobalAction" -> {
                // Exactly three actions are reachable; everything else is a
                // plain false rather than an error, and a disconnected service
                // is false too.
                result.success(performAccessibilityGlobalAction(call.argument<String>("action")))
            }
            "takePendingSharedPdf" -> {
                // Pull, and clear so Dart owns the path from here: the same PDF
                // is never imported twice by a push and a pull.
                val path = pendingSharedPdfPath
                pendingSharedPdfPath = null
                result.success(path)
            }
            "extractPdfText" -> {
                val path = call.argument<String>("path")
                if (path.isNullOrBlank()) {
                    result.error("INVALID_ARGS", "path is required", null)
                } else {
                    extractPdfText(path, result)
                }
            }
            "pickPdf" -> {
                pickPdf(result)
            }
            else -> return false
        }
        return true
    }

    // --- App shortcuts ----------------------------------------------------------------

    /**
     * The launcher's public shortcut entry point.
     *
     * Every read is gated on the host permission the platform grants only the
     * default launcher; without it an empty list is the honest answer, so a
     * non-default install sees no shortcuts rather than a channel error. The
     * query itself (and its icon rasterisation) runs off the main thread because
     * it is real work and the dialog is opening on the frame it is called from.
     */
    private fun fetchAppShortcuts(packageName: String, result: MethodChannel.Result) {
        val apps = launcherApps()
        if (apps == null) {
            result.success(emptyList<Map<String, Any?>>())
            return
        }
        if (!apps.hasShortcutHostPermission()) {
            result.success(emptyList<Map<String, Any?>>())
            return
        }
        shortcutExecutor.execute {
            val shortcuts = try {
                queryAppShortcuts(apps, packageName)
            } catch (error: Exception) {
                android.util.Log.w(TAG, "CF_SHORTCUTS: query failed", error)
                emptyList()
            }
            runOnUiThread { result.success(shortcuts) }
        }
    }

    private fun launcherApps(): LauncherApps? =
        getSystemService(Context.LAUNCHER_APPS_SERVICE) as? LauncherApps

    /**
     * Resolves the package's dynamic, manifest and pinned shortcuts.
     *
     * Pinned shortcuts always survive; everything else is ordered by the app's
     * own rank and capped, so one app with dozens of shortcuts cannot flood the
     * action dialog. The icon is rendered at the display density into at most
     * [MAX_SHORTCUT_ICON_DP] dp so the channel payload stays small.
     */
    private fun queryAppShortcuts(
        apps: LauncherApps,
        packageName: String,
    ): List<Map<String, Any?>> {
        val query = LauncherApps.ShortcutQuery().apply {
            setPackage(packageName)
            setQueryFlags(
                LauncherApps.ShortcutQuery.FLAG_MATCH_DYNAMIC or
                    LauncherApps.ShortcutQuery.FLAG_MATCH_MANIFEST or
                    LauncherApps.ShortcutQuery.FLAG_MATCH_PINNED,
            )
        }
        val found = apps.getShortcuts(query, Process.myUserHandle()) ?: emptyList()
        val pinned = found.filter { it.isPinned }
        val ranked = found
            .filter { !it.isPinned }
            .sortedWith(compareBy({ it.rank }, { it.id }))
            .take(MAX_UNPINNED_SHORTCUTS)

        return (pinned + ranked).map { shortcutToMap(apps, it) }
    }

    private fun shortcutToMap(
        apps: LauncherApps,
        shortcut: ShortcutInfo,
    ): Map<String, Any?> {
        val iconPng = try {
            apps.getShortcutIconDrawable(shortcut, resources.displayMetrics.densityDpi)
                ?.let { drawableToIconPng(it) }
        } catch (error: Exception) {
            android.util.Log.d(TAG, "CF_SHORTCUTS: icon unavailable", error)
            null
        }
        return mapOf(
            "id" to shortcut.id,
            "packageName" to shortcut.`package`,
            "shortLabel" to (shortcut.shortLabel?.toString() ?: ""),
            "longLabel" to (shortcut.longLabel?.toString() ?: ""),
            "rank" to shortcut.rank,
            "isPinned" to shortcut.isPinned,
            "iconPng" to iconPng,
        )
    }

    /** Renders [drawable] as a square PNG no larger than 64 dp a side. */
    private fun drawableToIconPng(drawable: Drawable): ByteArray? {
        val edge = (MAX_SHORTCUT_ICON_DP * resources.displayMetrics.density)
            .toInt()
            .coerceIn(1, 512)
        return try {
            val bitmap = Bitmap.createBitmap(edge, edge, Bitmap.Config.ARGB_8888)
            try {
                val canvas = Canvas(bitmap)
                drawable.setBounds(0, 0, canvas.width, canvas.height)
                drawable.draw(canvas)
                val stream = ByteArrayOutputStream()
                bitmap.compress(Bitmap.CompressFormat.PNG, 100, stream)
                stream.toByteArray()
            } finally {
                bitmap.recycle()
            }
        } catch (error: Exception) {
            android.util.Log.d(TAG, "CF_SHORTCUTS: icon encode failed", error)
            null
        }
    }

    /**
     * Launches a shortcut, or reports false.
     *
     * The host permission is checked first, then the shortcut is resolved and
     * confirmed enabled, so a disabled or removed shortcut is a plain "no"
     * rather than a thrown `ActivityNotFoundException` inside the launcher.
     */
    private fun startAppShortcut(packageName: String, id: String, sourceBounds: Rect?): Boolean {
        val apps = launcherApps() ?: return false
        if (!apps.hasShortcutHostPermission()) return false

        val enabled = try {
            val query = LauncherApps.ShortcutQuery().apply {
                setPackage(packageName)
                setShortcutIds(listOf(id))
                setQueryFlags(
                    LauncherApps.ShortcutQuery.FLAG_MATCH_DYNAMIC or
                        LauncherApps.ShortcutQuery.FLAG_MATCH_MANIFEST or
                        LauncherApps.ShortcutQuery.FLAG_MATCH_PINNED,
                )
            }
            apps.getShortcuts(query, Process.myUserHandle())
                ?.firstOrNull { it.id == id }
                ?.isEnabled == true
        } catch (error: Exception) {
            false
        }
        if (!enabled) return false

        return try {
            markForeignTaskHandoff()
            apps.startShortcut(packageName, id, sourceBounds, null, Process.myUserHandle())
            true
        } catch (error: Exception) {
            android.util.Log.d(TAG, "CF_SHORTCUTS: start refused", error)
            // Nothing was handed anywhere, so the launcher still owns the screen.
            lockSurfaceHost.onForeignHandoffFailed()
            false
        }
    }

    /** Reads the optional physical-pixel `sourceBounds` a Dart tap sent. */
    private fun readSourceBounds(call: MethodCall): Rect? {
        @Suppress("UNCHECKED_CAST")
        val map = call.argument<Map<String, Any?>>("sourceBounds") ?: return null
        val left = (map["left"] as? Number)?.toInt() ?: return null
        val top = (map["top"] as? Number)?.toInt() ?: return null
        val right = (map["right"] as? Number)?.toInt() ?: return null
        val bottom = (map["bottom"] as? Number)?.toInt() ?: return null
        val rect = Rect(left, top, right, bottom)
        if (rect.width() <= 0 || rect.height() <= 0) return null
        return rect
    }

    // --- Haptics ----------------------------------------------------------------------

    private fun vibrator(): Vibrator? {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            (getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as? VibratorManager)
                ?.defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
        }
    }

    /**
     * Plays one of ChronoFold's named touch haptics.
     *
     * API 30+ gets a composed primitive when the device can play every primitive
     * the composition uses; otherwise the platform's predefined touch effects
     * (29+) or a short one-shot (26–28) stand in. From API 33 the request carries
     * [VibrationAttributes.USAGE_TOUCH] so the system's own Touch feedback
     * setting decides whether it plays; below 33 that setting is read directly
     * and a disabled switch silences the call.
     */
    private fun performHaptic(type: String?) {
        if (type == null) return
        val vibrator = vibrator()?.takeIf { it.hasVibrator() } ?: return

        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            val enabled = try {
                Settings.System.getInt(
                    contentResolver,
                    Settings.System.HAPTIC_FEEDBACK_ENABLED,
                    1,
                )
            } catch (error: Exception) {
                1
            }
            if (enabled == 0) return
        }

        try {
            val effect = vibrationEffectFor(vibrator, type) ?: return
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                vibrator.vibrate(
                    effect,
                    VibrationAttributes.createForUsage(VibrationAttributes.USAGE_TOUCH),
                )
            } else {
                @Suppress("DEPRECATION")
                vibrator.vibrate(effect, sonificationAttributes())
            }
        } catch (error: Exception) {
            android.util.Log.d(TAG, "CF_HAPTIC: vibration refused", error)
        }
    }

    private fun sonificationAttributes(): AudioAttributes =
        AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_ASSISTANCE_SONIFICATION)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .build()

    private fun vibrationEffectFor(vibrator: Vibrator, type: String): VibrationEffect? {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val supported = try {
                vibrator.areAllPrimitivesSupported(
                    VibrationEffect.Composition.PRIMITIVE_TICK,
                    VibrationEffect.Composition.PRIMITIVE_CLICK,
                    VibrationEffect.Composition.PRIMITIVE_LOW_TICK,
                    VibrationEffect.Composition.PRIMITIVE_THUD,
                    VibrationEffect.Composition.PRIMITIVE_SPIN,
                )
            } catch (error: Exception) {
                false
            }
            if (supported) {
                val primitive = when (type) {
                    "tick" -> VibrationEffect.Composition.PRIMITIVE_TICK
                    "click" -> VibrationEffect.Composition.PRIMITIVE_CLICK
                    "lowTick" -> VibrationEffect.Composition.PRIMITIVE_LOW_TICK
                    "heavyClick" -> VibrationEffect.Composition.PRIMITIVE_THUD
                    "confirm" -> VibrationEffect.Composition.PRIMITIVE_SPIN
                    "reject" -> VibrationEffect.Composition.PRIMITIVE_THUD
                    else -> return null
                }
                return VibrationEffect.startComposition()
                    .addPrimitive(primitive, 1.0f)
                    .compose()
            }
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val predefined = when (type) {
                "tick", "lowTick" -> VibrationEffect.EFFECT_TICK
                "click" -> VibrationEffect.EFFECT_CLICK
                "heavyClick" -> VibrationEffect.EFFECT_HEAVY_CLICK
                "confirm", "reject" -> VibrationEffect.EFFECT_DOUBLE_CLICK
                else -> return null
            }
            return VibrationEffect.createPredefined(predefined)
        }

        val durationMs = when (type) {
            "heavyClick", "confirm", "reject" -> 20L
            "tick", "click", "lowTick" -> 10L
            else -> return null
        }
        return VibrationEffect.createOneShot(durationMs, VibrationEffect.DEFAULT_AMPLITUDE)
    }

    // --- PDF import ------------------------------------------------------------------

    /**
     * Stores a shared/opened PDF path and forwards it to Dart.
     *
     * The extra is removed from the intent first so a re-delivery (a config
     * change reusing the same intent) cannot repeat the import. The path is
     * retained in [pendingSharedPdfPath] as well, because the push is
     * best-effort: on a cold start Dart may not have installed its handler yet,
     * and `takePendingSharedPdf` is how it collects the path then.
     */
    private fun handleSharedPdfExtra(source: Intent?) {
        val path = source?.getStringExtra(ShareReceiverActivity.EXTRA_SHARED_PDF_PATH)
            ?: return
        source.removeExtra(ShareReceiverActivity.EXTRA_SHARED_PDF_PATH)
        // This activity is exported, so the extra can come from any app. Only
        // a file inside our own imports cache (where ShareReceiverActivity
        // copies to) is ever handed to Dart.
        if (!isInsideImportsDir(path)) {
            android.util.Log.w(TAG, "CF_PDF: ignoring a shared PDF path outside the imports cache")
            return
        }
        pendingSharedPdfPath = path
        lockSurface?.invokeAppsMethod(
            "onSharedPdf",
            mapOf("path" to path),
            object : MethodChannel.Result {
                override fun success(result: Any?) {
                    // Dart's handler delivered it, so the startup pull must not
                    // import the same file a second time.
                    if (pendingSharedPdfPath == path) pendingSharedPdfPath = null
                }

                override fun error(code: String, message: String?, details: Any?) {
                    // Kept for the pull.
                }

                override fun notImplemented() {
                    // No Dart handler yet; kept for the pull.
                }
            },
        )
    }

    /** Whether [path] canonically resolves inside the private imports cache. */
    private fun isInsideImportsDir(path: String): Boolean {
        return try {
            val root = ShareReceiverActivity.importsDir(applicationContext).canonicalPath
            val candidate = File(path).canonicalPath
            candidate.startsWith(root + File.separator)
        } catch (error: Exception) {
            false
        }
    }

    /**
     * Extracts the text layer of the PDF at [path] off the main thread and
     * answers on it.
     *
     * The document is capped at [MAX_EXTRACT_PAGES] pages with position-sorted
     * text; [PDDocument.numberOfPages] still reports the true total so Dart can
     * say the result was truncated. An encrypted document reports
     * `PDF_ENCRYPTED`; every other failure reports `PDF_UNREADABLE`. There is
     * deliberately no OCR here: a PDF with no text layer comes back empty, not
     * unrecognized.
     */
    private fun extractPdfText(path: String, result: MethodChannel.Result) {
        pdfExecutor.execute {
            try {
                // Cheap hygiene before every parse: imports older than a day are
                // dropped, so the cache cannot grow without bound. The file just
                // copied is new and survives.
                ShareReceiverActivity.cleanupOldImports(applicationContext)
                val file = File(path)
                if (!file.exists()) {
                    runOnUiThread {
                        result.error("PDF_UNREADABLE", "The PDF file is missing", null)
                    }
                    return@execute
                }
                ensurePdfBoxInitialized()
                val document = try {
                    PDDocument.load(file)
                } catch (e: InvalidPasswordException) {
                    runOnUiThread {
                        result.error("PDF_ENCRYPTED", "The PDF is password protected", null)
                    }
                    return@execute
                } catch (e: Throwable) {
                    runOnUiThread {
                        result.error("PDF_UNREADABLE", e.message, null)
                    }
                    return@execute
                }
                try {
                    val totalPages = document.numberOfPages
                    val lastPage = minOf(totalPages, MAX_EXTRACT_PAGES)
                    val stripper = ColumnTextStripper().apply {
                        sortByPosition = true
                        startPage = 1
                        endPage = lastPage
                    }
                    val text = stripper.getText(document)
                    val payload = mapOf(
                        "text" to text,
                        "pageCount" to totalPages,
                        "truncated" to (totalPages > MAX_EXTRACT_PAGES),
                    )
                    runOnUiThread {
                        result.success(payload)
                    }
                } finally {
                    try {
                        document.close()
                    } catch (closeError: Throwable) {
                        android.util.Log.d(TAG, "CF_PDF: closing the document failed", closeError)
                    }
                }
            } catch (e: Throwable) {
                // Throwable, not Exception: a hostile or huge PDF can make
                // PDFBox throw OutOfMemoryError, which would otherwise kill the
                // HOME process and leave the Dart future unanswered.
                android.util.Log.w(TAG, "CF_PDF: text extraction failed", e)
                runOnUiThread {
                    result.error("PDF_UNREADABLE", e.message, null)
                }
            }
        }
    }

    /** Initializes PDFBox's asset-backed resources exactly once. */
    private fun ensurePdfBoxInitialized() {
        if (pdfBoxInitialized) return
        PDFBoxResourceLoader.init(applicationContext)
        pdfBoxInitialized = true
    }

    /**
     * Raises the system document picker for a single PDF and answers with the
     * cached path, or null when the user cancels.
     *
     * Only one pick may be in flight: a second request while the chooser is up
     * is refused rather than overwriting the first result.
     */
    private fun pickPdf(result: MethodChannel.Result) {
        if (pendingPdfPickResult != null) {
            result.error("PICK_IN_PROGRESS", "A PDF pick is already in progress", null)
            return
        }
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "application/pdf"
        }
        pendingPdfPickResult = result
        try {
            startActivityForResult(intent, REQUEST_PICK_PDF)
        } catch (e: Exception) {
            pendingPdfPickResult = null
            result.error("PDF_UNREADABLE", "No document picker is available", null)
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == REQUEST_PICK_PDF) {
            val pending = pendingPdfPickResult
            pendingPdfPickResult = null
            val uri = data?.data
            if (resultCode != RESULT_OK || uri == null) {
                // A cancel and a pick that returned nothing are both "null": no
                // path was produced, and Dart treats that as a cancelled import.
                pending?.success(null)
                return
            }
            // Reading a potentially large stream must not block the main thread.
            pdfExecutor.execute {
                ShareReceiverActivity.cleanupOldImports(applicationContext)
                var tooLarge = false
                val path = ShareReceiverActivity.copyToImports(applicationContext, uri) {
                    tooLarge = true
                }
                runOnUiThread {
                    if (path == null && tooLarge) {
                        // Distinct from a cancel, so Dart can say why.
                        pending?.error("PDF_TOO_LARGE", "The PDF is larger than 25 MB", null)
                    } else {
                        pending?.success(path)
                    }
                }
            }
            return
        }
        super.onActivityResult(requestCode, resultCode, data)
    }

    // --- Lock activity over a foreign task ---------------------------------------------

    /**
     * Whether this app may draw over other apps.
     *
     * That grant is the one exemption from Android's background-activity-launch
     * limits, so it decides whether the lock activity can be raised directly on
     * screen-off or needs a full-screen-intent notification instead.
     */
    private fun hasOverlayAccess(): Boolean = Settings.canDrawOverlays(this)

    private fun requestOverlayAccess() {
        val intent = Intent(
            Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
            Uri.parse("package:$packageName"),
        )
        intent.flags = Intent.FLAG_ACTIVITY_NEW_TASK
        lockSurface?.startActivityQuietly(intent)
    }

    // --- Accessibility service ----------------------------------------------------------

    /**
     * Whether ChronoFold's optional accessibility service is connected, which
     * is the only state in which its three global actions can run.
     *
     * Reads the service instance rather than the settings list on purpose: the
     * component can be enabled in Settings while the platform has not bound it
     * yet, and an unbound service cannot perform anything.
     */
    private fun isAccessibilityEnabled(): Boolean =
        ChronoFoldAccessibilityService.instance != null

    /**
     * Opens Android's accessibility settings so the user can enable the service.
     *
     * The platform owns this grant and only the user can give it, so this is a
     * quiet handoff, not a request dialog. Returns whether the screen could be
     * opened.
     */
    private fun openAccessibilitySettings(): Boolean {
        val intent = Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)
        intent.flags = Intent.FLAG_ACTIVITY_NEW_TASK
        return lockSurface?.startActivityQuietly(intent) ?: false
    }

    /**
     * Performs exactly one of `notifications`, `lockScreen` or `recents`.
     *
     * Anything else — and every call while the service is not connected — is a
     * plain false. The whitelist lives in [ChronoFoldAccessibilityService]; this
     * only resolves the connected instance and never throws.
     */
    private fun performAccessibilityGlobalAction(action: String?): Boolean {
        val service = ChronoFoldAccessibilityService.instance ?: return false
        return try {
            service.performGlobal(action)
        } catch (error: Exception) {
            android.util.Log.d(TAG, "CF_A11Y: global action refused", error)
            false
        }
    }

    /**
     * Raises [LockActivity] over the foreign task that owns the screen.
     *
     * A screen-off broadcast is a background start, which Android may block. If
     * the overlay grant is held, the direct start is exempt and is used. Without
     * it the direct start is still attempted first (harmless), and a
     * full-screen-intent notification on the high-importance `lock_surface`
     * channel is posted alongside — the mechanism shipping third-party lock
     * screens use.
     */
    private fun raiseLockActivityOverForeignTask() {
        val intent = Intent(this, LockActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK
        }

        if (Settings.canDrawOverlays(this)) {
            val started = try {
                startActivity(intent)
                true
            } catch (error: Exception) {
                android.util.Log.w("ChronoFold", "CF_LOCK: direct lock start failed", error)
                false
            }
            val directSuffix = if (started) "" else " (failed)"
            android.util.Log.d(
                "ChronoFold",
                "CF_LOCK: lock activity start path=direct$directSuffix",
            )
            return
        }

        val directStarted = try {
            startActivity(intent)
            true
        } catch (error: Exception) {
            false
        }
        postLockSurfaceNotification(intent)
        val suffix = if (directStarted) " (direct also accepted)" else ""
        android.util.Log.d(
            "ChronoFold",
            "CF_LOCK: lock activity start path=fsi$suffix",
        )
    }

    @Suppress("DEPRECATION")
    private fun postLockSurfaceNotification(intent: Intent) {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
            ?: return
        // From API 34 the full-screen-intent grant is user-revocable. Without
        // it the platform silently downgrades the prompt to a heads-up
        // notification, which is noise rather than a lock surface; the direct
        // start already attempted by the caller is the only path left.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE &&
            !manager.canUseFullScreenIntent()
        ) {
            android.util.Log.w(
                "ChronoFold",
                "CF_LOCK: full-screen intent not permitted; not posting lock prompt",
            )
            return
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                LockSurfaceChannels.LOCK_SURFACE_CHANNEL_ID,
                "Lock screen",
                NotificationManager.IMPORTANCE_HIGH,
            ).apply {
                description = "Shows ChronoFold's lock surface over the running app."
                setSound(null, null)
                enableVibration(false)
            }
            manager.createNotificationChannel(channel)
        }

        val pendingIntent = PendingIntent.getActivity(
            this,
            LockSurfaceChannels.LOCK_SURFACE_NOTIFICATION_ID,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, LockSurfaceChannels.LOCK_SURFACE_CHANNEL_ID)
        } else {
            Notification.Builder(this)
        }

        val notification = builder
            .setSmallIcon(R.mipmap.ic_launcher)
            .setCategory(Notification.CATEGORY_SYSTEM)
            .setContentTitle("Lock screen")
            .setContentText("ChronoFold lock screen")
            .setFullScreenIntent(pendingIntent, true)
            .setOngoing(false)
            .setAutoCancel(true)
            .setTimeoutAfter(10_000L)
            .build()
        // Silent and vibration-free: this is a surface switch, not an alert.
        notification.sound = null
        notification.defaults = 0
        notification.vibrate = null

        manager.notify(LockSurfaceChannels.LOCK_SURFACE_NOTIFICATION_ID, notification)
    }
    /**
     * Opens Android's live-wallpaper chooser for the ambient layer.
     *
     * ColorOS renders a lock-screen-shaped surface for the direct preview
     * intent, which users can mistake for a ChronoFold keyguard. The chooser
     * keeps the OEM step explicit: the user selects "ChronoFold Ambient
     * Galaxy" there, then confirms its normal system preview/apply flow.
     */
    /**
     * Whether ChronoFold's galaxy is the system live wallpaper.
     *
     * With gesture navigation, ColorOS's own recents runs the close-app
     * animation and starts HOME only when it ends, so until then the system
     * wallpaper is the only thing behind the shrinking app. The launcher
     * cannot draw there; being that wallpaper is the only way the transition
     * shows the galaxy rather than the ColorOS background. Public API, no
     * permission: `getWallpaperInfo` describes a live wallpaper or is null.
     */
    private fun isCosmicWallpaperActive(): Boolean = try {
        android.app.WallpaperManager.getInstance(this).wallpaperInfo?.component ==
            android.content.ComponentName(this, CosmicLiveWallpaperService::class.java)
    } catch (exception: Exception) {
        android.util.Log.w("ChronoFold", "Unable to read the live wallpaper", exception)
        false
    }

    private fun openCosmicLiveWallpaperPreview(): Boolean {
        val chooserIntent = Intent(android.app.WallpaperManager.ACTION_LIVE_WALLPAPER_CHOOSER)

        return try {
            if (chooserIntent.resolveActivity(packageManager) == null) {
                false
            } else {
                markForeignTaskHandoff()
                startActivity(chooserIntent)
                true
            }
        } catch (exception: Exception) {
            android.util.Log.w(
                "ChronoFold",
                "Unable to open the cosmic live wallpaper chooser",
                exception,
            )
            lockSurfaceHost.onForeignHandoffFailed()
            false
        }
    }
    // --- Wallpaper -------------------------------------------------------------------

    /**
     * The system wallpaper's colour hints, or null when the platform cannot
     * say.
     *
     * `supportsDarkText` is the platform's own verdict that the wallpaper is
     * light enough for dark foreground content; it is what the status and
     * navigation bar icons and the home scrims follow. On API 31+ it comes
     * straight from [android.app.WallpaperColors.getColorHints]; below that
     * the hints are not public, so the primary colour's luminance stands in.
     */
    private fun readWallpaperTone(): Map<String, Any?>? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O_MR1) return null
        return try {
            val colors = WallpaperManager.getInstance(this)
                .getWallpaperColors(WallpaperManager.FLAG_SYSTEM) ?: return null
            val primary = colors.primaryColor.toArgb()
            val supportsDarkText: Boolean
            val supportsDarkTheme: Boolean
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val hints = colors.colorHints
                supportsDarkText =
                    (hints and android.app.WallpaperColors.HINT_SUPPORTS_DARK_TEXT) != 0
                supportsDarkTheme =
                    (hints and android.app.WallpaperColors.HINT_SUPPORTS_DARK_THEME) != 0
            } else {
                val luminance = colors.primaryColor.luminance()
                supportsDarkText = luminance > 0.5f
                supportsDarkTheme = luminance < 0.25f
            }
            mapOf(
                "primary" to primary,
                "secondary" to colors.secondaryColor?.toArgb(),
                "tertiary" to colors.tertiaryColor?.toArgb(),
                "supportsDarkText" to supportsDarkText,
                "supportsDarkTheme" to supportsDarkTheme,
            )
        } catch (error: Exception) {
            android.util.Log.w(TAG, "CF_WALLPAPER: colours unavailable", error)
            null
        }
    }

    private fun registerWallpaperColorsListener() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O_MR1) return
        if (wallpaperColorsListener != null) return
        val listener = WallpaperManager.OnColorsChangedListener { _, which ->
            if (which and WallpaperManager.FLAG_SYSTEM == 0) return@OnColorsChangedListener
            lockSurface?.invokeAppsMethod("onWallpaperToneChanged", readWallpaperTone())
        }
        try {
            WallpaperManager.getInstance(this).addOnColorsChangedListener(listener, mainHandler)
            wallpaperColorsListener = listener
        } catch (error: Exception) {
            android.util.Log.w(TAG, "CF_WALLPAPER: colour listener refused", error)
        }
    }

    private fun unregisterWallpaperColorsListener() {
        val listener = wallpaperColorsListener ?: return
        wallpaperColorsListener = null
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O_MR1) return
        try {
            WallpaperManager.getInstance(this).removeOnColorsChangedListener(listener)
        } catch (error: Exception) {
            android.util.Log.w(TAG, "CF_WALLPAPER: colour listener removal failed", error)
        }
    }

    /**
     * Tells WindowManager where the launcher is scrolled to, in wallpaper
     * fractions (0..1 each axis), so the system wallpaper pans with the galaxy
     * the way it pans with the stock launcher's pages. Coalesced: a burst of
     * reports during a fling collapses to the newest pair.
     */
    private fun reportWallpaperOffsets(x: Float, y: Float) {
        pendingWallpaperX = x.coerceIn(0f, 1f)
        pendingWallpaperY = y.coerceIn(0f, 1f)
        if (wallpaperReportQueued) return
        wallpaperReportQueued = true
        val token = window?.decorView?.windowToken
        if (token == null) {
            wallpaperReportQueued = false
            return
        }
        try {
            wallpaperExecutor.execute {
                wallpaperReportQueued = false
                val px = pendingWallpaperX
                val py = pendingWallpaperY
                if (px.isNaN() || py.isNaN()) return@execute
                try {
                    WallpaperManager.getInstance(this).setWallpaperOffsets(token, px, py)
                } catch (error: Exception) {
                    android.util.Log.d(TAG, "CF_WALLPAPER: offsets refused", error)
                }
            }
        } catch (error: java.util.concurrent.RejectedExecutionException) {
            // The activity is being destroyed; there is nothing to scroll.
            wallpaperReportQueued = false
        }
    }

    /**
     * Blurs the wallpaper behind the launcher window while a full-screen
     * surface (search, the comet, shopping) is up, the way ColorOS blurs it
     * behind its own drawer. Window background blur exists from API 31 and is
     * a device capability, so this reports whether it actually took effect.
     */
    private fun setWindowBackgroundBlur(enabled: Boolean): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return false
        val manager = getSystemService(Context.WINDOW_SERVICE) as? WindowManager ?: return false
        return try {
            if (enabled && !manager.isCrossWindowBlurEnabled) {
                false
            } else {
                val radiusPx = if (enabled) {
                    (WINDOW_BLUR_DP * resources.displayMetrics.density).toInt()
                } else {
                    0
                }
                window.setBackgroundBlurRadius(radiusPx)
                enabled
            }
        } catch (error: Exception) {
            android.util.Log.d(TAG, "CF_WALLPAPER: window blur refused", error)
            false
        }
    }

    private fun openAppInfo(packageName: String) {
        val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
            data = Uri.fromParts("package", packageName, null)
            flags = Intent.FLAG_ACTIVITY_NEW_TASK
        }
        lockSurface?.startActivityQuietly(intent)
    }

    private fun uninstallApplication(packageName: String) {
        val intent = Intent(Intent.ACTION_DELETE).apply {
            data = Uri.fromParts("package", packageName, null)
            flags = Intent.FLAG_ACTIVITY_NEW_TASK
        }
        lockSurface?.startActivityQuietly(intent)
    }

    private fun isDefaultLauncher(): Boolean {
        val intent = Intent(Intent.ACTION_MAIN).apply {
            addCategory(Intent.CATEGORY_HOME)
        }
        val resolveInfo = packageManager.resolveActivity(intent, PackageManager.MATCH_DEFAULT_ONLY)
        return resolveInfo?.activityInfo?.packageName == packageName
    }

    private fun requestDefaultLauncher() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val roleManager = getSystemService(RoleManager::class.java)
            if (roleManager != null && roleManager.isRoleAvailable(RoleManager.ROLE_HOME) && !roleManager.isRoleHeld(RoleManager.ROLE_HOME)) {
                val intent = roleManager.createRequestRoleIntent(RoleManager.ROLE_HOME)
                intent.flags = Intent.FLAG_ACTIVITY_NEW_TASK
                lockSurface?.startActivityQuietly(intent)
                return
            }
        }
        val intent = Intent(Settings.ACTION_HOME_SETTINGS).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK
        }
        lockSurface?.startActivityQuietly(intent)
    }
    /**
     * Allows or forbids MainActivity being drawn over the keyguard.
     *
     * Deliberately NOT paired with `setTurnScreenOn`, which it used to be.
     * `turnScreenOn` asks the platform to wake the display whenever this
     * activity comes to the front, and the flag was asserted at the exact moment
     * the screen went off — so the launcher could wake the device by itself and
     * land on a keyguard with its fingerprint affordance lit, which is what
     * "it asks for the fingerprint out of the blue" looks like from the outside.
     *
     * Occluding the keyguard needs no such power: the user has already woken the
     * device by the time the cosmic panel is meant to be visible. The flag is
     * cleared on both paths so an install that had it asserted loses it.
     */
    private fun setOverlayWhenLocked(enabled: Boolean) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(enabled)
            setTurnScreenOn(false)
        } else {
            @Suppress("DEPRECATION")
            if (enabled) {
                window.addFlags(WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED)
                window.clearFlags(WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON)
            } else {
                window.clearFlags(
                    WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                    WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
                )
            }
        }
    }
    /**
     * Opens a URL in the user's chosen browser.
     *
     * A bare ACTION_VIEW with an https URL is the correct mechanism: the
     * platform already routes it to the BROWSER role holder, so the launch is
     * silent and follows the user's preference. Verified on ColorOS 16
     * (CPH2765): resolves to a single activity (Brave), not a chooser.
     *
     * Note deliberately NOT used here: RoleManager.getRoleHolders, which is
     * platform-internal. The only public query is isRoleHeld, which answers
     * whether THIS app holds the role and so cannot identify the browser.
     * There is no public API to read the browser role holder's package.
     */
    private fun openWebUrl(url: String): Boolean {
        return try {
            val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url)).apply {
                addCategory(Intent.CATEGORY_BROWSABLE)
                flags = Intent.FLAG_ACTIVITY_NEW_TASK
            }
            markForeignTaskHandoff()
            startActivity(intent)
            true
        } catch (e: Exception) {
            // An unhandled URL throws ActivityNotFoundException. Returning false
            // lets the surface report it rather than crashing the launcher.
            lockSurfaceHost.onForeignHandoffFailed()
            false
        }
    }

    /**
     * Hands a raw query to the platform's web search handler.
     *
     * ACTION_WEB_SEARCH is an Activity action whose documented output is
     * "nothing" — it cannot return results. On the tested ColorOS 16 build it
     * resolves to the system chooser (seven handlers, no default), so callers
     * should label this action as a handoff rather than an inline answer.
     */
    private fun startWebSearch(query: String): Boolean {
        return try {
            val intent = Intent(Intent.ACTION_WEB_SEARCH).apply {
                putExtra(SearchManager.QUERY, query)
                flags = Intent.FLAG_ACTIVITY_NEW_TASK
            }
            markForeignTaskHandoff()
            startActivity(intent)
            true
        } catch (e: Exception) {
            lockSurfaceHost.onForeignHandoffFailed()
            false
        }
    }

    /**
     * Reports how ACTION_WEB_SEARCH would resolve, so the UI can label the
     * handoff honestly instead of promising a silent launch it cannot deliver.
     */
    private fun describeWebSearchHandoff(): Map<String, Any?> {
        val intent = Intent(Intent.ACTION_WEB_SEARCH)
        val handlers = packageManager
            .queryIntentActivities(intent, PackageManager.MATCH_DEFAULT_ONLY)
            .map { it.activityInfo.packageName }
            .distinct()

        // resolveActivity returns the platform's internal ResolverActivity when
        // no default exists, which is exactly the "a chooser will appear"
        // signal. On ColorOS 16 (CPH2765) this is the case: 7 handlers, no
        // default, package "android".
        val resolved = intent.resolveActivity(packageManager)
        val raisesChooser = resolved == null || resolved.packageName == "android"

        // Whether this app itself holds the browser role. Not the browser's
        // identity — that is not publicly readable — but useful for diagnostics.
        val holdsBrowserRole = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            (getSystemService(Context.ROLE_SERVICE) as? RoleManager)
                ?.isRoleHeld(RoleManager.ROLE_BROWSER) ?: false
        } else {
            false
        }

        return mapOf(
            "handlers" to handlers,
            "handlerCount" to handlers.size,
            "resolvedPackage" to resolved?.packageName,
            "raisesChooser" to raisesChooser,
            "holdsBrowserRole" to holdsBrowserRole,
        )
    }
}
