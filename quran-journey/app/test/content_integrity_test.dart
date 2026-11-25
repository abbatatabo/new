import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quran_journey/data/quran_db.dart';

import 'helpers.dart';

void main() {
  late QuranDb q;
  setUpAll(() async => q = await openRealQuranDb());

  test('114 surahs, 6236 verses, contiguous global ids', () async {
    expect(q.surahs.length, 114);
    expect(q.totalVerses, 6236);
    var expected = 1;
    for (final s in q.surahs) {
      expect(s.firstVerseId, expected, reason: 'surah ${s.number}');
      expected += s.ayahCount;
    }
    expect(expected - 1, 6236);
  });

  test('Known surah facts from Tanzil metadata', () {
    expect(q.surah(1).nameTranslit, 'Al-Faatiha');
    expect(q.surah(1).ayahCount, 7);
    expect(q.surah(2).ayahCount, 286);
    expect(q.surah(9).ayahCount, 129);
    expect(q.surah(114).ayahCount, 6);
    expect(q.surah(114).lastVerseId, 6236);
  });

  test('Arabic text checksum matches the build pipeline (text unaltered)', () async {
    final rows = await q.db.query('verses', columns: ['text_uthmani'], orderBy: 'id');
    final joined = rows.map((r) => r['text_uthmani'] as String).join('\n');
    final digest = sha256.convert(utf8.encode(joined)).toString();
    expect(digest, q.meta['arabic_text_sha256']);
  });

  test('Every stored verse is identical to the Tanzil source file', () async {
    // Independent of the build script: parse the verbatim source XML here.
    final xml = File('../content/sources/quran-uthmani.xml').readAsStringSync();
    final re = RegExp(r'<aya index="(\d+)" text="([^"]*)"');
    final source = re.allMatches(xml).map((m) => m.group(2)!).toList();
    expect(source.length, 6236);
    final rows = await q.db.query('verses', columns: ['text_uthmani'], orderBy: 'id');
    for (var i = 0; i < 6236; i++) {
      expect(rows[i]['text_uthmani'], source[i], reason: 'verse id ${i + 1}');
    }
    final v = await q.verseByKey(1, 2);
    expect(v!.arabic, source[1]);
  });

  test('Bismillah only on ayah 1 of surahs 2–114 except 9', () async {
    final rows = await q.db.rawQuery('SELECT surah, ayah FROM verses WHERE bismillah IS NOT NULL');
    expect(rows.every((r) => r['ayah'] == 1), isTrue);
    final surahs = rows.map((r) => r['surah'] as int).toSet();
    expect(surahs.contains(1), isFalse);
    expect(surahs.contains(9), isFalse);
    expect(surahs.length, 112);
  });

  test('Every translation covers every verse', () async {
    for (final t in q.translations) {
      final r = await q.db.rawQuery('SELECT COUNT(*) c FROM translation_text WHERE translation_id = ?', [t.id]);
      expect(r.first['c'], 6236, reason: t.code);
    }
    final p = await q.translationText(1, 2, 2);
    expect(p[2], 'Praise be to Allah, Lord of the Worlds,');
  });

  test('Word-by-word morphology from the corpus', () async {
    final words = await q.words(2); // 1:2
    expect(words.length, 4);
    expect(words.first.arabic, 'ٱلْحَمْدُ');
    expect(words.first.rootAr, 'ح م د');
    expect(words.first.pos, 'N');
    expect(words[1].rootAr, 'ا ل ه');
  });

  test('Search: reference, Arabic (diacritic-insensitive) and English', () async {
    expect(await q.search('2:255', translationId: 1), [262]);
    final ar = await q.search('الحمد لله رب العالمين', translationId: 1);
    expect(ar.contains(2), isTrue);
    final en = await q.search('Lord of the Worlds', translationId: 1);
    expect(en.first, 2);
    expect(await q.search('zzzzqqq', translationId: 1), isEmpty);
  });

  test('Source metadata recorded for every bundled dataset', () async {
    final s = await q.sources();
    expect(s.map((e) => e.id).toSet(), containsAll(['tanzil-uthmani', 'en.pickthall', 'en.yusufali', 'qac-morphology']));
    expect(s.every((e) => e.license.isNotEmpty && e.sha256 != null), isTrue);
  });
}
