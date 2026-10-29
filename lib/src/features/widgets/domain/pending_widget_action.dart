/// An action requested by a home-screen widget tap, carried out once the
/// vault is confirmed unlocked. The consumer clears the pending action
/// immediately after acting on it so rebuilds don't replay it.
sealed class PendingWidgetAction {
  const PendingWidgetAction();
}

class OpenNewNote extends PendingWidgetAction {
  const OpenNewNote();
}

class OpenNote extends PendingWidgetAction {
  const OpenNote(this.noteId);

  final String noteId;
}

/// [appWidgetId] is Android's widget instance id, carried as a string
/// throughout the Dart layer since it only ever needs to round-trip back to
/// `home_widget`'s string-keyed storage.
class ConfigureNoteWidget extends PendingWidgetAction {
  const ConfigureNoteWidget(this.appWidgetId);

  final String appWidgetId;
}
