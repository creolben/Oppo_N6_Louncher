package com.launcher.chronofold.mylauncher

import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification

/**
 * The one thing `MediaSessionManager.getActiveSessions()` needs: an enabled
 * notification listener.
 *
 * There is no other way to see another app's media session without a
 * privileged permission, so the lock screen's now-playing card cannot exist
 * until the user grants notification access once (P5 asks for it; the lock
 * screen itself never nags).
 *
 * This service is deliberately minimal — it reads nothing and shows nothing.
 * It exists only to make [android.media.session.MediaSessionManager] answer,
 * and to tell every live lock surface ([LockSurfaceChannels]) when the set of
 * sessions may have changed so the active one can be re-resolved. Notification
 * post/remove is a coarse trigger on purpose: it cannot miss a media-session
 * change, and the actual metadata always comes from the MediaController, never
 * from a notification.
 */
class MediaListenerService : NotificationListenerService() {

    companion object {
        /**
         * The connected listener, or null while notification access is
         * revoked. MainActivity checks this before touching MediaSessionManager
         * so a missing grant fails cheaply instead of throwing.
         */
        @Volatile
        var instance: MediaListenerService? = null
            private set

        /**
         * Everyone who wants to know that the active media session may have
         * changed. A list rather than a single callback because two activities
         * can be alive at once — MainActivity and the LockActivity it raised
         * over a foreign task — and each hosts its own media EventChannel.
         *
         * `CopyOnWriteArrayList` because notifications are delivered on the
         * service's thread while listeners are added/removed on the activity's
         * main thread; iteration must not race a write.
         */
        private val sessionsMayHaveChangedListeners =
            java.util.concurrent.CopyOnWriteArrayList<() -> Unit>()

        fun addSessionsMayHaveChangedListener(listener: () -> Unit) {
            if (!sessionsMayHaveChangedListeners.contains(listener)) {
                sessionsMayHaveChangedListeners.add(listener)
            }
        }

        fun removeSessionsMayHaveChangedListener(listener: () -> Unit) {
            sessionsMayHaveChangedListeners.remove(listener)
        }

        private fun notifySessionsMayHaveChanged() {
            for (listener in sessionsMayHaveChangedListeners) {
                listener()
            }
        }
    }

    override fun onListenerConnected() {
        super.onListenerConnected()
        instance = this
        notifySessionsMayHaveChanged()
    }

    override fun onListenerDisconnected() {
        instance = null
        notifySessionsMayHaveChanged()
        super.onListenerDisconnected()
    }

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        notifySessionsMayHaveChanged()
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification?) {
        notifySessionsMayHaveChanged()
    }
}
