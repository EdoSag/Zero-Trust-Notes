package dev.sagron.zerotrustnotes.widgets

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.net.Uri
import android.os.Bundle
import android.view.View
import android.widget.RemoteViews
import androidx.core.widget.RemoteViewsCompat
import dev.sagron.zerotrustnotes.MainActivity
import dev.sagron.zerotrustnotes.R
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetPlugin
import es.antonborri.home_widget.HomeWidgetProvider
import org.json.JSONArray

/**
 * Notes list (W4): the newest notes, pinned first, in a scrolling list, or
 * only the pinned ones (tap the title to switch; each widget remembers its
 * choice). Tap a note to open it, + for a new note.
 *
 * Renders only what HomeWidgetSyncService (Dart) wrote under
 * `notes_list_widget_json`, which exists only while "Show details on the
 * home screen" is on; otherwise the widget shows a lock and says how to
 * turn it on. It never reads the vault.
 */
class NotesListWidgetProvider : HomeWidgetProvider() {

    companion object {
        const val ACTION_SWITCH_VIEW = "dev.sagron.zerotrustnotes.widgets.NOTES_LIST_SWITCH_VIEW"
        private const val ITEMS_KEY = "notes_list_widget_json"
        private const val DETAILS_KEY = "notes_widget_details"

        private fun pinnedKey(widgetId: Int) = "notes_list_widget_${widgetId}_pinned"
    }

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        appWidgetIds.forEach { update(context, appWidgetManager, it, widgetData) }
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: Bundle,
    ) {
        update(context, appWidgetManager, appWidgetId, HomeWidgetPlugin.getData(context))
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == ACTION_SWITCH_VIEW) {
            val widgetId = intent.getIntExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, AppWidgetManager.INVALID_APPWIDGET_ID)
            if (widgetId == AppWidgetManager.INVALID_APPWIDGET_ID) return
            val prefs = HomeWidgetPlugin.getData(context)
            prefs.edit().putBoolean(pinnedKey(widgetId), !prefs.getBoolean(pinnedKey(widgetId), false)).apply()
            update(context, AppWidgetManager.getInstance(context), widgetId, prefs)
            return
        }
        super.onReceive(context, intent)
    }

    override fun onDeleted(context: Context, appWidgetIds: IntArray) {
        super.onDeleted(context, appWidgetIds)
        val editor = HomeWidgetPlugin.getData(context).edit()
        appWidgetIds.forEach { editor.remove(pinnedKey(it)) }
        editor.apply()
    }

    private fun update(
        context: Context,
        manager: AppWidgetManager,
        widgetId: Int,
        prefs: SharedPreferences,
    ) {
        val pinnedOnly = prefs.getBoolean(pinnedKey(widgetId), false)
        val detailsOn = prefs.getBoolean(DETAILS_KEY, false)
        val json = if (detailsOn) prefs.getString(ITEMS_KEY, null) else null
        val views = RemoteViews(context.packageName, R.layout.widget_notes_list)

        views.setTextViewText(
            R.id.notes_list_title,
            if (pinnedOnly) {
                WidgetText.get(context, prefs, "pinned", R.string.widget_pinned)
            } else {
                WidgetText.get(context, prefs, "notes", R.string.widget_notes)
            },
        )
        views.setContentDescription(
            R.id.notes_list_switch,
            WidgetText.get(context, prefs, "switch_view", R.string.widget_switch_view),
        )
        views.setContentDescription(
            R.id.notes_list_add,
            WidgetText.get(context, prefs, "new_note", R.string.widget_new_note),
        )
        views.setOnClickPendingIntent(
            R.id.notes_list_app_icon,
            HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java, Uri.parse("zerotrustnotes://open")),
        )
        views.setOnClickPendingIntent(
            R.id.notes_list_add,
            HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java, Uri.parse("zerotrustnotes://new-note")),
        )
        val switchIntent = Intent(context, NotesListWidgetProvider::class.java).apply {
            action = ACTION_SWITCH_VIEW
            putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, widgetId)
            // One PendingIntent per widget.
            data = Uri.parse("zerotrustnotes://widget/$widgetId/switch")
        }
        views.setOnClickPendingIntent(
            R.id.notes_list_switch,
            PendingIntent.getBroadcast(
                context,
                widgetId,
                switchIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            ),
        )

        if (json == null) {
            // Nothing the widget may show: a lock and how to change that.
            views.setViewVisibility(R.id.notes_list, View.GONE)
            views.setViewVisibility(R.id.notes_list_empty, View.GONE)
            views.setViewVisibility(R.id.notes_list_locked, View.VISIBLE)
            views.setTextViewText(
                R.id.notes_list_locked_text,
                if (detailsOn) {
                    WidgetText.get(context, prefs, "open_to_see", R.string.widget_open_to_see_notes)
                } else {
                    WidgetText.get(context, prefs, "details_off", R.string.widget_notes_hidden)
                },
            )
            views.setOnClickPendingIntent(
                R.id.notes_list_locked,
                HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java, Uri.parse("zerotrustnotes://open")),
            )
            // Drop rows an earlier update gave the list.
            RemoteViewsCompat.setRemoteAdapter(
                context,
                views,
                widgetId,
                R.id.notes_list,
                RemoteViewsCompat.RemoteCollectionItems.Builder().build(),
            )
            manager.updateAppWidget(widgetId, views)
            return
        }

        views.setViewVisibility(R.id.notes_list_locked, View.GONE)
        views.setViewVisibility(R.id.notes_list, View.VISIBLE)
        views.setTextViewText(
            R.id.notes_list_empty,
            if (pinnedOnly) {
                WidgetText.get(context, prefs, "no_pinned", R.string.widget_no_pinned)
            } else {
                WidgetText.get(context, prefs, "no_notes", R.string.widget_no_notes)
            },
        )
        views.setEmptyView(R.id.notes_list, R.id.notes_list_empty)
        views.setPendingIntentTemplate(R.id.notes_list, WidgetLaunch.rowTemplate(context, widgetId))

        val untitled = WidgetText.get(context, prefs, "untitled", R.string.widget_untitled)
        val items = RemoteViewsCompat.RemoteCollectionItems.Builder()
            .setHasStableIds(true)
            .setViewTypeCount(1)
        val notes = try { JSONArray(json) } catch (e: Exception) { JSONArray() }
        for (i in 0 until notes.length()) {
            val note = notes.optJSONObject(i) ?: continue
            val id = note.optString("id")
            if (id.isEmpty()) continue
            val pinned = note.optBoolean("p", false)
            if (pinnedOnly && !pinned) continue
            val title = note.optString("t")
            val body = note.optString("b")
            val row = RemoteViews(context.packageName, R.layout.widget_notes_list_item).apply {
                setTextViewText(R.id.note_row_title, if (title.isEmpty() && body.isEmpty()) untitled else title)
                setViewVisibility(
                    R.id.note_row_title,
                    if (title.isEmpty() && body.isNotEmpty()) View.GONE else View.VISIBLE,
                )
                setTextViewText(R.id.note_row_body, body)
                setViewVisibility(R.id.note_row_body, if (body.isEmpty()) View.GONE else View.VISIBLE)
                // The pin marks pinned notes among the others.
                setViewVisibility(R.id.note_row_pin, if (pinned && !pinnedOnly) View.VISIBLE else View.GONE)
                setOnClickFillInIntent(
                    R.id.note_row,
                    WidgetLaunch.rowFillIn("zerotrustnotes://note?id=" + Uri.encode(id)),
                )
            }
            items.addItem(id.hashCode().toLong(), row)
        }
        RemoteViewsCompat.setRemoteAdapter(context, views, widgetId, R.id.notes_list, items.build())
        manager.updateAppWidget(widgetId, views)
    }
}
