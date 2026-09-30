package com.launcher.chronofold.mylauncher

import android.app.Activity
import android.app.KeyguardManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.content.pm.ResolveInfo
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.Drawable
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.hardware.biometrics.BiometricPrompt
import android.hardware.fingerprint.FingerprintManager
import android.media.MediaMetadata
import android.media.session.MediaController
import android.media.session.MediaSessionManager
import android.media.session.PlaybackState
import android.os.Build
import android.os.CancellationSignal
import android.os.PowerManager
import android.provider.MediaStore
import android.provider.Settings
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.util.concurrent.Executors

/**
 * The platform-channel surface shared by the two activities that can show the
 * cosmic lock screen: [MainActivity] (the launcher, for a screen-off while the
 * launcher itself is on top) and [LockActivity] (raised over a foreign task).
 *
 * The two activities need the same apps/fingerprint/media/hinge/shake channels
 * but differ in a few decisions — who is "foreground", what a launch target
 * does, and whether finishing is allowed. Those differences live in [Host];
 * everything else is implemented once here so the two surfaces cannot drift.
 *
 * [MainActivity] keeps its own methods for the launcher-only surfaces
 * (search, uninstall, the return bridge, live wallpaper) and reaches them
 * through [Host.onUnhandledMethod].
 */
class LockSurfaceChannels(
    private val activity: Activity,
    private val messenger: BinaryMessenger,
    private val host: Host,
) {
    /**
     * What differs between the launcher and the lock activity.
     *
     * Deliberately small: anything both activities do identically belongs in
     * this class, not in the host.
     */
    interface Host {
        /** Whether this activity is genuinely the visible surface. */
        fun isForeground(): Boolean

        /** The launcher is about to background itself into another app. */
        fun onForeignHandoff()

        /** A start was attempted but nothing was handed anywhere. */
        fun onForeignHandoffFailed()

        /** The lock activity should leave the screen; a no-op on the launcher. */
        fun onFinishLock()

        /** Show or stop drawing this activity over the keyguard. */
        fun setOverlayWhenLocked(enabled: Boolean)

        /** Start an already-built intent once the keyguard is out of the way. */
        fun startTarget(intent: Intent, onStarted: (Boolean) -> Unit)

        /**
         * Handle a method this shared surface does not own. Return true when
         * the host served it; false falls through to `notImplemented`.
         */
        fun onUnhandledMethod(call: MethodCall, result: MethodChannel.Result): Boolean
    }

    companion object {
        const val APPS_CHANNEL = "com.launcher.chronofold/apps"
        const val HINGE_CHANNEL = "com.launcher.chronofold/hinge"
        const val SHAKE_CHANNEL = "com.launcher.chronofold/shake"
        const val FINGERPRINT_CHANNEL = "com.launcher.chronofold/fingerprint"
        const val MEDIA_CHANNEL = "com.launcher.chronofold/media"

        /** High-importance channel the full-screen-intent lock prompt uses. */
        const val LOCK_SURFACE_CHANNEL_ID = "lock_surface"

        /** Fixed id so [LockActivity] can cancel the prompt that raised it. */
        const val LOCK_SURFACE_NOTIFICATION_ID = 0x10C4

        /** Edge length of the launcher icons sent to Dart. */
        private const val ICON_PIXELS = 96

        /** Longest edge album art is scaled to before it is sent to Dart. */
        private const val MEDIA_ART_MAX_PIXELS = 256

        /**
         * The Material You tones, in the order [accentTones] reads its resource
         * ids. Shared so the tone list and the keys can never diverge.
         */
        private val SYSTEM_TONES = intArrayOf(
            0, 10, 50, 100, 200, 300, 400, 500, 600, 700, 800, 900, 1000,
        )
    }

    private val appsMethodChannel = MethodChannel(messenger, APPS_CHANNEL)

    private val backgroundExecutor = Executors.newSingleThreadExecutor()
    private var sensorManager: SensorManager? = null
    private var hingeSensor: Sensor? = null
    private var accelSensor: Sensor? = null
    private var fingerprintCancellation: CancellationSignal? = null
    private var fingerprintEvents: EventChannel.EventSink? = null
    private var powerManager: PowerManager? = null

    /**
     * Native media state for the lock screen's now-playing card.
     *
     * The card exists only while notification access is granted, because
     * `MediaSessionManager.getActiveSessions` refuses to answer otherwise. Every
     * call that touches the manager is therefore gated on
     * [hasMediaListenerAccess] and wrapped against `SecurityException`, so a
     * revoked grant degrades to "no media" rather than a crash.
     */
    private var mediaEvents: EventChannel.EventSink? = null
    private var mediaSessionManager: MediaSessionManager? = null
    private var activeSessionsListener: MediaSessionManager.OnActiveSessionsChangedListener? = null
    private var primaryController: MediaController? = null
    private var primaryControllerCallback: MediaController.Callback? = null

    /**
     * Signature of the last payload sent, so position ticks do not cross the
     * channel. Only metadata and transport-state changes reset it.
     */
    private var lastMediaSignature: String? = null

    /**
     * Signature of the last system palette pushed to Dart, so an `onResume`
     * that changed nothing (the common case) does not cross the channel.
     *
     * Only a map that was actually read is stored; a below-31/null read leaves
     * this untouched so the first real palette still counts as a change.
     */
    private var lastSystemPalette: Map<String, Any?>? = null

    /** The listener [MediaListenerService] holds, so [dispose] can remove it. */
    private val mediaListenerCallback: () -> Unit = {
        activity.runOnUiThread { onMediaListenerStateChanged() }
    }

    /** Registers every channel this surface owns. */
    fun configure() {
        sensorManager = activity.getSystemService(Context.SENSOR_SERVICE) as? SensorManager
        powerManager = activity.getSystemService(Context.POWER_SERVICE) as? PowerManager
        // TYPE_HINGE_ANGLE is 36
        hingeSensor = sensorManager?.getDefaultSensor(36)

        appsMethodChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "getInstalledApps" -> {
                    val includeIcons = call.argument<Boolean>("includeIcons") ?: true
                    backgroundExecutor.execute {
                        try {
                            val apps = fetchInstalledApps(includeIcons)
                            activity.runOnUiThread {
                                result.success(apps)
                            }
                        } catch (e: Exception) {
                            activity.runOnUiThread {
                                result.error("SCAN_ERROR", e.message, null)
                            }
                        }
                    }
                }
                "launchApp" -> {
                    val packageName = call.argument<String>("packageName")
                    val activityName = call.argument<String>("activityName")
                    if (packageName != null) {
                        // Resolved only once the keyguard is dismissed and the
                        // activity is started, reporting success back to Flutter.
                        launchApplication(packageName, activityName) { success ->
                            result.success(success)
                        }
                    } else {
                        result.error("INVALID_ARGS", "packageName is required", null)
                    }
                }
                "openQuickShortcut" -> {
                    result.success(openQuickShortcut(call.argument<String>("shortcut")))
                }
                "isKeyguardLocked" -> {
                    val keyguard = activity.getSystemService(Context.KEYGUARD_SERVICE) as? KeyguardManager
                    result.success(keyguard?.isKeyguardLocked == true || keyguard?.isDeviceLocked == true)
                }
                "isDeviceSecure" -> {
                    val keyguard = activity.getSystemService(Context.KEYGUARD_SERVICE) as? KeyguardManager
                    result.success(keyguard?.isDeviceSecure == true)
                }
                "getBatteryState" -> {
                    result.success(getBatteryState())
                }
                "getSystemPalette" -> {
                    // Null on API < 31 and on any read failure: Dart then keeps
                    // its own aqua accent instead of guessing a Material tone.
                    result.success(readSystemPalette())
                }
                "dismissKeyguard" -> {
                    requestKeyguardDismissal { success ->
                        activity.runOnUiThread {
                            // On the lock activity a successful dismissal means
                            // the lock surface has done its job: leave so the
                            // user lands on the app underneath. The launcher
                            // keeps its panel until Dart clears it.
                            if (success) host.onFinishLock()
                            result.success(success)
                        }
                    }
                }
                "setLockScreenOverlayEnabled" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: false
                    activity.runOnUiThread {
                        host.setOverlayWhenLocked(enabled)
                        result.success(true)
                    }
                }
                "hasMediaAccess" -> {
                    // Whether OUR component is in the platform's enabled
                    // notification-listener list. Reading this instead of the
                    // listener instance means the answer is honest even before
                    // the service has been rebound.
                    result.success(hasMediaListenerAccess())
                }
                "mediaCommand" -> {
                    result.success(handleMediaCommand(call.argument<String>("command")))
                }
                "finishLock" -> {
                    activity.runOnUiThread {
                        host.onFinishLock()
                        result.success(true)
                    }
                }
                "authenticate" -> {
                    val appName = call.argument<String>("appName")
                    authenticateUser(appName) { success, error ->
                        activity.runOnUiThread {
                            if (success) {
                                result.success(true)
                            } else {
                                result.error("AUTH_FAILED", error ?: "Authentication failed", null)
                            }
                        }
                    }
                }
                "fingerprintCapability" -> {
                    result.success(fingerprintCapability())
                }
                "startFingerprintScan" -> {
                    // The honest answer travels in the return value: Dart's
                    // armed state is "a scan was started and no terminal event
                    // has arrived", so a refusal must not read as a session.
                    result.success(startFingerprintScan())
                }
                "stopFingerprintScan" -> {
                    stopFingerprintScan()
                    result.success(true)
                }
                else -> {
                    if (!host.onUnhandledMethod(call, result)) {
                        result.notImplemented()
                    }
                }
            }
        }

        // EventChannel for Hinge Angle Sensor
        EventChannel(messenger, HINGE_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                private var listener: SensorEventListener? = null

                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    if (hingeSensor == null || sensorManager == null) {
                        return
                    }
                    listener = object : SensorEventListener {
                        override fun onSensorChanged(event: SensorEvent?) {
                            if (event != null && event.values.isNotEmpty()) {
                                val angle = event.values[0]
                                events?.success(angle.toDouble())
                            }
                        }

                        override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}
                    }
                    sensorManager?.registerListener(
                        listener,
                        hingeSensor,
                        SensorManager.SENSOR_DELAY_UI
                    )
                }

                override fun onCancel(arguments: Any?) {
                    listener?.let { sensorManager?.unregisterListener(it) }
                    listener = null
                }
            })

        // EventChannel for silent fingerprint scanning. Unlike BiometricPrompt,
        // the legacy FingerprintManager renders no system UI: the app owns the
        // affordance, so touching the sensor authenticates directly.
        EventChannel(messenger, FINGERPRINT_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    fingerprintEvents = events
                }

                override fun onCancel(arguments: Any?) {
                    fingerprintEvents = null
                    stopFingerprintScan()
                }
            })

        // The now-playing session for the lock screen, or null when there is
        // none. Registered here rather than in onCreate because the listener
        // service may connect before or after the engine exists; the companion
        // callback re-resolves sessions on either order.
        MediaListenerService.addSessionsMayHaveChangedListener(mediaListenerCallback)
        onMediaListenerStateChanged()

        EventChannel(messenger, MEDIA_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    mediaEvents = events
                    // Force the first emit: the signature cache may already
                    // hold a state the new sink never saw.
                    lastMediaSignature = null
                    onMediaListenerStateChanged()
                }

                override fun onCancel(arguments: Any?) {
                    mediaEvents = null
                }
            })

        accelSensor = sensorManager?.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)

        // EventChannel for Accelerometer Shake Detection
        EventChannel(messenger, SHAKE_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                private var listener: SensorEventListener? = null
                private var lastAcceleration = SensorManager.GRAVITY_EARTH
                private var currentAcceleration = SensorManager.GRAVITY_EARTH
                private var shakeMagnitude = 0f
                private var lastShakeTime = 0L

                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    if (accelSensor == null || sensorManager == null) {
                        return
                    }
                    listener = object : SensorEventListener {
                        override fun onSensorChanged(event: SensorEvent?) {
                            if (event != null && event.values.size >= 3) {
                                val x = event.values[0]
                                val y = event.values[1]
                                val z = event.values[2]
                                lastAcceleration = currentAcceleration
                                currentAcceleration = kotlin.math.sqrt((x * x + y * y + z * z).toDouble()).toFloat()
                                val delta = kotlin.math.abs(currentAcceleration - lastAcceleration)
                                shakeMagnitude = shakeMagnitude * 0.85f + delta
                                val now = System.currentTimeMillis()
                                val isShake = shakeMagnitude > 9.5f && now - lastShakeTime > 500
                                if (isShake) {
                                    lastShakeTime = now
                                }
                                events?.success(mapOf(
                                    "type" to if (isShake) "shake" else "tilt",
                                    "magnitude" to shakeMagnitude.toDouble(),
                                    "x" to x.toDouble(),
                                    "y" to y.toDouble(),
                                    "z" to z.toDouble()
                                ))
                            }
                        }

                        override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}
                    }
                    sensorManager?.registerListener(
                        listener,
                        accelSensor,
                        SensorManager.SENSOR_DELAY_UI
                    )
                }

                override fun onCancel(arguments: Any?) {
                    listener?.let { sensorManager?.unregisterListener(it) }
                    listener = null
                }
            })
    }

    /** Pushes a channel event to the Dart side (e.g. `lockScreen`). */
    fun invokeAppsMethod(method: String, arguments: Any?) {
        appsMethodChannel.invokeMethod(method, arguments)
    }

    /** Releases everything [configure] acquired. Safe to call once. */
    fun dispose() {
        stopFingerprintScan()
        // Drop the sink so a live channel cannot outlive the activity.
        fingerprintEvents = null
        mediaEvents = null
        unregisterMediaSessionListener()
        MediaListenerService.removeSessionsMayHaveChangedListener(mediaListenerCallback)
        appsMethodChannel.setMethodCallHandler(null)
    }

    // --- System palette ----------------------------------------------------------------

    /**
     * Re-reads the ColorOS/Material You palette and pushes it to Dart when it
     * changed since the last push.
     *
     * Called from `onResume` of both activities: a wallpaper or theme change
     * resumes (or recreates) the activity, so this covers both. A read that
     * fails or returns nothing below API 31 leaves the last value and the Dart
     * fallback alone rather than blanking a working accent.
     */
    fun pushSystemPaletteIfChanged() {
        val palette = readSystemPalette() ?: return
        if (palette == lastSystemPalette) return
        lastSystemPalette = palette
        appsMethodChannel.invokeMethod("onSystemPaletteChanged", palette)
    }

    /**
     * The Material You tonal palette, or null when it does not exist.
     *
     * `android.R.color.system_accent1_*` and friends were added in API 31; the
     * compiler inlines the resource ids, so the guard is what keeps older
     * devices from reading them. The map shape mirrors the Dart
     * `SystemPalette.fromMap`: `"accent1" -> {"200": argb, ...}` plus
     * `"source"`.
     */
    private fun readSystemPalette(): Map<String, Any?>? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return null
        return try {
            mapOf(
                "source" to "system",
                "accent1" to accentTones(
                    android.R.color.system_accent1_0,
                    android.R.color.system_accent1_10,
                    android.R.color.system_accent1_50,
                    android.R.color.system_accent1_100,
                    android.R.color.system_accent1_200,
                    android.R.color.system_accent1_300,
                    android.R.color.system_accent1_400,
                    android.R.color.system_accent1_500,
                    android.R.color.system_accent1_600,
                    android.R.color.system_accent1_700,
                    android.R.color.system_accent1_800,
                    android.R.color.system_accent1_900,
                    android.R.color.system_accent1_1000,
                ),
                "accent2" to accentTones(
                    android.R.color.system_accent2_0,
                    android.R.color.system_accent2_10,
                    android.R.color.system_accent2_50,
                    android.R.color.system_accent2_100,
                    android.R.color.system_accent2_200,
                    android.R.color.system_accent2_300,
                    android.R.color.system_accent2_400,
                    android.R.color.system_accent2_500,
                    android.R.color.system_accent2_600,
                    android.R.color.system_accent2_700,
                    android.R.color.system_accent2_800,
                    android.R.color.system_accent2_900,
                    android.R.color.system_accent2_1000,
                ),
                "accent3" to accentTones(
                    android.R.color.system_accent3_0,
                    android.R.color.system_accent3_10,
                    android.R.color.system_accent3_50,
                    android.R.color.system_accent3_100,
                    android.R.color.system_accent3_200,
                    android.R.color.system_accent3_300,
                    android.R.color.system_accent3_400,
                    android.R.color.system_accent3_500,
                    android.R.color.system_accent3_600,
                    android.R.color.system_accent3_700,
                    android.R.color.system_accent3_800,
                    android.R.color.system_accent3_900,
                    android.R.color.system_accent3_1000,
                ),
                "neutral1" to accentTones(
                    android.R.color.system_neutral1_0,
                    android.R.color.system_neutral1_10,
                    android.R.color.system_neutral1_50,
                    android.R.color.system_neutral1_100,
                    android.R.color.system_neutral1_200,
                    android.R.color.system_neutral1_300,
                    android.R.color.system_neutral1_400,
                    android.R.color.system_neutral1_500,
                    android.R.color.system_neutral1_600,
                    android.R.color.system_neutral1_700,
                    android.R.color.system_neutral1_800,
                    android.R.color.system_neutral1_900,
                    android.R.color.system_neutral1_1000,
                ),
                "neutral2" to accentTones(
                    android.R.color.system_neutral2_0,
                    android.R.color.system_neutral2_10,
                    android.R.color.system_neutral2_50,
                    android.R.color.system_neutral2_100,
                    android.R.color.system_neutral2_200,
                    android.R.color.system_neutral2_300,
                    android.R.color.system_neutral2_400,
                    android.R.color.system_neutral2_500,
                    android.R.color.system_neutral2_600,
                    android.R.color.system_neutral2_700,
                    android.R.color.system_neutral2_800,
                    android.R.color.system_neutral2_900,
                    android.R.color.system_neutral2_1000,
                ),
            )
        } catch (e: Exception) {
            null
        }
    }

    /**
     * Pairs the thirteen Material tones with the resource ids read above.
     *
     * The ids arrive in [SYSTEM_TONES] order, so the index is the tone and the
     * resource name cannot drift from the key Dart looks up.
     */
    private fun accentTones(vararg ids: Int): Map<String, Int> {
        val tones = HashMap<String, Int>()
        for (index in SYSTEM_TONES.indices) {
            tones[SYSTEM_TONES[index].toString()] = activity.getColor(ids[index])
        }
        return tones
    }

    // --- App inventory -----------------------------------------------------------------

    private fun fetchInstalledApps(includeIcons: Boolean): List<Map<String, Any?>> {
        val pm = activity.packageManager
        val mainIntent = Intent(Intent.ACTION_MAIN, null).apply {
            addCategory(Intent.CATEGORY_LAUNCHER)
        }
        val resolveInfoList: List<ResolveInfo> = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            pm.queryIntentActivities(mainIntent, PackageManager.ResolveInfoFlags.of(0))
        } else {
            @Suppress("DEPRECATION")
            pm.queryIntentActivities(mainIntent, 0)
        }

        val appList = ArrayList<Map<String, Any?>>()

        for (resolveInfo in resolveInfoList) {
            val packageName = resolveInfo.activityInfo.packageName
            if (packageName == activity.applicationContext.packageName) {
                continue
            }
            val activityName = resolveInfo.activityInfo.name
            val label = resolveInfo.loadLabel(pm).toString()
            val appInfo = resolveInfo.activityInfo.applicationInfo
            val isSystemApp = (appInfo.flags and ApplicationInfo.FLAG_SYSTEM) != 0

            val appData = HashMap<String, Any?>()
            appData["packageName"] = packageName
            appData["activityName"] = activityName
            appData["label"] = label
            appData["isSystemApp"] = isSystemApp

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                appData["category"] = appInfo.category
            } else {
                appData["category"] = -1
            }

            if (includeIcons) {
                try {
                    val iconDrawable = resolveInfo.loadIcon(pm)
                    val iconBytes = drawableToByteArray(iconDrawable)
                    appData["iconBytes"] = iconBytes
                } catch (e: Exception) {
                    appData["iconBytes"] = null
                }
            }

            appList.add(appData)
        }

        return appList
    }

    /**
     * Renders [drawable] into a launcher-sized PNG.
     *
     * Icons used to be sent at intrinsic size — for adaptive icons that is
     * 432px on this device — which put tens of megabytes into a single
     * platform-channel message and made the Dart side decode every icon at
     * full size. The Dart layer already downscales to this size before drawing,
     * so scaling here is lossless from the launcher's point of view and removes
     * both the channel weight and the decode cost.
     */
    private fun drawableToByteArray(drawable: Drawable): ByteArray {
        val bitmap = Bitmap.createBitmap(ICON_PIXELS, ICON_PIXELS, Bitmap.Config.ARGB_8888)
        try {
            val canvas = Canvas(bitmap)
            drawable.setBounds(0, 0, canvas.width, canvas.height)
            drawable.draw(canvas)

            val stream = ByteArrayOutputStream()
            // PNG is lossless, so the quality argument does nothing; the win is
            // that the bitmap is already the size the launcher renders.
            bitmap.compress(Bitmap.CompressFormat.PNG, 100, stream)
            return stream.toByteArray()
        } finally {
            bitmap.recycle()
        }
    }

    // --- Launching ---------------------------------------------------------------------

    /**
     * Starts [intent] once the keyguard is out of the way, then reports whether
     * it started.
     *
     * If the keyguard is not locked — the normal case, since the launcher no
     * longer occludes it by default — the intent starts immediately.
     *
     * If the keyguard is locked, [KeyguardManager.requestDismissKeyguard] is
     * requested, and the platform performs the authentication: biometric, PIN or
     * pattern, in its own UI. This is the launcher's only real authentication
     * gate. Nothing in Dart can stand in for it, because while the device is
     * locked only the keyguard may use the fingerprint sensor.
     *
     * [onStarted] reports true only when the activity is genuinely on its way to
     * being visible. A refused or cancelled dismissal reports false rather than
     * starting the activity behind the lock screen, where it would run unseen
     * while the caller believed the launch had succeeded.
     */
    private fun startWhenUnlocked(
        intent: Intent,
        onStarted: (Boolean) -> Unit,
    ) {
        val keyguard = activity.getSystemService(Context.KEYGUARD_SERVICE) as? KeyguardManager
        if (keyguard == null || !keyguard.isKeyguardLocked) {
            // This activity must resume as ordinary home content after the
            // target closes, not as an overlay that re-occludes a keyguard.
            host.setOverlayWhenLocked(false)
            host.startTarget(intent, onStarted)
            return
        }

        // Release this app's hold on the reader first so the keyguard can
        // take over sensor ownership cleanly.
        stopFingerprintScan()

        keyguard.requestDismissKeyguard(
            activity,
            object : KeyguardManager.KeyguardDismissCallback() {
                override fun onDismissSucceeded() {
                    // ColorOS can re-present its bouncer when MainActivity
                    // returns while it remains `showWhenLocked`. Remove that
                    // temporary window flag before starting the target; the
                    // Dart screen-off listener restores it for a real lock.
                    host.setOverlayWhenLocked(false)
                    host.startTarget(intent, onStarted)
                }

                override fun onDismissError() {
                    // Starting the activity anyway reported success for a launch
                    // the user cannot see: with the keyguard still up the
                    // activity lands *behind* it, running and invisible, which
                    // reads as the app never having opened. Reporting the
                    // failure lets the caller say so instead.
                    android.util.Log.w(
                        "ChronoFold",
                        "Keyguard refused to dismiss; not starting behind it",
                    )
                    onStarted(false)
                }

                override fun onDismissCancelled() {
                    onStarted(false)
                }
            },
        )
    }

    /**
     * Asks the platform to authenticate the user and clear the keyguard, without
     * launching anything.
     *
     * This exists because the launcher's own lock panel cannot authenticate
     * anyone. While the device is locked only the keyguard may use the
     * fingerprint sensor, so a panel drawn over the keyguard has no way to
     * verify identity itself. Its swipe-to-enter gesture therefore has exactly
     * two honest options: refuse, or ask the platform to do the authenticating.
     * This is the second.
     *
     * On a secure keyguard `requestDismissKeyguard` raises the platform's own
     * bouncer (biometric, PIN, pattern), and the callback reports what the user
     * did. On a device with no secure lock the keyguard is not locked and there
     * is nothing to authenticate, so this reports success immediately.
     */
    private fun requestKeyguardDismissal(onResult: (Boolean) -> Unit) {
        val keyguard = activity.getSystemService(Context.KEYGUARD_SERVICE) as? KeyguardManager
        if (keyguard == null || !keyguard.isKeyguardLocked) {
            onResult(true)
            return
        }

        // Release this app's hold on the reader first so the keyguard can take
        // sensor ownership cleanly.
        stopFingerprintScan()

        keyguard.requestDismissKeyguard(
            activity,
            object : KeyguardManager.KeyguardDismissCallback() {
                override fun onDismissSucceeded() {
                    onResult(true)
                }

                override fun onDismissError() {
                    onResult(false)
                }

                override fun onDismissCancelled() {
                    onResult(false)
                }
            },
        )
    }

    /**
     * Starts an external activity and records the handoff, the single entry
     * point both activities use for every external start. Public so the
     * launcher's own extras (app info, uninstall, overlay settings) reuse it.
     */
    fun startActivityQuietly(intent: Intent): Boolean {
        return try {
            host.onForeignHandoff()
            activity.startActivity(intent)
            true
        } catch (e: Exception) {
            // Nothing was handed anywhere, so the caller still owns the screen.
            host.onForeignHandoffFailed()
            false
        }
    }

    private fun launchApplication(
        packageName: String,
        activityName: String?,
        onComplete: (Boolean) -> Unit,
    ) {
        val intent = try {
            if (activityName != null && activityName.isNotEmpty()) {
                Intent().apply {
                    setClassName(packageName, activityName)
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED
                }
            } else {
                activity.packageManager.getLaunchIntentForPackage(packageName)?.apply {
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED
                }
            }
        } catch (e: Exception) {
            null
        }

        if (intent == null) {
            onComplete(false)
            return
        }
        startWhenUnlocked(intent, onComplete)
    }

    /**
     * Opens the platform's own handler for a lock-screen shortcut.
     *
     * The dialer is reached with ACTION_DIAL: every device answers it, it needs
     * no package name, and it is permitted over the keyguard. It also resolves
     * to a single activity on the tested ColorOS 16 build
     * (com.android.contacts/.DialtactsActivityAlias) — the very component the
     * launcher cannot find by package name, because that package publishes a
     * second launcher alias for Contacts.
     *
     * The camera has no equally unambiguous action: on the same device both
     * INTENT_ACTION_STILL_IMAGE_CAMERA_SECURE and INTENT_ACTION_STILL_IMAGE_CAMERA
     * are also claimed by a social app, so the platform raises a chooser. A
     * chooser is not an answer to "open the camera", so this reports failure and
     * lets the caller say so instead of surprising the user.
     */
    private fun openQuickShortcut(shortcut: String?): Boolean {
        val intent = when (shortcut) {
            "phone" -> Intent(Intent.ACTION_DIAL)
            "camera" -> Intent(MediaStore.INTENT_ACTION_STILL_IMAGE_CAMERA_SECURE)
            else -> return false
        }
        intent.flags = Intent.FLAG_ACTIVITY_NEW_TASK

        val resolved = intent.resolveActivity(activity.packageManager) ?: return false
        // "android" is the platform's own ResolverActivity, i.e. a chooser.
        if (resolved.packageName == "android") return false

        startWhenUnlocked(intent) { }
        return true
    }

    /**
     * The real battery state for the lock surface, which used to show a
     * hardcoded "92%" over a charging glyph.
     *
     * Returns level (0-100) and the charging flag, or null when the level is
     * genuinely unavailable — the panel then hides the percentage instead of
     * inventing one. minSdk is 26, so BATTERY_PROPERTY_CAPACITY and isCharging
     * are both fully available on every device this runs on.
     */
    private fun getBatteryState(): Map<String, Any>? {
        val manager = activity.getSystemService(Context.BATTERY_SERVICE) as? android.os.BatteryManager
            ?: return null
        return try {
            val level = manager.getIntProperty(android.os.BatteryManager.BATTERY_PROPERTY_CAPACITY)
            // An unavailable property answers Integer.MIN_VALUE (and the
            // occasional OEM build throws instead) — that is "unknown", not
            // zero, so it must not reach the panel as a number.
            if (level == Int.MIN_VALUE) null
            else mapOf(
                "level" to level,
                "charging" to manager.isCharging,
            )
        } catch (error: Exception) {
            android.util.Log.e("ChronoFold", "Battery state unavailable", error)
            null
        }
    }

    // --- Now-playing media -------------------------------------------------------------
    //
    // The card on the lock screen mirrors the one media session the user is
    // most likely to mean: the first PLAYING session, else the most recent
    // PAUSED/BUFFERING one. Everything here is gated on the notification
    // listener grant because MediaSessionManager refuses to answer without it.

    /**
     * Whether this app's listener component is in the platform's enabled list.
     *
     * Read from Settings rather than from [MediaListenerService.instance]
     * because the instance is null until the service is bound, and the user can
     * flip the grant in system settings while the service keeps running. The
     * secure setting is the platform's own record and updates immediately.
     *
     * The key is the literal `enabled_notification_listeners` — the public
     * constant for it is hidden in the framework, and this string is stable.
     */
    private fun hasMediaListenerAccess(): Boolean {
        val enabled = Settings.Secure.getString(
            activity.contentResolver,
            "enabled_notification_listeners",
        ) ?: return false
        val component = ComponentName(activity, MediaListenerService::class.java)
        return enabled.split(":").any { entry ->
            ComponentName.unflattenFromString(entry) == component
        }
    }

    /** Re-resolves the grant, registering or dropping the session listener. */
    private fun onMediaListenerStateChanged() {
        if (hasMediaListenerAccess()) {
            registerMediaSessionListener()
            refreshActiveSessions()
        } else {
            unregisterMediaSessionListener()
            lastMediaSignature = null
            emitMediaState(force = true)
        }
    }

    private fun registerMediaSessionListener() {
        if (activeSessionsListener != null) return
        val manager = resolveMediaSessionManager()
            ?: return
        if (!hasMediaListenerAccess()) return
        val component = ComponentName(activity, MediaListenerService::class.java)
        val listener = MediaSessionManager.OnActiveSessionsChangedListener { controllers ->
            // MediaSessionManager usually delivers on the main looper, but the
            // controller state this reads is owned by the main thread; posting
            // explicitly makes that independent of the platform's choice.
            activity.runOnUiThread { updatePrimaryController(controllers) }
        }
        try {
            manager.addOnActiveSessionsChangedListener(listener, component)
            activeSessionsListener = listener
        } catch (error: SecurityException) {
            // The grant was revoked between the check and the call.
            activeSessionsListener = null
            android.util.Log.d(
                "ChronoFold",
                "CF_MEDIA: cannot observe media sessions",
                error,
            )
        }
    }

    private fun unregisterMediaSessionListener() {
        val listener = activeSessionsListener
        activeSessionsListener = null
        if (listener != null) {
            try {
                resolveMediaSessionManager()?.removeOnActiveSessionsChangedListener(listener)
            } catch (error: Exception) {
                android.util.Log.d("ChronoFold", "CF_MEDIA: listener already gone", error)
            }
        }
        updatePrimaryController(emptyList())
    }

    private fun resolveMediaSessionManager(): MediaSessionManager? {
        return mediaSessionManager ?: run {
            val manager = activity.getSystemService(Context.MEDIA_SESSION_SERVICE) as? MediaSessionManager
            mediaSessionManager = manager
            manager
        }
    }

    private fun refreshActiveSessions() {
        val manager = resolveMediaSessionManager()
            ?: return
        if (!hasMediaListenerAccess()) return
        try {
            val component = ComponentName(activity, MediaListenerService::class.java)
            updatePrimaryController(manager.getActiveSessions(component))
        } catch (error: SecurityException) {
            android.util.Log.d(
                "ChronoFold",
                "CF_MEDIA: active media sessions unavailable",
                error,
            )
            updatePrimaryController(emptyList())
        }
    }

    /**
     * Picks the session the card should represent and swaps the callback to it.
     *
     * The order matters: a PLAYING session anywhere in the list wins over a
     * more recent paused one, because that is the session the user is hearing.
     * Only when nothing is playing does recency decide, and `getActiveSessions`
     * already returns the most recent first.
     */
    private fun updatePrimaryController(controllers: List<MediaController>?) {
        val sessions = controllers ?: emptyList()
        var chosen: MediaController? = null
        for (controller in sessions) {
            if (controller.playbackState?.state == PlaybackState.STATE_PLAYING) {
                chosen = controller
                break
            }
        }
        if (chosen == null) {
            for (controller in sessions) {
                val state = controller.playbackState?.state
                if (state == PlaybackState.STATE_PAUSED ||
                    state == PlaybackState.STATE_BUFFERING
                ) {
                    chosen = controller
                    break
                }
            }
        }
        setPrimaryController(chosen)
    }

    private fun setPrimaryController(controller: MediaController?) {
        val current = primaryController
        // Same session token: keep the existing callback and report through the
        // signature cache. `onPlaybackStateChanged` can fire for position-only
        // updates, so this path must never force: a force here would put a
        // message on the channel once per playback update, which is exactly the
        // throttle the signature exists to provide.
        if (controller != null &&
            current != null &&
            controller.sessionToken == current.sessionToken
        ) {
            emitMediaState(force = false)
            return
        }
        if (controller == null && current == null) {
            emitMediaState(force = false)
            return
        }

        val previousCallback = primaryControllerCallback
        if (current != null && previousCallback != null) {
            try {
                current.unregisterCallback(previousCallback)
            } catch (error: Exception) {
                android.util.Log.d("ChronoFold", "CF_MEDIA: callback already gone", error)
            }
        }
        primaryControllerCallback = null
        primaryController = controller

        if (controller != null) {
            val callback = object : MediaController.Callback() {
                override fun onPlaybackStateChanged(state: PlaybackState?) {
                    // The state may have dropped the session out of the
                    // PLAYING/PAUSED/BUFFERING set entirely, so re-resolve
                    // rather than assuming the same controller still wins.
                    activity.runOnUiThread { refreshActiveSessions() }
                }

                override fun onMetadataChanged(metadata: MediaMetadata?) {
                    activity.runOnUiThread { emitMediaState(force = true) }
                }

                override fun onSessionDestroyed() {
                    activity.runOnUiThread { refreshActiveSessions() }
                }
            }
            try {
                controller.registerCallback(callback)
                primaryControllerCallback = callback
            } catch (error: SecurityException) {
                android.util.Log.d("ChronoFold", "CF_MEDIA: cannot observe session", error)
                primaryController = null
            }
        }
        emitMediaState(force = true)
    }

    /**
     * Emits the current session on metadata/state changes only.
     *
     * [mediaSignature] deliberately excludes position and its timestamp: a
     * position that advanced is carried by the payload but must not, by itself,
     * cross the channel once per tick.
     */
    private fun emitMediaState(force: Boolean) {
        val signature = mediaSignature()
        if (!force && signature == lastMediaSignature) return
        lastMediaSignature = signature
        val payload = buildMediaPayload()
        activity.runOnUiThread {
            mediaEvents?.success(payload)
        }
    }

    private fun mediaSignature(): String {
        val controller = primaryController ?: return "none"
        val metadata = controller.metadata
        val playbackState = controller.playbackState
        return listOf(
            controller.packageName,
            playbackState?.state,
            playbackState?.actions,
            playbackState?.playbackSpeed,
            metadata?.getString(MediaMetadata.METADATA_KEY_TITLE),
            metadata?.getString(MediaMetadata.METADATA_KEY_ARTIST),
            metadata?.getString(MediaMetadata.METADATA_KEY_ALBUM),
            metadata?.getLong(MediaMetadata.METADATA_KEY_DURATION),
            metadata?.getBitmap(MediaMetadata.METADATA_KEY_ALBUM_ART)
                ?.let { System.identityHashCode(it) },
            metadata?.getBitmap(MediaMetadata.METADATA_KEY_ART)
                ?.let { System.identityHashCode(it) },
        ).joinToString("|")
    }

    private fun buildMediaPayload(): Map<String, Any?>? {
        val controller = primaryController ?: return null
        val metadata = controller.metadata
        val playbackState = controller.playbackState
        val controllerPackage = controller.packageName ?: return null

        val appLabel = try {
            val info = activity.packageManager.getApplicationInfo(controllerPackage, 0)
            activity.packageManager.getApplicationLabel(info).toString()
        } catch (error: Exception) {
            // An uninstalled or invisible package still has a session for a
            // moment; the package name is a truthful fallback.
            controllerPackage
        }

        val state = when (playbackState?.state) {
            PlaybackState.STATE_PLAYING,
            PlaybackState.STATE_FAST_FORWARDING,
            PlaybackState.STATE_REWINDING,
            PlaybackState.STATE_SKIPPING_TO_NEXT,
            PlaybackState.STATE_SKIPPING_TO_PREVIOUS -> "playing"
            PlaybackState.STATE_BUFFERING,
            PlaybackState.STATE_CONNECTING -> "buffering"
            PlaybackState.STATE_PAUSED -> "paused"
            else -> "stopped"
        }

        val actions = playbackState?.actions ?: 0L
        val duration = metadata?.getLong(MediaMetadata.METADATA_KEY_DURATION)
        return mapOf(
            "packageName" to controllerPackage,
            "appLabel" to appLabel,
            "title" to metadata?.getString(MediaMetadata.METADATA_KEY_TITLE),
            "artist" to metadata?.getString(MediaMetadata.METADATA_KEY_ARTIST),
            "album" to metadata?.getString(MediaMetadata.METADATA_KEY_ALBUM),
            // A missing or zero duration is "unknown"; Dart must not draw a
            // progress bar against it.
            "durationMs" to duration?.takeIf { it > 0L },
            "positionMs" to (playbackState?.position ?: 0L),
            "positionUpdatedAtMs" to (playbackState?.lastPositionUpdateTime ?: 0L),
            "speed" to (playbackState?.playbackSpeed ?: 1.0f).toDouble(),
            "state" to state,
            "canPrev" to (actions and PlaybackState.ACTION_SKIP_TO_PREVIOUS != 0L),
            "canNext" to (actions and PlaybackState.ACTION_SKIP_TO_NEXT != 0L),
            "canPlayPause" to (
                actions and (
                    PlaybackState.ACTION_PLAY_PAUSE or
                        PlaybackState.ACTION_PLAY or
                        PlaybackState.ACTION_PAUSE
                    ) != 0L
                ),
            "art" to bitmapToPngBytes(
                metadata?.getBitmap(MediaMetadata.METADATA_KEY_ALBUM_ART)
                    ?: metadata?.getBitmap(MediaMetadata.METADATA_KEY_ART),
            ),
        )
    }

    private fun handleMediaCommand(command: String?): Boolean {
        if (!hasMediaListenerAccess()) return false
        val controller = primaryController ?: return false
        val controls = controller.transportControls ?: return false
        return try {
            when (command) {
                "playPause" -> {
                    if (controller.playbackState?.state == PlaybackState.STATE_PLAYING) {
                        controls.pause()
                    } else {
                        controls.play()
                    }
                    true
                }
                "next" -> {
                    controls.skipToNext()
                    true
                }
                "previous" -> {
                    controls.skipToPrevious()
                    true
                }
                else -> false
            }
        } catch (error: SecurityException) {
            android.util.Log.d("ChronoFold", "CF_MEDIA: media command refused", error)
            false
        } catch (error: Exception) {
            android.util.Log.d("ChronoFold", "CF_MEDIA: media command failed", error)
            false
        }
    }

    /**
     * Encodes album art as a PNG no larger than [MEDIA_ART_MAX_PIXELS] a side.
     *
     * The bound is the same reason app icons are bounded: an unbounded bitmap
     * is a multi-megabyte platform-channel message and a full-size decode on
     * the Dart side, for something that renders 56dp wide. The source bitmap
     * belongs to the MediaMetadata and is never recycled.
     */
    private fun bitmapToPngBytes(bitmap: Bitmap?): ByteArray? {
        if (bitmap == null) return null
        return try {
            val largestEdge = maxOf(bitmap.width, bitmap.height)
            val scaled = if (largestEdge <= MEDIA_ART_MAX_PIXELS) {
                bitmap
            } else {
                val ratio = MEDIA_ART_MAX_PIXELS.toFloat() / largestEdge.toFloat()
                Bitmap.createScaledBitmap(
                    bitmap,
                    maxOf(1, (bitmap.width * ratio).toInt()),
                    maxOf(1, (bitmap.height * ratio).toInt()),
                    true,
                )
            }
            val stream = ByteArrayOutputStream()
            scaled.compress(Bitmap.CompressFormat.PNG, 100, stream)
            if (scaled !== bitmap) scaled.recycle()
            stream.toByteArray()
        } catch (error: Exception) {
            android.util.Log.e("ChronoFold", "CF_MEDIA: album art encode failed", error)
            null
        }
    }

    // --- Fingerprint -------------------------------------------------------------------

    private fun fingerprintManager(): FingerprintManager? =
        activity.getSystemService(Context.FINGERPRINT_SERVICE) as? FingerprintManager

    private fun fingerprintCapability(): Map<String, Any> {
        val manager = fingerprintManager()
        val hardware = manager?.isHardwareDetected == true
        val enrolled = hardware && manager?.hasEnrolledFingerprints() == true
        return mapOf("hardware" to hardware, "enrolled" to enrolled)
    }

    /**
     * Arms the silent reader.
     *
     * Returns whether a session was genuinely started: every refusal reports
     * false alongside its event, so an arm that never happened cannot
     * masquerade as a live session on the Dart side. Dart's armed state is
     * built from this answer plus the terminal events, not from `listening`.
     */
    @Suppress("DEPRECATION")
    private fun startFingerprintScan(): Boolean {
        val manager = fingerprintManager()
        if (manager == null || !manager.isHardwareDetected || !manager.hasEnrolledFingerprints()) {
            fingerprintEvents?.success(mapOf("type" to "unavailable"))
            return false
        }

        if (powerManager?.isInteractive != true) {
            // The platform cancels an app's reader session the moment the panel
            // goes off, so arming now would only burn the caller's retry budget
            // and leave the sensor dead before the user has touched anything.
            fingerprintEvents?.success(mapOf("type" to "screenOff"))
            return false
        }

        val keyguard = activity.getSystemService(Context.KEYGUARD_SERVICE) as? KeyguardManager
        if (keyguard?.isKeyguardLocked == true) {
            // While the keyguard is locked it owns the power-button sensor, and
            // this build cancels an app's reader session within ~2 ms of the
            // arm — cold start, no competing session, key-bound or bare
            // (repro-fingerprint-unlock Red 1). Every arm in this state was
            // measured to fail identically, so arming spends the sensor for
            // nothing and leaves it dead for the requests that matter. Refuse
            // without touching it and say so with a distinct event, so Dart
            // resolves the request through the platform's own bouncer — the
            // only reader a locked keyguard accepts.
            fingerprintEvents?.success(mapOf("type" to "keyguardLocked"))
            return false
        }

        if (!host.isForeground()) {
            // A biometric session opened from a background activity is one the
            // user never asked for, and on a device whose system UI draws the
            // sensor affordance for an active session it appears as a prompt out
            // of nowhere — over whatever app they are actually using.
            //
            // This is the last line of defence rather than the first: the Dart
            // panel is not supposed to ask while it is not the visible surface.
            // Saying no here means a stale caller cannot make it happen anyway.
            android.util.Log.d(
                "ChronoFold",
                "Refusing to arm the reader: surface is not in the foreground",
            )
            fingerprintEvents?.success(mapOf("type" to "background"))
            return false
        }

        stopFingerprintScan()
        val signal = CancellationSignal()
        fingerprintCancellation = signal

        return try {
            // A bare request. Binding the session to a keystore key was tried and
            // measured on the CPH2765: a key-bound `CryptoObject` is armed and
            // then cancelled in ~1 ms exactly like this one, so the refusal is
            // the device's lock policy rather than anything about the session's
            // shape. There is no form of app-owned reader session this build
            // accepts while the keyguard is up, which is why the lock screen
            // falls back to the platform's own prompt in that state.
            manager.authenticate(
                null,
                signal,
                0,
                object : FingerprintManager.AuthenticationCallback() {
                    /** Whether this session already reported `listening`. */
                    private var listeningAnnounced = false

                    override fun onAuthenticationSucceeded(
                        result: FingerprintManager.AuthenticationResult?
                    ) {
                        // A superseded session keeps reporting after it was
                        // replaced; only the live signal may reach Dart.
                        if (fingerprintCancellation !== signal) return
                        fingerprintCancellation = null
                        fingerprintEvents?.success(mapOf("type" to "succeeded"))
                    }

                    override fun onAuthenticationFailed() {
                        if (fingerprintCancellation !== signal) return
                        // A non-matching finger: the sensor stays armed.
                        fingerprintEvents?.success(mapOf("type" to "failed"))
                    }

                    override fun onAuthenticationError(errorCode: Int, errString: CharSequence?) {
                        if (fingerprintCancellation !== signal) return
                        fingerprintCancellation = null
                        fingerprintEvents?.success(
                            mapOf(
                                "type" to "error",
                                "code" to errorCode,
                                "message" to (errString?.toString() ?: ""),
                            )
                        )
                    }

                    override fun onAuthenticationHelp(helpCode: Int, helpString: CharSequence?) {
                        // A session is "listening" only once the platform has
                        // actually shown sensor activity, and a partial read
                        // (finger moved, sensor dirty) is the first honest
                        // signal of that — the sensor is genuinely live. The
                        // old emit right after authenticate() claimed a session
                        // this build then cancels within 1–6 ms, so Dart's
                        // armed state flickered for a session that never
                        // existed. Once per session, and a superseded session
                        // stays silent via the identity check above.
                        if (fingerprintCancellation !== signal) return
                        if (!listeningAnnounced) {
                            listeningAnnounced = true
                            fingerprintEvents?.success(mapOf("type" to "listening"))
                        }
                    }
                },
                null,
            )
            // The platform accepted the call — that is all this claims. The
            // session is live but nothing has touched the sensor yet, and on
            // this build the platform may still cancel it a millisecond later
            // (which arrives as an `error` event and clears Dart's armed
            // state again). Reporting more here would be the optimistic lie
            // this function used to tell.
            true
        } catch (error: Exception) {
            fingerprintCancellation = null
            android.util.Log.e("ChronoFold", "Fingerprint reader unavailable", error)
            fingerprintEvents?.success(
                mapOf(
                    "type" to "unavailable",
                    "message" to (error.message ?: "Fingerprint sensor unavailable"),
                )
            )
            false
        }
    }

    private fun stopFingerprintScan() {
        // Cleared before cancelling so the callback the cancel triggers is
        // recognised as belonging to a superseded session and is dropped.
        val signal = fingerprintCancellation
        fingerprintCancellation = null
        signal?.cancel()
    }

    private fun authenticateUser(appName: String?, callback: (Boolean, String?) -> Unit) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            val keyguardManager = activity.getSystemService(Context.KEYGUARD_SERVICE) as? KeyguardManager
            if (keyguardManager == null || !keyguardManager.isDeviceSecure) {
                callback(true, null)
                return
            }

            // The panel's silent reader and the system prompt cannot share the
            // sensor, and whichever grabs it second cancels the first. This is
            // the fallback path, so the system prompt wins.
            stopFingerprintScan()

            val title = if (!appName.isNullOrEmpty()) "Launch $appName" else "Verify Identity"
            val subtitle = if (!appName.isNullOrEmpty()) "Verify identity to open $appName" else "Scan fingerprint, face, or enter credential"

            val promptBuilder = BiometricPrompt.Builder(activity)
                .setTitle(title)
                .setSubtitle(subtitle)
                .setDescription("Scan fingerprint, face, or enter credential")

            // Do NOT brand this prompt. Measured on the CPH2765 (ColorOS 16):
            //
            //   java.lang.SecurityException: Must have SET_BIOMETRIC_DIALOG_ADVANCED
            //   permission ... at AuthService.checkBiometricAdvancedPermission(
            //   AuthService.java:993)
            //
            // AOSP's AuthService.checkBiometricAdvancedPermission requires that
            // signature permission whenever the request bundle carries the
            // "use logo" extra, and it enforces that check *server side*, inside
            // authenticate(). So a logo cannot be caught locally: the Builder
            // accepts setLogoRes, build() succeeds, and then authenticate()
            // throws. No third-party app can hold that permission, which means
            // ColorOS forbids third-party biometric-dialog customisation
            // outright — including setLogoBitmap and setConfirmationRequired,
            // which travel in the same bundle.
            //
            // Swallowing that throw would be worse than not branding: the Dart
            // credential fallback has no result, so the lock screen reports
            // "auth required" while the user was never prompted for anything.
            // The only correct behaviour is not to ask for the logo at all and
            // let the platform draw its own uncustomised prompt.
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                promptBuilder.setAllowedAuthenticators(
                    android.hardware.biometrics.BiometricManager.Authenticators.BIOMETRIC_STRONG or
                    android.hardware.biometrics.BiometricManager.Authenticators.DEVICE_CREDENTIAL
                )
            } else {
                @Suppress("DEPRECATION")
                promptBuilder.setNegativeButton(
                    "Cancel",
                    activity.mainExecutor
                ) { _, _ ->
                    callback(false, "Canceled")
                }
            }

            val cancellationSignal = CancellationSignal()
            promptBuilder.build().authenticate(
                cancellationSignal,
                activity.mainExecutor,
                object : BiometricPrompt.AuthenticationCallback() {
                    override fun onAuthenticationSucceeded(result: BiometricPrompt.AuthenticationResult?) {
                        super.onAuthenticationSucceeded(result)
                        callback(true, null)
                    }

                    override fun onAuthenticationError(errorCode: Int, errString: CharSequence?) {
                        super.onAuthenticationError(errorCode, errString)
                        callback(false, errString?.toString())
                    }

                    override fun onAuthenticationFailed() {
                        super.onAuthenticationFailed()
                    }
                }
            )
        } else {
            callback(true, null)
        }
    }
}
