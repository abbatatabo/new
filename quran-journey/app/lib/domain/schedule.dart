import 'progress.dart';

enum NotificationStyle { gentle, verse }

class NotificationPrefs {
  final bool enabled;
  final NotificationStyle style;
  final DateTime? pausedUntil;
  final bool quietHoursEnabled;
  final int quietStart; // minutes after midnight
  final int quietEnd;
  final bool preciseTiming;

  const NotificationPrefs({
    this.enabled = true,
    this.style = NotificationStyle.gentle,
    this.pausedUntil,
    this.quietHoursEnabled = false,
    this.quietStart = 22 * 60,
    this.quietEnd = 6 * 60,
    this.preciseTiming = false,
  });

  NotificationPrefs copyWith({
    bool? enabled,
    NotificationStyle? style,
    DateTime? pausedUntil,
    bool clearPause = false,
    bool? quietHoursEnabled,
    int? quietStart,
    int? quietEnd,
    bool? preciseTiming,
  }) => NotificationPrefs(
    enabled: enabled ?? this.enabled,
    style: style ?? this.style,
    pausedUntil: clearPause ? null : (pausedUntil ?? this.pausedUntil),
    quietHoursEnabled: quietHoursEnabled ?? this.quietHoursEnabled,
    quietStart: quietStart ?? this.quietStart,
    quietEnd: quietEnd ?? this.quietEnd,
    preciseTiming: preciseTiming ?? this.preciseTiming,
  );

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'style': style.name,
    'pausedUntil': pausedUntil?.millisecondsSinceEpoch,
    'quietHoursEnabled': quietHoursEnabled,
    'quietStart': quietStart,
    'quietEnd': quietEnd,
    'preciseTiming': preciseTiming,
  };

  factory NotificationPrefs.fromJson(Map<String, dynamic> j) => NotificationPrefs(
    enabled: j['enabled'] as bool? ?? true,
    style: NotificationStyle.values.firstWhere(
      (s) => s.name == j['style'],
      orElse: () => NotificationStyle.gentle,
    ),
    pausedUntil: j['pausedUntil'] == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(j['pausedUntil'] as int),
    quietHoursEnabled: j['quietHoursEnabled'] as bool? ?? false,
    quietStart: j['quietStart'] as int? ?? 22 * 60,
    quietEnd: j['quietEnd'] as int? ?? 6 * 60,
    preciseTiming: j['preciseTiming'] as bool? ?? false,
  );

  bool isPausedAt(DateTime t) => pausedUntil != null && t.isBefore(pausedUntil!);

  /// Quiet hours may wrap midnight (e.g. 22:00–06:00).
  bool isQuietAt(int minutes) {
    if (!quietHoursEnabled || quietStart == quietEnd) return false;
    if (quietStart < quietEnd) return minutes >= quietStart && minutes < quietEnd;
    return minutes >= quietStart || minutes < quietEnd;
  }
}

class PlannedReminder {
  final int id; // stable notification id
  final SessionConfig session;
  final DateTime day; // local date (midnight)
  final bool quiet; // delivered silently
  const PlannedReminder(this.id, this.session, this.day, this.quiet);
}

/// Gentle, non-guilt reminder texts. Rotated deterministically by day.
const gentleMessages = [
  'Your next 3 verses are ready.',
  "Pause and reflect on Allah's words.",
  'Your Quran journey continues.',
  "Take a few minutes to understand today's verses.",
  'A quiet moment with the Quran awaits.',
];

/// Plans the next [days] days of reminders (local wall-clock dates; the
/// notification service converts them to time-zone aware instants so
/// daylight-saving changes are handled by the tz database).
List<PlannedReminder> planReminders({
  required List<SessionConfig> sessions,
  required NotificationPrefs prefs,
  required DateTime now,
  int days = 7,
}) {
  if (!prefs.enabled) return const [];
  final out = <PlannedReminder>[];
  final today = DateTime(now.year, now.month, now.day);
  for (var d = 0; d < days; d++) {
    final day = DateTime(today.year, today.month, today.day + d);
    for (var i = 0; i < sessions.length; i++) {
      final s = sessions[i];
      if (!s.enabled) continue;
      final at = DateTime(day.year, day.month, day.day, s.minutes ~/ 60, s.minutes % 60);
      if (!at.isAfter(now)) continue;
      if (prefs.isPausedAt(at)) continue;
      final id = (day.year % 100) * 100000 + day.month * 3000 + day.day * 10 + i;
      out.add(PlannedReminder(id, s, day, prefs.isQuietAt(s.minutes)));
    }
  }
  return out;
}
