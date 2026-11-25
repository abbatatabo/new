# Releases and signing

## Android signing key (important)

The 1.0.0 APK is signed with a release key generated for this project:

* File: `quran-journey-release.jks` (PKCS12, RSA 4096, valid until 2054)
* Alias: `quranjourney`
* Certificate SHA-256: `B1:7E:18:42:AB:CC:83:8F:CE:60:89:32:64:75:66:6C:73:C8:A1:A8:2B:57:EC:53:F2:88:9A:49:BF:C8:B3:5B`

**The keystore and its passwords are not in this repository.** They were delivered to the owner separately.
Back them up somewhere safe, such as a password manager or encrypted storage.

* **If you lose the key,** phones with this APK installed cannot be updated. Users would have to uninstall,
  which deletes their local data unless they exported it or used sync.
* **For Google Play,** use Play App Signing and upload this key as the upload key, or register a new upload key.

## Building a signed release

Create `app/android/key.properties` (git-ignored):

```properties
storeFile=/absolute/path/to/quran-journey-release.jks
storePassword=…
keyAlias=quranjourney
keyPassword=…
```

For CI, set the environment variables `QJ_KEYSTORE`, `QJ_KEYSTORE_PASSWORD`, `QJ_KEY_ALIAS` and
`QJ_KEY_PASSWORD` instead.

```bash
cd app
# bump `version: 1.0.1+2` in pubspec.yaml (build number must increase)
flutter build apk --release        # build/app/outputs/flutter-apk/app-release.apk
flutter build appbundle --release  # build/app/outputs/bundle/release/app-release.aab
```

Without a key, the Gradle config falls back to the debug key so local `flutter run --release` works. Never
distribute such a build; check with:

```bash
apksigner verify --print-certs app-release.apk   # must show CN=The Quran Journey and the SHA-256 above
```

## Updating content without an app update

Publish reviewed content in the admin dashboard. Apps connected to that server fetch it on launch and resume.

Changes to the bundled database (`tools/build_content.py`) need a new app build. The app replaces its copy
of the database automatically when the bundled file changes, and user data lives in a separate database.

## iOS

See [IOS.md](IOS.md) for Archive, Ad Hoc and TestFlight distribution.
