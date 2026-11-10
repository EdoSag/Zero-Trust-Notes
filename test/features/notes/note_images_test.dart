import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:zero_trust_core/zero_trust_core.dart';
import 'package:zerotrust_notes/src/features/notes/domain/note.dart';

import '../../support/fake_sync_backend.dart';
import '../../support/notes_device.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final photo = Uint8List.fromList(List.generate(3000, (i) => i % 251));

  group('Note JSON', () {
    LocalItem item(Map<String, Object?> json) =>
        LocalItem(itemId: 'n1', json: json, updatedAt: DateTime.utc(2026), dirty: false);

    test('a note without images writes no images key, as older builds did', () {
      final json = Note.itemJson(title: 't', body: 'b', createdAt: DateTime.utc(2026));
      expect(json.containsKey('images'), isFalse);
    });

    test('image refs round-trip and an unreadable entry is skipped', () {
      final ref = ZtAttachmentRef(
        id: '0123456789abcdef0123456789abcdef',
        key: Uint8List(32),
        size: 10,
        mimeType: 'image/jpeg',
        name: 'a.jpg',
      );
      final json = Note.itemJson(
        title: 't',
        body: 'b',
        createdAt: DateTime.utc(2026),
        images: [ref],
      );
      final note = Note.fromItem(
        item({
          ...json,
          'images': [
            ...(json['images']! as List),
            'nonsense',
            {'id': 'x'},
          ],
        }),
      );
      expect(note.images, [ref]);
      expect(note.images.single.name, 'a.jpg');
      expect(note.extra.containsKey('images'), isFalse);
    });
  });

  group('Images in notes', () {
    late FakeSyncBackend server;
    late InMemoryAttachmentBackend files;
    late Device phone;
    late Device laptop;

    setUp(() async {
      server = FakeSyncBackend();
      files = InMemoryAttachmentBackend();
      phone = Device('phone', server, files: files);
      laptop = Device('laptop', server, files: files);
      await phone.unlock();
      await laptop.unlock();
    });

    tearDown(() {
      phone.container.dispose();
      laptop.container.dispose();
    });

    Future<void> uploads() async {
      // Uploads run in the background after put.
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }

    test('an image is stored encrypted and opens on another device', () async {
      final image = await phone.repo.addImage(photo, mimeType: 'image/jpeg', name: 'cat.jpg');
      await phone.repo.createNote(title: 'Cat', body: '', images: [image]);
      await uploads();
      await phone.sync();
      await laptop.sync();

      final stored = files.files.values.single;
      expect(stored, isNot(containsAllInOrder(photo.sublist(0, 64))));

      final note = (await laptop.repo.fetchAll()).single;
      expect(note.images, [image]);
      expect(await laptop.repo.readImage(note.images.single), photo);
    });

    test('deleting a note for good deletes its images', () async {
      final image = await phone.repo.addImage(photo);
      final note = await phone.repo.createNote(title: 'Gone', body: '', images: [image]);
      await uploads();
      expect(files.files, hasLength(1));

      await phone.repo.moveToTrash(note);
      expect(files.files, hasLength(1), reason: 'Trash keeps the images');
      expect(await phone.repo.emptyTrash(), 1);
      await uploads();
      expect(files.files, isEmpty);
    });

    test('an image shared by a conflicted copy stays until its last note goes', () async {
      final image = await phone.repo.addImage(photo);
      final original = await phone.repo.createNote(title: 'A', body: '', images: [image]);
      final copy = await phone.repo.createNote(title: 'A (copy)', body: '', images: [image]);
      await uploads();

      await phone.repo.deleteNote(original.id);
      await uploads();
      expect(files.files, hasLength(1));

      await phone.repo.deleteNote(copy.id);
      await uploads();
      expect(files.files, isEmpty);
    });

    test('releasing an image still in a note keeps it', () async {
      final image = await phone.repo.addImage(photo);
      await phone.repo.createNote(title: 'Keep', body: '', images: [image]);
      await uploads();
      await phone.repo.releaseImages([image]);
      await uploads();
      expect(files.files, hasLength(1));
    });

    test('an image added offline uploads once the network is back', () async {
      files.failWith = Exception('offline');
      final image = await phone.repo.addImage(photo);
      await phone.repo.createNote(title: 'Offline', body: '', images: [image]);
      await uploads();
      expect(files.files, isEmpty);
      expect(await phone.repo.readImage(image), photo, reason: 'readable on this device');

      files.failWith = null;
      await phone.sync();
      await uploads();
      expect(files.files, hasLength(1));
    });
  });
}
