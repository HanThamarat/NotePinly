import 'dart:ui';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notepinly/domain/entities/editor_tool.dart';
import 'package:notepinly/domain/entities/image_object.dart';
import 'package:notepinly/domain/entities/note_document.dart';
import 'package:notepinly/domain/entities/page_spec.dart';
import 'package:notepinly/domain/entities/stroke.dart';
import 'package:notepinly/presentation/editor/bloc/note_editor_bloc.dart';
import 'package:notepinly/presentation/editor/bloc/toolbar_cubit.dart';
import 'package:notepinly/presentation/editor/engine/eraser_engine.dart';

Stroke _stroke(String id, {Color color = const Color(0xFF161C1E)}) => Stroke(
      id: id,
      color: color,
      baseWidth: 3.5,
      points: const [
        StrokePoint(x: 0, y: 0, pressure: 0.5, timestampMs: 0),
        StrokePoint(x: 10, y: 10, pressure: 0.5, timestampMs: 8),
      ],
    );

NoteEditorBloc _bloc({int maxHistory = 200}) => NoteEditorBloc(
      noteId: 'n1',
      initialDocument: NoteDocument.blank(id: 'n1'),
      maxHistory: maxHistory,
    );

List<Stroke> _strokesOf(NoteEditorBloc bloc) =>
    bloc.state.currentPage!.strokes;

void main() {
  group('NoteEditorBloc strokes & undo/redo', () {
    blocTest<NoteEditorBloc, NoteEditorState>(
      'committed stroke is appended and enables undo',
      build: _bloc,
      act: (bloc) => bloc.add(EditorStrokeCommitted(_stroke('a'), tool: EditorTool.pen)),
      verify: (bloc) {
        expect(_strokesOf(bloc).map((s) => s.id), ['a']);
        expect(bloc.state.canUndo, isTrue);
        expect(bloc.state.canRedo, isFalse);
      },
    );

    blocTest<NoteEditorBloc, NoteEditorState>(
      'undo removes the stroke, redo restores it',
      build: _bloc,
      act: (bloc) => bloc
        ..add(EditorStrokeCommitted(_stroke('a'), tool: EditorTool.pen))
        ..add(const EditorUndoRequested())
        ..add(const EditorRedoRequested()),
      verify: (bloc) {
        expect(_strokesOf(bloc).map((s) => s.id), ['a']);
        expect(bloc.state.canRedo, isFalse);
      },
    );

    blocTest<NoteEditorBloc, NoteEditorState>(
      'a new stroke clears the redo stack',
      build: _bloc,
      act: (bloc) => bloc
        ..add(EditorStrokeCommitted(_stroke('a'), tool: EditorTool.pen))
        ..add(const EditorUndoRequested())
        ..add(EditorStrokeCommitted(_stroke('b'), tool: EditorTool.pen)),
      verify: (bloc) {
        expect(_strokesOf(bloc).map((s) => s.id), ['b']);
        expect(bloc.state.canRedo, isFalse);
      },
    );

    blocTest<NoteEditorBloc, NoteEditorState>(
      'history is capped',
      build: () => _bloc(maxHistory: 3),
      act: (bloc) {
        for (var i = 0; i < 5; i++) {
          bloc.add(EditorStrokeCommitted(_stroke('s$i'), tool: EditorTool.pen));
        }
        for (var i = 0; i < 5; i++) {
          bloc.add(const EditorUndoRequested());
        }
      },
      verify: (bloc) {
        expect(_strokesOf(bloc).length, 2);
        expect(bloc.state.canUndo, isFalse);
      },
    );
  });

  group('NoteEditorBloc eraser', () {
    blocTest<NoteEditorBloc, NoteEditorState>(
      'erase removes strokes and adds fragments as one undoable op',
      build: _bloc,
      act: (bloc) => bloc
        ..add(EditorStrokeCommitted(_stroke('a'), tool: EditorTool.pen))
        ..add(EditorStrokesErased([_stroke('a')], [_stroke('frag-1')]))
        ..add(const EditorUndoRequested()),
      verify: (bloc) {
        // Undo of the erase restores the original.
        expect(_strokesOf(bloc).map((s) => s.id), ['a']);
        expect(bloc.state.canRedo, isTrue);
      },
    );
  });

  group('NoteEditorBloc selection', () {
    blocTest<NoteEditorBloc, NoteEditorState>(
      'selection change carries no op (not undoable)',
      build: _bloc,
      act: (bloc) => bloc
        ..add(EditorStrokeCommitted(_stroke('a'), tool: EditorTool.pen))
        ..add(const EditorSelectionChanged({'a'})),
      verify: (bloc) {
        expect(bloc.state.selectedStrokeIds, {'a'});
        // Only the stroke commit is undoable; selecting added no op.
        expect(bloc.state.revision, 1);
      },
    );

    blocTest<NoteEditorBloc, NoteEditorState>(
      'recolor applies to selection and undo restores old colors',
      build: _bloc,
      act: (bloc) => bloc
        ..add(EditorStrokeCommitted(_stroke('a'), tool: EditorTool.pen))
        ..add(const EditorSelectionChanged({'a'}))
        ..add(const EditorSelectionRecolored(Color(0xFFB02A2D)))
        ..add(const EditorUndoRequested()),
      verify: (bloc) {
        expect(_strokesOf(bloc).single.color, const Color(0xFF161C1E));
      },
    );

    blocTest<NoteEditorBloc, NoteEditorState>(
      'selection transform replaces strokes and keeps them selected',
      build: _bloc,
      act: (bloc) {
        final before = _stroke('a');
        final after = Stroke(
          id: 'a',
          color: before.color,
          baseWidth: before.baseWidth,
          points: [
            for (final p in before.points)
              StrokePoint(
                  x: p.x + 50,
                  y: p.y,
                  pressure: p.pressure,
                  timestampMs: p.timestampMs),
          ],
        );
        bloc
          ..add(EditorStrokeCommitted(before, tool: EditorTool.pen))
          ..add(const EditorSelectionChanged({'a'}))
          ..add(EditorSelectionTransformed([before], [after]));
      },
      verify: (bloc) {
        expect(_strokesOf(bloc).single.points.first.x, 50);
        expect(bloc.state.selectedStrokeIds, {'a'});
      },
    );

    blocTest<NoteEditorBloc, NoteEditorState>(
      'delete selection removes the strokes',
      build: _bloc,
      act: (bloc) => bloc
        ..add(EditorStrokeCommitted(_stroke('a'), tool: EditorTool.pen))
        ..add(EditorStrokeCommitted(_stroke('b'), tool: EditorTool.pen))
        ..add(const EditorSelectionChanged({'a'}))
        ..add(const EditorSelectionDeleted()),
      verify: (bloc) {
        expect(_strokesOf(bloc).map((s) => s.id), ['b']);
        expect(bloc.state.hasSelection, isFalse);
      },
    );
  });

  group('NoteEditorBloc pages', () {
    blocTest<NoteEditorBloc, NoteEditorState>(
      'add page inserts after current and navigates to it',
      build: _bloc,
      act: (bloc) => bloc.add(const EditorPageAdded()),
      verify: (bloc) {
        expect(bloc.state.document!.pages.length, 2);
        expect(bloc.state.pageIndex, 1);
      },
    );

    blocTest<NoteEditorBloc, NoteEditorState>(
      'template change is undoable',
      build: _bloc,
      act: (bloc) => bloc
        ..add(const EditorTemplateChanged(PaperTemplate.grid))
        ..add(const EditorUndoRequested()),
      verify: (bloc) {
        expect(bloc.state.currentPage!.spec.template, PaperTemplate.blank);
        expect(bloc.state.canRedo, isTrue);
      },
    );

    blocTest<NoteEditorBloc, NoteEditorState>(
      'rotation cycles back to zero after four turns',
      build: _bloc,
      act: (bloc) {
        for (var i = 0; i < 4; i++) {
          bloc.add(const EditorPageRotated());
        }
      },
      verify: (bloc) {
        expect(bloc.state.currentPage!.spec.rotation, 0);
      },
    );
  });

  group('NoteEditorBloc images', () {
    const image = ImageObject(
        id: 'img1', assetPath: 'x.png', x: 10, y: 10, width: 100, height: 80);

    blocTest<NoteEditorBloc, NoteEditorState>(
      'added image is selected and undoable',
      build: _bloc,
      act: (bloc) => bloc.add(const EditorImageAdded(image)),
      verify: (bloc) {
        expect(bloc.state.currentPage!.images.single.id, 'img1');
        expect(bloc.state.selectedImageId, 'img1');
        expect(bloc.state.canUndo, isTrue);
      },
    );

    blocTest<NoteEditorBloc, NoteEditorState>(
      'image transform updates geometry; undo restores it',
      build: _bloc,
      act: (bloc) => bloc
        ..add(const EditorImageAdded(image))
        ..add(EditorImageTransformed(
            image, image.withRect(const Rect.fromLTWH(50, 50, 200, 160))))
        ..add(const EditorUndoRequested()),
      verify: (bloc) {
        expect(bloc.state.currentPage!.images.single.x, 10);
      },
    );

    blocTest<NoteEditorBloc, NoteEditorState>(
      'deleting a selected image removes it',
      build: _bloc,
      act: (bloc) => bloc
        ..add(const EditorImageAdded(image))
        ..add(const EditorSelectionDeleted()),
      verify: (bloc) {
        expect(bloc.state.currentPage!.images, isEmpty);
      },
    );
  });

  group('ToolbarCubit', () {
    blocTest<ToolbarCubit, ToolbarState>(
      'tool selection',
      build: ToolbarCubit.new,
      act: (cubit) => cubit.selectTool(EditorTool.lasso),
      verify: (cubit) => expect(cubit.state.tool, EditorTool.lasso),
    );

    blocTest<ToolbarCubit, ToolbarState>(
      'custom color is reported as custom',
      build: ToolbarCubit.new,
      act: (cubit) => cubit.selectColor(const Color(0xFF123456)),
      verify: (cubit) {
        expect(cubit.state.color, const Color(0xFF123456));
        expect(cubit.state.isCustomColor, isTrue);
      },
    );

    blocTest<ToolbarCubit, ToolbarState>(
      'eraser settings update and clamp',
      build: ToolbarCubit.new,
      act: (cubit) => cubit
        ..setEraserMode(EraserMode.area)
        ..setEraserRadius(500),
      verify: (cubit) {
        expect(cubit.state.eraserMode, EraserMode.area);
        expect(cubit.state.eraserRadius, lessThanOrEqualTo(60));
      },
    );

    blocTest<ToolbarCubit, ToolbarState>(
      'out-of-range width index is ignored',
      build: ToolbarCubit.new,
      act: (cubit) => cubit.selectWidth(99),
      expect: () => const <ToolbarState>[],
    );
  });
}
