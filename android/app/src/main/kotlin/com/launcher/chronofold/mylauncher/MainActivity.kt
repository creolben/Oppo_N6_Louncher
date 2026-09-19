package com.launcher.chronofold.mylauncher

import android.content.Context
import android.content.Intent
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
import android.os.CancellationSignal
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

    private val backgroundExecutor = Executors.newSingleThreadExecutor()
    private var sensorManager: SensorManager? = null
    private var hingeSensor: Sensor? = null
    private var accelSensor: Sensor? = null
    private var screenReceiver: BroadcastReceiver? = null
    private var packageReceiver: BroadcastReceiver? = null
    private var appsMethodChannel: MethodChannel? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.setBackgroundDrawable(android.graphics.drawable.ColorDrawable(android.graphics.Color.parseColor("#020306")))
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
                if (intent?.action == Intent.ACTION_SCREEN_OFF) {
                    runOnUiThread {
                        appsMethodChannel?.invokeMethod("lockScreen", null)
                    }
                }
            }
        }
        val filter = IntentFilter().apply {
            addAction(Intent.ACTION_SCREEN_OFF)
            addAction(Intent.ACTION_SCREEN_ON)
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
        screenReceiver?.let { unregisterReceiver(it) }
        packageReceiver?.let { unregisterReceiver(it) }
        super.onDestroy()
    }

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        sensorManager = getSystemService(Context.SENSOR_SERVICE) as? SensorManager
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
                            val success = launchApplication(packageName, activityName)
                            result.success(success)
                        } else {
                            result.error("INVALID_ARGS", "packageName is required", null)
                        }
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

    private fun drawableToByteArray(drawable: Drawable): ByteArray {
        val bitmap = if (drawable is BitmapDrawable && drawable.bitmap != null) {
            drawable.bitmap
        } else {
            val width = if (drawable.intrinsicWidth > 0) drawable.intrinsicWidth else 96
            val height = if (drawable.intrinsicHeight > 0) drawable.intrinsicHeight else 96
            val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
            val canvas = Canvas(bitmap)
            drawable.setBounds(0, 0, canvas.width, canvas.height)
            drawable.draw(canvas)
            bitmap
        }

        val stream = ByteArrayOutputStream()
        bitmap.compress(Bitmap.CompressFormat.PNG, 90, stream)
        return stream.toByteArray()
    }

    private fun launchApplication(packageName: String, activityName: String?): Boolean {
        return try {
            val intent = if (activityName != null && activityName.isNotEmpty()) {
                Intent().apply {
                    setClassName(packageName, activityName)
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED
                }
            } else {
                packageManager.getLaunchIntentForPackage(packageName)?.apply {
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED
                }
            }

            if (intent != null) {
                startActivity(intent)
                true
            } else {
                false
            }
        } catch (e: Exception) {
            false
        }
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
}
