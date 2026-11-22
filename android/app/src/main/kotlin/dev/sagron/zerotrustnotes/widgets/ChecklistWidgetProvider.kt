package dev.sagron.zerotrustnotes.widgets

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.graphics.Paint
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
import org.json.JSONObject

/**
 * Checklist (W5): one checklist note with tick circles. Tap a circle to
 * tick or untick the item; the tick shows at once and reaches the note the
 * next time ZT Notes is open and unlocked (see [ChecklistTicks]). Tap the
 * title to open the note.
 *
 * Renders only what HomeWidgetSyncService (Dart) wrote under
 * `checklist_widget_<id>_json`, which exists only while "Show details on
 * the home screen" is on; otherwise the widget shows a lock and says how to
 * turn it on. It never reads the vault.
 */
class ChecklistWidgetProvider : HomeWidgetProvider() {

    companion object {
        private const val DETAILS_KEY = "notes_widget_details"

        fun updateAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(ComponentName(context, ChecklistWidgetProvider::class.java))
            val prefs = HomeWidgetPlugin.getData(context)
            ids.forEach { update(context, manager, it, prefs) }
        }

        private fun update(
            context: Context,
            manager: AppWidgetManager,
            widgetId: Int,
            prefs: SharedPreferences,
        ) {
            val noteId = prefs.getString(ChecklistTicks.noteIdKey(widgetId), null)
            val detailsOn = prefs.getBoolean(DETAILS_KEY, false)
            val json = if (detailsOn) prefs.getString(ChecklistTicks.itemsKey(widgetId), null) else null
            val views = RemoteViews(context.packageName, R.layout.widget_checklist)

            val openUri = if (noteId == null) {
                Uri.parse("zerotrustnotes://open")
            } else {
                Uri.parse("zerotrustnotes://note?id=" + Uri.encode(noteId))
            }
            val openIntent = HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java, openUri)
            views.setOnClickPendingIntent(R.id.checklist_header, openIntent)
            views.setContentDescription(
                R.id.checklist_header,
                WidgetText.get(context, prefs, "open_checklist", R.string.widget_open_checklist),
            )

            val list = json?.let { try { JSONObject(it) } catch (e: Exception) { null } }
            if (noteId == null || list == null) {
                views.setTextViewText(
                    R.id.checklist_title,
                    WidgetText.get(context, prefs, "checklist", R.string.widget_checklist),
                )
                views.setViewVisibility(R.id.checklist_count, View.GONE)
                views.setViewVisibility(R.id.checklist_list, View.GONE)
                views.setViewVisibility(R.id.checklist_empty, View.GONE)
                views.setViewVisibility(R.id.checklist_locked, View.VISIBLE)
                views.setTextViewText(
                    R.id.checklist_locked_text,
                    when {
                        !detailsOn -> WidgetText.get(context, prefs, "checklist_hidden", R.string.widget_checklist_hidden)
                        noteId == null -> WidgetText.get(context, prefs, "pick_checklist", R.string.widget_pick_checklist)
                        else -> WidgetText.get(context, prefs, "open_to_see_checklist", R.string.widget_open_to_see_checklist)
                    },
                )
                views.setOnClickPendingIntent(R.id.checklist_locked, openIntent)
                RemoteViewsCompat.setRemoteAdapter(
                    context,
                    views,
                    widgetId,
                    R.id.checklist_list,
                    RemoteViewsCompat.RemoteCollectionItems.Builder().build(),
                )
                manager.updateAppWidget(widgetId, views)
                return
            }

            val items = list.optJSONArray("i")
            val title = list.optString("t")
            views.setTextViewText(
                R.id.checklist_title,
                title.ifEmpty { WidgetText.get(context, prefs, "checklist", R.string.widget_checklist) },
            )
            var done = 0
            var total = 0
            if (items != null) {
                for (i in 0 until items.length()) {
                    val item = items.optJSONObject(i) ?: continue
                    total++
                    if (item.optBoolean("c", false)) done++
                }
            }
            views.setViewVisibility(R.id.checklist_count, if (total == 0) View.GONE else View.VISIBLE)
            views.setTextViewText(R.id.checklist_count, "$done/$total")

            views.setViewVisibility(R.id.checklist_locked, View.GONE)
            views.setViewVisibility(R.id.checklist_list, View.VISIBLE)
            views.setTextViewText(
                R.id.checklist_empty,
                WidgetText.get(context, prefs, "checklist_empty", R.string.widget_checklist_empty),
            )
            views.setEmptyView(R.id.checklist_list, R.id.checklist_empty)
            views.setPendingIntentTemplate(R.id.checklist_list, tickTemplate(context, widgetId))

            val rows = RemoteViewsCompat.RemoteCollectionItems.Builder()
                .setHasStableIds(true)
                .setViewTypeCount(1)
            val tickLabel = WidgetText.get(context, prefs, "tick", R.string.widget_tick)
            val untickLabel = WidgetText.get(context, prefs, "untick", R.string.widget_untick)
            val openColor = context.getColor(R.color.zt_widget_on_surface)
            val doneColor = context.getColor(R.color.zt_widget_on_surface_variant)
            if (items != null) {
                for (i in 0 until items.length()) {
                    val item = items.optJSONObject(i) ?: continue
                    val id = item.optString("id")
                    if (id.isEmpty()) continue
                    val checked = item.optBoolean("c", false)
                    val text = item.optString("x")
                    val row = RemoteViews(context.packageName, R.layout.widget_checklist_item).apply {
                        setTextViewText(R.id.checklist_row_text, text)
                        setInt(
                            R.id.checklist_row_text,
                            "setPaintFlags",
                            if (checked) Paint.STRIKE_THRU_TEXT_FLAG or Paint.ANTI_ALIAS_FLAG else Paint.ANTI_ALIAS_FLAG,
                        )
                        setTextColor(R.id.checklist_row_text, if (checked) doneColor else openColor)
                        setViewVisibility(R.id.checklist_row_tick, if (checked) View.VISIBLE else View.GONE)
                        setViewVisibility(R.id.checklist_row_ring, if (checked) View.GONE else View.VISIBLE)
                        setContentDescription(
                            R.id.checklist_row,
                            (if (checked) untickLabel else tickLabel) + ": " + text,
                        )
                        setOnClickFillInIntent(
                            R.id.checklist_row,
                            Intent()
                                .putExtra(ChecklistTickReceiver.EXTRA_NOTE_ID, noteId)
                                .putExtra(ChecklistTickReceiver.EXTRA_ITEM_ID, id),
                        )
                    }
                    rows.addItem(id.hashCode().toLong(), row)
                }
            }
            RemoteViewsCompat.setRemoteAdapter(context, views, widgetId, R.id.checklist_list, rows.build())
            manager.updateAppWidget(widgetId, views)
        }

        /**
         * One template for the list's rows; each row fills in its note and
         * item. Mutable (rows fill it in) but explicit: it can only reach
         * this app's non-exported [ChecklistTickReceiver].
         */
        private fun tickTemplate(context: Context, widgetId: Int): PendingIntent {
            val intent = Intent(context, ChecklistTickReceiver::class.java).apply {
                action = ChecklistTickReceiver.ACTION_TICK
                data = Uri.parse("zerotrustnotes://widget/$widgetId/tick")
            }
            return PendingIntent.getBroadcast(
                context,
                widgetId,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE,
            )
        }
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

    override fun onDeleted(context: Context, appWidgetIds: IntArray) {
        super.onDeleted(context, appWidgetIds)
        val editor = HomeWidgetPlugin.getData(context).edit()
        appWidgetIds.forEach {
            editor.remove(ChecklistTicks.noteIdKey(it))
            editor.remove(ChecklistTicks.itemsKey(it))
        }
        editor.apply()
    }
}
