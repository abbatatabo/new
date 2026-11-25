# Changing the product name and branding

| What | Where |
|---|---|
| Name inside the app, notifications and widget data | `app/lib/config/brand.dart` → `appName` (or build with `--dart-define=QJ_APP_NAME="New Name"`) |
| Tagline | `app/lib/config/brand.dart` → `tagline` |
| Android launcher label and widget names | `app/android/app/src/main/res/values/strings.xml` |
| iOS home-screen name | `app/ios/Runner/Info.plist` → `CFBundleDisplayName` |
| iOS widget gallery name | `app/ios/QuranJourneyWidget/QuranJourneyWidget.swift` → `configurationDisplayName` |
| Colours | `app/lib/ui/theme.dart` → `Palette`; Android widgets `res/values*/widget_colors.xml`; iOS widget Swift colour constants |
| Brand mark | `BrandMarkPainter` in `app/lib/ui/common.dart`, and `design/*.svg` |
| App icons | Edit `design/app-icon-1024.svg`, then re-render with Chromium/Playwright (the `render_icons.js` approach in this repo's history) or any icon generator, into `android/app/src/main/res/mipmap-*` and `ios/Runner/Assets.xcassets/AppIcon.appiconset` |
| Package and bundle ids, deep-link scheme, App Group | Listed in [CONTRACTS.md](CONTRACTS.md) §1. Changing these is optional and touches several files |

## Design language

* **Colours:** warm paper whites, charcoal ink and a single deep-plum accent (`#5B3A63`), with a warm
  near-black in dark mode.
* **Type:**
  * Amiri Quran for the Quran text;
  * Amiri for other Arabic;
  * Newsreader (serif) for translation and headings;
  * Inter for the interface.
* **Mark:** a rising path with three stations, standing for three moments in a day on one continuous
  journey. There are no mosque, crescent or ornament clichés.
