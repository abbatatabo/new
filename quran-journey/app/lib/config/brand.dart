/// Central, configurable branding. Renaming the product only requires
/// changing values here (plus platform display names listed in
/// docs/BRANDING.md). Nothing else in the Dart code hard-codes the name.
class Brand {
  static const String appName = String.fromEnvironment(
    'QJ_APP_NAME',
    defaultValue: 'The Quran Journey',
  );
  static const String tagline = '3 verses. 3 moments. Every day.';
  static const String shortDescription =
      'A guided journey through the Quran, from Al-Fatihah to An-Nas.';

  /// Deep-link scheme (must match AndroidManifest + iOS Info.plist).
  static const String scheme = 'quranjourney';

  /// iOS App Group shared with the WidgetKit extension.
  static const String iosAppGroup = 'group.app.quranjourney.shared';
  static const String iosWidgetKind = 'QuranJourneyWidget';

  /// Fully-qualified Android AppWidgetProvider classes.
  static const List<String> androidWidgetProviders = [
    'app.quranjourney.quran_journey.widget.SmallVerseWidgetProvider',
    'app.quranjourney.quran_journey.widget.MediumStudyWidgetProvider',
    'app.quranjourney.quran_journey.widget.LargeJourneyWidgetProvider',
  ];

  /// Optional backend. Empty = fully local app (default).
  static const String defaultApiBaseUrl = String.fromEnvironment(
    'QJ_API_BASE_URL',
    defaultValue: '',
  );
}
