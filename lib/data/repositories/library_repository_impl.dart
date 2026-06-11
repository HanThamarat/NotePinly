import 'package:drift/drift.dart' show Value;

import '../../domain/entities/folder.dart' as domain;
import '../../domain/entities/note_document.dart';
import '../../domain/entities/page_spec.dart';
import '../../domain/repositories/library_repository.dart';
import '../../domain/services/pdf_renderer.dart';
import '../../domain/util/id_generator.dart';
import '../db/app_database.dart';
import '../files/note_file_store.dart';

class LibraryRepositoryImpl implements LibraryRepository {
  LibraryRepositoryImpl({
    required this.db,
    required this.files,
    this.pdfRenderer,
  });

  final AppDatabase db;
  final NoteFileStore files;
  final PdfRenderer? pdfRenderer;

  String _newId(String prefix) => newId(prefix);

  @override
  Stream<List<domain.Folder>> watchFolders() =>
      db.watchFolders().map((rows) => [
            for (final f in rows)
              domain.Folder(
                id: f.id,
                name: f.name,
                parentId: f.parentId,
                sortOrder: f.sortOrder,
              ),
          ]);

  @override
  Stream<List<domain.NoteMeta>> watchNotes(String? folderId) =>
      db.watchNotesIn(folderId).map((rows) => [
            for (final n in rows)
              domain.NoteMeta(
                id: n.id,
                title: n.title,
                folderId: n.folderId,
                kind: n.kind == 'whiteboard'
                    ? NoteKind.whiteboard
                    : NoteKind.note,
                updatedAt: n.updatedAt,
                thumbnailPath: n.thumbnailPath,
              ),
          ]);

  @override
  Future<domain.NoteMeta> createNote({
    NoteKind kind = NoteKind.note,
    String? folderId,
    PaperTemplate template = PaperTemplate.blank,
  }) async {
    final id = _newId(kind == NoteKind.whiteboard ? 'wb' : 'note');
    final title =
        kind == NoteKind.whiteboard ? 'Untitled whiteboard' : 'Untitled note';
    final now = DateTime.now();
    await files
        .writeDocument(NoteDocument.blank(id: id, kind: kind, template: template));
    await db.upsertNote(Note(
      id: id,
      title: title,
      folderId: folderId,
      kind: kind.name,
      thumbnailPath: null,
      createdAt: now,
      updatedAt: now,
    ));
    return domain.NoteMeta(
        id: id, title: title, folderId: folderId, kind: kind, updatedAt: now);
  }

  @override
  Future<domain.NoteMeta> createNoteFromPdf({
    required String pdfPath,
    String? folderId,
  }) async {
    final renderer = pdfRenderer;
    if (renderer == null) {
      throw StateError('No PDF renderer available');
    }
    final id = _newId('pdf');
    final storedPdf = await files.importPdf(id, pdfPath);
    final handle = await renderer.open(storedPdf);
    try {
      final pages = <NotePage>[];
      for (var i = 0; i < handle.pageCount; i++) {
        final size = await handle.pageSize(i);
        pages.add(NotePage(
          spec: PageSpec(
            id: '$id-p$i',
            width: size.width,
            height: size.height,
            pdfPageIndex: i,
          ),
        ));
      }
      final doc = NoteDocument(
        id: id,
        pages: pages,
        sourcePdfPath: storedPdf,
      );
      await files.writeDocument(doc);
    } finally {
      await handle.close();
    }

    final title = pdfPath
        .split(RegExp(r'[\\/]'))
        .last
        .replaceFirst(RegExp(r'\.pdf$', caseSensitive: false), '');
    final now = DateTime.now();
    await db.upsertNote(Note(
      id: id,
      title: title,
      folderId: folderId,
      kind: 'note',
      thumbnailPath: null,
      createdAt: now,
      updatedAt: now,
    ));
    return domain.NoteMeta(
        id: id, title: title, folderId: folderId, updatedAt: now);
  }

  @override
  Future<void> renameNote(String id, String title) async {
    final row = await db.noteById(id);
    if (row == null) return;
    await db.upsertNote(row.copyWith(title: title, updatedAt: DateTime.now()));
  }

  @override
  Future<void> moveNote(String id, String? folderId) async {
    final row = await db.noteById(id);
    if (row == null) return;
    await db.upsertNote(row.copyWith(folderId: Value(folderId)));
  }

  @override
  Future<void> deleteNote(String id) async {
    await db.deleteNoteById(id);
    await files.deleteNote(id);
  }

  @override
  Future<domain.Folder> createFolder(String name, {String? parentId}) async {
    final folder = Folder(
      id: _newId('folder'),
      name: name,
      parentId: parentId,
      sortOrder: 0,
      createdAt: DateTime.now(),
    );
    await db.upsertFolder(folder);
    return domain.Folder(id: folder.id, name: name, parentId: parentId);
  }

  @override
  Future<void> renameFolder(String id, String name) async {
    final rows = await db.watchFolders().first;
    final row = rows.where((f) => f.id == id).firstOrNull;
    if (row == null) return;
    await db.upsertFolder(row.copyWith(name: name));
  }

  @override
  Future<void> deleteFolder(String id) async {
    final folders = await db.watchFolders().first;
    final target = folders.where((f) => f.id == id).firstOrNull;
    if (target == null) return;
    // Contents move up to the deleted folder's parent — never deleted.
    for (final child in folders.where((f) => f.parentId == id)) {
      await db.upsertFolder(child.copyWith(parentId: Value(target.parentId)));
    }
    final notes = await db.watchNotesIn(id).first;
    for (final note in notes) {
      await db.upsertNote(note.copyWith(folderId: Value(target.parentId)));
    }
    await db.deleteFolderById(id);
  }

  @override
  Future<String?> lastRoute() => db.stateValue('lastRoute');

  @override
  Future<void> setLastRoute(String route) =>
      db.setStateValue('lastRoute', route);
}
