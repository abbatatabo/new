import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';

import '../config/brand.dart';

/// Snapshot written for the native home-screen widgets.
/// Keys and meaning: docs/CONTRACTS.md §4.
class WidgetSnapshot {
  final String arabic;
  final String translation;
  final String translationName;
  final String ref;
  final String studyTitle;
  final String studyLink;
  final int progressPermille;
  final String progressLabel;
  final int todayDone;
  final int todayTotal;
  final List<Map<String, dynamic>> sessions;
  final int pausedUntil;
  final int dark;

  const WidgetSnapshot({
    required this.arabic,
    required this.translation,
    required this.translationName,
    required this.ref,
    required this.studyTitle,
    required this.studyLink,
    required this.progressPermille,
    required this.progressLabel,
    required this.todayDone,
    required this.todayTotal,
    required this.sessions,
    required this.pausedUntil,
    required this.dark,
  });

  Map<String, Object> toMap() => {
    'qj_brand': Brand.appName,
    'qj_arabic': arabic,
    'qj_translation': translation,
    'qj_translation_name': translationName,
    'qj_ref': ref,
    'qj_study_title': studyTitle,
    'qj_study_link': studyLink,
    'qj_progress_permille': progressPermille,
    'qj_progress_label': progressLabel,
    'qj_today_done': todayDone,
    'qj_today_total': todayTotal,
    'qj_sessions': jsonEncode(sessions),
    'qj_paused_until': pausedUntil,
    'qj_updated_at': DateTime.now().millisecondsSinceEpoch,
    'qj_dark': dark,
  };
}

/// Instants at which Android widgets should redraw so "Ready"/"Next" labels
/// change at each session time and "done" marks reset after midnight
/// (today + tomorrow, chronological, future only).
List<DateTime> refreshTimes(List<Map<String, dynamic>> sessions, DateTime now) {
  final out = <DateTime>[];
  for (var d = 0; d < 2; d++) {
    final day = DateTime(now.year, now.month, now.day + d);
    out.add(day.add(const Duration(minutes: 1))); // just after midnight
    for (final s in sessions) {
      final m = s['minutes'] as int;
      out.add(DateTime(day.year, day.month, day.day, m ~/ 60, m % 60));
    }
  }
  return out.where((t) => t.isAfter(now)).toList()..sort();
}

class WidgetService {
  String? _lastHash;

  Future<void> init() async {
    if (Platform.isIOS) {
      await HomeWidget.setAppGroupId(Brand.iosAppGroup);
    }
  }

  Stream<Uri?> get clicks => HomeWidget.widgetClicked;
  Future<Uri?> initialLaunch() => HomeWidget.initiallyLaunchedFromHomeWidget();

  /// Writes data and asks the OS to redraw. Widgets also refresh on their
  /// own schedule (Android: every 30 min + at session times computed
  /// natively; iOS: WidgetKit timeline entries at each session time), so
  /// the "next session" label stays correct without the app running.
  Future<void> push(WidgetSnapshot s) async {
    final map = s.toMap();
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final hash = '$today ${jsonEncode({...map}..remove('qj_updated_at'))}';
    if (hash == _lastHash) return;
    _lastHash = hash;
    try {
      for (final e in map.entries) {
        await HomeWidget.saveWidgetData(e.key, e.value);
      }
      if (Platform.isAndroid) {
        final times = refreshTimes(s.sessions, DateTime.now());
        for (final p in Brand.androidWidgetProviders) {
          await HomeWidget.updateWidget(qualifiedAndroidName: p);
          try {
            await HomeWidget.scheduleWidgetUpdates(times, qualifiedAndroidName: p);
          } catch (e) {
            debugPrint('Widget update scheduling failed for $p: $e');
          }
        }
      } else if (Platform.isIOS) {
        await HomeWidget.updateWidget(iOSName: Brand.iosWidgetKind);
      }
    } catch (e) {
      debugPrint('Widget update failed: $e');
    }
  }
}
