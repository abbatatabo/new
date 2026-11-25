# iOS: build and install on your iPhone

**Status, plainly:** this environment is Linux. It has no Xcode and no macOS SDK,
so the iOS app and its widget extension **have not been compiled, signed or run**.
No IPA exists yet. The project is complete and configured. Building it needs a Mac,
following the steps below. The Swift code was reviewed by hand, but anything Xcode
reports on the first build is still an open item (see "Not verified" at the end).

## What is already configured

| Item | Where |
|---|---|
| Flutter app target `Runner` (iOS 15.0+) | `app/ios/Runner.xcodeproj` |
| WidgetKit extension `QuranJourneyWidget` (iOS 17.0+; small, medium, large, lock-screen rectangular and inline) | `app/ios/QuranJourneyWidget/` |
| Extension embedded in the app ("Embed Foundation Extensions", placed before "Thin Binary" to avoid Xcode's build-cycle error) | `project.pbxproj` |
| App Group `group.app.quranjourney.shared` on both targets | `Runner/Runner.entitlements`, `QuranJourneyWidget/QuranJourneyWidget.entitlements` |
| Deep links `quranjourney://…` | `Runner/Info.plist` (`CFBundleURLTypes`; `FlutterDeepLinkingEnabled = false` so `app_links` handles them) |
| Local notifications delegate + background-isolate registrant (flutter_local_notifications 23, UIScene lifecycle) | `Runner/AppDelegate.swift` |
| Background audio (recitation keeps playing when locked) | `UIBackgroundModes = audio` |
| Arabic font in the widget (Amiri Quran, OFL) | `QuranJourneyWidget/AmiriQuran-Regular.ttf`, `UIAppFonts` |
| Widget version follows the app version (`pubspec.yaml` `version:`) | `QuranJourneyWidget/QuranJourneyWidget.xcconfig` |

The extension target was added with a script, `tools/ios/add_widget_target.rb`. It uses
the `xcodeproj` gem and can be re-run safely. Re-run it only if you regenerate the iOS folder.

## Steps on a Mac

1. Install **Xcode** (version 16 or newer) from the App Store, open it once, and accept the licence.
   Install the **Flutter SDK** (`flutter doctor` should show Xcode as ready). Install CocoaPods
   with `sudo gem install cocoapods` or `brew install cocoapods`. Flutter uses Swift Package Manager
   where a plugin supports it and CocoaPods for the rest, and `flutter build` runs `pod install` for you.
2. Get the code and dependencies:
   ```bash
   cd quran-journey/app
   flutter pub get
   flutter build ios --config-only     # generates Flutter/Generated.xcconfig and the Podfile
   ```
3. Open **`app/ios/Runner.xcworkspace`** in Xcode. Use the workspace if it exists; otherwise
   use `Runner.xcodeproj`.
4. Select the **Runner** project ▸ **Signing & Capabilities**. For **both** the `Runner` and
   `QuranJourneyWidget` targets:
   * tick *Automatically manage signing* and choose your **Team**;
   * if Xcode says the bundle id is taken, change `app.quranjourney.quranJourney` (Runner)
     and `app.quranjourney.quranJourney.QuranJourneyWidget` (the extension id must stay
     `<app id>.QuranJourneyWidget`).
5. **App Group.** Under *App Groups* on both targets, make sure `group.app.quranjourney.shared`
   is ticked. If Xcode cannot register it for your team, create your own group, for example
   `group.<yourname>.quranjourney`, and change it in **all four** places:
   * `app/lib/config/brand.dart` → `iosAppGroup`
   * `app/ios/Runner/Runner.entitlements`
   * `app/ios/QuranJourneyWidget/QuranJourneyWidget.entitlements`
   * `app/ios/QuranJourneyWidget/WidgetData.swift` → `QJConfig.appGroup`
6. Connect your iPhone, select it as the run destination and press **Run**. You can also run
   `flutter run --release` from `app/`. On the phone, enable **Settings ▸ Privacy & Security ▸
   Developer Mode** the first time, and trust your developer certificate under
   **Settings ▸ General ▸ VPN & Device Management**.
7. Add the widget: long-press the home screen ▸ **+** ▸ *The Quran Journey* ▸ choose a size.
   Open the app at least once first so the widget has data.

### Free Apple ID versus paid Apple Developer Program

* **Free Apple ID (Personal Team):** the app installs and works, but the install expires after
  **7 days** and you must run it again from Xcode. Apple does **not** grant the App Groups
  capability to free personal teams, so Xcode will refuse to sign while App Groups is
  enabled. To build anyway, remove the *App Groups* capability from both targets. The app then
  works fully, notifications included, but the widget cannot read the app's data and will only
  show its "Open to begin your journey" state.
* **Paid Apple Developer Program (99 USD a year):** App Groups work, so widgets show live data.
  Installs last up to a year (development or Ad Hoc), and you can use TestFlight.

## Producing an IPA

```bash
cd quran-journey/app
flutter build ipa --release --export-method ad-hoc         # or app-store for TestFlight
# Output: app/build/ios/ipa/*.ipa
```
Alternatively, in Xcode choose **Product ▸ Archive**, then in the Organizer **Distribute App**
and pick **Ad Hoc** (devices registered in your account) or **App Store Connect / TestFlight**.
Both routes need a paid membership.

## Not verified here (be aware on the first build)

* Nothing iOS-side has been compiled. That covers the Swift syntax and type-checking of
  `QuranJourneyWidget.swift`, `WidgetData.swift` and `AppDelegate.swift`, and the build settings
  that `xcodeproj` generated. All of it was checked only by reading and by re-opening the project
  with the `xcodeproj` gem.
* Widget rendering, the Amiri Quran font loading in the extension, and the right-to-left layout
  of Arabic on the widget have not been seen on a simulator or a device.
* Notification delivery, deep links from notifications and widgets, and background audio have
  not been exercised on iOS.
* iOS keeps at most 64 pending local notifications per app. The app schedules fewer (3 sessions
  for 7 days, 21 in total) and reschedules on each launch.
* WidgetKit refreshes on its own budget. The widget refreshes at session times and at
  midnight when iOS allows it, and whenever the app calls `HomeWidget.updateWidget`. Exact-minute
  refreshes are not guaranteed.
