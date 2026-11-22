package dev.sagron.zerotrustnotes

import android.appwidget.AppWidgetManager
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.speech.SpeechRecognizer
import dev.sagron.zerotrustnotes.widgets.ChecklistTicks
import es.antonborri.home_widget.HomeWidgetPlugin
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * FlutterFragmentActivity, not FlutterActivity: the biometric prompt
 * (local_auth) needs a FragmentActivity.
 *
 * `home_widget`'s own launch-intent machinery (`initiallyLaunchedFromHomeWidget`,
 * `widgetClicked`, `initiallyLaunchedFromHomeWidgetConfigure`) covers tap-to-launch
 * and the *first* widget-configure request out of the box. The one gap it leaves is
 * a second APPWIDGET_CONFIGURE request arriving while this activity is already
 * running (singleTop, so it's redelivered via onNewIntent rather than a fresh
 * onCreate) — [widgetConfigureChannel] exists solely to cover that case.
 */
class MainActivity : FlutterFragmentActivity() {
    companion object {
        /** Sent by [ShareReceiverActivity] when something was shared to Notes. */
        const val ACTION_SHARED = "dev.sagron.zerotrustnotes.SHARED"
    }

    private var widgetConfigureChannel: MethodChannel? = null

    /** Hands shares from [ShareReceiverActivity] to Dart (see ShareIntentListener). */
    private var shareChannel: MethodChannel? = null

    /** ZT Keyboard is waiting for the user to pick a text here (see [TextPick]). */
    private var pickingText = false

    override fun onCreate(savedInstanceState: Bundle?) {
        if (intent?.action != ACTION_SHARED) SharedIntake.clearLeftovers(applicationContext)
        super.onCreate(savedInstanceState)
        if (TextPick.isPick(intent)) {
            // Only another Zero-Trust app may ask; anyone else gets nothing.
            if (TextPick.callerAllowed(this)) pickingText = true else TextPick.answer(this, null)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        widgetConfigureChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "dev.sagron.zerotrustnotes/widget_configure",
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    // Which widget is being set up: a Note or a Checklist widget.
                    "providerOf" -> {
                        val id = call.argument<String>("id")?.toIntOrNull()
                        val info = id?.let { AppWidgetManager.getInstance(this).getAppWidgetInfo(it) }
                        result.success(info?.provider?.className)
                    }
                    else -> result.notImplemented()
                }
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "dev.sagron.zerotrustnotes/checklist_widget",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                // Ticks made on Checklist widgets since the last time (see ChecklistTicks).
                "takeTicks" -> result.success(ChecklistTicks.take(HomeWidgetPlugin.getData(applicationContext)))
                else -> result.notImplemented()
            }
        }
        shareChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "dev.sagron.zerotrustnotes/share",
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "takeShare" -> result.success(SharedIntake.take())
                    else -> result.notImplemented()
                }
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "dev.sagron.zerotrustnotes/text_pick",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "isPick" -> result.success(pickingText)
                "finish" -> {
                    // Answers only the screen the keyboard itself opened.
                    if (pickingText) {
                        pickingText = false
                        TextPick.answer(this, call.argument<String>("text"))
                    }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "dev.sagron.zerotrustnotes/speech",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                // Voice notes must never send audio to a server. speech_to_text
                // only uses Android's on-device recognizer when this is true;
                // otherwise it falls back to the default (possibly online) one,
                // so Notes refuses to listen instead.
                "onDeviceAvailable" -> result.success(
                    Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
                        SpeechRecognizer.isOnDeviceRecognitionAvailable(applicationContext),
                )
                else -> result.notImplemented()
            }
        }
        // PDFs attached to notes, shown page by page (N-7).
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "dev.sagron.zerotrustnotes/pdf",
        ).setMethodCallHandler { call, result -> PdfPages.handle(call, result) }
    }

    override fun onNewIntent(intent: Intent) {
        // Ensure getIntent() reflects the latest intent — Activity does not
        // do this automatically, and home_widget's own
        // initiallyLaunchedFromHomeWidgetConfigure() reads getIntent().
        // A pick request is only honoured when it opens its own screen (onCreate), where
        // Android tells who is asking.
        if (TextPick.isPick(intent)) return
        setIntent(intent)
        super.onNewIntent(intent)

        if (intent.action == ACTION_SHARED) {
            shareChannel?.invokeMethod("shareReceived", null)
        }

        if (intent.action == AppWidgetManager.ACTION_APPWIDGET_CONFIGURE) {
            val appWidgetId = intent.getIntExtra(
                AppWidgetManager.EXTRA_APPWIDGET_ID,
                AppWidgetManager.INVALID_APPWIDGET_ID,
            )
            if (appWidgetId != AppWidgetManager.INVALID_APPWIDGET_ID) {
                widgetConfigureChannel?.invokeMethod("configure", appWidgetId.toString())
            }
        }
    }
}
