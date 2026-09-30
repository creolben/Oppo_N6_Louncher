package com.launcher.chronofold.mylauncher

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.os.Bundle
import android.view.WindowManager
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * The lock surface raised over a foreign task on screen-off.
 *
 * It exists because re-asserting `showWhenLocked` on the HOME activity and
 * mounting its panel sent the user back to the launcher instead of the app they
 * were in. A separate activity in its own task, in front of exactly what was
 * underneath, dismisses to reveal that surface unchanged.
 *
 * It runs its own Flutter engine on the `lockMain` entry point and shares the
 * platform-channel implementation with [MainActivity] through
 * [LockSurfaceChannels], so the two lock surfaces cannot drift.
 */
class LockActivity : FlutterActivity() {
    private companion object {
        const val TAG = "ChronoFold"
    }

    private var lockSurface: LockSurfaceChannels? = null
    private var resumed = false
    private var userPresentReceiver: BroadcastReceiver? = null

    /**
     * Whether this activity has already been asked to leave.
     *
     * One fingerprint unlock produced three finish paths within milliseconds —
     * the Dart surface's request, the platform's `ACTION_USER_PRESENT`, and a
     * second request — and every finish after the first ran on a dying activity.
     * The first call wins; the rest are no-ops.
     */
    private var lockFinished = false

    override fun getDartEntrypointFunctionName(): String = "lockMain"

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Draw over the keyguard, and never wake the display. This activity
        // is raised AT screen-off, to already be there for the NEXT wake;
        // turning the screen on is the power key's or the fingerprint's job.
        // Measured on ColorOS 16 (CPH2765): while turnScreenOn was asserted,
        // every screen-off was followed by "wm_set_resumed_activity
        // .LockActivity" and "screen_toggled 1" ~7 ms later — a wake loop that
        // also made KEYCODE_SLEEP appear to do nothing. The flag is explicitly
        // denied so an install that had it set loses it.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(false)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED)
        }

        // The notification (when one was used to raise this activity) has done
        // its job the moment the activity is here; leaving it would post a
        // second, stale lock prompt on the next screen-off.
        (getSystemService(Context.NOTIFICATION_SERVICE) as? android.app.NotificationManager)
            ?.cancel(LockSurfaceChannels.LOCK_SURFACE_NOTIFICATION_ID)

        android.util.Log.d(TAG, "CF_LOCK: lock activity shown over foreign task")

        // The platform may satisfy the lock by another path — face unlock, the
        // bouncer — and this activity is not the thing that authenticated, so
        // it leaves as soon as the platform says the user is present.
        userPresentReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                if (intent?.action == Intent.ACTION_USER_PRESENT) {
                    finishLock("user present")
                }
            }
        }
        registerReceiver(
            userPresentReceiver,
            IntentFilter(Intent.ACTION_USER_PRESENT),
        )
    }

    override fun onResume() {
        // Earliest marker a manual power-key test can read: if the display is
        // already interactive at this log line, the surface was ready before
        // the screen came on; if not, the screen woke this activity up.
        val power = getSystemService(Context.POWER_SERVICE) as? android.os.PowerManager
        android.util.Log.d(
            TAG,
            "CF_LOCK: lock activity resumed interactive=${power?.isInteractive}",
        )
        super.onResume()
        resumed = true
        // Same re-read as the launcher: a theme change resumes this surface
        // too, and the lock panel must not keep the old accent.
        lockSurface?.pushSystemPaletteIfChanged()
    }

    override fun onPause() {
        resumed = false
        super.onPause()
    }

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val surface = LockSurfaceChannels(
            this,
            flutterEngine.dartExecutor.binaryMessenger,
            lockSurfaceHost,
        )
        // Publish before configuring: `startTarget` reaches back through
        // lockSurface as soon as the first method arrives.
        lockSurface = surface
        surface.configure()
    }

    override fun onDestroy() {
        lockSurface?.dispose()
        lockSurface = null
        userPresentReceiver?.let { unregisterReceiver(it) }
        userPresentReceiver = null
        super.onDestroy()
    }

    /**
     * A lock surface has no back: the platform keyguard is the only way out, so
     * every back gesture is swallowed rather than exposing the app underneath.
     * Dart's `PopScope(canPop: false)` is the same refusal one layer up.
     */
    @Suppress("DEPRECATION")
    override fun onBackPressed() {
        // Deliberately does not call super: super would finish (or pop the
        // Flutter route and then finish), which is exactly the leak this
        // activity exists to prevent.
    }

    /**
     * The single exit. Every finish path routes here, and only the first one
     * logs and calls [finish]; the rest return silently.
     */
    private fun finishLock(reason: String) {
        if (lockFinished) return
        lockFinished = true
        android.util.Log.d(TAG, "CF_LOCK: lock activity finished ($reason)")
        finish()
    }

    private val lockSurfaceHost = object : LockSurfaceChannels.Host {
        override fun isForeground(): Boolean = resumed

        override fun onForeignHandoff() {
            // The lock activity is not the launcher; it has no return bridge to
            // arm, so a handoff marker would only be misleading.
        }

        override fun onForeignHandoffFailed() {
            // Nothing to unwind.
        }

        override fun onFinishLock() {
            finishLock("requested by lock surface")
        }

        override fun setOverlayWhenLocked(enabled: Boolean) {
            // This activity is always a lock surface, and the manifest already
            // asserts showWhenLocked; there is nothing to toggle.
        }

        override fun startTarget(intent: Intent, onStarted: (Boolean) -> Unit) {
            // `startWhenUnlocked` already dismissed the keyguard; start the
            // target and leave so the user lands in it, not on a stale lock.
            val started = lockSurface?.startActivityQuietly(intent) ?: false
            onStarted(started)
            if (started) {
                finishLock("launching target")
            }
        }

        override fun onUnhandledMethod(call: MethodCall, result: MethodChannel.Result): Boolean =
            false
    }
}
