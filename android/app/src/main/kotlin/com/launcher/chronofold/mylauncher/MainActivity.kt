package com.launcher.chronofold.mylauncher

import android.content.Context
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
import android.net.Uri
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

class MainActivity : FlutterActivity() {
    private val APPS_CHANNEL = "com.launcher.chronofold/apps"
    private val HINGE_CHANNEL = "com.launcher.chronofold/hinge"
    private val SHAKE_CHANNEL = "com.launcher.chronofold/shake"
    private val FINGERPRINT_CHANNEL = "com.launcher.chronofold/fingerprint"

    /** Edge length of the launcher icons sent to Dart. */
    private val ICON_PIXELS = 96

    private val backgroundExecutor = Executors.newSingleThreadExecutor()
    private var sensorManager: SensorManager? = null
    private var hingeSensor: Sensor? = null
    private var accelSensor: Sensor? = null
    private var fingerprintCancellation: CancellationSignal? = null
    private var fingerprintEvents: EventChannel.EventSink? = null
    private var powerManager: PowerManager? = null

    /**
     * Whether the keyguard required authentication when the panel last went
     * off. Only an unlock that follows a genuinely locked keyguard is handed to
     * the launcher: a wake that merely dismissed an already-open keyguard is
     * not an authentication and must not clear the overlay.
     */
    private var keyguardWasLocked = false
    private var screenReceiver: BroadcastReceiver? = null
    private var packageReceiver: BroadcastReceiver? = null
    private var appsMethodChannel: MethodChannel? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.setBackgroundDrawable(android.graphics.drawable.ColorDrawable(android.graphics.Color.parseColor("#020306")))
        // The cover screen is its own lock surface, so it is drawn over the
        // keyguard. Android still authenticates the keyguard behind it, which
        // is what makes a touch on the power-button reader unlock; the launcher
        // clears this overlay when the platform reports that unlock.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
            )
        }

        screenReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                val keyguard = getSystemService(Context.KEYGUARD_SERVICE) as? KeyguardManager
                when (intent?.action) {
                    Intent.ACTION_SCREEN_OFF -> {
                        keyguardWasLocked = keyguard?.isKeyguardLocked == true ||
                            keyguard?.isDeviceLocked == true
                        runOnUiThread {
                            appsMethodChannel?.invokeMethod("lockScreen", null)
                        }
                    }
                    Intent.ACTION_SCREEN_ON ->
                        runOnUiThread {
                            appsMethodChannel?.invokeMethod("screenOn", null)
                        }
                    Intent.ACTION_USER_PRESENT -> {
                        if (keyguardWasLocked) {
                            runOnUiThread {
                                appsMethodChannel?.invokeMethod("userPresent", null)
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
                    appsMethodChannel?.invokeMethod("onPackagesChanged", null)
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

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        if (intent.hasCategory(Intent.CATEGORY_HOME) || intent.action == Intent.ACTION_MAIN) {
            runOnUiThread {
                appsMethodChannel?.invokeMethod("onHomePressed", null)
            }
        }
    }

    override fun onDestroy() {
        stopFingerprintScan()
        // Drop the sink so a live channel cannot outlive the activity.
        fingerprintEvents = null
        screenReceiver?.let { unregisterReceiver(it) }
        packageReceiver?.let { unregisterReceiver(it) }
        super.onDestroy()
    }

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        sensorManager = getSystemService(Context.SENSOR_SERVICE) as? SensorManager
        powerManager = getSystemService(Context.POWER_SERVICE) as? PowerManager
        // TYPE_HINGE_ANGLE is 36
        hingeSensor = sensorManager?.getDefaultSensor(36)

        // MethodChannel for App querying & launching
        appsMethodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, APPS_CHANNEL)
        appsMethodChannel?.setMethodCallHandler { call, result ->
                when (call.method) {
                    "getInstalledApps" -> {
                        val includeIcons = call.argument<Boolean>("includeIcons") ?: true
                        backgroundExecutor.execute {
                            try {
                                val apps = fetchInstalledApps(includeIcons)
                                runOnUiThread {
                                    result.success(apps)
                                }
                            } catch (e: Exception) {
                                runOnUiThread {
                                    result.error("SCAN_ERROR", e.message, null)
                                }
                            }
                        }
                    }
                    "launchApp" -> {
                        val packageName = call.argument<String>("packageName")
                        val activityName = call.argument<String>("activityName")
                        if (packageName != null) {
                            // Resolved only once the keyguard is out of the way
                            // and the activity has actually been started, so the
                            // caller knows when it is safe to drop its own
                            // cover over the lock screen.
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
                        startActivity(intent)
                        result.success(true)
                    }
                    "getFilesDirPath" -> {
                        result.success(applicationContext.filesDir.absolutePath)
                    }
                    "authenticate" -> {
                        val appName = call.argument<String>("appName")
                        authenticateUser(appName) { success, error ->
                            runOnUiThread {
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
                        startFingerprintScan()
                        result.success(true)
                    }
                    "stopFingerprintScan" -> {
                        stopFingerprintScan()
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }

        // EventChannel for Hinge Angle Sensor
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, HINGE_CHANNEL)
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
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, FINGERPRINT_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    fingerprintEvents = events
                }

                override fun onCancel(arguments: Any?) {
                    fingerprintEvents = null
                    stopFingerprintScan()
                }
            })

        accelSensor = sensorManager?.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)

        // EventChannel for Accelerometer Shake Detection
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, SHAKE_CHANNEL)
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

    private fun fetchInstalledApps(includeIcons: Boolean): List<Map<String, Any?>> {
        val pm = packageManager
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
            if (packageName == applicationContext.packageName) {
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

    /**
     * Starts [intent] once the keyguard is out of the way, then reports whether
     * it started.
     *
     * The launcher draws over the keyguard (`showWhenLocked`), so its lock
     * overlay is interactive while the device is still locked. An activity
     * started from that state is placed *behind* the keyguard: the user
     * authenticates, the overlay clears, and they are shown the system lock
     * screen with the app they asked for running out of sight.
     *
     * [onStarted] is therefore invoked only after the keyguard has actually
     * gone and the activity is on its way, which is the signal the caller needs
     * to keep its own cover up for exactly as long as the system lock screen
     * could otherwise show through — that gap is what made the ColorOS keyguard
     * flash during the transition.
     *
     * `requestDismissKeyguard` only prompts when the device is still locked, so
     * on the normal path — the power-button reader authenticating the keyguard
     * itself — it dismisses silently.
     */
    private fun startWhenUnlocked(intent: Intent, onStarted: (Boolean) -> Unit) {
        val keyguard = getSystemService(Context.KEYGUARD_SERVICE) as? KeyguardManager
        if (keyguard == null || !keyguard.isKeyguardLocked) {
            onStarted(startActivityQuietly(intent))
            return
        }

        keyguard.requestDismissKeyguard(
            this,
            object : KeyguardManager.KeyguardDismissCallback() {
                override fun onDismissSucceeded() {
                    onStarted(startActivityQuietly(intent))
                }

                override fun onDismissError() {
                    // The keyguard refused to go; opening behind it would show
                    // the user a lock screen, so it is not started at all.
                    onStarted(false)
                }

                override fun onDismissCancelled() {
                    // The user backed out of the credential prompt.
                    onStarted(false)
                }
            },
        )
    }

    private fun startActivityQuietly(intent: Intent): Boolean {
        return try {
            startActivity(intent)
            true
        } catch (e: Exception) {
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
                packageManager.getLaunchIntentForPackage(packageName)?.apply {
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

        val resolved = intent.resolveActivity(packageManager) ?: return false
        // "android" is the platform's own ResolverActivity, i.e. a chooser.
        if (resolved.packageName == "android") return false

        startWhenUnlocked(intent) { }
        return true
    }

    private fun openAppInfo(packageName: String) {
        val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
            data = Uri.fromParts("package", packageName, null)
            flags = Intent.FLAG_ACTIVITY_NEW_TASK
        }
        startActivity(intent)
    }

    private fun uninstallApplication(packageName: String) {
        val intent = Intent(Intent.ACTION_DELETE).apply {
            data = Uri.fromParts("package", packageName, null)
            flags = Intent.FLAG_ACTIVITY_NEW_TASK
        }
        startActivity(intent)
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
                startActivity(intent)
                return
            }
        }
        val intent = Intent(Settings.ACTION_HOME_SETTINGS).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK
        }
        startActivity(intent)
    }

    // --- Silent fingerprint scanning -------------------------------------------------
    //
    // BiometricPrompt always draws its own system dialog. The legacy
    // FingerprintManager does not: the app owns the affordance, which is what
    // the lock screen provides, so touching the sensor authenticates directly
    // and no prompt is ever shown.

    private fun fingerprintManager(): FingerprintManager? =
        getSystemService(Context.FINGERPRINT_SERVICE) as? FingerprintManager

    private fun fingerprintCapability(): Map<String, Any> {
        val manager = fingerprintManager()
        val hardware = manager?.isHardwareDetected == true
        val enrolled = hardware && manager?.hasEnrolledFingerprints() == true
        return mapOf("hardware" to hardware, "enrolled" to enrolled)
    }

    @Suppress("DEPRECATION")
    private fun startFingerprintScan() {
        val manager = fingerprintManager()
        if (manager == null || !manager.isHardwareDetected || !manager.hasEnrolledFingerprints()) {
            fingerprintEvents?.success(mapOf("type" to "unavailable"))
            return
        }

        if (powerManager?.isInteractive != true) {
            // The platform cancels an app's reader session the moment the panel
            // goes off, so arming now would only burn the caller's retry budget
            // and leave the sensor dead before the user has touched anything.
            fingerprintEvents?.success(mapOf("type" to "screenOff"))
            return
        }

        stopFingerprintScan()
        val signal = CancellationSignal()
        fingerprintCancellation = signal

        try {
            manager.authenticate(
                null,
                signal,
                0,
                object : FingerprintManager.AuthenticationCallback() {
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
                        // Partial read (finger moved, sensor dirty): stay armed.
                    }
                },
                null,
            )
            fingerprintEvents?.success(mapOf("type" to "listening"))
        } catch (error: Exception) {
            fingerprintCancellation = null
            fingerprintEvents?.success(
                mapOf(
                    "type" to "unavailable",
                    "message" to (error.message ?: "Fingerprint sensor unavailable"),
                )
            )
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
            val keyguardManager = getSystemService(Context.KEYGUARD_SERVICE) as? KeyguardManager
            if (keyguardManager == null || !keyguardManager.isDeviceSecure) {
                callback(true, null)
                return
            }

            val title = if (!appName.isNullOrEmpty()) "Launch $appName" else "Verify Identity"
            val subtitle = if (!appName.isNullOrEmpty()) "Verify identity to open $appName" else "Scan fingerprint, face, or enter credential"

            val promptBuilder = BiometricPrompt.Builder(this)
                .setTitle(title)
                .setSubtitle(subtitle)
                .setDescription("Scan fingerprint, face, or enter credential")

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                promptBuilder.setAllowedAuthenticators(
                    android.hardware.biometrics.BiometricManager.Authenticators.BIOMETRIC_STRONG or
                    android.hardware.biometrics.BiometricManager.Authenticators.DEVICE_CREDENTIAL
                )
            } else {
                @Suppress("DEPRECATION")
                promptBuilder.setNegativeButton(
                    "Cancel",
                    mainExecutor
                ) { _, _ ->
                    callback(false, "Canceled")
                }
            }

            val cancellationSignal = CancellationSignal()
            promptBuilder.build().authenticate(
                cancellationSignal,
                mainExecutor,
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
