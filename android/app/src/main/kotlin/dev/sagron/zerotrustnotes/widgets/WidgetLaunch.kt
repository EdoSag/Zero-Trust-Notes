package dev.sagron.zerotrustnotes.widgets

import android.app.ActivityOptions
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import dev.sagron.zerotrustnotes.MainActivity
import es.antonborri.home_widget.HomeWidgetLaunchIntent

/**
 * Taps on rows of a scrolling widget list. A list takes one PendingIntent
 * template and each row fills in its own URI, so the template has to be
 * mutable; it names MainActivity explicitly, so no other app can redirect
 * it. The URI arrives in Dart through home_widget like any widget tap.
 */
object WidgetLaunch {
    fun rowTemplate(context: Context, requestCode: Int): PendingIntent {
        val intent = Intent(context, MainActivity::class.java).apply {
            action = HomeWidgetLaunchIntent.HOME_WIDGET_LAUNCH_ACTION
        }
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
        if (Build.VERSION.SDK_INT < 34) {
            return PendingIntent.getActivity(context, requestCode, intent, flags)
        }
        val options = ActivityOptions.makeBasic()
        if (Build.VERSION.SDK_INT >= 35) {
            options.setPendingIntentCreatorBackgroundActivityStartMode(
                ActivityOptions.MODE_BACKGROUND_ACTIVITY_START_ALLOWED,
            )
        } else {
            @Suppress("DEPRECATION")
            options.pendingIntentBackgroundActivityStartMode =
                ActivityOptions.MODE_BACKGROUND_ACTIVITY_START_ALLOWED
        }
        return PendingIntent.getActivity(context, requestCode, intent, flags, options.toBundle())
    }

    fun rowFillIn(uri: String): Intent = Intent().setData(Uri.parse(uri))
}
