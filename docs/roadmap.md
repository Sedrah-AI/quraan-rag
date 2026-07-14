# Feature roadmap

Backlog of requested features, roughly in the order they were raised. Not yet
scheduled or estimated — this is a holding pen for scope, not a sprint plan.

## 1. Memorization mode for Recite tab — ✅ done

Shipped: a "Recite from memory" toggle hides word text via CSS
(`.recite-page.hide-words .recite-word`) while keeping layout/click-targets/
highlight box intact, plus a further "Test my memory" mode that streams the
mic to pronunciation-service's existing `/ws/pronunciation` endpoint and
beeps + reveals a word if live transcription progress stalls for 4s. See
the wiki's [Recitation Helper](../../wiki/Recitation-Helper.md) page,
section 6, for the full writeup including a real bug hit (0-based vs
1-based word indexing) and what verification could and couldn't cover.

## 2. Word-occurrence count queries — ✅ done

Shipped: a new `retrieval-service/app/word_counts.py` builds an in-memory
normalized word-frequency index once at startup from content-service's
`words` table (~15k distinct words, diacritics stripped) - zero DB/LLM cost
per query afterward (~16ms end-to-end measured). Wired into `/api/query` as
the first check, ahead of reference/semantic search. Seeded with ~30
prophet/figure name aliases (Musa/Moses -> موسى, etc.) plus a few thematic
nouns. See the wiki's [Sample Queries](../../wiki/Sample-Queries.md) page
for example inputs and the exact-word-match methodology caveat.

## 3. Thematic / descriptive questions

"How does the Quran describe Hell / Paradise / death?" - a synthesis over a
theme, not a single best-matching ayah.

- Current `/api/query` semantic search returns top_k=5 closest ayahs by
  embedding similarity and asks the LLM to answer from just those - fine for
  a specific question, too narrow for a broad descriptive/thematic one.
- Needs either a much larger top_k for this query shape, a themed/topic
  index (pre-tagged verse clusters: Hell, Paradise, death, etc.), or a
  multi-pass retrieval (retrieve broadly, then let the LLM select/summarize
  across a larger candidate set) before generation-service's `/answer`.

## 4. Answer in the question's language + "list all matching verses" queries

Two related gaps in `/api/query`:

- **Language matching**: `generation-service`'s `/answer` endpoint
  (`main.py:78`) has no `lang` parameter at all (unlike `/meaning`, which
  does) - so answers don't currently adapt to the language the question was
  asked in. Needs detecting the query's language (frontend already has a
  `detectLang()` for Arabic vs. English, `app.js:208`) and threading it
  through gateway -> generation-service -> the system prompt.
- **Exhaustive list queries**: "what verse talks about bees?" or "which
  ayat mention fasting?" expects *every* matching verse, not one ranked
  answer - today's fixed `top_k=5` semantic search returns a small ranked
  sample, not an exhaustive match. Needs either a much higher top_k with a
  similarity-threshold cutoff (return everything above a relevance bar,
  not just the top N) or a keyword/topic index for exact-term queries
  ("bees" -> An-Nahl) layered on top of the semantic search.
- Also implies voice input ("ask questions verbally") - no speech-to-text
  exists on the query path today (ASR only exists on the pronunciation
  practice path, via `pronunciation-service`/Whisper) - would need a mic
  input + a similar transcription step wired into the Ask tab.

## 5. User accounts, resume, and progress dashboard — ✅ done

Raised as a follow-up to item 1, not originally on this list: real login
(not anonymous/local-only tracking), so recitation/pronunciation progress
follows a user across devices and resumes exactly where they left off.
Shipped as a new `account-service` (JWT + bcrypt, port 8106), an
append-only `recitation_events`/`pronunciation_attempts` event log, a
resume-to-exact-Mushaf-page lookup, and a dashboard tab. See the wiki's
[Accounts and Progress](../../wiki/Accounts-and-Progress.md) page for the
full design (including why JWT-in-a-header over cookies) and what's still
open (no password reset, no rate limiting yet).
