import 'dart:async';
import 'dart:ui' show Color;

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../domain/entities/document_op.dart';
import '../../../domain/entities/image_object.dart';
import '../../../domain/entities/note_document.dart';
import '../../../domain/entities/page_spec.dart';
import '../../../domain/entities/stroke.dart';
import '../../../domain/repositories/note_repository.dart';
import '../../../domain/util/id_generator.dart';

// --- Events ---

sealed class NoteEditorEvent extends Equatable {
  const NoteEditorEvent();

  @override
  List<Object?> get props => [];
}

final class EditorLoadRequested extends NoteEditorEvent {
  const EditorLoadRequested();
}

final class EditorStrokeCommitted extends NoteEditorEvent {
  const EditorStrokeCommitted(this.stroke);

  final Stroke stroke;

  @override
  List<Object?> get props => [stroke];
}

final class EditorStrokesErased extends NoteEditorEvent {
  const EditorStrokesErased(this.removed, this.added);

  final List<Stroke> removed;
  final List<Stroke> added;

  @override
  List<Object?> get props => [removed, added];
}

final class EditorUndoRequested extends NoteEditorEvent {
  const EditorUndoRequested();
}

final class EditorRedoRequested extends NoteEditorEvent {
  const EditorRedoRequested();
}

final class EditorPageCleared extends NoteEditorEvent {
  const EditorPageCleared();
}

final class EditorSelectionChanged extends NoteEditorEvent {
  const EditorSelectionChanged(this.strokeIds, {this.imageId});

  final Set<String> strokeIds;
  final String? imageId;

  @override
  List<Object?> get props => [strokeIds, imageId];
}

final class EditorSelectionTransformed extends NoteEditorEvent {
  const EditorSelectionTransformed(this.before, this.after);

  final List<Stroke> before;
  final List<Stroke> after;

  @override
  List<Object?> get props => [before, after];
}

final class EditorSelectionRecolored extends NoteEditorEvent {
  const EditorSelectionRecolored(this.color);

  final Color color;

  @override
  List<Object?> get props => [color];
}

final class EditorSelectionDeleted extends NoteEditorEvent {
  const EditorSelectionDeleted();
}

final class EditorImageAdded extends NoteEditorEvent {
  const EditorImageAdded(this.image);

  final ImageObject image;

  @override
  List<Object?> get props => [image];
}

final class EditorImageTransformed extends NoteEditorEvent {
  const EditorImageTransformed(this.before, this.after);

  final ImageObject before;
  final ImageObject after;

  @override
  List<Object?> get props => [before, after];
}

final class EditorImageDeleted extends NoteEditorEvent {
  const EditorImageDeleted();
}

final class EditorPageChanged extends NoteEditorEvent {
  const EditorPageChanged(this.pageIndex);

  final int pageIndex;

  @override
  List<Object?> get props => [pageIndex];
}

final class EditorPageAdded extends NoteEditorEvent {
  const EditorPageAdded();
}

final class EditorTemplateChanged extends NoteEditorEvent {
  const EditorTemplateChanged(this.template);

  final PaperTemplate template;

  @override
  List<Object?> get props => [template];
}

final class EditorPageRotated extends NoteEditorEvent {
  const EditorPageRotated();
}

final class EditorFlushRequested extends NoteEditorEvent {
  const EditorFlushRequested();
}

// --- State ---

enum EditorStatus { loading, ready, error }

final class NoteEditorState extends Equatable {
  const NoteEditorState({
    this.status = EditorStatus.loading,
    this.document,
    this.pageIndex = 0,
    this.selectedStrokeIds = const {},
    this.selectedImageId,
    this.canUndo = false,
    this.canRedo = false,
    this.revision = 0,
  });

  final EditorStatus status;
  final NoteDocument? document;
  final int pageIndex;
  final Set<String> selectedStrokeIds;
  final String? selectedImageId;
  final bool canUndo;
  final bool canRedo;

  /// Monotonic document version; painters key caches off this.
  final int revision;

  NotePage? get currentPage =>
      document == null || document!.pages.isEmpty ? null : document!.pages[pageIndex];

  bool get hasSelection =>
      selectedStrokeIds.isNotEmpty || selectedImageId != null;

  NoteEditorState copyWith({
    EditorStatus? status,
    NoteDocument? document,
    int? pageIndex,
    Set<String>? selectedStrokeIds,
    Object? selectedImageId = _sentinel,
    bool? canUndo,
    bool? canRedo,
    int? revision,
  }) =>
      NoteEditorState(
        status: status ?? this.status,
        document: document ?? this.document,
        pageIndex: pageIndex ?? this.pageIndex,
        selectedStrokeIds: selectedStrokeIds ?? this.selectedStrokeIds,
        selectedImageId: selectedImageId == _sentinel
            ? this.selectedImageId
            : selectedImageId as String?,
        canUndo: canUndo ?? this.canUndo,
        canRedo: canRedo ?? this.canRedo,
        revision: revision ?? this.revision,
      );

  static const _sentinel = Object();

  @override
  List<Object?> get props => [
        status,
        document,
        pageIndex,
        selectedStrokeIds,
        selectedImageId,
        canUndo,
        canRedo,
        revision,
      ];
}

// --- Bloc ---

/// Owns the committed document, undo/redo, selection, and the save
/// schedule. The live drawing path never touches this bloc; completed
/// strokes and gestures arrive as ops.
///
/// Persistence: every applied op is appended to the journal immediately;
/// a debounced full snapshot rewrites content.json and truncates the
/// journal (ARCHITECTURE.md, Auto-save).
class NoteEditorBloc extends Bloc<NoteEditorEvent, NoteEditorState> {
  NoteEditorBloc({
    required this.noteId,
    this.repository,
    NoteDocument? initialDocument,
    this.maxHistory = 200,
    this.saveDebounce = const Duration(seconds: 2),
  }) : super(initialDocument == null
            ? const NoteEditorState()
            : NoteEditorState(
                status: EditorStatus.ready, document: initialDocument)) {
    on<EditorLoadRequested>(_onLoad);
    on<EditorStrokeCommitted>(
        (e, emit) => _push(AddStrokeOp(state.pageIndex, e.stroke), emit));
    on<EditorStrokesErased>(_onErased);
    on<EditorUndoRequested>(_onUndo);
    on<EditorRedoRequested>(_onRedo);
    on<EditorPageCleared>(_onPageCleared);
    on<EditorSelectionChanged>(_onSelectionChanged);
    on<EditorSelectionTransformed>(_onSelectionTransformed);
    on<EditorSelectionRecolored>(_onSelectionRecolored);
    on<EditorSelectionDeleted>(_onSelectionDeleted);
    on<EditorImageAdded>(_onImageAdded);
    on<EditorImageTransformed>(_onImageTransformed);
    on<EditorImageDeleted>(_onImageDeleted);
    on<EditorPageChanged>(_onPageChanged);
    on<EditorPageAdded>(_onPageAdded);
    on<EditorTemplateChanged>(_onTemplateChanged);
    on<EditorPageRotated>(
        (e, emit) => _push(RotatePageOp(state.pageIndex), emit));
    on<EditorFlushRequested>((e, emit) async => _flushNow());

    if (initialDocument == null) add(const EditorLoadRequested());
  }

  final String noteId;
  final NoteRepository? repository;
  final int maxHistory;
  final Duration saveDebounce;

  final List<DocumentOp> _undoStack = [];
  final List<DocumentOp> _redoStack = [];
  Timer? _saveTimer;
  bool _dirty = false;

  Future<void> _onLoad(
      EditorLoadRequested event, Emitter<NoteEditorState> emit) async {
    final repo = repository;
    if (repo == null) {
      emit(NoteEditorState(
        status: EditorStatus.ready,
        document: NoteDocument.blank(id: noteId),
      ));
      return;
    }
    try {
      final doc = await repo.loadDocument(noteId);
      emit(NoteEditorState(status: EditorStatus.ready, document: doc));
    } catch (_) {
      emit(state.copyWith(status: EditorStatus.error));
    }
  }

  // --- Op plumbing ---

  void _push(DocumentOp op, Emitter<NoteEditorState> emit,
      {Set<String>? selection, String? imageSelection}) {
    final doc = state.document;
    if (doc == null) return;
    _undoStack.add(op);
    if (_undoStack.length > maxHistory) _undoStack.removeAt(0);
    _redoStack.clear();
    _persist(op);
    emit(state.copyWith(
      document: op.apply(doc),
      selectedStrokeIds: selection ?? state.selectedStrokeIds,
      selectedImageId: imageSelection,
      canUndo: true,
      canRedo: false,
      revision: state.revision + 1,
    ));
  }

  void _onUndo(EditorUndoRequested event, Emitter<NoteEditorState> emit) {
    final doc = state.document;
    if (doc == null || _undoStack.isEmpty) return;
    final op = _undoStack.removeLast();
    _redoStack.add(op);
    _markDirty();
    emit(state.copyWith(
      document: op.invert(doc),
      selectedStrokeIds: const {},
      selectedImageId: null,
      canUndo: _undoStack.isNotEmpty,
      canRedo: true,
      revision: state.revision + 1,
    ));
  }

  void _onRedo(EditorRedoRequested event, Emitter<NoteEditorState> emit) {
    final doc = state.document;
    if (doc == null || _redoStack.isEmpty) return;
    final op = _redoStack.removeLast();
    _undoStack.add(op);
    _markDirty();
    emit(state.copyWith(
      document: op.apply(doc),
      selectedStrokeIds: const {},
      selectedImageId: null,
      canUndo: true,
      canRedo: _redoStack.isNotEmpty,
      revision: state.revision + 1,
    ));
  }

  // --- Feature handlers ---

  void _onErased(EditorStrokesErased event, Emitter<NoteEditorState> emit) {
    if (event.removed.isEmpty && event.added.isEmpty) return;
    _push(EraseStrokesOp(state.pageIndex, event.removed, event.added), emit);
  }

  void _onPageCleared(EditorPageCleared event, Emitter<NoteEditorState> emit) {
    final page = state.currentPage;
    if (page == null || (page.strokes.isEmpty && page.images.isEmpty)) return;
    _push(
      ClearPageOp(state.pageIndex, page.strokes, page.images),
      emit,
      selection: const {},
    );
  }

  void _onSelectionChanged(
      EditorSelectionChanged event, Emitter<NoteEditorState> emit) {
    emit(state.copyWith(
      selectedStrokeIds: event.strokeIds,
      selectedImageId: event.imageId,
    ));
  }

  void _onSelectionTransformed(
      EditorSelectionTransformed event, Emitter<NoteEditorState> emit) {
    if (event.before.isEmpty) return;
    _push(
      ReplaceStrokesOp(state.pageIndex, event.before, event.after),
      emit,
      selection: {for (final s in event.after) s.id},
    );
  }

  void _onSelectionRecolored(
      EditorSelectionRecolored event, Emitter<NoteEditorState> emit) {
    final page = state.currentPage;
    if (page == null || state.selectedStrokeIds.isEmpty) return;
    final selected =
        [for (final s in page.strokes) if (state.selectedStrokeIds.contains(s.id)) s];
    _push(
      RecolorStrokesOp(
        state.pageIndex,
        [for (final s in selected) s.id],
        [for (final s in selected) _argb(s.color)],
        _argb(event.color),
      ),
      emit,
      selection: state.selectedStrokeIds,
    );
  }

  void _onSelectionDeleted(
      EditorSelectionDeleted event, Emitter<NoteEditorState> emit) {
    final page = state.currentPage;
    if (page == null) return;
    if (state.selectedImageId != null) {
      final index =
          page.images.indexWhere((i) => i.id == state.selectedImageId);
      if (index >= 0) {
        _push(DeleteImageOp(state.pageIndex, page.images[index], index), emit,
            selection: const {});
      }
      return;
    }
    final selected =
        [for (final s in page.strokes) if (state.selectedStrokeIds.contains(s.id)) s];
    if (selected.isEmpty) return;
    _push(ReplaceStrokesOp(state.pageIndex, selected, const []), emit,
        selection: const {});
  }

  void _onImageAdded(EditorImageAdded event, Emitter<NoteEditorState> emit) {
    _push(AddImageOp(state.pageIndex, event.image), emit,
        selection: const {}, imageSelection: event.image.id);
  }

  void _onImageTransformed(
      EditorImageTransformed event, Emitter<NoteEditorState> emit) {
    _push(TransformImageOp(state.pageIndex, event.before, event.after), emit,
        imageSelection: event.after.id);
  }

  void _onImageDeleted(EditorImageDeleted event, Emitter<NoteEditorState> emit) {
    _onSelectionDeleted(const EditorSelectionDeleted(), emit);
  }

  void _onPageChanged(EditorPageChanged event, Emitter<NoteEditorState> emit) {
    final doc = state.document;
    if (doc == null) return;
    final index = event.pageIndex.clamp(0, doc.pages.length - 1);
    if (index == state.pageIndex) return;
    emit(state.copyWith(
      pageIndex: index,
      selectedStrokeIds: const {},
      selectedImageId: null,
    ));
  }

  void _onPageAdded(EditorPageAdded event, Emitter<NoteEditorState> emit) {
    final doc = state.document;
    final page = state.currentPage;
    if (doc == null || page == null) return;
    final newIndex = state.pageIndex + 1;
    final spec = PageSpec(
      id: newId('$noteId-p'),
      width: page.spec.width,
      height: page.spec.height,
      template: page.spec.template,
    );
    _push(AddPageOp(newIndex, spec), emit, selection: const {});
    add(EditorPageChanged(newIndex));
  }

  void _onTemplateChanged(
      EditorTemplateChanged event, Emitter<NoteEditorState> emit) {
    final page = state.currentPage;
    if (page == null || page.spec.template == event.template) return;
    _push(
        SetTemplateOp(state.pageIndex, page.spec.template, event.template),
        emit);
  }

  // --- Persistence ---

  void _persist(DocumentOp op) {
    final repo = repository;
    if (repo == null) return;
    unawaited(repo.appendOp(noteId, op).catchError((_) {}));
    _markDirty();
  }

  void _markDirty() {
    if (repository == null) return;
    _dirty = true;
    _saveTimer?.cancel();
    _saveTimer = Timer(saveDebounce, _flushNow);
  }

  void _flushNow() {
    final repo = repository;
    final doc = state.document;
    if (repo == null || doc == null || !_dirty) return;
    _dirty = false;
    _saveTimer?.cancel();
    unawaited(repo.saveDocument(doc).catchError((_) {}));
  }

  @override
  Future<void> close() {
    _flushNow();
    _saveTimer?.cancel();
    return super.close();
  }

  static int _argb(Color c) =>
      (((c.a * 255).round() & 0xFF) << 24) |
      (((c.r * 255).round() & 0xFF) << 16) |
      (((c.g * 255).round() & 0xFF) << 8) |
      ((c.b * 255).round() & 0xFF);
}
