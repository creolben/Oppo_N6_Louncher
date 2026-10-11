package com.launcher.chronofold.mylauncher

import android.app.Notification
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import java.util.concurrent.CopyOnWriteArrayList

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
 *
 * The same grant is what makes notification badges visible. The service also
 * maintains a per-package badge count from the live notifications and publishes
 * it to every registered [addBadgeListener] listener. The count is derived from
 * the notification's own state — never from a private API — so it stays honest
 * when the grant is revoked (nothing is published at all).
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

        /**
         * Every live badge consumer. Same `CopyOnWriteArrayList` rationale as
         * the media listeners above: notification callbacks arrive on the
         * service's thread while an activity registers or drops its sink on the
         * main thread.
         */
        private val badgeListeners =
            java.util.concurrent.CopyOnWriteArrayList<(Map<String, Int>) -> Unit>()

        /** How long badge changes are coalesced before they cross the channel. */
        private const val BADGE_DEBOUNCE_MS = 250L

        /**
         * The last published per-package counts. Only non-zero entries are
         * kept, so a package whose last notification was removed disappears
         * rather than lingering at zero.
         */
        @Volatile
        private var badgeCounts: Map<String, Int> = emptyMap()

        fun addBadgeListener(listener: (Map<String, Int>) -> Unit) {
            if (!badgeListeners.contains(listener)) {
                badgeListeners.add(listener)
            }
            // A consumer that arrives after the last update still hears the
            // current state instead of waiting for the next notification.
            listener(currentBadgeCounts())
        }

        fun removeBadgeListener(listener: (Map<String, Int>) -> Unit) {
            badgeListeners.remove(listener)
        }

        /**
         * The current counts, or an empty map when notification access is not
         * granted. The grant is the platform's own gate — with no listener
         * bound there is no instance and nothing may be reported.
         */
        fun currentBadgeCounts(): Map<String, Int> {
            if (instance == null) return emptyMap()
            return badgeCounts
        }

        private fun publishBadgeCounts(counts: Map<String, Int>) {
            badgeCounts = counts
            for (listener in badgeListeners) {
                listener(counts)
            }
        }
    }

    private val mainHandler = Handler(Looper.getMainLooper())

    /**
     * Live notifications by key, maintained across post/remove so each refresh
     * recomputes from the real set instead of trying to add and subtract a
     * running total (a re-post of the same key is not a second notification).
     */
    private val activeByKey = LinkedHashMap<String, StatusBarNotification>()

    private val pendingBadgeRefresh = Runnable { refreshBadgeCounts() }

    override fun onListenerConnected() {
        super.onListenerConnected()
        instance = this
        activeByKey.clear()
        try {
            val current = activeNotifications
            if (current != null) {
                for (sbn in current) {
                    if (sbn != null) activeByKey[sbn.key] = sbn
                }
            }
        } catch (error: Exception) {
            android.util.Log.w("ChronoFold", "CF_BADGE: could not read active notifications", error)
        }
        notifySessionsMayHaveChanged()
        scheduleBadgeRefresh(immediate = true)
    }

    override fun onListenerDisconnected() {
        instance = null
        activeByKey.clear()
        mainHandler.removeCallbacks(pendingBadgeRefresh)
        // Nothing may be reported once the grant is gone; tell every consumer
        // so a stale badge cannot outlive the permission.
        publishBadgeCounts(emptyMap())
        notifySessionsMayHaveChanged()
        super.onListenerDisconnected()
    }

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        if (sbn != null) {
            activeByKey[sbn.key] = sbn
        }
        notifySessionsMayHaveChanged()
        scheduleBadgeRefresh()
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification?) {
        if (sbn != null) {
            activeByKey.remove(sbn.key)
        }
        notifySessionsMayHaveChanged()
        scheduleBadgeRefresh()
    }

    /**
     * Coalesces a burst of notification changes into one refresh. The first
     * change starts the 250 ms window; later changes in the window extend it so
     * a rapid sequence produces a single channel event.
     */
    private fun scheduleBadgeRefresh(immediate: Boolean = false) {
        mainHandler.removeCallbacks(pendingBadgeRefresh)
        if (immediate) {
            pendingBadgeRefresh.run()
        } else {
            mainHandler.postDelayed(pendingBadgeRefresh, BADGE_DEBOUNCE_MS)
        }
    }

    /**
     * Recomputes every package's badge count from the live notifications.
     *
     * A notification counts only when it is genuinely badgeable: not ongoing,
     * not a foreground-service notice, not a group summary, not this app's own,
     * and — the platform's own answer — `Ranking.canShowBadge()`. The
     * notification's `number` is the app's declared count and falls back to one
     * notification when it is absent or non-positive.
     */
    private fun refreshBadgeCounts() {
        val ranking = try {
            currentRanking
        } catch (error: Exception) {
            android.util.Log.w("ChronoFold", "CF_BADGE: ranking unavailable", error)
            null
        }

        val counts = HashMap<String, Int>()
        for (sbn in activeByKey.values) {
            if (!countsForBadge(sbn, ranking)) continue
            val number = sbn.notification?.number ?: 0
            counts[sbn.packageName] = (counts[sbn.packageName] ?: 0) + if (number > 0) number else 1
        }
        publishBadgeCounts(counts.filterValues { it > 0 })
    }

    private fun countsForBadge(
        sbn: StatusBarNotification,
        ranking: NotificationListenerService.RankingMap?,
    ): Boolean {
        if (sbn.packageName == packageName) return false

        val notification: Notification = sbn.notification ?: return false
        val flags = notification.flags
        if (flags and Notification.FLAG_ONGOING_EVENT != 0) return false
        if (flags and Notification.FLAG_FOREGROUND_SERVICE != 0) return false
        if (flags and Notification.FLAG_GROUP_SUMMARY != 0) return false

        // canShowBadge() is API 26+, which is this app's minSdk, but the guard
        // keeps the read honest on any device that reports an older platform.
        // RankingMap fills a Ranking out-parameter rather than returning one.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val outRanking = NotificationListenerService.Ranking()
            val ranked = try {
                ranking?.getRanking(sbn.key, outRanking) == true
            } catch (error: Exception) {
                false
            }
            if (!ranked || !outRanking.canShowBadge()) return false
        }
        return true
    }
}
