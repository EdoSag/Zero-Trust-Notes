package dev.sagron.zerotrustnotes

import android.annotation.SuppressLint
import android.app.PendingIntent
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import es.antonborri.home_widget.HomeWidgetLaunchIntent

/**
 * N-9: a "New note" tile for Quick Settings. Tapping it opens Notes on a
 * new note, after unlock if the app is locked, through the same
 * `zerotrustnotes://new-note` link the widgets use (WidgetLaunchListener in
 * Dart). The tile shows nothing from the notes.
 */
class NewNoteTileService : TileService() {

    override fun onStartListening() {
        super.onStartListening()
        qsTile?.apply {
            state = Tile.STATE_INACTIVE
            label = getString(R.string.tile_new_note)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                subtitle = getString(R.string.tile_new_note_subtitle)
            }
            updateTile()
        }
    }

    @SuppressLint("StartActivityAndCollapseDeprecated")
    override fun onClick() {
        super.onClick()
        val intent = Intent(this, MainActivity::class.java).apply {
            action = HomeWidgetLaunchIntent.HOME_WIDGET_LAUNCH_ACTION
            data = Uri.parse("zerotrustnotes://new-note")
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        val open = {
            if (Build.VERSION.SDK_INT >= 34) {
                startActivityAndCollapse(
                    PendingIntent.getActivity(
                        this,
                        0,
                        intent,
                        PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
                    ),
                )
            } else {
                @Suppress("DEPRECATION")
                startActivityAndCollapse(intent)
            }
        }
        // On a locked phone, ask for the screen lock first.
        if (isLocked) unlockAndRun { open() } else open()
    }
}
