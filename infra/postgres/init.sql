-- Postgres schema for content-service, migrated from
-- quraan-agent/quraan_agent/metadata_store.py's METADATA_SCHEMA (SQLite).
--
-- Same natural composite keys as the SQLite original (surah_id, ayah_id,
-- etc.) so the JSON wire shape app.js already depends on doesn't change.
-- Foreign keys added since SQLite had none - the data is already
-- internally consistent (it's been running in prod), so this is safe.

CREATE TABLE surahs (
  id          INTEGER PRIMARY KEY,
  name_ar     TEXT,
  name_en     TEXT,
  name_tr     TEXT,
  ayah_count  INTEGER
);

CREATE TABLE ayahs (
  surah_id            INTEGER NOT NULL REFERENCES surahs(id),
  ayah_id             INTEGER NOT NULL,
  global_ayah_id      INTEGER,
  ayah_ar             TEXT NOT NULL,
  ayah_ar_normalized  TEXT,
  ayah_en             TEXT,
  ayah_tr             TEXT,
  PRIMARY KEY (surah_id, ayah_id)
);

CREATE TABLE reciters (
  reciter_id      TEXT PRIMARY KEY,
  display_name    TEXT,
  style           TEXT,
  source_quality  TEXT
);

CREATE TABLE ayah_audio (
  surah_id         INTEGER NOT NULL,
  ayah_id          INTEGER NOT NULL,
  reciter_id       TEXT NOT NULL REFERENCES reciters(reciter_id),
  audio_asset_id   TEXT,
  source_dataset   TEXT,
  source_revision  TEXT,
  PRIMARY KEY (surah_id, ayah_id, reciter_id),
  FOREIGN KEY (surah_id, ayah_id) REFERENCES ayahs(surah_id, ayah_id)
);

CREATE TABLE words (
  surah_id            INTEGER NOT NULL,
  ayah_id             INTEGER NOT NULL,
  word_id             TEXT NOT NULL,
  word_index          INTEGER NOT NULL,
  word_ar             TEXT NOT NULL,
  word_ar_normalized  TEXT,
  word_en             TEXT,
  word_tr             TEXT,
  audio_asset_id      TEXT,
  PRIMARY KEY (surah_id, ayah_id, word_index),
  FOREIGN KEY (surah_id, ayah_id) REFERENCES ayahs(surah_id, ayah_id)
);

CREATE TABLE tafsir_passages (
  surah_id        INTEGER NOT NULL,
  ayah_id         INTEGER NOT NULL,
  tafsir_book     TEXT NOT NULL,
  tafsir_content  TEXT NOT NULL,
  PRIMARY KEY (surah_id, ayah_id, tafsir_book),
  FOREIGN KEY (surah_id, ayah_id) REFERENCES ayahs(surah_id, ayah_id)
);

-- Derived from Tanzil's quran-data.xml (CC-BY) - see
-- quraan-agent/scripts/import_mushaf_layout.py and
-- /data/quraan-rag/data/mushaf_layout_raw/SOURCE_README.md. One row per
-- ayah (the source only has page-level boundaries, no line-level data).
CREATE TABLE mushaf_pages (
  surah_id     INTEGER NOT NULL,
  ayah_id      INTEGER NOT NULL,
  page_number  INTEGER NOT NULL,
  juz          INTEGER,
  manzil       INTEGER,
  ruku_global  INTEGER,
  PRIMARY KEY (surah_id, ayah_id),
  FOREIGN KEY (surah_id, ayah_id) REFERENCES ayahs(surah_id, ayah_id)
);

-- Word-level start/end timestamps within one reciter's ayah_audio clip,
-- from CTC forced alignment (known text, unknown timing - not open ASR)
-- against jonatasgrosman/wav2vec2-large-xlsr-53-arabic. See
-- quraan-agent/scripts/align_ayah_words.py and quraan_agent/ctc_align.py.
-- Full-corpus run (minshawy_murattal): 77,429/77,429 words aligned,
-- 6,236/6,236 ayahs covered, 0 monotonicity violations.
CREATE TABLE ayah_word_timings (
  surah_id     INTEGER NOT NULL,
  ayah_id      INTEGER NOT NULL,
  reciter_id   TEXT NOT NULL REFERENCES reciters(reciter_id),
  word_index   INTEGER NOT NULL,
  start_ms     INTEGER NOT NULL,
  end_ms       INTEGER NOT NULL,
  confidence   DOUBLE PRECISION,
  align_model  TEXT,
  PRIMARY KEY (surah_id, ayah_id, reciter_id, word_index),
  FOREIGN KEY (surah_id, ayah_id, word_index) REFERENCES words(surah_id, ayah_id, word_index)
);

CREATE INDEX idx_ayahs_ref  ON ayahs(surah_id, ayah_id);
CREATE INDEX idx_words_ref  ON words(surah_id, ayah_id);
CREATE INDEX idx_audio_ref  ON ayah_audio(surah_id, ayah_id);
CREATE INDEX idx_tafsir_ref ON tafsir_passages(surah_id, ayah_id);
CREATE INDEX idx_word_timings_ref ON ayah_word_timings(surah_id, ayah_id);
CREATE INDEX idx_mushaf_pages_page ON mushaf_pages(page_number);

-- Fast substring search for the LIKE-fallback tier (today's _text_search()
-- in app/server.py, moving to a content-service endpoint) - same fallback
-- behavior the monolith already has, just made practical at scale.
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE INDEX idx_ayahs_en_trgm ON ayahs USING gin (ayah_en gin_trgm_ops);
CREATE INDEX idx_ayahs_tr_trgm ON ayahs USING gin (ayah_tr gin_trgm_ops);

-- account-service: user accounts + progress history. recitation_events is
-- an append-only log (not a "current position" pointer table) - resume
-- position is just the latest 'recited' row per user, and the same rows
-- power the dashboard, so there's only one source of truth to keep
-- consistent instead of two.
CREATE TABLE users (
  id             SERIAL PRIMARY KEY,
  email          TEXT NOT NULL UNIQUE,
  password_hash  TEXT NOT NULL,
  display_name   TEXT,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE recitation_events (
  id          SERIAL PRIMARY KEY,
  user_id     INTEGER NOT NULL REFERENCES users(id),
  surah_id    INTEGER NOT NULL,
  ayah_id     INTEGER NOT NULL,
  event_type  TEXT NOT NULL,  -- 'recited' | 'memory_miss'
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE pronunciation_attempts (
  id          SERIAL PRIMARY KEY,
  user_id     INTEGER NOT NULL REFERENCES users(id),
  surah_id    INTEGER NOT NULL,
  ayah_id     INTEGER NOT NULL,
  score       INTEGER NOT NULL,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_recitation_events_user ON recitation_events(user_id, created_at DESC);
CREATE INDEX idx_pronunciation_attempts_user ON pronunciation_attempts(user_id, created_at DESC);
