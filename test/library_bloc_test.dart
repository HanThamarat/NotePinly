import 'dart:io';

import 'package:bloc_test/bloc_test.dart';
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
    tempDir.deleteSync(recursive: true);
  });

  group('LibraryBloc', () {
    blocTest<LibraryBloc, LibraryState>(
      'starts watching and reaches ready with empty data',
      build: () => LibraryBloc(repository: repo),
      act: (bloc) => bloc.add(const LibraryStarted(null)),
      wait: const Duration(milliseconds: 50),
      verify: (bloc) {
        expect(bloc.state.status, LibraryStatus.ready);
        expect(bloc.state.notes, isEmpty);
        expect(bloc.state.folders, isEmpty);
      },
    );

    blocTest<LibraryBloc, LibraryState>(
      'creating a note surfaces it and requests navigation',
      build: () => LibraryBloc(repository: repo),
      act: (bloc) async {
        bloc.add(const LibraryStarted(null));
        await Future<void>.delayed(const Duration(milliseconds: 20));
        bloc.add(const LibraryNoteCreated(NoteKind.note));
      },
      wait: const Duration(milliseconds: 100),
      verify: (bloc) {
        expect(bloc.state.notes, hasLength(1));
      },
      expect: () => contains(
        isA<LibraryState>().having((s) => s.openNoteId, 'openNoteId', isNotNull),
      ),
    );

    blocTest<LibraryBloc, LibraryState>(
      'folder create / rename / delete round-trip',
      build: () => LibraryBloc(repository: repo),
      act: (bloc) async {
        bloc.add(const LibraryStarted(null));
        await Future<void>.delayed(const Duration(milliseconds: 20));
        bloc.add(const LibraryFolderCreated('School'));
        await Future<void>.delayed(const Duration(milliseconds: 50));
        final folder = bloc.state.folders.single;
        bloc.add(LibraryFolderRenamed(folder.id, 'University'));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      },
      wait: const Duration(milliseconds: 50),
      verify: (bloc) {
        expect(bloc.state.folders.single.name, 'University');
      },
    );

    blocTest<LibraryBloc, LibraryState>(
      'deleting a note removes it from the list',
      build: () => LibraryBloc(repository: repo),
      act: (bloc) async {
        bloc.add(const LibraryStarted(null));
        await Future<void>.delayed(const Duration(milliseconds: 20));
        bloc.add(const LibraryNoteCreated(NoteKind.note));
        await Future<void>.delayed(const Duration(milliseconds: 50));
        bloc.add(LibraryNoteDeleted(bloc.state.notes.single.id));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      },
      wait: const Duration(milliseconds: 50),
      verify: (bloc) => expect(bloc.state.notes, isEmpty),
    );

    blocTest<LibraryBloc, LibraryState>(
      'whiteboards are created with the whiteboard kind',
      build: () => LibraryBloc(repository: repo),
      act: (bloc) async {
        bloc.add(const LibraryStarted(null));
        await Future<void>.delayed(const Duration(milliseconds: 20));
        bloc.add(const LibraryNoteCreated(NoteKind.whiteboard));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      },
      wait: const Duration(milliseconds: 50),
      verify: (bloc) {
        expect(bloc.state.notes.single.kind, NoteKind.whiteboard);
      },
    );
  });
}
