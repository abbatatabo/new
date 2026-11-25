-- Read-only bundled content database shipped inside the app (assets/db/quran.db).
-- Built by tools/build_content.py from verbatim source files. Never edited by hand.

CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);

CREATE TABLE surahs (
  number INTEGER PRIMARY KEY,           -- 1..114
  name_ar TEXT NOT NULL,
  name_translit TEXT NOT NULL,
  name_en TEXT NOT NULL,
  revelation_type TEXT NOT NULL,        -- Meccan | Medinan (Tanzil metadata)
  revelation_order INTEGER NOT NULL,    -- Tanzil metadata
  ayah_count INTEGER NOT NULL,
  first_verse_id INTEGER NOT NULL,      -- global verse id of ayah 1
  rukus INTEGER NOT NULL
);

CREATE TABLE verses (
  id INTEGER PRIMARY KEY,               -- global 1..6236 in mushaf order
  surah INTEGER NOT NULL REFERENCES surahs(number),
  ayah INTEGER NOT NULL,
  text_uthmani TEXT NOT NULL,           -- verbatim Tanzil Uthmani text
  bismillah TEXT,                       -- Tanzil bismillah attribute (ayah 1 of surahs 2-114 except 9)
  juz INTEGER NOT NULL,
  page INTEGER NOT NULL,                -- Madinah mushaf page (Tanzil metadata)
  sajdah TEXT,                          -- recommended | obligatory | NULL
  search_ar TEXT NOT NULL,              -- normalised search index, never displayed
  UNIQUE (surah, ayah)
);

CREATE TABLE sources (
  id TEXT PRIMARY KEY,
  content_type TEXT NOT NULL,
  work_title TEXT NOT NULL,
  author TEXT NOT NULL,
  edition TEXT,
  url TEXT,
  license TEXT NOT NULL,
  verification_status TEXT NOT NULL,
  sha256 TEXT
);

CREATE TABLE translations (
  id INTEGER PRIMARY KEY,
  code TEXT NOT NULL UNIQUE,
  kind TEXT NOT NULL,                   -- translation | transliteration
  name TEXT NOT NULL,
  translator TEXT NOT NULL,
  language TEXT NOT NULL,
  source_id TEXT NOT NULL REFERENCES sources(id)
);

CREATE TABLE translation_text (
  translation_id INTEGER NOT NULL REFERENCES translations(id),
  verse_id INTEGER NOT NULL REFERENCES verses(id),
  text TEXT NOT NULL,
  PRIMARY KEY (translation_id, verse_id)
) WITHOUT ROWID;

CREATE TABLE words (
  verse_id INTEGER NOT NULL REFERENCES verses(id),
  position INTEGER NOT NULL,            -- corpus word number
  text_uthmani TEXT,                    -- the matching Tanzil token (NULL if alignment failed)
  root_bw TEXT,
  root_ar TEXT,                         -- root letters, space separated (corpus ROOT)
  lemma_bw TEXT,
  lemma_ar TEXT,                        -- corpus LEM
  pos TEXT,                             -- part of speech of the stem segment
  segments TEXT NOT NULL,               -- verbatim corpus rows: FORM\tTAG\tFEATURES, one segment per line (Buckwalter)
  PRIMARY KEY (verse_id, position)
) WITHOUT ROWID;

