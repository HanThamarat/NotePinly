import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../domain/entities/document_op.dart';
import '../../domain/entities/note_document.dart';

/// Per-note directory layout (ARCHITECTURE.md):
///
/// ```
/// notes/<noteId>/
///   content.json     canonical document snapshot
///   journal.ndjson   ops since the last snapshot (crash recovery)
///   assets/          imported images
///   source.pdf       original PDF for PDF-backed notes
///   thumbnail.png    library preview
/// ```
///
/// Write order keeps a recoverable state at every step: append ops
/// immediately; snapshot = write tmp → swap → truncate journal. Ops are
/// idempotent on apply, so replaying a journal that overlaps the
/// snapshot is safe.
class NoteFileStore {
  NoteFileStore(this.root);

  final Directory root;

  Directory noteDir(String id) => Directory('${root.path}/notes/$id');
  File contentFile(String id) => File('${noteDir(id).path}/content.json');
  File _tmpFile(String id) => File('${noteDir(id).path}/content.json.tmp');
  File journalFile(String id) => File('${noteDir(id).path}/journal.ndjson');
  Directory assetsDir(String id) => Directory('${noteDir(id).path}/assets');
  File thumbnailFile(String id) => File('${noteDir(id).path}/thumbnail.png');
  File sourcePdfFile(String id) => File('${noteDir(id).path}/source.pdf');

  Future<NoteDocument?> readDocument(String id) async {
    var file = contentFile(id);
    if (!file.existsSync()) {
      // A crash between delete and rename leaves only the tmp snapshot.
      final tmp = _tmpFile(id);
      if (!tmp.existsSync()) return null;
      file = tmp;
    }
    NoteDocument doc;
    try {
      doc = NoteDocument.fromJson(
          jsonDecode(await file.readAsString()) as Map<String, dynamic>);
    } on Object {
      return null;
    }
    return _replayJournal(id, doc);
  }

  Future<NoteDocument> _replayJournal(String id, NoteDocument doc) async {
    final journal = journalFile(id);
    if (!journal.existsSync()) return doc;
    var result = doc;
    for (final line in await journal.readAsLines()) {
      if (line.trim().isEmpty) continue;
      try {
        final op =
            DocumentOp.fromJson(jsonDecode(line) as Map<String, dynamic>);
        result = op.apply(result);
      } on Object {
        // A torn final line from a crash mid-append: stop replaying.
        break;
      }
    }
    return result;
  }

  Future<void> writeDocument(NoteDocument doc) async {
    final dir = noteDir(doc.id);
    dir.createSync(recursive: true);
    final tmp = _tmpFile(doc.id);
    await tmp.writeAsString(jsonEncode(doc.toJson()), flush: true);
    final content = contentFile(doc.id);
    if (content.existsSync()) content.deleteSync();
    tmp.renameSync(content.path);
    final journal = journalFile(doc.id);
    if (journal.existsSync()) await journal.writeAsString('', flush: true);
  }

  Future<void> appendOp(String id, DocumentOp op) async {
    noteDir(id).createSync(recursive: true);
    await journalFile(id).writeAsString(
      '${jsonEncode(op.toJson())}\n',
      mode: FileMode.append,
      flush: true,
    );
  }

  Future<String> importImage(String noteId, Uint8List bytes) async {
    final dir = assetsDir(noteId)..createSync(recursive: true);
    final file =
        File('${dir.path}/${DateTime.now().microsecondsSinceEpoch}.img');
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  Future<String> importPdf(String noteId, String pdfPath) async {
    noteDir(noteId).createSync(recursive: true);
    final target = sourcePdfFile(noteId);
    await File(pdfPath).copy(target.path);
    return target.path;
  }

  Future<void> writeThumbnail(String noteId, Uint8List pngBytes) async {
    noteDir(noteId).createSync(recursive: true);
    await thumbnailFile(noteId).writeAsBytes(pngBytes, flush: true);
  }

  Future<void> deleteNote(String id) async {
    final dir = noteDir(id);
    if (dir.existsSync()) await dir.delete(recursive: true);
  }
}
