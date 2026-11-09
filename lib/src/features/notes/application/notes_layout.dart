import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zero_trust_core/zero_trust_core.dart';

enum NotesLayout { grid, list }

/// Grid (Keep's cards) or list, remembered on this device.
class NotesLayoutController extends Notifier<NotesLayout> {
  static const _key = 'notes_layout';
  bool _chosen = false;

  @override
  NotesLayout build() {
    _load();
    return NotesLayout.grid;
  }

  Future<void> _load() async {
    try {
      final stored = await ref.read(ztPreferencesStoreProvider).read(_key);
      if (_chosen || stored == null) return;
      state = stored == 'list' ? NotesLayout.list : NotesLayout.grid;
    } on Object {
      // Unreadable: keep the default.
    }
  }

  Future<void> toggle() async {
    _chosen = true;
    state = state == NotesLayout.grid ? NotesLayout.list : NotesLayout.grid;
    try {
      await ref.read(ztPreferencesStoreProvider).write(_key, state.name);
    } on Object {
      // Not remembered this time; the toggle still applies.
    }
  }
}

final notesLayoutProvider = NotifierProvider<NotesLayoutController, NotesLayout>(
  NotesLayoutController.new,
);
