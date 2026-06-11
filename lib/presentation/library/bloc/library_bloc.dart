import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../domain/entities/folder.dart';
import '../../../domain/entities/note_document.dart';
import '../../../domain/repositories/library_repository.dart';

// --- Events ---

sealed class LibraryEvent extends Equatable {
  const LibraryEvent();

  @override
  List<Object?> get props => [];
}

final class LibraryStarted extends LibraryEvent {
  const LibraryStarted(this.folderId);

  final String? folderId;

  @override
  List<Object?> get props => [folderId];
}

final class _FoldersUpdated extends LibraryEvent {
  const _FoldersUpdated(this.folders);

  final List<Folder> folders;

  @override
  List<Object?> get props => [folders];
}

final class _NotesUpdated extends LibraryEvent {
  const _NotesUpdated(this.notes);

  final List<NoteMeta> notes;

  @override
  List<Object?> get props => [notes];
}

final class LibraryNoteCreated extends LibraryEvent {
  const LibraryNoteCreated(this.kind);

  final NoteKind kind;

  @override
  List<Object?> get props => [kind];
}

final class LibraryNoteFromPdfRequested extends LibraryEvent {
  const LibraryNoteFromPdfRequested(this.pdfPath);

  final String pdfPath;

  @override
  List<Object?> get props => [pdfPath];
}

final class LibraryNoteRenamed extends LibraryEvent {
  const LibraryNoteRenamed(this.noteId, this.title);

  final String noteId;
  final String title;

  @override
  List<Object?> get props => [noteId, title];
}

final class LibraryNoteMoved extends LibraryEvent {
  const LibraryNoteMoved(this.noteId, this.folderId);

  final String noteId;
  final String? folderId;

  @override
  List<Object?> get props => [noteId, folderId];
}

final class LibraryNoteDeleted extends LibraryEvent {
  const LibraryNoteDeleted(this.noteId);

  final String noteId;

  @override
  List<Object?> get props => [noteId];
}

final class LibraryFolderCreated extends LibraryEvent {
  const LibraryFolderCreated(this.name, {this.parentId});

  final String name;
  final String? parentId;

  @override
  List<Object?> get props => [name, parentId];
}

final class LibraryFolderRenamed extends LibraryEvent {
  const LibraryFolderRenamed(this.folderId, this.name);

  final String folderId;
  final String name;

  @override
  List<Object?> get props => [folderId, name];
}

final class LibraryFolderDeleted extends LibraryEvent {
  const LibraryFolderDeleted(this.folderId);

  final String folderId;

  @override
  List<Object?> get props => [folderId];
}

// --- State ---

enum LibraryStatus { loading, ready }

final class LibraryState extends Equatable {
  const LibraryState({
    this.status = LibraryStatus.loading,
    this.folderId,
    this.folders = const [],
    this.notes = const [],
    this.openNoteId,
  });

  final LibraryStatus status;
  final String? folderId;
  final List<Folder> folders;
  final List<NoteMeta> notes;

  /// Set right after a note is created so the UI can navigate into it.
  final String? openNoteId;

  Folder? get currentFolder =>
      folders.where((f) => f.id == folderId).firstOrNull;

  List<Folder> childrenOf(String? parentId) =>
      [for (final f in folders) if (f.parentId == parentId) f];

  LibraryState copyWith({
    LibraryStatus? status,
    Object? folderId = _sentinel,
    List<Folder>? folders,
    List<NoteMeta>? notes,
    Object? openNoteId = _sentinel,
  }) =>
      LibraryState(
        status: status ?? this.status,
        folderId: folderId == _sentinel ? this.folderId : folderId as String?,
        folders: folders ?? this.folders,
        notes: notes ?? this.notes,
        openNoteId:
            openNoteId == _sentinel ? this.openNoteId : openNoteId as String?,
      );

  static const _sentinel = Object();

  @override
  List<Object?> get props => [status, folderId, folders, notes, openNoteId];
}

// --- Bloc ---

class LibraryBloc extends Bloc<LibraryEvent, LibraryState> {
  LibraryBloc({required this.repository}) : super(const LibraryState()) {
    on<LibraryStarted>(_onStarted);
    on<_FoldersUpdated>((e, emit) => emit(state.copyWith(
        folders: e.folders, status: LibraryStatus.ready)));
    on<_NotesUpdated>((e, emit) =>
        emit(state.copyWith(notes: e.notes, status: LibraryStatus.ready)));
    on<LibraryNoteCreated>(_onNoteCreated);
    on<LibraryNoteFromPdfRequested>(_onNoteFromPdf);
    on<LibraryNoteRenamed>(
        (e, emit) => repository.renameNote(e.noteId, e.title));
    on<LibraryNoteMoved>(
        (e, emit) => repository.moveNote(e.noteId, e.folderId));
    on<LibraryNoteDeleted>((e, emit) => repository.deleteNote(e.noteId));
    on<LibraryFolderCreated>(
        (e, emit) => repository.createFolder(e.name, parentId: e.parentId));
    on<LibraryFolderRenamed>(
        (e, emit) => repository.renameFolder(e.folderId, e.name));
    on<LibraryFolderDeleted>(
        (e, emit) => repository.deleteFolder(e.folderId));
  }

  final LibraryRepository repository;
  StreamSubscription<List<Folder>>? _foldersSub;
  StreamSubscription<List<NoteMeta>>? _notesSub;

  Future<void> _onStarted(
      LibraryStarted event, Emitter<LibraryState> emit) async {
    emit(state.copyWith(folderId: event.folderId, openNoteId: null));
    await _foldersSub?.cancel();
    await _notesSub?.cancel();
    _foldersSub = repository
        .watchFolders()
        .listen((folders) => add(_FoldersUpdated(folders)));
    _notesSub = repository
        .watchNotes(event.folderId)
        .listen((notes) => add(_NotesUpdated(notes)));
  }

  Future<void> _onNoteCreated(
      LibraryNoteCreated event, Emitter<LibraryState> emit) async {
    final meta = await repository.createNote(
      kind: event.kind,
      folderId: state.folderId,
    );
    emit(state.copyWith(openNoteId: meta.id));
    emit(state.copyWith(openNoteId: null));
  }

  Future<void> _onNoteFromPdf(
      LibraryNoteFromPdfRequested event, Emitter<LibraryState> emit) async {
    final meta = await repository.createNoteFromPdf(
      pdfPath: event.pdfPath,
      folderId: state.folderId,
    );
    emit(state.copyWith(openNoteId: meta.id));
    emit(state.copyWith(openNoteId: null));
  }

  @override
  Future<void> close() async {
    await _foldersSub?.cancel();
    await _notesSub?.cancel();
    return super.close();
  }
}
