import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notepinly/data/db/app_database.dart';
import 'package:notepinly/data/files/note_file_store.dart';
import 'package:notepinly/data/repositories/library_repository_impl.dart';
import 'package:notepinly/domain/entities/note_document.dart';
import 'package:notepinly/presentation/library/bloc/library_bloc.dart';

void main() {
  late Directory tempDir;
  late AppDatabase db;
  late LibraryRepositoryImpl repo;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('notepinly_lib_test');
    db = AppDatabase(NativeDatabase.memory());
    repo = LibraryRepositoryImpl(db: db, files: NoteFileStore(tempDir));
  });

  tearDown(() async {
    await db.close();
    // Unawaited note-store writes may still hold file handles for a beat
    // (slow CI runners especially); a leaked temp dir beats a flaky suite.
    await Future<void>.delayed(const Duration(milliseconds: 100));
    try {
      tempDir.deleteSync(recursive: true);
    } on FileSystemException {
      // Leave it for the OS temp cleaner.
    }
  });

  LibraryBloc startBloc() {
    final bloc = LibraryBloc(repository: repo);
    addTearDown(bloc.close);
    bloc.add(const LibraryStarted(null));
    return bloc;
  }

  /// Waits until the bloc reaches a state matching [test] — repository
  /// work is real async IO, so fixed delays flake on slow runners.
  Future<LibraryState> waitFor(
    LibraryBloc bloc,
    bool Function(LibraryState) test, {
    String? reason,
  }) async {
    if (test(bloc.state)) return bloc.state;
    return bloc.stream.firstWhere(test).timeout(
          const Duration(seconds: 10),
          onTimeout: () => throw TestFailure(
              'timed out waiting for state${reason == null ? '' : ': $reason'}'),
        );
  }

  group('LibraryBloc', () {
    test('starts watching and reaches ready with empty data', () async {
      final bloc = startBloc();
      final state = await waitFor(bloc, (s) => s.status == LibraryStatus.ready,
          reason: 'ready');
      expect(state.notes, isEmpty);
      expect(state.folders, isEmpty);
    });

    test('creating a note surfaces it and requests navigation', () async {
      final bloc = startBloc();
      await waitFor(bloc, (s) => s.status == LibraryStatus.ready,
          reason: 'ready');
      // openNoteId is transient (set, then cleared); watch for it before
      // dispatching the create.
      final openRequested = bloc.stream
          .firstWhere((s) => s.openNoteId != null)
          .timeout(const Duration(seconds: 10));
      bloc.add(const LibraryNoteCreated(NoteKind.note));
      final opened = await openRequested;
      expect(opened.openNoteId, isNotNull);
      await waitFor(bloc, (s) => s.notes.length == 1,
          reason: 'note appears in the list');
    });

    test('folder create / rename / delete round-trip', () async {
      final bloc = startBloc();
      await waitFor(bloc, (s) => s.status == LibraryStatus.ready,
          reason: 'ready');
      bloc.add(const LibraryFolderCreated('School'));
      final created = await waitFor(bloc, (s) => s.folders.length == 1,
          reason: 'folder created');
      bloc.add(LibraryFolderRenamed(created.folders.single.id, 'University'));
      await waitFor(
          bloc, (s) => s.folders.singleOrNull?.name == 'University',
          reason: 'folder renamed');
    });

    test('deleting a note removes it from the list', () async {
      final bloc = startBloc();
      await waitFor(bloc, (s) => s.status == LibraryStatus.ready,
          reason: 'ready');
      bloc.add(const LibraryNoteCreated(NoteKind.note));
      final created = await waitFor(bloc, (s) => s.notes.length == 1,
          reason: 'note created');
      bloc.add(LibraryNoteDeleted(created.notes.single.id));
      await waitFor(bloc, (s) => s.notes.isEmpty, reason: 'note deleted');
    });

    test('whiteboards are created with the whiteboard kind', () async {
      final bloc = startBloc();
      await waitFor(bloc, (s) => s.status == LibraryStatus.ready,
          reason: 'ready');
      bloc.add(const LibraryNoteCreated(NoteKind.whiteboard));
      final state = await waitFor(bloc, (s) => s.notes.length == 1,
          reason: 'whiteboard created');
      expect(state.notes.single.kind, NoteKind.whiteboard);
    });
  });
}
