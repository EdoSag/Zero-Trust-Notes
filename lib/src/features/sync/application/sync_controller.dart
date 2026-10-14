import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:zero_trust_core/zero_trust_core.dart';

import '../../notes/application/notes_session.dart';

sealed class SyncUiState {
  const SyncUiState();
}

class SyncIdle extends SyncUiState {
  const SyncIdle();
}

class SyncSyncing extends SyncUiState {
  const SyncSyncing();
}

class SyncOffline extends SyncUiState {
  const SyncOffline();
}

class SyncError extends SyncUiState {
  const SyncError(this.message);

  final String message;
}

/// Overridable so tests don't need the connectivity plugin.
final isOnlineProvider = Provider<Future<bool> Function()>((ref) {
  final connectivity = Connectivity();
  return () async {
    final results = await connectivity.checkConnectivity();
    return !results.contains(ConnectivityResult.none);
  };
});

final syncControllerProvider = NotifierProvider<SyncController, SyncUiState>(SyncController.new);

/// Keeps notes in sync without a Sync button: once on unlock, shortly after
/// every local change, and live as other devices write.
///
/// When another device's newer edit wins over an unsynced local one, the
/// local version is kept as a separate "conflicted copy" note, so nothing a
/// user typed is ever silently lost.
class SyncController extends Notifier<SyncUiState> {
  static const debounce = Duration(seconds: 2);
  static const _uuid = Uuid();
  Timer? _timer;

  @override
  SyncUiState build() {
    ref.onDispose(() => _timer?.cancel());
    ref.listen(notesSessionProvider, fireImmediately: true, (_, next) {
      final session = next.value;
      if (session == null) return;
      session.engine.startLive(onApplied: (result) => _keepConflictCopies(session, result));
      Future.microtask(syncNow);
    });
    ref.listen(notesChangedProvider, (_, _) {
      _timer?.cancel();
      _timer = Timer(debounce, syncNow);
    });
    return const SyncIdle();
  }

  Future<void> syncNow() async {
    final session = ref.read(notesSessionProvider).value;
    if (session == null) return;
    if (!await ref.read(isOnlineProvider)()) {
      state = const SyncOffline();
      return;
    }
    state = const SyncSyncing();
    try {
      final result = await session.engine.sync();
      await _keepConflictCopies(session, result);
      if (!ref.mounted) return;
      state = const SyncIdle();
    } catch (error) {
      if (!ref.mounted) return;
      state = SyncError('Couldn\'t sync. Your notes are saved on this device and will sync later.');
    }
  }

  Future<void> _keepConflictCopies(NotesSession session, SyncResult result) async {
    if (result.conflicts.isEmpty) return;
    for (final conflict in result.conflicts) {
      final lost = conflict.lostLocal.json;
      if (lost == null) continue; // a local delete lost; nothing to restore
      final title = (lost['title'] as String?) ?? '';
      await session.engine.save(_uuid.v4(), {
        ...lost,
        'title': title.isEmpty ? 'Conflicted copy' : '$title (conflicted copy)',
      });
    }
    ref.read(notesChangedProvider.notifier).bump();
  }
}
