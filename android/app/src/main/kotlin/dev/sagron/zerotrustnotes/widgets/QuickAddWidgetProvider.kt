package dev.sagron.zerotrustnotes.widgets

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import android.widget.RemoteViews
import dev.sagron.zerotrustnotes.MainActivity
import dev.sagron.zerotrustnotes.R
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

/**
 * A 1x1 icon that never touches note content — tapping it just launches the
 * app straight into a blank note editor (see WidgetLaunchListener in Dart).
 */
class QuickAddWidgetProvider : HomeWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        appWidgetIds.forEach { widgetId ->
            val views = RemoteViews(context.packageName, R.layout.widget_quick_add).apply {
                val pendingIntent = HomeWidgetLaunchIntent.getActivity(
                    context,
                    MainActivity::class.java,
                    Uri.parse("zerotrustnotes://new-note"),
                )
                setOnClickPendingIntent(R.id.quick_add_widget_root, pendingIntent)
            }
            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }
}
