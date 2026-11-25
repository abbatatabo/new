import 'dart:convert';
import 'dart:math';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../domain/models.dart';
import '../domain/progress.dart';

String newId() {
  final r = Random.secure();
  final b = List<int>.generate(16, (_) => r.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
}

/// Local, private user data. Everything here works offline; `synced = 0`
/// rows are pushed when an account + server are configured.
class UserDb {
  final Database db;
  UserDb(this.db);

  static const _version = 1;

  static Future<UserDb> open({String? path, DatabaseFactory? factory}) async {
    final dbPath = path ?? p.join((await getApplicationSupportDirectory()).path, 'user.db');
    final f = factory ?? databaseFactory;
    final db = await f.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(version: _version, onCreate: (db, v) => _create(db)),
    );
    return UserDb(db);
  }

  static Future<void> _create(Database db) async {
    await db.execute('''CREATE TABLE completions(
      id TEXT PRIMARY KEY, start_id INTEGER NOT NULL, end_id INTEGER NOT NULL,
      completed_at INTEGER NOT NULL, journey INTEGER NOT NULL DEFAULT 1,
      updated_at INTEGER NOT NULL, deleted INTEGER NOT NULL DEFAULT 0,
      synced INTEGER NOT NULL DEFAULT 0)''');
    await db.execute('''CREATE TABLE notes(
      id TEXT PRIMARY KEY, study_start INTEGER NOT NULL, study_end INTEGER NOT NULL,
      verse_id INTEGER, text TEXT NOT NULL, created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL, deleted INTEGER NOT NULL DEFAULT 0,
      synced INTEGER NOT NULL DEFAULT 0, server_updated_at INTEGER, conflict_of TEXT)''');
    await db.execute('''CREATE TABLE bookmarks(
      id TEXT PRIMARY KEY, type TEXT NOT NULL, verse_start INTEGER NOT NULL,
      verse_end INTEGER NOT NULL, ref_id TEXT, label TEXT, created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL, deleted INTEGER NOT NULL DEFAULT 0,
      synced INTEGER NOT NULL DEFAULT 0)''');
    await db.execute('CREATE TABLE cache(key TEXT PRIMARY KEY, value TEXT NOT NULL, fetched_at INTEGER NOT NULL)');
    await db.execute('''CREATE TABLE content_items(
      id TEXT PRIMARY KEY, type TEXT NOT NULL, surah INTEGER, start_ayah INTEGER,
      end_ayah INTEGER, json TEXT NOT NULL, updated_at TEXT)''');
    await db.execute('CREATE TABLE groupings(id TEXT PRIMARY KEY, json TEXT NOT NULL)');
    await db.execute('CREATE TABLE kv(key TEXT PRIMARY KEY, value TEXT)');
    await db.execute('CREATE INDEX idx_notes_study ON notes(study_start)');
    await db.execute('CREATE INDEX idx_content_surah ON content_items(surah)');
  }

  int _now() => DateTime.now().millisecondsSinceEpoch;

  // ---------------- progress ----------------
  Future<List<Completion>> completions({required int journey}) async {
    final rows = await db.query('completions', where: 'deleted = 0 AND journey = ?', whereArgs: [journey]);
    return rows
        .map((r) => Completion(
              id: r['id'] as String,
              startId: r['start_id'] as int,
              endId: r['end_id'] as int,
              completedAt: DateTime.fromMillisecondsSinceEpoch(r['completed_at'] as int),
              journey: r['journey'] as int,
            ))
        .toList();
  }

  Future<void> addCompletion(Completion c) async {
    await db.insert('completions', {
      'id': c.id,
      'start_id': c.startId,
      'end_id': c.endId,
      'completed_at': c.completedAt.millisecondsSinceEpoch,
      'journey': c.journey,
      'updated_at': _now(),
    });
  }

  Future<int> completedJourneys() async {
    final r = await db.rawQuery('SELECT MAX(journey) m FROM completions WHERE deleted = 0');
    return (r.first['m'] as int?) ?? 1;
  }

  // ---------------- notes ----------------
  Note _note(Map<String, Object?> r) => Note(
    id: r['id'] as String,
    studyStart: r['study_start'] as int,
    studyEnd: r['study_end'] as int,
    verseId: r['verse_id'] as int?,
    text: r['text'] as String,
    createdAt: DateTime.fromMillisecondsSinceEpoch(r['created_at'] as int),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(r['updated_at'] as int),
    conflictOf: r['conflict_of'] as String?,
  );

  Future<List<Note>> notesForStudy(int start, int end) async {
    final rows = await db.query(
      'notes',
      where: 'deleted = 0 AND study_start <= ? AND study_end >= ?',
      whereArgs: [end, start],
      orderBy: 'created_at',
    );
    return rows.map(_note).toList();
  }

  Future<List<Note>> allNotes() async =>
      (await db.query('notes', where: 'deleted = 0', orderBy: 'updated_at DESC')).map(_note).toList();

  Future<Note> saveNote({String? id, required int studyStart, required int studyEnd, int? verseId, required String text}) async {
    final now = _now();
    if (id == null) {
      final n = {
        'id': newId(),
        'study_start': studyStart,
        'study_end': studyEnd,
        'verse_id': verseId,
        'text': text,
        'created_at': now,
        'updated_at': now,
      };
      await db.insert('notes', n);
      return _note(n);
    }
    await db.update('notes', {'text': text, 'updated_at': now, 'synced': 0}, where: 'id = ?', whereArgs: [id]);
    return _note((await db.query('notes', where: 'id = ?', whereArgs: [id])).first);
  }

  /// Soft delete (tombstone) so the deletion can sync.
  Future<void> deleteNote(String id) async =>
      db.update('notes', {'deleted': 1, 'updated_at': _now(), 'synced': 0}, where: 'id = ?', whereArgs: [id]);

  // ---------------- bookmarks ----------------
  Bookmark _bm(Map<String, Object?> r) => Bookmark(
    id: r['id'] as String,
    type: BookmarkType.values.byName(r['type'] as String),
    verseStart: r['verse_start'] as int,
    verseEnd: r['verse_end'] as int,
    refId: r['ref_id'] as String?,
    label: r['label'] as String?,
    createdAt: DateTime.fromMillisecondsSinceEpoch(r['created_at'] as int),
  );

  Future<List<Bookmark>> bookmarks() async =>
      (await db.query('bookmarks', where: 'deleted = 0', orderBy: 'created_at DESC')).map(_bm).toList();

  Future<Bookmark?> findBookmark(BookmarkType type, int start, int end, {String? refId}) async {
    final rows = await db.query(
      'bookmarks',
      where: 'deleted = 0 AND type = ? AND verse_start = ? AND verse_end = ? AND IFNULL(ref_id, \'\') = ?',
      whereArgs: [type.name, start, end, refId ?? ''],
    );
    return rows.isEmpty ? null : _bm(rows.first);
  }

  Future<Bookmark> addBookmark(BookmarkType type, int start, int end, {String? refId, String? label}) async {
    final existing = await findBookmark(type, start, end, refId: refId);
    if (existing != null) return existing;
    final now = _now();
    final row = {
      'id': newId(),
      'type': type.name,
      'verse_start': start,
      'verse_end': end,
      'ref_id': refId,
      'label': label,
      'created_at': now,
      'updated_at': now,
    };
    await db.insert('bookmarks', row);
    return _bm(row);
  }

  Future<void> removeBookmark(String id) async =>
      db.update('bookmarks', {'deleted': 1, 'updated_at': _now(), 'synced': 0}, where: 'id = ?', whereArgs: [id]);

  // ---------------- cache ----------------
  Future<String?> cacheGet(String key) async {
    final r = await db.query('cache', where: 'key = ?', whereArgs: [key]);
    return r.isEmpty ? null : r.first['value'] as String;
  }

  Future<void> cachePut(String key, String value) async => db.insert(
    'cache',
    {'key': key, 'value': value, 'fetched_at': _now()},
    conflictAlgorithm: ConflictAlgorithm.replace,
  );

  Future<int> cacheCount(String prefix) async {
    final r = await db.rawQuery('SELECT COUNT(*) c FROM cache WHERE key LIKE ?', ['$prefix%']);
    return r.first['c'] as int;
  }

  // ---------------- CMS content ----------------
  Future<void> upsertContent(List<Map<String, dynamic>> items, List<String> removed) async {
    final b = db.batch();
    for (final it in items) {
      b.insert(
        'content_items',
        {
          'id': it['id'],
          'type': it['type'],
          'surah': it['surah'],
          'start_ayah': it['start_ayah'],
          'end_ayah': it['end_ayah'],
          'json': jsonEncode(it),
          'updated_at': it['updated_at'],
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    for (final id in removed) {
      b.delete('content_items', where: 'id = ?', whereArgs: [id]);
      b.delete('groupings', where: 'id = ?', whereArgs: [id]);
    }
    await b.commit(noResult: true);
  }

  Future<void> upsertGroupings(List<Map<String, dynamic>> gs) async {
    final b = db.batch();
    for (final g in gs) {
      b.insert('groupings', {'id': g['id'], 'json': jsonEncode(g)}, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await b.commit(noResult: true);
  }

  Future<List<Map<String, dynamic>>> serverGroupings() async =>
      (await db.query('groupings')).map((r) => jsonDecode(r['json'] as String) as Map<String, dynamic>).toList();

  Future<List<Map<String, dynamic>>> contentFor(int surah, int startAyah, int endAyah) async {
    final rows = await db.query(
      'content_items',
      where: 'surah = ? AND start_ayah <= ? AND end_ayah >= ?',
      whereArgs: [surah, endAyah, startAyah],
    );
    return rows.map((r) => jsonDecode(r['json'] as String) as Map<String, dynamic>).toList();
  }

  Future<List<Map<String, dynamic>>> surahIntro(int surah) async {
    final rows = await db.query('content_items', where: 'surah = ? AND type = ?', whereArgs: [surah, 'surah_intro']);
    return rows.map((r) => jsonDecode(r['json'] as String) as Map<String, dynamic>).toList();
  }

  // ---------------- kv ----------------
  Future<String?> kvGet(String k) async {
    final r = await db.query('kv', where: 'key = ?', whereArgs: [k]);
    return r.isEmpty ? null : r.first['value'] as String?;
  }

  Future<void> kvSet(String k, String? v) async =>
      db.insert('kv', {'key': k, 'value': v}, conflictAlgorithm: ConflictAlgorithm.replace);

  // ---------------- sync support ----------------
  Future<List<Map<String, dynamic>>> unsyncedChanges() async {
    String iso(int ms) => DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).toIso8601String();
    final out = <Map<String, dynamic>>[];
    for (final r in await db.query('notes', where: 'synced = 0')) {
      out.add({
        'kind': 'note',
        'id': r['id'],
        'updated_at': iso(r['updated_at'] as int),
        'deleted': r['deleted'] == 1,
        'base_updated_at': r['server_updated_at'] == null ? null : iso(r['server_updated_at'] as int),
        'data': {
          'study_start': r['study_start'],
          'study_end': r['study_end'],
          'verse_id': r['verse_id'],
          'text': r['text'],
          'created_at': iso(r['created_at'] as int),
          if (r['conflict_of'] != null) 'conflict_of': r['conflict_of'],
        },
      });
    }
    for (final r in await db.query('bookmarks', where: 'synced = 0')) {
      out.add({
        'kind': 'bookmark',
        'id': r['id'],
        'updated_at': iso(r['updated_at'] as int),
        'deleted': r['deleted'] == 1,
        'base_updated_at': null,
        'data': {
          'type': r['type'],
          'verse_start': r['verse_start'],
          'verse_end': r['verse_end'],
          'ref_id': r['ref_id'],
          'label': r['label'],
          'created_at': iso(r['created_at'] as int),
        },
      });
    }
    for (final r in await db.query('completions', where: 'synced = 0')) {
      out.add({
        'kind': 'progress',
        'id': r['id'],
        'updated_at': iso(r['updated_at'] as int),
        'deleted': r['deleted'] == 1,
        'base_updated_at': null,
        'data': {
          'verse_start': r['start_id'],
          'verse_end': r['end_id'],
          'completed_at': iso(r['completed_at'] as int),
          'journey': r['journey'],
        },
      });
    }
    return out;
  }

  Future<void> markSynced(List<Map<String, dynamic>> sent) async {
    final b = db.batch();
    for (final c in sent) {
      final table = switch (c['kind']) { 'note' => 'notes', 'bookmark' => 'bookmarks', _ => 'completions' };
      final ms = DateTime.parse(c['updated_at'] as String).millisecondsSinceEpoch;
      // Only mark synced if not modified again since we sent it.
      b.update(
        table,
        {'synced': 1, if (table == 'notes') 'server_updated_at': ms},
        where: 'id = ? AND updated_at = ?',
        whereArgs: [c['id'], ms],
      );
    }
    await b.commit(noResult: true);
  }

  /// Applies a server record. Server wins only if it is newer; local unsynced
  /// note edits are never overwritten (the server resolves those as
  /// "kept_both" conflicts on the next push).
  Future<void> applyRemote(Map<String, dynamic> c) async {
    final ms = DateTime.parse(c['updated_at'] as String).millisecondsSinceEpoch;
    final d = (c['data'] as Map?)?.cast<String, dynamic>() ?? {};
    final deleted = c['deleted'] == true ? 1 : 0;
    int toMs(Object? iso) => iso == null ? ms : DateTime.parse(iso as String).millisecondsSinceEpoch;
    final table = switch (c['kind']) { 'note' => 'notes', 'bookmark' => 'bookmarks', _ => 'completions' };
    final local = await db.query(table, where: 'id = ?', whereArgs: [c['id']]);
    if (local.isNotEmpty) {
      final l = local.first;
      if (l['synced'] == 0 && table == 'notes') return; // protect unsynced user text
      if ((l['updated_at'] as int) >= ms && l['synced'] == 0) return;
    }
    final Map<String, Object?> row = switch (table) {
      'notes' => {
        'id': c['id'],
        'study_start': d['study_start'] ?? 1,
        'study_end': d['study_end'] ?? 1,
        'verse_id': d['verse_id'],
        'text': d['text'] ?? '',
        'created_at': toMs(d['created_at']),
        'updated_at': ms,
        'deleted': deleted,
        'synced': 1,
        'server_updated_at': ms,
        'conflict_of': d['conflict_of'],
      },
      'bookmarks' => {
        'id': c['id'],
        'type': d['type'] ?? 'verse',
        'verse_start': d['verse_start'] ?? 1,
        'verse_end': d['verse_end'] ?? 1,
        'ref_id': d['ref_id'],
        'label': d['label'],
        'created_at': toMs(d['created_at']),
        'updated_at': ms,
        'deleted': deleted,
        'synced': 1,
      },
      _ => {
        'id': c['id'],
        'start_id': d['verse_start'] ?? 1,
        'end_id': d['verse_end'] ?? 1,
        'completed_at': toMs(d['completed_at']),
        'journey': d['journey'] ?? 1,
        'updated_at': ms,
        'deleted': deleted,
        'synced': 1,
      },
    };
    await db.insert(table, row, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Everything the user created, for export.
  Future<Map<String, dynamic>> exportAll() async => {
    'exported_at': DateTime.now().toUtc().toIso8601String(),
    'completions': await db.query('completions'),
    'notes': await db.query('notes'),
    'bookmarks': await db.query('bookmarks'),
  };

  Future<void> wipeUserData() async {
    for (final t in ['completions', 'notes', 'bookmarks', 'kv']) {
      await db.delete(t);
    }
  }
}
