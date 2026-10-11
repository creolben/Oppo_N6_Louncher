package com.launcher.chronofold.mylauncher

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.util.Log
import java.io.File

/**
 * The share/open entry point for PDFs.
 *
 * It owns no UI: it copies the single URI it was handed into
 * `cacheDir/imports/<timestamp>.pdf`, starts [MainActivity] with the path in
 * [EXTRA_SHARED_PDF_PATH], and finishes. It deliberately takes no persistable
 * URI permission and reads nothing but the given URI, so nothing here outlives
 * the copy it makes.
 *
 * The copy is rejected outright when it exceeds [MAX_BYTES]; a stream is read
 * chunk by chunk and the partial file is deleted the moment the cap is crossed,
 * so a malicious or oversized share cannot fill the cache.
 */
class ShareReceiverActivity : Activity() {
    companion object {
        /** The path handed to [MainActivity]; mirrored in Dart's bridge. */
        const val EXTRA_SHARED_PDF_PATH = "com.launcher.chronofold.SHARED_PDF_PATH"

        private const val TAG = "ChronoFold"
        private const val IMPORTS_DIR = "imports"

        /** Largest PDF this entry point will accept, in bytes (25 MB). */
        private const val MAX_BYTES = 25L * 1024 * 1024

        /** The private drop box every received/picked PDF is copied into. */
        fun importsDir(context: Context): File = File(context.cacheDir, IMPORTS_DIR)

        /**
         * Copies [uri]'s stream into the app's imports cache and returns the
         * absolute path, or null when the stream cannot be opened or crosses
         * [MAX_BYTES]. Shared by the share receiver and the in-app picker so
         * both import paths behave identically.
         */
        fun copyToImports(context: Context, uri: Uri): String? {
            val dir = importsDir(context)
            if (!dir.exists() && !dir.mkdirs()) return null
            val target = File(dir, "${System.currentTimeMillis()}.pdf")
            return try {
                val input = context.contentResolver.openInputStream(uri)
                    ?: return null
                input.use { source ->
                    target.outputStream().use { output ->
                        val buffer = ByteArray(64 * 1024)
                        var total = 0L
                        while (true) {
                            val read = source.read(buffer)
                            if (read < 0) break
                            total += read
                            if (total > MAX_BYTES) {
                                output.close()
                                target.delete()
                                Log.w(TAG, "CF_PDF: rejected a PDF over 25 MB")
                                return null
                            }
                            output.write(buffer, 0, read)
                        }
                    }
                }
                target.absolutePath
            } catch (e: Exception) {
                target.delete()
                Log.w(TAG, "CF_PDF: copying a PDF into the cache failed", e)
                null
            }
        }

        /**
         * Deletes imports older than one day. Called on every extract so the
         * cache cannot grow without bound; the file about to be read was just
         * copied and is newer than the cutoff.
         */
        fun cleanupOldImports(context: Context) {
            try {
                val dir = importsDir(context)
                if (!dir.isDirectory) return
                val cutoff = System.currentTimeMillis() - 24L * 60 * 60 * 1000
                dir.listFiles()?.forEach { file ->
                    if (file.isFile && file.lastModified() < cutoff) {
                        file.delete()
                    }
                }
            } catch (e: Exception) {
                Log.w(TAG, "CF_PDF: cleaning old imports failed", e)
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Only content:// URIs are accepted; a raw file path from another app
        // is never followed.
        val uri = extractUri(intent)?.takeIf { it.scheme == "content" }
        if (uri == null) {
            Log.w(TAG, "CF_PDF: no readable PDF URI in the share intent")
            finish()
            return
        }
        // The copy can be large or slow (cloud providers), so it must not run
        // on the main thread. The activity stays alive until it finishes,
        // because the URI read grant only lasts as long as this activity.
        Thread({
            val path = copyToImports(this@ShareReceiverActivity, uri)
            runOnUiThread { deliver(path) }
        }, "cf-pdf-share").start()
    }

    private fun deliver(path: String?) {
        if (isDestroyed) return
        if (path != null) {
            // An explicit component start; deliberately no ACTION_MAIN /
            // CATEGORY_HOME, because MainActivity treats those as a HOME press
            // and would close the shopping surface it is about to open.
            val launch = Intent(this, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP
                putExtra(EXTRA_SHARED_PDF_PATH, path)
            }
            startActivity(launch)
        } else {
            Log.w(TAG, "CF_PDF: no readable PDF URI in the share intent")
        }
        finish()
    }

    @Suppress("DEPRECATION")
    private fun extractUri(source: Intent?): Uri? {
        return when (source?.action) {
            Intent.ACTION_SEND -> source.getParcelableExtra(Intent.EXTRA_STREAM)
            Intent.ACTION_VIEW -> source.data
            else -> null
        }
    }
}
