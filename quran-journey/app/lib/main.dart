import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'config/brand.dart';
import 'data/settings.dart';
import 'state/app_state.dart';
import 'ui/common.dart';
import 'ui/onboarding.dart';
import 'ui/root.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const _Boot());
}

/// Shows a calm splash while the bundled database is prepared (first launch
/// copies ~15 MB once), then hands over to the app.
class _Boot extends StatefulWidget {
  const _Boot();
  @override
  State<_Boot> createState() => _BootState();
}

class _BootState extends State<_Boot> {
  AppState? _state;
  Object? _error;

  @override
  void initState() {
    super.initState();
    AppState.create().then((s) => setState(() => _state = s), onError: (e) => setState(() => _error = e));
  }

  @override
  Widget build(BuildContext context) {
    final s = _state;
    if (s == null) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildTheme(Palette.light),
        darkTheme: buildTheme(Palette.dark),
        home: Scaffold(
          body: Center(
            child: _error != null
                ? Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text('The Quran data could not be opened.\n$_error', textAlign: TextAlign.center),
                  )
                : const BrandMark(size: 72),
          ),
        ),
      );
    }
    return ChangeNotifierProvider.value(value: s, child: const QuranJourneyApp());
  }
}

class QuranJourneyApp extends StatefulWidget {
  const QuranJourneyApp({super.key});
  @override
  State<QuranJourneyApp> createState() => _QuranJourneyAppState();
}

class _QuranJourneyAppState extends State<QuranJourneyApp> with WidgetsBindingObserver {
  StreamSubscription<Uri>? _links;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final state = context.read<AppState>();
    if (state.isTesting) return;
    try {
      final appLinks = AppLinks();
      _links = appLinks.uriLinkStream.listen((u) {
        final l = AppLink.parse(u.toString());
        if (l != null) state.pendingLink.value = l;
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _links?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) context.read<AppState>().onResume();
  }

  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    final mode = switch (st.settings.theme) {
      ThemePref.system => ThemeMode.system,
      ThemePref.light => ThemeMode.light,
      ThemePref.dark => ThemeMode.dark,
    };
    return MaterialApp(
      title: Brand.appName,
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Palette.light),
      darkTheme: buildTheme(Palette.dark),
      themeMode: mode,
      home: st.settings.onboarded ? const RootShell() : const OnboardingFlow(),
    );
  }
}
