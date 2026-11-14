import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:zero_trust_core/zero_trust_core.dart';
import 'package:zt_places/zt_places.dart';
import 'package:zt_sharing_ui/zt_sharing_ui.dart';

import '../../../shared/theme/app_spacing.dart';
import '../../../shared/widgets/accessible_touch_target.dart';
import '../../export/presentation/export_sheet.dart';
import '../../drawing/drawing.dart';
import '../../drawing/drawing_page.dart';
import '../../image_text/image_text_sheet.dart';
import '../../images/note_image_picker.dart';
import '../../images/note_image_views.dart';
import '../../notebooks/domain/notebook.dart';
import '../../notebooks/presentation/notebook_picker.dart';
import '../../places/note_place_reminder.dart';
import '../../places/place_providers.dart';
import '../../sharing/note_sharing.dart';
import '../../sharing/sharing_flows.dart';
import '../../tags/presentation/tag_picker.dart';
import '../../voice/voice_note_sheet.dart';
import '../../../shared/text_direction.dart';
import '../application/note_lock.dart';
import '../../widgets/domain/pending_widget_action.dart';
import '../application/notes_providers.dart';
import '../data/notes_repository.dart';
import '../domain/checklist_item.dart';
import '../domain/note.dart';
import '../domain/note_color.dart';
import 'checklist_editor.dart';
import 'note_actions.dart';
import 'package:zerotrust_notes/l10n/l10n.dart';

enum _SaveStatus { idle, saving, saved, failed }

class NoteEditorPage extends ConsumerStatefulWidget {
  const NoteEditorPage({
    super.key,
    this.note,
    this.startAsChecklist = false,
    this.initialNotebookId,
    this.initialTagId,
    this.archived = false,
    this.shared,
    this.startWithVoice = false,
    this.startWithPhoto = false,
  });

  final Note? note;

  /// For a new note: open the voice note sheet straight away.
  final bool startWithVoice;

  /// For a new note: open the camera straight away (the photos picker on a
  /// device without one), from the quick capture widget.
  final bool startWithPhoto;

  /// For a new note made from what another app shared.
  final SharedContent? shared;

  /// For a new note: start with checkboxes.
  final bool startAsChecklist;

  /// For a new note made while a notebook or tag is shown.
  final String? initialNotebookId;
  final String? initialTagId;

  /// For a new note made in the Archive view.
  final bool archived;

  @override
  ConsumerState<NoteEditorPage> createState() => _NoteEditorPageState();
}

class _NoteEditorPageState extends ConsumerState<NoteEditorPage> {
  late final TextEditingController _titleController = TextEditingController(
    text: widget.note?.title ?? widget.shared?.title ?? '',
  );
  late final TextEditingController _bodyController = TextEditingController(
    text: widget.note?.isChecklist ?? false ? '' : widget.note?.body ?? widget.shared?.body ?? '',
  );

  Note? _note;
  String? _notebookId;
  List<String> _tagIds = const [];
  bool _pinned = false;
  bool _archived = false;
  NoteColor _color = NoteColor.none;
  List<ChecklistItem>? _checklist;
  DateTime? _reminderAt;
  NotePlaceReminder? _placeReminder;
  List<ZtAttachmentRef> _images = const [];
  Map<String, ZtAttachmentRef> _drawings = const {};
  bool _locked = false;

  /// A locked note stays hidden until the phone's lock confirms it's the
  /// owner. Always true for an unlocked note.
  bool _lockOpen = true;

  /// Images being encrypted and stored right now.
  int _addingImages = 0;
  DateTime? _lastSavedAt;
  Timer? _debounce;
  _SaveStatus _status = _SaveStatus.idle;
  bool _dirty = false;
  bool _previewMode = false;

  /// Saves run one after another, so a quick second edit can't create the
  /// note twice.
  Future<bool> _saving = Future.value(true);

  bool get _isEditing => _note != null;

  /// Kept in a shared space now, or will be once saved (its notebook is
  /// shared).
  bool get _inShared => _note?.isShared == true || Notebook.spaceIdOf(_notebookId) != null;

  /// Shared on its own, not as part of a shared notebook.
  bool get _sharedAlone => _note?.isShared == true && Notebook.spaceIdOf(_notebookId) == null;
  bool get _inTrash => _note?.isTrashed ?? false;

  @override
  void initState() {
    super.initState();
    final note = widget.note;
    _note = note;
    _notebookId = note?.notebookId ?? widget.initialNotebookId;
    _tagIds = note?.tagIds ?? [?widget.initialTagId];
    _pinned = note?.pinned ?? false;
    _archived = note?.archived ?? widget.archived;
    _color = note?.color ?? NoteColor.none;
    _checklist = note?.checklist ?? (widget.startAsChecklist && note == null ? const [] : null);
    _reminderAt = note?.reminderAt;
    _placeReminder = note?.placeReminder;
    // A place reminder that goes off while the note is open is done: the
    // editor lets it go too, so saving doesn't put it back.
    _dropFiredPlaceReminder(ref.read(firedPlaceRemindersProvider));
    ref.listenManual(firedPlaceRemindersProvider, (_, fired) => _dropFiredPlaceReminder(fired));
    _images = note?.images ?? const [];
    _drawings = note?.drawings ?? const {};
    _locked = note?.locked ?? false;
    _lockOpen = !_locked;
    if (!_lockOpen) WidgetsBinding.instance.addPostFrameCallback((_) => _openLock());
    if (widget.startWithVoice && note == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _dictate());
    }
    if (widget.startWithPhoto && note == null) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _pickImages(_hasCamera ? NoteImageSource.camera : NoteImageSource.gallery),
      );
    }
    _lastSavedAt = note?.updatedAt;
    _titleController.addListener(_onTextChanged);
    _bodyController.addListener(_onTextChanged);
    final shared = widget.shared;
    if (shared != null && note == null) {
      // Shared text counts as an edit: save it even if nothing is typed.
      if (shared.title.isNotEmpty || shared.body.isNotEmpty) _dirty = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _takeShared(shared));
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _titleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  void _onTextChanged() => _changed(debounce: true);

  /// Marks the note changed; text edits wait a moment, other changes save
  /// at once.
  void _changed({bool debounce = false}) {
    if (_inTrash) return;
    _dirty = true;
    setState(() => _status = _SaveStatus.saving);
    _debounce?.cancel();
    if (debounce) {
      _debounce = Timer(const Duration(milliseconds: 800), _persist);
    } else {
      _persist();
    }
  }

  String get _body => _checklist != null
      ? ChecklistItem.toMarkdown(ChecklistItem.ordered(_checklist!))
      : _bodyController.text;

  bool get _isBlank =>
      _images.isEmpty &&
      _titleController.text.trim().isEmpty &&
      _body.trim().isEmpty &&
      (_checklist?.every((item) => item.text.trim().isEmpty) ?? true);

  /// Saves now. Returns false when the save failed; the edits stay marked
  /// unsaved so the next attempt writes them.
  Future<bool> _persist() {
    _debounce?.cancel();
    // Read now: this also runs as the page pops, after which `ref` is gone.
    final repository = ref.read(notesRepositoryProvider);
    final result = _saving
        .then((_) => _persistNow(repository))
        .then(
          (_) => true,
          onError: (Object _) {
            if (mounted) {
              setState(() => _status = _SaveStatus.failed);
              ScaffoldMessenger.maybeOf(
                context,
              )?.showSnackBar(SnackBar(content: Text(context.l10n.saveFailed)));
            }
            return false;
          },
        );
    _saving = result;
    return result;
  }

  void _dropFiredPlaceReminder(Set<String> fired) {
    final note = _note;
    final reminder = _placeReminder;
    if (note == null || reminder == null || !fired.contains(reminder.idFor(note.id))) return;
    if (mounted) {
      setState(() => _placeReminder = null);
    } else {
      _placeReminder = null;
    }
  }

  Future<void> _persistNow(NotesRepository? repository) async {
    if (!_dirty || repository == null) return;
    // Don't create an empty note just because the editor was opened.
    if (_note == null && _isBlank) {
      _dirty = false;
      return;
    }
    _dirty = false;
    try {
      await _write(repository);
    } on Object {
      _dirty = true; // Keep the edits for the next save.
      rethrow;
    }
    _lastSavedAt = DateTime.now();
    if (mounted) setState(() => _status = _SaveStatus.saved);
  }

  Future<void> _write(NotesRepository repository) async {
    final checklist = _checklist == null ? null : ChecklistItem.ordered(_checklist!);
    if (_note == null) {
      _note = await repository.createNote(
        title: _titleController.text,
        body: _body,
        notebookId: _notebookId,
        tagIds: _tagIds,
        pinned: _pinned,
        color: _color,
        archived: _archived,
        checklist: checklist,
        reminderAt: _reminderAt,
        images: _images,
        locked: _locked,
        placeReminder: _placeReminder,
        drawings: _drawings,
      );
    } else {
      final updated = _note!.copyWith(
        title: _titleController.text,
        body: _body,
        notebookId: _notebookId,
        tagIds: _tagIds,
        pinned: _pinned,
        color: _color,
        archived: _archived,
        checklist: checklist,
        reminderAt: _reminderAt,
        images: _images,
        locked: _locked,
        placeReminder: _placeReminder,
        drawings: _drawings,
      );
      _note = await repository.updateNote(updated);
    }
  }

  void _snack(String message) =>
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(message)));

  static bool get _hasCamera =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  Future<void> _pickImages(NoteImageSource source) async {
    final List<PickedImage> picked;
    try {
      picked = await ref
          .read(vaultControllerProvider.notifier)
          .whileShowingSystemUi(() => ref.read(noteImagePickerProvider).pick(source));
    } on Object {
      if (mounted) {
        _snack(
          source == NoteImageSource.camera
              ? context.l10n.cantOpenCamera
              : context.l10n.cantOpenPhotos,
        );
      }
      return;
    }
    await _addImages([
      for (final image in picked)
        () async => (bytes: image.bytes, mimeType: image.mimeType, name: image.name),
    ]);
  }

  /// Encrypts and stores each image, then adds it to the note. Each source
  /// is read only when its turn comes, so large shares don't all sit in
  /// memory at once.
  Future<int> _addImages(
    List<Future<({Uint8List bytes, String? mimeType, String? name})> Function()> sources,
  ) async {
    final repository = ref.read(notesRepositoryProvider);
    if (repository == null || sources.isEmpty) return 0;
    setState(() => _addingImages += sources.length);
    var tooLarge = 0;
    var failed = 0;
    var added = 0;
    for (final source in sources) {
      try {
        final image = await source();
        final stored = await repository.addImage(
          image.bytes,
          mimeType: image.mimeType,
          name: image.name,
        );
        if (!mounted) {
          // The page closed mid-way: nothing will reference this file.
          await repository.releaseImages([stored]);
          continue;
        }
        setState(() => _images = [..._images, stored]);
        added++;
        _changed();
      } on AttachmentTooLarge {
        tooLarge++;
      } on Object {
        failed++;
      } finally {
        if (mounted) setState(() => _addingImages--);
      }
    }
    if (mounted && tooLarge > 0) {
      _snack(context.l10n.imagesTooLarge(tooLarge));
    } else if (mounted && failed > 0) {
      _snack(context.l10n.imagesFailed(failed));
    }
    return added;
  }

  Future<void> _takeShared(SharedContent shared) async {
    if (shared.title.isNotEmpty || shared.body.isNotEmpty) _changed();
    final files = shared.images;
    await _addImages([
      for (final file in files)
        () async {
          final plain = File(file.path);
          try {
            return (bytes: await plain.readAsBytes(), mimeType: file.mimeType, name: file.name);
          } finally {
            // Only the encrypted copy stays on the device.
            try {
              await plain.delete();
              // The share's own folder, once its last image is read.
              await plain.parent.delete();
            } on Object {
              // Already gone, or other images still to read.
            }
          }
        },
    ]);
    if (mounted && shared.skipped > 0) {
      _snack(context.l10n.sharedSkipped(shared.skipped));
    }
  }

  void _openImage(int index) {
    final sharing = NoteSharing(context, ref);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => NoteImageViewer(
          images: _images,
          initialIndex: index,
          onRemove: _inTrash ? null : _removeImage,
          onShare: sharing.shareImage,
          onGrabText: _inTrash ? null : _grabImageText,
          onEditDrawing: _inTrash ? null : _editDrawing,
          isDrawing: (image) => _drawings.containsKey(image.id),
        ),
      ),
    );
  }

  Future<void> _removeImage(ZtAttachmentRef image) async {
    final repository = ref.read(notesRepositoryProvider);
    final strokes = _drawings[image.id];
    setState(() {
      _images = [
        for (final i in _images)
          if (i.id != image.id) i,
      ];
      if (strokes != null) _drawings = {..._drawings}..remove(image.id);
    });
    _changed();
    // Delete the file only once the note no longer points at it.
    if (await _saving) await repository?.releaseImages([image, ?strokes]);
  }

  /// Adds [text] read from an image: at the end of the text, or as new
  /// checklist items.
  void _appendText(String text) {
    if (text.trim().isEmpty) return;
    setState(() {
      if (_checklist != null) {
        _checklist = [..._checklist!, ...ChecklistItem.parseLines(text)];
      } else {
        final current = _bodyController.text.trimRight();
        _bodyController.text = current.isEmpty ? text : '$current\n\n$text';
        _previewMode = false;
      }
    });
    _changed();
  }

  Future<void> _textFromPhoto() async {
    final source = await showModalBottomSheet<NoteImageSource>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(24, 0, 24, 8),
              child: Text(sheetContext.l10n.imageTextPrivacy),
            ),
            if (_hasCamera)
              ListTile(
                leading: const Icon(Icons.photo_camera_outlined),
                title: Text(sheetContext.l10n.takePhoto),
                onTap: () => Navigator.of(sheetContext).pop(NoteImageSource.camera),
              ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text(sheetContext.l10n.choosePhoto),
              onTap: () => Navigator.of(sheetContext).pop(NoteImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;
    final List<PickedImage> picked;
    try {
      picked = await ref
          .read(vaultControllerProvider.notifier)
          .whileShowingSystemUi(() => ref.read(noteImagePickerProvider).pick(source));
    } on Object {
      if (mounted) {
        _snack(
          source == NoteImageSource.camera ? context.l10n.cantOpenCamera : context.l10n.cantOpenPhotos,
        );
      }
      return;
    }
    if (picked.isEmpty || !mounted) return;
    final text = await showImageTextSheet(context, picked.first.bytes);
    if (text != null && mounted) _appendText(text);
  }

  Future<void> _grabImageText(ZtAttachmentRef image) async {
    final repository = ref.read(notesRepositoryProvider);
    if (repository == null) return;
    final Uint8List bytes;
    try {
      bytes = await repository.readImage(image);
    } on Object {
      if (mounted) _snack(context.l10n.cantReadImageText);
      return;
    }
    if (!mounted) return;
    final text = await showImageTextSheet(context, bytes);
    if (text != null && mounted) _appendText(text);
  }

  Future<void> _addDrawing() async {
    final result = await DrawingPage.open(context);
    if (result == null || !mounted) return;
    await _storeDrawing(result);
  }

  Future<void> _editDrawing(ZtAttachmentRef image) async {
    final repository = ref.read(notesRepositoryProvider);
    final strokesRef = _drawings[image.id];
    if (repository == null || strokesRef == null) return;
    Drawing? drawing;
    try {
      drawing = Drawing.decode(await repository.readImage(strokesRef));
    } on Object {
      drawing = null;
    }
    if (!mounted) return;
    if (drawing == null) {
      _snack(context.l10n.cantOpenDrawing);
      return;
    }
    final result = await DrawingPage.open(context, initial: drawing);
    if (result == null || !mounted) return;
    await _storeDrawing(result, replacing: image);
  }

  /// Encrypts and stores a drawing (picture and strokes) and puts it in the
  /// note: in place of [replacing], or after the other images.
  Future<void> _storeDrawing(DrawingResult result, {ZtAttachmentRef? replacing}) async {
    final repository = ref.read(notesRepositoryProvider);
    if (repository == null) return;
    setState(() => _addingImages++);
    try {
      final picture = await repository.addImage(
        result.png,
        mimeType: 'image/png',
        name: 'drawing.png',
      );
      final strokes = await repository.addFile(
        result.drawing.encode(),
        mimeType: Drawing.mimeType,
        name: Drawing.fileName,
      );
      if (!mounted) return;
      final old = replacing == null ? null : _drawings[replacing.id];
      setState(() {
        final at = replacing == null ? -1 : _images.indexWhere((i) => i.id == replacing.id);
        _images = at < 0
            ? [..._images, picture]
            : [..._images.sublist(0, at), picture, ..._images.sublist(at + 1)];
        _drawings = {
          for (final e in _drawings.entries)
            if (e.key != replacing?.id) e.key: e.value,
          picture.id: strokes,
        };
      });
      _changed();
      if (replacing != null && await _saving) {
        await repository.releaseImages([replacing, ?old]);
      }
    } on AttachmentTooLarge {
      if (mounted) _snack(context.l10n.imagesTooLarge(1));
    } on Object {
      if (mounted) _snack(context.l10n.imagesFailed(1));
    } finally {
      if (mounted) setState(() => _addingImages--);
    }
  }

  Future<void> _openLock() async {
    final ok = await ref
        .read(noteLockAuthenticatorProvider)
        .confirm(context, ref, reason: context.l10n.reasonOpenLocked);
    if (ok && mounted) setState(() => _lockOpen = true);
  }

  void _toggleLock() {
    if (!_locked && _inShared) {
      _snack(context.l10n.sharedCantBeLocked);
      return;
    }
    setState(() => _locked = !_locked);
    _changed();
    _snack(_locked ? context.l10n.noteLockedMsg : context.l10n.noteUnlockedMsg);
  }

  /// Speaks into the note: the transcript goes after the text (or as a new
  /// checklist item).
  Future<void> _dictate() async {
    final text = await showVoiceNoteSheet(context);
    if (text == null || text.trim().isEmpty || !mounted) return;
    final spoken = text.trim();
    if (_checklist != null) {
      setState(() => _checklist = [..._checklist!, ChecklistItem.create(spoken)]);
    } else {
      final current = _bodyController.text.trimRight();
      _bodyController.text = current.isEmpty ? spoken : '$current\n$spoken';
      _bodyController.selection = TextSelection.collapsed(offset: _bodyController.text.length);
    }
    _changed();
  }

  Widget _lockedScreen(ThemeData theme) => Scaffold(
    appBar: AppBar(title: Text(context.l10n.lockedNote)),
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_outline, size: 56, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: AppSpacing.md),
            Text(
              widget.note?.title.trim().isNotEmpty ?? false
                  ? widget.note!.title
                  : context.l10n.lockedNote,
              textDirection: textDirectionOf(widget.note?.title ?? ''),
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(context.l10n.confirmToOpen, textAlign: TextAlign.center),
            const SizedBox(height: AppSpacing.md),
            FilledButton.icon(
              onPressed: _openLock,
              icon: const Icon(Icons.fingerprint),
              label: Text(context.l10n.unlock),
            ),
          ],
        ),
      ),
    ),
  );

  Future<void> _send() async {
    if (!await _persist() || !mounted) return;
    final note = _note;
    if (note == null) {
      _snack(context.l10n.nothingToSend);
      return;
    }
    await NoteSharing(context, ref).shareNote(note);
  }

  Future<void> _saveAndClose() async {
    if (await _persist() && mounted) Navigator.of(context).pop();
  }

  Future<void> _setNotebook(String? notebookId) async {
    final from = Notebook.spaceIdOf(_notebookId);
    final to = Notebook.spaceIdOf(notebookId);
    if (to != null && _locked) {
      _snack(context.l10n.lockedCantBeShared);
      return;
    }
    if (from != null && from != to && _note?.isShared == true) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(context.l10n.moveOutOfSharedQ),
          content: Text(context.l10n.moveOutOfSharedBody),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(context.l10n.cancel)),
            TextButton(
              key: const Key('move_out_of_shared'),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(context.l10n.moveAction),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }
    setState(() => _notebookId = notebookId);
    _changed();
  }

  /// Shares the note on its own, or shows who it is shared with.
  Future<void> _share() async {
    if (_note == null || _dirty) {
      if (!await _persist() || !mounted) return;
    }
    final note = _note;
    if (note == null) return;
    if (Notebook.spaceIdOf(_notebookId) case final spaceId?) {
      await openSharedSpace(context, ref, spaceId);
      return;
    }
    final shared = await shareNoteFlow(context, ref, note);
    if (shared != null && mounted) {
      setState(() {
        _note = shared;
        _notebookId = null;
      });
    }
  }

  void _setTags(List<String> tagIds) {
    setState(() => _tagIds = tagIds);
    _changed();
  }

  void _togglePin() {
    setState(() {
      _pinned = !_pinned;
      if (_pinned) _archived = false;
    });
    _changed();
  }

  Future<void> _toggleArchive() async {
    setState(() {
      _archived = !_archived;
      if (_archived) _pinned = false;
    });
    _changed();
    await _saving;
    if (!mounted) return;
    final wasArchived = _archived;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(wasArchived ? context.l10n.noteArchived : context.l10n.noteUnarchived),
      ),
    );
    if (wasArchived) Navigator.of(context).pop();
  }

  Future<void> _pickColor() async {
    final color = await showNoteColorPicker(context, _color);
    if (color == null || color == _color) return;
    setState(() => _color = color);
    _changed();
  }

  Future<void> _pickReminder() async {
    final choice = await showReminderPicker(context, ref, _reminderAt);
    if (choice == null) return;
    setState(() => _reminderAt = choice.at);
    _changed();
  }

  Future<void> _pickPlace() async {
    final places = ref.read(placeRemindersProvider);
    // Wait for the saved places the first time, so the list isn't empty
    // just because it was still loading.
    var saved = const <ZtPlace>[];
    final listening = ref.listenManual(savedPlacesProvider, (_, _) {});
    try {
      saved = await ref.read(savedPlacesProvider.future).timeout(const Duration(seconds: 3));
    } on Object {
      saved = ref.read(savedPlacesProvider).value ?? const <ZtPlace>[];
    } finally {
      listening.close();
    }
    if (!mounted) return;
    final repository = ref.read(savedPlacesRepositoryProvider);
    final choice = await ZtPlacePickerPage.show(
      context,
      reminders: places,
      savedPlaces: saved,
      initialPlace: _placeReminder?.place,
      initialTrigger: _placeReminder?.trigger ?? ZtPlaceTrigger.arrive,
      onRemovePlace: repository == null ? null : (place) => repository.delete(place.id),
      newId: () => const Uuid().v4(),
    );
    if (choice == null || !mounted) return;
    if (choice.saveToPlaces) await repository?.save(choice.place);
    if (!mounted) return;
    setState(
      () => _placeReminder = NotePlaceReminder(
        place: choice.place,
        trigger: choice.trigger,
        setAt: DateTime.now().toUtc(),
      ),
    );
    _changed();
  }

  void _toggleChecklist() {
    setState(() {
      if (_checklist == null) {
        _checklist = ChecklistItem.parseLines(_bodyController.text);
        _bodyController.removeListener(_onTextChanged);
        _bodyController.clear();
        _bodyController.addListener(_onTextChanged);
        _previewMode = false;
      } else {
        final text = [for (final item in _checklist!) item.text].join('\n');
        _checklist = null;
        _bodyController.removeListener(_onTextChanged);
        _bodyController.text = text;
        _bodyController.addListener(_onTextChanged);
      }
    });
    _changed();
  }

  void _onChecklistChanged(List<ChecklistItem> items, {required bool typing}) {
    setState(() => _checklist = items);
    _changed(debounce: typing);
  }

  Future<void> _moveToTrash() async {
    if (!await _persist()) return;
    final note = _note;
    if (note == null) {
      if (mounted) Navigator.of(context).pop();
      return;
    }
    if (!mounted) return;
    final actions = NoteActions(context, ref);
    Navigator.of(context).pop();
    await actions.moveToTrash(note);
  }

  Future<void> _restore() async {
    final note = _note;
    if (note == null) return;
    final restored = await NoteActions(context, ref).restore(note);
    if (restored != null && mounted) setState(() => _note = restored);
  }

  Future<void> _deleteForever() async {
    final note = _note;
    if (note == null) return;
    if (await NoteActions(context, ref).deleteForever(note) && mounted) {
      Navigator.of(context).pop();
    }
  }

  int get _wordCount {
    final text = _body.trim();
    if (text.isEmpty) return 0;
    return text.split(RegExp(r'\s+')).length;
  }

  String get _statusLabel => switch (_status) {
    _SaveStatus.idle => '',
    _SaveStatus.saving => context.l10n.saving,
    _SaveStatus.saved => context.l10n.saved,
    _SaveStatus.failed => context.l10n.notSaved,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (!_lockOpen) return _lockedScreen(theme);
    final background = _color.background(theme.brightness);
    final isChecklist = _checklist != null;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): _saveAndClose,
        const SingleActivator(LogicalKeyboardKey.keyS, meta: true): _saveAndClose,
        const SingleActivator(LogicalKeyboardKey.escape): _saveAndClose,
      },
      child: Focus(
        autofocus: true,
        child: PopScope(
          onPopInvokedWithResult: (didPop, _) {
            if (didPop) _persist();
          },
          child: Scaffold(
            backgroundColor: background,
            appBar: AppBar(
              backgroundColor: background,
              title: Semantics(
                header: true,
                child: Text(
                  _inTrash
                      ? context.l10n.inTrash
                      : (_isEditing ? context.l10n.editNote : context.l10n.newNote),
                ),
              ),
              actions: _inTrash ? _trashActions() : _editActions(isChecklist),
            ),
            body: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_inTrash)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: Text(context.l10n.trashNoEdit, style: theme.textTheme.bodySmall),
                    ),
                  Semantics(
                    textField: true,
                    label: context.l10n.noteTitle,
                    child: TextField(
                      key: const Key('note_title_field'),
                      controller: _titleController,
                      textDirection: textDirectionOf(_titleController.text),
                      readOnly: _inTrash,
                      decoration: InputDecoration(
                        labelText: context.l10n.title,
                        border: OutlineInputBorder(),
                      ),
                      textInputAction: TextInputAction.next,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  if (!_inTrash)
                    Wrap(
                      spacing: AppSpacing.xs,
                      runSpacing: AppSpacing.xs,
                      children: [
                        if (_sharedAlone)
                          ActionChip(
                            key: const Key('shared_note_chip'),
                            avatar: const Icon(Icons.people_outline, size: 18),
                            label: Text(context.l10n.sharedNote),
                            onPressed: _share,
                          )
                        else
                          NotebookField(notebookId: _notebookId, onChanged: _setNotebook),
                        TagField(tagIds: _tagIds, onChanged: _setTags),
                        if (_reminderAt != null)
                          InputChip(
                            avatar: const Icon(Icons.alarm, size: 18),
                            label: Text(formatReminder(_reminderAt!)),
                            onPressed: _pickReminder,
                            onDeleted: () {
                              setState(() => _reminderAt = null);
                              _changed();
                            },
                            deleteButtonTooltipMessage: context.l10n.removeReminder,
                          ),
                        if (_placeReminder != null)
                          InputChip(
                            key: const Key('note_place_reminder_chip'),
                            avatar: const Icon(Icons.place_outlined, size: 18),
                            label: Text(placeReminderLabel(context, _placeReminder!)),
                            onPressed: _pickPlace,
                            onDeleted: () {
                              setState(() => _placeReminder = null);
                              _changed();
                            },
                            deleteButtonTooltipMessage: context.l10n.removePlaceReminder,
                          ),
                      ],
                    ),
                  const SizedBox(height: AppSpacing.sm),
                  if (_images.isNotEmpty) ...[
                    NoteImageStrip(images: _images, onOpen: _openImage),
                    const SizedBox(height: AppSpacing.sm),
                  ],
                  if (_addingImages > 0) ...[
                    Semantics(
                      liveRegion: true,
                      label: context.l10n.addingImages,
                      child: const LinearProgressIndicator(),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                  ],
                  Expanded(child: isChecklist ? _checklistBody() : _textBody(theme)),
                  const SizedBox(height: AppSpacing.xs),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      _footerText(),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _trashActions() => [
    AccessibleIconButton(
      label: context.l10n.restore,
      icon: Icons.restore_from_trash_outlined,
      onPressed: _restore,
    ),
    AccessibleIconButton(
      label: context.l10n.deleteForever,
      icon: Icons.delete_forever_outlined,
      onPressed: _deleteForever,
    ),
  ];

  List<Widget> _editActions(bool isChecklist) => [
    Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      child: Center(
        child: Semantics(
          liveRegion: true,
          child: Text(_statusLabel, style: Theme.of(context).textTheme.bodySmall),
        ),
      ),
    ),
    AccessibleIconButton(
      label: _pinned ? context.l10n.unpinNote : context.l10n.pinNote,
      icon: _pinned ? Icons.push_pin : Icons.push_pin_outlined,
      onPressed: _togglePin,
    ),
    AccessibleIconButton(
      label: _reminderAt == null ? context.l10n.remindMe : context.l10n.changeReminder,
      icon: _reminderAt == null ? Icons.add_alert_outlined : Icons.notifications_active_outlined,
      onPressed: _pickReminder,
    ),
    AccessibleIconButton(
      label: _archived ? context.l10n.unarchiveNote : context.l10n.archiveNote,
      icon: _archived ? Icons.unarchive_outlined : Icons.archive_outlined,
      onPressed: _toggleArchive,
    ),
    PopupMenuButton<String>(
      tooltip: context.l10n.moreOptions,
      onSelected: (value) {
        switch (value) {
          case 'voice':
            _dictate();
          case 'place':
            _pickPlace();
          case 'draw':
            _addDrawing();
          case 'scanText':
            _textFromPhoto();
          case 'lock':
            _toggleLock();
          case 'share':
            _share();
          case 'camera':
            _pickImages(NoteImageSource.camera);
          case 'gallery':
            _pickImages(NoteImageSource.gallery);
          case 'send':
            _send();
          case 'color':
            _pickColor();
          case 'checklist':
            _toggleChecklist();
          case 'preview':
            setState(() => _previewMode = !_previewMode);
          case 'export':
            if (_note != null) showExportSheet(context, singleNote: _note);
          case 'trash':
            _moveToTrash();
          case 'save':
            _saveAndClose();
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'voice',
          child: ListTile(leading: Icon(Icons.mic_none), title: Text(context.l10n.voiceNote)),
        ),
        PopupMenuItem(
          value: 'place',
          child: ListTile(
            leading: Icon(Icons.add_location_alt_outlined),
            title: Text(context.l10n.remindAtPlace),
          ),
        ),
        if (!_inShared)
          PopupMenuItem(
            value: 'draw',
            child: ListTile(leading: Icon(Icons.draw_outlined), title: Text(context.l10n.addDrawing)),
          ),
        PopupMenuItem(
          value: 'scanText',
          child: ListTile(
            leading: Icon(Icons.document_scanner_outlined),
            title: Text(context.l10n.textFromPhoto),
          ),
        ),
        if (_hasCamera && !_inShared)
          PopupMenuItem(
            value: 'camera',
            child: ListTile(
              leading: Icon(Icons.photo_camera_outlined),
              title: Text(context.l10n.takePhoto),
            ),
          ),
        if (!_inShared)
          PopupMenuItem(
            value: 'gallery',
            child: ListTile(
              leading: Icon(Icons.add_photo_alternate_outlined),
              title: Text(context.l10n.addImage),
            ),
          ),
        if (!_inTrash && !_locked)
          PopupMenuItem(
            value: 'share',
            child: ListTile(
              leading: const Icon(Icons.group_add_outlined),
              title: Text(
                _inShared
                    ? ZtSharingStrings.of(context).peopleAndSharing
                    : context.l10n.shareWithPeople,
              ),
            ),
          ),
        PopupMenuItem(
          value: 'send',
          child: ListTile(leading: Icon(Icons.share_outlined), title: Text(context.l10n.send)),
        ),
        PopupMenuItem(
          value: 'color',
          child: ListTile(leading: Icon(Icons.palette_outlined), title: Text(context.l10n.colour)),
        ),
        PopupMenuItem(
          value: 'checklist',
          child: ListTile(
            leading: Icon(isChecklist ? Icons.notes : Icons.checklist),
            title: Text(isChecklist ? context.l10n.hideCheckboxes : context.l10n.showCheckboxes),
          ),
        ),
        if (!isChecklist)
          PopupMenuItem(
            value: 'preview',
            child: ListTile(
              leading: Icon(_previewMode ? Icons.edit_outlined : Icons.visibility_outlined),
              title: Text(_previewMode ? context.l10n.editText : context.l10n.previewMarkdown),
            ),
          ),
        if (!_inShared)
          PopupMenuItem(
            value: 'lock',
            child: ListTile(
              leading: Icon(_locked ? Icons.lock_open_outlined : Icons.lock_outline),
              title: Text(_locked ? context.l10n.unlockNote : context.l10n.lockNote),
            ),
          ),
        if (_isEditing)
          PopupMenuItem(
            value: 'export',
            child: ListTile(leading: Icon(Icons.ios_share), title: Text(context.l10n.exportNote)),
          ),
        if (_isEditing)
          PopupMenuItem(
            value: 'trash',
            child: ListTile(
              leading: Icon(Icons.delete_outline),
              title: Text(context.l10n.moveToTrash),
            ),
          ),
        PopupMenuItem(
          value: 'save',
          child: ListTile(leading: Icon(Icons.check), title: Text(context.l10n.saveAndClose)),
        ),
      ],
    ),
  ];

  Widget _checklistBody() =>
      ChecklistEditor(items: _checklist!, readOnly: _inTrash, onChanged: _onChecklistChanged);

  Widget _textBody(ThemeData theme) {
    if (_previewMode || _inTrash) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          border: Border.all(color: theme.colorScheme.outline),
          borderRadius: BorderRadius.circular(4),
        ),
        child: _bodyController.text.trim().isEmpty
            ? Text(
                context.l10n.nothingToPreview,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              )
            : Markdown(
                data: _bodyController.text,
                selectable: true,
                styleSheet: MarkdownStyleSheet.fromTheme(theme),
              ),
      );
    }
    return Semantics(
      textField: true,
      label: context.l10n.noteBody,
      child: TextField(
        key: const Key('note_body_field'),
        controller: _bodyController,
        textDirection: textDirectionOf(_bodyController.text),
        decoration: InputDecoration(
          labelText: context.l10n.bodyLabel,
          border: OutlineInputBorder(),
          alignLabelWithHint: true,
        ),
        maxLines: null,
        expands: true,
        textAlignVertical: TextAlignVertical.top,
      ),
    );
  }

  String _footerText() {
    final words = context.l10n.wordCount(_wordCount);
    if (_lastSavedAt == null) return words;
    return context.l10n.editedAgo(words, _relativeTime(_lastSavedAt!));
  }

  String _relativeTime(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inSeconds < 10) return context.l10n.justNow;
    if (diff.inMinutes < 1) return context.l10n.secondsAgo(diff.inSeconds);
    if (diff.inHours < 1) return context.l10n.minutesAgo(diff.inMinutes);
    if (diff.inDays < 1) return context.l10n.hoursAgo(diff.inHours);
    if (diff.inDays < 7) return context.l10n.daysAgo(diff.inDays);
    return '${time.year}-${time.month.toString().padLeft(2, '0')}-${time.day.toString().padLeft(2, '0')}';
  }
}
