import 'dart:io';
import 'dart:ui';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notepinly/data/db/app_database.dart';
import 'package:notepinly/data/files/note_file_store.dart';
import 'package:notepinly/data/repositories/library_repository_impl.dart';
import 'package:notepinly/data/repositories/note_repository_impl.dart';
import 'package:notepinly/domain/entities/document_op.dart';
import 'package:notepinly/domain/entities/image_object.dart';
import 'package:notepinly/domain/entities/note_document.dart';
import 'package:notepinly/domain/entities/page_spec.dart';
import 'package:notepinly/domain/entities/stroke.dart';

Stroke _stroke(String id) => Stroke(
      id: id,
      color: const Color(0xFF005D89),
      baseWidth: 3.5,
      points: const [
        StrokePoint(x: 1, y: 2, pressure: 0.4, timestampMs: 0),
        StrokePoint(x: 30, y: 40, pressure: 0.8, tilt: 0.2, timestampMs: 16),
      ],
    );

const _image = ImageObject(
  id: 'img1',
  assetPath: 'x.png',
  x: 10,
  y: 10,
  width: 100,
  height: 80,
);

void main() {
  late Directory tempDir;
  late NoteFileStore files;
  late AppDatabase db;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('notepinly_test');
    files = NoteFileStore(tempDir);
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
    tempDir.deleteSync(recursive: true);
  });

  group('Document ops JSON', () {
    test('every op type round-trips through the journal encoding', () {
      final ops = <DocumentOp>[
        AddStrokeOp(0, _stroke('a')),
        EraseStrokesOp(0, [_stroke('a')], [_stroke('f1')]),
        ReplaceStrokesOp(0, [_stroke('a')], [_stroke('a')]),
        const RecolorStrokesOp(0, ['a'], [0xFF161C1E], 0xFFB02A2D),
        const AddImageOp(0, _image),
        TransformImageOp(
            0, _image, _image.withRect(const Rect.fromLTWH(0, 0, 50, 40))),
        const DeleteImageOp(0, _image, 0),
        const AddPageOp(1, PageSpec(id: 'p2')),
        const SetTemplateOp(0, PaperTemplate.blank, PaperTemplate.grid),
        const RotatePageOp(0),
        ClearPageOp(0, [_stroke('a')], const [_image]),
      ];
      for (final op in ops) {
        final decoded = DocumentOp.fromJson(op.toJson());
        expect(decoded.toJson(), op.toJson(),
            reason: op.runtimeType.toString());
      }
    });

    test('apply followed by invert is identity', () {
      var doc = NoteDocument.blank(id: 'n');
      final ops = <DocumentOp>[
        AddStrokeOp(0, _stroke('a')),
        const AddImageOp(0, _image),
        const AddPageOp(1, PageSpec(id: 'p2')),
        const SetTemplateOp(0, PaperTemplate.blank, PaperTemplate.dotted),
        const RotatePageOp(0),
      ];
      for (final op in ops) {
        final applied = op.apply(doc);
        expect(op.invert(applied), doc, reason: op.runtimeType.toString());
        doc = applied;
      }
    });
  });

  group('NoteFileStore', () {
    test('document snapshot round-trips', () async {
      final doc = NoteDocument.blank(id: 'n1')
          .withPage(
              0,
              NotePage(
                spec: const PageSpec(id: 'n1-p0'),
                strokes: [_stroke('a')],
                images: const [_image],
              ));
      await files.writeDocument(doc);
      final loaded = await files.readDocument('n1');
      expect(loaded, doc);
    });

    test('journal ops are replayed over the snapshot (crash recovery)',
        () async {
      await files.writeDocument(NoteDocument.blank(id: 'n1'));
      // Simulate a crash: ops journaled but never snapshotted.
      await files.appendOp('n1', AddStrokeOp(0, _stroke('a')));
      await files.appendOp('n1', AddStrokeOp(0, _stroke('b')));
      final recovered = await files.readDocument('n1');
      expect(recovered!.pages.first.strokes.map((s) => s.id), ['a', 'b']);
    });

    test('snapshot truncates the journal', () async {
      final doc = NoteDocument.blank(id: 'n1');
      await files.writeDocument(doc);
      await files.appendOp('n1', AddStrokeOp(0, _stroke('a')));
      await files.writeDocument(AddStrokeOp(0, _stroke('a')).apply(doc));
      final loaded = await files.readDocument('n1');
      expect(loaded!.pages.first.strokes, hasLength(1));
    });

    test('replay over an already-applied op does not duplicate (idempotent)',
        () async {
      final withStroke =
          AddStrokeOp(0, _stroke('a')).apply(NoteDocument.blank(id: 'n1'));
      await files.writeDocument(withStroke);
      // Crash before truncation: the op is in the snapshot AND the journal.
      await files.appendOp('n1', AddStrokeOp(0, _stroke('a')));
      final loaded = await files.readDocument('n1');
      expect(loaded!.pages.first.strokes, hasLength(1));
    });

    test('a torn journal line stops replay without losing earlier ops',
        () async {
      await files.writeDocument(NoteDocument.blank(id: 'n1'));
      await files.appendOp('n1', AddStrokeOp(0, _stroke('a')));
      await files
          .journalFile('n1')
          .writeAsString('{"op":"addStroke","pa', mode: FileMode.append);
      final loaded = await files.readDocument('n1');
      expect(loaded!.pages.first.strokes.map((s) => s.id), ['a']);
    });
  });

  group('NoteRepositoryImpl', () {
    test('save updates updatedAt and writes a thumbnail', () async {
      final repo = NoteRepositoryImpl(db: db, files: files);
      final earlier = DateTime.now().subtract(const Duration(days: 1));
      await db.upsertNote(Note(
        id: 'n1',
        title: 't',
        folderId: null,
        kind: 'note',
        thumbnailPath: null,
        createdAt: earlier,
        updatedAt: earlier,
      ));
      await repo.saveDocument(
          AddStrokeOp(0, _stroke('a')).apply(NoteDocument.blank(id: 'n1')));

      final row = await db.noteById('n1');
      expect(row!.updatedAt.isAfter(earlier), isTrue);
      expect(row.thumbnailPath, isNotNull);
      expect(File(row.thumbnailPath!).existsSync(), isTrue);
    });

    test('loadDocument falls back to a blank doc of the recorded kind',
        () async {
      final repo = NoteRepositoryImpl(db: db, files: files);
      final now = DateTime.now();
      await db.upsertNote(Note(
        id: 'wb1',
        title: 'w',
        folderId: null,
        kind: 'whiteboard',
        thumbnailPath: null,
        createdAt: now,
        updatedAt: now,
      ));
      final doc = await repo.loadDocument('wb1');
      expect(doc.kind, NoteKind.whiteboard);
    });
  });

  group('LibraryRepositoryImpl', () {
    late LibraryRepositoryImpl repo;

    setUp(() => repo = LibraryRepositoryImpl(db: db, files: files));

    test('createNote writes the row and a loadable blank document', () async {
      final meta = await repo.createNote();
      final notes = await repo.watchNotes(null).first;
      expect(notes.map((n) => n.id), contains(meta.id));
      final doc = await files.readDocument(meta.id);
      expect(doc!.pages, hasLength(1));
    });

    test('folders nest, rename, and move notes', () async {
      final parent = await repo.createFolder('School');
      final child = await repo.createFolder('Math', parentId: parent.id);
      final note = await repo.createNote();
      await repo.moveNote(note.id, child.id);

      expect((await repo.watchNotes(child.id).first).single.id, note.id);
      expect(await repo.watchNotes(null).first, isEmpty);

      await repo.renameFolder(child.id, 'Algebra');
      final folders = await repo.watchFolders().first;
      expect(folders.firstWhere((f) => f.id == child.id).name, 'Algebra');
    });

    test('deleting a folder moves contents to its parent', () async {
      final parent = await repo.createFolder('School');
      final child = await repo.createFolder('Math', parentId: parent.id);
      final note = await repo.createNote(folderId: child.id);

      await repo.deleteFolder(child.id);

      final folders = await repo.watchFolders().first;
      expect(folders.map((f) => f.id), isNot(contains(child.id)));
      expect((await repo.watchNotes(parent.id).first).single.id, note.id);
    });

    test('deleteNote removes the row and the files', () async {
      final meta = await repo.createNote();
      expect(files.contentFile(meta.id).existsSync(), isTrue);
      await repo.deleteNote(meta.id);
      expect(await repo.watchNotes(null).first, isEmpty);
      expect(files.noteDir(meta.id).existsSync(), isFalse);
    });

    test('last route persists', () async {
      expect(await repo.lastRoute(), isNull);
      await repo.setLastRoute('/note/n1');
      expect(await repo.lastRoute(), '/note/n1');
    });
  });
}
