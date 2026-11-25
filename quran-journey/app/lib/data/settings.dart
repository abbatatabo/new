import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../config/brand.dart';
import '../domain/progress.dart';
import '../domain/schedule.dart';

enum ThemePref { system, light, dark }

class Settings {
  final bool onboarded;
  final List<SessionConfig> sessions;
  final NotificationPrefs notifications;
  final double arabicScale;
  final double translationScale;
  final bool showTransliteration;
  final int translationId;
  final ThemePref theme;
  final int versesPerStudy;
  final int journey;
  final String reciter;
  final bool onlineEnrichment;
  final String apiBaseUrl;
  final String? authToken;
  final String? authEmail;

  const Settings({
    this.onboarded = false,
    this.sessions = SessionConfig.defaults,
    this.notifications = const NotificationPrefs(),
    this.arabicScale = 1.0,
    this.translationScale = 1.0,
    this.showTransliteration = true,
    this.translationId = 1,
    this.theme = ThemePref.system,
    this.versesPerStudy = 3,
    this.journey = 1,
    this.reciter = 'Alafasy_128kbps',
    this.onlineEnrichment = true,
    this.apiBaseUrl = Brand.defaultApiBaseUrl,
    this.authToken,
    this.authEmail,
  });

  Settings copyWith({
    bool? onboarded,
    List<SessionConfig>? sessions,
    NotificationPrefs? notifications,
    double? arabicScale,
    double? translationScale,
    bool? showTransliteration,
    int? translationId,
    ThemePref? theme,
    int? versesPerStudy,
    int? journey,
    String? reciter,
    bool? onlineEnrichment,
    String? apiBaseUrl,
    String? authToken,
    String? authEmail,
    bool signOut = false,
  }) => Settings(
    onboarded: onboarded ?? this.onboarded,
    sessions: sessions ?? this.sessions,
    notifications: notifications ?? this.notifications,
    arabicScale: arabicScale ?? this.arabicScale,
    translationScale: translationScale ?? this.translationScale,
    showTransliteration: showTransliteration ?? this.showTransliteration,
    translationId: translationId ?? this.translationId,
    theme: theme ?? this.theme,
    versesPerStudy: versesPerStudy ?? this.versesPerStudy,
    journey: journey ?? this.journey,
    reciter: reciter ?? this.reciter,
    onlineEnrichment: onlineEnrichment ?? this.onlineEnrichment,
    apiBaseUrl: apiBaseUrl ?? this.apiBaseUrl,
    authToken: signOut ? null : (authToken ?? this.authToken),
    authEmail: signOut ? null : (authEmail ?? this.authEmail),
  );

  int get enabledSessionCount => sessions.where((s) => s.enabled).length;

  Map<String, dynamic> toJson() => {
    'onboarded': onboarded,
    'sessions': sessions.map((s) => s.toJson()).toList(),
    'notifications': notifications.toJson(),
    'arabicScale': arabicScale,
    'translationScale': translationScale,
    'showTransliteration': showTransliteration,
    'translationId': translationId,
    'theme': theme.name,
    'versesPerStudy': versesPerStudy,
    'journey': journey,
    'reciter': reciter,
    'onlineEnrichment': onlineEnrichment,
    'apiBaseUrl': apiBaseUrl,
    // authToken is deliberately NOT persisted here: it lives in the
    // platform keystore (flutter_secure_storage), see SyncService.
    'authEmail': authEmail,
  };

  factory Settings.fromJson(Map<String, dynamic> j) {
    const d = Settings();
    return Settings(
      onboarded: j['onboarded'] as bool? ?? false,
      sessions: (j['sessions'] as List?)
              ?.map((e) => SessionConfig.fromJson((e as Map).cast<String, dynamic>()))
              .toList() ??
          d.sessions,
      notifications: j['notifications'] == null
          ? d.notifications
          : NotificationPrefs.fromJson((j['notifications'] as Map).cast<String, dynamic>()),
      arabicScale: (j['arabicScale'] as num?)?.toDouble() ?? 1.0,
      translationScale: (j['translationScale'] as num?)?.toDouble() ?? 1.0,
      showTransliteration: j['showTransliteration'] as bool? ?? true,
      translationId: j['translationId'] as int? ?? 1,
      theme: ThemePref.values.firstWhere((t) => t.name == j['theme'], orElse: () => ThemePref.system),
      versesPerStudy: j['versesPerStudy'] as int? ?? 3,
      journey: j['journey'] as int? ?? 1,
      reciter: j['reciter'] as String? ?? d.reciter,
      onlineEnrichment: j['onlineEnrichment'] as bool? ?? true,
      apiBaseUrl: j['apiBaseUrl'] as String? ?? Brand.defaultApiBaseUrl,
      authEmail: j['authEmail'] as String?,
    );
  }
}

class SettingsStore {
  static const _key = 'qj_settings_v1';
  final SharedPreferences prefs;
  SettingsStore(this.prefs);

  Settings load() {
    final raw = prefs.getString(_key);
    if (raw == null) return const Settings();
    try {
      return Settings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return const Settings();
    }
  }

  Future<void> save(Settings s) => prefs.setString(_key, jsonEncode(s.toJson()));
}
