# Zero-Trust Notes

End-to-end encrypted notes: ideas, checklists, drawings, voice notes and
files that only you can read. On the phone it is called **ZT Notes**; in
stores and on release pages, **Zero-Trust Notes**. Same account, settings
and look as the other Zero-Trust apps, built on
[Zero-Trust-Core](https://github.com/EdoSag/Zero-Trust-Core). Part of the
[Zero-Trust suite](https://zerotrust.bz).

## What it does

- **Notes and checklists:** ticked items drop to the bottom, and a note
  turns into a list and back. Markdown with a preview.
- **Organise:** grid or list view, pin to top, colours, drag to reorder,
  notebooks and tags, search and filters across everything, archive, and a
  trash that keeps deleted notes for 30 days.
- **Images, drawings and handwriting**, encrypted like the rest. "Copy
  text" reads the text in a photo, and "Handwriting to text" reads what you
  wrote, both on the phone with Tesseract (English and Hebrew).
- **Files:** attach any file up to 20 MB as an encrypted attachment. PDFs
  open in the app.
- **Voice notes**, transcribed on the phone. A phone that can only
  transcribe online is not used: your voice is never sent anywhere.
- **Ask ZT Assist** (when [ZT Assist](https://github.com/EdoSag/Zero-Trust-Assist)
  is on the same phone): summarize a note, improve its writing, fix spelling
  and grammar, translate between Hebrew and English, or get a title
  suggested. It works on the whole note or on the text you selected, and
  you choose whether the answer replaces the text, is added below it, or is
  only copied. The AI model runs on the phone, inside ZT Assist.
- **Reminders:** at a time, or at a place ("when I get to the
  supermarket"). The phone watches for the place itself (Core's
  `zt_places`, no Google Play services), so your location never leaves it.
- **Links between notes:** link to another note and see which notes link
  here.
- **Templates and today's note:** start from a built-in template (daily
  journal, meeting notes, to-do list) or your own, and open today's note in
  one tap.
- **Version history:** earlier versions of a note, encrypted like the note
  (kept each time you come back to edit, at most every 10 minutes, the
  last 30), with Restore.
- **Locked notes:** a note can ask for your fingerprint, face or screen
  lock again before it opens.
- **Shared notebooks and notes** with other Zero-Trust users, end-to-end
  encrypted (Core's shared spaces). Invite by link or QR code and compare
  a short code before letting someone in. Everyone can add and edit;
  owners invite and remove people. Locked notes are never shared.
- **Share into Notes** from any app (text, pictures and files), and
  "Insert from ZT apps" in ZT Keyboard picks a note's text to type.
- **Home screen widgets** (Android): quick add, a single note, a notes list
  (all or pinned) and a checklist you can tick from the home screen. Plus a
  Quick Settings tile for a new note and launcher shortcuts (new note,
  today's note, new checklist, voice note).
- **Import:** Google Keep (Google Takeout), Evernote (.enex), Standard
  Notes (decrypted backup), Apple Notes and Markdown folders from Obsidian,
  Joplin and others. Files are read on the phone; notes already imported
  are skipped.
- **Export:** one note or all of them as Markdown, JSON or PDF, or a
  Markdown folder (.zip) with pictures and files.

## Privacy

Like every Zero-Trust app, it is zero-knowledge: your data is encrypted on
your device, with keys made from your password, before anything is sent.
The server stores only ciphertext and your password itself is never
sent, so neither we nor anyone who breaks into the server can read your
data. The recovery key shown at sign-up is the only way back in if you
forget the password. How the keys work:
[Zero-Trust-Core](https://github.com/EdoSag/Zero-Trust-Core#key-hierarchy) and
[zerotrust.bz/security](https://zerotrust.bz/security/).

- Notes, notebooks, tags, templates and versions are items in the shared
  `vault_items` table, encrypted on the device with the Notes app key.
  Pictures, drawings and files are encrypted attachments.
- Widgets show a lock until "Show details on the home screen" is turned on;
  then note titles and the start of their text are kept unencrypted on this
  phone for the launcher. Locked notes never show their text.
- A reminder hands only the note's title to Android.
- Text recognition, handwriting and voice transcription run on the phone.
- "Ask ZT Assist" hands the note's text to the ZT Assist app on the same
  phone, only when you ask, and only to an app signed with the same key as
  this one. ZT Assist does not save it and nothing is sent to a server.
- Exports are plain files. Locked notes are exported only after your
  fingerprint, face or screen lock.
- Notes from before the core (the old vault) are brought over on first
  unlock; see `lib/src/features/legacy_import/`.

## One account, one core

One Zero-Trust account opens every app in the suite. Sign-in, unlock
(fingerprint or face, auto-lock), the recovery key, settings, the look,
sync and languages come from
[Zero-Trust-Core](https://github.com/EdoSag/Zero-Trust-Core), so they work
the same in every app. Accounts made before the core still sign in and
see their data.

## Install

Android: get the latest signed APK from this repository's
[Releases](https://github.com/EdoSag/Zero-Trust-Notes/releases/latest),
or from [zerotrust.bz/install](https://zerotrust.bz/install/#notes),
which also shows each file's SHA-256, the signing fingerprint and an
Obtainium link. GitHub Releases are the main way the apps are published.

Builds from GitHub check for a newer release themselves (Settings > About,
one anonymous request a day, can be turned off). Every Zero-Trust app is signed
with the same key, and Android only installs an update signed with it.

## Languages

English and Hebrew, with right-to-left layout. Choose under
Settings > Appearance > Language.

## How it is built

```
lib/src/
  app/        sign-in, unlock, routing
  core/       shared helpers
  features/   one folder per feature: notes, notebooks, tags, reminders,
              places, images, drawing, handwriting, image_text, voice,
              files, links, templates, history, sharing, widgets, assist,
              keep_import, other_import, export, legacy_import, sync
  shared/     shared widgets
android/      widgets, Quick Settings tile, share target, PDF pages
```

- Flutter with Riverpod. Account, keys, lock, sync, settings and theme come
  from Zero-Trust-Core, pinned in `pubspec.yaml`.
- Optional note keys are written only when set, and keys a newer version
  adds are kept as they are, so notes still open in earlier builds.
- The app also builds for the browser (`.github/workflows/web.yml`, Core's
  web kit). Voice notes, place reminders and widgets are hidden there.

## Build from source

Flutter 3.47.9, the version CI pins (3.50 deprecates `material.dart` and
fails analyze).

First create a file named `.env` in the project folder. It is not committed
(CI writes its own) and it is bundled into the APK, so it holds public client
values only, never a service-role key:

```
SUPABASE_URL=https://<project>.supabase.co
SUPABASE_ANON_KEY=<publishable key>
```

Then:

```bash
flutter pub get
dart run zt_release_checks --app notes   # shared release checks
flutter analyze && flutter test test/
flutter run
```

Never add `cryptography_flutter`: it breaks the core's key derivation and
sign-in fails.

The tests need a `.env` file (it may be empty). Launcher icons are drawn
from the suite's brand mark: `flutter test tool/launcher_icon_test.dart`.

## Branches and releases

Work happens on `Dev`: pull requests target `Dev`, never `main`, and get a
test build. A release is one `Dev` → `main` pull request. Every push to
`main` runs the suite's release checks, builds a signed APK and a Google Play bundle
and publishes them as a GitHub Release named "Zero-Trust Notes"
(`.github/workflows/android-apk.yml`). The workflow needs the repository
secrets `ANDROID_KEYSTORE_BASE64` and `ANDROID_KEYSTORE_PASSWORD`, the
keystore shared by all Zero-Trust apps.

Pull requests also build the web app (`.github/workflows/web.yml`); a push
to `main` publishes it to Cloudflare Pages when the repository has the
`CLOUDFLARE_API_TOKEN` and `CLOUDFLARE_ACCOUNT_ID` secrets.

## Support and security

- Help centre: [zerotrust.bz/help](https://zerotrust.bz/help/). Questions and
  account deletion: support@zerotrust.bz.
- Security problems: please report them privately to cyber@zerotrust.bz. What
  the encryption does and doesn't protect against is on
  [zerotrust.bz/security](https://zerotrust.bz/security/).
- [Privacy policy](https://zerotrust.bz/privacy/) and
  [terms](https://zerotrust.bz/terms/).

## License

Copyright (C) 2026 Edo Sagron (https://zerotrust.bz)

Zero-Trust is open source under the [GNU Affero General Public License v3.0](LICENSE)
(AGPL-3.0-only), the same licence Signal uses.

- You may use, study, change and share the code, including in your own projects.
- If you share a changed version, or run it for other people over a network, you must
  publish your full source code under the same licence.
- This program comes with no warranty; see the licence for details.

Third-party libraries keep their own licences; the app lists them under
Settings > Open-source licences.

### Name and logo

The AGPL covers the code, not the brand. "Zero-Trust", "ZT", the app names and icons are
reserved. If you publish a fork, give it a different name and icon so nobody mistakes it
for an official Zero-Trust app.

### Servers

The official apps use the Zero-Trust servers. A fork must use its own backend (for
example its own Supabase project) and must not connect to the official servers.

### Contributing

Pull requests are welcome. By sending one you agree that your contribution is licensed
under the AGPL-3.0 and that the copyright holder may also license it under other terms,
including commercially. This keeps the project able to offer paid plans and other licences.
