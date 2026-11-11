// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_l10n.dart';

// ignore_for_file: type=lint

/// The translations for Hebrew (`he`).
class AppL10nHe extends AppL10n {
  AppL10nHe([String locale = 'he']) : super(locale);

  @override
  String get cancel => 'ביטול';

  @override
  String get import => 'ייבוא';

  @override
  String get done => 'סיום';

  @override
  String get remove => 'הסרה';

  @override
  String get delete => 'מחיקה';

  @override
  String get save => 'שמירה';

  @override
  String notesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count פתקים',
      two: 'שני פתקים',
      one: 'פתק אחד',
    );
    return '$_temp0';
  }

  @override
  String importedNotes(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'יובאו $count פתקים.',
      two: 'יובאו שני פתקים.',
      one: 'יובא פתק אחד.',
    );
    return '$_temp0';
  }

  @override
  String get noteNotFound => 'הפתק לא נמצא. ייתכן שנמחק.';

  @override
  String get cantOpenNotes => 'לא ניתן לפתוח את הפתקים במכשיר הזה.';

  @override
  String get tryAgain => 'לנסות שוב';

  @override
  String get legacyBanner =>
      'Notes משתמשת עכשיו בחשבון Zero-Trust שלך. להעביר את הפתקים מהכספת הישנה?';

  @override
  String get later => 'אחר כך';

  @override
  String get legacyWrongPass => 'הסיסמה הזו לא פותחת את הפתקים הישנים.';

  @override
  String get legacyIntegrity =>
      'הגיבוי הישן בענן לא עבר בדיקת שלמות, ולכן לא יובא.';

  @override
  String get importFailedConnection =>
      'הייבוא נכשל. כדאי לבדוק את החיבור ולנסות שוב.';

  @override
  String get legacyTitle => 'ייבוא פתקים ישנים';

  @override
  String get legacyExplain =>
      'יש להזין את סיסמת הכספת שהשתמשת בה לפני העדכון. צריך אותה רק פעם אחת.';

  @override
  String get legacyPassLabel => 'סיסמת הכספת הישנה';

  @override
  String get keepChooseFile => 'בחירת קובץ Google Takeout';

  @override
  String get importFromKeep => 'ייבוא מ-Google Keep';

  @override
  String get keepExplain =>
      '1. נכנסים ל-takeout.google.com ובוחרים רק את \"Keep\".\n2. מורידים את הייצוא לטלפון הזה.\n3. בוחרים כאן את קובץ ה-ZIP (או את קובצי ה-JSON מתיקיית Keep שבו).\n\nהקובץ נקרא בטלפון הזה, והפתקים מוצפנים לפני הסנכרון. תוויות הופכות לתגיות; צבעים, הצמדות, ארכיון ורשימות משימות עוברים גם הם. פתקים שכבר יובאו מדולגים. תמונות והקלטות עדיין לא מיובאות.';

  @override
  String get chooseFile => 'בחירת קובץ';

  @override
  String get cantOpenFile => 'לא ניתן לפתוח את הקובץ.';

  @override
  String get noFileChosen => 'לא נבחר קובץ ZIP או JSON.';

  @override
  String get keepNoneFound => 'לא נמצאו בקובץ פתקים של Google Keep.';

  @override
  String get importingNotes => 'מייבא את הפתקים…';

  @override
  String keepStopped(String failure) {
    return 'הייבוא נעצר באמצע ($failure). אפשר להריץ אותו שוב כדי לסיים; פתקים שכבר יובאו ידולגו.';
  }

  @override
  String keepImportedTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'יובאו $count פתקים',
      two: 'יובאו שני פתקים',
      one: 'יובא פתק אחד',
    );
    return '$_temp0';
  }

  @override
  String keepSkippedDup(int count) {
    return '$count כבר נמצאים ב-Notes ודולגו.';
  }

  @override
  String keepSkippedTrash(int count) {
    return '$count מהאשפה של Keep, דולגו.';
  }

  @override
  String keepAttachmentsSkipped(int count) {
    return '$count תמונות או הקלטות לא יובאו.';
  }

  @override
  String get keepEverything => 'הכול הועבר.';

  @override
  String imageNofM(int n, int total) {
    return 'תמונה $n מתוך $total';
  }

  @override
  String get opensImage => 'פותח את התמונה';

  @override
  String get removeImageQ => 'להסיר את התמונה?';

  @override
  String get removeImageBody => 'היא תוסר מהפתק בכל המכשירים.';

  @override
  String nOfM(int n, int total) {
    return '$n מתוך $total';
  }

  @override
  String get image => 'תמונה';

  @override
  String get sendImage => 'שליחת התמונה';

  @override
  String get removeImage => 'הסרת התמונה';

  @override
  String get voiceNote => 'פתק קולי';

  @override
  String get voiceExplain =>
      'התמלול נעשה בטלפון הזה. הקול שלך לא נשלח לשום מקום.';

  @override
  String get voiceOnlineOnly =>
      'הטלפון הזה יכול לתמלל דיבור רק באינטרנט, כלומר לשלוח את הקול שלך לשרת, ולכן Notes לא משתמשת בזה. פתקים קוליים דורשים Android 12 ומעלה עם זיהוי דיבור במכשיר.';

  @override
  String get voiceUnavailable =>
      'זיהוי דיבור לא זמין בטלפון הזה, או שאין ל-Notes הרשאה למיקרופון.';

  @override
  String get language => 'שפה';

  @override
  String get listening => 'מקשיב…';

  @override
  String get tapMicAndSpeak => 'יש להקיש על המיקרופון ולדבר.';

  @override
  String get stopListening => 'הפסקת ההקשבה';

  @override
  String get startListening => 'התחלת ההקשבה';

  @override
  String get addToNote => 'הוספה לפתק';

  @override
  String voiceLangMissing(String language) {
    return 'זיהוי דיבור ב$language עדיין לא מותקן בטלפון, ו-Notes מתמללת רק במכשיר. אפשר להוריד את $language לזיהוי דיבור אופליין בהגדרות הטלפון (לחפש \"זיהוי דיבור אופליין\") ולנסות שוב.';
  }

  @override
  String get voiceNeedsMic =>
      'Notes צריכה גישה למיקרופון בשביל פתקים קוליים. אפשר לאשר אותה בהגדרות הטלפון.';

  @override
  String get voiceNoMatch =>
      'לא הצלחתי לשמוע. יש להקיש על המיקרופון ולנסות שוב.';

  @override
  String get voiceBusy => 'זיהוי הדיבור עסוק. כדאי לנסות שוב בעוד רגע.';

  @override
  String voiceStopped(String code) {
    return 'הפתק הקולי נעצר ($code). כדאי לנסות שוב.';
  }

  @override
  String get listItem => 'פריט ברשימה';

  @override
  String tickedItems(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count פריטים מסומנים',
      two: 'שני פריטים מסומנים',
      one: 'פריט אחד מסומן',
    );
    return '$_temp0';
  }

  @override
  String get removeItem => 'הסרת הפריט';

  @override
  String get undo => 'ביטול פעולה';

  @override
  String get noteArchived => 'הפתק הועבר לארכיון';

  @override
  String get noteUnarchived => 'הפתק הוצא מהארכיון';

  @override
  String get noteTrashed => 'הפתק הועבר לאשפה';

  @override
  String get noteRestored => 'הפתק שוחזר';

  @override
  String get deleteForeverQ => 'למחוק לצמיתות?';

  @override
  String get deleteForeverBody =>
      'הפתק יימחק בכל המכשירים. אי אפשר לבטל את זה.';

  @override
  String get restore => 'שחזור';

  @override
  String get deleteForever => 'מחיקה לצמיתות';

  @override
  String get unpin => 'ביטול הצמדה';

  @override
  String get pin => 'הצמדה';

  @override
  String get unarchive => 'הוצאה מהארכיון';

  @override
  String get archive => 'העברה לארכיון';

  @override
  String get colour => 'צבע';

  @override
  String get remindMe => 'תזכורת';

  @override
  String get send => 'שליחה';

  @override
  String get moveToTrash => 'העברה לאשפה';

  @override
  String get reasonSendLocked => 'שליחת הפתק הנעול';

  @override
  String get laterToday => 'מאוחר יותר היום';

  @override
  String get tomorrowMorning => 'מחר בבוקר';

  @override
  String get nextWeek => 'בשבוע הבא';

  @override
  String get pickDateTime => 'בחירת תאריך ושעה';

  @override
  String get removeReminder => 'הסרת התזכורת';

  @override
  String get pickFutureTime => 'יש לבחור זמן עתידי.';

  @override
  String get reminderNotifsOff =>
      'התזכורת נשמרה, אבל ההתראות של Notes כבויות. אפשר להפעיל אותן בהגדרות המערכת.';

  @override
  String todayAt(String time) {
    return 'היום, $time';
  }

  @override
  String tomorrowAt(String time) {
    return 'מחר, $time';
  }

  @override
  String yesterdayAt(String time) {
    return 'אתמול, $time';
  }

  @override
  String get semPinned => 'מוצמד.';

  @override
  String get semLocked => 'נעול.';

  @override
  String semImages(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count תמונות.',
      two: 'שתי תמונות.',
      one: 'תמונה אחת.',
    );
    return '$_temp0';
  }

  @override
  String get semUntitled => 'פתק ללא כותרת.';

  @override
  String semChecklist(int done, int total) {
    return 'רשימת משימות, $done מתוך $total בוצעו.';
  }

  @override
  String semReminder(String when) {
    return 'תזכורת: $when.';
  }

  @override
  String semTags(String tags) {
    return 'תגיות: $tags.';
  }

  @override
  String get semOpensNote => 'פותח את הפתק. לחיצה ארוכה לפעולות נוספות.';

  @override
  String get locked => 'נעול';

  @override
  String get emptyNote => 'פתק ריק';

  @override
  String nMore(int count) {
    return '+ עוד $count';
  }

  @override
  String plusTicked(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '+ $count פריטים מסומנים',
      two: '+ שני פריטים מסומנים',
      one: '+ פריט אחד מסומן',
    );
    return '$_temp0';
  }

  @override
  String get wrongPassword => 'הסיסמה שגויה.';

  @override
  String get openLockedNote => 'פתיחת פתק נעול';

  @override
  String get noScreenLock =>
      'בטלפון הזה אין נעילת מסך, לכן יש להזין את סיסמת החשבון. כדי להשתמש בטביעת אצבע או בזיהוי פנים, יש להגדיר נעילת מסך.';

  @override
  String get accountPassword => 'סיסמת החשבון';

  @override
  String get open => 'פתיחה';

  @override
  String semNotebook(String name) {
    return 'מחברת: $name';
  }

  @override
  String get none => 'ללא';

  @override
  String get opensNotebookPicker => 'פותח את בחירת המחברת';

  @override
  String get noNotebook => 'ללא מחברת';

  @override
  String get renameNotebook => 'שינוי שם המחברת';

  @override
  String get notebook => 'מחברת';

  @override
  String get deleteNotebook => 'מחיקת המחברת';

  @override
  String failedNotebooks(String error) {
    return 'טעינת המחברות נכשלה: $error';
  }

  @override
  String get newNotebookName => 'שם המחברת החדשה';

  @override
  String get createNotebook => 'יצירת מחברת';

  @override
  String get addTag => 'הוספת תגית';

  @override
  String get tags => 'תגיות';

  @override
  String get deleteTag => 'מחיקת התגית';

  @override
  String failedTags(String error) {
    return 'טעינת התגיות נכשלה: $error';
  }

  @override
  String get newTagName => 'שם התגית החדשה';

  @override
  String get createTag => 'יצירת תגית';

  @override
  String get exportAll => 'ייצוא כל הפתקים';

  @override
  String get exportThis => 'ייצוא הפתק הזה';

  @override
  String get exportLockedOne => 'הייצוא כולל פתק נעול';

  @override
  String exportLockedMany(int count) {
    return 'הייצוא כולל $count פתקים נעולים';
  }

  @override
  String get exportNeedsAuth =>
      'לא יוצא. פתקים נעולים מיוצאים רק אחרי טביעת אצבע, זיהוי פנים או נעילת מסך.';

  @override
  String exportFailed(String error) {
    return 'הייצוא נכשל: $error';
  }

  @override
  String exportAs(String format) {
    return 'ייצוא כ-$format';
  }

  @override
  String get widgetDetails => 'הצגת פרטים במסך הבית';

  @override
  String get widgetDetailsBody =>
      'כבוי: הווידג\'ט של הפתק מציג מנעול. מופעל: הכותרת ותחילת כל פתק מוצמד נשמרות בטלפון הזה ללא הצפנה, בשביל מסך הבית. הטקסט של פתקים נעולים אף פעם לא מוצג';

  @override
  String get exportFormats => 'Markdown,‏ JSON או PDF';

  @override
  String get keepSubtitle => 'מקובץ Google Takeout, בטלפון הזה';

  @override
  String get importOldVault => 'ייבוא פתקים מהכספת הישנה';

  @override
  String get importOldVaultSub => 'נדרשת סיסמת הכספת שהשתמשת בה לפני העדכון';

  @override
  String get syncing => 'מסנכרן';

  @override
  String get notSynced => 'לא מסונכרן';

  @override
  String get notSyncedYet => 'עדיין לא סונכרן';

  @override
  String get synced => 'מסונכרן';

  @override
  String syncStatus(String status) {
    return 'מצב סנכרון: $status';
  }

  @override
  String get syncNow => 'סנכרון עכשיו';

  @override
  String get showTextQ => 'להציג את טקסט הפתקים במסך הבית?';

  @override
  String get showTextBody =>
      'פעולה זו מפעילה את \"הצגת פרטים במסך הבית\" בכל הווידג\'טים של פתקים, כולל אלה שכבר הוספת. הכותרות ותחילת הטקסט יישמרו בטלפון הזה ללא הצפנה כדי שהווידג\'טים יוכלו להציג אותם. אפשר לכבות את זה בהגדרות.';

  @override
  String get keepHidden => 'להשאיר מוסתר';

  @override
  String get showOnAll => 'הצגה בכל הווידג\'טים';

  @override
  String get chooseNoteToPin => 'בחירת פתק להצמדה';

  @override
  String get noNotesCreateFirst => 'אין עדיין פתקים. כדאי ליצור פתק קודם.';

  @override
  String get lockedNote => 'פתק נעול';

  @override
  String failedNotes(String error) {
    return 'טעינת הפתקים נכשלה: $error';
  }

  @override
  String get untitled => '(ללא כותרת)';

  @override
  String get noteDeleted => 'הפתק נמחק';

  @override
  String get nothingToSend => 'הפתק ריק: אין מה לשלוח.';

  @override
  String imagesNotHere(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count תמונות עדיין לא נמצאות במכשיר, ולכן לא נשלחו.',
      one: 'תמונה אחת עדיין לא נמצאת במכשיר, ולכן לא נשלחה.',
    );
    return '$_temp0';
  }

  @override
  String get cantShare => 'לא ניתן לפתוח את חלון השיתוף.';

  @override
  String get reminderChannel => 'תזכורות לפתקים';

  @override
  String get reminderChannelDesc => 'תזכורות שהגדרת על פתקים';

  @override
  String get noteReminder => 'תזכורת לפתק';

  @override
  String get reminder => 'תזכורת';

  @override
  String get saveFailed =>
      'לא ניתן לשמור את הפתק. השינויים עדיין כאן; כדאי לנסות שוב.';

  @override
  String get cantOpenCamera => 'לא ניתן לפתוח את המצלמה.';

  @override
  String get cantOpenPhotos => 'לא ניתן לפתוח את התמונות.';

  @override
  String imagesTooLarge(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count תמונות גדולות מ-20MB ואי אפשר להוסיף אותן.',
      one: 'התמונה גדולה מ-20MB ואי אפשר להוסיף אותה.',
    );
    return '$_temp0';
  }

  @override
  String imagesFailed(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'לא ניתן להוסיף $count תמונות.',
      one: 'לא ניתן להוסיף תמונה.',
    );
    return '$_temp0';
  }

  @override
  String sharedSkipped(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count פריטים משותפים לא נוספו (אפשר להוסיף רק טקסט ותמונות עד 20MB).',
      one: 'פריט משותף אחד לא נוסף (אפשר להוסיף רק טקסט ותמונות עד 20MB).',
    );
    return '$_temp0';
  }

  @override
  String get reasonOpenLocked => 'פתיחת הפתק הנעול';

  @override
  String get noteLockedMsg =>
      'הפתק ננעל. כדי לפתוח אותו יידרשו טביעת אצבע, זיהוי פנים או נעילת מסך.';

  @override
  String get noteUnlockedMsg => 'הנעילה הוסרה מהפתק.';

  @override
  String get confirmToOpen => 'כדי לפתוח את הפתק יש לאמת את זהותך.';

  @override
  String get unlock => 'ביטול נעילה';

  @override
  String get saving => 'שומר…';

  @override
  String get saved => 'נשמר';

  @override
  String get notSaved => 'לא נשמר';

  @override
  String get inTrash => 'באשפה';

  @override
  String get editNote => 'עריכת פתק';

  @override
  String get newNote => 'פתק חדש';

  @override
  String get trashNoEdit =>
      'אי אפשר לערוך פתקים שבאשפה. כדי לשנות, צריך לשחזר את הפתק.';

  @override
  String get noteTitle => 'כותרת הפתק';

  @override
  String get title => 'כותרת';

  @override
  String get addingImages => 'מוסיף תמונות';

  @override
  String get unpinNote => 'ביטול הצמדת הפתק';

  @override
  String get pinNote => 'הצמדת הפתק';

  @override
  String get changeReminder => 'שינוי התזכורת';

  @override
  String get unarchiveNote => 'הוצאת הפתק מהארכיון';

  @override
  String get archiveNote => 'העברת הפתק לארכיון';

  @override
  String get moreOptions => 'אפשרויות נוספות';

  @override
  String get takePhoto => 'צילום תמונה';

  @override
  String get addImage => 'הוספת תמונה';

  @override
  String get hideCheckboxes => 'הסתרת תיבות הסימון';

  @override
  String get showCheckboxes => 'הצגת תיבות סימון';

  @override
  String get editText => 'עריכת הטקסט';

  @override
  String get previewMarkdown => 'תצוגה מקדימה של Markdown';

  @override
  String get unlockNote => 'ביטול נעילת הפתק';

  @override
  String get lockNote => 'נעילת הפתק';

  @override
  String get exportNote => 'ייצוא הפתק';

  @override
  String get saveAndClose => 'שמירה וסגירה';

  @override
  String get nothingToPreview => 'אין עדיין מה להציג.';

  @override
  String get noteBody => 'תוכן הפתק';

  @override
  String get bodyLabel => 'תוכן (יש תמיכה ב-Markdown)';

  @override
  String wordCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count מילים',
      two: 'שתי מילים',
      one: 'מילה אחת',
    );
    return '$_temp0';
  }

  @override
  String editedAgo(String words, String when) {
    return '$words · נערך $when';
  }

  @override
  String get justNow => 'הרגע';

  @override
  String secondsAgo(int n) {
    return 'לפני $n שנ׳';
  }

  @override
  String minutesAgo(int n) {
    return 'לפני $n דק׳';
  }

  @override
  String hoursAgo(int n) {
    return 'לפני $n שע׳';
  }

  @override
  String daysAgo(int n) {
    return 'לפני $n ימים';
  }

  @override
  String get sortCustom => 'סדר מותאם (גרירה להזזה)';

  @override
  String get sortUpdatedDesc => 'עריכה אחרונה (מהחדש)';

  @override
  String get sortUpdatedAsc => 'עריכה אחרונה (מהישן)';

  @override
  String get sortCreatedDesc => 'תאריך יצירה (מהחדש)';

  @override
  String get sortCreatedAsc => 'תאריך יצירה (מהישן)';

  @override
  String get sortTitle => 'כותרת (א-ת)';

  @override
  String get emptyTrashQ => 'לרוקן את האשפה?';

  @override
  String get emptyTrashBody =>
      'כל הפתקים שבאשפה יימחקו בכל המכשירים. אי אפשר לבטל את זה.';

  @override
  String get emptyTrash => 'ריקון האשפה';

  @override
  String get viewNotes => 'פתקים';

  @override
  String get viewReminders => 'תזכורות';

  @override
  String get viewArchive => 'ארכיון';

  @override
  String get viewTrash => 'אשפה';

  @override
  String get syncFailed =>
      'הסנכרון נכשל. הפתקים שמורים במכשיר הזה ויסונכרנו מאוחר יותר.';

  @override
  String get searchNotes => 'חיפוש פתקים';

  @override
  String searchIn(String place) {
    return 'חיפוש ב$place…';
  }

  @override
  String get closeSearch => 'סגירת החיפוש';

  @override
  String get showAsList => 'הצגה כרשימה';

  @override
  String get showAsGrid => 'הצגה כרשת';

  @override
  String get trashAfter30 => 'פתקים באשפה נמחקים אחרי 30 יום.';

  @override
  String get newVoiceNote => 'פתק קולי חדש';

  @override
  String get newChecklist => 'רשימת משימות חדשה';

  @override
  String get createNote => 'יצירת פתק חדש';

  @override
  String get tag => 'תגית';

  @override
  String get notebooks => 'מחברות';

  @override
  String get settings => 'הגדרות';

  @override
  String get all => 'הכול';

  @override
  String get unfiled => 'ללא מחברת';

  @override
  String get checklists => 'רשימות משימות';

  @override
  String get clearFilters => 'ניקוי המסננים';

  @override
  String get any => 'הכול';

  @override
  String get pinned => 'מוצמדים';

  @override
  String get others => 'אחרים';

  @override
  String get noMatch => 'אין פתקים שמתאימים לחיפוש או למסנן.';

  @override
  String get noNotesHere => 'אין כאן עדיין פתקים.';

  @override
  String get noNotesYet => 'אין עדיין פתקים. אפשר להקיש על + כדי ליצור פתק.';

  @override
  String get remindersEmpty => 'פתקים עם תזכורות יופיעו כאן.';

  @override
  String get archiveEmpty => 'הפתקים שבארכיון יופיעו כאן.';

  @override
  String get trashEmpty => 'אין פתקים באשפה.';

  @override
  String get colorDefault => 'ברירת מחדל';

  @override
  String get colorRed => 'אדום';

  @override
  String get colorOrange => 'כתום';

  @override
  String get colorYellow => 'צהוב';

  @override
  String get colorGreen => 'ירוק';

  @override
  String get colorTeal => 'טורקיז';

  @override
  String get colorBlue => 'כחול';

  @override
  String get colorNavy => 'כחול כהה';

  @override
  String get colorPurple => 'סגול';

  @override
  String get colorPink => 'ורוד';

  @override
  String get colorBrown => 'חום';

  @override
  String get colorGray => 'אפור';

  @override
  String get widgetTakeANote => 'כתיבת פתק…';

  @override
  String get widgetNote => 'פתק';

  @override
  String get widgetTapToOpen => 'יש להקיש כדי לפתוח ב-ZT Notes';

  @override
  String get imageTextTitle => 'טקסט מתמונה';

  @override
  String get imageTextPrivacy =>
      'הטקסט נקרא בטלפון עצמו. התמונה לא נשלחת לשום מקום.';

  @override
  String get ocrBoth => 'שתיהן';

  @override
  String get ocrEnglish => 'אנגלית';

  @override
  String get ocrHebrew => 'עברית';

  @override
  String get readingImageText => 'קורא את הטקסט…';

  @override
  String get cantReadImageText => 'לא הצלחנו לקרוא את הטקסט בתמונה.';

  @override
  String get noImageText =>
      'לא נמצא טקסט בתמונה. נסו שפה אחרת למעלה, או תמונה חדה יותר.';

  @override
  String get copyText => 'העתקה';

  @override
  String get textCopied => 'הטקסט הועתק';

  @override
  String get textFromPhoto => 'טקסט מתמונה';

  @override
  String get grabImageText => 'העתקת הטקסט מהתמונה';

  @override
  String get choosePhoto => 'בחירת תמונה';

  @override
  String get addDrawing => 'ציור';

  @override
  String get newDrawing => 'ציור חדש';

  @override
  String get editDrawing => 'עריכת הציור';

  @override
  String get saveDrawing => 'שמירת הציור';

  @override
  String get drawSomethingFirst => 'צריך לצייר משהו קודם.';

  @override
  String get discardDrawingQ => 'לבטל את השינויים בציור?';

  @override
  String get keepDrawing => 'המשך לצייר';

  @override
  String get discard => 'ביטול השינויים';

  @override
  String get colorBlack => 'שחור';

  @override
  String get pen => 'עט';

  @override
  String get highlighter => 'מרקר';

  @override
  String get eraser => 'מחק';

  @override
  String get redo => 'ביצוע מחדש';

  @override
  String get clearDrawing => 'ניקוי הדף';

  @override
  String get drawingCanvas => 'אזור הציור. אפשר לצייר באצבע או בעט.';

  @override
  String get cantOpenDrawing =>
      'אי אפשר לערוך את הציור הזה כאן עדיין. סנכרנו ונסו שוב.';

  @override
  String thickness(int size) {
    return 'עובי $size';
  }
}
