import fs from 'node:fs';
import path from 'node:path';
import { DatabaseSync } from 'node:sqlite';

const SCHEMA = `
PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS users (
  id TEXT PRIMARY KEY,
  email TEXT NOT NULL UNIQUE COLLATE NOCASE,
  password_hash TEXT NOT NULL,
  salt TEXT NOT NULL,
  role TEXT NOT NULL DEFAULT 'user' CHECK (role IN ('user','editor','reviewer','admin')),
  created_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS tokens (
  token_hash TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  created_at TEXT NOT NULL,
  expires_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS login_failures (
  key TEXT NOT NULL,
  at INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_login_failures ON login_failures(key, at);

-- User data synchronised from devices (notes, bookmarks, progress)
CREATE TABLE IF NOT EXISTS user_records (
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  kind TEXT NOT NULL CHECK (kind IN ('note','bookmark','progress')),
  id TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  deleted INTEGER NOT NULL DEFAULT 0,
  data TEXT NOT NULL,
  server_updated_at TEXT NOT NULL,
  PRIMARY KEY (user_id, kind, id)
);
CREATE INDEX IF NOT EXISTS idx_user_records_sync ON user_records(user_id, server_updated_at);

CREATE TABLE IF NOT EXISTS sources (
  id TEXT PRIMARY KEY,
  title TEXT NOT NULL,
  author TEXT,
  edition TEXT,
  publisher TEXT,
  year TEXT,
  url TEXT,
  license TEXT NOT NULL,
  notes TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS scholars (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  death_year_ah INTEGER,
  death_year_ce INTEGER,
  bio_url TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS content_items (
  id TEXT PRIMARY KEY,
  type TEXT NOT NULL CHECK (type IN ('context','tafsir','reflection','word_note','surah_intro')),
  category TEXT NOT NULL CHECK (category IN ('direct_quotation','paraphrase','editorial_summary','ai_assisted')),
  surah INTEGER NOT NULL CHECK (surah BETWEEN 1 AND 114),
  start_ayah INTEGER NOT NULL,
  end_ayah INTEGER NOT NULL,
  word_position INTEGER,
  title TEXT,
  body TEXT NOT NULL,
  language TEXT NOT NULL DEFAULT 'en',
  source_id TEXT REFERENCES sources(id) ON DELETE SET NULL,
  scholar_id TEXT REFERENCES scholars(id) ON DELETE SET NULL,
  citation TEXT NOT NULL DEFAULT '{}',
  status TEXT NOT NULL DEFAULT 'draft'
    CHECK (status IN ('draft','source_verified','reviewed','approved','published','unpublished')),
  reviewer TEXT,
  verified_at TEXT,
  version INTEGER NOT NULL DEFAULT 1,
  created_by TEXT,
  updated_by TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_content_status ON content_items(status, updated_at);

CREATE TABLE IF NOT EXISTS groupings (
  id TEXT PRIMARY KEY,
  surah INTEGER NOT NULL CHECK (surah BETWEEN 1 AND 114),
  start_ayah INTEGER NOT NULL,
  end_ayah INTEGER NOT NULL,
  rationale TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','published','unpublished')),
  created_by TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS audio_reciters (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  style TEXT,
  base_url TEXT NOT NULL,
  file_pattern TEXT NOT NULL DEFAULT '{surah3}{ayah3}.mp3',
  license TEXT NOT NULL,
  source_url TEXT,
  enabled INTEGER NOT NULL DEFAULT 1,
  notes TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS translations_meta (
  id TEXT PRIMARY KEY,
  code TEXT NOT NULL UNIQUE,
  name TEXT NOT NULL,
  translator TEXT NOT NULL,
  language TEXT NOT NULL,
  license TEXT NOT NULL,
  source_url TEXT,
  enabled INTEGER NOT NULL DEFAULT 1,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

-- Items that left the published set; clients delete cached copies.
CREATE TABLE IF NOT EXISTS removals (
  id TEXT NOT NULL,
  kind TEXT NOT NULL,
  removed_at TEXT NOT NULL,
  PRIMARY KEY (id, kind)
);

CREATE TABLE IF NOT EXISTS audit_log (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id TEXT,
  user_email TEXT,
  action TEXT NOT NULL,
  entity TEXT NOT NULL,
  entity_id TEXT,
  detail TEXT,
  at TEXT NOT NULL
);
`;

export function openDatabase(dbPath) {
  if (dbPath !== ':memory:') fs.mkdirSync(path.dirname(dbPath), { recursive: true });
  const db = new DatabaseSync(dbPath);
  db.exec('PRAGMA journal_mode = WAL;');
  db.exec(SCHEMA);
  return db;
}

/** Opens the bundled Quran database strictly read-only (verse text is immutable). */
export function openQuranDatabase(quranDbPath) {
  if (!quranDbPath || !fs.existsSync(quranDbPath)) return null;
  return new DatabaseSync(quranDbPath, { readOnly: true });
}

export function tx(db, fn) {
  db.exec('BEGIN IMMEDIATE');
  try {
    const r = fn();
    db.exec('COMMIT');
    return r;
  } catch (e) {
    db.exec('ROLLBACK');
    throw e;
  }
}
