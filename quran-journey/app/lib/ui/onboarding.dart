import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../config/brand.dart';
import '../data/settings.dart';
import '../domain/progress.dart';
import '../state/app_state.dart';
import 'common.dart';
import 'theme.dart';

class OnboardingFlow extends StatefulWidget {
  const OnboardingFlow({super.key});
  @override
  State<OnboardingFlow> createState() => _OnboardingFlowState();
}

class _OnboardingFlowState extends State<OnboardingFlow> {
  final _page = PageController();
  int _i = 0;
  static const _count = 5;

  void _next() {
    if (_i < _count - 1) {
      _page.nextPage(duration: const Duration(milliseconds: 380), curve: Curves.easeOutCubic);
    }
  }

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 8, 0),
            child: Row(children: [
              for (var k = 0; k < _count; k++)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  margin: const EdgeInsets.only(right: 6),
                  width: k == _i ? 22 : 7,
                  height: 7,
                  decoration: BoxDecoration(color: k <= _i ? p.accent : p.line, borderRadius: BorderRadius.circular(7)),
                ),
              const Spacer(),
              if (_i > 0)
                TextButton(
                  onPressed: () => _page.previousPage(duration: const Duration(milliseconds: 300), curve: Curves.easeOut),
                  child: const Text('Back'),
                ),
            ]),
          ),
          Expanded(
            child: PageView(
              controller: _page,
              physics: const NeverScrollableScrollPhysics(),
              onPageChanged: (i) => setState(() => _i = i),
              children: [
                _Intro(onNext: _next),
                _Schedule(onNext: _next),
                _Preferences(onNext: _next),
                _Notifications(onNext: _next),
                const _Begin(),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}

class _Page extends StatelessWidget {
  final List<Widget> children;
  final Widget action;
  const _Page({required this.children, required this.action});
  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Expanded(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
        ),
      ),
      Padding(padding: const EdgeInsets.fromLTRB(24, 0, 24, 20), child: action),
    ]);
  }
}

class _Intro extends StatelessWidget {
  final VoidCallback onNext;
  const _Intro({required this.onNext});
  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final t = Theme.of(context).textTheme;
    return _Page(
      action: FilledButton(onPressed: onNext, child: const Text('Begin')),
      children: [
        const SizedBox(height: 24),
        const BrandMark(size: 76),
        const SizedBox(height: 36),
        Text(Brand.appName, style: sans(14, weight: FontWeight.w600, color: p.inkSoft, spacing: 0.4)),
        const SizedBox(height: 10),
        Text('3 verses.\n3 moments.\nEvery day.', style: t.displaySmall),
        const SizedBox(height: 20),
        Text(
          'A calm, guided journey through the Quran, from Al-Fatihah to An-Nas. Each session brings you the next few '
          'verses to read, understand and reflect on.',
          style: t.bodyLarge?.copyWith(color: p.inkSoft),
        ),
        const SizedBox(height: 20),
        Text('No ads. No streaks. No pressure. Miss a day and your journey simply waits for you.', style: t.bodyMedium),
      ],
    );
  }
}

class _Schedule extends StatelessWidget {
  final VoidCallback onNext;
  const _Schedule({required this.onNext});
  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    final p = Palette.of(context);
    final t = Theme.of(context).textTheme;
    void save(SessionConfig s) => st.updateSettings(
      st.settings.copyWith(sessions: st.settings.sessions.map((x) => x.id == s.id ? s : x).toList()),
    );
    return _Page(
      action: FilledButton(onPressed: onNext, child: const Text('Continue')),
      children: [
        Text('Your three moments', style: t.headlineMedium),
        const SizedBox(height: 10),
        Text('Pick times that already have a little space in them. You can change these whenever you like.',
            style: t.bodyMedium),
        const SizedBox(height: 24),
        for (final s in st.settings.sessions)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Surface(
              margin: EdgeInsets.zero,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              onTap: () async {
                final r = await showTimePicker(context: context, initialTime: TimeOfDay(hour: s.minutes ~/ 60, minute: s.minutes % 60));
                if (r != null) save(s.copyWith(minutes: r.hour * 60 + r.minute, enabled: true));
              },
              child: Row(children: [
                Icon(switch (s.id) {
                  'morning' => Icons.wb_twilight_outlined,
                  'afternoon' => Icons.wb_sunny_outlined,
                  _ => Icons.nightlight_outlined,
                }, color: p.accent),
                const SizedBox(width: 14),
                Expanded(child: Text(s.label, style: sans(16, weight: FontWeight.w600, color: p.ink))),
                Text(s.timeLabel, style: serif(22, color: s.enabled ? p.ink : p.inkFaint)),
                const SizedBox(width: 10),
                Switch(value: s.enabled, onChanged: (v) => save(s.copyWith(enabled: v))),
              ]),
            ),
          ),
      ],
    );
  }
}

class _Preferences extends StatelessWidget {
  final VoidCallback onNext;
  const _Preferences({required this.onNext});
  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    final p = Palette.of(context);
    final t = Theme.of(context).textTheme;
    final set = st.settings;
    return _Page(
      action: FilledButton(onPressed: onNext, child: const Text('Continue')),
      children: [
        Text('Reading comfort', style: t.headlineMedium),
        const SizedBox(height: 18),
        Surface(
          margin: EdgeInsets.zero,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            QuranText('ٱلْحَمْدُ لِلَّهِ رَبِّ ٱلْعَـٰلَمِينَ', size: 28 * set.arabicScale, align: TextAlign.center),
            if (set.showTransliteration)
              const Center(child: TransliterationText('Al<u>h</u>amdu lill<u>a</u>hi rabbi alAA<u>a</u>lameen<b>a</b>')),
            const SizedBox(height: 6),
            Text(
              set.translationId == 1 ? 'Praise be to Allah, Lord of the Worlds,' : 'Praise be to Allah, the Cherisher and Sustainer of the worlds;',
              textAlign: TextAlign.center,
              style: serif(17, color: p.ink),
            ),
          ]),
        ),
        const SizedBox(height: 18),
        Text('Arabic size', style: t.titleSmall),
        Slider(value: set.arabicScale, min: 0.8, max: 1.8, divisions: 10, onChanged: (v) => st.updateSettings(set.copyWith(arabicScale: v))),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Show transliteration'),
          value: set.showTransliteration,
          onChanged: (v) => st.updateSettings(set.copyWith(showTransliteration: v)),
        ),
        const SizedBox(height: 8),
        Text('Translation', style: t.titleSmall),
        const SizedBox(height: 8),
        SegmentedButton<int>(
          showSelectedIcon: false,
          segments: [for (final tr in st.quran.englishTranslations) ButtonSegment(value: tr.id, label: Text(tr.name))],
          selected: {set.translationId},
          onSelectionChanged: (s) => st.updateSettings(set.copyWith(translationId: s.first)),
        ),
        const SizedBox(height: 18),
        Text('Theme', style: t.titleSmall),
        const SizedBox(height: 8),
        SegmentedButton<ThemePref>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: ThemePref.system, label: Text('System')),
            ButtonSegment(value: ThemePref.light, label: Text('Light')),
            ButtonSegment(value: ThemePref.dark, label: Text('Dark')),
          ],
          selected: {set.theme},
          onSelectionChanged: (s) => st.updateSettings(set.copyWith(theme: s.first)),
        ),
      ],
    );
  }
}

class _Notifications extends StatelessWidget {
  final VoidCallback onNext;
  const _Notifications({required this.onNext});
  @override
  Widget build(BuildContext context) {
    final st = context.read<AppState>();
    final p = Palette.of(context);
    final t = Theme.of(context).textTheme;
    return _Page(
      action: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        FilledButton(
          onPressed: () async {
            await st.requestNotificationPermission();
            onNext();
          },
          child: const Text('Allow gentle reminders'),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () async {
            await st.updateSettings(st.settings.copyWith(notifications: st.settings.notifications.copyWith(enabled: false)));
            onNext();
          },
          child: const Text('Not now'),
        ),
      ]),
      children: [
        Text('A quiet nudge', style: t.headlineMedium),
        const SizedBox(height: 10),
        Text('At each of your times, a short reminder lets you know your next verses are ready. That is all: no '
            'counting, no guilt.', style: t.bodyMedium),
        const SizedBox(height: 24),
        Surface(
          margin: EdgeInsets.zero,
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(color: p.accent, borderRadius: BorderRadius.circular(10)),
              child: Padding(padding: const EdgeInsets.all(6), child: BrandMark(color: p.onAccent, gapColor: p.accent)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Morning · ${Brand.appName}', style: sans(13.5, weight: FontWeight.w600, color: p.ink)),
                const SizedBox(height: 2),
                Text('Your next 3 verses are ready.', style: sans(13.5, color: p.inkSoft)),
              ]),
            ),
          ]),
        ),
        const SizedBox(height: 16),
        Text('Reading never requires notifications. You can pause reminders, set quiet hours or turn them off at any time.',
            style: t.bodySmall),
      ],
    );
  }
}

class _Begin extends StatelessWidget {
  const _Begin();
  @override
  Widget build(BuildContext context) {
    final st = context.read<AppState>();
    final p = Palette.of(context);
    final t = Theme.of(context).textTheme;
    final fatihah = st.quran.surah(1);
    return _Page(
      action: FilledButton(
        onPressed: () => st.updateSettings(st.settings.copyWith(onboarded: true)),
        child: const Text('Start my journey'),
      ),
      children: [
        const SizedBox(height: 12),
        Text('Your journey begins with', style: t.bodyLarge?.copyWith(color: p.inkSoft)),
        const SizedBox(height: 14),
        Text(fatihah.nameAr, style: arabicUi(48, p.accent)),
        Text('Al-Fatihah', style: t.displaySmall),
        Text('The Opening · ${fatihah.ayahCount} verses', style: t.bodyMedium),
        const SizedBox(height: 28),
        Text(
          'From here the journey goes through all 114 surahs in order, a few verses at a time, until An-Nas. Each '
          'study has the Arabic text, transliteration, translation, word-by-word analysis, context, tafsir sources '
          'and space for your own reflections.',
          style: t.bodyMedium,
        ),
      ],
    );
  }
}
