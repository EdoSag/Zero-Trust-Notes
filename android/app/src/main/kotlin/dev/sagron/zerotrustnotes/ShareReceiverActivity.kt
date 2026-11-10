package dev.sagron.zerotrustnotes

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.OpenableColumns
import java.io.File
import java.util.UUID

/**
 * Receives text and images shared from other apps ("Share" → "ZT Notes").
 *
 * A separate, invisible activity rather than an intent filter on
 * [MainActivity]: a share would otherwise start a second copy of the app
 * inside the sharing app's task. This one copies what was shared, hands it
 * to the running (or starting) app through [SharedIntake], brings
 * [MainActivity] to the front and closes. The note is made there, after
 * unlock, where the images are encrypted and these plain copies deleted.
 */
class ShareReceiverActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val shared = intent
        // Copying a few large photos can take a moment: not on the UI thread.
        Thread {
            try {
                SharedIntake.receive(applicationContext, shared)
            } catch (_: Exception) {
                // Nothing usable was shared; the app still opens.
            }
            runOnUiThread {
                startActivity(
                    Intent(this, MainActivity::class.java).apply {
                        action = MainActivity.ACTION_SHARED
                        addFlags(
                            Intent.FLAG_ACTIVITY_NEW_TASK or
                                Intent.FLAG_ACTIVITY_CLEAR_TOP or
                                Intent.FLAG_ACTIVITY_SINGLE_TOP,
                        )
                    },
                )
                finish()
            }
        }.start()
    }
}

/** The latest share, until the Dart side takes it. */
object SharedIntake {
    private const val MAX_IMAGES = 20

    /** The core's attachment limit: a larger image couldn't be saved anyway. */
    private const val MAX_BYTES = 20_000_000L

    @Volatile
    private var pending: Map<String, Any?>? = null

    private fun dir(context: Context) = File(context.cacheDir, "shared_in")

    /** Deletes plain copies left by a share that never reached a note. */
    fun clearLeftovers(context: Context) {
        if (pending == null) dir(context).deleteRecursively()
    }

    fun take(): Map<String, Any?>? {
        val share = pending
        pending = null
        return share
    }

    fun receive(context: Context, intent: Intent) {
        val dir = dir(context)
        dir.deleteRecursively()
        dir.mkdirs()

        val text = intent.getCharSequenceExtra(Intent.EXTRA_TEXT)?.toString()
        val subject = intent.getStringExtra(Intent.EXTRA_SUBJECT)
            ?: intent.getStringExtra(Intent.EXTRA_TITLE)

        val uris = when (intent.action) {
            Intent.ACTION_SEND -> listOfNotNull(streamOf(intent))
            Intent.ACTION_SEND_MULTIPLE -> streamsOf(intent)
            else -> emptyList()
        }

        val images = mutableListOf<Map<String, Any?>>()
        var skipped = 0
        for (uri in uris) {
            if (images.size >= MAX_IMAGES) {
                skipped++
                continue
            }
            val image = copyImage(context, uri, dir)
            if (image == null) skipped++ else images.add(image)
        }

        if (text.isNullOrBlank() && images.isEmpty() && skipped == 0) return
        pending = mapOf(
            "text" to text,
            "subject" to subject,
            "images" to images,
            "skipped" to skipped,
        )
    }

    /**
     * Only `content://` images from other apps. A `file://` link, or one to
     * this app's own provider, could point at Notes' private files and copy
     * them into a note, so those are refused.
     */
    private fun copyImage(context: Context, uri: Uri, dir: File): Map<String, Any?>? {
        if (uri.scheme != "content") return null
        val authority = uri.authority ?: return null
        if (authority.startsWith(context.packageName)) return null
        val resolver = context.contentResolver
        val mime = resolver.getType(uri) ?: return null
        if (!mime.startsWith("image/")) return null

        var name: String? = null
        try {
            resolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use {
                if (it.moveToFirst() && !it.isNull(0)) name = it.getString(0)
            }
        } catch (_: Exception) {
            // The name is optional.
        }

        val out = File(dir, UUID.randomUUID().toString())
        try {
            val input = resolver.openInputStream(uri) ?: return null
            input.use { source ->
                out.outputStream().use { sink ->
                    val buffer = ByteArray(64 * 1024)
                    var total = 0L
                    while (true) {
                        val read = source.read(buffer)
                        if (read < 0) break
                        total += read
                        if (total > MAX_BYTES) throw TooLarge()
                        sink.write(buffer, 0, read)
                    }
                }
            }
        } catch (_: Exception) {
            out.delete()
            return null
        }
        return mapOf("path" to out.absolutePath, "mimeType" to mime, "name" to name)
    }

    private class TooLarge : Exception()

    private fun streamOf(intent: Intent): Uri? =
        if (Build.VERSION.SDK_INT >= 33) {
            intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
        } else {
            @Suppress("DEPRECATION")
            intent.getParcelableExtra(Intent.EXTRA_STREAM)
        }

    private fun streamsOf(intent: Intent): List<Uri> =
        if (Build.VERSION.SDK_INT >= 33) {
            intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM, Uri::class.java)
        } else {
            @Suppress("DEPRECATION")
            intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM)
        } ?: emptyList()
}
