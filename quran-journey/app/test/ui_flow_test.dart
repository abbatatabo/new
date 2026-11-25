import 'dart:io';
import 'dart:ui' show ImageByteFormat;

import 'package:flutter/rendering.dart' show RenderRepaintBoundary;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:quran_journey/data/quran_db.dart';
import 'package:quran_journey/data/settings.dart';
import 'package:quran_journey/domain/grouping.dart';
import 'package:quran_journey/main.dart';
import 'package:quran_journey/state/app_state.dart';
import 'package:quran_journey/ui/settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers.dart';

/// End-to-end UI flow on the real bundled database, rendered with the real
/// fonts. Screenshots are written to build/screenshots/ for visual review.
Future<void> loadFonts() async {
  Future<void> load(String family, List<String> files) async {
    final l = FontLoader(family);
    for (final f in files) {
      final bytes = File(f).readAsBytesSync();
      l.addFont(Future.value(ByteData.view(bytes.buffer)));
    }
    await l.load();
  }

  await load('Inter', ['assets/fonts/Inter-Variable.ttf']);
  await load('Newsreader', ['assets/fonts/Newsreader-Variable.ttf']);
  await load('AmiriQuran', ['assets/fonts/AmiriQuran-Regular.ttf']);
  await load('Amiri', ['assets/fonts/Amiri-Regular.ttf', 'assets/fonts/Amiri-Bold.ttf']);
  final flutterRoot = Platform.environment['FLUTTER_ROOT'] ?? '/opt/tools/flutter';
  await load('MaterialIcons', ['$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf']);
}

void main() {
  late QuranDb quran;
  final shots = Directory('build/screenshots')..createSync(recursive: true);

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await loadFonts();
    quran = await openRealQuranDb();
  });

  Future<AppState> newState(WidgetTester t, {Settings? settings}) async {
    SharedPreferences.setMockInitialValues({});
    late AppState s;
    await t.runAsync(() async {
      final prefs = await SharedPreferences.getInstance();
      final userDb = await openMemoryUserDb();
      s = await AppState.forTesting(
        quran: quran,
        userDb: userDb,
        store: SettingsStore(prefs),
        settings: settings,
        overrides: const [GroupingOverride(1, 1, 4, 'praise'), GroupingOverride(1, 5, 7, 'request')],
      );
    });
    return s;
  }

  Future<void> settle(WidgetTester t, [int ms = 250]) async {
    for (var i = 0; i < 4; i++) {
      await t.runAsync(() => Future<void>.delayed(Duration(milliseconds: ms ~/ 4)));
      await t.pump(const Duration(milliseconds: 50));
    }
    await t.pump(const Duration(milliseconds: 400));
  }

  Future<void> shot(WidgetTester t, String name) async {
    final boundary = t.renderObject<RenderRepaintBoundary>(find.byKey(const Key('shot')));
    await t.runAsync(() async {
      final img = await boundary.toImage(pixelRatio: 2);
      final png = await img.toByteData(format: ImageByteFormat.png);
      File('${shots.path}/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
    });
  }

  /// Dispose the tree and let snackbar/tooltip timers expire.
  Future<void> finish(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 12));
  }

  Widget app(AppState s) => RepaintBoundary(
    key: const Key('shot'),
    child: ChangeNotifierProvider.value(value: s, child: const QuranJourneyApp()),
  );

  void phone(WidgetTester t) {
    t.view.physicalSize = const Size(390 * 3, 844 * 3);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
  }

  testWidgets('Onboarding: 5 screens, defaults, begins at Al-Fatihah', (t) async {
    phone(t);
    final s = await newState(t);
    await t.pumpWidget(app(s));
    await settle(t);
    expect(find.textContaining('3 verses.'), findsOneWidget);
    await shot(t, '01-onboarding-intro');
    await t.tap(find.text('Begin'));
    await settle(t);
    expect(find.text('Your three moments'), findsOneWidget);
    expect(find.text('07:00'), findsOneWidget);
    expect(find.text('13:30'), findsOneWidget);
    expect(find.text('20:00'), findsOneWidget);
    await shot(t, '02-onboarding-schedule');
    await t.tap(find.text('Continue'));
    await settle(t);
    expect(find.text('Reading comfort'), findsOneWidget);
    await shot(t, '03-onboarding-preferences');
    await t.tap(find.text('Continue'));
    await settle(t);
    expect(find.text('A quiet nudge'), findsOneWidget);
    await shot(t, '04-onboarding-notifications');
    await t.tap(find.text('Not now')); // reading must work without notifications
    await settle(t);
    expect(s.settings.notifications.enabled, isFalse);
    expect(find.text('Al-Fatihah'), findsOneWidget);
    await shot(t, '05-onboarding-begin');
    await t.tap(find.text('Start my journey'));
    await settle(t, 600);
    expect(s.settings.onboarded, isTrue);
    expect(find.text('YOUR JOURNEY BEGINS'), findsOneWidget);
    expect(find.text('Al-Faatiha'), findsWidgets);
    await finish(t);
  }, timeout: const Timeout(Duration(minutes: 2)));

  testWidgets('Home → study → complete advances progress; slots update', (t) async {
    phone(t);
    final s = await newState(t, settings: const Settings(onboarded: true, onlineEnrichment: false));
    await t.pumpWidget(app(s));
    await settle(t, 600);
    await shot(t, '06-home-light');
    expect(find.text('0 of 3'), findsOneWidget);

    await t.tap(find.text('YOUR JOURNEY BEGINS'));
    await settle(t, 800);
    expect(find.text('Al-Faatiha 1:1–4'), findsOneWidget);
    expect(find.text('1:1'), findsOneWidget);
    expect(s.plan.byRange(1, 4)!.verseCount, 4);
    expect(find.text('1:5'), findsNothing, reason: 'study shows only its own verses');
    expect(find.textContaining('Praise be to Allah, Lord of the Worlds'), findsOneWidget);
    await shot(t, '07-study-read');

    await t.tap(find.text('Words'));
    await settle(t, 800);
    await shot(t, '08-study-words');
    expect(find.textContaining('Quranic Arabic Corpus'), findsOneWidget);
    expect(find.text('س م و'), findsWidgets); // root of بِسْمِ (1:1), from the corpus
    await shot(t, '08-study-words');

    await t.tap(find.text('Context'));
    await settle(t, 600);
    expect(find.text('Meccan'), findsOneWidget);
    await shot(t, '09-study-context');
    await t.drag(find.text('Meccan'), const Offset(0, -700));
    await settle(t);
    expect(find.textContaining('does not generate them'), findsOneWidget);

    await t.tap(find.text('Tafsir'));
    await settle(t, 600);
    expect(find.text('Ibn Kathir'), findsOneWidget);
    await shot(t, '10-study-tafsir');
    await t.drag(find.text('Ibn Kathir'), const Offset(0, -900));
    await settle(t);
    expect(find.textContaining('under copyright'), findsOneWidget);

    await t.tap(find.text('Reflect'));
    await settle(t, 600);
    expect(find.textContaining('not tafsir'), findsOneWidget);
    await shot(t, '11-study-reflect');

    // Write a reflection.
    await t.ensureVisible(find.text('Write a reflection'));
    await t.tap(find.text('Write a reflection'));
    await settle(t);
    await t.enterText(find.byType(TextField), 'All praise belongs to Him alone.');
    await t.tap(find.text('Save'));
    await settle(t, 600);
    expect(find.text('All praise belongs to Him alone.'), findsOneWidget);

    await t.tap(find.text('Complete'));
    await settle(t, 600);
    expect(find.text('Study complete'), findsOneWidget);
    expect(find.textContaining('Up next: Al-Faatiha 1:5–7'), findsOneWidget);
    await shot(t, '12-study-complete');
    expect(s.progress.completedVerses, 4);
    expect(s.progress.nextStudy!.refLabel, '1:5–7');

    await t.tap(find.text('Back to today'));
    await settle(t, 600);
    expect(find.text('1 of 3'), findsOneWidget);
    expect(find.text('Completed'), findsOneWidget);
    expect(find.text('YOUR NEXT STUDY'), findsOneWidget);
    await shot(t, '13-home-after-complete');

    // Saved tab shows the reflection.
    await t.tap(find.text('Saved'));
    await settle(t);
    await t.tap(find.text('Reflections'));
    await settle(t, 600);
    expect(find.text('All praise belongs to Him alone.'), findsOneWidget);
    await shot(t, '14-saved-reflections');
    await finish(t);
  }, timeout: const Timeout(Duration(minutes: 2)));

  testWidgets('Verse bookmark appears in Saved and can be removed', (t) async {
    phone(t);
    final s = await newState(t, settings: const Settings(onboarded: true));
    await t.pumpWidget(app(s));
    await settle(t, 600);
    await t.tap(find.text('YOUR JOURNEY BEGINS'));
    await settle(t, 800);
    await t.tap(find.byTooltip('Save verse').first);
    await settle(t);
    await t.pageBack();
    await settle(t);
    await t.tap(find.text('Saved'));
    await settle(t, 600);
    expect(find.text('Al-Faatiha 1:1'), findsOneWidget);
    await t.drag(find.text('Al-Faatiha 1:1'), const Offset(-500, 0));
    await settle(t, 600);
    expect(find.text('Al-Faatiha 1:1'), findsNothing);
    expect(await t.runAsync(() => s.userDb.bookmarks()), isEmpty);
    await finish(t);
  }, timeout: const Timeout(Duration(minutes: 2)));

  testWidgets('Journey screen lists 114 surahs; search finds 2:255 and Arabic text', (t) async {
    phone(t);
    final s = await newState(t, settings: const Settings(onboarded: true));
    await t.pumpWidget(app(s));
    await settle(t, 600);
    await t.tap(find.text('Journey'));
    await settle(t, 600);
    expect(find.text('All 114 surahs'.toUpperCase()), findsOneWidget);
    await shot(t, '15-journey');

    await t.tap(find.text('Library'));
    await settle(t, 600);
    await t.enterText(find.byType(TextField), '2:255');
    await settle(t, 900);
    await settle(t, 900);
    expect(find.text('Al-Baqara 2:255'), findsOneWidget);
    await shot(t, '16-search-reference');
    await t.enterText(find.byType(TextField), 'العالمين');
    await settle(t, 900);
    await settle(t, 900);
    expect(find.text('Al-Faatiha 1:2'), findsOneWidget);
    await finish(t);
  }, timeout: const Timeout(Duration(minutes: 2)));

  testWidgets('Dark mode and large Arabic text render without overflow', (t) async {
    phone(t);
    final s = await newState(t, settings: const Settings(onboarded: true, theme: ThemePref.dark, arabicScale: 1.8, translationScale: 1.4));
    await t.pumpWidget(app(s));
    await settle(t, 600);
    await shot(t, '17-home-dark');
    await t.tap(find.text('YOUR JOURNEY BEGINS'));
    await settle(t, 800);
    await shot(t, '18-study-dark-large-text');
    expect(t.takeException(), isNull);
    await finish(t);
  }, timeout: const Timeout(Duration(minutes: 2)));

  testWidgets('Settings: schedule, reminders, sources & methodology', (t) async {
    phone(t);
    final s = await newState(t, settings: const Settings(onboarded: true));
    await t.pumpWidget(app(s));
    await settle(t, 600);
    await t.tap(find.text('You'));
    await settle(t, 600);
    expect(find.text('Every day at 07:00'), findsOneWidget);
    await shot(t, '19-settings');
    // Toggle the afternoon session off -> home shows 2 slots.
    await t.tap(find.byType(Switch).at(1));
    await settle(t);
    expect(s.settings.enabledSessionCount, 2);
    await t.scrollUntilVisible(find.text('Sources & methodology'), 300,
        scrollable: find.descendant(of: find.byType(SettingsScreen), matching: find.byType(Scrollable)).first);
    await t.drag(find.descendant(of: find.byType(SettingsScreen), matching: find.byType(Scrollable)).first, const Offset(0, -200));
    await settle(t);
    await t.tap(find.text('Sources & methodology'));
    await settle(t, 800);
    await shot(t, '20-sources');
    expect(find.textContaining('No Quran text, translation, tafsir'), findsOneWidget);
    expect(find.textContaining('Tanzil Uthmani text'), findsOneWidget);
    await shot(t, '20-sources');
    await finish(t);
  }, timeout: const Timeout(Duration(minutes: 2)));

  testWidgets('Deep link to a study opens it (notification / widget tap)', (t) async {
    phone(t);
    final s = await newState(t, settings: const Settings(onboarded: true));
    await t.pumpWidget(app(s));
    await settle(t, 600);
    s.pendingLink.value = AppLink.parse('quranjourney://study/8-10?homeWidget=1');
    await settle(t, 800);
    expect(find.text('Al-Baqara 2:1–3'), findsOneWidget);
    await finish(t);
  }, timeout: const Timeout(Duration(minutes: 2)));
}
