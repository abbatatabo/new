import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/brand.dart';
import '../domain/models.dart';
import '../domain/progress.dart';
import '../domain/schedule.dart';
import '../data/settings.dart';
import '../services/audio_service.dart';
import '../services/notification_service.dart';
import '../state/app_state.dart';
import 'common.dart';
import 'theme.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    final t = Theme.of(context).textTheme;
    final set = st.settings;
    final n = set.notifications;
    final paused = n.pausedUntil != null && n.pausedUntil!.isAfter(DateTime.now());
    return SafeArea(
      bottom: false,
      child: ListView(children: [
        Padding(padding: const EdgeInsets.fromLTRB(20, 24, 20, 4), child: Text('You', style: t.headlineMedium)),
        SectionLabel('Daily schedule'),
        for (final s in set.sessions) _SessionTile(session: s),
        SectionLabel('Reminders'),
        if (st.notificationPermission == PermissionState.denied)
          Surface(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Notifications are off for this app', style: t.titleSmall),
              const SizedBox(height: 4),
              Text('Reading works without them. To get gentle reminders, allow notifications in system settings.',
                  style: t.bodyMedium),
              TextButton(onPressed: st.requestNotificationPermission, child: const Text('Allow reminders')),
            ]),
          ),
        SwitchListTile(
          title: const Text('Study reminders'),
          subtitle: const Text('Local notifications at your session times'),
          value: n.enabled,
          onChanged: (v) async {
            if (v && st.notificationPermission != PermissionState.granted) await st.requestNotificationPermission();
            await st.updateSettings(set.copyWith(notifications: n.copyWith(enabled: v)));
          },
        ),
        ListTile(
          title: const Text('Reminder text'),
          subtitle: Text(n.style == NotificationStyle.gentle ? 'A short, gentle message' : 'The opening of your next verses'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _pickStyle(context),
        ),
        ListTile(
          title: Text(paused ? 'Paused until ${_dt(n.pausedUntil!)}' : 'Pause reminders'),
          subtitle: Text(paused ? 'Tap to resume now' : 'For travel, illness or a break. Progress is kept.'),
          trailing: Icon(paused ? Icons.play_arrow : Icons.pause),
          onTap: () => paused
              ? st.updateSettings(set.copyWith(notifications: n.copyWith(clearPause: true)))
              : _pickPause(context),
        ),
        SwitchListTile(
          title: const Text('Quiet hours'),
          subtitle: Text(n.quietHoursEnabled
              ? 'Silent between ${_hm(n.quietStart)} and ${_hm(n.quietEnd)}'
              : 'Deliver reminders silently at night'),
          value: n.quietHoursEnabled,
          onChanged: (v) => st.updateSettings(set.copyWith(notifications: n.copyWith(quietHoursEnabled: v))),
        ),
        if (n.quietHoursEnabled)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () async {
                    final v = await _pickTime(context, n.quietStart);
                    if (v != null) await st.updateSettings(set.copyWith(notifications: n.copyWith(quietStart: v)));
                  },
                  child: Text('From ${_hm(n.quietStart)}'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton(
                  onPressed: () async {
                    final v = await _pickTime(context, n.quietEnd);
                    if (v != null) await st.updateSettings(set.copyWith(notifications: n.copyWith(quietEnd: v)));
                  },
                  child: Text('Until ${_hm(n.quietEnd)}'),
                ),
              ),
            ]),
          ),
        if (Platform.isAndroid)
          SwitchListTile(
            title: const Text('Precise timing'),
            subtitle: const Text('Ask Android for exact alarms. Without this, reminders may arrive a few minutes late.'),
            value: n.preciseTiming,
            onChanged: (v) async {
              if (v && !await st.notifications.canScheduleExact()) await st.notifications.requestExactAlarms();
              await st.updateSettings(set.copyWith(notifications: n.copyWith(preciseTiming: v)));
            },
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
          child: Text('Reminders are scheduled on this device for the next 7 days and refreshed each time you open the app. '
              'Your phone decides exactly when they are delivered, so battery saving can delay them.', style: t.bodySmall),
        ),
        SectionLabel('Reading'),
        ListTile(
          title: const Text('Translation'),
          subtitle: Text('${st.translation.name} — ${st.translation.translator}'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _pickTranslation(context),
        ),
        SwitchListTile(
          title: const Text('Transliteration'),
          value: set.showTransliteration,
          onChanged: (v) => st.updateSettings(set.copyWith(showTransliteration: v)),
        ),
        ListTile(
          title: const Text('Arabic text size'),
          subtitle: Slider(
            value: set.arabicScale,
            min: 0.8,
            max: 1.8,
            divisions: 10,
            onChanged: (v) => st.updateSettings(set.copyWith(arabicScale: v)),
          ),
        ),
        ListTile(
          title: const Text('Reciter'),
          subtitle: Text(reciters.firstWhere((r) => r.id == set.reciter, orElse: () => reciters.first).name),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _pickReciter(context),
        ),
        ListTile(
          title: const Text('Verses per study'),
          subtitle: Text('${set.versesPerStudy} (default 3). Changing this regroups future studies; verses you have studied stay studied.'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _pickVerses(context),
        ),
        SwitchListTile(
          title: const Text('Online study sources'),
          subtitle: const Text('Load word meanings and classical tafsir from Quran.com when connected (then cached)'),
          value: set.onlineEnrichment,
          onChanged: (v) => st.updateSettings(set.copyWith(onlineEnrichment: v)),
        ),
        SectionLabel('Appearance'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SegmentedButton<ThemePref>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: ThemePref.system, label: Text('System')),
              ButtonSegment(value: ThemePref.light, label: Text('Light')),
              ButtonSegment(value: ThemePref.dark, label: Text('Dark')),
            ],
            selected: {set.theme},
            onSelectionChanged: (s) => st.updateSettings(set.copyWith(theme: s.first)),
          ),
        ),
        SectionLabel('Account & sync'),
        const _AccountSection(),
        SectionLabel('Your data'),
        ListTile(
          leading: const Icon(Icons.file_download_outlined),
          title: const Text('Export my data'),
          subtitle: const Text('Progress, reflections and saved items as JSON'),
          onTap: () => _export(context),
        ),
        ListTile(
          leading: const Icon(Icons.delete_outline),
          title: const Text('Erase data on this device'),
          subtitle: const Text('Removes progress, reflections and saved items here'),
          onTap: () => _erase(context),
        ),
        SectionLabel('About'),
        ListTile(
          leading: const Icon(Icons.fact_check_outlined),
          title: const Text('Sources & methodology'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SourcesScreen())),
        ),
        ListTile(
          leading: const Icon(Icons.privacy_tip_outlined),
          title: const Text('Privacy'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PrivacyScreen())),
        ),
        ListTile(
          leading: const Icon(Icons.info_outline),
          title: Text(Brand.appName),
          subtitle: Text('${Brand.tagline}\nContent version ${st.quran.meta['content_version'] ?? '-'}'),
          isThreeLine: true,
        ),
        const SizedBox(height: 32),
      ]),
    );
  }

  static String _hm(int m) => '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';
  static String _dt(DateTime d) => '${d.day}/${d.month} ${_hm(d.hour * 60 + d.minute)}';

  static Future<int?> _pickTime(BuildContext context, int minutes) async {
    final t = await showTimePicker(context: context, initialTime: TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60));
    return t == null ? null : t.hour * 60 + t.minute;
  }

  Future<void> _pickStyle(BuildContext context) async {
    final st = context.read<AppState>();
    final v = await _choose<NotificationStyle>(context, 'Reminder text', [
      (NotificationStyle.gentle, 'Gentle message', '“Your next 3 verses are ready.”'),
      (NotificationStyle.verse, 'Verse preview', 'The translation of your next study\'s first verse'),
    ], st.settings.notifications.style);
    if (v != null) await st.updateSettings(st.settings.copyWith(notifications: st.settings.notifications.copyWith(style: v)));
  }

  Future<void> _pickPause(BuildContext context) async {
    final st = context.read<AppState>();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final v = await _choose<int>(context, 'Pause reminders', [
      (1, 'Until tomorrow', null),
      (3, 'For 3 days', null),
      (7, 'For a week', null),
      (30, 'For a month', null),
    ], null);
    if (v != null) {
      await st.updateSettings(st.settings.copyWith(
        notifications: st.settings.notifications.copyWith(pausedUntil: DateTime(today.year, today.month, today.day + v)),
      ));
    }
  }

  Future<void> _pickTranslation(BuildContext context) async {
    final st = context.read<AppState>();
    final v = await _choose<int>(context, 'Translation', [
      for (final t in st.quran.englishTranslations) (t.id, t.name, t.translator),
    ], st.settings.translationId);
    if (v != null) await st.updateSettings(st.settings.copyWith(translationId: v));
  }

  Future<void> _pickReciter(BuildContext context) async {
    final st = context.read<AppState>();
    final v = await _choose<String>(context, 'Reciter', [for (final r in reciters) (r.id, r.name, r.style)], st.settings.reciter);
    if (v != null) await st.updateSettings(st.settings.copyWith(reciter: v));
  }

  Future<void> _pickVerses(BuildContext context) async {
    final st = context.read<AppState>();
    final v = await _choose<int>(context, 'Verses per study', [
      (1, '1 verse', 'Slow, focused study'),
      (2, '2 verses', null),
      (3, '3 verses', 'Recommended · uses editorial groupings'),
      (5, '5 verses', 'Long verses still stay short'),
    ], st.settings.versesPerStudy);
    if (v != null) await st.updateSettings(st.settings.copyWith(versesPerStudy: v));
  }

  Future<void> _export(BuildContext context) async {
    final st = context.read<AppState>();
    final data = await st.userDb.exportAll();
    final json = const JsonEncoder.withIndent('  ').convert(data);
    final dir = await getApplicationDocumentsDirectory();
    final f = File(p.join(dir.path, 'quran-journey-export-${DateTime.now().millisecondsSinceEpoch}.json'));
    await f.writeAsString(json);
    await Clipboard.setData(ClipboardData(text: json));
    if (context.mounted) toast(context, 'Export copied to clipboard and saved in the app\'s documents.');
  }

  Future<void> _erase(BuildContext context) async {
    final st = context.read<AppState>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Erase data on this device?'),
        content: const Text('Your progress, reflections and saved items on this device will be removed. '
            'Data already synced to your account is not deleted (use "Delete account" for that).'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Erase')),
        ],
      ),
    );
    if (ok == true) {
      await st.userDb.wipeUserData();
      await st.updateSettings(st.settings.copyWith(journey: 1), rebuild: true);
      if (context.mounted) toast(context, 'Erased');
    }
  }
}

Future<T?> _choose<T>(BuildContext context, String title, List<(T, String, String?)> options, T? current) {
  final p = Palette.of(context);
  return showModalBottomSheet<T>(
    context: context,
    builder: (c) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(padding: const EdgeInsets.fromLTRB(24, 0, 24, 8), child: Text(title, style: Theme.of(c).textTheme.titleLarge)),
        for (final (v, label, sub) in options)
          ListTile(
            title: Text(label),
            subtitle: sub == null ? null : Text(sub),
            trailing: v == current ? Icon(Icons.check, color: p.accent) : null,
            onTap: () => Navigator.pop(c, v),
          ),
        const SizedBox(height: 12),
      ]),
    ),
  );
}

class _SessionTile extends StatelessWidget {
  final SessionConfig session;
  const _SessionTile({required this.session});
  @override
  Widget build(BuildContext context) {
    final st = context.read<AppState>();
    final p = Palette.of(context);
    void save(SessionConfig s) {
      final list = st.settings.sessions.map((x) => x.id == s.id ? s : x).toList();
      st.updateSettings(st.settings.copyWith(sessions: list));
    }

    return ListTile(
      leading: Icon(switch (session.id) {
        'morning' => Icons.wb_twilight_outlined,
        'afternoon' => Icons.wb_sunny_outlined,
        _ => Icons.nightlight_outlined,
      }),
      title: Text(session.label),
      subtitle: Text(session.enabled ? 'Every day at ${session.timeLabel}' : 'Off'),
      onTap: () async {
        final v = await SettingsScreen._pickTime(context, session.minutes);
        if (v != null) save(session.copyWith(minutes: v, enabled: true));
      },
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(session.timeLabel, style: sans(15, weight: FontWeight.w600, color: session.enabled ? p.ink : p.inkFaint)),
        const SizedBox(width: 8),
        Switch(value: session.enabled, onChanged: (v) => save(session.copyWith(enabled: v))),
      ]),
    );
  }
}

class _AccountSection extends StatefulWidget {
  const _AccountSection();
  @override
  State<_AccountSection> createState() => _AccountSectionState();
}

class _AccountSectionState extends State<_AccountSection> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    final t = Theme.of(context).textTheme;
    final set = st.settings;
    if (set.apiBaseUrl.isEmpty) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
          child: Text('No account needed. Everything is stored privately on this device. To sync between devices, '
              'connect a server you run (see the project README).', style: t.bodyMedium),
        ),
        ListTile(
          leading: const Icon(Icons.dns_outlined),
          title: const Text('Connect a sync server'),
          onTap: () => _serverDialog(context),
        ),
      ]);
    }
    if (!st.sync.signedIn) {
      return Column(children: [
        ListTile(leading: const Icon(Icons.dns_outlined), title: const Text('Server'), subtitle: Text(set.apiBaseUrl), onTap: () => _serverDialog(context)),
        ListTile(leading: const Icon(Icons.login), title: const Text('Sign in or create account'), onTap: () => _authDialog(context)),
      ]);
    }
    return Column(children: [
      ListTile(leading: const Icon(Icons.person_outline), title: Text(set.authEmail ?? 'Signed in'), subtitle: Text(set.apiBaseUrl)),
      ListTile(
        leading: st.syncing ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.sync),
        title: const Text('Sync now'),
        subtitle: st.lastSyncMessage == null ? null : Text(st.lastSyncMessage!),
        onTap: st.syncNow,
      ),
      ListTile(
        leading: const Icon(Icons.logout),
        title: const Text('Sign out'),
        subtitle: const Text('Data on this device stays'),
        onTap: () async {
          await st.sync.signOut();
          await st.updateSettings(set.copyWith(signOut: true));
        },
      ),
      ListTile(
        leading: const Icon(Icons.no_accounts_outlined),
        title: const Text('Delete account'),
        subtitle: const Text('Permanently deletes your account and synced data from the server'),
        onTap: _busy ? null : () => _deleteAccount(context),
      ),
    ]);
  }

  Future<void> _serverDialog(BuildContext context) async {
    final st = context.read<AppState>();
    final ctrl = TextEditingController(text: st.settings.apiBaseUrl);
    final v = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Sync server'),
        content: TextField(controller: ctrl, keyboardType: TextInputType.url, decoration: const InputDecoration(hintText: 'https://your-server.example')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, ''), child: const Text('Disconnect')),
          FilledButton(onPressed: () => Navigator.pop(c, ctrl.text.trim()), child: const Text('Save')),
        ],
      ),
    );
    if (v == null) return;
    if (v.isNotEmpty && !v.startsWith('https://')) {
      if (context.mounted) toast(context, 'Use an https:// address.');
      return;
    }
    if (v.isEmpty) await st.sync.signOut();
    await st.updateSettings(st.settings.copyWith(apiBaseUrl: v, signOut: v.isEmpty));
  }

  Future<void> _authDialog(BuildContext context) async {
    final st = context.read<AppState>();
    final email = TextEditingController();
    final pass = TextEditingController();
    final mode = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Account'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: email, keyboardType: TextInputType.emailAddress, autofillHints: const [AutofillHints.email], decoration: const InputDecoration(hintText: 'Email')),
          const SizedBox(height: 10),
          TextField(controller: pass, obscureText: true, autofillHints: const [AutofillHints.password], decoration: const InputDecoration(hintText: 'Password (10+ characters)')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Create account')),
          FilledButton(onPressed: () => Navigator.pop(c, false), child: const Text('Sign in')),
        ],
      ),
    );
    if (mode == null) return;
    setState(() => _busy = true);
    try {
      final e = await st.sync.authenticate(st.settings.apiBaseUrl, email.text.trim(), pass.text, register: mode);
      await st.updateSettings(st.settings.copyWith(authEmail: e));
      await st.syncNow();
    } catch (e) {
      if (context.mounted) toast(context, '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteAccount(BuildContext context) async {
    final st = context.read<AppState>();
    final pass = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Delete account?'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('This permanently deletes your account and all synced data on the server. Data on this device stays.'),
          const SizedBox(height: 10),
          TextField(controller: pass, obscureText: true, decoration: const InputDecoration(hintText: 'Confirm with your password')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await st.sync.deleteAccount(st.settings.apiBaseUrl, pass.text);
      await st.updateSettings(st.settings.copyWith(signOut: true));
      if (context.mounted) toast(context, 'Account deleted');
    } catch (e) {
      if (context.mounted) toast(context, '$e');
    }
  }
}

class SourcesScreen extends StatelessWidget {
  const SourcesScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final st = context.read<AppState>();
    final t = Theme.of(context).textTheme;
    final pal = Palette.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Sources & methodology')),
      body: FutureBuilder<List<SourceInfo>>(
        future: st.quran.sources(),
        builder: (c, s) => ListView(padding: const EdgeInsets.only(bottom: 32), children: [
          SectionLabel('Our commitments'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              '• The Quran text is the Tanzil Uthmani text, copied word for word and never changed. Each build checks it '
              'against its source: 114 surahs, 6,236 verses, the standard Hafs verse counts, and an exact byte-for-byte '
              'comparison.\n'
              '• No Quran text, translation, tafsir, hadith, occasion of revelation or grammar is generated by AI.\n'
              '• Every piece of study content is labelled as a direct quotation, paraphrase, editorial summary or '
              'AI-assisted explanation, and is shown only after it has been reviewed, approved and published.\n'
              '• When reliable content is missing, the app says so instead of filling the gap.',
              style: t.bodyMedium,
            ),
          ),
          SectionLabel('How studies are grouped'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              'Studies run in mushaf order from 1:1 to 114:6 and never cross from one surah into the next. Each study '
              'takes the next ${st.settings.versesPerStudy} verses, but stops early if it would go over ${st.plan.maxWords} '
              'Arabic words, so a long verse such as 2:282 is studied on its own. If the last study of a surah would be '
              'a single verse, it joins the study before it when that stays short enough. A few editorial groupings, '
              'each with a published reason, replace this rule where it would split a passage awkwardly. Progress '
              'counts the verses you have actually completed, not calendar days. Missing a day never skips a verse.\n\n'
              'Current plan: ${formatInt(st.plan.length)} studies covering ${formatInt(st.plan.totalVerses)} verses.',
              style: t.bodyMedium,
            ),
          ),
          SectionLabel('Bundled data'),
          for (final src in s.data ?? const <SourceInfo>[])
            Surface(
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(src.workTitle, style: t.titleSmall),
                Text(src.author, style: t.bodyMedium),
                if (src.edition != null) Text(src.edition!, style: t.bodySmall),
                const SizedBox(height: 6),
                Text('Licence: ${src.license}', style: t.bodySmall),
                Text('Status: ${src.verificationStatus.replaceAll('_', ' ')}', style: t.bodySmall),
                if (src.sha256 != null) Text('SHA-256: ${src.sha256!.substring(0, 16)}…', style: t.bodySmall),
                if (src.url != null)
                  TextButton(
                    style: TextButton.styleFrom(padding: EdgeInsets.zero),
                    onPressed: () => launchUrl(Uri.parse(src.url!), mode: LaunchMode.externalApplication),
                    child: Text(src.url!),
                  ),
              ]),
            ),
          SectionLabel('Loaded online when you choose'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              '• Word-by-word meanings: Quran.com (api.quran.com). Cached on your device after the first load.\n'
              '• Classical tafsir, in the original Arabic: Ibn Kathir, al-Tabari, al-Qurtubi and al-Baghawi, from the '
              'Quran.com digital edition. These works are centuries old and in the public domain. They are shown word '
              'for word, with no translation or summary added.\n'
              '• Recitation audio: EveryAyah.com verse-by-verse recordings, streamed or downloaded.\n'
              '• English tafsir works under copyright are linked, not copied.',
              style: t.bodyMedium,
            ),
          ),
          SectionLabel('Fonts'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text('Amiri Quran and Amiri (Khaled Hosny, SIL Open Font Licence) · Inter · Newsreader (SIL OFL).',
                style: t.bodyMedium?.copyWith(color: pal.inkSoft)),
          ),
          if ((st.quran.meta['arabic_text_sha256'] ?? '').isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Text('Arabic text checksum: ${st.quran.meta['arabic_text_sha256']}', style: t.bodySmall),
            ),
        ]),
      ),
    );
  }
}

class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Privacy')),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        Text(
          'No advertising, analytics or tracking code is included in this app.\n\n'
          'Without an account, your progress, reflections, saved items and settings stay on this device only.\n\n'
          'If you turn on online study sources, the app asks Quran.com for word meanings and tafsir, and EveryAyah.com '
          'for recitation, by verse reference only. Nothing about you is sent.\n\n'
          'If you connect a sync server and create an account, your email address, a securely hashed password, and your '
          'progress, reflections and saved items are stored on that server so they can sync. You can export your data '
          'or permanently delete your account at any time from this screen.\n\n'
          'Sign-in tokens are kept in the device keychain or keystore.',
          style: t.bodyLarge,
        ),
      ]),
    );
  }
}
