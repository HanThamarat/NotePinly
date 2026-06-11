import 'dart:typed_data';

import '../entities/document_op.dart';
import '../entities/note_document.dart';

/// Content persistence for a single note. Implementations must be
/// crash-safe: [appendOp] lands on disk immediately and cheaply, while
/// [saveDocument] is the debounced full snapshot that truncates the
/// journal.
abstract interface class NoteRepository {
  Future<NoteDocument> loadDocument(String noteId);

  Future<void> appendOp(String noteId, DocumentOp op);

  Future<void> saveDocument(NoteDocument document);

  /// Copies image bytes into the note's assets directory; returns the
  /// stored file path for an [ImageObject.assetPath].
  Future<String> importImageBytes(String noteId, Uint8List bytes);

  /// Absolute path of the note's source PDF, for PDF-backed pages.
  String sourcePdfPath(String noteId);
}
