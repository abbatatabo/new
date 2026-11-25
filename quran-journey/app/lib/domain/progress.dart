import 'grouping.dart';
import 'models.dart';

/// One completed study, as stored and synced. Progress is verse-based, not
/// date-based: the journey position is the first verse not yet completed.
class Completion {
  final String id;
  final int startId;
  final int endId;
  final DateTime completedAt; // local time
  final int journey; // 1 = first journey; increments on "begin again"
  const Completion({
    required this.id,
    required this.startId,
    required this.endId,
    required this.completedAt,
    this.journey = 1,
  });
}

enum SlotState { done, ready, upcoming }

class SessionConfig {
  final String id; // morning | afternoon | evening
  final String label;
  final int minutes; // minutes after local midnight
  final bool enabled;
  const SessionConfig(this.id, this.label, this.minutes, this.enabled);

  SessionConfig copyWith({String? label, int? minutes, bool? enabled}) =>
      SessionConfig(id, label ?? this.label, minutes ?? this.minutes, enabled ?? this.enabled);

  Map<String, dynamic> toJson() => {'id': id, 'label': label, 'minutes': minutes, 'enabled': enabled};
  factory SessionConfig.fromJson(Map<String, dynamic> j) => SessionConfig(
    j['id'] as String,
    j['label'] as String,
    j['minutes'] as int,
    j['enabled'] as bool,
  );

  String get timeLabel {
    final h = minutes ~/ 60, m = minutes % 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
  }

  static const defaults = [
    SessionConfig('morning', 'Morning', 7 * 60, true),
    SessionConfig('afternoon', 'Afternoon', 13 * 60 + 30, true),
    SessionConfig('evening', 'Evening', 20 * 60, true),
  ];
}

class TodaySlot {
  final SessionConfig session;
  final Study study;
  final SlotState state;
  const TodaySlot(this.session, this.study, this.state);
}

class SurahProgress {
  final int surah;
  final int completedVerses;
  final int totalVerses;
  const SurahProgress(this.surah, this.completedVerses, this.totalVerses);
  bool get complete => completedVerses == totalVerses;
  bool get started => completedVerses > 0;
  double get fraction => totalVerses == 0 ? 0 : completedVerses / totalVerses;
}

/// Pure progression engine. No I/O, fully unit-tested.
class Progress {
  final StudyPlan plan;
  final List<bool> _done; // index = verse id
  final List<Completion> completions; // current journey only, chronological
  int _frontierStudy = 0;
  int _completedCount = 0;

  Progress(this.plan, Iterable<Completion> all)
    : _done = List<bool>.filled(plan.totalVerses + 1, false),
      completions = (all.toList()..sort((a, b) => a.completedAt.compareTo(b.completedAt))) {
    for (final c in completions) {
      _mark(c.startId, c.endId);
    }
    _advanceFrontier();
  }

  void _mark(int a, int b) {
    final lo = a.clamp(1, plan.totalVerses), hi = b.clamp(1, plan.totalVerses);
    for (var v = lo; v <= hi; v++) {
      if (!_done[v]) {
        _done[v] = true;
        _completedCount++;
      }
    }
  }

  void _advanceFrontier() {
    while (_frontierStudy < plan.length && isStudyComplete(plan.studies[_frontierStudy])) {
      _frontierStudy++;
    }
  }

  /// Record a completion (returns false if it added no new verses, i.e. a
  /// re-read; re-reads are still allowed, they just don't change progress).
  bool add(Completion c) {
    final before = _completedCount;
    completions.add(c);
    _mark(c.startId, c.endId);
    _advanceFrontier();
    return _completedCount > before;
  }

  bool isVerseComplete(int id) => id >= 1 && id < _done.length && _done[id];
  bool isStudyComplete(Study s) {
    for (var v = s.startId; v <= s.endId; v++) {
      if (!_done[v]) return false;
    }
    return true;
  }

  int get completedVerses => _completedCount;
  double get fraction => _completedCount / plan.totalVerses;
  bool get journeyComplete => _frontierStudy >= plan.length;

  /// The next study to read: the first study (in mushaf order) that still
  /// has an unread verse. Never skips verses, regardless of missed days.
  Study? get nextStudy => journeyComplete ? null : plan.studies[_frontierStudy];

  /// The next [n] unread studies starting from the frontier.
  List<Study> upcoming(int n) {
    final out = <Study>[];
    for (var i = _frontierStudy; i < plan.length && out.length < n; i++) {
      if (!isStudyComplete(plan.studies[i])) out.add(plan.studies[i]);
    }
    return out;
  }

  /// Completions recorded on the local calendar day of [now] that advanced
  /// the journey (distinct studies, in order of completion).
  List<Completion> completedOn(DateTime now) {
    final seen = <String>{};
    final out = <Completion>[];
    for (final c in completions) {
      final d = c.completedAt;
      if (d.year == now.year && d.month == now.month && d.day == now.day) {
        if (seen.add('${c.startId}-${c.endId}')) out.add(c);
      }
    }
    return out;
  }

  /// Today's sessions. Slots are filled in order: studies already completed
  /// today first, then the next unread studies. A missed day therefore never
  /// creates a backlog or skips verses: today simply continues from where
  /// the user left off.
  List<TodaySlot> today(List<SessionConfig> sessions, DateTime now) {
    final enabled = sessions.where((s) => s.enabled).toList()
      ..sort((a, b) => a.minutes.compareTo(b.minutes));
    final doneToday = completedOn(now);
    final nowMin = now.hour * 60 + now.minute;
    final pending = upcoming(enabled.length);
    final slots = <TodaySlot>[];
    var pi = 0;
    for (var i = 0; i < enabled.length; i++) {
      final s = enabled[i];
      if (i < doneToday.length) {
        final c = doneToday[i];
        final st = plan.studyForVerse(c.startId);
        slots.add(TodaySlot(s, st, SlotState.done));
      } else if (pi < pending.length) {
        slots.add(TodaySlot(s, pending[pi++], s.minutes <= nowMin ? SlotState.ready : SlotState.upcoming));
      }
    }
    return slots;
  }

  List<SurahProgress> surahProgress(List<Surah> surahs) => [
    for (final s in surahs)
      SurahProgress(s.number, _countDone(s.firstVerseId, s.lastVerseId), s.ayahCount),
  ];

  int _countDone(int a, int b) {
    var n = 0;
    for (var v = a; v <= b; v++) {
      if (_done[v]) n++;
    }
    return n;
  }

  /// Distinct completed studies, most recent first (for "completed" lists).
  List<Study> completedStudies() {
    final seen = <int>{};
    final out = <Study>[];
    for (final c in completions.reversed) {
      final s = plan.studyForVerse(c.startId);
      if (isStudyComplete(s) && seen.add(s.index)) out.add(s);
    }
    return out;
  }
}
