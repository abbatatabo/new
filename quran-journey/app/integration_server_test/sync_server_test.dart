// Cross-system test: the app's real SyncService + UserDb against the real
// Node backend. Run with tools/run_server_integration.sh (starts a throwaway
// server and sets QJ_TEST_SERVER / QJ_TEST_ADMIN_*).
import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:quran_journey/data/user_db.dart';
import 'package:quran_journey/domain/models.dart';
import 'package:quran_journey/domain/progress.dart';
import 'package:quran_journey/services/sync_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

final base = Platform.environment['QJ_TEST_SERVER'] ?? '';

Future<UserDb> freshDb() async {
  sqfliteFfiInit();
  final dir = Directory.systemTemp.createTempSync('qj_sync_');
  return UserDb.open(path: '${dir.path}/u.db', factory: databaseFactoryFfiNoIsolate);
}

Future<Map<String, dynamic>> api(String method, String path, {String? token, Object? body}) async {
  final req = http.Request(method, Uri.parse('$base$path'))
    ..headers['Content-Type'] = 'application/json';
  if (token != null) req.headers['Authorization'] = 'Bearer $token';
  if (body != null) req.body = jsonEncode(body);
  final r = await http.Response.fromStream(await req.send());
  if (r.statusCode >= 400) throw Exception('$method $path -> ${r.statusCode} ${r.body}');
  return r.body.isEmpty ? {} : jsonDecode(r.body) as Map<String, dynamic>;
}

void main() {
  FlutterSecureStorage.setMockInitialValues({});

  test('two devices sync notes, bookmarks and progress; conflicting edits keep both', () async {
    final email = 'device-test-${DateTime.now().microsecondsSinceEpoch}@example.org';
    const pw = 'correct horse battery staple';
    final dbA = await freshDb(), dbB = await freshDb();
    final a = SyncService(dbA), b = SyncService(dbB);

    await a.authenticate(base, email, pw, register: true);
    final note = await dbA.saveNote(studyStart: 1, studyEnd: 4, text: 'Written on phone A');
    await dbA.addBookmark(BookmarkType.verse, 2, 2, label: 'Al-Faatiha 1:2');
    await dbA.addCompletion(Completion(id: newId(), startId: 1, endId: 4, completedAt: DateTime.now()));
    final r1 = await a.sync(base);
    expect(r1.error, isNull);
    expect(r1.pushed, 3);

    // Device B signs in with the same account and receives everything.
    // (B uses its own secure-storage key namespace via a fresh service.)
    await b.authenticate(base, email, pw, register: false);
    final r2 = await b.sync(base);
    expect(r2.error, isNull);
    expect((await dbB.notesForStudy(1, 4)).single.text, 'Written on phone A');
    expect((await dbB.bookmarks()).single.label, 'Al-Faatiha 1:2');
    expect((await dbB.completions(journey: 1)).single.endId, 4);

    // Both edit the same note offline; B syncs first, then A.
    await dbB.saveNote(id: note.id, studyStart: 1, studyEnd: 4, text: 'Edited on B');
    expect((await b.sync(base)).error, isNull);
    await dbA.saveNote(id: note.id, studyStart: 1, studyEnd: 4, text: 'Edited on A');
    final r3 = await a.sync(base);
    expect(r3.error, isNull);
    expect(r3.conflicts, 1);
    final notesA = (await dbA.notesForStudy(1, 4)).map((n) => n.text).toSet();
    expect(notesA, {'Edited on B', 'Edited on A'}, reason: 'user text is never discarded');

    // B receives A's conflict copy.
    await b.sync(base);
    expect((await dbB.notesForStudy(1, 4)).map((n) => n.text).toSet(), {'Edited on B', 'Edited on A'});

    // Deleting a bookmark on B removes it on A (tombstone).
    final bm = (await dbB.bookmarks()).single;
    await dbB.removeBookmark(bm.id);
    await b.sync(base);
    await a.sync(base);
    expect(await dbA.bookmarks(), isEmpty);
  });

  test('only published CMS content reaches the app; unpublishing removes it', () async {
    final login = await api('POST', '/api/auth/login', body: {
      'email': Platform.environment['QJ_TEST_ADMIN_EMAIL'],
      'password': Platform.environment['QJ_TEST_ADMIN_PASSWORD'],
    });
    final admin = login['token'] as String;
    final revEmail = 'reviewer-${DateTime.now().microsecondsSinceEpoch}@example.org';
    final rev = await api('POST', '/api/auth/register', body: {'email': revEmail, 'password': 'another long password'});
    await api('PUT', '/api/admin/users/${(rev['user'] as Map)['id']}/role', token: admin, body: {'role': 'reviewer'});
    final reviewer = (await api('POST', '/api/auth/login', body: {'email': revEmail, 'password': 'another long password'}))['token'] as String;

    final item = (await api('POST', '/api/admin/content', token: admin, body: {
      'type': 'context', 'category': 'editorial_summary', 'surah': 1, 'start_ayah': 1, 'end_ayah': 4,
      'title': 'Integration test item', 'body': 'Test body (temporary database).',
    }))['item'] as Map;
    final id = item['id'] as String;

    final db = await freshDb();
    final sync = SyncService(db);
    await sync.fetchPublishedContent(base);
    expect(await db.contentFor(1, 1, 4), isEmpty, reason: 'drafts never reach the app');

    await api('POST', '/api/admin/content/$id/status', token: admin, body: {'status': 'source_verified'});
    await expectLater(api('POST', '/api/admin/content/$id/status', token: admin, body: {'status': 'published'}), throwsException);
    await api('POST', '/api/admin/content/$id/status', token: reviewer, body: {'status': 'reviewed'});
    await api('POST', '/api/admin/content/$id/status', token: reviewer, body: {'status': 'approved'});
    await sync.fetchPublishedContent(base);
    expect(await db.contentFor(1, 1, 4), isEmpty, reason: 'approved is not yet published');

    await api('POST', '/api/admin/content/$id/status', token: admin, body: {'status': 'published'});
    await sync.fetchPublishedContent(base);
    final got = await db.contentFor(1, 1, 4);
    expect(got.single['id'], id);
    expect(got.single['category'], 'editorial_summary');

    await api('POST', '/api/admin/content/$id/status', token: admin, body: {'status': 'unpublished'});
    await sync.fetchPublishedContent(base);
    expect(await db.contentFor(1, 1, 4), isEmpty, reason: 'unpublished items are removed from devices');
  });
}
