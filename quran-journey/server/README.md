# The Quran Journey – backend & admin dashboard

**Optional.** The mobile app works fully offline without it. The backend adds:

* accounts and encrypted-in-transit sync of notes, bookmarks and progress across devices;
* a content-management dashboard (`/admin`) with a review workflow, so verified study
  content (context, tafsir excerpts, reflections, word notes, study-grouping overrides)
  can be published to the app without an app update.

Zero runtime dependencies: Node.js ≥ 22.13 built-ins only (`node:http`, `node:sqlite`,
`node:crypto`). Data is one SQLite file.

## Run locally

```bash
cd quran-journey/server
npm run seed                                   # sources, scholars, reciters, translations (idempotent)
QJ_ADMIN_PASSWORD='choose-a-long-password' npm run create-admin -- you@example.org
npm start                                      # http://localhost:8787/admin
npm test                                       # 23 tests, node:test
```

`create-admin` prompts for the password (hidden) when `QJ_ADMIN_PASSWORD` is not set.
Running it for an existing email promotes that user to admin and resets the password.

## Configuration (environment variables)

| Variable | Default | Purpose |
|---|---|---|
| `QJ_PORT` | `8787` | Listen port |
| `QJ_HOST` | `0.0.0.0` | Listen address |
| `QJ_DB_PATH` | `server/data/quran-journey.sqlite` | Server database (users, sync data, content) |
| `QJ_QURAN_DB_PATH` | `../app/assets/db/quran.db` | Bundled Quran DB, opened **read-only** for the verse browser |
| `QJ_CORS_ORIGINS` | *(empty)* | Comma-separated browser origins allowed to call the API. The mobile app sends no `Origin` and is unaffected. The dashboard is same-origin and needs nothing here. |
| `QJ_TRUST_PROXY` | *(unset)* | Set `1` behind a reverse proxy so login rate-limiting uses `X-Forwarded-For` |

No secrets are needed: passwords are hashed with scrypt (per-user salt), and session
tokens are random 256-bit values stored only as SHA-256 hashes, expiring after 30 days.

## Roles and workflow

`user` (app sync only) → `editor` → `reviewer` → `admin`. Only admins assign roles.

Content moves `draft → source_verified → reviewed → approved → published`
(`published → unpublished`). Editors draft and verify sources; reviewers review and
approve (never their own item); admins publish. **Any edit returns an item to draft**
and bumps its version, and an edited published item is withdrawn from the app until it is
approved again. Every administrative action is written to the audit log.

Each item records its category — *direct quotation*, *paraphrase*, *editorial summary* or
*AI-assisted* — plus source, scholar and citation (volume, page, edition, URL). A direct
quotation must cite a source.

**Quran text is read-only.** The verse browser shows the verbatim Tanzil text; every
write endpoint for verses returns `405`. To update the text, replace the Tanzil source file
and rebuild with `tools/build_content.py`, which re-runs the integrity checks.

## Deploy

HTTPS is required in production (tokens and passwords travel in requests). Put the server
behind any TLS-terminating host or proxy.

**Docker (any host)** – build from `quran-journey/`:

```bash
docker build -f server/Dockerfile -t quran-journey-server .
docker run -d -p 8787:8787 -v qj-data:/data --name qj quran-journey-server
docker exec -it qj node bin/seed.js
docker exec -it qj node bin/create-admin.js you@example.org
```

**Fly.io**: `fly launch --dockerfile server/Dockerfile` from `quran-journey/`, then
`fly volumes create qj_data --size 1` and mount it at `/data` in `fly.toml`
(`[mounts] source="qj_data" destination="/data"`). Fly provides HTTPS.

**Render**: new Web Service → Docker, Dockerfile path `server/Dockerfile`, root directory
`quran-journey`, add a persistent disk mounted at `/data`. Render provides HTTPS.

Then set the server URL in the app (Settings ▸ Account ▸ Server), or build the app with
`--dart-define=QJ_API_BASE_URL=https://your-host`.

## Backup

The whole state is `QJ_DB_PATH` (SQLite in WAL mode). Use SQLite's online backup so the
copy is consistent while the server runs:

```bash
node --no-warnings -e "const {DatabaseSync}=require('node:sqlite');new DatabaseSync(process.argv[1]).exec(\"VACUUM INTO '\"+process.argv[2]+\"'\")" /data/quran-journey.sqlite /data/backup-$(date +%F).sqlite
```

Copy the backup off the host. Restoring = stopping the server and replacing the file.

## API

Implemented as specified in [`../docs/CONTRACTS.md`](../docs/CONTRACTS.md) §5, plus:
`POST /api/auth/logout`, `GET /api/audio/reciters` (public), `GET /healthz`, and the admin API
under `/api/admin/*` (content, review-queue, stats, sources, scholars, groupings, audio,
translations, surahs (read-only), users, audit).
