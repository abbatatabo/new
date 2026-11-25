import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../domain/models.dart';
import '../state/app_state.dart';
import 'common.dart';
import 'study.dart';
import 'theme.dart';

/// Free reading of a whole surah (does not change journey progress).
class ReaderScreen extends StatefulWidget {
  final int surah;
  final int? ayah;
  const ReaderScreen({super.key, required this.surah, this.ayah});

  static Route<void> route(int surah, {int? ayah}) =>
      MaterialPageRoute(builder: (_) => ReaderScreen(surah: surah, ayah: ayah));

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  late Future<(List<Verse>, Map<int, String>, Map<int, String>)> _f;
  final _scroll = ScrollController();
  final _keys = <int, GlobalKey>{};

  @override
  void initState() {
    super.initState();
    final st = context.read<AppState>();
    final s = st.quran.surah(widget.surah);
    _f = () async {
      final v = await st.quran.verses(s.firstVerseId, s.lastVerseId);
      final t = await st.quran.translationText(st.translation.id, s.firstVerseId, s.lastVerseId);
      final tl = await st.quran.translationText(st.quran.transliteration.id, s.firstVerseId, s.lastVerseId);
      return (v, t, tl);
    }();
    if (widget.ayah != null && widget.ayah! > 1) {
      _f.then((_) => WidgetsBinding.instance.addPostFrameCallback((_) => _jump()));
    }
  }

  void _jump() {
    final k = _keys[widget.ayah];
    if (k?.currentContext != null) {
      Scrollable.ensureVisible(k!.currentContext!, duration: const Duration(milliseconds: 400), alignment: 0.1);
    } else if (_scroll.hasClients) {
      // Items further down are not built yet: approximate, then refine.
      _scroll.jumpTo((widget.ayah! - 1) * 220.0);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final k2 = _keys[widget.ayah];
        if (k2?.currentContext != null) Scrollable.ensureVisible(k2!.currentContext!, alignment: 0.1);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    final p = Palette.of(context);
    final s = st.quran.surah(widget.surah);
    final set = st.settings;
    return Scaffold(
      appBar: AppBar(
        title: Text(s.nameTranslit),
        actions: [
          IconButton(
            tooltip: 'Text size',
            icon: const Icon(Icons.text_fields),
            onPressed: () => showModalBottomSheet<void>(context: context, builder: (_) => const TextSizeSheet()),
          ),
        ],
      ),
      body: FutureBuilder(
        future: _f,
        builder: (c, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator(strokeWidth: 2));
          final (verses, tr, tl) = snap.data!;
          return ListView.builder(
            controller: _scroll,
            itemCount: verses.length + 1,
            itemBuilder: (c, i) {
              if (i == 0) {
                return Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                  child: Column(children: [
                    Text(s.nameAr, style: arabicUi(32, p.ink)),
                    Text('${s.nameEn} · ${s.revelationType} · ${s.ayahCount} verses', style: Theme.of(context).textTheme.bodySmall),
                    if (verses.first.bismillah != null) ...[
                      const SizedBox(height: 14),
                      QuranText(verses.first.bismillah!, size: 24 * set.arabicScale, align: TextAlign.center, color: p.inkSoft),
                    ],
                  ]),
                );
              }
              final v = verses[i - 1];
              final key = _keys.putIfAbsent(v.ayah, GlobalKey.new);
              final study = st.plan.studyForVerse(v.id);
              return Container(
                key: key,
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
                decoration: BoxDecoration(
                  color: widget.ayah == v.ayah ? p.accentSoft.withValues(alpha: 0.6) : null,
                  border: Border(bottom: BorderSide(color: p.line)),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Row(children: [
                    Tag(v.key),
                    const SizedBox(width: 6),
                    if (st.progress.isVerseComplete(v.id)) Icon(Icons.check, size: 15, color: p.accent),
                    const Spacer(),
                    TextButton(
                      onPressed: () => Navigator.of(context).push(StudyScreen.route(study)),
                      child: const Text('Study'),
                    ),
                  ]),
                  Directionality(
                    textDirection: TextDirection.rtl,
                    child: SelectableText.rich(
                      TextSpan(children: [
                        TextSpan(text: v.arabic),
                        TextSpan(text: ' ${ayahMark(v.ayah)}', style: TextStyle(color: p.accent)),
                      ]),
                      style: quranStyle(27 * set.arabicScale, p.ink),
                      textAlign: TextAlign.right,
                    ),
                  ),
                  if (set.showTransliteration) ...[
                    const SizedBox(height: 8),
                    TransliterationText(tl[v.id] ?? '', size: 14 * set.translationScale),
                  ],
                  const SizedBox(height: 8),
                  Text(tr[v.id] ?? '', style: serif(17 * set.translationScale, color: p.ink, height: 1.5)),
                ]),
              );
            },
          );
        },
      ),
    );
  }
}
