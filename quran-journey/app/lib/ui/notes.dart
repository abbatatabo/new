import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../domain/models.dart';
import '../state/app_state.dart';
import 'common.dart';
import 'theme.dart';

/// Personal reflections for a study. Stored locally first; synced if signed in.
class NotesSection extends StatefulWidget {
  final int studyStart;
  final int studyEnd;
  const NotesSection({super.key, required this.studyStart, required this.studyEnd});
  @override
  State<NotesSection> createState() => _NotesSectionState();
}

class _NotesSectionState extends State<NotesSection> {
  late Future<List<Note>> _notes;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _notes = context.read<AppState>().userDb.notesForStudy(widget.studyStart, widget.studyEnd);
  }

  Future<void> _edit([Note? n]) async {
    final saved = await showNoteEditor(context, studyStart: widget.studyStart, studyEnd: widget.studyEnd, note: n);
    if (saved && mounted) setState(_reload);
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return FutureBuilder<List<Note>>(
      future: _notes,
      builder: (c, s) {
        final notes = s.data ?? const <Note>[];
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (final n in notes)
            Surface(
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              onTap: () => _edit(n),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(n.text, style: serif(16.5, color: p.ink, height: 1.5)),
                const SizedBox(height: 8),
                Row(children: [
                  Text(_date(n.updatedAt), style: Theme.of(context).textTheme.bodySmall),
                  if (n.conflictOf != null) ...[
                    const SizedBox(width: 8),
                    const Tag('Copy kept from another device'),
                  ],
                ]),
              ]),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: OutlinedButton.icon(
              onPressed: () => _edit(),
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: Text(notes.isEmpty ? 'Write a reflection' : 'Add another reflection'),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: Text('Private to you. Saved on this device and works offline.', style: Theme.of(context).textTheme.bodySmall),
          ),
        ]);
      },
    );
  }
}

String _date(DateTime d) {
  const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${d.day} ${m[d.month - 1]} ${d.year}';
}

/// Returns true when something was saved or deleted.
Future<bool> showNoteEditor(BuildContext context,
    {required int studyStart, required int studyEnd, Note? note}) async {
  final st = context.read<AppState>();
  final ctrl = TextEditingController(text: note?.text ?? '');
  final result = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (c) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(c).viewInsets.bottom),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(note == null ? 'New reflection' : 'Edit reflection', style: Theme.of(c).textTheme.titleLarge),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              autofocus: true,
              minLines: 5,
              maxLines: 12,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(hintText: 'What did these verses bring to mind?'),
            ),
            const SizedBox(height: 12),
            Row(children: [
              if (note != null)
                TextButton(
                  onPressed: () async {
                    final ok = await showDialog<bool>(
                      context: c,
                      builder: (d) => AlertDialog(
                        title: const Text('Delete this reflection?'),
                        content: const Text('This cannot be undone on this device.'),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Keep')),
                          TextButton(onPressed: () => Navigator.pop(d, true), child: const Text('Delete')),
                        ],
                      ),
                    );
                    if (ok == true && c.mounted) Navigator.pop(c, '__delete__');
                  },
                  child: const Text('Delete'),
                ),
              const Spacer(),
              TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
              const SizedBox(width: 8),
              FilledButton(onPressed: () => Navigator.pop(c, ctrl.text), child: const Text('Save')),
            ]),
          ]),
        ),
      ),
    ),
  );
  if (result == null) return false;
  if (result == '__delete__' && note != null) {
    await st.userDb.deleteNote(note.id);
  } else if (result.trim().isNotEmpty) {
    await st.userDb.saveNote(id: note?.id, studyStart: studyStart, studyEnd: studyEnd, text: result.trim());
  } else {
    return false;
  }
  st.dataChanged();
  return true;
}
