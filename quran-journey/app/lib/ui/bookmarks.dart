import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../domain/models.dart';
import '../state/app_state.dart';
import 'common.dart';
import 'notes.dart';
import 'reader.dart';
import 'study.dart';
import 'theme.dart';

class BookmarksScreen extends StatefulWidget {
  const BookmarksScreen({super.key});
  @override
  State<BookmarksScreen> createState() => _BookmarksScreenState();
}

class _BookmarksScreenState extends State<BookmarksScreen> {
  int _seg = 0;
  int _tick = 0;

  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    final t = Theme.of(context).textTheme;
    return SafeArea(
      bottom: false,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(padding: const EdgeInsets.fromLTRB(20, 24, 20, 12), child: Text('Saved', style: t.headlineMedium)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SegmentedButton<int>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: 0, label: Text('Verses')),
              ButtonSegment(value: 1, label: Text('Studies')),
              ButtonSegment(value: 2, label: Text('Reflections')),
            ],
            selected: {_seg},
            onSelectionChanged: (s) => setState(() => _seg = s.first),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async {
              await st.syncNow();
              setState(() => _tick++);
            },
            child: _seg == 2 ? _NotesList(key: ValueKey('n$_tick')) : _BookmarkList(key: ValueKey('b$_seg$_tick'), types: _seg == 0 ? {BookmarkType.verse} : {BookmarkType.study, BookmarkType.tafsir, BookmarkType.reflection}),
          ),
        ),
      ]),
    );
  }
}

class _BookmarkList extends StatefulWidget {
  final Set<BookmarkType> types;
  const _BookmarkList({super.key, required this.types});
  @override
  State<_BookmarkList> createState() => _BookmarkListState();
}

class _BookmarkListState extends State<_BookmarkList> {
  late final Future<List<Bookmark>> _f = context.read<AppState>().userDb.bookmarks();

  @override
  Widget build(BuildContext context) {
    final st = context.read<AppState>();
    final p = Palette.of(context);
    return FutureBuilder<List<Bookmark>>(
      future: _f,
      builder: (c, s) {
        final list = (s.data ?? const <Bookmark>[]).where((b) => widget.types.contains(b.type)).toList();
        if (s.hasData && list.isEmpty) {
          return ListView(children: [
            EmptyState(
              icon: Icons.bookmark_outline,
              title: widget.types.contains(BookmarkType.verse) ? 'No saved verses yet' : 'No saved studies yet',
              message: 'Tap the bookmark icon while studying to keep something here.',
            ),
          ]);
        }
        return ListView.builder(
          itemCount: list.length,
          itemBuilder: (c, i) {
            final b = list[i];
            return Dismissible(
              key: ValueKey(b.id),
              direction: DismissDirection.endToStart,
              background: Container(
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.only(right: 24),
                color: p.surfaceAlt,
                child: Icon(Icons.delete_outline, color: p.inkSoft),
              ),
              onDismissed: (_) async {
                await st.userDb.removeBookmark(b.id);
                st.syncNow(quiet: true);
                if (context.mounted) toast(context, 'Removed');
              },
              child: ListTile(
                leading: Icon(b.type == BookmarkType.verse ? Icons.format_quote_outlined : Icons.menu_book_outlined, color: p.accent),
                title: Text(b.label ?? 'Saved'),
                subtitle: Text(b.type == BookmarkType.verse ? 'Verse' : b.type == BookmarkType.study ? 'Study' : b.type.name),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  if (b.type == BookmarkType.verse) {
                    final v = st.plan.studyForVerse(b.verseStart);
                    final ayah = v.startAyah + (b.verseStart - v.startId);
                    Navigator.of(context).push(ReaderScreen.route(v.surah, ayah: ayah));
                  } else {
                    Navigator.of(context).push(StudyScreen.route(st.plan.studyForVerse(b.verseStart)));
                  }
                },
              ),
            );
          },
        );
      },
    );
  }
}

class _NotesList extends StatefulWidget {
  const _NotesList({super.key});
  @override
  State<_NotesList> createState() => _NotesListState();
}

class _NotesListState extends State<_NotesList> {
  late Future<List<Note>> _f = context.read<AppState>().userDb.allNotes();

  @override
  Widget build(BuildContext context) {
    final st = context.read<AppState>();
    final p = Palette.of(context);
    return FutureBuilder<List<Note>>(
      future: _f,
      builder: (c, s) {
        final list = s.data ?? const <Note>[];
        if (s.hasData && list.isEmpty) {
          return ListView(children: const [
            EmptyState(
              icon: Icons.edit_note,
              title: 'No reflections yet',
              message: 'Write a reflection from the Reflect tab of any study. It stays private on this device.',
            ),
          ]);
        }
        return ListView.builder(
          padding: const EdgeInsets.only(top: 8, bottom: 24),
          itemCount: list.length,
          itemBuilder: (c, i) {
            final n = list[i];
            final study = st.plan.studyForVerse(n.studyStart.clamp(1, st.plan.totalVerses));
            return Surface(
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              onTap: () async {
                final changed = await showNoteEditor(context, studyStart: n.studyStart, studyEnd: n.studyEnd, note: n);
                if (changed && mounted) setState(() => _f = st.userDb.allNotes());
              },
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(st.studyTitle(study).toUpperCase(), style: Theme.of(context).textTheme.labelSmall),
                const SizedBox(height: 6),
                Text(n.text, style: serif(16.5, color: p.ink, height: 1.45), maxLines: 6, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 6),
                TextButton(
                  style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 32)),
                  onPressed: () => Navigator.of(context).push(StudyScreen.route(study)),
                  child: const Text('Open study'),
                ),
              ]),
            );
          },
        );
      },
    );
  }
}
