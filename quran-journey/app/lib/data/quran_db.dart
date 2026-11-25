import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../domain/models.dart';

/// Read-only access to the bundled, verified Quran database
/// (assets/db/quran.db, built by tools/build_content.py).
class QuranDb {
  final Database db;
  late final List<Surah> surahs;
  late final List<int> wordCounts; // index = verse id
  late final List<TranslationInfo> translations;
  late final Map<String, String> meta;

  QuranDb._(this.db);

  static const _assetPath = 'assets/db/quran.db';
  static const _bundleStamp = 'quran_db_bundle_bytes';

  /// Copies the asset into app storage once per bundled version (the copy is
  /// refreshed automatically after an app update ships a new database).
  static Future<QuranDb> open({String? overridePath}) async {
    String path;
    if (overridePath != null) {
      path = overridePath;
    } else {
      final dir = await getApplicationSupportDirectory();
      path = p.join(dir.path, 'quran.db');
      final data = await rootBundle.load(_assetPath);
      final prefs = await SharedPreferences.getInstance();
      final stamp = '${data.lengthInBytes}';
      final file = File(path);
      if (!await file.exists() || prefs.getString(_bundleStamp) != stamp) {
        await file.parent.create(recursive: true);
        await file.writeAsBytes(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
          flush: true,
        );
        await prefs.setString(_bundleStamp, stamp);
      }
    }
    final db = await openDatabase(path, readOnly: true, singleInstance: true);
    final q = QuranDb._(db);
    await q._load();
    return q;
  }

  /// For tests (sqflite_common_ffi database factory).
  static Future<QuranDb> openWith(Database db) async {
    final q = QuranDb._(db);
    await q._load();
    return q;
  }

  Future<void> _load() async {
    surahs = (await db.query('surahs', orderBy: 'number')).map(Surah.fromRow).toList();
    final total = surahs.fold<int>(0, (a, s) => a + s.ayahCount);
    wordCounts = List<int>.filled(total + 1, 0);
    for (final r in await db.rawQuery('SELECT verse_id, COUNT(*) c FROM words GROUP BY verse_id')) {
      wordCounts[r['verse_id'] as int] = r['c'] as int;
    }
    translations = (await db.query('translations', orderBy: 'id')).map(TranslationInfo.fromRow).toList();
    meta = {
      for (final r in await db.query('meta')) r['key'] as String: r['value'] as String,
    };
  }

  int get totalVerses => wordCounts.length - 1;
  Surah surah(int n) => surahs[n - 1];

  List<TranslationInfo> get englishTranslations =>
      translations.where((t) => t.kind == 'translation').toList();
  TranslationInfo get transliteration => translations.firstWhere((t) => t.kind == 'transliteration');

  Future<List<Verse>> verses(int startId, int endId) async {
    final rows = await db.query(
      'verses',
      where: 'id BETWEEN ? AND ?',
      whereArgs: [startId, endId],
      orderBy: 'id',
    );
    return rows.map(Verse.fromRow).toList();
  }

  Future<Verse?> verseByKey(int surah, int ayah) async {
    final rows = await db.query('verses', where: 'surah = ? AND ayah = ?', whereArgs: [surah, ayah]);
    return rows.isEmpty ? null : Verse.fromRow(rows.first);
  }

  Future<Map<int, String>> translationText(int translationId, int startId, int endId) async {
    final rows = await db.query(
      'translation_text',
      columns: ['verse_id', 'text'],
      where: 'translation_id = ? AND verse_id BETWEEN ? AND ?',
      whereArgs: [translationId, startId, endId],
    );
    return {for (final r in rows) r['verse_id'] as int: r['text'] as String};
  }

  Future<List<Word>> words(int verseId) async {
    final rows = await db.query('words', where: 'verse_id = ?', whereArgs: [verseId], orderBy: 'position');
    return rows.map((r) {
      final segs = (r['segments'] as String).split('\n').map((line) {
        final f = line.split('\t');
        return WordSegment(f[0], f[1], f[2]);
      }).toList();
      return Word(
        verseId: r['verse_id'] as int,
        position: r['position'] as int,
        arabic: r['text_uthmani'] as String?,
        rootBw: r['root_bw'] as String?,
        rootAr: r['root_ar'] as String?,
        lemmaBw: r['lemma_bw'] as String?,
        lemmaAr: r['lemma_ar'] as String?,
        pos: r['pos'] as String?,
        segments: segs,
      );
    }).toList();
  }

  /// Other verses whose words share [rootBw] (from the corpus), for
  /// "occurrences of this root".
  Future<int> rootOccurrences(String rootBw) async {
    final r = await db.rawQuery('SELECT COUNT(*) c FROM words WHERE root_bw = ?', [rootBw]);
    return r.first['c'] as int;
  }

  Future<List<SourceInfo>> sources() async =>
      (await db.query('sources')).map(SourceInfo.fromRow).toList();

  /// Search: surah names, verse references ("2:255"), Arabic (diacritics
  /// insensitive) and translation text. Returns verse ids, max [limit].
  Future<List<int>> search(String query, {required int translationId, int limit = 60}) async {
    final q = query.trim();
    if (q.isEmpty) return const [];
    final ref = RegExp(r'^(\d{1,3})\s*[:.\s]\s*(\d{1,3})$').firstMatch(q);
    if (ref != null) {
      final v = await verseByKey(int.parse(ref.group(1)!), int.parse(ref.group(2)!));
      return v == null ? const [] : [v.id];
    }
    final isArabic = RegExp(r'[؀-ۿ]').hasMatch(q);
    if (isArabic) {
      final norm = normaliseArabic(q);
      final rows = await db.query(
        'verses',
        columns: ['id'],
        where: 'search_ar LIKE ?',
        whereArgs: ['%$norm%'],
        orderBy: 'id',
        limit: limit,
      );
      return rows.map((r) => r['id'] as int).toList();
    }
    final rows = await db.query(
      'translation_text',
      columns: ['verse_id'],
      where: 'translation_id = ? AND text LIKE ?',
      whereArgs: [translationId, '%$q%'],
      orderBy: 'verse_id',
      limit: limit,
    );
    return rows.map((r) => r['verse_id'] as int).toList();
  }

  /// Must mirror tools/build_content.py search_normalise().
  static String normaliseArabic(String text) {
    var t = text.replaceAll(RegExp('[ؐ-ًؚ-ٰٟۖ-ۭـ]'), '');
    t = t
        .replaceAll('ٱ', 'ا')
        .replaceAll('أ', 'ا')
        .replaceAll('إ', 'ا')
        .replaceAll('آ', 'ا')
        .replaceAll('ى', 'ي');
    return t.replaceAll(RegExp(r'\s+'), ' ').trim();
  }
}
