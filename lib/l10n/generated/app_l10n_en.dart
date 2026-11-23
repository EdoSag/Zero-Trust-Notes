// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_l10n.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppL10nEn extends AppL10n {
  AppL10nEn([String locale = 'en']) : super(locale);

  @override
  String get cancel => 'Cancel';

  @override
  String get import => 'Import';

  @override
  String get done => 'Done';

  @override
  String get remove => 'Remove';

  @override
  String get delete => 'Delete';

  @override
  String get save => 'Save';

  @override
  String notesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count notes',
      one: '1 note',
    );
    return '$_temp0';
  }

  @override
  String importedNotes(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count notes',
      one: '1 note',
    );
    return 'Imported $_temp0.';
  }

  @override
  String get noteNotFound =>
      'That note could not be found — it may have been deleted.';

  @override
  String get cantOpenNotes => 'Couldn\'t open your notes on this device.';

  @override
  String get tryAgain => 'Try again';

  @override
  String get legacyBanner =>
      'Notes now uses your Zero-Trust account. Bring over the notes from your old vault?';

  @override
  String get later => 'Later';

  @override
  String get legacyWrongPass => 'That passphrase doesn\'t open your old notes.';

  @override
  String get legacyIntegrity =>
      'Your old cloud backup failed its integrity check, so it wasn\'t imported.';

  @override
  String get importFailedConnection =>
      'Couldn\'t import. Check your connection and try again.';

  @override
  String get legacyTitle => 'Import old notes';

  @override
  String get legacyExplain =>
      'Enter the vault passphrase you used before this update. It\'s only needed once.';

  @override
  String get legacyPassLabel => 'Old vault passphrase';

  @override
  String get keepChooseFile => 'Choose your Google Takeout file';

  @override
  String get importFromKeep => 'Import from Google Keep';

  @override
  String get keepExplain =>
      '1. Go to takeout.google.com and choose only \"Keep\".\n2. Download the export to this phone.\n3. Pick the .zip file here (or the .json files from its Keep folder).\n\nThe file is read on this phone and your notes are encrypted before they sync. Labels become tags; colours, pins, archive and checklists come along. Notes already imported are skipped. Images and recordings aren\'t imported yet.';

  @override
  String get chooseFile => 'Choose file';

  @override
  String get cantOpenFile => 'Couldn\'t open that file.';

  @override
  String get noFileChosen => 'No .zip or .json file was chosen.';

  @override
  String get keepNoneFound => 'No Google Keep notes were found in that file.';

  @override
  String get importingNotes => 'Importing your notes…';

  @override
  String keepStopped(String failure) {
    return 'The import stopped part-way ($failure). Run it again to finish; notes already imported are skipped.';
  }

  @override
  String keepImportedTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count notes',
      one: '1 note',
    );
    return 'Imported $_temp0';
  }

  @override
  String keepSkippedDup(int count) {
    return '$count already in Notes, skipped.';
  }

  @override
  String keepSkippedTrash(int count) {
    return '$count from Keep\'s trash, skipped.';
  }

  @override
  String keepAttachmentsSkipped(int count) {
    return '$count images or recordings weren\'t imported.';
  }

  @override
  String get keepEverything => 'Everything came across.';

  @override
  String imageNofM(int n, int total) {
    return 'Image $n of $total';
  }

  @override
  String get opensImage => 'Opens the image';

  @override
  String get removeImageQ => 'Remove this image?';

  @override
  String get removeImageBody =>
      'It will be removed from this note on every device.';

  @override
  String nOfM(int n, int total) {
    return '$n of $total';
  }

  @override
  String get image => 'Image';

  @override
  String get sendImage => 'Send image';

  @override
  String get removeImage => 'Remove image';

  @override
  String get voiceNote => 'Voice note';

  @override
  String get voiceExplain =>
      'Transcribed on this phone. Your voice is never sent anywhere.';

  @override
  String get voiceOnlineOnly =>
      'This phone can only transcribe speech online, which would send your voice to a server, so Notes doesn\'t use it. Voice notes need Android 12 or later with on-device speech recognition.';

  @override
  String get voiceUnavailable =>
      'Speech recognition isn\'t available on this phone, or the microphone isn\'t allowed for Notes.';

  @override
  String get language => 'Language';

  @override
  String get listening => 'Listening…';

  @override
  String get tapMicAndSpeak => 'Tap the microphone and speak.';

  @override
  String get stopListening => 'Stop listening';

  @override
  String get startListening => 'Start listening';

  @override
  String get addToNote => 'Add to note';

  @override
  String voiceLangMissing(String language) {
    return 'Speech recognition for $language isn\'t on this phone yet, and Notes only transcribes on the device. Download $language for offline speech in your phone\'s settings (search for \"offline speech recognition\"), then try again.';
  }

  @override
  String get voiceNeedsMic =>
      'Notes needs the microphone for voice notes. Allow it in your phone\'s settings.';

  @override
  String get voiceNoMatch =>
      'Didn\'t catch that. Tap the microphone and try again.';

  @override
  String get voiceBusy => 'Speech recognition is busy. Try again in a moment.';

  @override
  String voiceStopped(String code) {
    return 'Voice notes stopped ($code). Try again.';
  }

  @override
  String get listItem => 'List item';

  @override
  String tickedItems(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ticked items',
      one: '1 ticked item',
    );
    return '$_temp0';
  }

  @override
  String get removeItem => 'Remove item';

  @override
  String get undo => 'Undo';

  @override
  String get noteArchived => 'Note archived';

  @override
  String get noteUnarchived => 'Note unarchived';

  @override
  String get noteTrashed => 'Note moved to Trash';

  @override
  String get noteRestored => 'Note restored';

  @override
  String get deleteForeverQ => 'Delete forever?';

  @override
  String get deleteForeverBody =>
      'This note will be deleted on every device. This can\'t be undone.';

  @override
  String get restore => 'Restore';

  @override
  String get deleteForever => 'Delete forever';

  @override
  String get unpin => 'Unpin';

  @override
  String get pin => 'Pin';

  @override
  String get unarchive => 'Unarchive';

  @override
  String get archive => 'Archive';

  @override
  String get colour => 'Colour';

  @override
  String get remindMe => 'Remind me';

  @override
  String get send => 'Send';

  @override
  String get moveToTrash => 'Move to Trash';

  @override
  String get reasonSendLocked => 'Send your locked note';

  @override
  String get laterToday => 'Later today';

  @override
  String get tomorrowMorning => 'Tomorrow morning';

  @override
  String get nextWeek => 'Next week';

  @override
  String get pickDateTime => 'Pick date and time';

  @override
  String get removeReminder => 'Remove reminder';

  @override
  String get pickFutureTime => 'Pick a time in the future.';

  @override
  String get reminderNotifsOff =>
      'Reminder saved, but notifications are off for Notes. Turn them on in system settings.';

  @override
  String todayAt(String time) {
    return 'Today, $time';
  }

  @override
  String tomorrowAt(String time) {
    return 'Tomorrow, $time';
  }

  @override
  String yesterdayAt(String time) {
    return 'Yesterday, $time';
  }

  @override
  String get semPinned => 'Pinned.';

  @override
  String get semLocked => 'Locked.';

  @override
  String semImages(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count images.',
      one: '1 image.',
    );
    return '$_temp0';
  }

  @override
  String get semUntitled => 'Untitled note.';

  @override
  String semChecklist(int done, int total) {
    return 'Checklist, $done of $total done.';
  }

  @override
  String semReminder(String when) {
    return 'Reminder $when.';
  }

  @override
  String semTags(String tags) {
    return 'Tags: $tags.';
  }

  @override
  String get semOpensNote => 'Opens note. Long press for more actions.';

  @override
  String get locked => 'Locked';

  @override
  String get emptyNote => 'Empty note';

  @override
  String nMore(int count) {
    return '+ $count more';
  }

  @override
  String plusTicked(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '+ $count ticked items',
      one: '+ 1 ticked item',
    );
    return '$_temp0';
  }

  @override
  String get wrongPassword => 'That password isn\'t right.';

  @override
  String get openLockedNote => 'Open locked note';

  @override
  String get noScreenLock =>
      'This phone has no screen lock, so enter your account password. Set a screen lock to use your fingerprint or face instead.';

  @override
  String get accountPassword => 'Account password';

  @override
  String get open => 'Open';

  @override
  String semNotebook(String name) {
    return 'Notebook: $name';
  }

  @override
  String get none => 'None';

  @override
  String get opensNotebookPicker => 'Opens notebook picker';

  @override
  String get noNotebook => 'No notebook';

  @override
  String get renameNotebook => 'Rename notebook';

  @override
  String get notebook => 'Notebook';

  @override
  String get deleteNotebook => 'Delete notebook';

  @override
  String failedNotebooks(String error) {
    return 'Failed to load notebooks: $error';
  }

  @override
  String get newNotebookName => 'New notebook name';

  @override
  String get createNotebook => 'Create notebook';

  @override
  String get addTag => 'Add tag';

  @override
  String get tags => 'Tags';

  @override
  String get deleteTag => 'Delete tag';

  @override
  String failedTags(String error) {
    return 'Failed to load tags: $error';
  }

  @override
  String get newTagName => 'New tag name';

  @override
  String get createTag => 'Create tag';

  @override
  String get exportAll => 'Export all notes';

  @override
  String get exportThis => 'Export this note';

  @override
  String get exportLockedOne => 'Export includes a locked note';

  @override
  String exportLockedMany(int count) {
    return 'Export includes $count locked notes';
  }

  @override
  String get exportNeedsAuth =>
      'Not exported. Locked notes are only exported after your fingerprint, face or screen lock.';

  @override
  String exportFailed(String error) {
    return 'Export failed: $error';
  }

  @override
  String exportAs(String format) {
    return 'Export as $format';
  }

  @override
  String get widgetDetails => 'Show details on the home screen';

  @override
  String get widgetDetailsBody =>
      'Off: note widgets show a lock. On: note titles and the start of their text are stored unencrypted on this phone for the home screen (the Note widget\'s note, and the newest notes for the Notes list widget). Locked notes never show their text';

  @override
  String get exportFormats => 'Markdown, JSON or PDF';

  @override
  String get keepSubtitle => 'From a Google Takeout file, on this phone';

  @override
  String get importOldVault => 'Import notes from your old vault';

  @override
  String get importOldVaultSub =>
      'Needs the vault passphrase you used before this update';

  @override
  String get syncing => 'Syncing';

  @override
  String get notSynced => 'Not synced';

  @override
  String get notSyncedYet => 'Not synced yet';

  @override
  String get synced => 'Synced';

  @override
  String syncStatus(String status) {
    return 'Sync status: $status';
  }

  @override
  String get syncNow => 'Sync now';

  @override
  String get showTextQ => 'Show note text on the home screen?';

  @override
  String get showTextBody =>
      'This turns on \"Show details on the home screen\" for every note widget, including ones you already placed. Their titles and the start of their text will be stored unencrypted on this phone so the widgets can show them. You can turn this off in Settings.';

  @override
  String get keepHidden => 'Keep hidden';

  @override
  String get showOnAll => 'Show on all widgets';

  @override
  String get chooseNoteToPin => 'Choose a note to pin';

  @override
  String get noNotesCreateFirst => 'No notes yet. Create one first.';

  @override
  String get lockedNote => 'Locked note';

  @override
  String failedNotes(String error) {
    return 'Failed to load notes: $error';
  }

  @override
  String get untitled => '(untitled)';

  @override
  String get noteDeleted => 'Note deleted';

  @override
  String get nothingToSend => 'This note is empty: there is nothing to send.';

  @override
  String imagesNotHere(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count images aren\'t on this device yet, so they weren\'t sent.',
      one: 'One image isn\'t on this device yet, so it wasn\'t sent.',
    );
    return '$_temp0';
  }

  @override
  String get cantShare => 'Couldn\'t open the share sheet.';

  @override
  String get reminderChannel => 'Note reminders';

  @override
  String get reminderChannelDesc => 'Reminders you set on notes';

  @override
  String get noteReminder => 'Note reminder';

  @override
  String get reminder => 'Reminder';

  @override
  String get saveFailed =>
      'Couldn\'t save this note. Your changes are still here; try again.';

  @override
  String get cantOpenCamera => 'Couldn\'t open the camera.';

  @override
  String get cantOpenPhotos => 'Couldn\'t open your photos.';

  @override
  String imagesTooLarge(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count images are over 20 MB, too large to add.',
      one: 'That image is over 20 MB, too large to add.',
    );
    return '$_temp0';
  }

  @override
  String imagesFailed(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Couldn\'t add $count images.',
      one: 'Couldn\'t add an image.',
    );
    return '$_temp0';
  }

  @override
  String sharedSkipped(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count shared items couldn\'t be added (only text and images up to 20 MB can).',
      one:
          'One shared item couldn\'t be added (only text and images up to 20 MB can).',
    );
    return '$_temp0';
  }

  @override
  String get reasonOpenLocked => 'Open your locked note';

  @override
  String get noteLockedMsg =>
      'Note locked. Opening it will ask for your fingerprint, face or screen lock.';

  @override
  String get noteUnlockedMsg => 'Note unlocked.';

  @override
  String get confirmToOpen => 'Confirm it\'s you to open this note.';

  @override
  String get unlock => 'Unlock';

  @override
  String get saving => 'Saving…';

  @override
  String get saved => 'Saved';

  @override
  String get notSaved => 'Not saved';

  @override
  String get inTrash => 'In Trash';

  @override
  String get editNote => 'Edit note';

  @override
  String get newNote => 'New note';

  @override
  String get trashNoEdit =>
      'Notes in Trash can\'t be edited. Restore it to make changes.';

  @override
  String get noteTitle => 'Note title';

  @override
  String get title => 'Title';

  @override
  String get addingImages => 'Adding images';

  @override
  String get unpinNote => 'Unpin note';

  @override
  String get pinNote => 'Pin note';

  @override
  String get changeReminder => 'Change reminder';

  @override
  String get unarchiveNote => 'Unarchive note';

  @override
  String get archiveNote => 'Archive note';

  @override
  String get moreOptions => 'More options';

  @override
  String get takePhoto => 'Take photo';

  @override
  String get addImage => 'Add image';

  @override
  String get hideCheckboxes => 'Hide checkboxes';

  @override
  String get showCheckboxes => 'Show checkboxes';

  @override
  String get editText => 'Edit text';

  @override
  String get previewMarkdown => 'Preview Markdown';

  @override
  String get unlockNote => 'Unlock note';

  @override
  String get lockNote => 'Lock note';

  @override
  String get exportNote => 'Export note';

  @override
  String get saveAndClose => 'Save and close';

  @override
  String get nothingToPreview => 'Nothing to preview yet.';

  @override
  String get noteBody => 'Note body';

  @override
  String get bodyLabel => 'Body (Markdown supported)';

  @override
  String wordCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count words',
      one: '1 word',
    );
    return '$_temp0';
  }

  @override
  String editedAgo(String words, String when) {
    return '$words · Edited $when';
  }

  @override
  String get justNow => 'just now';

  @override
  String secondsAgo(int n) {
    return '${n}s ago';
  }

  @override
  String minutesAgo(int n) {
    return '${n}m ago';
  }

  @override
  String hoursAgo(int n) {
    return '${n}h ago';
  }

  @override
  String daysAgo(int n) {
    return '${n}d ago';
  }

  @override
  String get sortCustom => 'Custom order (drag to move)';

  @override
  String get sortUpdatedDesc => 'Last edited (newest)';

  @override
  String get sortUpdatedAsc => 'Last edited (oldest)';

  @override
  String get sortCreatedDesc => 'Date created (newest)';

  @override
  String get sortCreatedAsc => 'Date created (oldest)';

  @override
  String get sortTitle => 'Title (A-Z)';

  @override
  String get emptyTrashQ => 'Empty Trash?';

  @override
  String get emptyTrashBody =>
      'All notes in Trash will be deleted on every device. This can\'t be undone.';

  @override
  String get emptyTrash => 'Empty Trash';

  @override
  String get viewNotes => 'Notes';

  @override
  String get viewReminders => 'Reminders';

  @override
  String get viewArchive => 'Archive';

  @override
  String get viewTrash => 'Trash';

  @override
  String get syncFailed =>
      'Couldn\'t sync. Your notes are saved on this device and will sync later.';

  @override
  String get searchNotes => 'Search notes';

  @override
  String searchIn(String place) {
    return 'Search $place…';
  }

  @override
  String get closeSearch => 'Close search';

  @override
  String get showAsList => 'Show as list';

  @override
  String get showAsGrid => 'Show as grid';

  @override
  String get trashAfter30 => 'Notes in Trash are deleted after 30 days.';

  @override
  String get newVoiceNote => 'New voice note';

  @override
  String get newChecklist => 'New checklist';

  @override
  String get createNote => 'Create new note';

  @override
  String get tag => 'Tag';

  @override
  String get notebooks => 'Notebooks';

  @override
  String get settings => 'Settings';

  @override
  String get all => 'All';

  @override
  String get unfiled => 'Unfiled';

  @override
  String get checklists => 'Checklists';

  @override
  String get clearFilters => 'Clear filters';

  @override
  String get any => 'Any';

  @override
  String get pinned => 'Pinned';

  @override
  String get others => 'Others';

  @override
  String get noMatch => 'No notes match your search or filter.';

  @override
  String get noNotesHere => 'No notes here yet.';

  @override
  String get noNotesYet => 'No notes yet. Tap + to create one.';

  @override
  String get remindersEmpty => 'Notes with reminders appear here.';

  @override
  String get archiveEmpty => 'Your archived notes appear here.';

  @override
  String get trashEmpty => 'No notes in Trash.';

  @override
  String get colorDefault => 'Default';

  @override
  String get colorRed => 'Red';

  @override
  String get colorOrange => 'Orange';

  @override
  String get colorYellow => 'Yellow';

  @override
  String get colorGreen => 'Green';

  @override
  String get colorTeal => 'Teal';

  @override
  String get colorBlue => 'Blue';

  @override
  String get colorNavy => 'Dark blue';

  @override
  String get colorPurple => 'Purple';

  @override
  String get colorPink => 'Pink';

  @override
  String get colorBrown => 'Brown';

  @override
  String get colorGray => 'Gray';

  @override
  String get widgetTakeANote => 'Take a note…';

  @override
  String get widgetNote => 'Note';

  @override
  String get widgetTapToOpen => 'Tap to open in ZT Notes';

  @override
  String get shareNotebook => 'Share notebook';

  @override
  String get shareWithPeople => 'Share with people';

  @override
  String shareNamed(String name) {
    return 'Share “$name”';
  }

  @override
  String get shareNotebookExplain =>
      'Its notes move into a shared notebook that only the people you invite can read, end-to-end encrypted. Locked notes stay private. Photos show only on your devices for now.';

  @override
  String get shareNoteExplain =>
      'The note moves into a shared space that only the people you invite can read, end-to-end encrypted. Photos show only on your devices for now.';

  @override
  String get joinWithInvite => 'Join with an invite';

  @override
  String get sharedHeading => 'Shared';

  @override
  String get sharedNote => 'Shared note';

  @override
  String get semShared => 'Shared with other people.';

  @override
  String get sharedNotebookDescription =>
      'End-to-end encrypted. Everyone here can add and edit notes; owners can also invite and remove people.';

  @override
  String get moveOutOfSharedQ => 'Move out of the shared notebook?';

  @override
  String get moveOutOfSharedBody => 'The others won\'t see this note any more.';

  @override
  String get moveAction => 'Move';

  @override
  String get lockedCantBeShared =>
      'Locked notes can\'t be shared. Remove the lock first.';

  @override
  String get sharedCantBeLocked =>
      'Shared notes can\'t be locked: the lock is only yours.';

  @override
  String get noPhotosInShared =>
      'Photos and drawings can\'t be added to shared notes yet.';

  @override
  String get sharingUnavailable =>
      'Sharing isn\'t available right now. Check your internet connection.';

  @override
  String get remindAtPlace => 'Remind me at a place';

  @override
  String get removePlaceReminder => 'Remove place reminder';

  @override
  String get imageTextTitle => 'Text from image';

  @override
  String get imageTextPrivacy =>
      'The text is read on this phone. The image is never uploaded.';

  @override
  String get ocrBoth => 'Both';

  @override
  String get ocrEnglish => 'English';

  @override
  String get ocrHebrew => 'Hebrew';

  @override
  String get readingImageText => 'Reading the text…';

  @override
  String get cantReadImageText => 'Couldn\'t read the text in this image.';

  @override
  String get noImageText =>
      'No text found in this image. Try another language above, or a sharper photo.';

  @override
  String get copyText => 'Copy';

  @override
  String get textCopied => 'Text copied';

  @override
  String get textFromPhoto => 'Text from a photo';

  @override
  String get grabImageText => 'Grab image text';

  @override
  String get choosePhoto => 'Choose a photo';

  @override
  String get addDrawing => 'Drawing';

  @override
  String get newDrawing => 'New drawing';

  @override
  String get editDrawing => 'Edit drawing';

  @override
  String get saveDrawing => 'Save drawing';

  @override
  String get drawSomethingFirst => 'Draw something first.';

  @override
  String get discardDrawingQ => 'Discard your changes to this drawing?';

  @override
  String get keepDrawing => 'Keep drawing';

  @override
  String get discard => 'Discard';

  @override
  String get colorBlack => 'Black';

  @override
  String get pen => 'Pen';

  @override
  String get highlighter => 'Highlighter';

  @override
  String get eraser => 'Eraser';

  @override
  String get redo => 'Redo';

  @override
  String get clearDrawing => 'Clear page';

  @override
  String get drawingCanvas => 'Drawing area. Draw with a finger or a stylus.';

  @override
  String get cantOpenDrawing =>
      'This drawing can\'t be opened for editing here yet. Sync, then try again.';

  @override
  String thickness(int size) {
    return 'Thickness $size';
  }

  @override
  String get widgetNotes => 'Notes';

  @override
  String get widgetPinned => 'Pinned';

  @override
  String get widgetNoNotes => 'No notes yet';

  @override
  String get widgetNoPinned => 'No pinned notes';

  @override
  String get widgetNotesHidden =>
      'Turn on \"Show details on the home screen\" in ZT Notes settings to see your notes here';

  @override
  String get widgetOpenToSeeNotes => 'Open ZT Notes to see your notes';

  @override
  String get widgetSwitchView => 'Switch between all notes and pinned notes';

  @override
  String get widgetPhotoNote => 'New note with a photo';

  @override
  String get insertIntoKeyboard => 'Insert into ZT Keyboard';

  @override
  String get insertPickHint => 'Tap a note, then the line to type.';

  @override
  String get insertNoNotes => 'No notes match.';

  @override
  String get insertWholeNote => 'Whole note';

  @override
  String get insertLockedHidden => 'Locked notes are not offered here.';

  @override
  String get widgetChecklist => 'Checklist';

  @override
  String get widgetChecklistEmpty => 'Nothing on this list';

  @override
  String get widgetChecklistHidden =>
      'Turn on \"Show details on the home screen\" in ZT Notes settings to tick items here';

  @override
  String get widgetOpenToSeeChecklist => 'Open ZT Notes to see this list';

  @override
  String get widgetPickChecklist => 'Tap to pick a checklist';

  @override
  String get widgetOpenChecklist => 'Open the checklist in ZT Notes';

  @override
  String get widgetTick => 'Tick';

  @override
  String get widgetUntick => 'Untick';

  @override
  String get chooseChecklistToPin => 'Choose a checklist for the widget';

  @override
  String get noChecklistsCreateFirst =>
      'No checklists yet. Make a checklist note first, then add the widget again.';

  @override
  String get handwritingToText => 'Handwriting to text';

  @override
  String get handwritingTextTitle => 'Handwriting to text';

  @override
  String get handwritingTextPrivacy =>
      'Your writing is read on this phone, line by line. Nothing is uploaded. Clear, printed letters read best.';

  @override
  String get noHandwritingText =>
      'No words found. Try another language above, or write larger and more clearly.';

  @override
  String get writeSomethingFirst => 'Write something first';

  @override
  String get keepDrawingTooQ => 'Keep the drawing too?';

  @override
  String get keepDrawingTooBody =>
      'The text goes into the note. You can also keep the handwriting as a drawing.';

  @override
  String get textOnly => 'Text only';

  @override
  String get textAndDrawing => 'Text and drawing';

  @override
  String get linkToNote => 'Link to a note';

  @override
  String get searchNotesToLink => 'Search notes';

  @override
  String get noNotesToLink => 'No notes with a title to link to.';

  @override
  String createLinkedNote(String title) {
    return 'Make the note \"$title\"';
  }

  @override
  String openLinkedNote(String title) {
    return 'Open \"$title\"';
  }

  @override
  String linksHere(String title) {
    return '\"$title\" links here';
  }

  @override
  String get templates => 'Templates';

  @override
  String get templatesSubtitle =>
      'Notes to start from, and what today\'s note looks like';

  @override
  String templatesHelp(String tokens) {
    return 'Start a note from a template with \"New from template\" in the notes list. The one marked here is what \"Today\'s note\" starts from. Use $tokens in a template and they are filled in.';
  }

  @override
  String get newFromTemplate => 'New from template';

  @override
  String get todaysNote => 'Today\'s note';

  @override
  String get manageTemplates => 'Manage templates';

  @override
  String get saveAsTemplate => 'Save as template';

  @override
  String get templateName => 'Template name';

  @override
  String templateSaved(String name) {
    return 'Saved the template \"$name\"';
  }

  @override
  String get renameTemplate => 'Rename';

  @override
  String get deleteTemplate => 'Delete template';

  @override
  String get builtInTemplate => 'Built in';

  @override
  String get ownTemplate => 'Your template';

  @override
  String get dailyNoteTemplate => 'Used for today\'s note';

  @override
  String get templateJournal => 'Daily journal';

  @override
  String templateJournalBody(String date) {
    return '## $date\n\n**Today I want to**\n- \n\n**Notes**\n\n\n**Grateful for**\n- ';
  }

  @override
  String get templateMeeting => 'Meeting notes';

  @override
  String templateMeetingTitle(String date) {
    return 'Meeting $date';
  }

  @override
  String get templateMeetingBody =>
      '**Who:** \n**About:** \n\n## Notes\n\n\n## Decisions\n- \n\n## Next steps\n- [ ] ';

  @override
  String get templateTodo => 'To-do list';

  @override
  String templateTodoTitle(String date) {
    return 'To do $date';
  }

  @override
  String get templateTodoItems => 'Most important first\nThen this\nAnd this';

  @override
  String get versionHistory => 'Version history';

  @override
  String get versionHistoryHelp =>
      'Earlier versions of this note, kept on your devices and encrypted like your notes. A version is kept each time you come back to edit (at most every 10 minutes), up to the last 30.';

  @override
  String get noVersionsYet =>
      'No earlier versions yet. They appear here after the note\'s text changes.';

  @override
  String get cantLoadVersions => 'Can\'t load the history right now.';

  @override
  String get restoreVersion => 'Restore';

  @override
  String get versionRestored =>
      'Earlier version brought back. The text before it is in the history.';

  @override
  String get attachFile => 'Attach file';

  @override
  String get attachedFile => 'File';

  @override
  String openFile(String name) {
    return 'Open $name';
  }

  @override
  String get openInAnotherApp => 'Open in another app';

  @override
  String get removeFile => 'Remove file';

  @override
  String filesTooLarge(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count files are over 20 MB, too large to attach.',
      one: 'That file is over 20 MB, too large to attach.',
    );
    return '$_temp0';
  }

  @override
  String filesFailed(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Couldn\'t attach $count files.',
      one: 'Couldn\'t attach a file.',
    );
    return '$_temp0';
  }

  @override
  String get cantOpenPdf =>
      'Can\'t show this PDF. Try opening it in another app.';

  @override
  String pdfPageNofM(int page, int pages) {
    return 'Page $page of $pages';
  }

  @override
  String get exportMarkdownFolder =>
      'Markdown folder (.zip, with pictures and files)';

  @override
  String get importFromOtherApps => 'Import from other apps';

  @override
  String get otherAppsSubtitle =>
      'Evernote, Standard Notes, Apple Notes, Markdown';

  @override
  String get otherAppsExplain =>
      'Choose the export file (or several, or a .zip):\n\n• Evernote: export notebooks or notes as .enex.\n• Standard Notes: Settings, Backups, download a decrypted backup.\n• Apple Notes: request a copy of your iCloud Notes at privacy.apple.com, or export them as Markdown with an exporter app.\n• Obsidian, Joplin and other Markdown apps: a .zip of the folder, or the .md files.\n\nThe files are read on this phone and your notes are encrypted before they sync. Tags, folders (as notebooks), pictures and files up to 20 MB come along. Notes already imported are skipped.';

  @override
  String importProgress(int done, int total) {
    return 'Importing $done of $total…';
  }

  @override
  String otherSkippedTrash(int count) {
    return '$count from the other app\'s trash, skipped.';
  }

  @override
  String otherFilesSkipped(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count pictures or files weren\'t added (over 20 MB, or unreadable).',
      one: '1 picture or file wasn\'t added (over 20 MB, or unreadable).',
    );
    return '$_temp0';
  }

  @override
  String otherEncrypted(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count notes are in an encrypted backup and can\'t be read. Download a decrypted backup instead.',
      one:
          '1 note is in an encrypted backup and can\'t be read. Download a decrypted backup instead.',
    );
    return '$_temp0';
  }

  @override
  String get otherNoneFound =>
      'No notes found in that file. Choose an .enex, a Standard Notes backup, or Markdown, text or HTML notes.';
}
