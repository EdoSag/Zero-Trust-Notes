import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zero_trust_core/zero_trust_core.dart';
import 'package:zerotrust_notes/l10n/l10n.dart';
import 'package:zt_places/zt_places.dart';

import '../notes/application/notes_providers.dart';
import '../notes/domain/note.dart';
import 'note_place_reminder.dart';
import 'saved_places_repository.dart';

/// The phone's place watcher. Tests override it with `ZtPlaceRemindersFake`.
final placeRemindersPlatformProvider = Provider<ZtPlaceReminders>((ref) {
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    return ZtPlaceRemindersAndroid();
  }
  return ZtPlaceRemindersFake(supported: false, granted: ZtPlacePermissions.none);
});

/// [placeRemindersPlatformProvider], with permission prompts and the
/// settings page kept from auto-locking Notes while they are open.
final placeRemindersProvider = Provider<ZtPlaceReminders>(
  (ref) => _SystemUiAwarePlaceReminders(ref.watch(placeRemindersPlatformProvider), ref),
);

class _SystemUiAwarePlaceReminders implements ZtPlaceReminders {
  _SystemUiAwarePlaceReminders(this._inner, this._ref);

  final ZtPlaceReminders _inner;
  final Ref _ref;

  Future<R> _guard<R>(Future<R> Function() action) =>
      _ref.read(vaultControllerProvider.notifier).whileShowingSystemUi(action);

  @override
  bool get supported => _inner.supported;

  @override
  Future<int> sync(List<ZtPlaceReminder> reminders, {required ZtPlaceNotificationStyle style}) =>
      _inner.sync(reminders, style: style);

  @override
  Future<void> clear() => _inner.clear();

  @override
  Future<ZtPlacePermissions> permissions() => _inner.permissions();

  @override
  Future<ZtPlacePermissions> requestLocation() => _guard(_inner.requestLocation);

  @override
  Future<ZtPlacePermissions> requestBackground() => _guard(_inner.requestBackground);

  @override
  Future<ZtPlacePermissions> requestNotifications() => _guard(_inner.requestNotifications);

  /// Stays "showing system UI" until the person comes back from Settings.
  @override
  Future<void> openSettings() => _guard(() async {
    final back = Completer<void>();
    final listener = AppLifecycleListener(
      onResume: () {
        if (!back.isCompleted) back.complete();
      },
    );
    try {
      await _inner.openSettings();
      await back.future.timeout(const Duration(minutes: 15), onTimeout: () {});
    } finally {
      listener.dispose();
    }
  });

  @override
  Future<ZtLatLng?> currentLocation({Duration timeout = const Duration(seconds: 20)}) =>
      _inner.currentLocation(timeout: timeout);

  @override
  Stream<ZtPlaceEvent> get events => _inner.events;

  @override
  Future<void> collect() => _inner.collect();
}

final savedPlacesRepositoryProvider = Provider<SavedPlacesRepository?>((ref) {
  final store = watchOpenNotesStore(ref);
  if (store == null) return null;
  return SavedPlacesRepository(store: store, sync: syncForWrites(ref));
});

/// "My places", by name.
final savedPlacesProvider = StreamProvider<List<ZtPlace>>((ref) {
  final repository = ref.watch(savedPlacesRepositoryProvider);
  if (repository == null) return const Stream.empty();
  return repository.watchAll();
});

/// The place strings in the app's current language.
ZtPlacesStrings get currentPlacesStrings =>
    ZtPlacesStrings.forLocale(Locale(currentL10n.localeName));

/// How Notes's place notifications look.
ZtPlaceNotificationStyle placeNotificationStyle() {
  final s = currentPlacesStrings;
  return ZtPlaceNotificationStyle(
    channelId: 'note_place_reminders',
    channelName: s.channelName,
    channelDescription: s.channelDescription,
    doneLabel: currentL10n.done,
    publicTitle: s.publicTitle,
  );
}

/// The place reminders [notes] want the phone to watch: outside Trash.
/// Only the title and the place name reach the OS, as with timed reminders.
List<ZtPlaceReminder> placeRemindersFor(Iterable<Note> notes) {
  final s = currentPlacesStrings;
  return [
    for (final note in notes)
      if (note.placeReminder case final r? when !note.isTrashed)
        ZtPlaceReminder(
          id: r.idFor(note.id),
          place: r.place,
          trigger: r.trigger,
          title: note.title.trim().isEmpty ? currentL10n.reminder : note.title.trim(),
          body: r.trigger == ZtPlaceTrigger.arrive
              ? s.arriving(r.place.name)
              : s.leaving(r.place.name),
          payload: note.id,
        ),
  ];
}

/// Place reminders that fired (or were marked done from the notification)
/// and whose note still has to drop them. Collected while locked too, then
/// applied once the notes are open.
class FiredPlaceReminders extends Notifier<Set<String>> {
  @override
  Set<String> build() => const {};

  void add(String reminderId) => state = {...state, reminderId};

  void removeAll(Iterable<String> ids) => state = state.difference(ids.toSet());
}

final firedPlaceRemindersProvider = NotifierProvider<FiredPlaceReminders, Set<String>>(
  FiredPlaceReminders.new,
);

/// Drops the place reminder of each note whose reminder id is in [fired]:
/// a place reminder is done once it has gone off, like a timed one that
/// has passed. Returns the ids handled (found or no longer there).
///
/// Shared notes are read after the account's own. Until they are in
/// ([allLoaded] false), a reminder whose note isn't in [notes] is kept
/// for the next try instead of counted as gone.
Future<Set<String>> clearFiredPlaceReminders(
  Future<void> Function(Note note) updateNote,
  List<Note> notes,
  Set<String> fired, {
  bool allLoaded = true,
}) async {
  final handled = <String>{};
  for (final id in fired) {
    final noteId = NotePlaceReminder.noteIdOf(id);
    final note = notes.where((n) => n.id == noteId).firstOrNull;
    if (note == null && !allLoaded) continue;
    final current = note?.placeReminder;
    if (note != null && current != null && current.idFor(note.id) == id) {
      await updateNote(note.copyWith(placeReminder: null));
    }
    handled.add(id);
  }
  return handled;
}

/// "When you arrive at Home" / "When you leave Office", in the app's language.
String placeReminderLabel(BuildContext context, NotePlaceReminder reminder) {
  final s = ZtPlacesStrings.of(context);
  return reminder.trigger == ZtPlaceTrigger.arrive
      ? s.arriving(reminder.place.name)
      : s.leaving(reminder.place.name);
}
