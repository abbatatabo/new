import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../config/brand.dart';
import '../domain/schedule.dart';
import '../domain/progress.dart';

enum PermissionState { granted, denied, unknown }

/// Local scheduled reminders. Reminders do not depend on a server or
/// network. Delivery time is decided by the OS: by default Android may
/// batch "inexact" alarms by a few minutes; with "Precise timing" enabled
/// (and the exact-alarm permission granted) they are scheduled exactly, but
/// the OS can still delay them in battery saver / Doze.
class NotificationService {
  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  final StreamController<String> _taps = StreamController.broadcast();
  String? _timezoneId;
  bool _ready = false;

  Stream<String> get taps => _taps.stream;
  String? get timezoneId => _timezoneId;

  static const _channelId = 'study_sessions';
  static const _quietChannelId = 'study_sessions_quiet';

  Future<String?> init() async {
    tzdata.initializeTimeZones();
    await refreshTimezone();
    const android = AndroidInitializationSettings('@drawable/ic_stat_journey');
    const darwin = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    await _plugin.initialize(
      settings: const InitializationSettings(android: android, iOS: darwin),
      onDidReceiveNotificationResponse: (r) {
        final p = r.payload;
        if (p != null && p.isNotEmpty) _taps.add(p);
      },
    );
    _ready = true;
    final launch = await _plugin.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp == true) {
      return launch!.notificationResponse?.payload;
    }
    return null;
  }

  /// Returns true when the device time zone changed since last check.
  Future<bool> refreshTimezone() async {
    String id;
    try {
      id = (await FlutterTimezone.getLocalTimezone()).identifier;
    } catch (_) {
      id = 'UTC';
    }
    final changed = _timezoneId != null && _timezoneId != id;
    _timezoneId = id;
    try {
      tz.setLocalLocation(tz.getLocation(id));
    } catch (_) {
      tz.setLocalLocation(tz.UTC);
    }
    return changed;
  }

  Future<PermissionState> permission() async {
    if (!_ready) return PermissionState.unknown;
    if (Platform.isAndroid) {
      final a = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      final ok = await a?.areNotificationsEnabled();
      return ok == null ? PermissionState.unknown : (ok ? PermissionState.granted : PermissionState.denied);
    }
    if (Platform.isIOS) {
      final i = _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
      final o = await i?.checkPermissions();
      if (o == null) return PermissionState.unknown;
      return o.isEnabled ? PermissionState.granted : PermissionState.denied;
    }
    return PermissionState.unknown;
  }

  Future<bool> requestPermission() async {
    if (Platform.isAndroid) {
      final a = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      return await a?.requestNotificationsPermission() ?? false;
    }
    if (Platform.isIOS) {
      final i = _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
      return await i?.requestPermissions(alert: true, sound: true, badge: false) ?? false;
    }
    return false;
  }

  Future<bool> canScheduleExact() async {
    if (!Platform.isAndroid) return true;
    final a = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    return await a?.canScheduleExactNotifications() ?? false;
  }

  Future<void> requestExactAlarms() async {
    if (!Platform.isAndroid) return;
    final a = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await a?.requestExactAlarmsPermission();
  }

  /// Cancels everything and schedules the next 7 days (≤ 21 requests, well
  /// within iOS' 64 pending-notification limit). Called on launch, resume,
  /// schedule/prefs change, progress change and time-zone change.
  Future<int> reschedule({
    required List<SessionConfig> sessions,
    required NotificationPrefs prefs,
    required String Function(PlannedReminder r) bodyFor,
    required String Function(PlannedReminder r) payloadFor,
  }) async {
    if (!_ready) return 0;
    await _plugin.cancelAll();
    final plan = planReminders(sessions: sessions, prefs: prefs, now: DateTime.now());
    if (plan.isEmpty) return 0;
    final exact = prefs.preciseTiming && await canScheduleExact();
    var n = 0;
    for (final r in plan) {
      final when = tz.TZDateTime(
        tz.local,
        r.day.year,
        r.day.month,
        r.day.day,
        r.session.minutes ~/ 60,
        r.session.minutes % 60,
      );
      if (!when.isAfter(tz.TZDateTime.now(tz.local))) continue;
      final details = NotificationDetails(
        android: AndroidNotificationDetails(
          r.quiet ? _quietChannelId : _channelId,
          r.quiet ? 'Study reminders (quiet hours)' : 'Study reminders',
          channelDescription: 'Gentle reminders for your daily Quran study sessions',
          importance: r.quiet ? Importance.low : Importance.defaultImportance,
          priority: r.quiet ? Priority.low : Priority.defaultPriority,
          playSound: !r.quiet,
          enableVibration: !r.quiet,
          category: AndroidNotificationCategory.reminder,
          styleInformation: const BigTextStyleInformation(''),
        ),
        iOS: DarwinNotificationDetails(
          presentSound: !r.quiet,
          interruptionLevel: r.quiet ? InterruptionLevel.passive : InterruptionLevel.active,
          threadIdentifier: 'study_sessions',
        ),
      );
      try {
        await _plugin.zonedSchedule(
          id: r.id,
          scheduledDate: when,
          notificationDetails: details,
          androidScheduleMode: exact
              ? AndroidScheduleMode.exactAllowWhileIdle
              : AndroidScheduleMode.inexactAllowWhileIdle,
          title: '${r.session.label} · ${Brand.appName}',
          body: bodyFor(r),
          payload: payloadFor(r),
        );
        n++;
      } catch (e) {
        debugPrint('Failed to schedule ${r.id}: $e');
      }
    }
    return n;
  }

  Future<int> pendingCount() async => (await _plugin.pendingNotificationRequests()).length;

  Future<void> cancelAll() => _plugin.cancelAll();
}
