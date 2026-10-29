package dev.sagron.zerotrustnotes.widgets

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import android.os.Bundle
import android.widget.RemoteViews
import dev.sagron.zerotrustnotes.MainActivity
import dev.sagron.zerotrustnotes.R
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetPlugin
import es.antonborri.home_widget.HomeWidgetProvider

/**
 * Renders strictly from the pre-redacted SharedPreferences cache that
 * `HomeWidgetSyncService` (Dart) writes — this class never calls into Dart
 * and never blocks on the vault being unlocked. `widget_single_note_locked`
 * has no title/body TextView at all, so there is no view here that could
 * ever be populated with stale plaintext, even by mistake.
 */
class SingleNoteWidgetProvider : HomeWidgetProvider() {

    companion object {
        // Below this cell height, only the title fits comfortably.
        private const val LARGE_HEIGHT_DP_THRESHOLD = 110
    }

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        appWidgetIds.forEach { widgetId -> updateOne(context, appWidgetManager, widgetId, widgetData) }
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: Bundle,
    ) {
        super.onAppWidgetOptionsChanged(context, appWidgetManager, appWidgetId, newOptions)
        updateOne(context, appWidgetManager, appWidgetId, HomeWidgetPlugin.getData(context))
    }

    override fun onDeleted(context: Context, appWidgetIds: IntArray) {
        super.onDeleted(context, appWidgetIds)
        val editor = HomeWidgetPlugin.getData(context).edit()
        appWidgetIds.forEach { widgetId ->
            editor.remove("widget_${widgetId}_note_id")
            editor.remove("widget_${widgetId}_locked")
            editor.remove("widget_${widgetId}_title")
            editor.remove("widget_${widgetId}_body")
        }
        editor.apply()
    }

    private fun updateOne(
        context: Context,
        appWidgetManager: AppWidgetManager,
        widgetId: Int,
        widgetData: SharedPreferences,
    ) {
        val noteId = widgetData.getString("widget_${widgetId}_note_id", null)
        val locked = widgetData.getBoolean("widget_${widgetId}_locked", true)

        val clickUri = noteId?.let { Uri.parse("zerotrustnotes://note?id=$it") }
        val clickIntent = HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java, clickUri)

        // No noteId yet means this instance hasn't finished configuration
        // (shouldn't normally be reachable, since Android defers onUpdate
        // until the configure activity returns RESULT_OK) — fall back to
        // the same not-note-aware locked layout rather than guessing.
        val views = if (noteId == null || locked) {
            RemoteViews(context.packageName, R.layout.widget_single_note_locked).apply {
                setOnClickPendingIntent(R.id.single_note_widget_root, clickIntent)
            }
        } else {
            val title = widgetData.getString("widget_${widgetId}_title", null) ?: "(untitled)"
            val body = widgetData.getString("widget_${widgetId}_body", null) ?: ""
            val minHeight = appWidgetManager
                .getAppWidgetOptions(widgetId)
                .getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 0)
            val showBody = minHeight >= LARGE_HEIGHT_DP_THRESHOLD
            val layoutRes = if (showBody) {
                R.layout.widget_single_note_unlocked_large
            } else {
                R.layout.widget_single_note_unlocked_small
            }
            RemoteViews(context.packageName, layoutRes).apply {
                setOnClickPendingIntent(R.id.single_note_widget_root, clickIntent)
                setTextViewText(R.id.single_note_title, title)
                if (showBody) {
                    setTextViewText(R.id.single_note_body, body)
                }
            }
        }

        appWidgetManager.updateAppWidget(widgetId, views)
    }
}
