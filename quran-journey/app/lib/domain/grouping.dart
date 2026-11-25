import 'models.dart';

/// An editorial grouping override for part of a surah. Overrides come from
/// the bundled `assets/content/groupings.json` and, if a server is
/// configured, from published CMS groupings.
class GroupingOverride {
  final int surah;
  final int startAyah;
  final int endAyah;
  final String rationale;
  const GroupingOverride(this.surah, this.startAyah, this.endAyah, this.rationale);

  factory GroupingOverride.fromJson(Map<String, dynamic> j) => GroupingOverride(
    j['surah'] as int,
    j['start_ayah'] as int,
    j['end_ayah'] as int,
    (j['rationale'] as String?) ?? '',
  );
}

/// The transparent study progression rule (also shown in-app under
/// Settings ▸ Sources & methodology):
///
/// 1. Studies follow mushaf order from 1:1 to 114:6 and never cross a surah
///    boundary.
/// 2. Each study takes the next [versesPerStudy] verses (default 3)…
/// 3. …but stops early if adding the next verse would exceed [maxWords]
///    Arabic words, so very long verses (e.g. 2:282) are studied alone or in
///    smaller groups. A study always contains at least one complete verse.
/// 4. If the last study of a surah would contain a single verse, it is
///    merged into the previous study when that keeps the study within
///    [maxWords] (avoids a lone, context-less final verse).
/// 5. Editorial overrides replace the rule for the verses they cover (each
///    has a published rationale). Invalid overrides are ignored.
class StudyPlan {
  final int versesPerStudy;
  final int maxWords;
  final List<Study> studies;
  final List<int> _studyIndexByVerse; // verse id -> study index

  StudyPlan._(this.versesPerStudy, this.maxWords, this.studies, this._studyIndexByVerse);

  int get length => studies.length;
  int get totalVerses => _studyIndexByVerse.length - 1;

  Study studyForVerse(int verseId) => studies[_studyIndexByVerse[verseId]];

  Study? byRange(int startId, int endId) {
    if (startId < 1 || startId > totalVerses) return null;
    final s = studyForVerse(startId);
    if (s.startId == startId && s.endId == endId) return s;
    return null;
  }

  static StudyPlan build({
    required List<Surah> surahs,
    required List<int> wordCounts, // index = verse id (0 unused)
    List<GroupingOverride> overrides = const [],
    int versesPerStudy = 3,
    int maxWords = 75,
  }) {
    assert(versesPerStudy >= 1);
    final studies = <Study>[];
    final total = surahs.fold<int>(0, (a, s) => a + s.ayahCount);
    final byVerse = List<int>.filled(total + 1, -1);

    final bySurah = <int, List<GroupingOverride>>{};
    for (final o in overrides) {
      bySurah.putIfAbsent(o.surah, () => []).add(o);
    }

    for (final s in surahs) {
      final valid = _validOverrides(s, bySurah[s.number] ?? const []);
      final groups = <List<Object?>>[]; // [startAyah, endAyah, rationale]
      var ayah = 1;
      var oi = 0;
      while (ayah <= s.ayahCount) {
        if (oi < valid.length && valid[oi].startAyah == ayah) {
          final o = valid[oi++];
          groups.add([o.startAyah, o.endAyah, o.rationale]);
          ayah = o.endAyah + 1;
          continue;
        }
        final limit = oi < valid.length ? valid[oi].startAyah - 1 : s.ayahCount;
        final start = ayah;
        var end = ayah;
        var words = wordCounts[s.firstVerseId + ayah - 1];
        while (end - start + 1 < versesPerStudy && end < limit) {
          final next = wordCounts[s.firstVerseId + end];
          if (words + next > maxWords) break;
          words += next;
          end++;
        }
        groups.add([start, end, null]);
        ayah = end + 1;
      }
      // Rule 4: merge a lone final verse into the previous rule-made group.
      if (groups.length >= 2) {
        final last = groups.last;
        final prev = groups[groups.length - 2];
        if (last[0] == last[1] && last[2] == null && prev[2] == null && versesPerStudy > 1) {
          var w = 0;
          for (var a = prev[0] as int; a <= (last[1] as int); a++) {
            w += wordCounts[s.firstVerseId + a - 1];
          }
          if (w <= maxWords) {
            prev[1] = last[1];
            groups.removeLast();
          }
        }
      }
      for (final g in groups) {
        final a0 = g[0] as int, a1 = g[1] as int;
        final st = Study(
          index: studies.length,
          surah: s.number,
          startAyah: a0,
          endAyah: a1,
          startId: s.firstVerseId + a0 - 1,
          endId: s.firstVerseId + a1 - 1,
          rationale: g[2] as String?,
        );
        for (var v = st.startId; v <= st.endId; v++) {
          byVerse[v] = st.index;
        }
        studies.add(st);
      }
    }
    // Integrity: every verse belongs to exactly one study, in order.
    for (var v = 1; v <= total; v++) {
      if (byVerse[v] < 0) throw StateError('Verse $v not covered by the study plan');
    }
    return StudyPlan._(versesPerStudy, maxWords, studies, byVerse);
  }

  static List<GroupingOverride> _validOverrides(Surah s, List<GroupingOverride> list) {
    final sorted = [...list]..sort((a, b) => a.startAyah.compareTo(b.startAyah));
    final out = <GroupingOverride>[];
    var lastEnd = 0;
    for (final o in sorted) {
      final ok = o.startAyah >= 1 &&
          o.endAyah <= s.ayahCount &&
          o.startAyah <= o.endAyah &&
          o.startAyah > lastEnd;
      if (ok) {
        out.add(o);
        lastEnd = o.endAyah;
      }
    }
    return out;
  }
}
