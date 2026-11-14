package dev.sagron.zerotrustnotes.widgets

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import android.os.Bundle
import android.view.View
import android.widget.RemoteViews
import dev.sagron.zerotrustnotes.MainActivity
import dev.sagron.zerotrustnotes.R
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetPlugin
import es.antonborri.home_widget.HomeWidgetProvider

/**
 * New note: a round + at 1x1, a "Take a note" bar when made wider, and from
 * about three cells wide Keep-style quick capture buttons (checklist, voice
 * note, photo) in place of the + (W4). It never
 * touches note content; a tap launches the app straight into a blank note
 * editor (see WidgetLaunchListener in Dart). Shared Zero-Trust widget look
 * (Zero-Trust-Core/android-widget-kit).
 */
class QuickAddWidgetProvider : HomeWidgetProvider() {

    companion object {
        // From about two cells wide there is room for the bar.
        private const val BAR_MIN_WIDTH_DP = 140

        // Room for the hint plus three 40dp buttons.
        private const val CAPTURE_MIN_WIDTH_DP = 230
    }

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        appWidgetIds.forEach { widgetId ->
            appWidgetManager.updateAppWidget(
                widgetId,
                buildViews(context, appWidgetManager.getAppWidgetOptions(widgetId)),
            )
        }
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: Bundle,
    ) {
        appWidgetManager.updateAppWidget(appWidgetId, buildViews(context, newOptions))
    }

    private fun buildViews(context: Context, options: Bundle?): RemoteViews {
        val width = options?.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 0) ?: 0
        val bar = width >= BAR_MIN_WIDTH_DP
        val capture = width >= CAPTURE_MIN_WIDTH_DP
        val prefs = HomeWidgetPlugin.getData(context)
        val newNote = WidgetText.get(context, prefs, "new_note", R.string.widget_new_note)
        return RemoteViews(context.packageName, R.layout.widget_quick_add).apply {
            setTextViewText(
                R.id.quick_add_hint,
                WidgetText.get(context, prefs, "take_a_note", R.string.widget_take_a_note),
            )
            setContentDescription(R.id.quick_add_compact, newNote)
            setContentDescription(R.id.quick_add_bar_button, newNote)
            setViewVisibility(R.id.quick_add_compact, if (bar) View.GONE else View.VISIBLE)
            setViewVisibility(R.id.quick_add_bar, if (bar) View.VISIBLE else View.GONE)
            val captureVisibility = if (capture) View.VISIBLE else View.GONE
            setViewVisibility(R.id.quick_add_checklist, captureVisibility)
            setViewVisibility(R.id.quick_add_voice, captureVisibility)
            setViewVisibility(R.id.quick_add_photo, captureVisibility)
            setViewVisibility(R.id.quick_add_bar_button, if (capture) View.GONE else View.VISIBLE)
            setContentDescription(
                R.id.quick_add_checklist,
                WidgetText.get(context, prefs, "new_checklist", R.string.widget_new_checklist),
            )
            setContentDescription(
                R.id.quick_add_voice,
                WidgetText.get(context, prefs, "voice_note", R.string.widget_voice_note),
            )
            setContentDescription(
                R.id.quick_add_photo,
                WidgetText.get(context, prefs, "photo_note", R.string.widget_photo_note),
            )
            setOnClickPendingIntent(R.id.quick_add_widget_root, launch(context, "zerotrustnotes://new-note"))
            setOnClickPendingIntent(
                R.id.quick_add_checklist,
                launch(context, "zerotrustnotes://new-note?kind=checklist"),
            )
            setOnClickPendingIntent(R.id.quick_add_voice, launch(context, "zerotrustnotes://new-note?kind=voice"))
            setOnClickPendingIntent(R.id.quick_add_photo, launch(context, "zerotrustnotes://new-note?kind=photo"))
        }
    }

    // Each kind has its own URI, so Android keeps four separate PendingIntents.
    private fun launch(context: Context, uri: String) =
        HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java, Uri.parse(uri))
}
