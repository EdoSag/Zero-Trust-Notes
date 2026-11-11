import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timezone/timezone.dart' as tz;

import '../notes/domain/note.dart';
import 'package:zerotrust_notes/l10n/l10n.dart';

/// A reminder the OS should show at [at], for the note [noteId].
@immutable
class ScheduledReminder {
  const ScheduledReminder({required this.noteId, required this.at, required this.title});

  final String noteId;
  final DateTime at;

  /// The note's title. This is the only note text that leaves the vault:
  /// the OS has to hold it to show the reminder while Notes is locked.
  final String title;

  /// A stable 31-bit notification id per note.
  int get notificationId => notificationIdFor(noteId);

  static int notificationIdFor(String noteId) {
    // FNV-1a, so the id is the same on every run (String.hashCode isn't).
    var hash = 0x811c9dc5;
    for (final unit in noteId.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash & 0x7fffffff;
  }

  /// Carried on the notification so a tap can open the note.
  String get payload => '$noteId|${at.toUtc().toIso8601String()}';

  static String? noteIdFromPayload(String? payload) {
    if (payload == null || payload.isEmpty) return null;
    return payload.split('|').first;
  }

  /// The reminders [notes] want right now: future ones, outside Trash.
  static List<ScheduledReminder> fromNotes(Iterable<Note> notes, DateTime now) => [
    for (final note in notes)
      if (note.reminderAt != null && !note.isTrashed && note.reminderAt!.isAfter(now))
        ScheduledReminder(noteId: note.id, at: note.reminderAt!, title: note.title),
  ];

  @override
  bool operator ==(Object other) =>
      other is ScheduledReminder &&
      other.noteId == noteId &&
      other.at.isAtSameMomentAs(at) &&
      other.title == title;

  @override
  int get hashCode => Object.hash(noteId, at.millisecondsSinceEpoch, title);
}

/// Hands note reminders to the OS so they fire even while Notes is closed or
/// locked.
abstract interface class ReminderScheduler {
  /// Makes the OS's pending reminders exactly [reminders].
  Future<void> sync(List<ScheduledReminder> reminders);

  /// Drops every reminder (sign-out).
  Future<void> cancelAll();

  /// Asks for notification (and, on Android, exact alarm) permission.
  /// Returns false when notifications are off.
  Future<bool> requestPermission();

  /// Note ids from reminder taps, including the one that launched the app.
  Stream<String> get taps;
}

/// For tests and platforms without notifications.
class NoopReminderScheduler implements ReminderScheduler {
  List<ScheduledReminder> scheduled = const [];

  @override
  Future<void> sync(List<ScheduledReminder> reminders) async => scheduled = reminders;

  @override
  Future<void> cancelAll() async => scheduled = const [];

  @override
  Future<bool> requestPermission() async => true;

  @override
  Stream<String> get taps => const Stream.empty();
}

class LocalNotificationsReminderScheduler implements ReminderScheduler {
  LocalNotificationsReminderScheduler([FlutterLocalNotificationsPlugin? plugin])
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  final _taps = StreamController<String>.broadcast();
  String? _launchNoteId;
  Future<void>? _ready;

  static AndroidNotificationDetails get _channel => AndroidNotificationDetails(
    'note_reminders',
    currentL10n.reminderChannel,
    channelDescription: currentL10n.reminderChannelDesc,
    importance: Importance.high,
    priority: Priority.high,
    category: AndroidNotificationCategory.reminder,
    // The lock screen shows "Note reminder", not the note's title.
    visibility: NotificationVisibility.private,
  );

  static NotificationDetails get _details => NotificationDetails(
    android: _channel,
    iOS: const DarwinNotificationDetails(),
  );

  Future<void> _init() => _ready ??= () async {
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        // Permission is asked when the first reminder is set, not at launch.
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestSoundPermission: false,
          requestBadgePermission: false,
        ),
      ),
      onDidReceiveNotificationResponse: (response) {
        final noteId = ScheduledReminder.noteIdFromPayload(response.payload);
        if (noteId != null) _taps.add(noteId);
      },
    );
    final launch = await _plugin.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp ?? false) {
      _launchNoteId = ScheduledReminder.noteIdFromPayload(launch!.notificationResponse?.payload);
    }
  }();

  /// Call once at start-up.
  Future<void> initialize() => _init();

  @override
  Stream<String> get taps async* {
    try {
      await _init();
    } on Object {
      return; // No notifications on this device; nothing will be tapped.
    }
    final launched = _launchNoteId;
    _launchNoteId = null;
    if (launched != null) yield launched;
    yield* _taps.stream;
  }

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

  @override
  Future<bool> requestPermission() async {
    await _init();
    final android = _android;
    if (android != null) {
      final granted = await android.requestNotificationsPermission() ?? true;
      if (granted && !(await android.canScheduleExactNotifications() ?? true)) {
        await android.requestExactAlarmsPermission();
      }
      return granted;
    }
    final ios = _plugin
        .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
    if (ios != null) {
      return await ios.requestPermissions(alert: true, sound: true, badge: false) ?? false;
    }
    return true;
  }

  @override
  Future<void> sync(List<ScheduledReminder> reminders) async {
    await _init();
    final wanted = {for (final reminder in reminders) reminder.notificationId: reminder};
    final pending = await _plugin.pendingNotificationRequests();
    for (final request in pending) {
      final want = wanted[request.id];
      if (want == null) {
        await _plugin.cancel(id: request.id);
      } else if (request.payload == want.payload && request.title == _title(want)) {
        wanted.remove(request.id); // Already scheduled as it should be.
      }
    }
    if (wanted.isEmpty) return;
    final exact = await _android?.canScheduleExactNotifications() ?? true;
    for (final reminder in wanted.values) {
      await _plugin.zonedSchedule(
        id: reminder.notificationId,
        title: _title(reminder),
        body: currentL10n.noteReminder,
        payload: reminder.payload,
        // An absolute instant, so the device's time zone doesn't matter.
        scheduledDate: tz.TZDateTime.from(reminder.at.toUtc(), tz.UTC),
        notificationDetails: _details,
        androidScheduleMode: exact
            ? AndroidScheduleMode.exactAllowWhileIdle
            : AndroidScheduleMode.inexactAllowWhileIdle,
      );
    }
  }

  String _title(ScheduledReminder reminder) =>
      reminder.title.trim().isEmpty ? currentL10n.reminder : reminder.title.trim();

  @override
  Future<void> cancelAll() async {
    await _init();
    await _plugin.cancelAll();
  }
}

final reminderSchedulerProvider = Provider<ReminderScheduler>((ref) {
  if (kIsWeb ||
      !(defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS)) {
    return NoopReminderScheduler();
  }
  return LocalNotificationsReminderScheduler();
});
