package dev.sagron.zerotrustnotes

import android.appwidget.AppWidgetManager
import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel

/**
 * `home_widget`'s own launch-intent machinery (`initiallyLaunchedFromHomeWidget`,
 * `widgetClicked`, `initiallyLaunchedFromHomeWidgetConfigure`) covers tap-to-launch
 * and the *first* widget-configure request out of the box. The one gap it leaves is
 * a second APPWIDGET_CONFIGURE request arriving while this activity is already
 * running (singleTop, so it's redelivered via onNewIntent rather than a fresh
 * onCreate) — [widgetConfigureChannel] exists solely to cover that case.
 */
class MainActivity : FlutterActivity() {
    private val widgetConfigureChannel = "dev.sagron.zerotrustnotes/widget_configure"

    override fun onNewIntent(intent: Intent) {
        // Ensure getIntent() reflects the latest intent — Activity does not
        // do this automatically, and home_widget's own
        // initiallyLaunchedFromHomeWidgetConfigure() reads getIntent().
        setIntent(intent)
        super.onNewIntent(intent)

        if (intent.action == AppWidgetManager.ACTION_APPWIDGET_CONFIGURE) {
            val appWidgetId = intent.getIntExtra(
                AppWidgetManager.EXTRA_APPWIDGET_ID,
                AppWidgetManager.INVALID_APPWIDGET_ID,
            )
            if (appWidgetId != AppWidgetManager.INVALID_APPWIDGET_ID) {
                val engine = flutterEngine ?: return
                MethodChannel(engine.dartExecutor.binaryMessenger, widgetConfigureChannel)
                    .invokeMethod("configure", appWidgetId.toString())
            }
        }
    }
}
