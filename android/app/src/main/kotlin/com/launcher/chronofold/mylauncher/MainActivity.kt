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

    private val backgroundExecutor = Executors.newSingleThreadExecutor()
    private var sensorManager: SensorManager? = null
    private var hingeSensor: Sensor? = null

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        sensorManager = getSystemService(Context.SENSOR_SERVICE) as? SensorManager
        // TYPE_HINGE_ANGLE is 36
        hingeSensor = sensorManager?.getDefaultSensor(36)

        // MethodChannel for App querying & launching
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, APPS_CHANNEL)
            .setMethodCallHandler { call, result ->
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
                    "openHomeSettings" -> {
                        val intent = Intent(Settings.ACTION_HOME_SETTINGS)
                        intent.flags = Intent.FLAG_ACTIVITY_NEW_TASK
                        startActivity(intent)
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
}
