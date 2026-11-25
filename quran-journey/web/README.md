# The Quran Journey: web app (PHP)

The same guided study experience as the mobile app, in any browser, built with plain PHP 8.2+ (no framework and
no Composer dependencies). It reads the verified bundled database `../app/assets/db/quran.db`, so the Quran
text is byte-for-byte the same as in the mobile app. It also uses the same progression rules: its study plan is
tested to be identical to the Flutter app's at 1, 2, 3 and 5 verses per study.

## Features

* **Onboarding:** the concept, your three session times, and reading comfort (translation, transliteration,
  Arabic size, theme).
* **Today:** your next study, today's three sessions (completed / ready / upcoming, in your time zone) and
  journey progress.
* **Study:** the same five tabs as the mobile app:
  * **Read:** verbatim Arabic, transliteration and translation, with verse-by-verse recitation and
    follow-along highlighting;
  * **Words:** Quran.com glosses plus Quranic Arabic Corpus roots, lemmas and morphology;
  * **Context**;
  * **Tafsir:** the original Arabic of Ibn Kathir, al-Tabari, al-Qurtubi and al-Baghawi, plus external
    English links;
  * **Reflect:** reflection prompts and private notes.

  It also has verse and study bookmarks, and a Complete button.
* **Journey:** all 114 surahs, and the studies in each surah.
* **Library:** search by reference, Arabic (diacritics ignored; Uthmani or everyday spelling), English, notes and
  bookmarks; a full Quran reader.
* **Saved:** verses, studies and reflections.
* **You:** schedule, reading and appearance, online sources on/off, export and erase, and a transfer code.

## Accounts, privacy and reminders

* **No accounts.** Each browser gets a random 192-bit token in an `HttpOnly`, `SameSite=Lax` cookie (`Secure`
  over HTTPS). Data is stored under the token's SHA-256 hash.
* **Another device:** go to *You ▸ Use on another device* and enter the **transfer code** there.
* **Reminders:** browsers can't reliably wake you at a set time without a push server. The app offers
  `/calendar.ics` instead: one daily repeating event per enabled session, with an alert, in your time zone.
  Import it into Apple Calendar, Google Calendar or Outlook. For built-in reminders and widgets, use the
  mobile app.
* **Security:**
  * a strict Content-Security-Policy (no inline scripts), plus `nosniff` and `frame-ancestors 'none'`;
  * CSRF tokens on every POST;
  * prepared SQL statements;
  * all output escaped.

## Run locally

```bash
cd quran-journey/web
php -S 127.0.0.1:8080 -t public public/index.php
# open http://127.0.0.1:8080
```

Requirements: PHP 8.2 or newer with `pdo_sqlite` and `mbstring`. The `curl` extension is recommended, for word
meanings and tafsir.

## Deploy

### Docker

Run from the `quran-journey/` folder:

```bash
docker build -f web/Dockerfile -t quran-journey-web .
docker run -d -p 8080:80 -v qj-web-data:/var/www/web/data quran-journey-web
```

Put it behind HTTPS (Caddy, nginx, Cloudflare and so on). If the proxy terminates TLS, set
`QJ_TRUST_PROXY=1` so cookies get the `Secure` flag.

### Shared hosting or any PHP host

1. Upload `web/` and `app/assets/db/quran.db` and `app/assets/content/groupings.json`, keeping the relative
   layout (`web/` beside `app/`).
2. Point the document root at `web/public`. Apache uses the included `.htaccess`; for nginx use
   `try_files $uri /index.php?$query_string;`.
3. Make `web/data/` writable by PHP and **not** web-accessible. It already sits outside `public/`.

### Environment variables (all optional)

| Variable | Default | Purpose |
|---|---|---|
| `QJ_QURAN_DB` | `../app/assets/db/quran.db` | Bundled Quran database |
| `QJ_WEB_DB` | `web/data/web.sqlite` | Profiles, progress, notes, bookmarks, cache |
| `QJ_API_BASE_URL` | (empty) | The backend in `../server`. When set, published, reviewed CMS content appears in studies |
| `QJ_TRUST_PROXY` | (unset) | `1` = trust `X-Forwarded-Proto` for HTTPS detection |

Back up `web/data/web.sqlite` regularly; it holds your users' journeys and reflections.

## Tests

```bash
php tests/run.php
```

This runs 29 tests:

* **Unit:** plan parity with the mobile app, missed days, time zones, reading ahead, search, morphology, and
  safe transliteration markup.
* **End-to-end HTTP:** a throwaway server is driven through onboarding, all study tabs, completion,
  bookmarks, reflections (including an XSS attempt), search, the calendar export, data export, the transfer
  code, path traversal and erase.
