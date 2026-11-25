# Interface contracts

These contracts connect the Flutter app, the native widgets (Android + iOS)
and the optional backend. Change them in one place only: here.

## 1. Identifiers

| Thing | Value |
|---|---|
| Android applicationId / namespace | `app.quranjourney.quran_journey` |
| iOS bundle id (app) | `app.quranjourney.quranJourney` |
| iOS bundle id (widget extension) | `app.quranjourney.quranJourney.QuranJourneyWidget` |
| iOS App Group | `group.app.quranjourney.shared` |
| iOS widget `kind` | `QuranJourneyWidget` |
| Deep-link scheme | `quranjourney` |

## 2. Global verse id

Verses are numbered 1..6236 in mushaf order (`verses.id` in `quran.db`).
A **study** is a contiguous verse range inside one surah: `start..end` (global ids).

## 3. Deep links

| URI | Opens |
|---|---|
| `quranjourney://study/<start>-<end>` | The study covering global verses start..end |
| `quranjourney://next` | The user's next unread study |
| `quranjourney://today` | Home (today's sessions) |
| `quranjourney://verse/<surah>:<ayah>` | Reader at that verse |

Widgets and notifications only ever emit these URIs.

## 4. Home-widget shared data

Written by the Flutter app with `home_widget` (Android: `HomeWidgetPreferences`
SharedPreferences; iOS: `UserDefaults(suiteName: "group.app.quranjourney.shared")`).
All values are strings or ints. Widgets must render sensibly if any key is missing
(first launch): show the brand name and "Open to begin your journey".

| Key | Type | Example | Meaning |
|---|---|---|---|
| `qj_brand` | String | `The Quran Journey` | App name (configurable branding) |
| `qj_arabic` | String | `ٱلْحَمْدُ لِلَّهِ رَبِّ ٱلْعَـٰلَمِينَ` | Arabic of the featured verse (verbatim Tanzil) – may be empty if too long for a widget |
| `qj_translation` | String | `Praise be to Allah, Lord of the Worlds,` | Translation of the featured verse |
| `qj_translation_name` | String | `Pickthall` | Translator attribution |
| `qj_ref` | String | `Al-Faatiha 1:2` | Reference of the featured verse |
| `qj_study_title` | String | `Al-Faatiha 1:1–4` | Current/next study |
| `qj_study_link` | String | `quranjourney://study/1-4` | Deep link for the study |
| `qj_progress_permille` | int | `12` | Journey progress 0..1000 (verses completed / 6236) |
| `qj_progress_label` | String | `1.2% of the Quran · Surah 2 of 114` | Human label |
| `qj_today_done` | int | `1` | Studies completed today |
| `qj_today_total` | int | `3` | Enabled sessions per day |
| `qj_sessions` | String (JSON) | `[{"label":"Morning","minutes":450,"enabled":true,"done":true}]` | Today's sessions; `minutes` = minutes after local midnight |
| `qj_paused_until` | int | `0` | Epoch millis; notifications paused until this time (0 = not paused) |
| `qj_updated_at` | int | `1764050000000` | Epoch millis of last write |
| `qj_dark` | int | `0`/`1`/`-1` | Theme preference (-1 = follow system) |

Widgets compute "next session" themselves from `qj_sessions` and the device clock,
so that the label stays correct between app launches.

## 5. Backend API (optional – app works fully offline without it)

Base URL is compiled in with `--dart-define=QJ_API_BASE_URL=https://…` or set in
Settings ▸ Account ▸ Server. All bodies are JSON. Errors: `{ "error": "message" }`
with a 4xx/5xx status.

### Auth
* `POST /api/auth/register` `{email, password}` → `201 {token, user:{id,email,role}}`
* `POST /api/auth/login` `{email, password}` → `200 {token, user}`
* `GET /api/auth/me` (Bearer) → `{user}`
* `DELETE /api/account` (Bearer) `{password}` → `204` – deletes the user and all their data
* `GET /api/account/export` (Bearer) → all user data as JSON

Token: `Authorization: Bearer <token>`; opaque to the client; expires after 30 days.

### Sync (Bearer)
`POST /api/sync`
```json
{ "since": "2026-11-25T10:00:00.000Z or null",
  "changes": [
    { "kind": "note|bookmark|progress", "id": "uuid", "updated_at": "ISO-8601",
      "deleted": false, "base_updated_at": "ISO-8601 or null", "data": { } }
  ] }
```
→
```json
{ "server_time": "ISO", "changes": [ same shape, records changed on server since `since` ],
  "conflicts": [ { "kind": "note", "id": "uuid", "server": { record }, "resolution": "kept_both" } ] }
```
Rules:
* Last-writer-wins by `updated_at` for bookmarks and progress.
* Notes: if the server copy changed after the client's `base_updated_at` and the text differs,
  the server keeps the server copy and stores the client's text as a **new note** (new id,
  `data.conflict_of = original id`). Both are returned. User text is never discarded.
* Deletes are tombstones (`deleted: true`), kept for 90 days.

`data` shapes:
* note: `{ "study_start": int, "study_end": int, "verse_id": int|null, "text": string, "created_at": ISO }`
* bookmark: `{ "type": "verse|study|tafsir|reflection", "verse_start": int, "verse_end": int, "ref_id": string|null, "label": string|null, "created_at": ISO }`
* progress: `{ "verse_start": int, "verse_end": int, "completed_at": ISO }` (one record per completed study)

### Published study content (no auth)
`GET /api/content/published?since=<ISO|empty>` →
```json
{ "server_time": "ISO",
  "items": [ ContentItem ],
  "groupings": [ { "id": "uuid", "surah": 1, "start_ayah": 1, "end_ayah": 4, "rationale": "…", "status": "published", "updated_at": "ISO" } ],
  "sources": [ Source ], "scholars": [ Scholar ], "removed_ids": [ "uuid" ] }
```
Only items with `status = "published"` are ever returned. Unpublished items appear in
`removed_ids` so clients delete their cached copy.

ContentItem:
```json
{ "id": "uuid", "type": "context|tafsir|reflection|word_note|surah_intro",
  "category": "direct_quotation|paraphrase|editorial_summary|ai_assisted",
  "surah": 1, "start_ayah": 1, "end_ayah": 4, "word_position": null,
  "title": "string|null", "body": "string (plain text, paragraphs separated by blank lines)",
  "language": "en", "source_id": "uuid|null", "scholar_id": "uuid|null",
  "citation": { "volume": "…", "page": "…", "edition": "…", "url": "…" },
  "status": "published", "reviewer": "name|null", "verified_at": "ISO|null",
  "version": 3, "updated_at": "ISO" }
```
Source: `{ id, title, author, edition, publisher, year, url, license, notes }`
Scholar: `{ id, name, death_year_ah, death_year_ce, bio_url }`

### Content workflow (admin)
States: `draft → source_verified → reviewed → approved → published` (and `published → unpublished`).
* `editor`: create/edit drafts, mark `source_verified`.
* `reviewer`: mark `reviewed` / `approved` (cannot approve own item).
* `admin`: everything, publish/unpublish, manage users.
Any edit to an item's body/citation resets its status to `draft` and bumps `version`.
