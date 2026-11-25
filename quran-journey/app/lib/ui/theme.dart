
import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoPageTransitionsBuilder;
import 'package:material_ui/material_ui.dart';

/// Design tokens. A restrained palette: warm paper whites, charcoal ink and
/// a single deep-plum accent. Dark mode is a warm near-black, not pure black.
class Palette {
  final Color bg, surface, surfaceAlt, ink, inkSoft, inkFaint, line, accent, accentSoft, onAccent, success;
  final Brightness brightness;
  const Palette({
    required this.bg,
    required this.surface,
    required this.surfaceAlt,
    required this.ink,
    required this.inkSoft,
    required this.inkFaint,
    required this.line,
    required this.accent,
    required this.accentSoft,
    required this.onAccent,
    required this.success,
    required this.brightness,
  });

  static const light = Palette(
    bg: Color(0xFFFAF7F2),
    surface: Color(0xFFFFFFFF),
    surfaceAlt: Color(0xFFF3EEE7),
    ink: Color(0xFF231F24),
    inkSoft: Color(0xFF5E5761),
    inkFaint: Color(0xFF948C96),
    line: Color(0xFFE7E0D8),
    accent: Color(0xFF5B3A63),
    accentSoft: Color(0xFFEFE6F0),
    onAccent: Color(0xFFFFFFFF),
    success: Color(0xFF4F6B57),
    brightness: Brightness.light,
  );

  static const dark = Palette(
    bg: Color(0xFF151216),
    surface: Color(0xFF1E1A20),
    surfaceAlt: Color(0xFF262128),
    ink: Color(0xFFEEE8EF),
    inkSoft: Color(0xFFB9B0BB),
    inkFaint: Color(0xFF857D87),
    line: Color(0xFF332D35),
    accent: Color(0xFFC9A9D1),
    accentSoft: Color(0xFF34283A),
    onAccent: Color(0xFF1E1420),
    success: Color(0xFF9DBBA4),
    brightness: Brightness.dark,
  );

  static Palette of(BuildContext c) => Theme.of(c).brightness == Brightness.dark ? dark : light;
}

/// Inter / Newsreader are variable fonts; map weight to the 'wght' axis.
TextStyle sans(double size, {FontWeight weight = FontWeight.w400, Color? color, double? height, double? spacing}) =>
    TextStyle(
      fontFamily: 'Inter',
      fontSize: size,
      fontWeight: weight,
      fontVariations: [FontVariation('wght', weight.value.toDouble())],
      color: color,
      height: height,
      letterSpacing: spacing,
    );

TextStyle serif(double size, {FontWeight weight = FontWeight.w400, Color? color, double? height, bool italic = false}) =>
    TextStyle(
      fontFamily: 'Newsreader',
      fontSize: size,
      fontWeight: weight,
      fontStyle: italic ? FontStyle.italic : FontStyle.normal,
      fontVariations: [FontVariation('wght', weight.value.toDouble()), FontVariation('opsz', size.clamp(6, 72).toDouble())],
      color: color,
      height: height,
    );

TextStyle quranStyle(double size, Color color) =>
    TextStyle(fontFamily: 'AmiriQuran', fontSize: size, height: 2.05, color: color);

TextStyle arabicUi(double size, Color color, {FontWeight weight = FontWeight.w400}) =>
    TextStyle(fontFamily: 'Amiri', fontSize: size, color: color, fontWeight: weight, height: 1.5);

ThemeData buildTheme(Palette p) {
  final scheme = ColorScheme(
    brightness: p.brightness,
    primary: p.accent,
    onPrimary: p.onAccent,
    secondary: p.accent,
    onSecondary: p.onAccent,
    error: const Color(0xFFB3261E),
    onError: Colors.white,
    surface: p.surface,
    onSurface: p.ink,
    surfaceContainerHighest: p.surfaceAlt,
    outline: p.line,
    outlineVariant: p.line,
  );
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    brightness: p.brightness,
    scaffoldBackgroundColor: p.bg,
    fontFamily: 'Inter',
    splashFactory: InkSparkle.splashFactory,
  );
  return base.copyWith(
    textTheme: base.textTheme.copyWith(
      displaySmall: serif(34, weight: FontWeight.w500, color: p.ink, height: 1.15),
      headlineMedium: serif(28, weight: FontWeight.w500, color: p.ink, height: 1.2),
      headlineSmall: serif(23, weight: FontWeight.w500, color: p.ink, height: 1.25),
      titleLarge: sans(19, weight: FontWeight.w600, color: p.ink),
      titleMedium: sans(16, weight: FontWeight.w600, color: p.ink),
      titleSmall: sans(14, weight: FontWeight.w600, color: p.ink),
      bodyLarge: sans(16, color: p.ink, height: 1.5),
      bodyMedium: sans(14.5, color: p.inkSoft, height: 1.5),
      bodySmall: sans(12.5, color: p.inkFaint, height: 1.4),
      labelLarge: sans(15, weight: FontWeight.w600, color: p.ink),
      labelMedium: sans(13, weight: FontWeight.w500, color: p.inkSoft),
      labelSmall: sans(11.5, weight: FontWeight.w600, color: p.inkFaint, spacing: 0.6),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: p.bg,
      surfaceTintColor: Colors.transparent,
      foregroundColor: p.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: sans(17, weight: FontWeight.w600, color: p.ink),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: p.bg,
      surfaceTintColor: Colors.transparent,
      indicatorColor: p.accentSoft,
      height: 68,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (s) => sans(11.5, weight: s.contains(WidgetState.selected) ? FontWeight.w600 : FontWeight.w500,
            color: s.contains(WidgetState.selected) ? p.ink : p.inkFaint),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (s) => IconThemeData(color: s.contains(WidgetState.selected) ? p.accent : p.inkFaint, size: 24),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: p.accent,
        foregroundColor: p.onAccent,
        minimumSize: const Size(64, 52),
        textStyle: sans(15.5, weight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: p.ink,
        minimumSize: const Size(64, 50),
        side: BorderSide(color: p.line),
        textStyle: sans(15, weight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: p.accent, textStyle: sans(14.5, weight: FontWeight.w600), minimumSize: const Size(48, 44)),
    ),
    dividerTheme: DividerThemeData(color: p.line, thickness: 1, space: 1),
    listTileTheme: ListTileThemeData(
      iconColor: p.inkSoft,
      titleTextStyle: sans(15.5, weight: FontWeight.w500, color: p.ink),
      subtitleTextStyle: sans(13, color: p.inkFaint),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
      minVerticalPadding: 12,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? p.onAccent : p.inkFaint),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? p.accent : p.surfaceAlt),
      trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
    ),
    sliderTheme: SliderThemeData(activeTrackColor: p.accent, thumbColor: p.accent, inactiveTrackColor: p.line, overlayColor: p.accentSoft),
    tabBarTheme: TabBarThemeData(
      labelColor: p.ink,
      unselectedLabelColor: p.inkFaint,
      labelStyle: sans(14, weight: FontWeight.w600),
      unselectedLabelStyle: sans(14, weight: FontWeight.w500),
      indicatorColor: p.accent,
      indicatorSize: TabBarIndicatorSize.label,
      dividerColor: p.line,
      tabAlignment: TabAlignment.start,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: p.surface,
      hintStyle: sans(15, color: p.inkFaint),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: p.line)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: p.line)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: p.accent, width: 1.4)),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: p.surface,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    ),
    dialogTheme: DialogThemeData(backgroundColor: p.surface, surfaceTintColor: Colors.transparent),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: p.ink,
      contentTextStyle: sans(14, color: p.bg),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
      TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
    }),
  );
}
