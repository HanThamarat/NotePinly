import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;

import '../../domain/entities/document_op.dart';
import '../../domain/entities/note_document.dart';
import '../../domain/repositories/note_repository.dart';
import '../db/app_database.dart';
import '../files/note_file_store.dart';
import '../files/thumbnailer.dart';

class NoteRepositoryImpl implements NoteRepository {
  NoteRepositoryImpl({required this.db, required this.files});

  final AppDatabase db;
  final NoteFileStore files;

  @override
  Future<NoteDocument> loadDocument(String noteId) async {
    final stored = await files.readDocument(noteId);
    if (stored != null) return stored;
    // Direct navigation to a note that has no content yet (or whose
    // files were lost): start blank with the kind recorded in the DB.
    final row = await db.noteById(noteId);
    final kind = row?.kind == 'whiteboard' ? NoteKind.whiteboard : NoteKind.note;
    return NoteDocument.blank(id: noteId, kind: kind);
  }

  @override
  Future<void> appendOp(String noteId, DocumentOp op) =>
      files.appendOp(noteId, op);

  @override
  Future<void> saveDocument(NoteDocument document) async {
    await files.writeDocument(document);
    final row = await db.noteById(document.id);
    String? thumbnailPath;
    if (document.kind == NoteKind.note) {
      final png = await renderThumbnailPng(document);
      if (png != null) {
        await files.writeThumbnail(document.id, Uint8List.fromList(png));
        thumbnailPath = files.thumbnailFile(document.id).path;
      }
    }
    if (row != null) {
      await db.upsertNote(row.copyWith(
        updatedAt: DateTime.now(),
        thumbnailPath: Value(thumbnailPath ?? row.thumbnailPath),
      ));
    }
  }

  @override
  Future<String> importImageBytes(String noteId, Uint8List bytes) =>
      files.importImage(noteId, bytes);

  @override
  String sourcePdfPath(String noteId) => files.sourcePdfFile(noteId).path;
}
