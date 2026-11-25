import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/quran_db.dart';
import '../data/settings.dart';
import '../data/user_db.dart';
import '../domain/grouping.dart';
import '../domain/models.dart';
import '../domain/progress.dart';
import '../domain/schedule.dart';
import '../services/audio_service.dart';
import '../services/notification_service.dart';
import '../services/online_content.dart';
import '../services/sync_service.dart';
import '../services/widget_service.dart';

/// Parsed deep link (docs/CONTRACTS.md §3). Query strings (e.g. the
/// `?homeWidget=1` marker iOS widgets add) are ignored.
sealed class AppLink {
  const AppLink();
  static AppLink? parse(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final uri = Uri.tryParse(raw);
    if (uri == null || uri.scheme != 'quranjourney') return null;
    final seg = [uri.host, ...uri.pathSegments].where((s) => s.isNotEmpty).toList();
    if (seg.isEmpty) return const TodayLink();
    switch (seg.first) {
      case 'study':
        if (seg.length < 2) return const NextLink();
        final m = RegExp(r'^(\d+)-(\d+)$').firstMatch(seg[1]);
        if (m == null) return const NextLink();
        return StudyLink(int.parse(m.group(1)!), int.parse(m.group(2)!));
      case 'next':
        return const NextLink();
      case 'verse':
        if (seg.length < 2) return const TodayLink();
        final m = RegExp(r'^(\d+):(\d+)$').firstMatch(seg[1]);
        if (m == null) return const TodayLink();
        return VerseLink(int.parse(m.group(1)!), int.parse(m.group(2)!));
      default:
        return const TodayLink();
    }
  }
}

class StudyLink extends AppLink {
  final int start, end;
  StudyLink(this.start, this.end);
}

class NextLink extends AppLink {
  const NextLink();
}

class TodayLink extends AppLink {
  const TodayLink();
}

class VerseLink extends AppLink {
  final int surah, ayah;
  VerseLink(this.surah, this.ayah);
}

class AppState extends ChangeNotifier {
  final QuranDb quran;
  final UserDb userDb;
  final SettingsStore store;
  final NotificationService notifications;
  final WidgetService widgets;
  final AudioService audio;
  final OnlineContentService online;
  final SyncService sync;

  Settings settings;
  late StudyPlan plan;
  late Progress progress;
  List<GroupingOverride> _bundledOverrides = const [];
  final ValueNotifier<AppLink?> pendingLink = ValueNotifier(null);
  PermissionState notificationPermission = PermissionState.unknown;
  String? lastSyncMessage;
  bool syncing = false;

  AppState._({
    required this.quran,
    required this.userDb,
    required this.store,
    required this.notifications,
    required this.widgets,
    required this.audio,
    required this.online,
    required this.sync,
    required this.settings,
  });

  static Future<AppState> create() async {
    final prefs = await SharedPreferences.getInstance();
    final quran = await QuranDb.open();
    final userDb = await UserDb.open();
    final store = SettingsStore(prefs);
    final s = AppState._(
      quran: quran,
      userDb: userDb,
      store: store,
      notifications: NotificationService(),
      widgets: WidgetService(),
      audio: AudioService(),
      online: OnlineContentService(userDb),
      sync: SyncService(userDb),
      settings: store.load(),
    );
    await s._init();
    return s;
  }

  /// Test harness: real databases, no platform plugins.
  @visibleForTesting
  static Future<AppState> forTesting({
    required QuranDb quran,
    required UserDb userDb,
    required SettingsStore store,
    Settings? settings,
    List<GroupingOverride> overrides = const [],
  }) async {
    final s = AppState._(
      quran: quran,
      userDb: userDb,
      store: store,
      notifications: NotificationService(),
      widgets: WidgetService(),
      audio: AudioService(),
      online: OnlineContentService(userDb),
      sync: SyncService(userDb),
      settings: settings ?? store.load(),
    );
    s._bundledOverrides = overrides;
    s._testing = true;
    await s._rebuildPlan();
    return s;
  }

  bool _testing = false;

  Future<void> _init() async {
    _bundledOverrides = await _loadBundledOverrides();
    await _rebuildPlan();
    await widgets.init();
    final launchPayload = await notifications.init();
    pendingLink.value = AppLink.parse(launchPayload);
    notifications.taps.listen((p) => pendingLink.value = AppLink.parse(p));
    try {
      final w = await widgets.initialLaunch();
      if (w != null) pendingLink.value = AppLink.parse(w.toString());
      widgets.clicks.listen((u) {
        if (u != null) pendingLink.value = AppLink.parse(u.toString());
      });
    } catch (_) {}
    await sync.loadToken();
    notificationPermission = await notifications.permission();
    unawaited(refreshSideEffects());
    unawaited(_backgroundOnline());
  }

  Future<List<GroupingOverride>> _loadBundledOverrides() async {
    try {
      final raw = await rootBundle.loadString('assets/content/groupings.json');
      final j = jsonDecode(raw) as Map<String, dynamic>;
      return (j['groupings'] as List)
          .map((e) => GroupingOverride.fromJson((e as Map).cast<String, dynamic>()))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> _rebuildPlan() async {
    final server = (await userDb.serverGroupings())
        .map(GroupingOverride.fromJson)
        .toList();
    // Server (CMS) overrides take precedence for the surahs they cover.
    final serverSurahs = server.map((g) => g.surah).toSet();
    final overrides = [
      ..._bundledOverrides.where((g) => !serverSurahs.contains(g.surah)),
      ...server,
    ];
    plan = StudyPlan.build(
      surahs: quran.surahs,
      wordCounts: quran.wordCounts,
      overrides: settings.versesPerStudy == 3 ? overrides : const [],
      versesPerStudy: settings.versesPerStudy,
    );
    progress = Progress(plan, await userDb.completions(journey: settings.journey));
  }

  // ------------------------------------------------------------ actions
  Future<void> updateSettings(Settings next, {bool rebuild = false}) async {
    final regroup = rebuild || next.versesPerStudy != settings.versesPerStudy;
    settings = next;
    await store.save(next);
    if (regroup) await _rebuildPlan();
    notifyListeners();
    await refreshSideEffects();
  }

  Future<bool> completeStudy(Study s) async {
    final c = Completion(
      id: newId(),
      startId: s.startId,
      endId: s.endId,
      completedAt: DateTime.now(),
      journey: settings.journey,
    );
    final advanced = progress.add(c);
    await userDb.addCompletion(c);
    notifyListeners();
    unawaited(refreshSideEffects());
    unawaited(syncNow(quiet: true));
    return advanced;
  }

  Future<void> beginNewJourney() async {
    await updateSettings(settings.copyWith(journey: settings.journey + 1), rebuild: true);
  }

  Future<void> onResume() async {
    final tzChanged = await notifications.refreshTimezone();
    notificationPermission = await notifications.permission();
    if (tzChanged) debugPrint('Time zone changed; rescheduling');
    notifyListeners();
    await refreshSideEffects();
    unawaited(_backgroundOnline());
  }

  Future<void> _backgroundOnline() async {
    if (settings.apiBaseUrl.isEmpty) return;
    final n = await sync.fetchPublishedContent(settings.apiBaseUrl);
    if (n > 0) {
      await _rebuildPlan();
      notifyListeners();
    }
    await syncNow(quiet: true);
  }

  Future<void> syncNow({bool quiet = false}) async {
    if (_testing) return;
    if (!sync.signedIn || settings.apiBaseUrl.isEmpty || syncing) return;
    syncing = true;
    if (!quiet) notifyListeners();
    final r = await sync.sync(settings.apiBaseUrl);
    syncing = false;
    lastSyncMessage = r.error ??
        'Synced · ${r.pushed} sent, ${r.pulled} received${r.conflicts > 0 ? ', ${r.conflicts} note conflicts kept as separate notes' : ''}';
    if (r.error == null && r.pulled > 0) {
      progress = Progress(plan, await userDb.completions(journey: settings.journey));
    }
    notifyListeners();
  }

  Future<bool> requestNotificationPermission() async {
    final ok = await notifications.requestPermission();
    notificationPermission = await notifications.permission();
    notifyListeners();
    await refreshSideEffects();
    return ok;
  }

  // -------------------------------------------------------- side effects
  /// Reschedules reminders and refreshes widgets from current state.
  Future<void> refreshSideEffects() async {
    if (_testing) return;
    try {
      await _reschedule();
    } catch (e) {
      debugPrint('reschedule failed: $e');
    }
    try {
      await _pushWidget();
    } catch (e) {
      debugPrint('widget push failed: $e');
    }
  }

  Future<void> _reschedule() async {
    final next = progress.nextStudy;
    String? preview;
    if (next != null && settings.notifications.style == NotificationStyle.verse) {
      final t = await quran.translationText(settings.translationId, next.startId, next.startId);
      final text = t[next.startId] ?? '';
      preview = '${surahName(next.surah)} ${next.refLabel}: ${_clip(text, 140)}';
    }
    await notifications.reschedule(
      sessions: settings.sessions,
      prefs: settings.notifications,
      bodyFor: (r) {
        if (next == null) return 'You completed the Quran journey. Alhamdulillah.';
        if (preview != null) return preview;
        return gentleMessages[(r.day.day + r.session.minutes) % gentleMessages.length];
      },
      payloadFor: (_) => next?.deepLink ?? 'quranjourney://today',
    );
  }

  static String _clip(String s, int n) {
    if (s.length <= n) return s;
    final cut = s.substring(0, n);
    final sp = cut.lastIndexOf(' ');
    return '${cut.substring(0, sp > 40 ? sp : n)}…';
  }

  Future<void> _pushWidget() async {
    final now = DateTime.now();
    final next = progress.nextStudy;
    final tr = quran.englishTranslations.firstWhere(
      (t) => t.id == settings.translationId,
      orElse: () => quran.englishTranslations.first,
    );
    var arabic = '', translation = '', ref = '', title = '', link = 'quranjourney://today';
    if (next != null) {
      final verses = await quran.verses(next.startId, next.endId);
      final texts = await quran.translationText(tr.id, next.startId, next.endId);
      // Feature the shortest verse of the study so it fits a widget without
      // cutting a verse mid-way; long verses show translation with "…".
      verses.sort((a, b) => a.arabic.length.compareTo(b.arabic.length));
      final v = verses.first;
      arabic = v.arabic.length <= 140 ? v.arabic : '';
      translation = _clip(texts[v.id] ?? '', 180);
      ref = '${surahName(v.surah)} ${v.surah}:${v.ayah}';
      title = '${surahName(next.surah)} ${next.refLabel}';
      link = next.deepLink;
    } else {
      title = 'Journey complete';
      translation = 'You have studied the whole Quran. Begin again whenever you wish.';
    }
    final slots = progress.today(settings.sessions, now);
    final doneToday = slots.where((s) => s.state == SlotState.done).length;
    final cur = next == null ? 114 : next.surah;
    await widgets.push(WidgetSnapshot(
      arabic: arabic,
      translation: translation,
      translationName: tr.name,
      ref: ref,
      studyTitle: title,
      studyLink: link,
      progressPermille: (progress.fraction * 1000).floor(),
      progressLabel: '${(progress.fraction * 100).toStringAsFixed(1)}% of the Quran · Surah $cur of 114',
      todayDone: doneToday,
      todayTotal: settings.enabledSessionCount,
      sessions: [
        for (final s in settings.sessions.where((s) => s.enabled))
          {
            'label': s.label,
            'minutes': s.minutes,
            'enabled': s.enabled,
            'done': slots.any((x) => x.session.id == s.id && x.state == SlotState.done),
          },
      ],
      pausedUntil: settings.notifications.pausedUntil?.millisecondsSinceEpoch ?? 0,
      dark: switch (settings.theme) { ThemePref.system => -1, ThemePref.light => 0, ThemePref.dark => 1 },
    ));
  }

  // ------------------------------------------------------------- helpers
  String surahName(int n) => quran.surah(n).nameTranslit;
  String studyTitle(Study s) => '${surahName(s.surah)} ${s.refLabel}';
  TranslationInfo get translation => quran.englishTranslations.firstWhere(
    (t) => t.id == settings.translationId,
    orElse: () => quran.englishTranslations.first,
  );
}
