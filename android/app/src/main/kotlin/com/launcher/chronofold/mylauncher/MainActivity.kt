package com.launcher.chronofold.mylauncher

import android.content.Context
import android.content.ComponentName
import android.content.Intent
import android.app.SearchManager
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.content.pm.ResolveInfo
import android.graphics.Bitmap
import android.graphics.Canvas
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
import android.provider.Settings
import android.content.BroadcastReceiver
import android.content.IntentFilter
import android.os.Bundle
import android.view.WindowManager
import android.app.KeyguardManager
import android.app.role.RoleManager
import android.hardware.biometrics.BiometricPrompt
import android.hardware.fingerprint.FingerprintManager
import android.os.CancellationSignal
import android.os.PowerManager
import android.provider.MediaStore
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.util.concurrent.Executors

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
class MainActivity : FlutterActivity() {
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
     * An opaque native cover surface held above Flutter while a foreign task is
     * foregrounded. Keeping this in the launcher task prevents ColorOS from
     * exposing its own task/background frame on the way back.
     */
    private var returnBridge: android.view.View? = null
    private var returnBridgeAwaitingReturn = false
    private var returnBridgeLeftForTarget = false
    private var returnBridgeGeneration = 0

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

        override fun startTarget(intent: Intent, onStarted: (Boolean) -> Unit) {
            startTargetWithReturnBridge(intent, onStarted)
        }

        override fun onUnhandledMethod(call: MethodCall, result: MethodChannel.Result): Boolean =
            handleMainOnlyMethod(call, result)
    }
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.setBackgroundDrawable(android.graphics.drawable.ColorDrawable(android.graphics.Color.parseColor("#050A16")))
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
    }
    override fun onPause() {
        launcherResumed = false
        // This is set only after the target activity has been accepted for
        // launch, so transient keyguard UI cannot be mistaken for a return.
        if (returnBridgeAwaitingReturn) {
            returnBridgeLeftForTarget = true
        }
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
        if (!returnBridgeAwaitingReturn || !returnBridgeLeftForTarget) return

        // Keep the native bridge visible until Flutter has painted a fresh
        // launcher frame. The timeout is a fail-safe for an engine failure,
        // never the normal return path.
        val bridge = returnBridge ?: return
        bridge.bringToFront()
        val generation = returnBridgeGeneration
        bridge.postDelayed({
            if (generation == returnBridgeGeneration &&
                returnBridgeAwaitingReturn &&
                returnBridgeLeftForTarget) {
                hideReturnBridge()
            }
        }, 900L)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        if (intent.hasCategory(Intent.CATEGORY_HOME) || intent.action == Intent.ACTION_MAIN) {
            runOnUiThread {
                lockSurface?.invokeAppsMethod("onHomePressed", null)
            }
        }
    }
    override fun onDestroy() {
        // Everything the shared surface acquired (sensors, the media session
        // callback, the apps channel handler) is released here.
        lockSurface?.dispose()
        lockSurface = null
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
                val intent = Intent(Settings.ACTION_HOME_SETTINGS)
                intent.flags = Intent.FLAG_ACTIVITY_NEW_TASK
                lockSurface?.startActivityQuietly(intent)
                result.success(true)
            }
            "openCosmicLiveWallpaperPreview" -> {
                result.success(openCosmicLiveWallpaperPreview())
            }
            "getFilesDirPath" -> {
                result.success(applicationContext.filesDir.absolutePath)
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
            "launcherFrameReady" -> {
                runOnUiThread {
                    // An initial Flutter frame (or one sent before MainActivity
                    // actually paused) must not dismiss the bridge while a
                    // target is still opening.
                    if (returnBridgeAwaitingReturn && returnBridgeLeftForTarget) {
                        hideReturnBridge()
                    }
                    result.success(true)
                }
            }
            "hasOverlayAccess" -> {
                result.success(hasOverlayAccess())
            }
            "requestOverlayAccess" -> {
                requestOverlayAccess()
                result.success(true)
            }
            else -> return false
        }
        return true
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
            false
        }
    }
    /**
     * Makes the last launcher buffer a native cover-like surface before a
     * foreign task begins. It stays above Flutter during the round trip and is
     * removed only after Dart confirms its replacement frame is painted.
     */
    private fun showReturnBridge() {
        val bridge = returnBridge ?: android.view.View(this).apply {
            setBackgroundResource(R.drawable.return_cover_bridge)
            importantForAccessibility = android.view.View.IMPORTANT_FOR_ACCESSIBILITY_NO
            // Do not allow an unseen Flutter surface to receive a tap while
            // this noninteractive transition surface is visible.
            isClickable = true
            isFocusable = true
        }.also { view ->
            addContentView(
                view,
                android.view.ViewGroup.LayoutParams(
                    android.view.ViewGroup.LayoutParams.MATCH_PARENT,
                    android.view.ViewGroup.LayoutParams.MATCH_PARENT,
                ),
            )
            returnBridge = view
        }

        returnBridgeGeneration += 1
        returnBridgeAwaitingReturn = true
        returnBridgeLeftForTarget = false
        bridge.animate().cancel()
        bridge.alpha = 1f
        bridge.visibility = android.view.View.VISIBLE
        bridge.bringToFront()
        bridge.invalidate()
    }

    private fun hideReturnBridge() {
        val bridge = returnBridge ?: return
        returnBridgeAwaitingReturn = false
        returnBridgeLeftForTarget = false
        returnBridgeGeneration += 1
        bridge.animate().cancel()
        bridge.animate()
            .alpha(0f)
            .setDuration(120L)
            .withEndAction {
                if (!returnBridgeAwaitingReturn) {
                    bridge.visibility = android.view.View.GONE
                }
            }
            .start()
    }

    private fun startTargetWithReturnBridge(
        intent: Intent,
        onStarted: (Boolean) -> Unit,
    ) {
        showReturnBridge()
        val bridge = returnBridge
        if (bridge == null) {
            onStarted(lockSurface?.startActivityQuietly(intent) ?: false)
            return
        }

        // Allow one compositor beat for the native bridge to become the
        // launcher task's visible buffer before the target task takes over.
        bridge.postDelayed({
            val started = lockSurface?.startActivityQuietly(intent) ?: false
            if (!started) {
                hideReturnBridge()
            }
            onStarted(started)
        }, 16L)
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
