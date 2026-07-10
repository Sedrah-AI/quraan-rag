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

CREATE INDEX idx_ayahs_ref  ON ayahs(surah_id, ayah_id);
CREATE INDEX idx_words_ref  ON words(surah_id, ayah_id);
CREATE INDEX idx_audio_ref  ON ayah_audio(surah_id, ayah_id);
CREATE INDEX idx_tafsir_ref ON tafsir_passages(surah_id, ayah_id);

-- Fast substring search for the LIKE-fallback tier (today's _text_search()
-- in app/server.py, moving to a content-service endpoint) - same fallback
-- behavior the monolith already has, just made practical at scale.
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE INDEX idx_ayahs_en_trgm ON ayahs USING gin (ayah_en gin_trgm_ops);
CREATE INDEX idx_ayahs_tr_trgm ON ayahs USING gin (ayah_tr gin_trgm_ops);
