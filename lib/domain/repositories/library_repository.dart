import '../entities/folder.dart';
import '../entities/note_document.dart';
import '../entities/page_spec.dart';

abstract interface class LibraryRepository {
  Stream<List<Folder>> watchFolders();
  Stream<List<NoteMeta>> watchNotes(String? folderId);

  Future<NoteMeta> createNote({
    NoteKind kind = NoteKind.note,
    String? folderId,
    PaperTemplate template = PaperTemplate.blank,
  });

  /// Creates a note whose pages are the PDF's pages. [pdfPath] is the
  /// picked file; it gets copied into the note directory.
  Future<NoteMeta> createNoteFromPdf({
    required String pdfPath,
    String? folderId,
  });

  Future<void> renameNote(String id, String title);
  Future<void> moveNote(String id, String? folderId);
  Future<void> deleteNote(String id);

  Future<Folder> createFolder(String name, {String? parentId});
  Future<void> renameFolder(String id, String name);

  /// Deletes the folder; contained notes and subfolders move to its parent.
  Future<void> deleteFolder(String id);

  Future<String?> lastRoute();
  Future<void> setLastRoute(String route);
}
