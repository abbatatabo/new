import 'package:flutter_test/flutter_test.dart';
import 'package:quran_journey/data/quran_db.dart';
import 'package:quran_journey/domain/grouping.dart';
import 'package:quran_journey/domain/progress.dart';

import 'helpers.dart';

const fatihahOverrides = [
  GroupingOverride(1, 1, 4, 'praise'),
  GroupingOverride(1, 5, 7, 'request'),
];

void main() {
  late QuranDb q;
  late StudyPlan plan;
  setUpAll(() async {
    q = await openRealQuranDb();
    plan = StudyPlan.build(surahs: q.surahs, wordCounts: q.wordCounts, overrides: fatihahOverrides);
  });

  group('Study plan', () {
    test('covers every verse exactly once, in order, never crossing a surah', () {
      var expected = 1;
      for (final s in plan.studies) {
        expect(s.startId, expected, reason: '$s');
        expect(s.endId >= s.startId, isTrue);
        final surah = q.surah(s.surah);
        expect(s.startId >= surah.firstVerseId && s.endId <= surah.lastVerseId, isTrue, reason: '$s crosses surah');
        expect(s.endAyah - s.startAyah, s.endId - s.startId);
        expected = s.endId + 1;
      }
      expect(expected - 1, 6236);
      for (var i = 0; i < plan.length; i++) {
        expect(plan.studies[i].index, i);
      }
    });

    test('default size is 3 verses; only merges or overrides make 4', () {
      for (final s in plan.studies) {
        if (s.rationale != null) continue;
        expect(s.verseCount, lessThanOrEqualTo(4), reason: '$s');
      }
      expect(plan.studies.where((s) => s.verseCount == 3).length, greaterThan(plan.length * 0.6));
    });

    test('word limit respected except for single long verses', () {
      for (final s in plan.studies.where((s) => s.rationale == null)) {
        var w = 0;
        for (var v = s.startId; v <= s.endId; v++) {
          w += q.wordCounts[v];
        }
        if (s.verseCount > 1) expect(w, lessThanOrEqualTo(plan.maxWords), reason: '$s has $w words');
      }
    });

    test('Al-Fatihah uses the editorial grouping 1–4, 5–7', () {
      expect(plan.studies[0].refLabel, '1:1–4');
      expect(plan.studies[1].refLabel, '1:5–7');
      expect(plan.studies[2].surah, 2);
      expect(plan.studies[2].startAyah, 1);
    });

    test('2:282 (the longest verse) is studied on its own', () {
      final id = q.surah(2).firstVerseId + 281;
      final s = plan.studyForVerse(id);
      expect(s.startId, id);
      expect(s.endId, id);
    });

    test('last study ends at An-Nas 114:6', () {
      final last = plan.studies.last;
      expect(last.surah, 114);
      expect(last.endAyah, 6);
    });

    test('lone final verse merges into the previous study', () {
      // Surah 1 without overrides: 7 verses -> 1–3, 4–7
      final p = StudyPlan.build(surahs: q.surahs, wordCounts: q.wordCounts);
      expect(p.studies[0].refLabel, '1:1–3');
      expect(p.studies[1].refLabel, '1:4–7');
    });

    test('invalid overrides are ignored safely', () {
      final p = StudyPlan.build(surahs: q.surahs, wordCounts: q.wordCounts, overrides: const [
        GroupingOverride(1, 3, 99, 'out of range'),
        GroupingOverride(1, 5, 2, 'reversed'),
      ]);
      expect(p.studies[0].refLabel, '1:1–3');
    });

    test('other study sizes still cover everything', () {
      for (final n in [1, 2, 5]) {
        final p = StudyPlan.build(surahs: q.surahs, wordCounts: q.wordCounts, versesPerStudy: n);
        expect(p.studies.last.endId, 6236);
        expect(p.studies.every((s) => s.verseCount <= n + 1), isTrue);
      }
      expect(StudyPlan.build(surahs: q.surahs, wordCounts: q.wordCounts, versesPerStudy: 1).length, 6236);
    });

    test('byRange finds exact studies only', () {
      expect(plan.byRange(1, 4), plan.studies[0]);
      expect(plan.byRange(1, 3), isNull);
      expect(plan.byRange(9999, 10000), isNull);
    });
  });

  group('Progress', () {
    Completion c(int a, int b, DateTime at) => Completion(id: '$a-$b-$at', startId: a, endId: b, completedAt: at);
    final day1 = DateTime(2026, 3, 1, 8);

    test('starts at Al-Fatihah', () {
      final p = Progress(plan, const []);
      expect(p.nextStudy, plan.studies.first);
      expect(p.completedVerses, 0);
    });

    test('advances through surah boundary 1 -> 2', () {
      final p = Progress(plan, [c(1, 4, day1), c(5, 7, day1)]);
      expect(p.nextStudy!.surah, 2);
      expect(p.nextStudy!.startAyah, 1);
      expect(p.surahProgress(q.surahs).first.complete, isTrue);
    });

    test('missed days never skip verses', () {
      final p = Progress(plan, [c(1, 4, day1)]);
      // A week passes with no study: next is still 1:5.
      final later = DateTime(2026, 3, 9, 20);
      expect(p.nextStudy!.refLabel, '1:5–7');
      final slots = p.today(SessionConfig.defaults, later);
      expect(slots.first.study.refLabel, '1:5–7');
      expect(slots.map((s) => s.study.index).toList(), [1, 2, 3]);
    });

    test('today slots: done first, then the next unread, with states by time', () {
      final p = Progress(plan, [c(1, 4, DateTime(2026, 3, 2, 7, 10))]);
      final now = DateTime(2026, 3, 2, 14, 0);
      final slots = p.today(SessionConfig.defaults, now);
      expect(slots[0].state, SlotState.done);
      expect(slots[1].state, SlotState.ready); // 13:30 passed
      expect(slots[2].state, SlotState.upcoming); // 20:00
      expect(slots[1].study.refLabel, '1:5–7');
    });

    test('disabled sessions reduce daily slots', () {
      final p = Progress(plan, const []);
      final sessions = [SessionConfig.defaults[0], SessionConfig.defaults[1].copyWith(enabled: false), SessionConfig.defaults[2]];
      expect(p.today(sessions, day1).length, 2);
    });

    test('reading ahead out of order keeps the earliest unread as next', () {
      final p = Progress(plan, const []);
      final s3 = plan.studies[3];
      expect(p.add(c(s3.startId, s3.endId, day1)), isTrue);
      expect(p.nextStudy, plan.studies[0]);
      expect(p.isStudyComplete(s3), isTrue);
      p.add(c(1, 4, day1));
      p.add(c(5, 7, day1));
      p.add(c(plan.studies[2].startId, plan.studies[2].endId, day1));
      expect(p.nextStudy, plan.studies[4]); // skips the already-read study 3, never an unread one
    });

    test('re-reading does not double count', () {
      final p = Progress(plan, [c(1, 4, day1)]);
      expect(p.add(c(1, 4, day1.add(const Duration(hours: 5)))), isFalse);
      expect(p.completedVerses, 4);
    });

    test('changing verses-per-study keeps completed verses', () {
      final p3 = Progress(plan, [c(1, 4, day1), c(5, 7, day1), c(8, 10, day1)]);
      expect(p3.completedVerses, 10);
      final plan1 = StudyPlan.build(surahs: q.surahs, wordCounts: q.wordCounts, versesPerStudy: 1);
      final p1 = Progress(plan1, p3.completions);
      expect(p1.completedVerses, 10);
      expect(p1.nextStudy!.startId, 11);
    });

    test('journey completes at An-Nas and reports no next study', () {
      final p = Progress(plan, [c(1, 6236, day1)]);
      expect(p.journeyComplete, isTrue);
      expect(p.nextStudy, isNull);
      expect(p.fraction, 1.0);
      expect(p.today(SessionConfig.defaults, day1).length, 1); // only the record completed today
    });
  });
}
