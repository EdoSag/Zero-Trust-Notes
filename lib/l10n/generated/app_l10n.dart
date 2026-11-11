import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_l10n_en.dart';
import 'app_l10n_he.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppL10n
/// returned by `AppL10n.of(context)`.
///
/// Applications need to include `AppL10n.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_l10n.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppL10n.localizationsDelegates,
///   supportedLocales: AppL10n.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppL10n.supportedLocales
/// property.
abstract class AppL10n {
  AppL10n(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppL10n of(BuildContext context) {
    return Localizations.of<AppL10n>(context, AppL10n)!;
  }

  static const LocalizationsDelegate<AppL10n> delegate = _AppL10nDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('he'),
  ];

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @import.
  ///
  /// In en, this message translates to:
  /// **'Import'**
  String get import;

  /// No description provided for @done.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get done;

  /// No description provided for @remove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get remove;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @notesCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 note} other{{count} notes}}'**
  String notesCount(int count);

  /// No description provided for @importedNotes.
  ///
  /// In en, this message translates to:
  /// **'Imported {count, plural, =1{1 note} other{{count} notes}}.'**
  String importedNotes(int count);

  /// No description provided for @noteNotFound.
  ///
  /// In en, this message translates to:
  /// **'That note could not be found — it may have been deleted.'**
  String get noteNotFound;

  /// No description provided for @cantOpenNotes.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t open your notes on this device.'**
  String get cantOpenNotes;

  /// No description provided for @tryAgain.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get tryAgain;

  /// No description provided for @legacyBanner.
  ///
  /// In en, this message translates to:
  /// **'Notes now uses your Zero-Trust account. Bring over the notes from your old vault?'**
  String get legacyBanner;

  /// No description provided for @later.
  ///
  /// In en, this message translates to:
  /// **'Later'**
  String get later;

  /// No description provided for @legacyWrongPass.
  ///
  /// In en, this message translates to:
  /// **'That passphrase doesn\'t open your old notes.'**
  String get legacyWrongPass;

  /// No description provided for @legacyIntegrity.
  ///
  /// In en, this message translates to:
  /// **'Your old cloud backup failed its integrity check, so it wasn\'t imported.'**
  String get legacyIntegrity;

  /// No description provided for @importFailedConnection.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t import. Check your connection and try again.'**
  String get importFailedConnection;

  /// No description provided for @legacyTitle.
  ///
  /// In en, this message translates to:
  /// **'Import old notes'**
  String get legacyTitle;

  /// No description provided for @legacyExplain.
  ///
  /// In en, this message translates to:
  /// **'Enter the vault passphrase you used before this update. It\'s only needed once.'**
  String get legacyExplain;

  /// No description provided for @legacyPassLabel.
  ///
  /// In en, this message translates to:
  /// **'Old vault passphrase'**
  String get legacyPassLabel;

  /// No description provided for @keepChooseFile.
  ///
  /// In en, this message translates to:
  /// **'Choose your Google Takeout file'**
  String get keepChooseFile;

  /// No description provided for @importFromKeep.
  ///
  /// In en, this message translates to:
  /// **'Import from Google Keep'**
  String get importFromKeep;

  /// No description provided for @keepExplain.
  ///
  /// In en, this message translates to:
  /// **'1. Go to takeout.google.com and choose only \"Keep\".\n2. Download the export to this phone.\n3. Pick the .zip file here (or the .json files from its Keep folder).\n\nThe file is read on this phone and your notes are encrypted before they sync. Labels become tags; colours, pins, archive and checklists come along. Notes already imported are skipped. Images and recordings aren\'t imported yet.'**
  String get keepExplain;

  /// No description provided for @chooseFile.
  ///
  /// In en, this message translates to:
  /// **'Choose file'**
  String get chooseFile;

  /// No description provided for @cantOpenFile.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t open that file.'**
  String get cantOpenFile;

  /// No description provided for @noFileChosen.
  ///
  /// In en, this message translates to:
  /// **'No .zip or .json file was chosen.'**
  String get noFileChosen;

  /// No description provided for @keepNoneFound.
  ///
  /// In en, this message translates to:
  /// **'No Google Keep notes were found in that file.'**
  String get keepNoneFound;

  /// No description provided for @importingNotes.
  ///
  /// In en, this message translates to:
  /// **'Importing your notes…'**
  String get importingNotes;

  /// No description provided for @keepStopped.
  ///
  /// In en, this message translates to:
  /// **'The import stopped part-way ({failure}). Run it again to finish; notes already imported are skipped.'**
  String keepStopped(String failure);

  /// No description provided for @keepImportedTitle.
  ///
  /// In en, this message translates to:
  /// **'Imported {count, plural, =1{1 note} other{{count} notes}}'**
  String keepImportedTitle(int count);

  /// No description provided for @keepSkippedDup.
  ///
  /// In en, this message translates to:
  /// **'{count} already in Notes, skipped.'**
  String keepSkippedDup(int count);

  /// No description provided for @keepSkippedTrash.
  ///
  /// In en, this message translates to:
  /// **'{count} from Keep\'s trash, skipped.'**
  String keepSkippedTrash(int count);

  /// No description provided for @keepAttachmentsSkipped.
  ///
  /// In en, this message translates to:
  /// **'{count} images or recordings weren\'t imported.'**
  String keepAttachmentsSkipped(int count);

  /// No description provided for @keepEverything.
  ///
  /// In en, this message translates to:
  /// **'Everything came across.'**
  String get keepEverything;

  /// No description provided for @imageNofM.
  ///
  /// In en, this message translates to:
  /// **'Image {n} of {total}'**
  String imageNofM(int n, int total);

  /// No description provided for @opensImage.
  ///
  /// In en, this message translates to:
  /// **'Opens the image'**
  String get opensImage;

  /// No description provided for @removeImageQ.
  ///
  /// In en, this message translates to:
  /// **'Remove this image?'**
  String get removeImageQ;

  /// No description provided for @removeImageBody.
  ///
  /// In en, this message translates to:
  /// **'It will be removed from this note on every device.'**
  String get removeImageBody;

  /// No description provided for @nOfM.
  ///
  /// In en, this message translates to:
  /// **'{n} of {total}'**
  String nOfM(int n, int total);

  /// No description provided for @image.
  ///
  /// In en, this message translates to:
  /// **'Image'**
  String get image;

  /// No description provided for @sendImage.
  ///
  /// In en, this message translates to:
  /// **'Send image'**
  String get sendImage;

  /// No description provided for @removeImage.
  ///
  /// In en, this message translates to:
  /// **'Remove image'**
  String get removeImage;

  /// No description provided for @voiceNote.
  ///
  /// In en, this message translates to:
  /// **'Voice note'**
  String get voiceNote;

  /// No description provided for @voiceExplain.
  ///
  /// In en, this message translates to:
  /// **'Transcribed on this phone. Your voice is never sent anywhere.'**
  String get voiceExplain;

  /// No description provided for @voiceOnlineOnly.
  ///
  /// In en, this message translates to:
  /// **'This phone can only transcribe speech online, which would send your voice to a server, so Notes doesn\'t use it. Voice notes need Android 12 or later with on-device speech recognition.'**
  String get voiceOnlineOnly;

  /// No description provided for @voiceUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Speech recognition isn\'t available on this phone, or the microphone isn\'t allowed for Notes.'**
  String get voiceUnavailable;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @listening.
  ///
  /// In en, this message translates to:
  /// **'Listening…'**
  String get listening;

  /// No description provided for @tapMicAndSpeak.
  ///
  /// In en, this message translates to:
  /// **'Tap the microphone and speak.'**
  String get tapMicAndSpeak;

  /// No description provided for @stopListening.
  ///
  /// In en, this message translates to:
  /// **'Stop listening'**
  String get stopListening;

  /// No description provided for @startListening.
  ///
  /// In en, this message translates to:
  /// **'Start listening'**
  String get startListening;

  /// No description provided for @addToNote.
  ///
  /// In en, this message translates to:
  /// **'Add to note'**
  String get addToNote;

  /// No description provided for @voiceLangMissing.
  ///
  /// In en, this message translates to:
  /// **'Speech recognition for {language} isn\'t on this phone yet, and Notes only transcribes on the device. Download {language} for offline speech in your phone\'s settings (search for \"offline speech recognition\"), then try again.'**
  String voiceLangMissing(String language);

  /// No description provided for @voiceNeedsMic.
  ///
  /// In en, this message translates to:
  /// **'Notes needs the microphone for voice notes. Allow it in your phone\'s settings.'**
  String get voiceNeedsMic;

  /// No description provided for @voiceNoMatch.
  ///
  /// In en, this message translates to:
  /// **'Didn\'t catch that. Tap the microphone and try again.'**
  String get voiceNoMatch;

  /// No description provided for @voiceBusy.
  ///
  /// In en, this message translates to:
  /// **'Speech recognition is busy. Try again in a moment.'**
  String get voiceBusy;

  /// No description provided for @voiceStopped.
  ///
  /// In en, this message translates to:
  /// **'Voice notes stopped ({code}). Try again.'**
  String voiceStopped(String code);

  /// No description provided for @listItem.
  ///
  /// In en, this message translates to:
  /// **'List item'**
  String get listItem;

  /// No description provided for @tickedItems.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 ticked item} other{{count} ticked items}}'**
  String tickedItems(int count);

  /// No description provided for @removeItem.
  ///
  /// In en, this message translates to:
  /// **'Remove item'**
  String get removeItem;

  /// No description provided for @undo.
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get undo;

  /// No description provided for @noteArchived.
  ///
  /// In en, this message translates to:
  /// **'Note archived'**
  String get noteArchived;

  /// No description provided for @noteUnarchived.
  ///
  /// In en, this message translates to:
  /// **'Note unarchived'**
  String get noteUnarchived;

  /// No description provided for @noteTrashed.
  ///
  /// In en, this message translates to:
  /// **'Note moved to Trash'**
  String get noteTrashed;

  /// No description provided for @noteRestored.
  ///
  /// In en, this message translates to:
  /// **'Note restored'**
  String get noteRestored;

  /// No description provided for @deleteForeverQ.
  ///
  /// In en, this message translates to:
  /// **'Delete forever?'**
  String get deleteForeverQ;

  /// No description provided for @deleteForeverBody.
  ///
  /// In en, this message translates to:
  /// **'This note will be deleted on every device. This can\'t be undone.'**
  String get deleteForeverBody;

  /// No description provided for @restore.
  ///
  /// In en, this message translates to:
  /// **'Restore'**
  String get restore;

  /// No description provided for @deleteForever.
  ///
  /// In en, this message translates to:
  /// **'Delete forever'**
  String get deleteForever;

  /// No description provided for @unpin.
  ///
  /// In en, this message translates to:
  /// **'Unpin'**
  String get unpin;

  /// No description provided for @pin.
  ///
  /// In en, this message translates to:
  /// **'Pin'**
  String get pin;

  /// No description provided for @unarchive.
  ///
  /// In en, this message translates to:
  /// **'Unarchive'**
  String get unarchive;

  /// No description provided for @archive.
  ///
  /// In en, this message translates to:
  /// **'Archive'**
  String get archive;

  /// No description provided for @colour.
  ///
  /// In en, this message translates to:
  /// **'Colour'**
  String get colour;

  /// No description provided for @remindMe.
  ///
  /// In en, this message translates to:
  /// **'Remind me'**
  String get remindMe;

  /// No description provided for @send.
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get send;

  /// No description provided for @moveToTrash.
  ///
  /// In en, this message translates to:
  /// **'Move to Trash'**
  String get moveToTrash;

  /// No description provided for @reasonSendLocked.
  ///
  /// In en, this message translates to:
  /// **'Send your locked note'**
  String get reasonSendLocked;

  /// No description provided for @laterToday.
  ///
  /// In en, this message translates to:
  /// **'Later today'**
  String get laterToday;

  /// No description provided for @tomorrowMorning.
  ///
  /// In en, this message translates to:
  /// **'Tomorrow morning'**
  String get tomorrowMorning;

  /// No description provided for @nextWeek.
  ///
  /// In en, this message translates to:
  /// **'Next week'**
  String get nextWeek;

  /// No description provided for @pickDateTime.
  ///
  /// In en, this message translates to:
  /// **'Pick date and time'**
  String get pickDateTime;

  /// No description provided for @removeReminder.
  ///
  /// In en, this message translates to:
  /// **'Remove reminder'**
  String get removeReminder;

  /// No description provided for @pickFutureTime.
  ///
  /// In en, this message translates to:
  /// **'Pick a time in the future.'**
  String get pickFutureTime;

  /// No description provided for @reminderNotifsOff.
  ///
  /// In en, this message translates to:
  /// **'Reminder saved, but notifications are off for Notes. Turn them on in system settings.'**
  String get reminderNotifsOff;

  /// No description provided for @todayAt.
  ///
  /// In en, this message translates to:
  /// **'Today, {time}'**
  String todayAt(String time);

  /// No description provided for @tomorrowAt.
  ///
  /// In en, this message translates to:
  /// **'Tomorrow, {time}'**
  String tomorrowAt(String time);

  /// No description provided for @yesterdayAt.
  ///
  /// In en, this message translates to:
  /// **'Yesterday, {time}'**
  String yesterdayAt(String time);

  /// No description provided for @semPinned.
  ///
  /// In en, this message translates to:
  /// **'Pinned.'**
  String get semPinned;

  /// No description provided for @semLocked.
  ///
  /// In en, this message translates to:
  /// **'Locked.'**
  String get semLocked;

  /// No description provided for @semImages.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 image.} other{{count} images.}}'**
  String semImages(int count);

  /// No description provided for @semUntitled.
  ///
  /// In en, this message translates to:
  /// **'Untitled note.'**
  String get semUntitled;

  /// No description provided for @semChecklist.
  ///
  /// In en, this message translates to:
  /// **'Checklist, {done} of {total} done.'**
  String semChecklist(int done, int total);

  /// No description provided for @semReminder.
  ///
  /// In en, this message translates to:
  /// **'Reminder {when}.'**
  String semReminder(String when);

  /// No description provided for @semTags.
  ///
  /// In en, this message translates to:
  /// **'Tags: {tags}.'**
  String semTags(String tags);

  /// No description provided for @semOpensNote.
  ///
  /// In en, this message translates to:
  /// **'Opens note. Long press for more actions.'**
  String get semOpensNote;

  /// No description provided for @locked.
  ///
  /// In en, this message translates to:
  /// **'Locked'**
  String get locked;

  /// No description provided for @emptyNote.
  ///
  /// In en, this message translates to:
  /// **'Empty note'**
  String get emptyNote;

  /// No description provided for @nMore.
  ///
  /// In en, this message translates to:
  /// **'+ {count} more'**
  String nMore(int count);

  /// No description provided for @plusTicked.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{+ 1 ticked item} other{+ {count} ticked items}}'**
  String plusTicked(int count);

  /// No description provided for @wrongPassword.
  ///
  /// In en, this message translates to:
  /// **'That password isn\'t right.'**
  String get wrongPassword;

  /// No description provided for @openLockedNote.
  ///
  /// In en, this message translates to:
  /// **'Open locked note'**
  String get openLockedNote;

  /// No description provided for @noScreenLock.
  ///
  /// In en, this message translates to:
  /// **'This phone has no screen lock, so enter your account password. Set a screen lock to use your fingerprint or face instead.'**
  String get noScreenLock;

  /// No description provided for @accountPassword.
  ///
  /// In en, this message translates to:
  /// **'Account password'**
  String get accountPassword;

  /// No description provided for @open.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get open;

  /// No description provided for @semNotebook.
  ///
  /// In en, this message translates to:
  /// **'Notebook: {name}'**
  String semNotebook(String name);

  /// No description provided for @none.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get none;

  /// No description provided for @opensNotebookPicker.
  ///
  /// In en, this message translates to:
  /// **'Opens notebook picker'**
  String get opensNotebookPicker;

  /// No description provided for @noNotebook.
  ///
  /// In en, this message translates to:
  /// **'No notebook'**
  String get noNotebook;

  /// No description provided for @renameNotebook.
  ///
  /// In en, this message translates to:
  /// **'Rename notebook'**
  String get renameNotebook;

  /// No description provided for @notebook.
  ///
  /// In en, this message translates to:
  /// **'Notebook'**
  String get notebook;

  /// No description provided for @deleteNotebook.
  ///
  /// In en, this message translates to:
  /// **'Delete notebook'**
  String get deleteNotebook;

  /// No description provided for @failedNotebooks.
  ///
  /// In en, this message translates to:
  /// **'Failed to load notebooks: {error}'**
  String failedNotebooks(String error);

  /// No description provided for @newNotebookName.
  ///
  /// In en, this message translates to:
  /// **'New notebook name'**
  String get newNotebookName;

  /// No description provided for @createNotebook.
  ///
  /// In en, this message translates to:
  /// **'Create notebook'**
  String get createNotebook;

  /// No description provided for @addTag.
  ///
  /// In en, this message translates to:
  /// **'Add tag'**
  String get addTag;

  /// No description provided for @tags.
  ///
  /// In en, this message translates to:
  /// **'Tags'**
  String get tags;

  /// No description provided for @deleteTag.
  ///
  /// In en, this message translates to:
  /// **'Delete tag'**
  String get deleteTag;

  /// No description provided for @failedTags.
  ///
  /// In en, this message translates to:
  /// **'Failed to load tags: {error}'**
  String failedTags(String error);

  /// No description provided for @newTagName.
  ///
  /// In en, this message translates to:
  /// **'New tag name'**
  String get newTagName;

  /// No description provided for @createTag.
  ///
  /// In en, this message translates to:
  /// **'Create tag'**
  String get createTag;

  /// No description provided for @exportAll.
  ///
  /// In en, this message translates to:
  /// **'Export all notes'**
  String get exportAll;

  /// No description provided for @exportThis.
  ///
  /// In en, this message translates to:
  /// **'Export this note'**
  String get exportThis;

  /// No description provided for @exportLockedOne.
  ///
  /// In en, this message translates to:
  /// **'Export includes a locked note'**
  String get exportLockedOne;

  /// No description provided for @exportLockedMany.
  ///
  /// In en, this message translates to:
  /// **'Export includes {count} locked notes'**
  String exportLockedMany(int count);

  /// No description provided for @exportNeedsAuth.
  ///
  /// In en, this message translates to:
  /// **'Not exported. Locked notes are only exported after your fingerprint, face or screen lock.'**
  String get exportNeedsAuth;

  /// No description provided for @exportFailed.
  ///
  /// In en, this message translates to:
  /// **'Export failed: {error}'**
  String exportFailed(String error);

  /// No description provided for @exportAs.
  ///
  /// In en, this message translates to:
  /// **'Export as {format}'**
  String exportAs(String format);

  /// No description provided for @widgetDetails.
  ///
  /// In en, this message translates to:
  /// **'Show details on the home screen'**
  String get widgetDetails;

  /// No description provided for @widgetDetailsBody.
  ///
  /// In en, this message translates to:
  /// **'Off: the Note widget shows a lock. On: the title and start of each pinned note are stored unencrypted on this phone for the home screen. Locked notes never show their text'**
  String get widgetDetailsBody;

  /// No description provided for @exportFormats.
  ///
  /// In en, this message translates to:
  /// **'Markdown, JSON or PDF'**
  String get exportFormats;

  /// No description provided for @keepSubtitle.
  ///
  /// In en, this message translates to:
  /// **'From a Google Takeout file, on this phone'**
  String get keepSubtitle;

  /// No description provided for @importOldVault.
  ///
  /// In en, this message translates to:
  /// **'Import notes from your old vault'**
  String get importOldVault;

  /// No description provided for @importOldVaultSub.
  ///
  /// In en, this message translates to:
  /// **'Needs the vault passphrase you used before this update'**
  String get importOldVaultSub;

  /// No description provided for @syncing.
  ///
  /// In en, this message translates to:
  /// **'Syncing'**
  String get syncing;

  /// No description provided for @notSynced.
  ///
  /// In en, this message translates to:
  /// **'Not synced'**
  String get notSynced;

  /// No description provided for @notSyncedYet.
  ///
  /// In en, this message translates to:
  /// **'Not synced yet'**
  String get notSyncedYet;

  /// No description provided for @synced.
  ///
  /// In en, this message translates to:
  /// **'Synced'**
  String get synced;

  /// No description provided for @syncStatus.
  ///
  /// In en, this message translates to:
  /// **'Sync status: {status}'**
  String syncStatus(String status);

  /// No description provided for @syncNow.
  ///
  /// In en, this message translates to:
  /// **'Sync now'**
  String get syncNow;

  /// No description provided for @showTextQ.
  ///
  /// In en, this message translates to:
  /// **'Show note text on the home screen?'**
  String get showTextQ;

  /// No description provided for @showTextBody.
  ///
  /// In en, this message translates to:
  /// **'This turns on \"Show details on the home screen\" for every note widget, including ones you already placed. Their titles and the start of their text will be stored unencrypted on this phone so the widgets can show them. You can turn this off in Settings.'**
  String get showTextBody;

  /// No description provided for @keepHidden.
  ///
  /// In en, this message translates to:
  /// **'Keep hidden'**
  String get keepHidden;

  /// No description provided for @showOnAll.
  ///
  /// In en, this message translates to:
  /// **'Show on all widgets'**
  String get showOnAll;

  /// No description provided for @chooseNoteToPin.
  ///
  /// In en, this message translates to:
  /// **'Choose a note to pin'**
  String get chooseNoteToPin;

  /// No description provided for @noNotesCreateFirst.
  ///
  /// In en, this message translates to:
  /// **'No notes yet. Create one first.'**
  String get noNotesCreateFirst;

  /// No description provided for @lockedNote.
  ///
  /// In en, this message translates to:
  /// **'Locked note'**
  String get lockedNote;

  /// No description provided for @failedNotes.
  ///
  /// In en, this message translates to:
  /// **'Failed to load notes: {error}'**
  String failedNotes(String error);

  /// No description provided for @untitled.
  ///
  /// In en, this message translates to:
  /// **'(untitled)'**
  String get untitled;

  /// No description provided for @noteDeleted.
  ///
  /// In en, this message translates to:
  /// **'Note deleted'**
  String get noteDeleted;

  /// No description provided for @nothingToSend.
  ///
  /// In en, this message translates to:
  /// **'This note is empty: there is nothing to send.'**
  String get nothingToSend;

  /// No description provided for @imagesNotHere.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{One image isn\'t on this device yet, so it wasn\'t sent.} other{{count} images aren\'t on this device yet, so they weren\'t sent.}}'**
  String imagesNotHere(int count);

  /// No description provided for @cantShare.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t open the share sheet.'**
  String get cantShare;

  /// No description provided for @reminderChannel.
  ///
  /// In en, this message translates to:
  /// **'Note reminders'**
  String get reminderChannel;

  /// No description provided for @reminderChannelDesc.
  ///
  /// In en, this message translates to:
  /// **'Reminders you set on notes'**
  String get reminderChannelDesc;

  /// No description provided for @noteReminder.
  ///
  /// In en, this message translates to:
  /// **'Note reminder'**
  String get noteReminder;

  /// No description provided for @reminder.
  ///
  /// In en, this message translates to:
  /// **'Reminder'**
  String get reminder;

  /// No description provided for @saveFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t save this note. Your changes are still here; try again.'**
  String get saveFailed;

  /// No description provided for @cantOpenCamera.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t open the camera.'**
  String get cantOpenCamera;

  /// No description provided for @cantOpenPhotos.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t open your photos.'**
  String get cantOpenPhotos;

  /// No description provided for @imagesTooLarge.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{That image is over 20 MB, too large to add.} other{{count} images are over 20 MB, too large to add.}}'**
  String imagesTooLarge(int count);

  /// No description provided for @imagesFailed.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Couldn\'t add an image.} other{Couldn\'t add {count} images.}}'**
  String imagesFailed(int count);

  /// No description provided for @sharedSkipped.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{One shared item couldn\'t be added (only text and images up to 20 MB can).} other{{count} shared items couldn\'t be added (only text and images up to 20 MB can).}}'**
  String sharedSkipped(int count);

  /// No description provided for @reasonOpenLocked.
  ///
  /// In en, this message translates to:
  /// **'Open your locked note'**
  String get reasonOpenLocked;

  /// No description provided for @noteLockedMsg.
  ///
  /// In en, this message translates to:
  /// **'Note locked. Opening it will ask for your fingerprint, face or screen lock.'**
  String get noteLockedMsg;

  /// No description provided for @noteUnlockedMsg.
  ///
  /// In en, this message translates to:
  /// **'Note unlocked.'**
  String get noteUnlockedMsg;

  /// No description provided for @confirmToOpen.
  ///
  /// In en, this message translates to:
  /// **'Confirm it\'s you to open this note.'**
  String get confirmToOpen;

  /// No description provided for @unlock.
  ///
  /// In en, this message translates to:
  /// **'Unlock'**
  String get unlock;

  /// No description provided for @saving.
  ///
  /// In en, this message translates to:
  /// **'Saving…'**
  String get saving;

  /// No description provided for @saved.
  ///
  /// In en, this message translates to:
  /// **'Saved'**
  String get saved;

  /// No description provided for @notSaved.
  ///
  /// In en, this message translates to:
  /// **'Not saved'**
  String get notSaved;

  /// No description provided for @inTrash.
  ///
  /// In en, this message translates to:
  /// **'In Trash'**
  String get inTrash;

  /// No description provided for @editNote.
  ///
  /// In en, this message translates to:
  /// **'Edit note'**
  String get editNote;

  /// No description provided for @newNote.
  ///
  /// In en, this message translates to:
  /// **'New note'**
  String get newNote;

  /// No description provided for @trashNoEdit.
  ///
  /// In en, this message translates to:
  /// **'Notes in Trash can\'t be edited. Restore it to make changes.'**
  String get trashNoEdit;

  /// No description provided for @noteTitle.
  ///
  /// In en, this message translates to:
  /// **'Note title'**
  String get noteTitle;

  /// No description provided for @title.
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get title;

  /// No description provided for @addingImages.
  ///
  /// In en, this message translates to:
  /// **'Adding images'**
  String get addingImages;

  /// No description provided for @unpinNote.
  ///
  /// In en, this message translates to:
  /// **'Unpin note'**
  String get unpinNote;

  /// No description provided for @pinNote.
  ///
  /// In en, this message translates to:
  /// **'Pin note'**
  String get pinNote;

  /// No description provided for @changeReminder.
  ///
  /// In en, this message translates to:
  /// **'Change reminder'**
  String get changeReminder;

  /// No description provided for @unarchiveNote.
  ///
  /// In en, this message translates to:
  /// **'Unarchive note'**
  String get unarchiveNote;

  /// No description provided for @archiveNote.
  ///
  /// In en, this message translates to:
  /// **'Archive note'**
  String get archiveNote;

  /// No description provided for @moreOptions.
  ///
  /// In en, this message translates to:
  /// **'More options'**
  String get moreOptions;

  /// No description provided for @takePhoto.
  ///
  /// In en, this message translates to:
  /// **'Take photo'**
  String get takePhoto;

  /// No description provided for @addImage.
  ///
  /// In en, this message translates to:
  /// **'Add image'**
  String get addImage;

  /// No description provided for @hideCheckboxes.
  ///
  /// In en, this message translates to:
  /// **'Hide checkboxes'**
  String get hideCheckboxes;

  /// No description provided for @showCheckboxes.
  ///
  /// In en, this message translates to:
  /// **'Show checkboxes'**
  String get showCheckboxes;

  /// No description provided for @editText.
  ///
  /// In en, this message translates to:
  /// **'Edit text'**
  String get editText;

  /// No description provided for @previewMarkdown.
  ///
  /// In en, this message translates to:
  /// **'Preview Markdown'**
  String get previewMarkdown;

  /// No description provided for @unlockNote.
  ///
  /// In en, this message translates to:
  /// **'Unlock note'**
  String get unlockNote;

  /// No description provided for @lockNote.
  ///
  /// In en, this message translates to:
  /// **'Lock note'**
  String get lockNote;

  /// No description provided for @exportNote.
  ///
  /// In en, this message translates to:
  /// **'Export note'**
  String get exportNote;

  /// No description provided for @saveAndClose.
  ///
  /// In en, this message translates to:
  /// **'Save and close'**
  String get saveAndClose;

  /// No description provided for @nothingToPreview.
  ///
  /// In en, this message translates to:
  /// **'Nothing to preview yet.'**
  String get nothingToPreview;

  /// No description provided for @noteBody.
  ///
  /// In en, this message translates to:
  /// **'Note body'**
  String get noteBody;

  /// No description provided for @bodyLabel.
  ///
  /// In en, this message translates to:
  /// **'Body (Markdown supported)'**
  String get bodyLabel;

  /// No description provided for @wordCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 word} other{{count} words}}'**
  String wordCount(int count);

  /// No description provided for @editedAgo.
  ///
  /// In en, this message translates to:
  /// **'{words} · Edited {when}'**
  String editedAgo(String words, String when);

  /// No description provided for @justNow.
  ///
  /// In en, this message translates to:
  /// **'just now'**
  String get justNow;

  /// No description provided for @secondsAgo.
  ///
  /// In en, this message translates to:
  /// **'{n}s ago'**
  String secondsAgo(int n);

  /// No description provided for @minutesAgo.
  ///
  /// In en, this message translates to:
  /// **'{n}m ago'**
  String minutesAgo(int n);

  /// No description provided for @hoursAgo.
  ///
  /// In en, this message translates to:
  /// **'{n}h ago'**
  String hoursAgo(int n);

  /// No description provided for @daysAgo.
  ///
  /// In en, this message translates to:
  /// **'{n}d ago'**
  String daysAgo(int n);

  /// No description provided for @sortCustom.
  ///
  /// In en, this message translates to:
  /// **'Custom order (drag to move)'**
  String get sortCustom;

  /// No description provided for @sortUpdatedDesc.
  ///
  /// In en, this message translates to:
  /// **'Last edited (newest)'**
  String get sortUpdatedDesc;

  /// No description provided for @sortUpdatedAsc.
  ///
  /// In en, this message translates to:
  /// **'Last edited (oldest)'**
  String get sortUpdatedAsc;

  /// No description provided for @sortCreatedDesc.
  ///
  /// In en, this message translates to:
  /// **'Date created (newest)'**
  String get sortCreatedDesc;

  /// No description provided for @sortCreatedAsc.
  ///
  /// In en, this message translates to:
  /// **'Date created (oldest)'**
  String get sortCreatedAsc;

  /// No description provided for @sortTitle.
  ///
  /// In en, this message translates to:
  /// **'Title (A-Z)'**
  String get sortTitle;

  /// No description provided for @emptyTrashQ.
  ///
  /// In en, this message translates to:
  /// **'Empty Trash?'**
  String get emptyTrashQ;

  /// No description provided for @emptyTrashBody.
  ///
  /// In en, this message translates to:
  /// **'All notes in Trash will be deleted on every device. This can\'t be undone.'**
  String get emptyTrashBody;

  /// No description provided for @emptyTrash.
  ///
  /// In en, this message translates to:
  /// **'Empty Trash'**
  String get emptyTrash;

  /// No description provided for @viewNotes.
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get viewNotes;

  /// No description provided for @viewReminders.
  ///
  /// In en, this message translates to:
  /// **'Reminders'**
  String get viewReminders;

  /// No description provided for @viewArchive.
  ///
  /// In en, this message translates to:
  /// **'Archive'**
  String get viewArchive;

  /// No description provided for @viewTrash.
  ///
  /// In en, this message translates to:
  /// **'Trash'**
  String get viewTrash;

  /// No description provided for @syncFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t sync. Your notes are saved on this device and will sync later.'**
  String get syncFailed;

  /// No description provided for @searchNotes.
  ///
  /// In en, this message translates to:
  /// **'Search notes'**
  String get searchNotes;

  /// No description provided for @searchIn.
  ///
  /// In en, this message translates to:
  /// **'Search {place}…'**
  String searchIn(String place);

  /// No description provided for @closeSearch.
  ///
  /// In en, this message translates to:
  /// **'Close search'**
  String get closeSearch;

  /// No description provided for @showAsList.
  ///
  /// In en, this message translates to:
  /// **'Show as list'**
  String get showAsList;

  /// No description provided for @showAsGrid.
  ///
  /// In en, this message translates to:
  /// **'Show as grid'**
  String get showAsGrid;

  /// No description provided for @trashAfter30.
  ///
  /// In en, this message translates to:
  /// **'Notes in Trash are deleted after 30 days.'**
  String get trashAfter30;

  /// No description provided for @newVoiceNote.
  ///
  /// In en, this message translates to:
  /// **'New voice note'**
  String get newVoiceNote;

  /// No description provided for @newChecklist.
  ///
  /// In en, this message translates to:
  /// **'New checklist'**
  String get newChecklist;

  /// No description provided for @createNote.
  ///
  /// In en, this message translates to:
  /// **'Create new note'**
  String get createNote;

  /// No description provided for @tag.
  ///
  /// In en, this message translates to:
  /// **'Tag'**
  String get tag;

  /// No description provided for @notebooks.
  ///
  /// In en, this message translates to:
  /// **'Notebooks'**
  String get notebooks;

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// No description provided for @all.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get all;

  /// No description provided for @unfiled.
  ///
  /// In en, this message translates to:
  /// **'Unfiled'**
  String get unfiled;

  /// No description provided for @checklists.
  ///
  /// In en, this message translates to:
  /// **'Checklists'**
  String get checklists;

  /// No description provided for @clearFilters.
  ///
  /// In en, this message translates to:
  /// **'Clear filters'**
  String get clearFilters;

  /// No description provided for @any.
  ///
  /// In en, this message translates to:
  /// **'Any'**
  String get any;

  /// No description provided for @pinned.
  ///
  /// In en, this message translates to:
  /// **'Pinned'**
  String get pinned;

  /// No description provided for @others.
  ///
  /// In en, this message translates to:
  /// **'Others'**
  String get others;

  /// No description provided for @noMatch.
  ///
  /// In en, this message translates to:
  /// **'No notes match your search or filter.'**
  String get noMatch;

  /// No description provided for @noNotesHere.
  ///
  /// In en, this message translates to:
  /// **'No notes here yet.'**
  String get noNotesHere;

  /// No description provided for @noNotesYet.
  ///
  /// In en, this message translates to:
  /// **'No notes yet. Tap + to create one.'**
  String get noNotesYet;

  /// No description provided for @remindersEmpty.
  ///
  /// In en, this message translates to:
  /// **'Notes with reminders appear here.'**
  String get remindersEmpty;

  /// No description provided for @archiveEmpty.
  ///
  /// In en, this message translates to:
  /// **'Your archived notes appear here.'**
  String get archiveEmpty;

  /// No description provided for @trashEmpty.
  ///
  /// In en, this message translates to:
  /// **'No notes in Trash.'**
  String get trashEmpty;

  /// No description provided for @colorDefault.
  ///
  /// In en, this message translates to:
  /// **'Default'**
  String get colorDefault;

  /// No description provided for @colorRed.
  ///
  /// In en, this message translates to:
  /// **'Red'**
  String get colorRed;

  /// No description provided for @colorOrange.
  ///
  /// In en, this message translates to:
  /// **'Orange'**
  String get colorOrange;

  /// No description provided for @colorYellow.
  ///
  /// In en, this message translates to:
  /// **'Yellow'**
  String get colorYellow;

  /// No description provided for @colorGreen.
  ///
  /// In en, this message translates to:
  /// **'Green'**
  String get colorGreen;

  /// No description provided for @colorTeal.
  ///
  /// In en, this message translates to:
  /// **'Teal'**
  String get colorTeal;

  /// No description provided for @colorBlue.
  ///
  /// In en, this message translates to:
  /// **'Blue'**
  String get colorBlue;

  /// No description provided for @colorNavy.
  ///
  /// In en, this message translates to:
  /// **'Dark blue'**
  String get colorNavy;

  /// No description provided for @colorPurple.
  ///
  /// In en, this message translates to:
  /// **'Purple'**
  String get colorPurple;

  /// No description provided for @colorPink.
  ///
  /// In en, this message translates to:
  /// **'Pink'**
  String get colorPink;

  /// No description provided for @colorBrown.
  ///
  /// In en, this message translates to:
  /// **'Brown'**
  String get colorBrown;

  /// No description provided for @colorGray.
  ///
  /// In en, this message translates to:
  /// **'Gray'**
  String get colorGray;

  /// No description provided for @widgetTakeANote.
  ///
  /// In en, this message translates to:
  /// **'Take a note…'**
  String get widgetTakeANote;

  /// No description provided for @widgetNote.
  ///
  /// In en, this message translates to:
  /// **'Note'**
  String get widgetNote;

  /// No description provided for @widgetTapToOpen.
  ///
  /// In en, this message translates to:
  /// **'Tap to open in ZT Notes'**
  String get widgetTapToOpen;

  /// No description provided for @remindAtPlace.
  ///
  /// In en, this message translates to:
  /// **'Remind me at a place'**
  String get remindAtPlace;

  /// No description provided for @removePlaceReminder.
  ///
  /// In en, this message translates to:
  /// **'Remove place reminder'**
  String get removePlaceReminder;

  /// No description provided for @imageTextTitle.
  ///
  /// In en, this message translates to:
  /// **'Text from image'**
  String get imageTextTitle;

  /// No description provided for @imageTextPrivacy.
  ///
  /// In en, this message translates to:
  /// **'The text is read on this phone. The image is never uploaded.'**
  String get imageTextPrivacy;

  /// No description provided for @ocrBoth.
  ///
  /// In en, this message translates to:
  /// **'Both'**
  String get ocrBoth;

  /// No description provided for @ocrEnglish.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get ocrEnglish;

  /// No description provided for @ocrHebrew.
  ///
  /// In en, this message translates to:
  /// **'Hebrew'**
  String get ocrHebrew;

  /// No description provided for @readingImageText.
  ///
  /// In en, this message translates to:
  /// **'Reading the text…'**
  String get readingImageText;

  /// No description provided for @cantReadImageText.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t read the text in this image.'**
  String get cantReadImageText;

  /// No description provided for @noImageText.
  ///
  /// In en, this message translates to:
  /// **'No text found in this image. Try another language above, or a sharper photo.'**
  String get noImageText;

  /// No description provided for @copyText.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get copyText;

  /// No description provided for @textCopied.
  ///
  /// In en, this message translates to:
  /// **'Text copied'**
  String get textCopied;

  /// No description provided for @textFromPhoto.
  ///
  /// In en, this message translates to:
  /// **'Text from a photo'**
  String get textFromPhoto;

  /// No description provided for @grabImageText.
  ///
  /// In en, this message translates to:
  /// **'Grab image text'**
  String get grabImageText;

  /// No description provided for @choosePhoto.
  ///
  /// In en, this message translates to:
  /// **'Choose a photo'**
  String get choosePhoto;

  /// No description provided for @addDrawing.
  ///
  /// In en, this message translates to:
  /// **'Drawing'**
  String get addDrawing;

  /// No description provided for @newDrawing.
  ///
  /// In en, this message translates to:
  /// **'New drawing'**
  String get newDrawing;

  /// No description provided for @editDrawing.
  ///
  /// In en, this message translates to:
  /// **'Edit drawing'**
  String get editDrawing;

  /// No description provided for @saveDrawing.
  ///
  /// In en, this message translates to:
  /// **'Save drawing'**
  String get saveDrawing;

  /// No description provided for @drawSomethingFirst.
  ///
  /// In en, this message translates to:
  /// **'Draw something first.'**
  String get drawSomethingFirst;

  /// No description provided for @discardDrawingQ.
  ///
  /// In en, this message translates to:
  /// **'Discard your changes to this drawing?'**
  String get discardDrawingQ;

  /// No description provided for @keepDrawing.
  ///
  /// In en, this message translates to:
  /// **'Keep drawing'**
  String get keepDrawing;

  /// No description provided for @discard.
  ///
  /// In en, this message translates to:
  /// **'Discard'**
  String get discard;

  /// No description provided for @colorBlack.
  ///
  /// In en, this message translates to:
  /// **'Black'**
  String get colorBlack;

  /// No description provided for @pen.
  ///
  /// In en, this message translates to:
  /// **'Pen'**
  String get pen;

  /// No description provided for @highlighter.
  ///
  /// In en, this message translates to:
  /// **'Highlighter'**
  String get highlighter;

  /// No description provided for @eraser.
  ///
  /// In en, this message translates to:
  /// **'Eraser'**
  String get eraser;

  /// No description provided for @redo.
  ///
  /// In en, this message translates to:
  /// **'Redo'**
  String get redo;

  /// No description provided for @clearDrawing.
  ///
  /// In en, this message translates to:
  /// **'Clear page'**
  String get clearDrawing;

  /// No description provided for @drawingCanvas.
  ///
  /// In en, this message translates to:
  /// **'Drawing area. Draw with a finger or a stylus.'**
  String get drawingCanvas;

  /// No description provided for @cantOpenDrawing.
  ///
  /// In en, this message translates to:
  /// **'This drawing can\'t be opened for editing here yet. Sync, then try again.'**
  String get cantOpenDrawing;

  /// No description provided for @thickness.
  ///
  /// In en, this message translates to:
  /// **'Thickness {size}'**
  String thickness(int size);
}

class _AppL10nDelegate extends LocalizationsDelegate<AppL10n> {
  const _AppL10nDelegate();

  @override
  Future<AppL10n> load(Locale locale) {
    return SynchronousFuture<AppL10n>(lookupAppL10n(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'he'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppL10nDelegate old) => false;
}

AppL10n lookupAppL10n(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppL10nEn();
    case 'he':
      return AppL10nHe();
  }

  throw FlutterError(
    'AppL10n.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
