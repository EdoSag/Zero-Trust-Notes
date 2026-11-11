import 'package:flutter/widgets.dart';
import 'package:zerotrust_notes/l10n/l10n.dart';

import '../application/home_widget_sync_service.dart';

/// Hands the home screen widgets the app's language: whenever the language
/// in Settings changes (and once at start), their fixed texts are saved
/// again in it.
class WidgetTextSync extends StatefulWidget {
  const WidgetTextSync({super.key, required this.child});

  final Widget child;

  @override
  State<WidgetTextSync> createState() => _WidgetTextSyncState();
}

class _WidgetTextSyncState extends State<WidgetTextSync> {
  String? _synced;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final l10n = context.l10n;
    if (l10n.localeName == _synced) return;
    _synced = l10n.localeName;
    // Best effort: a widget keeps its last texts if this fails.
    const HomeWidgetSyncService().saveTexts(l10n).catchError((Object _) {});
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
