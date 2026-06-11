import 'package:drift/drift.dart';

part 'app_database.g.dart';

class Folders extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get parentId => text().nullable()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

class Notes extends Table {
  TextColumn get id => text()();
  TextColumn get title => text()();
  TextColumn get folderId => text().nullable()();

  /// 'note' | 'whiteboard'
  TextColumn get kind => text().withDefault(const Constant('note'))();
  TextColumn get thumbnailPath => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Single-row key-value store: last open route, preferences.
class AppState extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}

@DriftDatabase(tables: [Folders, Notes, AppState])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);

  @override
  int get schemaVersion => 1;

  // --- Folders ---

  Stream<List<Folder>> watchFolders() =>
      (select(folders)..orderBy([(f) => OrderingTerm.asc(f.sortOrder), (f) => OrderingTerm.asc(f.name)])).watch();

  Future<void> upsertFolder(Folder folder) =>
      into(folders).insertOnConflictUpdate(folder);

  Future<void> deleteFolderById(String id) =>
      (delete(folders)..where((f) => f.id.equals(id))).go();

  // --- Notes ---

  Stream<List<Note>> watchNotesIn(String? folderId) {
    final query = select(notes)
      ..where((n) =>
          folderId == null ? n.folderId.isNull() : n.folderId.equals(folderId))
      ..orderBy([(n) => OrderingTerm.desc(n.updatedAt)]);
    return query.watch();
  }

  Future<Note?> noteById(String id) =>
      (select(notes)..where((n) => n.id.equals(id))).getSingleOrNull();

  Future<void> upsertNote(Note note) => into(notes).insertOnConflictUpdate(note);

  Future<void> deleteNoteById(String id) =>
      (delete(notes)..where((n) => n.id.equals(id))).go();

  // --- App state ---

  Future<String?> stateValue(String key) async {
    final row = await (select(appState)..where((s) => s.key.equals(key)))
        .getSingleOrNull();
    return row?.value;
  }

  Future<void> setStateValue(String key, String value) =>
      into(appState).insertOnConflictUpdate(
        AppStateData(key: key, value: value),
      );
}
