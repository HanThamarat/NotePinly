// Visual-verification captures, not regression goldens.
//
// Run with:
//   flutter test test/preview/editor_preview_test.dart --update-goldens
//
// Renders the app at tablet landscape size with the real Roboto +
// MaterialIcons fonts and writes PNGs to test/preview/goldens/ for
// design review. Strokes are deterministic (event-timestamp driven).
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notepinly/app/theme/app_theme.dart';
import 'package:notepinly/data/db/app_database.dart';
import 'package:notepinly/data/files/note_file_store.dart';
import 'package:notepinly/data/repositories/library_repository_impl.dart';
import 'package:notepinly/data/repositories/note_repository_impl.dart';
import 'package:notepinly/domain/entities/folder.dart' as domain;
import 'package:notepinly/domain/entities/note_document.dart';
import 'package:notepinly/domain/repositories/library_repository.dart';
import 'package:notepinly/domain/repositories/note_repository.dart';
import 'package:notepinly/presentation/editor/canvas/ink_canvas.dart';
import 'package:notepinly/presentation/editor/note_editor_screen.dart';
import 'package:notepinly/presentation/editor/widgets/page_chip.dart';
import 'package:notepinly/presentation/library/library_screen.dart';

/// The SDK's bundled fonts, wherever Flutter is installed (local machines
/// and CI runners differ).
String _materialFontsDir() {
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root != null && root.isNotEmpty) {
    return '$root/bin/cache/artifacts/material_fonts';
  }
  // `flutter test` runs on the SDK's own Dart:
  // <flutter>/bin/cache/dart-sdk/bin/dart(.exe)
  final cache = File(Platform.resolvedExecutable).parent.parent.parent;
  return '${cache.path}/artifacts/material_fonts';
}

Future<void> _loadRealFonts() async {
  final dir = _materialFontsDir();
  ByteData read(String file) =>
      ByteData.view(File('$dir/$file').readAsBytesSync().buffer);

  final roboto = FontLoader('Roboto');
  for (final file in [
    'roboto-regular.ttf',
    'roboto-medium.ttf',
    'roboto-bold.ttf',
  ]) {
    roboto.addFont(Future.value(read(file)));
  }
  final icons = FontLoader('MaterialIcons')
    ..addFont(Future.value(read('materialicons-regular.otf')));
  await Future.wait([roboto.load(), icons.load()]);
}

ThemeData _previewTheme() {
  final theme = buildAppTheme();
  return theme.copyWith(
      textTheme: theme.textTheme.apply(fontFamily: 'Roboto'));
}

/// testWidgets with real shadows; the flag must be restored before the
/// body ends or the binding's invariant check fails.
void preview(String description, Future<void> Function(WidgetTester) body) {
  testWidgets(description, (tester) async {
    debugDisableShadows = false;
    try {
      await body(tester);
    } finally {
      debugDisableShadows = true;
    }
  });
}

void main() {
  setUpAll(_loadRealFonts);

  late Directory tempDir;
  late AppDatabase db;
  late LibraryRepositoryImpl library;
  late NoteRepositoryImpl notes;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('notepinly_preview');
    db = AppDatabase(NativeDatabase.memory());
    final files = NoteFileStore(tempDir);
    library = LibraryRepositoryImpl(db: db, files: files);
    notes = NoteRepositoryImpl(db: db, files: files);
  });

  tearDown(() async {
    await db.close();
    // Unawaited journal writes from the editor bloc may still hold file
    // handles for a beat; a leaked temp dir beats a flaky suite.
    await Future<void>.delayed(const Duration(milliseconds: 100));
    try {
      tempDir.deleteSync(recursive: true);
    } on FileSystemException {
      // Leave it for the OS temp cleaner.
    }
  });

  Widget app(Widget home) => MultiRepositoryProvider(
        providers: [
          RepositoryProvider<LibraryRepository>.value(value: library),
          RepositoryProvider<NoteRepository>.value(value: notes),
        ],
        child: MaterialApp(
          theme: _previewTheme(),
          debugShowCheckedModeBanner: false,
          home: home,
        ),
      );

  Future<void> pumpEditor(WidgetTester tester, {String noteId = 'n1'}) async {
    tester.view.physicalSize = const Size(1366, 1024);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app(NoteEditorScreen(noteId: noteId)));
    // The bloc's load does real file IO; interleave real-async windows
    // with pumps until the canvas is up — never capture the spinner.
    for (var i = 0;
        i < 20 && find.byType(InkCanvas).evaluate().isEmpty;
        i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 25)));
      await tester.pump();
    }
    await tester.pump();
    expect(find.byType(InkCanvas), findsOneWidget,
        reason: 'editor must finish loading before capture');
  }

  Future<void> draw(
    WidgetTester tester,
    Offset start,
    List<Offset> deltas, {
    PointerDeviceKind kind = PointerDeviceKind.stylus,
    bool lift = true,
  }) async {
    final gesture = await tester.startGesture(start, kind: kind);
    for (final d in deltas) {
      await gesture.moveBy(d);
      await tester.pump(const Duration(milliseconds: 8));
    }
    if (lift) {
      await gesture.up();
      await tester.pump();
    }
  }

  Future<void> writeSample(WidgetTester tester) async {
    const base = Offset(420, 360);
    for (var k = 0; k < 3; k++) {
      await draw(tester, base + Offset(k * 130.0, 0), [
        for (var i = 1; i <= 24; i++)
          Offset(
            3.5 - (i % 12) * (i < 12 ? 0.1 : -0.1),
            (i < 12 ? -1 : 1) * (6 - (i % 12) * 0.5),
          ),
      ]);
    }
    await draw(tester, base + const Offset(-20, 90), [
      for (var i = 0; i < 30; i++) Offset(14, i < 15 ? -0.8 : 0.8),
    ]);
  }

  Future<void> capture(WidgetTester tester, String name) => expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/$name.png'),
      );

  preview('editor — ink and toolbar', (tester) async {
    await pumpEditor(tester);
    await writeSample(tester);
    await capture(tester, 'editor_with_ink');
  });

  preview('editor — eraser mid-drag with cursor indicator', (tester) async {
    await pumpEditor(tester);
    await writeSample(tester);
    await tester.tap(find.bySemanticsLabel('Eraser'));
    await tester.pump();
    final gesture = await tester.startGesture(
      const Offset(420, 430),
      kind: PointerDeviceKind.stylus,
    );
    for (var i = 0; i < 12; i++) {
      await gesture.moveBy(const Offset(18, 1));
      await tester.pump(const Duration(milliseconds: 8));
    }
    await capture(tester, 'editor_eraser_drag');
    await gesture.up();
    await tester.pump();
  });

  preview('editor — lasso selection with action bar', (tester) async {
    await pumpEditor(tester);
    await writeSample(tester);
    await tester.tap(find.byIcon(Icons.highlight_alt_rounded));
    await tester.pump();
    await draw(tester, const Offset(340, 260), [
      for (var i = 0; i < 10; i++) const Offset(48, 0),
      for (var i = 0; i < 10; i++) const Offset(0, 26),
      for (var i = 0; i < 10; i++) const Offset(-48, 0),
      for (var i = 0; i < 10; i++) const Offset(0, -26),
    ]);
    await capture(tester, 'editor_lasso_selection');
  });

  preview('editor — grid paper via template sheet', (tester) async {
    await pumpEditor(tester);
    await writeSample(tester);
    await tester.tap(find.byIcon(Icons.more_horiz_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Paper style…'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Grid'));
    await tester.pumpAndSettle();
    await capture(tester, 'editor_grid_template');
  });

  preview('editor — page rotated 90 degrees', (tester) async {
    await pumpEditor(tester);
    await writeSample(tester);
    await tester.tap(find.byIcon(Icons.more_horiz_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rotate page'));
    await tester.pumpAndSettle();
    await capture(tester, 'editor_rotated');
  });

  preview('editor — second page added', (tester) async {
    await pumpEditor(tester);
    await writeSample(tester);
    await tester.tap(find.descendant(
      of: find.byType(PageChip),
      matching: find.byIcon(Icons.add_rounded),
    ));
    await tester.pump();
    // Let the page-turn transition finish before capturing.
    await tester.pumpAndSettle();
    await capture(tester, 'editor_second_page');
  });

  preview('editor — continuous scroll across the page boundary', (tester) async {
    await pumpEditor(tester);
    await writeSample(tester);
    await tester.tap(find.descendant(
      of: find.byType(PageChip),
      matching: find.byIcon(Icons.add_rounded),
    ));
    await tester.pump();
    await tester.pumpAndSettle();
    // Wheel-scroll back up: both pages share the viewport and the
    // current-page indicator follows the page at the center.
    final wheel = TestPointer(7, PointerDeviceKind.mouse);
    wheel.hover(const Offset(683, 500));
    await tester.sendEventToBinding(wheel.scroll(const Offset(0, -800)));
    await tester.pump();
    await tester.pump();
    expect(find.text('1 of 2'), findsOneWidget);
    await capture(tester, 'editor_continuous_scroll');
  });

  preview('whiteboard — unbounded canvas at 100%', (tester) async {
    // Real file IO must run outside the FakeAsync test zone.
    final meta = await tester.runAsync(
        () => library.createNote(kind: NoteKind.whiteboard));
    await pumpEditor(tester, noteId: meta!.id);
    await tester.pump();
    await draw(tester, const Offset(500, 400), [
      for (var i = 0; i < 24; i++)
        Offset(10, (i < 12 ? -1 : 1) * (6 - (i % 12) * 0.5)),
    ]);
    await capture(tester, 'whiteboard');
  });

  // Stubbed repository: seeding drift inside a widget test wedges its
  // stream teardown. The real persistence path is covered by
  // persistence_test and library_bloc_test.
  Future<void> pumpLibrary(WidgetTester tester, {bool empty = false}) async {
    tester.view.physicalSize = const Size(1366, 1024);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MultiRepositoryProvider(
      providers: [
        RepositoryProvider<LibraryRepository>.value(
            value: _StubLibraryRepository(empty: empty)),
        RepositoryProvider<NoteRepository>.value(value: notes),
      ],
      child: MaterialApp(
        theme: _previewTheme(),
        debugShowCheckedModeBanner: false,
        home: const LibraryScreen(),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  preview('library — populated with folders and notes', (tester) async {
    await pumpLibrary(tester);
    // The whole tree must render: School with Math nested, Work at root.
    expect(find.text('School'), findsOneWidget);
    expect(find.text('Math'), findsOneWidget);
    expect(find.text('Work'), findsOneWidget);
    expect(find.text('Untitled note'), findsNWidgets(2));
    expect(find.text('Untitled whiteboard'), findsOneWidget);
    await capture(tester, 'library_populated');
  });

  preview('library — first run empty state', (tester) async {
    await pumpLibrary(tester, empty: true);
    expect(find.text('Nothing here yet'), findsOneWidget);
    await capture(tester, 'library_first_run');
  });

  // Collapse state is session-global, so this runs after the populated
  // capture (which expects the tree expanded).
  preview('library — subfolders collapsed', (tester) async {
    await pumpLibrary(tester);
    await tester.tap(find.bySemanticsLabel('Collapse subfolders'));
    await tester.pumpAndSettle();
    expect(find.text('Math'), findsNothing);
    await capture(tester, 'library_sidebar_collapsed');
    // Re-expand so the module-level state doesn't leak into other runs.
    await tester.tap(find.bySemanticsLabel('Expand subfolders'));
    await tester.pumpAndSettle();
  });

  preview('editor — overscroll page-turn hint', (tester) async {
    await pumpEditor(tester);
    await writeSample(tester);
    // Two-finger upward drag at the page edge charges the page-turn gauge;
    // on a single-page note the hint reads "New page".
    final a = await tester.startGesture(const Offset(520, 620),
        kind: PointerDeviceKind.touch);
    final b = await tester.startGesture(const Offset(660, 620),
        kind: PointerDeviceKind.touch);
    for (var i = 0; i < 10; i++) {
      await a.moveBy(const Offset(0, -7));
      await b.moveBy(const Offset(0, -7));
      await tester.pump(const Duration(milliseconds: 8));
    }
    await tester.pump();
    expect(find.text('New page'), findsOneWidget);
    await capture(tester, 'editor_page_turn_hint');
    await a.up();
    await b.up();
    await tester.pump();
  });

  preview('editor — width popover open', (tester) async {
    await pumpEditor(tester);
    await writeSample(tester);
    await tester.tap(find.bySemanticsLabel('Stroke width'));
    await tester.pumpAndSettle();
    await capture(tester, 'editor_width_popover');
  });
}

/// In-memory library data for the library captures — no drift, no IO.
class _StubLibraryRepository implements LibraryRepository {
  _StubLibraryRepository({this.empty = false});

  final bool empty;
  final _now = DateTime.now();

  @override
  Stream<List<domain.Folder>> watchFolders() => Stream.value(empty
      ? const []
      : const [
          domain.Folder(id: 'f-school', name: 'School'),
          domain.Folder(id: 'f-math', name: 'Math', parentId: 'f-school'),
          domain.Folder(id: 'f-work', name: 'Work'),
        ]);

  @override
  Stream<List<domain.NoteMeta>> watchNotes(String? folderId) => Stream.value(
      empty
          ? const []
          : [
              domain.NoteMeta(
                  id: 'n1', title: 'Untitled note', updatedAt: _now),
              domain.NoteMeta(
                  id: 'n2', title: 'Untitled note', updatedAt: _now),
              domain.NoteMeta(
                id: 'wb1',
                title: 'Untitled whiteboard',
                kind: NoteKind.whiteboard,
                updatedAt: _now,
              ),
            ]);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not stubbed');
}
