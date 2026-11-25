import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import 'bookmarks.dart';
import 'home.dart';
import 'journey.dart';
import 'library.dart';
import 'settings_screen.dart';
import 'study.dart';
import 'reader.dart';

class RootShell extends StatefulWidget {
  const RootShell({super.key});
  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  int _tab = 0;
  late final AppState _state;

  @override
  void initState() {
    super.initState();
    _state = context.read<AppState>();
    _state.pendingLink.addListener(_handleLink);
    WidgetsBinding.instance.addPostFrameCallback((_) => _handleLink());
  }

  @override
  void dispose() {
    _state.pendingLink.removeListener(_handleLink);
    super.dispose();
  }

  /// Notification taps, widget taps and quranjourney:// links all land here.
  void _handleLink() {
    final link = _state.pendingLink.value;
    if (link == null || !mounted) return;
    _state.pendingLink.value = null;
    final nav = Navigator.of(context);
    nav.popUntil((r) => r.isFirst);
    switch (link) {
      case StudyLink(:final start, :final end):
        final s = _state.plan.byRange(start, end) ?? _state.plan.studyForVerse(start.clamp(1, _state.plan.totalVerses));
        nav.push(StudyScreen.route(s));
      case NextLink():
        final s = _state.progress.nextStudy;
        if (s != null) nav.push(StudyScreen.route(s));
      case VerseLink(:final surah, :final ayah):
        if (surah >= 1 && surah <= 114) nav.push(ReaderScreen.route(surah, ayah: ayah));
      case TodayLink():
        setState(() => _tab = 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = const [HomeScreen(), JourneyScreen(), LibraryScreen(), BookmarksScreen(), SettingsScreen()];
    return Scaffold(
      body: IndexedStack(index: _tab, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.wb_twilight_outlined), selectedIcon: Icon(Icons.wb_twilight), label: 'Today'),
          NavigationDestination(icon: Icon(Icons.route_outlined), selectedIcon: Icon(Icons.route), label: 'Journey'),
          NavigationDestination(icon: Icon(Icons.menu_book_outlined), selectedIcon: Icon(Icons.menu_book), label: 'Library'),
          NavigationDestination(icon: Icon(Icons.bookmark_outline), selectedIcon: Icon(Icons.bookmark), label: 'Saved'),
          NavigationDestination(icon: Icon(Icons.tune_outlined), selectedIcon: Icon(Icons.tune), label: 'You'),
        ],
      ),
    );
  }
}
