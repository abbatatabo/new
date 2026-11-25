import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../domain/models.dart';
import '../domain/progress.dart';
import '../state/app_state.dart';
import 'common.dart';
import 'study.dart';
import 'theme.dart';

class JourneyScreen extends StatelessWidget {
  final bool standalone;
  const JourneyScreen({super.key, this.standalone = false});

  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    final p = Palette.of(context);
    final t = Theme.of(context).textTheme;
    final sp = st.progress.surahProgress(st.quran.surahs);
    final current = st.progress.nextStudy?.surah;
    final completeSurahs = sp.where((s) => s.complete).length;
    final body = CustomScrollView(slivers: [
      SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.fromLTRB(20, standalone ? 8 : 24, 20, 8),
          child: Text('Your journey', style: t.headlineMedium),
        ),
      ),
      SliverToBoxAdapter(
        child: Surface(
          margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(children: [
            ProgressRing(
              value: st.progress.fraction,
              size: 104,
              stroke: 7,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text('${(st.progress.fraction * 100).toStringAsFixed(1)}%', style: sans(20, weight: FontWeight.w600, color: p.ink)),
                Text('of the Quran', style: sans(11, color: p.inkFaint)),
              ]),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _stat(context, formatInt(st.progress.completedVerses), 'verses studied'),
                const SizedBox(height: 10),
                _stat(context, '$completeSurahs', 'surahs completed'),
                const SizedBox(height: 10),
                _stat(context, formatInt(st.progress.completedStudies().length), 'of ${formatInt(st.plan.length)} studies'),
              ]),
            ),
          ]),
        ),
      ),
      if (st.settings.journey > 1)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: Text('Journey ${st.settings.journey}', style: t.bodySmall),
          ),
        ),
      SliverToBoxAdapter(child: SectionLabel('All 114 surahs')),
      SliverList.builder(
        itemCount: st.quran.surahs.length,
        itemBuilder: (c, i) => _SurahRow(surah: st.quran.surahs[i], progress: sp[i], current: current == i + 1),
      ),
      const SliverToBoxAdapter(child: SizedBox(height: 32)),
    ]);
    if (!standalone) return SafeArea(bottom: false, child: body);
    return Scaffold(appBar: AppBar(), body: body);
  }

  Widget _stat(BuildContext c, String n, String label) {
    final p = Palette.of(c);
    return Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
      Text(n, style: serif(22, weight: FontWeight.w500, color: p.ink)),
      const SizedBox(width: 6),
      Flexible(child: Text(label, style: sans(13, color: p.inkSoft))),
    ]);
  }
}

class _SurahRow extends StatelessWidget {
  final Surah surah;
  final SurahProgress progress;
  final bool current;
  const _SurahRow({required this.surah, required this.progress, required this.current});

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return InkWell(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => SurahStudiesScreen(surah: surah))),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        color: current ? p.accentSoft.withValues(alpha: 0.6) : null,
        child: Row(children: [
          SizedBox(
            width: 38,
            height: 38,
            child: Stack(alignment: Alignment.center, children: [
              ProgressRing(value: progress.fraction, size: 38, stroke: 3),
              progress.complete
                  ? Icon(Icons.check, size: 16, color: p.accent)
                  : Text('${surah.number}', style: sans(12, weight: FontWeight.w600, color: p.inkSoft)),
            ]),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(child: Text(surah.nameTranslit, style: sans(15.5, weight: FontWeight.w600, color: p.ink))),
                if (current) ...[const SizedBox(width: 8), Tag('Now', color: p.onAccent, background: p.accent)],
              ]),
              const SizedBox(height: 2),
              Text('${surah.nameEn} · ${surah.ayahCount} verses'
                  '${progress.started && !progress.complete ? ' · ${progress.completedVerses} studied' : ''}',
                  style: sans(12.5, color: p.inkFaint)),
            ]),
          ),
          Text(surah.nameAr, style: arabicUi(20, p.inkSoft)),
        ]),
      ),
    );
  }
}

/// Studies inside one surah: completed, current and upcoming.
class SurahStudiesScreen extends StatelessWidget {
  final Surah surah;
  const SurahStudiesScreen({super.key, required this.surah});

  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    final p = Palette.of(context);
    final studies = st.plan.studies.where((s) => s.surah == surah.number).toList();
    final next = st.progress.nextStudy;
    return Scaffold(
      appBar: AppBar(title: Text(surah.nameTranslit)),
      body: ListView(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
          child: Row(children: [
            Expanded(
              child: Text('${surah.nameEn} · ${surah.revelationType} · ${surah.ayahCount} verses · ${studies.length} studies',
                  style: Theme.of(context).textTheme.bodyMedium),
            ),
            Text(surah.nameAr, style: arabicUi(24, p.inkSoft)),
          ]),
        ),
        const SizedBox(height: 8),
        for (final s in studies)
          ListTile(
            leading: Icon(
              st.progress.isStudyComplete(s)
                  ? Icons.check_circle
                  : s == next
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
              color: st.progress.isStudyComplete(s) || s == next ? p.accent : p.inkFaint,
            ),
            title: Text('Verses ${s.startAyah}${s.endAyah != s.startAyah ? '–${s.endAyah}' : ''}'),
            subtitle: Text(st.progress.isStudyComplete(s)
                ? 'Completed'
                : s == next
                    ? 'Next study'
                    : 'Available to read ahead'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(StudyScreen.route(s)),
          ),
      ]),
    );
  }
}
