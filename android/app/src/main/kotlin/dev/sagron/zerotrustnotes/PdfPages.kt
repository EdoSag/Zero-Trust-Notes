package dev.sagron.zerotrustnotes

import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.pdf.PdfRenderer
import android.os.ParcelFileDescriptor
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.concurrent.Executors

/**
 * Shows a PDF attached to a note (N-7) with Android's own PdfRenderer, so
 * no PDF library is added and nothing leaves the phone. Dart writes the
 * decrypted PDF to a file in the app's private cache, asks for pages as
 * PNGs here, and deletes the file when the viewer closes.
 */
object PdfPages {
    private val worker = Executors.newSingleThreadExecutor()

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        val path = call.argument<String>("path")
        if (path == null) {
            result.error("bad_args", "No path", null)
            return
        }
        when (call.method) {
            "pageCount" -> worker.execute {
                try {
                    open(path) { renderer -> post(result) { success(renderer.pageCount) } }
                } catch (e: Exception) {
                    post(result) { error("unreadable", e.toString(), null) }
                }
            }
            "renderPage" -> {
                val index = call.argument<Int>("index") ?: 0
                val width = (call.argument<Int>("width") ?: 1080).coerceIn(100, 3000)
                worker.execute {
                    try {
                        val png = open(path) { renderer ->
                            renderer.openPage(index).use { page ->
                                val height = (width.toLong() * page.height / page.width.coerceAtLeast(1))
                                    .toInt().coerceIn(1, 6000)
                                val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
                                bitmap.eraseColor(Color.WHITE)
                                page.render(bitmap, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
                                val out = ByteArrayOutputStream()
                                bitmap.compress(Bitmap.CompressFormat.PNG, 100, out)
                                bitmap.recycle()
                                out.toByteArray()
                            }
                        }
                        post(result) { success(png) }
                    } catch (e: Exception) {
                        post(result) { error("unreadable", e.toString(), null) }
                    }
                }
            }
            else -> result.notImplemented()
        }
    }

    private fun <T> open(path: String, use: (PdfRenderer) -> T): T {
        val fd = ParcelFileDescriptor.open(File(path), ParcelFileDescriptor.MODE_READ_ONLY)
        return PdfRenderer(fd).use { renderer -> use(renderer) }
    }

    private val main = android.os.Handler(android.os.Looper.getMainLooper())

    private fun post(result: MethodChannel.Result, reply: MethodChannel.Result.() -> Unit) {
        main.post { result.reply() }
    }
}
