import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../config/brand.dart';
import '../domain/models.dart';
import '../domain/progress.dart';
import '../state/app_state.dart';
import 'common.dart';
import 'journey.dart';
import 'study.dart';
import 'theme.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  String _greeting(DateTime now) {
    final h = now.hour;
    if (h < 5) return 'Peaceful night';
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    final p = Palette.of(context);
    final now = DateTime.now();
    final next = st.progress.nextStudy;
    final slots = st.progress.today(st.settings.sessions, now);
    final doneToday = slots.where((s) => s.state == SlotState.done).length;
    final last = st.progress.completions.isEmpty ? null : st.progress.completions.last.completedAt;
    final away = last != null && now.difference(last).inDays >= 3;
    final t = Theme.of(context).textTheme;

    return SafeArea(
      bottom: false,
      child: CustomScrollView(slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
            child: Row(children: [
              const BrandMark(size: 30),
              const SizedBox(width: 10),
              Expanded(child: Text(Brand.appName, style: sans(15, weight: FontWeight.w600, color: p.inkSoft))),
            ]),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 0),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_greeting(now), style: t.headlineMedium),
              const SizedBox(height: 6),
              Text(
                away
                    ? 'Welcome back. Your journey is right where you left it.'
                    : next == null
                        ? 'You have completed the journey through the whole Quran.'
                        : doneToday >= slots.length && slots.isNotEmpty
                            ? "Today's moments are complete. May they stay with you."
                            : Brand.tagline,
                style: t.bodyMedium,
              ),
            ]),
          ),
        ),
        SliverToBoxAdapter(child: const SizedBox(height: 22)),
        if (next != null) SliverToBoxAdapter(child: _NextStudyCard(study: next)),
        if (next == null) SliverToBoxAdapter(child: _CompleteCard()),
        SliverToBoxAdapter(
          child: SectionLabel('Today', trailing: Text('$doneToday of ${slots.length}', style: t.labelMedium)),
        ),
        if (slots.isEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text('No sessions are enabled. You can still read any time, or enable sessions under You ▸ Schedule.',
                  style: t.bodyMedium),
            ),
          ),
        SliverList.separated(
          itemCount: slots.length,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (c, i) => _SlotTile(slot: slots[i]),
        ),
        if (next != null && slots.isNotEmpty && doneToday >= slots.length)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: TextButton.icon(
                onPressed: () => Navigator.of(context).push(StudyScreen.route(next)),
                icon: const Icon(Icons.arrow_forward, size: 18),
                label: Text('Continue to ${st.studyTitle(next)}'),
              ),
            ),
          ),
        SliverToBoxAdapter(child: SectionLabel('Journey')),
        SliverToBoxAdapter(child: _JourneySummary()),
        const SliverToBoxAdapter(child: SizedBox(height: 32)),
      ]),
    );
  }
}

class _NextStudyCard extends StatelessWidget {
  final Study study;
  const _NextStudyCard({required this.study});

  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    final p = Palette.of(context);
    final surah = st.quran.surah(study.surah);
    final started = st.progress.completedVerses > 0;
    return Surface(
      color: p.accent,
      padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
      onTap: () => Navigator.of(context).push(StudyScreen.route(study)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(started ? 'YOUR NEXT STUDY' : 'YOUR JOURNEY BEGINS',
              style: sans(11.5, weight: FontWeight.w700, color: p.onAccent.withValues(alpha: 0.72), spacing: 1.1)),
          const Spacer(),
          Text(surah.nameAr, style: arabicUi(22, p.onAccent)),
        ]),
        const SizedBox(height: 10),
        Text(surah.nameTranslit, style: serif(30, weight: FontWeight.w500, color: p.onAccent, height: 1.1)),
        const SizedBox(height: 4),
        Text('${surah.nameEn} · Verses ${study.startAyah}–${study.endAyah}'.replaceAll('Verses ${study.startAyah}–${study.startAyah}', 'Verse ${study.startAyah}'),
            style: sans(14, color: p.onAccent.withValues(alpha: 0.8))),
        const SizedBox(height: 18),
        FutureBuilder<List<Verse>>(
          future: st.quran.verses(study.startId, study.startId),
          builder: (c, snap) {
            final v = snap.data?.firstOrNull;
            if (v == null) return const SizedBox(height: 56);
            // Quran text is never cut mid-verse: show the whole opening verse
            // when it is short, otherwise just name where the study begins.
            if (v.arabic.length > 90) {
              return Text('Begins at ${surah.nameTranslit} ${v.surah}:${v.ayah}',
                  style: serif(17, color: p.onAccent.withValues(alpha: 0.9), italic: true));
            }
            return Directionality(
              textDirection: TextDirection.rtl,
              child: SizedBox(
                width: double.infinity,
                child: Text(v.arabic, style: quranStyle(24, p.onAccent), softWrap: true),
              ),
            );
          },
        ),
        const SizedBox(height: 14),
        Row(children: [
          Text('${study.verseCount} ${study.verseCount == 1 ? 'verse' : 'verses'} · about ${3 + study.verseCount * 2} min',
              style: sans(13, color: p.onAccent.withValues(alpha: 0.75))),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
            decoration: BoxDecoration(color: p.onAccent, borderRadius: BorderRadius.circular(999)),
            child: Text(started ? 'Continue' : 'Begin', style: sans(14, weight: FontWeight.w600, color: p.accent)),
          ),
        ]),
      ]),
    );
  }
}

class _CompleteCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final st = context.read<AppState>();
    return Surface(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Alhamdulillah', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 6),
        Text('You have studied every verse from Al-Fatihah to An-Nas. Your notes and bookmarks remain. '
            'You may begin the journey again whenever you wish.', style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: 14),
        OutlinedButton(
          onPressed: () async {
            final ok = await showDialog<bool>(
              context: context,
              builder: (c) => AlertDialog(
                title: const Text('Begin a new journey?'),
                content: const Text('Your previous journey is kept in history. Notes and bookmarks are not affected.'),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Not now')),
                  FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Begin again')),
                ],
              ),
            );
            if (ok == true) await st.beginNewJourney();
          },
          child: const Text('Begin a new journey'),
        ),
      ]),
    );
  }
}

class _SlotTile extends StatelessWidget {
  final TodaySlot slot;
  const _SlotTile({required this.slot});

  IconData get _icon => switch (slot.session.id) {
    'morning' => Icons.wb_twilight_outlined,
    'afternoon' => Icons.wb_sunny_outlined,
    _ => Icons.nightlight_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final st = context.read<AppState>();
    final p = Palette.of(context);
    final done = slot.state == SlotState.done;
    final status = switch (slot.state) {
      SlotState.done => 'Completed',
      SlotState.ready => 'Ready',
      SlotState.upcoming => 'At ${slot.session.timeLabel}',
    };
    return Surface(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      onTap: () => Navigator.of(context).push(StudyScreen.route(slot.study)),
      child: Row(children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(color: done ? p.accentSoft : p.surfaceAlt, borderRadius: BorderRadius.circular(12)),
          child: Icon(done ? Icons.check : _icon, color: done ? p.accent : p.inkSoft, size: 21),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(slot.session.label, style: sans(15, weight: FontWeight.w600, color: p.ink)),
            const SizedBox(height: 2),
            Text(st.studyTitle(slot.study), style: sans(13.5, color: p.inkSoft)),
          ]),
        ),
        Text(status,
            style: sans(12.5,
                weight: FontWeight.w600,
                color: slot.state == SlotState.ready ? p.accent : (done ? p.success : p.inkFaint))),
        const SizedBox(width: 4),
        Icon(Icons.chevron_right, color: p.inkFaint, size: 20),
      ]),
    );
  }
}

class _JourneySummary extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    final p = Palette.of(context);
    final next = st.progress.nextStudy;
    final surah = next == null ? null : st.quran.surah(next.surah);
    return Surface(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const JourneyScreen(standalone: true))),
      child: Row(children: [
        ProgressRing(
          value: st.progress.fraction,
          size: 64,
          stroke: 5,
          child: Text('${(st.progress.fraction * 100).toStringAsFixed(st.progress.fraction < 0.1 ? 1 : 0)}%',
              style: sans(13, weight: FontWeight.w600, color: p.ink)),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${formatInt(st.progress.completedVerses)} of ${formatInt(st.plan.totalVerses)} verses',
                style: sans(15, weight: FontWeight.w600, color: p.ink)),
            const SizedBox(height: 3),
            Text(surah == null ? 'Journey complete' : 'Now in ${surah.nameTranslit} · Surah ${surah.number} of 114',
                style: sans(13.5, color: p.inkSoft)),
          ]),
        ),
        Icon(Icons.chevron_right, color: p.inkFaint),
      ]),
    );
  }
}
