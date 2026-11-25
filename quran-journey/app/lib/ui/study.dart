import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../domain/models.dart';
import '../domain/morphology.dart';
import '../services/audio_service.dart';
import '../services/online_content.dart';
import '../state/app_state.dart';
import 'common.dart';
import 'content_badges.dart';
import 'notes.dart';
import 'theme.dart';

class StudyData {
  final List<Verse> verses;
  final Map<int, String> translation;
  final Map<int, String> transliteration;
  final List<Map<String, dynamic>> cms;
  const StudyData(this.verses, this.translation, this.transliteration, this.cms);
}

class StudyScreen extends StatefulWidget {
  final Study study;
  const StudyScreen({super.key, required this.study});

  static Route<void> route(Study s) => MaterialPageRoute(builder: (_) => StudyScreen(study: s));

  @override
  State<StudyScreen> createState() => _StudyScreenState();
}

class _StudyScreenState extends State<StudyScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 5, vsync: this);
  late Future<StudyData> _data;
  bool _bookmarked = false;

  Study get s => widget.study;

  @override
  void initState() {
    super.initState();
    final st = context.read<AppState>();
    _data = _load(st);
    st.userDb.findBookmark(BookmarkType.study, s.startId, s.endId).then((b) {
      if (mounted) setState(() => _bookmarked = b != null);
    });
  }

  Future<StudyData> _load(AppState st) async {
    final verses = await st.quran.verses(s.startId, s.endId);
    final tr = await st.quran.translationText(st.translation.id, s.startId, s.endId);
    final tl = await st.quran.translationText(st.quran.transliteration.id, s.startId, s.endId);
    final cms = await st.userDb.contentFor(s.surah, s.startAyah, s.endAyah);
    return StudyData(verses, tr, tl, cms);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _toggleStudyBookmark() async {
    final st = context.read<AppState>();
    final existing = await st.userDb.findBookmark(BookmarkType.study, s.startId, s.endId);
    if (existing != null) {
      await st.userDb.removeBookmark(existing.id);
    } else {
      await st.userDb.addBookmark(BookmarkType.study, s.startId, s.endId, label: st.studyTitle(s));
    }
    if (!mounted) return;
    setState(() => _bookmarked = existing == null);
    toast(context, existing == null ? 'Study saved' : 'Removed from saved');
    st.syncNow(quiet: true);
  }

  void _textSizeSheet() {
    showModalBottomSheet<void>(context: context, builder: (_) => const TextSizeSheet());
  }

  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    final p = Palette.of(context);
    final surah = st.quran.surah(s.surah);
    return Scaffold(
      appBar: AppBar(
        title: Text(st.studyTitle(s)),
        actions: [
          IconButton(tooltip: 'Text size', onPressed: _textSizeSheet, icon: const Icon(Icons.text_fields)),
          IconButton(
            tooltip: _bookmarked ? 'Remove saved study' : 'Save study',
            onPressed: _toggleStudyBookmark,
            icon: Icon(_bookmarked ? Icons.bookmark : Icons.bookmark_outline, color: _bookmarked ? p.accent : null),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Align(
            alignment: Alignment.centerLeft,
            child: TabBar(
              controller: _tabs,
              isScrollable: true,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              tabs: const [
                Tab(text: 'Read'),
                Tab(text: 'Words'),
                Tab(text: 'Context'),
                Tab(text: 'Tafsir'),
                Tab(text: 'Reflect'),
              ],
            ),
          ),
        ),
      ),
      body: FutureBuilder<StudyData>(
        future: _data,
        builder: (c, snap) {
          if (snap.hasError) {
            return Center(child: Text('Could not load these verses: ${snap.error}'));
          }
          if (!snap.hasData) return const Center(child: CircularProgressIndicator(strokeWidth: 2));
          final d = snap.data!;
          return TabBarView(controller: _tabs, children: [
            _ReadTab(study: s, data: d, surah: surah),
            _WordsTab(study: s, data: d),
            _ContextTab(study: s, data: d, surah: surah),
            _TafsirTab(study: s, data: d),
            _ReflectTab(study: s, data: d),
          ]);
        },
      ),
      bottomNavigationBar: _StudyBottomBar(study: s, dataFuture: _data),
    );
  }
}

// ------------------------------------------------------------------ READ
class _ReadTab extends StatelessWidget {
  final Study study;
  final StudyData data;
  final Surah surah;
  const _ReadTab({required this.study, required this.data, required this.surah});

  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    final p = Palette.of(context);
    final set = st.settings;
    final first = data.verses.first;
    return ValueListenableBuilder<int?>(
      valueListenable: st.audio.currentVerse,
      builder: (context, playing, _) => ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
            child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(surah.nameTranslit, style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 2),
                  Text('${surah.nameEn} · ${surah.revelationType} · ${surah.ayahCount} verses',
                      style: Theme.of(context).textTheme.bodySmall),
                ]),
              ),
              Text(surah.nameAr, style: arabicUi(26, p.inkSoft)),
            ]),
          ),
          if (first.bismillah != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
              child: Center(child: QuranText(first.bismillah!, size: 24 * set.arabicScale, align: TextAlign.center, color: p.inkSoft)),
            ),
          for (final v in data.verses)
            _VerseBlock(
              verse: v,
              translation: data.translation[v.id] ?? '',
              transliteration: data.transliteration[v.id] ?? '',
              playing: playing == v.id,
              onPlay: () => _play(context, v),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: Text(
              'Arabic: Tanzil Uthmani text ${st.quran.meta['tanzil_version'] ?? ''} (verbatim, tanzil.net). '
              'Translation: ${st.translation.translator} (${st.translation.name}). '
              'Transliteration: Tanzil English transliteration.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _play(BuildContext context, Verse v) async {
    final st = context.read<AppState>();
    final ids = data.verses.map((e) => e.id).toList();
    try {
      if (!st.audio.isLoadedFor(ids, st.settings.reciter)) {
        await st.audio.load(
          reciter: st.settings.reciter,
          verseIds: ids,
          keys: data.verses.map((e) => (e.surah, e.ayah)).toList(),
        );
      }
      await st.audio.playFrom(ids.indexOf(v.id));
    } catch (e) {
      if (context.mounted) toast(context, 'Recitation is unavailable offline unless downloaded.');
    }
  }
}

class _VerseBlock extends StatefulWidget {
  final Verse verse;
  final String translation;
  final String transliteration;
  final bool playing;
  final VoidCallback onPlay;
  const _VerseBlock({
    required this.verse,
    required this.translation,
    required this.transliteration,
    required this.playing,
    required this.onPlay,
  });
  @override
  State<_VerseBlock> createState() => _VerseBlockState();
}

class _VerseBlockState extends State<_VerseBlock> {
  bool _saved = false;

  @override
  void initState() {
    super.initState();
    context.read<AppState>().userDb.findBookmark(BookmarkType.verse, widget.verse.id, widget.verse.id).then((b) {
      if (mounted) setState(() => _saved = b != null);
    });
  }

  Future<void> _toggle() async {
    final st = context.read<AppState>();
    final v = widget.verse;
    final b = await st.userDb.findBookmark(BookmarkType.verse, v.id, v.id);
    if (b != null) {
      await st.userDb.removeBookmark(b.id);
    } else {
      await st.userDb.addBookmark(BookmarkType.verse, v.id, v.id, label: '${st.surahName(v.surah)} ${v.key}');
    }
    if (mounted) setState(() => _saved = b == null);
    st.syncNow(quiet: true);
  }

  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    final p = Palette.of(context);
    final set = st.settings;
    final v = widget.verse;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      margin: const EdgeInsets.fromLTRB(12, 16, 12, 0),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 16),
      decoration: BoxDecoration(
        color: widget.playing ? p.accentSoft : Colors.transparent,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Tag(v.key, color: p.accent, background: p.accentSoft),
          if (v.sajdah != null) ...[
            const SizedBox(width: 6),
            Tag('Sajdah (${v.sajdah})', icon: Icons.south),
          ],
          const Spacer(),
          IconButton(
            tooltip: 'Play recitation',
            visualDensity: VisualDensity.compact,
            onPressed: widget.onPlay,
            icon: Icon(widget.playing ? Icons.graphic_eq : Icons.play_circle_outline, color: p.inkSoft),
          ),
          IconButton(
            tooltip: _saved ? 'Remove saved verse' : 'Save verse',
            visualDensity: VisualDensity.compact,
            onPressed: _toggle,
            icon: Icon(_saved ? Icons.bookmark : Icons.bookmark_outline, color: _saved ? p.accent : p.inkSoft),
          ),
        ]),
        const SizedBox(height: 6),
        Directionality(
          textDirection: TextDirection.rtl,
          child: SelectableText.rich(
            TextSpan(children: [
              TextSpan(text: v.arabic),
              TextSpan(text: ' ${ayahMark(v.ayah)}', style: TextStyle(color: p.accent)),
            ]),
            style: quranStyle(29 * set.arabicScale, p.ink),
            textAlign: TextAlign.right,
          ),
        ),
        if (set.showTransliteration && widget.transliteration.isNotEmpty) ...[
          const SizedBox(height: 10),
          TransliterationText(widget.transliteration, size: 14.5 * set.translationScale),
        ],
        const SizedBox(height: 10),
        SelectableText(widget.translation, style: serif(18.5 * set.translationScale, color: p.ink, height: 1.5)),
      ]),
    );
  }
}

class TextSizeSheet extends StatelessWidget {
  const TextSizeSheet({super.key});
  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    final p = Palette.of(context);
    final set = st.settings;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Reading', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          Center(child: QuranText('ٱلْحَمْدُ لِلَّهِ رَبِّ ٱلْعَـٰلَمِينَ', size: 28 * set.arabicScale, align: TextAlign.center)),
          Row(children: [
            Text('Arabic', style: sans(14, color: p.inkSoft)),
            Expanded(
              child: Slider(
                value: set.arabicScale,
                min: 0.8,
                max: 1.8,
                divisions: 10,
                label: '${(set.arabicScale * 100).round()}%',
                onChanged: (v) => st.updateSettings(set.copyWith(arabicScale: v)),
              ),
            ),
          ]),
          Row(children: [
            Text('Translation', style: sans(14, color: p.inkSoft)),
            Expanded(
              child: Slider(
                value: set.translationScale,
                min: 0.85,
                max: 1.5,
                divisions: 13,
                label: '${(set.translationScale * 100).round()}%',
                onChanged: (v) => st.updateSettings(set.copyWith(translationScale: v)),
              ),
            ),
          ]),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Show transliteration'),
            value: set.showTransliteration,
            onChanged: (v) => st.updateSettings(set.copyWith(showTransliteration: v)),
          ),
        ]),
      ),
    );
  }
}

// ----------------------------------------------------------------- WORDS
class _WordsTab extends StatelessWidget {
  final Study study;
  final StudyData data;
  const _WordsTab({required this.study, required this.data});

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: p.surfaceAlt, borderRadius: BorderRadius.circular(14)),
            child: Text(
              'Roots, lemmas and grammatical tags come from the Quranic Arabic Corpus (v0.4, University of Leeds). '
              'Word meanings are Quran.com\'s word-by-word glosses, loaded online once and then kept for offline use. '
              'Glosses are literal aids, not a translation. Syntactic roles (iʿrāb) and contextual meanings are not '
              'included yet, because no reviewed source for them is available.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ),
        for (final v in data.verses) _VerseWords(verse: v),
      ],
    );
  }
}

class _VerseWords extends StatefulWidget {
  final Verse verse;
  const _VerseWords({required this.verse});
  @override
  State<_VerseWords> createState() => _VerseWordsState();
}

class _VerseWordsState extends State<_VerseWords> {
  late Future<(List<Word>, List<WordGloss>?)> _f;

  @override
  void initState() {
    super.initState();
    _f = _load();
  }

  Future<(List<Word>, List<WordGloss>?)> _load() async {
    final st = context.read<AppState>();
    final words = await st.quran.words(widget.verse.id);
    final gl = await st.online.wordGlosses(widget.verse.surah, widget.verse.ayah, allowNetwork: st.settings.onlineEnrichment);
    return (words, gl);
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return FutureBuilder<(List<Word>, List<WordGloss>?)>(
      future: _f,
      builder: (c, snap) {
        final (words, glosses) = snap.data ?? (const <Word>[], null);
        final byPos = {for (final g in glosses ?? const <WordGloss>[]) g.position: g};
        // Only use glosses when their word count matches the corpus words.
        final glossOk = glosses != null && glosses.length == words.length;
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SectionLabel('Verse ${widget.verse.key}',
              trailing: !snap.hasData
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 1.5))
                  : glossOk
                      ? null
                      : TextButton(
                          onPressed: () => setState(() => _f = _load()),
                          child: const Text('Load meanings'),
                        )),
          if (snap.hasData && !glossOk)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text('Word meanings need a one-time connection (or are turned off in settings). '
                  'Morphology below is fully offline.', style: Theme.of(context).textTheme.bodySmall),
            ),
          for (final w in words)
            _WordTile(word: w, gloss: glossOk ? byPos[w.position] : null, p: p),
        ]);
      },
    );
  }
}

class _WordTile extends StatelessWidget {
  final Word word;
  final WordGloss? gloss;
  final Palette p;
  const _WordTile({required this.word, this.gloss, required this.p});

  @override
  Widget build(BuildContext context) {
    final st = context.read<AppState>();
    final arabic = word.arabic ?? Morphology.bwToArabic(word.segments.map((s) => s.formBw).join());
    return Surface(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: EdgeInsets.zero,
          childrenPadding: EdgeInsets.zero,
          shape: const Border(),
          title: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(gloss?.translation ?? '—', style: serif(17, color: p.ink, weight: FontWeight.w500)),
                if (gloss != null && gloss!.transliteration.isNotEmpty)
                  Text(gloss!.transliteration, style: sans(13, color: p.inkSoft).copyWith(fontStyle: FontStyle.italic)),
                const SizedBox(height: 6),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  Tag(Morphology.stemPos(word)),
                  if (word.rootAr != null) Tag('Root ${word.rootAr}', color: p.accent, background: p.accentSoft),
                ]),
              ]),
            ),
            const SizedBox(width: 12),
            Directionality(textDirection: TextDirection.rtl, child: Text(arabic, style: quranStyle(28, p.ink).copyWith(height: 1.6))),
          ]),
          children: [
            const SizedBox(height: 6),
            if (word.lemmaAr != null) _kv(context, 'Lemma (dictionary form)', word.lemmaAr!, arabic: true),
            if (word.rootAr != null) _kv(context, 'Root letters', word.rootAr!, arabic: true),
            if (word.rootBw != null)
              FutureBuilder<int>(
                future: st.quran.rootOccurrences(word.rootBw!),
                builder: (c, s) => s.hasData
                    ? _kv(context, 'Occurrences of this root', '${s.data} words in the Quran (corpus count)')
                    : const SizedBox.shrink(),
              ),
            const SizedBox(height: 6),
            Text('MORPHOLOGY', style: Theme.of(context).textTheme.labelSmall),
            const SizedBox(height: 6),
            for (final seg in word.segments)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SizedBox(
                    width: 64,
                    child: Directionality(
                      textDirection: TextDirection.rtl,
                      child: Text(Morphology.bwToArabic(seg.formBw), style: arabicUi(18, p.ink)),
                    ),
                  ),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(Morphology.describe(seg), style: sans(13.5, color: p.ink)),
                      Text('Corpus tags: ${seg.tag} | ${seg.features}', style: sans(11, color: p.inkFaint)),
                    ]),
                  ),
                ]),
              ),
            if (word.arabic == null)
              Text('Note: the corpus segments this verse differently from the Tanzil text; '
                  'the word shown is reconstructed from the corpus form.', style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }

  Widget _kv(BuildContext c, String k, String v, {bool arabic = false}) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(children: [
      Expanded(child: Text(k, style: sans(13, color: p.inkSoft))),
      Text(v, style: arabic ? arabicUi(18, p.ink) : sans(13, color: p.ink, weight: FontWeight.w500)),
    ]),
  );
}

// --------------------------------------------------------------- CONTEXT
class _ContextTab extends StatelessWidget {
  final Study study;
  final StudyData data;
  final Surah surah;
  const _ContextTab({required this.study, required this.data, required this.surah});

  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    final p = Palette.of(context);
    final t = Theme.of(context).textTheme;
    final inSurah = st.plan.studies.where((x) => x.surah == study.surah).toList();
    final pos = inSurah.indexOf(study) + 1;
    final prev = study.index > 0 ? st.plan.studies[study.index - 1] : null;
    final next = study.index + 1 < st.plan.length ? st.plan.studies[study.index + 1] : null;
    final ctx = data.cms.where((e) => e['type'] == 'context').toList();
    final first = data.verses.first;
    return ListView(padding: const EdgeInsets.only(bottom: 24), children: [
      SectionLabel('About this surah'),
      Surface(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text('${surah.nameTranslit} — ${surah.nameEn}', style: t.titleMedium)),
            Text(surah.nameAr, style: arabicUi(22, p.inkSoft)),
          ]),
          const SizedBox(height: 12),
          _fact(context, 'Surah', '${surah.number} of 114'),
          _fact(context, 'Classification', surah.revelationType),
          _fact(context, 'Traditional order of revelation', '${surah.revelationOrder}'),
          _fact(context, 'Verses', '${surah.ayahCount}'),
          _fact(context, 'Sections (rukūʿ)', '${surah.rukus}'),
          _fact(context, 'These verses', 'Juz ${first.juz} · Madinah mushaf page ${first.page}'),
          const SizedBox(height: 8),
          Text('Source: Tanzil Quran metadata. Scholars differ on the Meccan/Medinan classification and the revelation '
              'order of some surahs; these values follow Tanzil\'s commonly used tables.', style: t.bodySmall),
        ]),
      ),
      FutureBuilder<List<Map<String, dynamic>>>(
        future: st.userDb.surahIntro(study.surah),
        builder: (c, s) => Column(children: [
          for (final item in s.data ?? const <Map<String, dynamic>>[]) ...[
            const SizedBox(height: 12),
            CmsItemCard(item: item),
          ],
        ]),
      ),
      SectionLabel('Where these verses sit'),
      Surface(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Verses ${study.startAyah}–${study.endAyah} of ${surah.ayahCount} · study $pos of ${inSurah.length} in this surah',
              style: t.titleSmall),
          if (study.rationale != null) ...[
            const SizedBox(height: 8),
            Text('Grouping note: ${study.rationale}', style: t.bodyMedium),
          ],
          if (prev != null) _Neighbour(label: 'Before this passage', verseId: prev.endId),
          if (next != null) _Neighbour(label: 'After this passage', verseId: next.startId),
          const SizedBox(height: 8),
          Text('Neighbouring verses are quoted from the translation for continuity.', style: t.bodySmall),
        ]),
      ),
      SectionLabel('Historical context'),
      if (ctx.isEmpty)
        Surface(
          child: Text(
            'No reviewed historical context or occasion of revelation has been published for these verses yet. '
            'This app does not generate them: they are added only after source verification and review.',
            style: t.bodyMedium,
          ),
        )
      else
        for (final item in ctx) Padding(padding: const EdgeInsets.only(bottom: 12), child: CmsItemCard(item: item)),
    ]);
  }

  Widget _fact(BuildContext c, String k, String v) {
    final p = Palette.of(c);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Expanded(child: Text(k, style: sans(13.5, color: p.inkSoft))),
        Text(v, style: sans(13.5, color: p.ink, weight: FontWeight.w600)),
      ]),
    );
  }
}

class _Neighbour extends StatelessWidget {
  final String label;
  final int verseId;
  const _Neighbour({required this.label, required this.verseId});
  @override
  Widget build(BuildContext context) {
    final st = context.read<AppState>();
    final p = Palette.of(context);
    return FutureBuilder<(Verse, String)>(
      future: () async {
        final v = (await st.quran.verses(verseId, verseId)).first;
        final t = await st.quran.translationText(st.translation.id, verseId, verseId);
        return (v, t[verseId] ?? '');
      }(),
      builder: (c, s) {
        if (!s.hasData) return const SizedBox(height: 40);
        final (v, tr) = s.data!;
        return Padding(
          padding: const EdgeInsets.only(top: 14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${label.toUpperCase()} · ${st.surahName(v.surah)} ${v.key}', style: Theme.of(context).textTheme.labelSmall),
            const SizedBox(height: 4),
            Text(tr, style: serif(16, color: p.inkSoft, italic: true, height: 1.45)),
          ]),
        );
      },
    );
  }
}

// ----------------------------------------------------------------- TAFSIR
class _TafsirTab extends StatefulWidget {
  final Study study;
  final StudyData data;
  const _TafsirTab({required this.study, required this.data});
  @override
  State<_TafsirTab> createState() => _TafsirTabState();
}

class _TafsirTabState extends State<_TafsirTab> {
  late Verse _verse = widget.data.verses.first;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final p = Palette.of(context);
    final cms = widget.data.cms.where((e) => e['type'] == 'tafsir').toList();
    return ListView(padding: const EdgeInsets.only(bottom: 24), children: [
      SectionLabel('Reviewed tafsir notes'),
      if (cms.isEmpty)
        Surface(
          child: Text(
            'No reviewed English tafsir summary has been published for these verses yet. Below you can read '
            'the original Arabic text of classical tafsir works, and links to recognised English tafsir.',
            style: t.bodyMedium,
          ),
        )
      else
        for (final item in cms) Padding(padding: const EdgeInsets.only(bottom: 12), child: CmsItemCard(item: item)),
      SectionLabel('Classical tafsir · original Arabic'),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Wrap(spacing: 8, runSpacing: 8, children: [
          for (final v in widget.data.verses)
            ChoiceChip(
              label: Text(v.key),
              selected: v.id == _verse.id,
              onSelected: (_) => setState(() => _verse = v),
              selectedColor: p.accentSoft,
              labelStyle: sans(13, weight: FontWeight.w600, color: v.id == _verse.id ? p.accent : p.inkSoft),
              side: BorderSide(color: p.line),
              showCheckmark: false,
            ),
        ]),
      ),
      const SizedBox(height: 12),
      for (final w in classicalTafsirs) _ClassicalTafsirCard(key: ValueKey('${w.id}-${_verse.id}'), work: w, verse: _verse),
      SectionLabel('English tafsir · external'),
      Surface(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(children: [
          for (final (label, url) in OnlineContentService.externalEnglishTafsir(_verse.surah, _verse.ayah))
            ListTile(
              title: Text(label, style: sans(14.5, color: p.ink, weight: FontWeight.w500)),
              trailing: const Icon(Icons.open_in_new, size: 18),
              onTap: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
            ),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
        child: Text('These English works are under copyright, so the app links to their publishers\' sites and does not copy them.',
            style: t.bodySmall),
      ),
      const SizedBox(height: 8),
      const ContentLegend(),
    ]);
  }
}

class _ClassicalTafsirCard extends StatefulWidget {
  final ClassicalTafsir work;
  final Verse verse;
  const _ClassicalTafsirCard({super.key, required this.work, required this.verse});
  @override
  State<_ClassicalTafsirCard> createState() => _ClassicalTafsirCardState();
}

class _ClassicalTafsirCardState extends State<_ClassicalTafsirCard> {
  Future<TafsirText?>? _f;
  bool _open = false;
  bool _expanded = false;

  void _toggle() {
    final st = context.read<AppState>();
    setState(() {
      _open = !_open;
      _f ??= st.online.tafsir(widget.work, widget.verse.surah, widget.verse.ayah, allowNetwork: st.settings.onlineEnrichment);
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final t = Theme.of(context).textTheme;
    final w = widget.work;
    return Surface(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        InkWell(
          onTap: _toggle,
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(w.scholar, style: t.titleSmall),
                Text('${w.work} · d. ${w.deathAh} AH / ${w.deathCe} CE', style: t.bodySmall),
              ]),
            ),
            Text(w.scholarAr, style: arabicUi(18, p.inkSoft)),
            Icon(_open ? Icons.expand_less : Icons.expand_more, color: p.inkFaint),
          ]),
        ),
        if (_open)
          FutureBuilder<TafsirText?>(
            future: _f,
            builder: (c, s) {
              if (s.connectionState != ConnectionState.done) {
                return const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator(strokeWidth: 2)));
              }
              final tx = s.data;
              if (tx == null) {
                return Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text('This text is not available offline yet. Connect once to load it, then it stays on this device. '
                      '(Online sources can be turned off in settings.)', style: t.bodySmall),
                );
              }
              final paras = _expanded ? tx.paragraphs : tx.paragraphs.take(3).toList();
              return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const SizedBox(height: 12),
                Wrap(spacing: 6, children: [
                  const CategoryTag('direct_quotation'),
                  Tag('Arabic original', icon: Icons.translate),
                  if (tx.coveredKeys.length > 1) Tag('Covers ${tx.coveredKeys.first}–${tx.coveredKeys.last.split(':').last}'),
                ]),
                const SizedBox(height: 10),
                for (final para in paras)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Directionality(
                      textDirection: TextDirection.rtl,
                      child: SelectableText(para, style: arabicUi(18, p.ink).copyWith(height: 1.9), textAlign: TextAlign.justify),
                    ),
                  ),
                if (tx.paragraphs.length > 3)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: () => setState(() => _expanded = !_expanded),
                      child: Text(_expanded ? 'Show less' : 'Read all ${tx.paragraphs.length} paragraphs'),
                    ),
                  ),
                Text(
                  '${w.scholar}, ${w.work}. Original text shown word for word from the Quran.com digital edition, '
                  'with nothing translated or summarised. The digital source does not give volume and page numbers.',
                  style: t.bodySmall,
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => launchUrl(Uri.parse(tx.sourceUrl), mode: LaunchMode.externalApplication),
                    icon: const Icon(Icons.open_in_new, size: 16),
                    label: const Text('View source'),
                  ),
                ),
              ]);
            },
          ),
      ]),
    );
  }
}

// ---------------------------------------------------------------- REFLECT
const _generalPrompts = [
  'Which word or phrase in these verses stayed with you, and why?',
  'What do these verses tell you about Allah?',
  'Is there one thing you could carry from these verses into today?',
  'How might these verses shape the way you treat the people around you?',
  'What question would you like to learn more about from these verses?',
  'Read the verses again slowly. What did you notice the second time?',
  'Is there a du‘a (supplication) these verses inspire you to make?',
  'What feeling did these verses leave you with?',
];

class _ReflectTab extends StatelessWidget {
  final Study study;
  final StudyData data;
  const _ReflectTab({required this.study, required this.data});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final p = Palette.of(context);
    final cms = data.cms.where((e) => e['type'] == 'reflection').toList();
    final prompts = [for (var i = 0; i < 3; i++) _generalPrompts[(study.index + i * 3) % _generalPrompts.length]];
    return ListView(padding: const EdgeInsets.only(bottom: 24), children: [
      if (cms.isNotEmpty) ...[
        SectionLabel('Reflections on these verses'),
        for (final item in cms) Padding(padding: const EdgeInsets.only(bottom: 12), child: CmsItemCard(item: item)),
      ],
      SectionLabel('Questions to sit with'),
      Surface(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (final q in prompts)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Padding(padding: const EdgeInsets.only(top: 8), child: Container(width: 5, height: 5, decoration: BoxDecoration(color: p.accent, shape: BoxShape.circle))),
                const SizedBox(width: 12),
                Expanded(child: Text(q, style: serif(17.5, color: p.ink, height: 1.45))),
              ]),
            ),
          Text('General reflection prompts written by the app\'s editors. They are not tafsir and make no claim about '
              'the meaning of these verses.', style: t.bodySmall),
        ]),
      ),
      SectionLabel('Your reflections'),
      NotesSection(studyStart: study.startId, studyEnd: study.endId),
    ]);
  }
}

// ------------------------------------------------------------ BOTTOM BAR
class _StudyBottomBar extends StatelessWidget {
  final Study study;
  final Future<StudyData> dataFuture;
  const _StudyBottomBar({required this.study, required this.dataFuture});

  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    final p = Palette.of(context);
    final done = st.progress.isStudyComplete(study);
    final reciter = reciters.firstWhere((r) => r.id == st.settings.reciter, orElse: () => reciters.first);
    return Container(
      decoration: BoxDecoration(color: p.bg, border: Border(top: BorderSide(color: p.line))),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 16, 10),
          child: Row(children: [
            StreamBuilder<bool>(
              stream: st.audio.playingStream,
              builder: (c, s) {
                final playing = s.data ?? false;
                return Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(
                    tooltip: playing ? 'Pause' : 'Play recitation (${reciter.name})',
                    onPressed: () async {
                      final d = await dataFuture;
                      final ids = d.verses.map((e) => e.id).toList();
                      try {
                        if (!st.audio.isLoadedFor(ids, st.settings.reciter)) {
                          await st.audio.load(
                            reciter: st.settings.reciter,
                            verseIds: ids,
                            keys: d.verses.map((e) => (e.surah, e.ayah)).toList(),
                          );
                          await st.audio.playFrom(0);
                        } else {
                          await st.audio.toggle();
                        }
                      } catch (_) {
                        if (context.mounted) toast(context, 'Recitation needs a connection unless downloaded.');
                      }
                    },
                    icon: Icon(playing ? Icons.pause_circle_filled : Icons.play_circle_fill, color: p.accent, size: 38),
                  ),
                  IconButton(tooltip: 'Previous verse', onPressed: st.audio.previous, icon: const Icon(Icons.skip_previous_outlined)),
                  IconButton(tooltip: 'Next verse', onPressed: st.audio.next, icon: const Icon(Icons.skip_next_outlined)),
                  IconButton(tooltip: 'Replay verse', onPressed: st.audio.replay, icon: const Icon(Icons.replay)),
                ]);
              },
            ),
            const Spacer(),
            if (!done)
              FilledButton(
                onPressed: () async {
                  await st.audio.stop();
                  await st.completeStudy(study);
                  if (context.mounted) _showDone(context);
                },
                child: const Text('Complete'),
              )
            else
              Row(children: [
                Icon(Icons.check_circle, color: p.success, size: 20),
                const SizedBox(width: 6),
                Text('Studied', style: sans(14, weight: FontWeight.w600, color: p.success)),
              ]),
          ]),
        ),
      ),
    );
  }

  void _showDone(BuildContext context) {
    final st = context.read<AppState>();
    final next = st.progress.nextStudy;
    final p = Palette.of(context);
    showModalBottomSheet<void>(
      context: context,
      builder: (c) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Icon(Icons.check_circle_outline, color: p.accent, size: 40),
            const SizedBox(height: 10),
            Text('Study complete', textAlign: TextAlign.center, style: Theme.of(c).textTheme.headlineSmall),
            const SizedBox(height: 6),
            Text(
              next == null
                  ? 'You have reached the end of the Quran. Alhamdulillah.'
                  : 'May these verses stay with you. Up next: ${st.studyTitle(next)}.',
              textAlign: TextAlign.center,
              style: Theme.of(c).textTheme.bodyMedium,
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () {
                Navigator.pop(c);
                Navigator.of(context).pop();
              },
              child: const Text('Back to today'),
            ),
            if (next != null) ...[
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () {
                  Navigator.pop(c);
                  Navigator.of(context).pushReplacement(StudyScreen.route(next));
                },
                child: const Text('Read the next study now'),
              ),
            ],
          ]),
        ),
      ),
    );
  }
}
