package com.launcher.chronofold.mylauncher

import android.accessibilityservice.AccessibilityService
import android.content.Intent
import android.os.Build
import android.view.accessibility.AccessibilityEvent

/**
 * ChronoFold's optional accessibility service.
 *
 * It exists for exactly three global actions — open the notification shade,
 * lock the screen and show recent apps — and nothing else. Its metadata (see
 * `res/xml/chronofold_accessibility_service.xml`) requests no event types,
 * `canRetrieveWindowContent` false and `canPerformGestures` false, so the
 * platform never hands it window content and it never asks for any. The service
 * is off until the user enables it in Android's accessibility settings;
 * ChronoFold only ever opens that settings page and never nags.
 *
 * Public Android APIs only: no root, no SystemUI hooks, no hidden APIs.
 */
class ChronoFoldAccessibilityService : AccessibilityService() {

    companion object {
        private const val TAG = "ChronoFold"

        /**
         * The connected instance, or null while the user has not enabled the
         * service.
         *
         * `@Volatile` because [onServiceConnected], [onUnbind] and [onDestroy]
         * run on the main thread while the launcher's method channel reads this
         * from whichever thread the engine uses. Set in [onServiceConnected] and
         * cleared in [onUnbind]/[onDestroy], so a disconnected service can never
         * be mistaken for an enabled one.
         */
        @Volatile
        private var connected: ChronoFoldAccessibilityService? = null

        /** The connected service, or null when it is not enabled. */
        val instance: ChronoFoldAccessibilityService?
            get() = connected

        /** The three actions this service is allowed to perform. */
        const val ACTION_NOTIFICATIONS = "notifications"
        const val ACTION_LOCK_SCREEN = "lockScreen"
        const val ACTION_RECENTS = "recents"
    }

    override fun onServiceConnected() {
        super.onServiceConnected()
        connected = this
    }

    /**
     * Runs one of the three whitelisted global actions, or reports false.
     *
     * Anything outside the whitelist is refused rather than mapped onto some
     * other action, and lock-screen reports false below API 28, where the
     * platform has no such global action. Never throws: a refusal by the
     * platform is a plain "no" for the caller.
     */
    fun performGlobal(action: String?): Boolean {
        val globalAction = when (action) {
            ACTION_NOTIFICATIONS -> GLOBAL_ACTION_NOTIFICATIONS
            ACTION_LOCK_SCREEN -> {
                if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P) return false
                GLOBAL_ACTION_LOCK_SCREEN
            }
            ACTION_RECENTS -> GLOBAL_ACTION_RECENTS
            else -> return false
        }
        return try {
            performGlobalAction(globalAction)
        } catch (error: Exception) {
            android.util.Log.d(TAG, "CF_A11Y: global action refused", error)
            false
        }
    }

    /**
     * Deliberately empty.
     *
     * The service subscribes to no accessibility event types and retrieves no
     * window content, so there is nothing to handle and nothing is read.
     */
    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        // No event types are requested; nothing arrives here.
    }

    /** Deliberately empty: nothing this service does can be interrupted. */
    override fun onInterrupt() {
        // Nothing to interrupt.
    }

    override fun onUnbind(intent: Intent?): Boolean {
        connected = null
        return super.onUnbind(intent)
    }

    override fun onDestroy() {
        connected = null
        super.onDestroy()
    }
}
