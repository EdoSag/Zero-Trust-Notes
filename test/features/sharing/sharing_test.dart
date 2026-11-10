import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:zero_trust_core/zero_trust_core.dart';
import 'package:zerotrust_notes/src/features/notes/domain/checklist_item.dart';
import 'package:zerotrust_notes/src/features/notes/domain/note.dart';
import 'package:zerotrust_notes/src/features/sharing/note_sharing.dart';
import 'package:zerotrust_notes/src/features/widgets/domain/pending_widget_action.dart';

void main() {
  Note note({String title = '', String body = '', List<ChecklistItem>? checklist}) => Note(
    id: 'n',
    notebookId: null,
    title: title,
    body: body,
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
    checklist: checklist,
  );

  group('noteShareText', () {
    test('title, blank line, text', () {
      expect(noteShareText(note(title: ' Plan ', body: 'ship it\n')), 'Plan\n\nship it');
    });

    test('a note without a title is just its text', () {
      expect(noteShareText(note(body: 'hello')), 'hello');
    });

    test('a checklist is sent with boxes, not Markdown', () {
      final text = noteShareText(
        note(
          title: 'Shop',
          body: '- [ ] milk',
          checklist: [
            ChecklistItem.create('milk'),
            ChecklistItem.create('eggs', checked: true),
            ChecklistItem.create('  '),
          ],
        ),
      );
      expect(text, 'Shop\n\n☐ milk\n☑ eggs');
    });

    test('an empty note sends nothing', () {
      expect(noteShareText(note(title: ' ', body: '\n')), '');
    });

    test('images do not change the text', () {
      final withImage = Note(
        id: 'n',
        notebookId: null,
        title: 'Pic',
        body: '',
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
        images: [ZtAttachmentRef(id: '0' * 32, key: Uint8List(32), size: 1)],
      );
      expect(noteShareText(withImage), 'Pic');
    });
  });

  group('SharedContent', () {
    test('reads what the Android side hands over', () {
      final content = SharedContent.fromMap({
        'text': 'https://example.com/article',
        'subject': 'An article',
        'images': [
          {'path': '/cache/shared_in/a', 'mimeType': 'image/png', 'name': 'a.png'},
          {'mimeType': 'image/png'},
        ],
        'skipped': 2,
      });
      expect(content.title, 'An article');
      expect(content.body, 'https://example.com/article');
      expect(content.images.single.path, '/cache/shared_in/a');
      expect(content.images.single.name, 'a.png');
      expect(content.skipped, 2);
    });

    test('a subject that repeats the text is not used as the title', () {
      final content = SharedContent.fromMap({'text': 'hello', 'subject': 'hello'});
      expect(content.title, '');
      expect(content.body, 'hello');
    });
  });
}
