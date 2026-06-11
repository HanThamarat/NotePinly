import 'package:equatable/equatable.dart';

import 'note_document.dart' show NoteKind;

class Folder extends Equatable {
  const Folder({
    required this.id,
    required this.name,
    this.parentId,
    this.sortOrder = 0,
  });

  final String id;
  final String name;
  final String? parentId;
  final int sortOrder;

  @override
  List<Object?> get props => [id, name, parentId, sortOrder];
}

/// Library-level note metadata (the SQLite row, not the content).
class NoteMeta extends Equatable {
  const NoteMeta({
    required this.id,
    required this.title,
    this.folderId,
    this.kind = NoteKind.note,
    required this.updatedAt,
    this.thumbnailPath,
  });

  final String id;
  final String title;
  final String? folderId;
  final NoteKind kind;
  final DateTime updatedAt;
  final String? thumbnailPath;

  @override
  List<Object?> get props =>
      [id, title, folderId, kind, updatedAt, thumbnailPath];
}
