import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../domain/models.dart';
import '../state/app_state.dart';
import 'common.dart';
import 'reader.dart';
import 'study.dart';
import 'theme.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});
  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _SearchResults {
  final List<Surah> surahs;
  final List<Verse> verses;
  final Map<int, String> translations;
  final List<Bookmark> bookmarks;
  final List<Note> notes;
  const _SearchResults(this.surahs, this.verses, this.translations, this.bookmarks, this.notes);
  bool get isEmpty => surahs.isEmpty && verses.isEmpty && bookmarks.isEmpty && notes.isEmpty;
}

class _LibraryScreenState extends State<LibraryScreen> {
  final _q = TextEditingController();
  Timer? _debounce;
  Future<_SearchResults>? _results;

  @override
  void dispose() {
    _debounce?.cancel();
    _q.dispose();
    super.dispose();
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 280), () {
      setState(() => _results = v.trim().length < 2 ? null : _search(v.trim()));
    });
  }

  Future<_SearchResults> _search(String q) async {
    final st = context.read<AppState>();
    final lower = q.toLowerCase();
    String simple(String s) => s.toLowerCase().replaceAll(RegExp(r"[^a-z0-9]"), '');
    final surahs = st.quran.surahs
        .where((s) =>
            simple(s.nameTranslit).contains(simple(q)) ||
            s.nameEn.toLowerCase().contains(lower) ||
            s.nameAr.contains(q) ||
            '${s.number}' == q)
        .toList();
    final ids = await st.quran.search(q, translationId: st.translation.id);
    final verses = <Verse>[];
    final tr = <int, String>{};
    for (final id in ids) {
      verses.addAll(await st.quran.verses(id, id));
      tr.addAll(await st.quran.translationText(st.translation.id, id, id));
    }
    final bms = (await st.userDb.bookmarks()).where((b) => (b.label ?? '').toLowerCase().contains(lower)).toList();
    final notes = (await st.userDb.allNotes()).where((n) => n.text.toLowerCase().contains(lower)).toList();
    return _SearchResults(surahs, verses, tr, bms, notes);
  }

  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    final p = Palette.of(context);
    final t = Theme.of(context).textTheme;
    final completed = st.progress.completedStudies();
    return SafeArea(
      bottom: false,
      child: CustomScrollView(slivers: [
        SliverToBoxAdapter(
          child: Padding(padding: const EdgeInsets.fromLTRB(20, 24, 20, 12), child: Text('Library', style: t.headlineMedium)),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _q,
              onChanged: _onChanged,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: 'Surah, 2:255, Arabic or English words',
                suffixIcon: _q.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => setState(() {
                          _q.clear();
                          _results = null;
                        }),
                      ),
              ),
            ),
          ),
        ),
        if (_results != null)
          SliverToBoxAdapter(
            child: FutureBuilder<_SearchResults>(
              future: _results,
              builder: (c, s) {
                if (!s.hasData) return const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator(strokeWidth: 2)));
                final r = s.data!;
                if (r.isEmpty) {
                  return const EmptyState(
                    icon: Icons.search_off,
                    title: 'Nothing found',
                    message: 'Try a surah name, a reference such as 2:255, or a word from the translation.',
                  );
                }
                return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  if (r.surahs.isNotEmpty) ...[
                    SectionLabel('Surahs'),
                    for (final su in r.surahs)
                      ListTile(
                        title: Text('${su.number}. ${su.nameTranslit}'),
                        subtitle: Text(su.nameEn),
                        trailing: Text(su.nameAr, style: arabicUi(18, p.inkSoft)),
                        onTap: () => Navigator.of(context).push(ReaderScreen.route(su.number)),
                      ),
                  ],
                  if (r.verses.isNotEmpty) ...[
                    SectionLabel('Verses (${r.verses.length}${r.verses.length >= 60 ? '+' : ''})'),
                    for (final v in r.verses)
                      ListTile(
                        title: Text('${st.surahName(v.surah)} ${v.key}', style: sans(14, weight: FontWeight.w600, color: p.ink)),
                        subtitle: Text(r.translations[v.id] ?? '', maxLines: 3, overflow: TextOverflow.ellipsis),
                        onTap: () => Navigator.of(context).push(ReaderScreen.route(v.surah, ayah: v.ayah)),
                      ),
                  ],
                  if (r.bookmarks.isNotEmpty) ...[
                    SectionLabel('Saved'),
                    for (final b in r.bookmarks)
                      ListTile(
                        leading: const Icon(Icons.bookmark_outline),
                        title: Text(b.label ?? ''),
                        onTap: () => Navigator.of(context).push(StudyScreen.route(st.plan.studyForVerse(b.verseStart))),
                      ),
                  ],
                  if (r.notes.isNotEmpty) ...[
                    SectionLabel('Your reflections'),
                    for (final n in r.notes)
                      ListTile(
                        leading: const Icon(Icons.edit_note),
                        title: Text(n.text, maxLines: 2, overflow: TextOverflow.ellipsis),
                        subtitle: Text(st.studyTitle(st.plan.studyForVerse(n.studyStart))),
                        onTap: () => Navigator.of(context).push(StudyScreen.route(st.plan.studyForVerse(n.studyStart))),
                      ),
                  ],
                ]);
              },
            ),
          )
        else ...[
          SliverToBoxAdapter(child: SectionLabel('Studied', trailing: Text('${completed.length}', style: t.labelMedium))),
          if (completed.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text('Studies you complete are kept here to revisit.', style: t.bodyMedium),
              ),
            )
          else
            SliverList.builder(
              itemCount: completed.length.clamp(0, 30),
              itemBuilder: (c, i) {
                final s = completed[i];
                return ListTile(
                  leading: Icon(Icons.check_circle_outline, color: p.accent),
                  title: Text(st.studyTitle(s)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(StudyScreen.route(s)),
                );
              },
            ),
          SliverToBoxAdapter(child: SectionLabel('Read the Quran')),
          SliverList.builder(
            itemCount: 114,
            itemBuilder: (c, i) {
              final su = st.quran.surahs[i];
              return ListTile(
                leading: SizedBox(width: 28, child: Text('${su.number}', style: sans(13, weight: FontWeight.w600, color: p.inkFaint))),
                title: Text(su.nameTranslit),
                subtitle: Text('${su.nameEn} · ${su.ayahCount} verses'),
                trailing: Text(su.nameAr, style: arabicUi(19, p.inkSoft)),
                onTap: () => Navigator.of(context).push(ReaderScreen.route(su.number)),
              );
            },
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ]),
    );
  }
}
