import 'dart:io';

import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path_provider/path_provider.dart';

import 'app/router.dart';
import 'app/theme/app_theme.dart';
import 'data/db/app_database.dart';
import 'data/files/note_file_store.dart';
import 'data/pdf/pdfx_renderer.dart';
import 'data/repositories/library_repository_impl.dart';
import 'data/repositories/note_repository_impl.dart';
import 'domain/repositories/library_repository.dart';
import 'domain/repositories/note_repository.dart';
import 'domain/services/pdf_renderer.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final db = AppDatabase(driftDatabase(name: 'notepinly'));
  final documentsDir = await getApplicationDocumentsDirectory();
  final files = NoteFileStore(Directory('${documentsDir.path}/notepinly'));
  final pdfRenderer = PdfxRenderer();
  final library =
      LibraryRepositoryImpl(db: db, files: files, pdfRenderer: pdfRenderer);
  final notes = NoteRepositoryImpl(db: db, files: files);

  // Reopen where the user left off (ARCHITECTURE.md: navigation restore).
  final lastRoute = await library.lastRoute() ?? '/';

  runApp(NotepinlyApp(
    library: library,
    notes: notes,
    pdfRenderer: pdfRenderer,
    initialLocation: lastRoute,
  ));
}

class NotepinlyApp extends StatefulWidget {
  const NotepinlyApp({
    super.key,
    required this.library,
    required this.notes,
    required this.pdfRenderer,
    this.initialLocation = '/',
  });

  final LibraryRepository library;
  final NoteRepository notes;
  final PdfRenderer pdfRenderer;
  final String initialLocation;

  @override
  State<NotepinlyApp> createState() => _NotepinlyAppState();
}

class _NotepinlyAppState extends State<NotepinlyApp> {
  // Router lives in state so hot reload never drops the navigation stack.
  late final _router = buildRouter(
    library: widget.library,
    initialLocation: widget.initialLocation,
  );

  @override
  Widget build(BuildContext context) {
    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider<LibraryRepository>.value(value: widget.library),
        RepositoryProvider<NoteRepository>.value(value: widget.notes),
        RepositoryProvider<PdfRenderer>.value(value: widget.pdfRenderer),
      ],
      child: MaterialApp.router(
        title: 'NotePinly',
        theme: buildAppTheme(),
        routerConfig: _router,
        debugShowCheckedModeBanner: false,
      ),
    );
  }
}
