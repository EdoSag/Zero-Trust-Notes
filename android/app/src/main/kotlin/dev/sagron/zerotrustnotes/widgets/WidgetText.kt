package dev.sagron.zerotrustnotes.widgets

import android.content.Context
import android.content.SharedPreferences

/**
 * The widgets' fixed texts in the language picked in the app's Settings
 * (English or Hebrew). The app stores them as `notes_widget_text_<key>` in
 * home_widget's preferences whenever its language is set; until the app has
 * run, the string resources (English, or Hebrew on a Hebrew phone) are used.
 */
object WidgetText {
    fun get(context: Context, prefs: SharedPreferences, key: String, fallback: Int): String =
        prefs.getString("notes_widget_text_$key", null) ?: context.getString(fallback)
}
