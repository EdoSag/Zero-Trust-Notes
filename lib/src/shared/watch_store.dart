import 'dart:async';

import 'package:zero_trust_core/zero_trust_core.dart';

/// [read]'s result now, and again after every change to [store].
Stream<T> watchStore<T>(ZtLocalStore store, Future<T> Function() read) {
  late final StreamController<T> controller;
  StreamSubscription<Set<String>>? changes;
  Future<void> emit() async {
    try {
      final value = await read();
      if (!controller.isClosed) controller.add(value);
    } catch (e, s) {
      if (!controller.isClosed) controller.addError(e, s);
    }
  }

  controller = StreamController<T>(
    onListen: () {
      // Listen before the first read, so no change falls in between.
      changes = store.changes.listen((_) => emit());
      emit();
    },
    onCancel: () => changes?.cancel(),
  );
  return controller.stream;
}
