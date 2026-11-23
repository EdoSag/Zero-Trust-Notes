package dev.sagron.zerotrustnotes.widgets

import android.appwidget.AppWidgetManager
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import es.antonborri.home_widget.HomeWidgetPlugin
import org.json.JSONArray
import org.json.JSONObject

/**
 * Ticks made on a Checklist widget (W5). The widget shows the tick at
 * once (in its own cached copy of the list) and queues it here; the app
 * applies the queue to the encrypted note the next time it is unlocked or
 * comes to the foreground (ChecklistWidgetTicks in Dart), the same way
 * ZT Tasks queues widget ticks while locked.
 *
 * Only item ids and the ticked state are queued: no note text.
 */
object ChecklistTicks {
    const val PENDING_KEY = "checklist_widget_pending"

    private val lock = Any()

    fun itemsKey(widgetId: Int) = "checklist_widget_${widgetId}_json"
    fun noteIdKey(widgetId: Int) = "checklist_widget_${widgetId}_note_id"

    /**
     * Ticks or unticks [itemId] of [noteId] on every Checklist widget that
     * shows that note, and queues the change for the app.
     */
    fun toggle(context: Context, noteId: String, itemId: String) {
        val prefs = HomeWidgetPlugin.getData(context)
        val manager = AppWidgetManager.getInstance(context)
        val ids = manager.getAppWidgetIds(ComponentName(context, ChecklistWidgetProvider::class.java))
        synchronized(lock) {
            var checked: Boolean? = null
            val editor = prefs.edit()
            for (id in ids) {
                if (prefs.getString(noteIdKey(id), null) != noteId) continue
                val json = prefs.getString(itemsKey(id), null) ?: continue
                val list = try { JSONObject(json) } catch (e: Exception) { continue }
                val items = list.optJSONArray("i") ?: continue
                for (i in 0 until items.length()) {
                    val item = items.optJSONObject(i) ?: continue
                    if (item.optString("id") != itemId) continue
                    val now = checked ?: !item.optBoolean("c", false)
                    checked = now
                    item.put("c", now)
                }
                list.put("i", ordered(items))
                editor.putString(itemsKey(id), list.toString())
            }
            val now = checked ?: return
            val pending = try {
                JSONArray(prefs.getString(PENDING_KEY, null) ?: "[]")
            } catch (e: Exception) {
                JSONArray()
            }
            pending.put(
                JSONObject()
                    .put("n", noteId)
                    .put("i", itemId)
                    .put("c", now)
                    .put("at", System.currentTimeMillis()),
            )
            editor.putString(PENDING_KEY, pending.toString())
            editor.commit()
        }
        ChecklistWidgetProvider.updateAll(context)
    }

    /**
     * The queued ticks, oldest first, for the app. They stay queued until
     * the app has saved them and calls [ack], so a save that fails (the
     * vault locking part-way) is tried again on the next unlock.
     */
    fun peek(prefs: SharedPreferences): String {
        synchronized(lock) {
            return prefs.getString(PENDING_KEY, null) ?: "[]"
        }
    }

    /** Drops the first [count] queued ticks: the ones the app has saved. */
    fun ack(prefs: SharedPreferences, count: Int) {
        synchronized(lock) {
            val pending = try {
                JSONArray(prefs.getString(PENDING_KEY, null) ?: "[]")
            } catch (e: Exception) {
                JSONArray()
            }
            val rest = JSONArray()
            for (i in count until pending.length()) rest.put(pending.get(i))
            val editor = prefs.edit()
            if (rest.length() == 0) editor.remove(PENDING_KEY) else editor.putString(PENDING_KEY, rest.toString())
            editor.commit()
        }
    }

    /** Open items first, then ticked ones, each in their own order (like the app). */
    private fun ordered(items: JSONArray): JSONArray {
        val open = JSONArray()
        val done = JSONArray()
        for (i in 0 until items.length()) {
            val item = items.optJSONObject(i) ?: continue
            if (item.optBoolean("c", false)) done.put(item) else open.put(item)
        }
        for (i in 0 until done.length()) open.put(done.get(i))
        return open
    }
}

/**
 * A tap on a row's tick circle. Not exported: only this app's own widget
 * PendingIntents can reach it, so no other app can tick a note's items.
 */
class ChecklistTickReceiver : BroadcastReceiver() {
    companion object {
        const val ACTION_TICK = "dev.sagron.zerotrustnotes.widgets.CHECKLIST_TICK"
        const val EXTRA_NOTE_ID = "note_id"
        const val EXTRA_ITEM_ID = "item_id"
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != ACTION_TICK) return
        val noteId = intent.getStringExtra(EXTRA_NOTE_ID) ?: return
        val itemId = intent.getStringExtra(EXTRA_ITEM_ID) ?: return
        ChecklistTicks.toggle(context, noteId, itemId)
    }
}
