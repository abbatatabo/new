class Surah {
  final int number;
  final String nameAr;
  final String nameTranslit;
  final String nameEn;
  final String revelationType;
  final int revelationOrder;
  final int ayahCount;
  final int firstVerseId;
  final int rukus;

  const Surah({
    required this.number,
    required this.nameAr,
    required this.nameTranslit,
    required this.nameEn,
    required this.revelationType,
    required this.revelationOrder,
    required this.ayahCount,
    required this.firstVerseId,
    required this.rukus,
  });

  int get lastVerseId => firstVerseId + ayahCount - 1;

  factory Surah.fromRow(Map<String, Object?> r) => Surah(
    number: r['number'] as int,
    nameAr: r['name_ar'] as String,
    nameTranslit: r['name_translit'] as String,
    nameEn: r['name_en'] as String,
    revelationType: r['revelation_type'] as String,
    revelationOrder: r['revelation_order'] as int,
    ayahCount: r['ayah_count'] as int,
    firstVerseId: r['first_verse_id'] as int,
    rukus: r['rukus'] as int,
  );
}

class Verse {
  final int id;
  final int surah;
  final int ayah;
  final String arabic;
  final String? bismillah;
  final int juz;
  final int page;
  final String? sajdah;

  const Verse({
    required this.id,
    required this.surah,
    required this.ayah,
    required this.arabic,
    this.bismillah,
    required this.juz,
    required this.page,
    this.sajdah,
  });

  String get key => '$surah:$ayah';

  factory Verse.fromRow(Map<String, Object?> r) => Verse(
    id: r['id'] as int,
    surah: r['surah'] as int,
    ayah: r['ayah'] as int,
    arabic: r['text_uthmani'] as String,
    bismillah: r['bismillah'] as String?,
    juz: r['juz'] as int,
    page: r['page'] as int,
    sajdah: r['sajdah'] as String?,
  );
}

/// A study = a contiguous verse range inside one surah.
class Study {
  final int index; // 0-based position in the whole journey
  final int surah;
  final int startAyah;
  final int endAyah;
  final int startId; // global verse id
  final int endId;
  final String? rationale; // set when an editorial grouping override applies

  const Study({
    required this.index,
    required this.surah,
    required this.startAyah,
    required this.endAyah,
    required this.startId,
    required this.endId,
    this.rationale,
  });

  int get verseCount => endId - startId + 1;
  String get rangeKey => '$startId-$endId';
  String get refLabel =>
      startAyah == endAyah ? '$surah:$startAyah' : '$surah:$startAyah–$endAyah';
  String get deepLink => 'quranjourney://study/$startId-$endId';
  bool containsVerse(int id) => id >= startId && id <= endId;

  @override
  bool operator ==(Object other) =>
      other is Study && other.startId == startId && other.endId == endId;
  @override
  int get hashCode => Object.hash(startId, endId);
  @override
  String toString() => 'Study#$index($refLabel)';
}

class TranslationInfo {
  final int id;
  final String code;
  final String kind;
  final String name;
  final String translator;
  final String language;
  final String sourceId;
  const TranslationInfo({
    required this.id,
    required this.code,
    required this.kind,
    required this.name,
    required this.translator,
    required this.language,
    required this.sourceId,
  });
  factory TranslationInfo.fromRow(Map<String, Object?> r) => TranslationInfo(
    id: r['id'] as int,
    code: r['code'] as String,
    kind: r['kind'] as String,
    name: r['name'] as String,
    translator: r['translator'] as String,
    language: r['language'] as String,
    sourceId: r['source_id'] as String,
  );
}

class SourceInfo {
  final String id;
  final String contentType;
  final String workTitle;
  final String author;
  final String? edition;
  final String? url;
  final String license;
  final String verificationStatus;
  final String? sha256;
  const SourceInfo({
    required this.id,
    required this.contentType,
    required this.workTitle,
    required this.author,
    this.edition,
    this.url,
    required this.license,
    required this.verificationStatus,
    this.sha256,
  });
  factory SourceInfo.fromRow(Map<String, Object?> r) => SourceInfo(
    id: r['id'] as String,
    contentType: r['content_type'] as String,
    workTitle: r['work_title'] as String,
    author: r['author'] as String,
    edition: r['edition'] as String?,
    url: r['url'] as String?,
    license: r['license'] as String,
    verificationStatus: r['verification_status'] as String,
    sha256: r['sha256'] as String?,
  );
}

class Word {
  final int verseId;
  final int position;
  final String? arabic; // Tanzil token
  final String? rootBw;
  final String? rootAr;
  final String? lemmaBw;
  final String? lemmaAr;
  final String? pos;
  final List<WordSegment> segments;

  const Word({
    required this.verseId,
    required this.position,
    this.arabic,
    this.rootBw,
    this.rootAr,
    this.lemmaBw,
    this.lemmaAr,
    this.pos,
    required this.segments,
  });
}

class WordSegment {
  final String formBw;
  final String tag;
  final String features;
  const WordSegment(this.formBw, this.tag, this.features);
}

class Note {
  final String id;
  final int studyStart;
  final int studyEnd;
  final int? verseId;
  final String text;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? conflictOf;
  const Note({
    required this.id,
    required this.studyStart,
    required this.studyEnd,
    this.verseId,
    required this.text,
    required this.createdAt,
    required this.updatedAt,
    this.conflictOf,
  });
}

enum BookmarkType { verse, study, tafsir, reflection }

class Bookmark {
  final String id;
  final BookmarkType type;
  final int verseStart;
  final int verseEnd;
  final String? refId;
  final String? label;
  final DateTime createdAt;
  const Bookmark({
    required this.id,
    required this.type,
    required this.verseStart,
    required this.verseEnd,
    this.refId,
    this.label,
    required this.createdAt,
  });
}
