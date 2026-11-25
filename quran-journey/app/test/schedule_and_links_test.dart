import 'package:flutter_test/flutter_test.dart';
import 'package:quran_journey/domain/morphology.dart';
import 'package:quran_journey/domain/models.dart';
import 'package:quran_journey/domain/progress.dart';
import 'package:quran_journey/domain/schedule.dart';
import 'package:quran_journey/services/online_content.dart';
import 'package:quran_journey/services/widget_service.dart';
import 'package:quran_journey/state/app_state.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

void main() {
  group('Reminder planning', () {
    final now = DateTime(2026, 3, 10, 12, 0);

    test('7 days × enabled sessions, only future times', () {
      final r = planReminders(sessions: SessionConfig.defaults, prefs: const NotificationPrefs(), now: now);
      // today: 13:30 and 20:00 remain; then 6 full days × 3
      expect(r.length, 2 + 6 * 3);
      expect(r.length, lessThanOrEqualTo(64)); // iOS pending limit
      expect(r.map((e) => e.id).toSet().length, r.length, reason: 'ids unique');
    });

    test('disabled sessions and master switch', () {
      final sessions = [SessionConfig.defaults[0].copyWith(enabled: false), ...SessionConfig.defaults.skip(1)];
      expect(planReminders(sessions: sessions, prefs: const NotificationPrefs(), now: now).length, 2 + 6 * 2);
      expect(planReminders(sessions: SessionConfig.defaults, prefs: const NotificationPrefs(enabled: false), now: now), isEmpty);
    });

    test('pause skips reminders until the pause ends', () {
      final prefs = NotificationPrefs(pausedUntil: DateTime(2026, 3, 13));
      final r = planReminders(sessions: SessionConfig.defaults, prefs: prefs, now: now);
      expect(r.every((e) => !e.day.isBefore(DateTime(2026, 3, 13))), isTrue);
      expect(r.length, 4 * 3);
    });

    test('quiet hours wrap midnight and mark reminders silent', () {
      const prefs = NotificationPrefs(quietHoursEnabled: true, quietStart: 19 * 60, quietEnd: 7 * 60 + 30);
      expect(prefs.isQuietAt(20 * 60), isTrue);
      expect(prefs.isQuietAt(7 * 60), isTrue);
      expect(prefs.isQuietAt(13 * 60 + 30), isFalse);
      final r = planReminders(sessions: SessionConfig.defaults, prefs: prefs, now: now);
      expect(r.where((e) => e.session.id == 'evening').every((e) => e.quiet), isTrue);
      expect(r.where((e) => e.session.id == 'afternoon').every((e) => !e.quiet), isTrue);
    });

    test('ids stay unique across a year boundary', () {
      final r = planReminders(sessions: SessionConfig.defaults, prefs: const NotificationPrefs(), now: DateTime(2026, 12, 29, 6));
      expect(r.map((e) => e.id).toSet().length, r.length);
    });

    test('daylight-saving: wall-clock time is preserved across the DST change (tz database)', () {
      tzdata.initializeTimeZones();
      final ny = tz.getLocation('America/New_York');
      // DST starts 2026-03-08 02:00 in New York.
      final before = tz.TZDateTime(ny, 2026, 3, 7, 7, 0);
      final after = tz.TZDateTime(ny, 2026, 3, 9, 7, 0);
      expect(before.hour, 7);
      expect(after.hour, 7);
      expect(before.timeZoneOffset, const Duration(hours: -5));
      expect(after.timeZoneOffset, const Duration(hours: -4));
    });

    test('settings JSON round trip', () {
      final p = NotificationPrefs(style: NotificationStyle.verse, pausedUntil: DateTime(2026, 1, 1), quietHoursEnabled: true);
      final back = NotificationPrefs.fromJson(p.toJson());
      expect(back.style, NotificationStyle.verse);
      expect(back.pausedUntil, DateTime(2026, 1, 1));
      expect(back.quietHoursEnabled, isTrue);
    });
  });

  group('Widget refresh schedule', () {
    test('future session times and midnights, sorted', () {
      final t = refreshTimes([
        {'minutes': 420},
        {'minutes': 1200},
      ], DateTime(2026, 3, 10, 12));
      expect(t.first, DateTime(2026, 3, 10, 20));
      expect(t, contains(DateTime(2026, 3, 11, 0, 1)));
      expect(t.last, DateTime(2026, 3, 11, 20));
      expect(t.length, 4);
    });
  });

  group('Deep links', () {
    test('study, next, today, verse; iOS widget query ignored', () {
      final s = AppLink.parse('quranjourney://study/8-10?homeWidget=1');
      expect(s, isA<StudyLink>());
      expect((s as StudyLink).start, 8);
      expect(s.end, 10);
      expect(AppLink.parse('quranjourney://next'), isA<NextLink>());
      expect(AppLink.parse('quranjourney://today?homeWidget'), isA<TodayLink>());
      final v = AppLink.parse('quranjourney://verse/2:255') as VerseLink;
      expect((v.surah, v.ayah), (2, 255));
      expect(AppLink.parse('https://evil.example/study/1-4'), isNull);
      expect(AppLink.parse('quranjourney://study/abc'), isA<NextLink>());
      expect(AppLink.parse(''), isNull);
    });

    test('study deep link format matches contract', () {
      const s = Study(index: 0, surah: 1, startAyah: 1, endAyah: 4, startId: 1, endId: 4);
      expect(s.deepLink, 'quranjourney://study/1-4');
    });
  });

  group('Morphology', () {
    test('describes corpus tags without inventing', () {
      expect(Morphology.describe(const WordSegment('Hamodu', 'N', 'STEM|POS:N|LEM:Hamod|ROOT:Hmd|M|NOM')), 'Noun · M · nominative'.replaceAll('M ·', 'masculine ·'));
      expect(Morphology.describe(const WordSegment('{lo', 'DET', 'PREFIX|Al+')), 'Prefix: definite article al-');
      expect(Morphology.describe(const WordSegment('hum', 'PRON', 'SUFFIX|PRON:3MP')), 'Suffix: attached pronoun (3rd person masculine plural)');
      expect(Morphology.describe(const WordSegment('qaAla', 'V', 'STEM|POS:V|PERF|LEM:qaAla|ROOT:qwl|3MS')),
          'Verb · perfect aspect · 3rd person masculine singular');
      expect(Morphology.describe(const WordSegment('x', 'ZZZ', 'STEM|POS:ZZZ|WEIRD')), 'ZZZ · WEIRD');
    });

    test('Buckwalter decoding', () {
      expect(Morphology.bwToArabic('Hamod'), 'حَمْد');
      expect(Morphology.bwToArabic('maE2'), 'مَع');
    });
  });

  group('Tafsir HTML', () {
    test('keeps words, removes tags', () {
      final p = OnlineContentService.htmlToParagraphs('<p lang="ar">قال <span class="blue">ابن</span> كثير</p><p>ثانٍ &amp; ثالث</p>');
      expect(p, ['قال ابن كثير', 'ثانٍ & ثالث']);
    });
  });
}
