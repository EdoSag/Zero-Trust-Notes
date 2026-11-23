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
 * Receives text, images and other files shared from other apps ("Share" →
 * "ZT Notes"), such as a PDF from ZT Browser's downloads.
 *
 * A separate, invisible activity rather than an intent filter on
 * [MainActivity]: a share would otherwise start a second copy of the app
 * inside the sharing app's task. This one copies what was shared, hands it
 * to the running (or starting) app through [SharedIntake], brings
 * [MainActivity] to the front and closes. The note is made there, after
 * unlock, where the files are encrypted and these plain copies deleted.
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
    private const val MAX_ITEMS = 20

    /** The core's attachment limit: a larger file couldn't be saved anyway. */
    private const val MAX_BYTES = 20_000_000L

    /** All of one share together, so a big share can't fill the phone. */
    private const val MAX_TOTAL_BYTES = 100_000_000L

    @Volatile
    private var pending: Map<String, Any?>? = null

    /** The folder of [pending]'s files, if it hasn't been taken yet. */
    @Volatile
    private var pendingDir: File? = null

    private fun dir(context: Context) = File(context.cacheDir, "shared_in")

    /** Deletes plain copies left by a share that never reached a note. */
    fun clearLeftovers(context: Context) {
        if (pending == null) dir(context).deleteRecursively()
    }

    /** Dart now owns the files and deletes each one once it's encrypted. */
    fun take(): Map<String, Any?>? {
        val share = pending
        pending = null
        pendingDir = null
        return share
    }

    fun receive(context: Context, intent: Intent) {
        // Each share gets its own folder: an earlier share may still be
        // importing its files. Only an earlier share nobody took is dropped.
        pendingDir?.deleteRecursively()
        pending = null
        pendingDir = null
        val dir = File(dir(context), UUID.randomUUID().toString())
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
        val files = mutableListOf<Map<String, Any?>>()
        var skipped = 0
        var total = 0L
        for (uri in uris) {
            if (images.size + files.size >= MAX_ITEMS) {
                skipped++
                continue
            }
            val copy = copyFile(context, uri, dir, intent.type, MAX_TOTAL_BYTES - total)
            if (copy == null) {
                skipped++
                continue
            }
            total += copy["size"] as Long
            if ((copy["mimeType"] as String).startsWith("image/")) images.add(copy) else files.add(copy)
        }

        if (text.isNullOrBlank() && images.isEmpty() && files.isEmpty() && skipped == 0) {
            dir.deleteRecursively()
            return
        }
        pendingDir = dir
        pending = mapOf(
            "text" to text,
            "subject" to subject,
            "images" to images,
            "files" to files,
            "skipped" to skipped,
        )
    }

    /**
     * Only `content://` files from other apps. A `file://` link, or one to
     * this app's own provider, could point at Notes' private files and copy
     * them into a note, so those are refused. Images go with the note's
     * pictures; anything else (a PDF, a document) is attached as a file.
     */
    private fun copyFile(
        context: Context,
        uri: Uri,
        dir: File,
        sharedType: String?,
        room: Long,
    ): Map<String, Any?>? {
        if (uri.scheme != "content") return null
        val authority = uri.authority ?: return null
        if (authority.startsWith(context.packageName)) return null
        val resolver = context.contentResolver
        val mime = resolver.getType(uri)
            ?: sharedType?.takeUnless { it.contains('*') }
            ?: "application/octet-stream"
        val limit = minOf(MAX_BYTES, room)

        var name: String? = null
        try {
            resolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use {
                if (it.moveToFirst() && !it.isNull(0)) name = it.getString(0)
            }
        } catch (_: Exception) {
            // The name is optional.
        }

        val out = File(dir, UUID.randomUUID().toString())
        var total = 0L
        try {
            val input = resolver.openInputStream(uri) ?: return null
            input.use { source ->
                out.outputStream().use { sink ->
                    val buffer = ByteArray(64 * 1024)
                    while (true) {
                        val read = source.read(buffer)
                        if (read < 0) break
                        total += read
                        if (total > limit) throw TooLarge()
                        sink.write(buffer, 0, read)
                    }
                }
            }
        } catch (_: Exception) {
            out.delete()
            return null
        }
        return mapOf("path" to out.absolutePath, "mimeType" to mime, "name" to name, "size" to total)
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
