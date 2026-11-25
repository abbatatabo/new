# Data architecture

The data lives in three places, each with a different owner and lifecycle.

## 1. Bundled content database: `app/assets/db/quran.db` (read-only, ships in the app)

Built only by `tools/build_content.py`; the schema is in `content/schema/quran_bundle.sql`.

| Table | Purpose |
|---|---|
| `meta` | Schema/content version, Tanzil and corpus copyright notices, source SHA-256s, Arabic text checksum |
| `surahs` | 114 rows: names (Arabic, transliterated, English), Meccan/Medinan, revelation order, verse count, first global verse id, rukus |
| `verses` | 6,236 rows: global id, surah, ayah, verbatim Uthmani text, bismillah, juz, page, sajdah, normalised search index |
| `sources` | Every bundled dataset: title, author, edition, URL, licence, verification status, SHA-256 |
| `translations` | Translation/transliteration catalogue (multilingual-ready: a `language` column) |
| `translation_text` | One row per (translation, verse) |
| `words` | 77,429 rows: Tanzil word, root, lemma, part of speech, verbatim corpus segments |

When an app update ships a new database, the app re-copies it on first launch. User data is never stored here.

## 2. Private user database: `user.db` (on the device)

| Table | Purpose |
|---|---|
| `completions` | One row per completed study (verse range, time, journey number); progress is derived from these |
| `notes` | Personal reflections, tied to a study (and optionally a verse) |
| `bookmarks` | Saved verses, studies, tafsir excerpts and reflections |
| `cache` | Word glosses and tafsir texts fetched online, kept for offline use |
| `content_items`, `groupings` | Published CMS content and grouping overrides received from the server |
| `kv` | Sync cursors and the CMS source and scholar catalogues |

Every user row has `updated_at`, `deleted` (a tombstone) and `synced`, which supports offline edits and
conflict-safe sync. Settings live in `SharedPreferences`; the sign-in token is in the Keychain or Keystore.
Notification schedules are derived from settings and rebuilt on each launch. Widget data lives in the shared
store described in [CONTRACTS.md](CONTRACTS.md) §4.

On Android the user database is excluded from cloud backup and device transfer, so reflections stay private.

## 3. Server database (optional backend, SQLite via `node:sqlite`)

| Table | Purpose |
|---|---|
| `users` | Email, scrypt hash and salt, role (user / editor / reviewer / admin) |
| `tokens` | Hashed bearer tokens with expiry |
| `login_failures` | Rate limiting |
| `user_records` | Synced notes, bookmarks and progress (JSON, per user), with tombstones |
| `sources`, `scholars` | Citation catalogue |
| `content_items` | Study content with category, citation, verse range, workflow status, version, author, reviewer and verification date |
| `groupings` | Study-grouping overrides with rationale and status |
| `audio_reciters`, `translations_meta` | Audio and translation metadata |
| `removals` | Ids of unpublished items, so clients delete their copies |
| `audit_log` | Every admin change |

The Quran text is not stored or editable on the server. The admin dashboard reads it from the bundled
database, read-only, because the Tanzil licence forbids changes.

## Sync semantics

* **Bookmarks and progress:** last writer wins.
* **Notes:** if both sides changed, both versions are kept and the app labels the copy.
* **Deletes:** tombstones, kept for 90 days.

Details are in [CONTRACTS.md](CONTRACTS.md) §5. Both behaviours are verified by
`app/integration_server_test/`.
