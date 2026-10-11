package com.launcher.chronofold.mylauncher

import android.app.Activity
import android.app.AlertDialog
import android.content.Context
import android.content.pm.LauncherApps
import android.os.Build
import android.os.Bundle

/**
 * The system's "pin this shortcut?" surface.
 *
 * Android delivers a pin request by starting an activity that declares
 * `android.content.pm.action.CONFIRM_PIN_SHORTCUT`, with the request attached to
 * the launch intent. This activity is that receiver: it asks the user to confirm
 * the one shortcut the request carries, and accepts only when they say yes.
 *
 * It is exported because the platform (and the requesting app) start it across
 * processes, but it advertises no LAUNCHER category and has its own task, so it
 * never appears in the launcher UI or the launcher's task. App-widget pin
 * requests are deliberately ignored here (finished without accepting) — this
 * launcher's home widgets are the galaxy, not Android app widgets.
 */
class ShortcutPinActivity : Activity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            finish()
            return
        }

        val request = try {
            (getSystemService(Context.LAUNCHER_APPS_SERVICE) as? LauncherApps)
                ?.getPinItemRequest(intent)
        } catch (error: Exception) {
            android.util.Log.w("ChronoFold", "CF_SHORTCUTS: pin request unreadable", error)
            null
        }

        // A request is offered once and only while it is valid; anything else
        // (a re-delivery, a revoked request, another request type) closes
        // without accepting.
        if (request == null ||
            !request.isValid ||
            request.requestType != LauncherApps.PinItemRequest.REQUEST_TYPE_SHORTCUT
        ) {
            finish()
            return
        }

        val info = request.shortcutInfo
        val label = info?.shortLabel?.toString()?.takeIf { it.isNotBlank() }
            ?: info?.longLabel?.toString()?.takeIf { it.isNotBlank() }
            ?: info?.id
            ?: "shortcut"

        AlertDialog.Builder(this)
            .setTitle("Add $label to ChronoFold?")
            .setPositiveButton("Add") { _, _ ->
                // Re-check on accept: the request can expire between the dialog
                // appearing and the tap.
                if (request.isValid) {
                    try {
                        request.accept()
                    } catch (error: Exception) {
                        android.util.Log.w(
                            "ChronoFold",
                            "CF_SHORTCUTS: pin accept failed",
                            error,
                        )
                    }
                }
                finish()
            }
            .setNegativeButton("Cancel") { _, _ -> finish() }
            .setOnCancelListener { finish() }
            .show()
    }
}
