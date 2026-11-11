import 'package:flutter/material.dart';

import '../../../shared/markdown_snippet.dart';
import '../../../shared/text_direction.dart';
import '../../../shared/theme/app_spacing.dart';
import '../../images/note_image_views.dart';
import '../../places/place_providers.dart';
import '../domain/note.dart';
import 'note_actions.dart';
import 'package:zerotrust_notes/l10n/l10n.dart';

/// One note in the grid or list: its first image, colour, title, a preview
/// of the text or checklist, tags and reminder.
class NoteCard extends StatelessWidget {
  const NoteCard({
    super.key,
    required this.note,
    required this.tagNames,
    required this.onTap,
    this.onLongPress,
    this.compact = false,
  });

  final Note note;
  final List<String> tagNames;
  final VoidCallback onTap;

  /// Null when a parent handles long press (dragging to reorder).
  final VoidCallback? onLongPress;

  /// List mode: fewer preview lines.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final background = note.color.background(theme.brightness);
    final onColor = background == null ? scheme.onSurface : _textOn(background);
    final muted = onColor.withValues(alpha: 0.72);
    final title = note.title.trim();
    // A locked note shows only its title until it's opened.
    final locked = note.locked;
    final snippet = locked ? '' : stripMarkdownForSnippet(note.body);

    final semantics = [
      if (note.pinned) context.l10n.semPinned,
      if (locked) context.l10n.semLocked,
      if (note.hasImages && !locked) context.l10n.semImages(note.images.length),
      title.isEmpty ? context.l10n.semUntitled : '$title.',
      if (note.isChecklist && !locked)
        context.l10n.semChecklist(
          note.checklist!.where((i) => i.checked).length,
          note.checklist!.length,
        )
      else if (snippet.isNotEmpty)
        snippet,
      if (note.reminderAt != null) context.l10n.semReminder(formatReminder(note.reminderAt!)),
      if (note.placeReminder != null) placeReminderLabel(context, note.placeReminder!),
      if (tagNames.isNotEmpty) context.l10n.semTags(tagNames.join(', ')),
      if (note.isShared) context.l10n.semShared,
    ].join(' ');

    return Semantics(
      label: semantics,
      button: true,
      hint: context.l10n.semOpensNote,
      excludeSemantics: true,
      child: Card(
        margin: EdgeInsets.zero,
        elevation: 0,
        color: background ?? scheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: background == null ? BorderSide(color: scheme.outlineVariant) : BorderSide.none,
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (note.hasImages && !locked) _CardImage(note: note, height: compact ? 96 : 140),
              Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (title.isNotEmpty)
                      Text(
                        title,
                        textDirection: textDirectionOf(title),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(color: onColor),
                      ),
                    if (title.isNotEmpty && (snippet.isNotEmpty || note.isChecklist || locked))
                      const SizedBox(height: AppSpacing.xs),
                    if (locked)
                      Row(
                        children: [
                          Icon(Icons.lock_outline, size: 18, color: muted),
                          const SizedBox(width: 6),
                          Text(
                            context.l10n.locked,
                            style: theme.textTheme.bodyMedium?.copyWith(color: muted),
                          ),
                        ],
                      )
                    else if (note.isChecklist)
                      _ChecklistPreview(note: note, color: onColor, muted: muted, compact: compact)
                    else if (snippet.isNotEmpty)
                      Text(
                        snippet,
                        textDirection: textDirectionOf(snippet),
                        maxLines: compact ? 2 : 8,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(color: onColor),
                      ),
                    if (title.isEmpty &&
                        snippet.isEmpty &&
                        !note.isChecklist &&
                        !note.hasImages &&
                        !locked)
                      Text(
                        context.l10n.emptyNote,
                        style: theme.textTheme.bodyMedium?.copyWith(color: muted),
                      ),
                    if (note.hasAnyReminder || tagNames.isNotEmpty || note.isShared) ...[
                      const SizedBox(height: AppSpacing.sm),
                      Wrap(
                        spacing: AppSpacing.xs,
                        runSpacing: AppSpacing.xs,
                        children: [
                          if (note.reminderAt != null)
                            _Pill(
                              icon: Icons.alarm,
                              label: formatReminder(note.reminderAt!),
                              color: onColor,
                              strike: note.reminderAt!.isBefore(DateTime.now()),
                            ),
                          if (note.isShared)
                            _Pill(
                              key: const Key('note_shared_pill'),
                              icon: Icons.people_outline,
                              label: context.l10n.sharedHeading,
                              color: onColor,
                            ),
                          if (note.placeReminder != null)
                            _Pill(
                              icon: Icons.place_outlined,
                              label: placeReminderLabel(context, note.placeReminder!),
                              color: onColor,
                            ),
                          for (final name in tagNames.take(3)) _Pill(label: name, color: onColor),
                          if (tagNames.length > 3)
                            _Pill(label: '+${tagNames.length - 3}', color: onColor),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Color _textOn(Color background) =>
      ThemeData.estimateBrightnessForColor(background) == Brightness.dark
      ? Colors.white
      : const Color(0xFF202124);
}

/// The note's first image across the top of the card, with a count when
/// there are more.
class _CardImage extends StatelessWidget {
  const _CardImage({required this.note, required this.height});

  final Note note;
  final double height;

  @override
  Widget build(BuildContext context) {
    final more = note.images.length - 1;
    return SizedBox(
      height: height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          NoteImage(
            image: note.images.first,
            cacheWidth: (360 * MediaQuery.devicePixelRatioOf(context)).round(),
          ),
          if (more > 0)
            PositionedDirectional(
              end: 6,
              bottom: 6,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  child: Text(
                    '+$more',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Colors.white),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ChecklistPreview extends StatelessWidget {
  const _ChecklistPreview({
    required this.note,
    required this.color,
    required this.muted,
    required this.compact,
  });

  final Note note;
  final Color color;
  final Color muted;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final items = note.checklist!;
    final open = items.where((item) => !item.checked).toList();
    final done = items.length - open.length;
    final shown = open.take(compact ? 3 : 8).toList();
    final style = Theme.of(context).textTheme.bodyMedium?.copyWith(color: color);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final item in shown)
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.check_box_outline_blank, size: 18, color: muted),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    item.text,
                    textDirection: textDirectionOf(item.text),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: style,
                  ),
                ),
              ],
            ),
          ),
        if (open.length > shown.length)
          Text(
            context.l10n.nMore(open.length - shown.length),
            style: style?.copyWith(color: muted),
          ),
        if (done > 0) Text(context.l10n.plusTicked(done), style: style?.copyWith(color: muted)),
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({super.key, required this.label, required this.color, this.icon, this.strike = false});

  final String label;
  final Color color;
  final IconData? icon;
  final bool strike;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
        color: color.withValues(alpha: 0.06),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 14, color: color), const SizedBox(width: 4)],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: color,
                decoration: strike ? TextDecoration.lineThrough : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
