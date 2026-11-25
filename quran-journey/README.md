# The Quran Journey

**3 verses. 3 moments. Every day.**

A calm, offline-first Quran study companion for Android and iOS. It guides you through the whole Quran in
order, from Al-Fatihah to An-Nas, a few verses at a time, in three study sessions a day at times you choose.

* No ads, no tracking, no streaks, no guilt.
* Works fully offline: Quran text, translations, transliteration and word morphology are bundled.
* Real home-screen widgets (Android and iOS) and real scheduled local notifications.
* Every piece of content has a source. Nothing is generated and presented as scripture or scholarship.

> The product name is a placeholder and can be changed in one place: see [docs/BRANDING.md](docs/BRANDING.md).

---

## Contents

| Path | What it is |
|---|---|
| `app/` | Flutter app (Android + iOS), with native Android widgets (Kotlin) and an iOS WidgetKit extension (SwiftUI) |
| `web/` | **Web app (PHP 8, no dependencies)**: the same study experience in any browser; see [web/README.md](web/README.md) |
| `server/` | Optional backend: accounts, sync, content-management API and **admin dashboard** (Node 22, zero dependencies) |
| `content/` | Verbatim source datasets, database schema and the integrity report |
| `tools/build_content.py` | Builds and verifies the bundled database `app/assets/db/quran.db` |
| `tools/run_server_integration.sh` | Runs the app's sync code against a throwaway server |
| `design/` | Brand mark and icon sources |
| `docs/` | Installation, release, content sources, database, testing, iOS, contracts |

## Installing

* **Android:** [docs/INSTALL-ANDROID.md](docs/INSTALL-ANDROID.md). Download `releases/android/the-quran-journey-1.0.0.apk` and install it.
* **Web (any browser, including iPhone):** run or deploy `web/`; see [web/README.md](web/README.md).
* **iPhone:** [docs/IOS.md](docs/IOS.md). This needs a Mac with Xcode; there is no IPA yet (see below).

## Technology choices and why

| Concern | Choice | Reason |
|---|---|---|
| App UI and logic | **Flutter 3.50 (Dart)**, one codebase | Precise control of typography (essential for Arabic), consistent rendering on both platforms, fast development, mature plugins for notifications and widgets |
| Android widgets | **Native Kotlin `AppWidgetProvider` + RemoteViews** (via `home_widget`) | Real home-screen widgets with no Flutter engine at render time; cheap and reliable to refresh |
| iOS widgets | **Native SwiftUI WidgetKit extension** | The only way to build real iOS widgets; timeline entries at each session time |
| Notifications | `flutter_local_notifications` + `timezone` | Local scheduling with no server dependency; time-zone and DST aware; re-armed after reboot (Android) |
| Offline data | **SQLite** (bundled read-only `quran.db` + private `user.db`) | Proper relational model, fast search, no giant JSON |
| Audio | `just_audio`, EveryAyah verse files | Verse-level playlists, follow-along highlighting, optional offline download |
| Backend (optional) | **Node 22, `node:sqlite`, zero npm dependencies** | Tiny attack surface, runs anywhere (Docker, any VPS, Fly.io, Render), trivially testable |
| Auth tokens on device | `flutter_secure_storage` (Keychain / Keystore) | Credentials never sit in plain preferences |

The app is **local-first**. With no server configured it is complete: reading, studying, progress, notes,
bookmarks, widgets and reminders all work. A server adds only cross-device sync and the ability to publish
new reviewed study content without an app update.

## Feature overview

* **Onboarding:** five short screens covering the concept, your three session times, reading comfort,
  notification permission (optional) and starting at Al-Fatihah.
* **Today:** your next study, today's three sessions (completed / ready / upcoming), a gentle welcome back
  after a break, and journey progress.
* **Study** (tabs):
  * **Read:** verbatim Uthmani Arabic (Amiri Quran font, right-to-left, adjustable size, never truncated),
    transliteration (toggle), translation with translator attribution, recitation with verse highlighting,
    verse bookmarks.
  * **Words:** every word with its Quran.com gloss and transliteration; root letters, lemma, part of speech,
    and a full morphological breakdown from the Quranic Arabic Corpus; how often the root occurs.
  * **Context:** surah facts (Tanzil metadata), where the passage sits, quoted neighbouring verses, the
    grouping rationale, and reviewed historical context once published.
  * **Tafsir:** reviewed CMS tafsir notes (labelled by category, with citations); the original Arabic text of
    Ibn Kathir, al-Tabari, al-Qurtubi and al-Baghawi; links to copyrighted English tafsir.
  * **Reflect:** reflection questions (clearly labelled as not tafsir) and your private notes.
* **Journey:** all 114 surahs with per-surah progress, the current position, and the studies in each surah.
* **Library:** search by surah, reference (`2:255`), Arabic (ignores diacritics; Uthmani or everyday spelling),
  translation text, your saved items and your notes; an archive of completed studies; a full Quran reader.
* **Saved:** verses, studies and reflections.
* **You:** schedule, reminders (style, pause, quiet hours, precise timing), translation, transliteration,
  text size, reciter, verses per study, online sources on/off, theme, account and sync, export and erase data,
  privacy, and sources & methodology.

## Progression rule (transparent, verse-based)

Defined in `app/lib/domain/grouping.dart` and `progress.dart`, and explained in the app under
*You ▸ Sources & methodology*.

1. Studies follow mushaf order and never cross a surah boundary.
2. Each study takes the next 3 verses (configurable: 1, 2, 3 or 5) …
3. … but stops early if the study would go over 75 Arabic words, so 2:282 is studied alone.
4. A lone final verse of a surah joins the previous study, if that stays within the limit.
5. Editorial overrides (bundled, or published from the CMS) replace the rule where it would split a passage
   awkwardly, and each one carries a rationale. Al-Fatihah is studied as 1:1–4 and 1:5–7.
6. Progress is the set of **verses you have completed**. "Next" is always the first study that still has an
   unread verse, so missed days never skip a verse and re-reading never double-counts.
   * **Missed days:** today's three slots simply continue from where you left off.
   * **Reading ahead:** allowed.
   * **Changing the study size:** keeps every completed verse.
   * **After An-Nas:** you can begin a new journey; the previous one is kept.

At the default size the plan has **2,162 studies**: about 721 days at three a day.

## Content accuracy (summary)

Full detail is in [docs/CONTENT-SOURCES.md](docs/CONTENT-SOURCES.md).

* **Quran text:** Tanzil Uthmani 1.1, verbatim. The build pipeline checks:
  * 114 surahs, 6,236 verses and the canonical Hafs per-surah counts;
  * the placement of every bismillah;
  * an exact byte-for-byte match with the source, plus a SHA-256 checksum.

  The app tests independently re-compare every verse against the source file.
* **Translations:** Pickthall (1930) and Yusuf Ali (original 1934–38 text), both public domain in
  life+70 jurisdictions. The digital text is from Tanzil.
* **Transliteration:** Tanzil's English transliteration.
* **Morphology:** Quranic Arabic Corpus v0.4 (roots, lemmas, part of speech and features). It aligns word
  for word with the Tanzil text in 6,232 of 6,236 verses; the other 4 fall back to the corpus form, with a note.
* **Word glosses and classical Arabic tafsir:** Quran.com API, loaded on demand and cached. Each is clearly
  attributed and shown verbatim.
* **Reviewed study content** (context, tafsir summaries, reflections): created in the CMS and shown only
  after the full workflow `draft → source_verified → reviewed → approved → published`. Nobody can approve
  their own item. Each item is labelled *direct quotation*, *paraphrase*, *editorial summary* or
  *AI-assisted*. **No such content has been published yet:** this needs qualified human reviewers. The app
  says so wherever the content is missing.

## Admin dashboard and backend

See [server/README.md](server/README.md): setup, environment variables, Docker deployment, creating the
first admin, and backups. Then open `https://your-server/admin`. In the app, connect the server under
*You ▸ Account & sync*, or build it in with `--dart-define=QJ_API_BASE_URL=https://…`.

## Building from source

```bash
# Content database (only needed if sources change)
python3 -I tools/build_content.py

# App
cd app
flutter pub get
flutter test                              # 57 tests
flutter build apk --release               # needs android/key.properties, see docs/RELEASE.md
flutter build appbundle --release

# Native Android widget tests (Robolectric, no emulator needed)
cd android && ./gradlew :app:testDebugUnitTest

# Backend
cd ../../server && npm test               # 23 tests
cd .. && tools/run_server_integration.sh  # app ↔ server
```

## Test results and known limitations

Full detail is in [docs/TESTING.md](docs/TESTING.md).

**Verified here:**
* 57 Flutter tests (content integrity, progression, scheduling, deep links, data, full UI flows with
  screenshots).
* 7 Robolectric tests on the native Android widgets.
* 23 backend tests and 2 app↔server integration tests.
* The release APK builds, signs and verifies.

**Not verified here:**
* **On a physical Android device:** this sandbox has no hardware virtualisation, so no emulator could run.
  Untested on a real phone: notification delivery and timing, reboot behaviour, the widgets on a real
  launcher, audio playback and the system permission dialogs.
* **The iOS app and widget have not been compiled.** No Mac or Xcode was available, so there is no IPA.
  The project is fully configured; see [docs/IOS.md](docs/IOS.md).
* **Unpublished study content:** no reviewed context, tafsir summaries or reflections have been published,
  because that needs human reviewers.
* **Reminder timing is decided by the OS:** reminders are scheduled 7 days ahead and refreshed whenever the
  app is opened. Battery savers can delay them.
