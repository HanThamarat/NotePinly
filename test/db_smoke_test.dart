import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notepinly/data/db/app_database.dart';

void main() {
  test('in-memory database round-trips a note row', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    final now = DateTime.now();
    await db.upsertNote(Note(
      id: 'n1',
      title: 'Untitled note',
      folderId: null,
      kind: 'note',
      thumbnailPath: null,
      createdAt: now,
      updatedAt: now,
    ));

    final note = await db.noteById('n1');
    expect(note?.title, 'Untitled note');
  });
}
