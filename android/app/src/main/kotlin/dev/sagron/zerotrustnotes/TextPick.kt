package dev.sagron.zerotrustnotes

import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager

/**
 * ZT Keyboard's "Insert from ZT apps" key: the keyboard opens this app to let the user
 * pick a line of a note, and types what was picked.
 *
 * Only a Zero-Trust app may ask. All of them are signed with the same key, so the caller
 * must carry this app's own signature; anyone else is turned away before anything is
 * shown. The answer is the one text the user tapped, nothing more, and only after the
 * vault was unlocked as usual.
 */
object TextPick {
    const val ACTION = "bz.zerotrust.action.PICK_TEXT"
    const val EXTRA_TEXT = "bz.zerotrust.extra.TEXT"

    fun isPick(intent: Intent?): Boolean = intent?.action == ACTION

    /**
     * Whether [activity] was opened, for an answer, by an app signed with this app's key.
     * Android only names the caller when it waits for an answer, and that name cannot be
     * faked by the caller.
     */
    fun callerAllowed(activity: Activity): Boolean {
        val caller = activity.callingPackage ?: return false
        return try {
            activity.packageManager.checkSignatures(activity.packageName, caller) ==
                PackageManager.SIGNATURE_MATCH
        } catch (error: Exception) {
            false
        }
    }

    fun answer(activity: Activity, text: String?) {
        if (text.isNullOrEmpty()) {
            activity.setResult(Activity.RESULT_CANCELED)
        } else {
            activity.setResult(Activity.RESULT_OK, Intent().putExtra(EXTRA_TEXT, text))
        }
        activity.finish()
    }
}
