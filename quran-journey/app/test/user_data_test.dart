import 'package:flutter_test/flutter_test.dart';
import 'package:quran_journey/data/user_db.dart';
import 'package:quran_journey/domain/models.dart';
import 'package:quran_journey/domain/progress.dart';

import 'helpers.dart';

void main() {
  late UserDb db;
  setUp(() async => db = await openMemoryUserDb());
  tearDown(() async => db.db.close());

  test('notes: create, edit, delete (tombstone), study lookup', () async {
    final n = await db.saveNote(studyStart: 1, studyEnd: 4, text: 'First');
    expect((await db.notesForStudy(1, 4)).single.text, 'First');
    await db.saveNote(id: n.id, studyStart: 1, studyEnd: 4, text: 'Edited');
    expect((await db.notesForStudy(1, 4)).single.text, 'Edited');
    expect(await db.notesForStudy(5, 7), isEmpty);
    await db.deleteNote(n.id);
    expect(await db.notesForStudy(1, 4), isEmpty);
    final changes = await db.unsyncedChanges();
    expect(changes.single['deleted'], isTrue, reason: 'deletion must sync as a tombstone');
  });

  test('bookmarks: add is idempotent, remove works, types kept apart', () async {
    final a = await db.addBookmark(BookmarkType.verse, 2, 2, label: '1:2');
    final b = await db.addBookmark(BookmarkType.verse, 2, 2, label: '1:2');
    expect(a.id, b.id);
    await db.addBookmark(BookmarkType.study, 1, 4);
    expect((await db.bookmarks()).length, 2);
    await db.removeBookmark(a.id);
    final left = await db.bookmarks();
    expect(left.single.type, BookmarkType.study);
    expect(await db.findBookmark(BookmarkType.verse, 2, 2), isNull);
  });

  test('progress persists and is journey-scoped', () async {
    await db.addCompletion(Completion(id: newId(), startId: 1, endId: 4, completedAt: DateTime(2026, 1, 1)));
    await db.addCompletion(Completion(id: newId(), startId: 1, endId: 4, completedAt: DateTime(2026, 2, 1), journey: 2));
    expect((await db.completions(journey: 1)).length, 1);
    expect((await db.completions(journey: 2)).length, 1);
  });

  test('sync: markSynced only clears rows unchanged since sending', () async {
    final n = await db.saveNote(studyStart: 1, studyEnd: 4, text: 'v1');
    final sent = await db.unsyncedChanges();
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await db.saveNote(id: n.id, studyStart: 1, studyEnd: 4, text: 'v2 (edited during sync)');
    await db.markSynced(sent);
    final again = await db.unsyncedChanges();
    expect(again.single['data']['text'], 'v2 (edited during sync)');
  });

  test('sync: remote changes never overwrite unsynced local note text', () async {
    final n = await db.saveNote(studyStart: 1, studyEnd: 4, text: 'local words');
    await db.applyRemote({
      'kind': 'note',
      'id': n.id,
      'updated_at': DateTime.now().add(const Duration(hours: 1)).toUtc().toIso8601String(),
      'deleted': false,
      'data': {'study_start': 1, 'study_end': 4, 'text': 'server words', 'created_at': DateTime.now().toUtc().toIso8601String()},
    });
    expect((await db.notesForStudy(1, 4)).single.text, 'local words');
  });

  test('sync: remote records are applied (new note, conflict copy, bookmark tombstone)', () async {
    final now = DateTime.now().toUtc().toIso8601String();
    await db.applyRemote({
      'kind': 'note', 'id': 'n1', 'updated_at': now, 'deleted': false,
      'data': {'study_start': 5, 'study_end': 7, 'text': 'from phone', 'created_at': now, 'conflict_of': 'n0'},
    });
    final notes = await db.notesForStudy(5, 7);
    expect(notes.single.text, 'from phone');
    expect(notes.single.conflictOf, 'n0');
    final bm = await db.addBookmark(BookmarkType.verse, 9, 9);
    await db.markSynced(await db.unsyncedChanges());
    await db.applyRemote({
      'kind': 'bookmark', 'id': bm.id, 'updated_at': DateTime.now().add(const Duration(minutes: 1)).toUtc().toIso8601String(),
      'deleted': true, 'data': {'type': 'verse', 'verse_start': 9, 'verse_end': 9},
    });
    expect(await db.bookmarks(), isEmpty);
    await db.applyRemote({
      'kind': 'progress', 'id': 'p1', 'updated_at': now, 'deleted': false,
      'data': {'verse_start': 1, 'verse_end': 4, 'completed_at': now, 'journey': 1},
    });
    expect((await db.completions(journey: 1)).single.endId, 4);
  });

  test('CMS content: only stored items are returned per verse range; removal works', () async {
    await db.upsertContent([
      {'id': 'c1', 'type': 'tafsir', 'surah': 1, 'start_ayah': 1, 'end_ayah': 2, 'status': 'published', 'body': 'x'},
      {'id': 'c2', 'type': 'context', 'surah': 2, 'start_ayah': 1, 'end_ayah': 5, 'status': 'published', 'body': 'y'},
    ], const []);
    expect((await db.contentFor(1, 1, 4)).single['id'], 'c1');
    expect(await db.contentFor(1, 5, 7), isEmpty);
    await db.upsertContent(const [], ['c1']);
    expect(await db.contentFor(1, 1, 4), isEmpty);
  });

  test('export and wipe', () async {
    await db.saveNote(studyStart: 1, studyEnd: 4, text: 'keep me');
    final e = await db.exportAll();
    expect((e['notes'] as List).length, 1);
    await db.wipeUserData();
    expect(await db.allNotes(), isEmpty);
  });

  test('ids are RFC 4122 v4 UUIDs', () {
    final id = newId();
    expect(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$').hasMatch(id), isTrue);
  });
}
