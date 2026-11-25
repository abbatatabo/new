# Test results

Run on 2026-11-25 in a Linux build container: Flutter 3.50.1, Android SDK 36/37, JDK 21 and Node 22.
There was no hardware virtualisation (no KVM), so **no Android emulator could run**, and there was no
macOS or Xcode.

## Summary

| Suite | Command | Result |
|---|---|---|
| Content pipeline integrity (28 checks) | `python3 -I tools/build_content.py` | 28/28 checks passed (`content/integrity-report.json`) |
| Flutter unit and UI tests | `cd app && flutter test` | **57 passed, 0 failed** |
| Native Android widgets (Robolectric) | `cd app/android && ./gradlew :app:testDebugUnitTest` | **7 passed, 0 failed** |
| Backend | `cd server && npm test` | **23 passed, 0 failed** |
| App ↔ backend integration | `tools/run_server_integration.sh` | **2 passed, 0 failed** |
| Release APK | `flutter build apk --release` | Built (64.4 MB), signed with the v2 scheme by the release key, `apksigner verify` OK |
| Release AAB | `flutter build appbundle --release` | Built (64.7 MB), signed |
| Static analysis | `flutter analyze` | No issues |
| PHP web app (unit + end-to-end HTTP) | `php web/tests/run.php` | **29 passed, 0 failed**; the study plan is identical to the Flutter app's (SHA-256 at 1/2/3/5 verses per study) |
| PHP web app in Chromium (Playwright; phone light/dark and desktop) | scripted walkthrough | No console or CSP errors |

## What the suites cover

### `app/test/content_integrity_test.dart` (9 tests)

* 114 surahs and 6,236 verses with contiguous ids.
* All 6,236 verses are byte-identical to the Tanzil source XML, and the checksum matches.
* Bismillah placement.
* Every translation covers every verse.
* Corpus morphology.
* Search:
  * by reference;
  * Arabic in both Uthmani and everyday spelling, ignoring diacritics;
  * English;
  * no false results.
* Source metadata.

### `app/test/progression_test.dart` (19 tests)

* The plan covers every verse once, in order, and never crosses a surah.
* Study sizes; the 75-word limit; 2:282 studied alone.
* The Al-Fatihah grouping, and the default lone-verse merge.
* Invalid overrides are ignored.
* Plans at 1, 2 and 5 verses per study.
* Surah transition 1 → 2.
* **Missed days never skip verses.**
* Today's slots: done, ready and upcoming by time.
* Disabled sessions.
* Reading ahead out of order.
* Re-reads don't double-count.
* Changing the study size keeps progress.
* End of the Quran.

### `app/test/schedule_and_links_test.dart` (13 tests)

* 7-day reminder plan; never more than 64 reminders (the iOS limit).
* Unique ids, including across a year boundary.
* Disabled sessions, master switch, pause, and quiet hours that wrap midnight.
* **DST:** wall-clock time is preserved across the New York change (tz database).
* Settings JSON round trip.
* Widget refresh times.
* Deep-link parsing, including the iOS widget query, and rejection of foreign schemes.
* Morphology wording; Buckwalter decoding; tafsir HTML stripped without altering words.

### `app/test/user_data_test.dart` (9 tests)

* Notes: create, edit and delete (as a tombstone).
* Bookmarks are idempotent and removable.
* Progress is scoped by journey.
* A note edited during sync stays unsynced.
* **Remote data never overwrites unsynced note text.**
* Conflict copies; bookmark tombstones; remote progress.
* CMS content per verse range, and removal.
* Export and wipe; UUID format.

### `app/test/ui_flow_test.dart` (7 tests)

These run on the real database with the real fonts and save the screenshots in `docs/screenshots/`.

* The full onboarding: reading works with notifications declined.
* Home → study (all five tabs) → write a reflection → complete:
  * progress becomes 4 verses and the next study is 1:5–7;
  * home shows "1 of 3", and the reflection appears in Saved.
* Bookmarking a verse adds it to Saved; swipe removes it.
* Journey lists the surahs; search finds `2:255` and `العالمين`.
* Dark mode at 180% Arabic and 140% translation renders without exceptions.
* Settings: switching a session off updates the plan; Sources & methodology opens.
* A deep link (`quranjourney://study/8-10?homeWidget=1`) opens Al-Baqara 2:1–3.

### `app/android/.../WidgetProvidersTest.kt` (7 tests)

The real layouts are inflated under Android's RemoteViews rules by the real providers.

* Small, medium and large widgets show the verse, reference, progress, today's count, next session and
  session rows.
* Empty state before the first launch.
* "Done" marks reset on a new day.
* Paused state; all-done state.

### `server/test/*.test.js` (23 tests)

* Accounts: authentication, rate limiting, token expiry, account deletion and export.
* Sync: last-writer-wins, note conflicts, tombstones.
* The publication workflow and its permissions (including that nobody can approve their own item);
  only published content is served; `removed_ids` after unpublishing.
* Verse text is immutable.
* Validation, security headers, CORS.

### `app/integration_server_test/` (2 tests)

* **Two devices, one account:** notes, bookmarks and progress sync; a conflicting edit keeps both texts
  on both devices; a deletion propagates.
* A CMS item stays invisible to the app as draft, source-verified, reviewed and approved. It appears only
  when published, and disappears again when unpublished.

## Bugs found by testing and fixed

1. **Large Android widget would have failed to load** on real phones: a plain `View` is not allowed in
   RemoteViews. Found by Robolectric; the divider is now a `FrameLayout`.
2. **Saved tab didn't refresh** after you bookmarked or wrote a reflection; it now reloads on every change.
3. **`setState` with an async closure** in Library search, Notes, the Saved refresh and the word-meanings
   reload, which throws in debug builds.
4. **The home card re-queried the database on every rebuild.** The query is now cached.
5. **Arabic search missed everyday spelling** (for example العالمين against the Uthmani العَـٰلَمِين). Fixed
   by indexing Tanzil's Simple-Clean text.
6. **Hand-typed Arabic preview text was not byte-identical to the source.** All Quran text in the UI now
   comes from the database.
7. **Line-ending normalisation would have altered the source files' checksums** in git. Fixed with
   `.gitattributes`.

## Not tested, and why

| Area | Status |
|---|---|
| Install and run on a physical Android phone or emulator | **Not done.** No KVM here, so no emulator; no device attached. The APK installs through the standard Android installer. |
| Notification delivery, timing, reboot re-arming, permission dialogs | Scheduling logic is unit-tested; delivery by the OS is **untested** |
| Widgets on a real launcher (placement, resizing, tap-through) | Rendering is tested with Robolectric; behaviour on a real launcher is **untested** |
| Audio playback | **Untested**. The EveryAyah URLs were checked live (HTTP 206 for all four reciters) |
| Online word glosses and classical tafsir in the app | The API response formats were checked live; the in-app fetch is **untested** on a device |
| Entire iOS app and widget | **Not compiled.** No Mac or Xcode. See [IOS.md](IOS.md) |
| Backend Dockerfile | Not built (no Docker daemon used) |

Recommended first checks on your phone:

1. Complete onboarding.
2. Set a session two minutes from now and lock the phone, to check the reminder arrives.
3. Add all three widgets.
4. Tap a widget and the notification.
5. Play a recitation.
6. Turn on airplane mode and reopen a study.
