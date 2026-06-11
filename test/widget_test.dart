import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notepinly/presentation/editor/canvas/ink_canvas.dart';
import 'package:notepinly/presentation/editor/note_editor_screen.dart';
import 'package:notepinly/presentation/editor/widgets/page_chip.dart';
import 'package:notepinly/presentation/editor/widgets/selection_bar.dart';

void main() {
  Future<void> pumpEditor(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const MaterialApp(home: NoteEditorScreen(noteId: 'test-note')),
    );
    // Bloc loads a blank document asynchronously (no repository in tests).
    await tester.pump();
    await tester.pump();
  }

  Future<void> drawStroke(
    WidgetTester tester, {
    PointerDeviceKind kind = PointerDeviceKind.stylus,
    Offset? from,
    Offset delta = const Offset(8, 4),
    int steps = 10,
  }) async {
    final start = from ?? tester.getCenter(find.byType(InkCanvas));
    final gesture = await tester.startGesture(start, kind: kind);
    for (var i = 1; i <= steps; i++) {
      await gesture.moveBy(delta);
      await tester.pump(const Duration(milliseconds: 8));
    }
    await gesture.up();
    await tester.pump();
  }

  IconButton buttonOf(WidgetTester tester, IconData icon) =>
      tester.widget<IconButton>(find.widgetWithIcon(IconButton, icon));

  group('NoteEditorScreen', () {
    testWidgets('shows the full toolbar with every tool live', (tester) async {
      await pumpEditor(tester);

      expect(find.text('Untitled note'), findsOneWidget);
      expect(find.byIcon(Icons.edit_rounded), findsOneWidget);
      expect(find.bySemanticsLabel('Eraser'), findsOneWidget);
      expect(find.byIcon(Icons.highlight_alt_rounded), findsOneWidget);
      expect(find.byIcon(Icons.image_outlined), findsOneWidget);
      expect(find.bySemanticsLabel('Custom color'), findsOneWidget);
      expect(find.byType(PageChip), findsOneWidget);

      // No save affordance anywhere (PRODUCT.md principle 3).
      expect(find.byIcon(Icons.save), findsNothing);
      expect(find.textContaining('Save'), findsNothing);
    });

    testWidgets('a stylus stroke commits and enables undo', (tester) async {
      await pumpEditor(tester);
      await drawStroke(tester);
      expect(buttonOf(tester, Icons.undo_rounded).onPressed, isNotNull);
    });

    testWidgets('after stylus contact, fingers no longer draw',
        (tester) async {
      await pumpEditor(tester);
      await drawStroke(tester); // stylus flips the session
      await drawStroke(tester, kind: PointerDeviceKind.touch);
      await tester.tap(find.widgetWithIcon(IconButton, Icons.undo_rounded));
      await tester.pump();
      // Only the stylus stroke existed, so undo is exhausted.
      expect(buttonOf(tester, Icons.undo_rounded).onPressed, isNull);
    });

    testWidgets('eraser drag removes the stroke as one undoable op',
        (tester) async {
      await pumpEditor(tester);
      final center = tester.getCenter(find.byType(InkCanvas));
      await drawStroke(tester, from: center);

      await tester.tap(find.bySemanticsLabel('Eraser'));
      await tester.pump();
      // Drag the eraser across the ink.
      await drawStroke(tester, from: center, delta: const Offset(10, 5));

      // Stroke gone: undo (one op) restores it, then undo again removes
      // the original draw.
      await tester.tap(find.widgetWithIcon(IconButton, Icons.undo_rounded));
      await tester.pump();
      expect(buttonOf(tester, Icons.undo_rounded).onPressed, isNotNull);
      await tester.tap(find.widgetWithIcon(IconButton, Icons.undo_rounded));
      await tester.pump();
      expect(buttonOf(tester, Icons.undo_rounded).onPressed, isNull);
    });

    testWidgets('lasso loop selects the stroke and shows the selection bar',
        (tester) async {
      await pumpEditor(tester);
      final center = tester.getCenter(find.byType(InkCanvas));
      await drawStroke(tester, from: center, steps: 6);

      await tester.tap(find.byIcon(Icons.highlight_alt_rounded));
      await tester.pump();

      // Draw a loop around the ink.
      final gesture = await tester.startGesture(
        center - const Offset(80, 80),
        kind: PointerDeviceKind.stylus,
      );
      for (final d in const [
        Offset(220, 0),
        Offset(0, 200),
        Offset(-220, 0),
        Offset(0, -200),
      ]) {
        for (var i = 0; i < 8; i++) {
          await gesture.moveBy(d / 8);
          await tester.pump(const Duration(milliseconds: 8));
        }
      }
      await gesture.up();
      await tester.pump();

      expect(find.byType(SelectionBar), findsOneWidget);
      expect(find.textContaining('selected'), findsOneWidget);

      // Delete via the bar.
      await tester.tap(find.byIcon(Icons.delete_outline_rounded));
      await tester.pump();
      expect(find.byType(SelectionBar), findsNothing);
    });

    testWidgets('add page navigates to the new page', (tester) async {
      await pumpEditor(tester);
      expect(find.text('1 of 1'), findsOneWidget);
      await tester.tap(find.descendant(
        of: find.byType(PageChip),
        matching: find.byIcon(Icons.add_rounded),
      ));
      await tester.pump();
      // Page-turn and chip-label animations run; settle before asserting.
      await tester.pumpAndSettle();
      expect(find.text('2 of 2'), findsOneWidget);
    });

    testWidgets('width menu opens and shows the current preset',
        (tester) async {
      await pumpEditor(tester);
      await tester.tap(find.bySemanticsLabel('Stroke width'));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    });
  });
}
