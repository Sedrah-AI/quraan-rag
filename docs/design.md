# Quran RAG Design

Date: 2026-06-30
Workspace: /home/nvidia/Quraan-Rag
Local agent reviewed: quraan-agent/
Dataset target: data/quran-audio-text-dataset/

## 1. Executive summary

The target should not be described as a "100% accurate generative model." A model cannot be made 100% accurate for sacred text by fine-tuning alone. The realistic target is a Quran system with:

1. A canonical, immutable Quran data layer.
2. Deterministic verse, word, audio, and reciter retrieval.
3. A retrieval and reranking layer that is evaluated until it reaches near-perfect retrieval for known supported query classes.
4. A generation layer that is forbidden from inventing Quran text, translations, references, tajweed rules, or recitation feedback.
5. A verification layer that validates every cited ayah, word, translation, and audio asset before it reaches the user.
6. A recitation and memorization layer based on speech recognition, forced alignment, canonical text comparison, and human-reviewed tajweed scoring labels.

The model should tutor, explain, align, score, and guide. It should not be the source of Quran truth. The source of truth should be the database built from Quran-MD plus a second canonical Quran reference that we validate against during ingestion.

## 2. Local dataset status

The Hugging Face dataset repository is:

https://huggingface.co/datasets/Buraaq/quran-audio-text-dataset

The repository contains one large archive:

- quran_audio_data.tar.gz
- Size from Hugging Face API: 36,053,485,528 bytes
- Local target: data/quran-audio-text-dataset/quran_audio_data.tar.gz
- Local README saved: data/quran-audio-text-dataset/README.md

The archive download was started with:

```bash
curl -L --fail --continue-at - --retry 5 --retry-delay 10 \
  --output data/quran-audio-text-dataset/quran_audio_data.tar.gz \
  https://huggingface.co/datasets/Buraaq/quran-audio-text-dataset/resolve/main/quran_audio_data.tar.gz
```

After the archive is complete, extract it with:

```bash
tar -xzf data/quran-audio-text-dataset/quran_audio_data.tar.gz \
  -C data/quran-audio-text-dataset
```

Expected extracted layout:

```text
data/quran-audio-text-dataset/
  README.md
  quran_audio_data.tar.gz
  quran_audio_data/
    audio/
      ayahs/
        <reciter_slug>/
          001001.mp3
          ...
      words/
        001_001_001.mp3
        ...
    data/
      quran_.json
      missing_data.json
      reciters.json
      number_of_ayahs.json
      surahs.txt
      number_of_verses.txt
```

Dataset card facts to use in planning:

- 187,080 ayah-level MP3 recordings.
- 77,429 word-level MP3 recordings.
- About 264,509 total MP3 files.
- 30 reciters in the dataset card, each with 6,236 ayahs.
- 6,236 unique ayahs.
- Arabic original, English translation, and transliteration.
- Audio quality varies from 32 kbps to 192 kbps.

The local ingestion pipeline must validate these counts after extraction. If any count differs, the manifest should record the actual extracted count and dataset revision.

## 3. Product goals

The system should support four main workflows.

### 3.1 Quran reading

User asks for a surah, ayah, range, phrase, theme, translation, or explanation.

The system returns:

- Canonical Arabic ayah text.
- Reference in surah:ayah form.
- Surah name in Arabic, English, transliteration.
- Translation and transliteration, with translation edition identified.
- Optional tafsir from an approved source.
- Audio playback from selected reciter.
- Word-by-word breakdown where available.
- Clear separation between Quran text, translation, tafsir, and assistant commentary.

### 3.2 Recitation playback and guidance

User selects a verse, range, reciter, style, or memorization loop.

The system returns:

- Ground-truth audio from dataset, not generated Quran recitation.
- Segment loop controls: ayah, word, repeated passage, page, hizb, juz.
- Slower teacher recitation when available.
- Word-level audio for pronunciation drills.
- Reciter metadata and qiraah/style metadata when known.

### 3.3 Recitation checking

User records recitation for a target ayah/range.

The system returns:

- ASR transcript.
- Alignment to expected ayah/word sequence.
- Omitted, inserted, substituted, and reordered words.
- Confidence per word.
- Timing feedback.
- Tajweed feedback only where the model is trained and validated for that rule.
- A conservative "not enough confidence" response when audio quality or model certainty is insufficient.

### 3.4 Memorization

User practices memorization.

The system provides:

- Spaced repetition scheduling.
- Listen-repeat-shadow mode.
- Hide/reveal ayah mode.
- Mistake history by ayah and word.
- Weak-word drilling using word-level audio.
- Progress by surah, juz, page, and ayah.
- A memorization score based on exactness, fluency, and consistency over sessions.

## 4. Current quraan-agent code review

The local code is a useful MVP scaffold, but it is not yet a production Quran RAG system.

### 4.1 Current strengths

- quraan_agent/metadata_store.py already models surahs, ayahs, reciters, ayah_audio, and words.
- quraan_agent/vector_store.py stores ayah documents and normalized float32 embeddings in SQLite.
- quraan_agent/vector_store.py has Arabic diacritic stripping and simple Arabic normalization.
- quraan_agent/vector_store.py adds lexical boosting for references, surah names, and token overlap.
- scripts/build_vector_index.py can build local, hashing, or OpenAI embedding indexes.
- scripts/evaluate_retrieval.py and quraan_agent/test_set.py provide a starting retrieval benchmark.
- scripts/generate_training_data.py and scripts/finetune_embedder.py provide an early path for embedding fine-tuning.
- app/server.py exposes basic API endpoints for health, ayah lookup, search, RAG query, audio, and pronunciation.

### 4.2 Critical gaps

1. The default embedding provider is "local", but sentence-transformers is not installed in requirements.txt. A default app startup can fail unless optional dependencies are installed.

2. Retrieval is text-only. Audio paths exist in the metadata schema, but the retrieval context does not retrieve or rank audio assets, reciters, word audio, or memorization metadata.

3. The vector search scans all embeddings in SQLite in Python. This is acceptable for 6,236 ayahs, but it will not scale cleanly once word-level documents, tafsir passages, multiple translations, reciter profiles, and memorization notes are added.

4. The RAG prompt says not to invent citations, but there is no post-generation citation verifier. The assistant can still output a wrong citation if the LLM misbehaves.

5. The agent uses retrieved context only as text. It does not enforce that every Quran quote exactly matches the canonical database.

6. Direct reference lookup exists in app/server.py but not inside QuranAgent.retrieve. Any non-server caller misses this deterministic path.

7. quraan_agent/data_loader.py only loads JSON and is mostly unused for the SQLite metadata path.

8. scripts/generate_training_data.py creates positives but no curated hard negatives, no Arabic paraphrase queries, no tafsir queries, no qiraat-aware queries, and no typo/diacritic/no-diacritic variants at sufficient scale.

9. quraan_agent/test_set.py is a good seed but too small for production. It must include all surah names, aliases, references, Arabic phrase lookups, transliteration variants, multi-ayah answers, translation variants, and adversarial near-matches.

10. app/server.py has hardcoded legacy local paths for Minshawy audio. This should come from the extracted Quran-MD manifest.

11. The pronunciation endpoint uses whisper-1 transcription and a simple zipped word comparison. That is not recitation scoring, tajweed scoring, or reliable word alignment.

12. app/server.py swallows search exceptions in /api/search. Production should return structured diagnostic errors in logs and safe user-facing messages.

13. The generation model default is gpt-4o-mini. For religious and educational safety, the architecture should support a stronger verifier/generator or a strict extractive answer path when exactness matters.

14. The repo does not yet include ingestion scripts for the Quran-MD archive, manifest generation, audio checksum validation, or canonical Quran cross-validation.

## 5. Accuracy strategy

Accuracy must be engineered by system design.

### 5.1 Define supported answer modes

Mode A: Exact canonical retrieval

- Used for requests like "2:255", "Surah Al-Fatiha", "play Al-Ikhlas", "word 3 of 112:1".
- No LLM required.
- Must be deterministic.

Mode B: Extractive Quran answer

- Used when the answer is one or more verses.
- The model may rank and explain, but Quran text comes only from DB.
- Every returned ayah is validated against DB.

Mode C: Tafsir or explanation

- Uses retrieved Quran ayahs plus approved tafsir sources.
- Clearly labels translation, tafsir, and assistant explanation.
- If tafsir sources are missing, say so.

Mode D: Recitation feedback

- Uses audio ASR/alignment models.
- Feedback is constrained to observed transcript/alignment differences.
- Tajweed feedback is only enabled for rules with labeled validation data.

Mode E: Open educational conversation

- General study and coaching.
- Must cite when making Quran claims.
- Must refuse or caveat unsupported legal, sectarian, or disputed claims.

### 5.2 Validation gates

Every response should pass through these gates:

1. Reference validator: check surah range 1-114 and ayah range against number_of_ayahs.json.
2. Canonical text validator: all Quran Arabic shown to user must come from quran_.json or another approved canonical source.
3. Translation validator: every translation must include edition/source metadata.
4. Citation validator: every citation in generated text must match retrieved context or DB lookup.
5. Audio validator: every audio path must exist and match expected reciter/reference.
6. Abstention gate: if retrieval confidence is below threshold or citations fail validation, answer with insufficient context rather than guessing.

### 5.3 Retrieval target metrics

Before production:

- Reference lookup: 100% exact for all 6,236 ayah IDs and all valid ranges.
- Surah lookup: 100% recall for all 114 surahs and aliases.
- Arabic exact phrase retrieval: at least 99% recall@5 on generated phrase tests from canonical text.
- Translation phrase retrieval: at least 98% recall@5 per supported translation.
- Thematic retrieval: measured by curated scholar-reviewed test sets, not claimed as 100%.
- Audio path retrieval: 100% for every extracted ayah/reciter file and word file.
- Recitation ASR WER/CER: measured per reciter, per audio quality band, and per user accent group.
- Tajweed scoring: rule-level F1 must be measured against labeled human annotations.

## 6. Proposed architecture

### 6.1 Data layer

Create these local data assets:

```text
data/
  quran-audio-text-dataset/
    README.md
    quran_audio_data.tar.gz
    quran_audio_data/
      audio/
      data/
  quran_canonical/
    quran_uthmani.json
    quran_simple.json
    translations/
    tafsir/
  quran_agent.sqlite3
  quran_vectors/
  manifests/
    dataset_manifest.json
    audio_manifest.jsonl
    canonical_validation_report.json
```

SQLite tables:

- surahs
- ayahs
- ayah_words
- reciters
- ayah_audio
- word_audio
- translations
- tafsir_passages
- aliases
- retrieval_documents
- user_memorization_sessions
- user_recitation_attempts
- recitation_word_scores

Do not rely on file names alone. Build a manifest with:

- source dataset URL
- source file
- extracted path
- file size
- sha256
- surah_id
- ayah_id
- word_index
- reciter_id
- audio duration
- sample rate
- bitrate
- validation status

### 6.2 Ingestion pipeline

1. Extract archive into data/quran-audio-text-dataset/.
2. Parse quran_audio_data/data/quran_.json.
3. Normalize all IDs to integers internally and formatted strings externally.
4. Import surahs, ayahs, words, reciters, ayah audio, and word audio into SQLite.
5. Generate audio manifests with ffprobe.
6. Cross-check:
   - 114 surahs.
   - 6,236 ayahs.
   - expected ayah counts by surah.
   - all Arabic ayah texts non-empty.
   - all listed ayah audio paths exist.
   - all listed word audio paths exist.
   - missing_data.json accounted for.
7. Validate against a second canonical Quran source before marking canonical_validation_status="passed".
8. Store source revision and checksum.

### 6.3 Retrieval layer

Use hybrid retrieval:

1. Deterministic reference parser.
2. Exact Arabic phrase and normalized Arabic phrase index.
3. BM25 sparse retrieval for Arabic, English, transliteration, aliases.
4. Dense multilingual retrieval for semantic/thematic queries.
5. Reranker/cross-encoder for top 50 candidates.
6. Rule-based boosts for exact reference, surah name, alias, quoted phrase, and memorization context.

Recommended retrieval model:

- BAAI/bge-m3 as the local embedding/reranking foundation.
- Why:
  - 1024-dimensional embedding model.
  - Supports dense, sparse lexical, and ColBERT-style multi-vector retrieval.
  - Supports more than 100 languages.
  - Supports up to 8192 token sequence length.
  - Has public fine-tuning examples.
  - Better fit than MiniLM for Arabic and hybrid retrieval.

Fine-tune BGE-M3 for:

- Arabic ayah phrase to ayah.
- English translation phrase to ayah.
- Transliteration to ayah.
- Surah alias/reference to ayah/range.
- Theme query to ayah set.
- Tafsir query to tafsir passage plus ayah.

### 6.4 Generation layer

The generation layer should use tool-calling / function-calling style APIs:

Tools:

- get_ayah(reference)
- get_ayah_range(start_ref, end_ref)
- search_quran(query, filters)
- get_audio(reference, reciter)
- get_word_audio(reference, word_index)
- get_tafsir(reference, tafsir_source)
- verify_citations(answer)
- score_recitation(audio, reference)

The model is never allowed to quote Quran text from memory. It must call retrieval tools.

Answer policy:

- Quran Arabic: DB only.
- Translation: DB only, with edition.
- Tafsir: approved source only.
- Model commentary: allowed only after citations pass.
- Recitation advice: allowed only from alignment/scoring outputs.

### 6.5 Audio and recitation layer

Pipeline:

1. Convert user audio to 16 kHz mono WAV.
2. Denoise and normalize loudness.
3. Detect speech region.
4. ASR with Quran-adapted Whisper or Qwen3-Omni audio model.
5. Forced alignment to expected ayah words.
6. Compute word-level edit operations.
7. Compute timing and fluency features.
8. Optional tajweed classifier per rule once labels exist.
9. Return feedback with confidence and exact practice targets.

Important distinction:

- Playback of Quran recitation should use authentic dataset audio.
- TTS/generated audio should be used only for assistant coaching prompts, not for Quran recitation, unless a scholar-reviewed generated recitation system is separately validated.

## 7. Model recommendation

There is no single model that should own all tasks. The best design is modular.

### 7.1 Primary open multimodal model for fine-tuning

Recommended base:

- Qwen/Qwen3-Omni-30B-A3B-Thinking for audio/text input and text feedback.
- Qwen/Qwen3-Omni-30B-A3B-Instruct only if spoken assistant replies are required.

Why:

- Open Apache-2.0 license.
- Native multimodal support for text, image, audio, and video.
- Supports Arabic as a speech input language.
- Supports audio input with text output in the Thinking model.
- Supports audio and text output in the Instruct model.
- 30B MoE model with about 3B active parameters, which is realistic on this machine's 8x H100 80GB GPUs.
- Strong fit for recitation coaching because it can consume audio plus text instructions.

Use Qwen3-Omni for:

- Listening to a user's recitation attempt.
- Producing text feedback after alignment evidence is computed.
- Explaining memorization mistakes.
- Conversational tutoring.

Do not use Qwen3-Omni as:

- The canonical Quran text store.
- The only judge of tajweed correctness.
- A generated Quran recitation source.

### 7.2 ASR and alignment specialist

Recommended base:

- Whisper large-v3 as a baseline ASR model.
- Fine-tune or adapt it on Quran-MD ayah audio and Arabic transcripts.
- Use forced alignment/WhisperX-style alignment or a CTC aligner for word timings.

Why:

- Strong public baseline for multilingual speech recognition.
- Smaller and easier to fine-tune/evaluate than an omni model.
- Useful as an independent ASR signal beside Qwen3-Omni.

Use Whisper for:

- Transcript extraction.
- CER/WER measurement.
- Reference-aware decoding experiments.

Do not rely on vanilla Whisper for tajweed. It is not a tajweed model.

### 7.3 Text retrieval model

Recommended base:

- BAAI/bge-m3.

Why:

- Multilingual retrieval, including Arabic use cases.
- Dense, sparse, and multi-vector retrieval modes.
- Long context support for tafsir passages.
- Open and fine-tunable.

Use BGE-M3 for:

- Ayah retrieval.
- Tafsir retrieval.
- Multilingual query matching.
- Hybrid dense/sparse retrieval.
- Reranking with ColBERT-style signals.

### 7.4 Hosted model option

If using hosted frontier models:

- Use the strongest available OpenAI text/audio model for orchestration, conversation, and final response drafting.
- Keep Quran text/audio retrieval local and deterministic.
- Use OpenAI audio transcription only as one ASR option, not the sole recitation scoring authority.
- Keep citations verified by local code, not by the model.

The current app uses gpt-4o-mini and whisper-1. For a high-stakes Quran tutor, that should be upgraded or abstracted behind a model registry so stronger models can be selected without code rewrites.

## 8. Fine-tuning plan

Fine-tuning should be done in stages. Do not start with a giant multimodal fine-tune before the retrieval and evaluation substrate is correct.

### 8.1 Stage 0: data validation

Inputs:

- quran_audio_data/data/quran_.json
- quran_audio_data/data/reciters.json
- quran_audio_data/audio/ayahs
- quran_audio_data/audio/words
- second canonical Quran source

Outputs:

- quran_agent.sqlite3
- dataset_manifest.json
- audio_manifest.jsonl
- validation_report.json

Acceptance:

- 6,236 ayahs imported.
- 114 surahs imported.
- all ayah counts match number_of_ayahs.json.
- every DB audio path exists or is explicitly marked missing.
- every Quran Arabic text record matches canonical source or is flagged.

### 8.2 Stage 1: retrieval fine-tuning

Base:

- BAAI/bge-m3.

Training data:

- Query: exact reference, e.g. "2:255".
- Query: range reference, e.g. "Al-Baqarah 255".
- Query: Arabic ayah phrase with diacritics.
- Query: Arabic ayah phrase without diacritics.
- Query: transliteration phrase.
- Query: English translation phrase.
- Query: surah name aliases.
- Query: thematic question.
- Positive: canonical ayah document or tafsir passage.
- Hard negatives:
  - adjacent ayahs.
  - same surah different ayah.
  - similar Arabic roots.
  - same English keyword but wrong concept.
  - same reciter/audio path wrong ayah.

Loss:

- Start with MultipleNegativesRankingLoss for dense retrieval.
- Add hard-negative contrastive training.
- If using full BGE-M3 functionality, use the FlagEmbedding unified fine-tuning recipe for dense+sparse+ColBERT.

Evaluation:

- recall@1, recall@3, recall@5.
- MRR.
- nDCG.
- category breakdown: references, Arabic, English, transliteration, surah aliases, themes, tafsir.

Production gate:

- Exact references and aliases must be deterministic, not just embedding-based.
- Semantic retrieval can be high quality but not claimed 100%.

### 8.3 Stage 2: Quran ASR fine-tuning

Base:

- Whisper large-v3 or Qwen3-Omni audio branch.

Training data:

- 187,080 ayah-level recitations.
- Transcript: canonical Arabic ayah text.
- Metadata: reciter, style, surah, ayah, duration, bitrate.

Preprocessing:

- Convert MP3 to 16 kHz mono WAV for training cache.
- Keep original MP3 as source artifact.
- Normalize Arabic transcripts consistently.
- Preserve a fully diacritized target and a no-diacritic target if training both tasks.

Splits:

- Train: 24 reciters.
- Validation: 3 reciters.
- Test: 3 held-out reciters.
- Also hold out selected surahs to test generalization.

Tasks:

- Arabic ASR.
- Reference-aware recitation verification.
- Missing/extra word detection.

Metrics:

- character error rate.
- word error rate after Quran-aware normalization.
- exact ayah transcript match.
- per-reciter WER/CER.
- per-bitrate WER/CER.
- confusion matrix for common Quranic words.

### 8.4 Stage 3: forced alignment and word scoring

Inputs:

- user audio.
- expected ayah words from DB.
- ASR transcript.
- word-level dataset audio.

Train/evaluate:

- word boundary prediction.
- word correctness classifier.
- omission/insertion/substitution classifier.
- fluency/timing features.

Labels:

- Automatic labels can bootstrap from synthetic corruptions.
- Human labels are required for production quality.
- Tajweed labels require qualified annotators.

Metrics:

- word alignment F1.
- omission recall.
- substitution precision.
- timing MAE.
- confidence calibration.

### 8.5 Stage 4: Qwen3-Omni LoRA fine-tuning

Goal:

- Make the multimodal tutor better at Quran recitation feedback, memorization coaching, and safe source-grounded explanations.

Do not train it to memorize and recite Quran from weights. Train it to use retrieved/validated context.

Training examples:

1. Text-only RAG examples:
   - user question.
   - retrieved ayahs/tafsir.
   - answer with citations and strict source separation.

2. Audio + text examples:
   - user audio.
   - target reference.
   - ASR/alignment JSON.
   - feedback JSON plus natural-language coaching.

3. Memorization examples:
   - attempt history.
   - missed words.
   - next drill recommendation.

4. Refusal/abstention examples:
   - unsupported legal claims.
   - requests to fabricate citations.
   - low-confidence recitation scoring.
   - asking for Quran text without retrieval context.

Method:

- Parameter-efficient fine-tuning with LoRA or QLoRA.
- Keep a separate adapter for:
  - RAG answer formatting.
  - recitation feedback.
  - memorization coaching.
- Use full fine-tuning only if LoRA fails and evaluation justifies the cost.

Hardware:

- Current machine has 8x NVIDIA H100 80GB.
- This is enough for serious LoRA/SFT runs on Qwen3-Omni class models with distributed training.

Training config starting point:

- precision: bf16.
- optimizer: AdamW or paged AdamW for QLoRA.
- sequence packing: enabled for text examples.
- audio max duration: cap early experiments at one ayah; then expand to ranges.
- learning rate: start 1e-5 to 2e-5 for LoRA SFT.
- epochs: 1-3; stop by validation metrics, not by fixed epoch count.
- gradient checkpointing: enabled.
- evaluation every 500-1000 steps.

Evaluation:

- factual citation accuracy.
- Quran text exactness.
- abstention rate on unsupported questions.
- recitation feedback correctness against held-out labeled attempts.
- memorization recommendation quality.
- latency.

### 8.6 Stage 5: safety and scholar review

Before production:

- Have qualified reviewers approve canonical data, translation editions, tafsir sources, and tajweed labels.
- Add source metadata to every answer.
- Disable unsupported fatwa/legal advice.
- Add user-facing uncertainty where scholarship differs.
- Audit generated text for hallucinated Quran quotes.

## 9. Implementation roadmap

### Milestone 1: dataset extraction and manifest

- Complete archive download.
- Extract into data/quran-audio-text-dataset/.
- Write scripts/import_quran_md.py.
- Generate SQLite DB and manifests.
- Add checksum validation.
- Add tests for counts and path existence.

### Milestone 2: deterministic Quran API

- Move direct reference parsing into quraan_agent.
- Add ayah range lookup.
- Add surah alias lookup.
- Add audio lookup by reciter.
- Add word lookup and word audio lookup.
- Return structured response objects with source fields.

### Milestone 3: production retrieval

- Replace brute-force SQLite vector scan with one of:
  - LanceDB.
  - Qdrant.
  - Milvus.
  - FAISS plus SQLite metadata.
- Add BM25 or BGE-M3 sparse retrieval.
- Add reranking.
- Expand test_set.py to thousands of generated and curated tests.

### Milestone 4: answer verifier

- Add post-generation citation parser.
- Validate all references.
- Replace any generated Quran text with DB text.
- Fail closed if validation fails.

### Milestone 5: recitation MVP

- Replace zip-word scoring with ASR plus alignment.
- Add audio preprocessing.
- Store user attempts.
- Return word-level differences with confidence.
- Add held-out evaluation by reciter.

### Milestone 6: fine-tuning

- Fine-tune BGE-M3 retrieval adapter.
- Fine-tune Whisper/Qwen ASR on ayah audio.
- Build alignment model.
- Fine-tune Qwen3-Omni LoRA for feedback and tutoring.

### Milestone 7: memorization product

- Add user progress DB.
- Add spaced repetition.
- Add per-word mistake history.
- Add listen-repeat-shadow workflows.
- Add lesson plan generation grounded in actual mistakes.

## 10. Concrete code changes recommended next

1. Add data/quran-audio-text-dataset/ to .gitignore except README.md and manifest summaries.
2. Add scripts/import_quran_md.py.
3. Add quraan_agent/reference.py for parsing references and ranges.
4. Move deterministic lookup into QuranAgent.
5. Add quraan_agent/audio_store.py.
6. Add quraan_agent/verification.py.
7. Replace MINSHAWY_AUDIO_ROOT hardcode with DB-backed audio lookup.
8. Add requirements extras:
   - [retrieval]: FlagEmbedding, faiss-cpu/faiss-gpu, rank-bm25 or bm25s.
   - [audio]: librosa, soundfile, ffmpeg-python, faster-whisper/transformers.
   - [training]: torch, sentence-transformers, peft, accelerate, deepspeed.
9. Expand tests:
   - all valid references.
   - invalid references.
   - surah aliases.
   - audio path lookup.
   - citation verifier.
   - extraction count validation.
10. Add CI smoke tests that do not require the 36GB archive.

## 11. Source references

- Quran-MD dataset: https://huggingface.co/datasets/Buraaq/quran-audio-text-dataset
- Quran-MD paper: https://arxiv.org/abs/2601.17880
- Qwen3-Omni model card: https://huggingface.co/Qwen/Qwen3-Omni-30B-A3B-Thinking
- BGE-M3 model card: https://huggingface.co/BAAI/bge-m3
- Whisper large-v3 model card: https://huggingface.co/openai/whisper-large-v3
- OpenAI fine-tuning docs: https://platform.openai.com/docs/guides/fine-tuning
- OpenAI embeddings docs: https://platform.openai.com/docs/guides/embeddings
- OpenAI speech-to-text docs: https://platform.openai.com/docs/guides/speech-to-text

## 12. Bottom line

The right architecture is not "fine-tune a model until it knows the Quran." The right architecture is:

- canonical Quran database,
- deterministic retrieval,
- hybrid semantic retrieval,
- verified citations,
- authentic audio playback,
- ASR/alignment-based recitation scoring,
- multimodal tutoring model constrained by tools and validation.

That is how we get as close as possible to 100% correctness for the parts that can be exact, while being honest and measurable for the parts that require interpretation or speech assessment.

## 13. Current architecture (as built, 2026-07-02)

Sections 1-12 above describe the original plan. This section documents what
has actually been implemented and verified since, so it can be trusted as a
snapshot of ground truth rather than intent. Everything below was run and
checked, not just written.

### 13.0 Pipeline sketch

```
 SOURCES (HuggingFace)
 +-------------------------------+   +----------------------------------+
 | Buraaq/quran-audio-text-      |   | MohamedRashad/Quran-Tafseer      |
 | dataset (audio + text, 36GB)  |   | (218,530 rows, 84 tafsir books)  |
 +---------------+----------------+   +----------------+-------------------+
                 |                                     |
                 | import_quran_md.py                  | import_tafsir.py
                 | (parse, validate counts)            | (text-match + fuzzy fallback,
                 v                                      |  99.8% match rate)
 +--------------------------------------------------------------------------+
 |                     data/quran_metadata.sqlite3                          |
 |  surahs | ayahs | reciters | ayah_audio | words | tafsir_passages        |
 |  (114)    (6236)  (31)       (187,080)    (77,429) (20,266 matched)      |
 +--------------+--------------------------------------------+--------------+
                |                                             |
                | build_milvus_index.py                       | prepare_asr_manifest.py
                | (BGEEmbedder, GPU)                          | (split by reciter, drop >30s)
                v                                             v
 +----------------------------+                  +---------------------------------+
 |   Milvus (standalone GPU)  |                  | asr_dataset.py + finetune_       |
 |   collection: quran_ayahs  |                  | whisper.py  (8x H100, full FT of |
 |   BGE-M3 (1024d) + cuVS    |                  | tarteel-ai/whisper-base-ar-quran)|
 |   GPU_CAGRA index          |                  +----------------+------------------+
 |   infra/milvus/docker-     |                                   |
 |   compose.yml, persisted   |                                   v
 |   to data/milvus_volumes/  |                       models/quran-whisper/
 +--------------+-------------+                       (10.42% WER, held-out reciters)
                |
                |                     RUNTIME (app/server.py, FastAPI)
                |    +------------------------------------------------------------+
                |    |  /api/query, /api/search                                   |
                |    |         |                                                  |
                |    |         v                                                  |
                |    |  reference.py: parse_reference()                          |
                |    |  (exact ref / range / alias, fuzzy surah-name match)       |
                |    |         |                                                  |
                |    |   +-----+------+                                          |
                |    |   |            |                                          |
                |    |  no match    match (single/range)                         |
                +---------->|            |                                          |
             semantic  |   v            v                                          |
             search    |  agent.retrieve()   _lookup_range()                       |
                       |  (Milvus +           (sqlite, deterministic)              |
                       |   BGEEmbedder)              |                             |
                       |         |                   |                             |
                       |         +--------+----------+                             |
                       |                  v                                        |
                       |            _enrich()  <- attaches has_minshawy_audio       |
                       |                          and tafsir (from tafsir_passages) |
                       |             |         |                                    |
                       |             v         v                                   |
                       |      /api/audio/*   OpenAI gpt-4o-mini                     |
                       |      (real mp3 via   (commentary text -                    |
                       |       ayah_audio)     currently 429 quota-blocked;         |
                       |                       Qwen2.5 self-host swap planned)      |
                       |                                                            |
                       |      /api/pronunciation -> OpenAI whisper-1                |
                       |      (swap to models/quran-whisper/ planned, not wired yet)|
                       +-------------------------+----------------------------------+
                                                 |
                                                 | uvicorn --host 0.0.0.0 --port 8000
                                                 v
                                    +----------------------------------------+
                                    | app/static/ (index.html, app.js,        |
                                    | style.css) - "Ask" + "Pronunciation"    |
                                    | tabs, tafsir <details> block            |
                                    +-------------------+----------------------+
                                                        |
                              +-------------------------+-------------------------+
                              v                                                   v
                     LAN / VPN (172.16.0.2:8000)                 cloudflared quick tunnel
                                                                  (https://*.trycloudflare.com)
                                                                              |
                                                                              v
                                                                         iPad Safari
```

### 13.1 Data layer

`data/quran_metadata.sqlite3` (built by `quraan-agent/scripts/import_quran_md.py`):

- `surahs` — 114 rows.
- `ayahs` — 6,236 rows, canonical Arabic/English/transliteration text.
- `reciters` — 31 rows. One (`maher_almuaiqly`) has an empty audio folder in
  the extracted archive and contributes zero rows to `ayah_audio` — a real
  gap in the source archive, not a bug.
- `ayah_audio` — 187,080 rows (30 populated reciters x 6,236 ayahs),
  relative paths resolved against `data/quran-audio-text-dataset/`.
- `words` — 77,429 rows, all with word-level audio.
- `tafsir_passages` (new) — see 13.5.
- Manifests: `data/manifests/import_validation_report.json`,
  `data/manifests/tafsir_import_report.json`.

### 13.2 Vector retrieval: Milvus + BGE-M3 + cuVS

Standalone Milvus (`milvusdb/milvus:v2.6.19-gpu`) runs via
`infra/milvus/docker-compose.yml` (etcd + MinIO + standalone), state
bind-mounted to `data/milvus_volumes/` for on-disk persistence across
container restarts (verified with a full `docker compose down`/`up`).

- Collection `quran_ayahs`: 6,236 ayah-level documents, dense embeddings
  from `BAAI/bge-m3` (1024-dim), indexed with a cuVS-backed `GPU_CAGRA`
  index (`intermediate_graph_degree=64`, `graph_degree=32`,
  `adapt_for_cpu=true`). Query-time search uses the `ef` search param
  (the CPU-adapted HNSW-like format the index converts to at load time,
  not the GPU-side `itopk_size`/`search_width`).
- `quraan_agent/milvus_store.py` (`MilvusStore`) and the `BGEEmbedder` class
  in `quraan_agent/embeddings.py` (GPU by default, `device="cpu"` fallback
  for when the shared GPUs on this machine are contended by other jobs).
- `scripts/build_milvus_index.py` embeds and ingests ayahs.
- `quraan_agent/agent.py::QuranAgent.retrieve()` was rewired from a dead
  SQLite `VectorStore` (pointed at `data/quran_vectors.sqlite3`, which was
  never built) to this Milvus pipeline. Semantic queries that previously
  returned nothing now return well-matched results (e.g. "patience in
  hardship" surfaces 2:45, 70:5, 8:46, 16:127, 2:153).

### 13.3 Deterministic reference/range/alias parsing

`quraan_agent/reference.py` (new), used by both `/api/query` and
`/api/search` in `app/server.py`:

- `SurahDirectory` resolves surah names/numbers, with a `difflib`-based
  fuzzy fallback for transliteration variance ("sora alkahef" -> Al-Kahf).
- `parse_reference()` handles exact `S:A`, ranges (`S:A-B`, `S:A to B`,
  `surah S ayah A to B`), "first N ayahs/verses of `<surah>`", and verse
  aliases (e.g. "Ayat al-Kursi" -> 2:255) seeded from
  `quraan_agent/test_set.py`'s alias test cases, with typo-tolerant fuzzy
  matching for common misspellings.
- Ranges are clamped to the surah's real ayah count and capped at 50 ayahs.
- A lightweight `context.last_reference` field (tracked client-side in
  `app.js`) lets follow-ups like "what is the completion of this verse?"
  resolve without repeating the reference.

### 13.4 ASR fine-tuning: tarteel-ai/whisper-base-ar-quran

- `scripts/prepare_asr_manifest.py` builds train/val/test manifests from
  `ayah_audio`, split **by reciter** (24 train / 3 val / 3 test) to avoid
  leakage, dropping recordings over 30s (Whisper's fixed input window —
  truncating would mismatch audio against the full-ayah label text). Result:
  154,960 usable recordings of 187,080 (17.17% dropped for length).
- `quraan_agent/asr_dataset.py` decodes audio via `soundfile` (libsndfile
  1.2.2 decodes MP3 natively — no `ffmpeg` needed on this machine) and
  resamples via `scipy.signal.resample_poly`, with a retry-on-corrupt-file
  guard (a handful of archive mp3s are truncated/malformed).
- `scripts/finetune_whisper.py`: `Seq2SeqTrainer`, WER via `jiwer` with
  Quran-aware Arabic normalization (reusing `_arabic_fold` from
  `embeddings.py`). Works around the base model shipping no
  `generation_config.json` on the Hub by pulling one from `openai/whisper-base`.
- Full run on 8x H100 via `accelerate launch --multi_gpu --num_processes 8`:
  3 epochs, 1,482 steps, ~9m42s, final **eval WER 10.42%** on held-out val
  reciters (`hudhaify`, `ghamadi`, `fares_abbad` — never seen in training).
  Saved to `models/quran-whisper/` (gitignored — regenerable, not a
  committed artifact).

### 13.5 Tafsir: MohamedRashad/Quran-Tafseer

`scripts/import_tafsir.py` ingests
[MohamedRashad/Quran-Tafseer](https://huggingface.co/datasets/MohamedRashad/Quran-Tafseer)
(218,530 rows, 84 tafsir books, Apache 2.0, sourced from Altafsir.com) and
links it to our own `ayahs` table by normalized text matching (the dataset
has no numeric surah/ayah id, only surah name + full ayah text).

- Curated to 5 well-known books by default: Ibn Kathir, Al-Jalalayn,
  Al-Tabari, Al-Qurtubi, Al-Baghawi (`--all` ingests all 84).
- Matching combines `_arabic_fold` normalization with whitespace collapsing
  (our canonical text has standalone Quranic pause marks like `ۛ` that leave
  double-space artifacts after stripping) plus a tight `difflib` fuzzy
  fallback (cutoff 0.92) for residual orthographic variants between sources
  (e.g. classical Uthmani rasm spelling vs modern simplified spelling).
  **Final match rate: 99.8%** (20,266/20,307 rows for the 5 curated books).
- Stored in a new `tafsir_passages` table (SQLite, not Milvus — this is
  exact-key lookup by `surah_id`/`ayah_id`/`tafsir_book`, not semantic
  search; embedding tafsir content into a second Milvus collection for
  semantic tafsir search is a real but not-yet-built extension).

### 13.6 Web application

`app/server.py` (FastAPI) + `app/static/{index.html,app.js,style.css}`
(existing "Ask the Quran" and "Pronunciation Practice" tabs, extended
rather than rebuilt):

- Fixed a broken hardcoded `MINSHAWY_ROOT` (pointed at a nonexistent path
  from a different developer's Mac) to resolve real audio from the
  `ayah_audio` table.
- `_enrich()` is the single attachment point for `has_minshawy_audio` and
  `tafsir` on every ayah dict, so both flow through `/api/ayah/{s}/{a}`,
  `/api/search`, and `/api/query` automatically.
- `/api/query`/`/api/search` resolve deterministic references/ranges/aliases
  via `reference.py` first (no LLM call), falling back to Milvus semantic
  retrieval, falling back to a LIKE-search on English translation.
- Deployed with `uvicorn --host 0.0.0.0 --port 8000` (LAN-reachable) and
  additionally exposed publicly via a `cloudflared` quick tunnel for
  off-LAN (iPad) access. The quick-tunnel URL is random and unstable across
  restarts, and the server has no auth — acceptable for personal testing,
  not for anything beyond that.

### 13.7 Known issues fixed along the way

- `/home/nvidia/.bashrc` had `OPENAI_API_KEY` split across two lines inside
  an unclosed quote, giving the key a literal embedded newline. This broke
  the `Authorization` header on every OpenAI SDK call, surfacing as a
  generic `Connection error` that the UI misleadingly displayed as an
  API-key problem. Fixed in `.bashrc` (future logins) and re-exported
  directly for the currently-running server process (a `.bashrc` fix alone
  doesn't reach an already-running process, and doesn't even get sourced by
  non-interactive shells due to the standard early-return guard).

### 13.8 Known gaps (honest status, not yet done)

- **Commentary/answer generation still depends on OpenAI** (`gpt-4o-mini`),
  currently blocked by account-level `429 insufficient_quota` (a real
  billing limit, not something fixable from this environment). Discussed
  replacement: self-host `Qwen2.5-7B-Instruct` or `-14B-Instruct` via vLLM's
  OpenAI-compatible endpoint — not yet implemented.
- **Pronunciation transcription still uses OpenAI `whisper-1`** — the
  fine-tuned local `models/quran-whisper/` checkpoint (13.4) is a ready
  drop-in replacement but hasn't been wired into `/api/pronunciation` yet.
- **No training data exists yet for commentary-model fine-tuning** — only
  retrieval pairs (`data/training_pairs.jsonl`) and ASR manifests exist.
  Building (query, retrieved-context, grounded-answer) triples, ideally
  distilled from the now-available tafsir text rather than a model's
  ungrounded parametric knowledge, is unstarted.
- **Tafsir is not semantically searchable** — SQLite exact-key lookup only,
  as noted in 13.5.
- **Retrieval uses off-the-shelf BGE-M3**, not fine-tuned on Quran-specific
  data (Stage 1 in section 8.2 was never executed).
- **No automated tests** for `reference.py`, `milvus_store.py`, or the
  tafsir import/matching logic — `tests/test_agent.py` only covers the
  original agent/vector_store basics.

## 14. Guided recitation and memorization UI (design, not yet built)

Date: 2026-07-10

Goal: a full-page Mushaf view where the agent leads recitation out loud
with synchronized verse- and word-level highlighting, the user can stop
it and re-trigger any verse or single word on demand (e.g. to hear a
hard word again), and the same page can flip into a memorization test
mode that hides words/ayahs for recall practice. This sits alongside the
existing 3.2 (playback/guidance) and 3.4 (memorization) product goals —
this section makes them concrete enough to build.

**Hard constraint carried over from section 6.5**: agent-led playback
must use authentic reciter audio, never TTS/generated recitation. This
section only sequences and highlights recordings that already exist in
the dataset; it adds no new audio synthesis.

### 14.1 Two audio sources, used for two different jobs

The dataset already gives us two different granularities of authentic
audio, and they map cleanly onto two different UI actions instead of
needing one system to do both:

- **`ayah_audio`** (187,080 continuous full-verse recordings) — used for
  agent-led verse playback. Continuous speech preserves connected-speech
  tajweed rules (idgham, madd, qalqalah, etc.) that only exist *across*
  word boundaries, which isolated word clips cannot demonstrate. This is
  the audio the user hears when the agent "recites."
- **`words`** (77,429 isolated word recordings, already has
  `audio_asset_id` per `(surah_id, ayah_id, word_index)`, confirmed
  populated in `data/quran_metadata.sqlite3`) — used only for the
  on-demand "replay this one word" action when a user taps/highlights a
  word they find difficult. No new data needed for this path at all.

Word highlighting *during* verse playback is the one piece that needs
new data: knowing when each word starts/ends inside the continuous
`ayah_audio` clip.

### 14.2 Word-level timing via CTC forced alignment — DONE (2026-07-11)

The canonical Arabic text of every ayah is already known exactly (it's
in `ayahs.ayah_ar`), so this is forced alignment (align known text to
audio), not open transcription — a materially easier and more reliable
problem than ASR, and it does not require our fine-tuned
`models/quran-whisper/` (a seq2seq model; its cross-attention timestamps
are coarser and less suited to this than CTC) or the tajweed-service
wav2vec2 model (that checkpoint was contrastively trained into a
256-dim embedding head for similarity scoring — it has no CTC output
layer and cannot produce frame-level character probabilities).

Shipped approach:

1. `jonatasgrosman/wav2vec2-large-xlsr-53-arabic` (off-the-shelf, no
   fine-tuning — forced alignment only needs boundary precision, not
   recognition accuracy, since the text is already known). Its vocab is
   plain undiacritized Arabic characters, so the canonical text is
   harakat-stripped before alignment (using `embeddings.py`'s
   `ARABIC_DIACRITICS_RE` directly — see the regex-bug note below for
   why this wasn't hand-retyped).
2. `quraan_agent/ctc_align.py`: a from-scratch, vectorized (no Python-level
   loop over label positions) CTC Viterbi forced-alignment implementation,
   not `torchaudio.functional.forced_align` — the installed torch build
   (2.12.1+cu130) has no matching torchaudio wheel yet, and forced_align
   is a C++ extension needing exact ABI compatibility, an avoidable risk
   to a shared venv other services depend on for a ~30-line algorithm.
3. Character-level alignment collapsed to word-level `start_ms`/`end_ms`
   by splitting on the model's word-delimiter token (`quraan_agent/ctc_align.py::word_frame_ranges`).
4. Per-ayah confidence = exp(mean per-frame log-prob along the winning
   Viterbi path).

New table, shipped in both SQLite and Postgres (`infra/postgres/init.sql`,
`scripts/migrate_metadata_to_postgres.py`):

```sql
CREATE TABLE ayah_word_timings (
  surah_id      INTEGER NOT NULL,
  ayah_id       INTEGER NOT NULL,
  reciter_id    TEXT NOT NULL REFERENCES reciters(reciter_id),
  word_index    INTEGER NOT NULL,
  start_ms      INTEGER NOT NULL,
  end_ms        INTEGER NOT NULL,
  confidence    DOUBLE PRECISION,
  align_model   TEXT,
  PRIMARY KEY (surah_id, ayah_id, reciter_id, word_index),
  FOREIGN KEY (surah_id, ayah_id, word_index) REFERENCES words(surah_id, ayah_id, word_index)
);
```

**Result**: full corpus, one reciter (`minshawy_murattal`) — **77,429/77,429
words aligned (100%), 6,236/6,236 ayahs covered (100%), 0 monotonicity
violations, 0 word-count mismatches**. Confidence distribution: p10=0.53,
p50=0.69, p90=0.91, min=0.31 (2:282, the longest ayah in the Quran —
expected, per the risk noted in 14.7), max=0.98. Migration verified
(row counts + byte-level spot-check, same standard as the rest of this
project's Postgres sync).

Scope stayed v1 as planned: only the default reciter is aligned; other
reciters can be added later via the same script with no schema change,
each reciter's rows keyed independently by `reciter_id`.

**Real bugs hit and fixed during this run** (kept here rather than
silently fixed, matching this project's own convention in the wiki's
"Real bugs found during the build-out" section):

1. **Thread oversubscription (performance, not correctness)**: an early
   full-run attempt spent ~15 wall-clock minutes accumulating ~14.7
   CPU-*hours* across 235 threads without finishing a single ayah.
   `torch.set_num_threads(1)` only limits torch's own intra-op dispatch,
   not the OpenMP/MKL/OpenBLAS thread pools those libraries spin up
   independently at import time (measured 66 threads/worker even with
   that call in place). Fixed by setting `OMP_NUM_THREADS`,
   `MKL_NUM_THREADS`, `OPENBLAS_NUM_THREADS`, `NUMEXPR_NUM_THREADS`,
   `VECLIB_MAXIMUM_THREADS` to `1` before numpy/torch/scipy import.
2. **Scrambled diacritics regex (correctness, silent)**: while
   parallelizing across ayahs (this box's 208 CPU cores, all 8 GPUs
   already saturated by other jobs), the diacritic-stripping regex was
   hand-retyped with literal Arabic characters and its range order got
   scrambled by bidi rendering — it silently matched *base letters too*,
   not just diacritics (`بِسْمِ` → `''`, wiping whole words). This is the
   exact same failure mode already hit once before porting the same
   regex into pronunciation-service (see
   [Microservice-Architecture](../wiki/Microservice-Architecture.md)).
   It surfaced as 100% alignment failures rather than corrupted-but-
   plausible-looking output only because an empty target sequence makes
   `word_frame_ranges` return zero words, which trips the word-count
   check — a differently-shaped bug could have shipped silently-wrong
   timings instead. Fixed by importing `embeddings.py`'s
   `ARABIC_DIACRITICS_RE` directly instead of retyping the character
   class.
3. **Embedded space inside one `words`-table row**: 37:130's word_index 3
   ("Ilyasin") is stored as two space-separated tokens in one row. Spaces
   were originally treated as word-delimiters even *within* a single
   row's text, splitting it into two `word_frame_ranges` entries (the
   sole failure in the first full run, 6,235/6,236). Fixed by only
   delimiting *between* `words`-table rows, not on any embedded space
   inside one row's text; backfilled the single affected ayah rather
   than re-running the full corpus.

### 14.3 Mushaf page layout — DONE (2026-07-10)

Sourced and ingested: **Tanzil's `quran-data.xml`**
(https://tanzil.net/docs/quran_metadata, CC-BY, downloaded to
`/data/quraan-rag/data/mushaf_layout_raw/`, see its `SOURCE_README.md`).
This is the same upstream source quran.ksu.edu.sa itself credits and
builds on — going directly to Tanzil avoided scraping a JS SPA with no
documented API for the same underlying data.

The file stores **boundary markers**, not a per-ayah/per-line table:
`<page index="N" sura="S" aya="A" />` means page N begins at ayah S:A
(same shape for `juz`/`manzil`/`ruku`). `scripts/import_mushaf_layout.py`
converts each `(sura, aya)` to a single global ayah ordinal (via each
`<sura>`'s `start` offset) and, for every ayah in our own `ayahs` table,
finds the latest boundary at or before it.

Actual schema shipped (simpler than the line-based draft originally
sketched here, since the source has no line-level data at all — see
the known limitation below):

```sql
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
```

Validated: all 6,236 ayahs mapped, exactly 604 distinct pages (page 1 =
1:1, page 604 = 112:1–114:6), zero surah ayah-count mismatches against
the XML's own `<sura ayas="...">` counts. Spot-checked against known
reference points, not just internal consistency: 2:255 (Ayat al-Kursi)
→ page 42; the juz-2 boundary (2:142) → page 22 — both match the real
Madani Mushaf. Report: `quraan-agent/data/manifests/mushaf_layout_import_report.json`.
Migrated to Postgres (`infra/postgres/init.sql`,
`scripts/migrate_metadata_to_postgres.py`) — row counts and byte-level
content spot-checks both verified.

**Known limitation carried forward, not resolved**: no line-level data
exists in this source, so an ayah that visually spans a page break
mid-ayah on a physical Mushaf is *not* split here — each ayah is
assigned wholly to the page it starts on. Acceptable for word-highlight
playback (this section's actual goal) but not pixel/line-accurate to a
printed Mushaf. A page/line typesetting dataset would be a separate,
later sourcing task if that precision is ever needed.

### 14.4 API surface (content-service + gateway)

New content-service endpoints:

- `GET /pages/{page_number}` → ordered list of `{surah_id, ayah_id,
  line_number, words: [...]}` for that Mushaf page, reusing the existing
  per-ayah enrichment (tafsir, audio availability).
- `GET /words/{surah_id}/{ayah_id}/{word_index}/audio` → serves the
  existing isolated word MP3 (same `FileResponse` pattern as the current
  `/audio/{reciter_id}/{surah_id}/{ayah_id}`).
- `GET /ayahs/{surah_id}/{ayah_id}/timings?reciter=...` → word
  `start_ms`/`end_ms` array plus `confidence`; `null`/omitted when no
  alignment row exists yet for that reciter, so the frontend can apply
  the even-interpolation fallback from 14.2.

gateway-service adds thin proxying routes for all three, matching the
existing pattern in `clients.py`.

### 14.5 Frontend: Recite view

New tab (alongside "Ask the Quran" and "Pronunciation Practice") that
renders one Mushaf page as a sequence of `<span>`-per-word ayahs (word
spans keyed by `word_index`, exactly like the comparison grid the
pronunciation tab already renders word arrays into).

Playback engine (new `recitation.js`, client-side only — no new backend
statefulness, unlike the live-pronunciation WebSocket which is stateful
by necessity because it's consuming a live mic stream):

- **Start recitation**: plays each ayah's `ayah_audio` clip in page
  order via a plain `<audio>` element. On each `timeupdate`, walks the
  fetched timings array for the current ayah and toggles a `.highlight`
  class on the word span whose `[start_ms, end_ms)` contains
  `audio.currentTime`.
- **Stop**: `audio.pause()` — no server round-trip needed, this is a
  purely client-side action.
- **Re-recite this verse**: reset that ayah's `<audio>` to `currentTime
  = 0` and play — since each ayah is already its own clip, "replay the
  verse" needs no slicing logic.
- **Replay this word**: fetch/play the isolated word clip from 14.4
  instead of seeking within the verse clip — reuses the dataset's
  existing word-level recordings directly, and is a separate short clip
  rather than a seek, so it doesn't disturb verse playback position.
- **Memorization test mode**: pure client-state toggle, no backend
  change. Selected words/ayahs render as a masked box (fixed-width RTL
  placeholder) instead of the Arabic text, keyed by the same
  `word_index`; tapping reveals it. Because there's no user-account
  system yet (`docs/design.md` section 13.6/wiki already flag "no
  auth"), persisting which words a given user struggles with is
  out of scope for v1 — session-local `localStorage` only, matching the
  no-auth reality rather than building storage for users that don't
  exist yet. Cross-session mistake history (goal 3.4) becomes possible
  once accounts exist, not before.

### 14.6 Milestones

1. **DONE (2026-07-10)** — see 14.3. Sourced + license-checked Tanzil's
   `quran-data.xml`; `scripts/import_mushaf_layout.py`; `mushaf_pages`
   table added to SQLite and Postgres; 604-page/6,236-ayah coverage
   validated; migration re-run and verified (counts + byte-level spot
   check).
2. **DONE (2026-07-11)** — see 14.2. `scripts/align_ayah_words.py` (CTC
   forced alignment, parallelized across this box's 208 CPU cores);
   `ayah_word_timings` table in SQLite and Postgres; full-corpus run for
   the default reciter, 100% coverage (77,429/77,429 words, 6,236/6,236
   ayahs), 0 monotonicity violations; migration verified.
3. content-service: add the three endpoints in 14.4.
4. gateway-service: proxy routes + static asset wiring.
5. Frontend: Recite tab — page render, sequential playback with
   highlighting, stop, per-verse replay, per-word on-demand playback,
   hide-word memorization mode.
6. Evaluation: hand-check alignment boundaries against a small
   human-labeled sample (e.g. 20-30 ayahs spanning short/long/heavy-tajweed
   cases) before trusting confidence scores as a gating signal.

### 14.7 Known gaps/risks

- **Alignment quality is measured only by internal consistency so far
  (coverage, monotonicity, confidence), not against human-labeled ground
  truth** — milestone 6's hand-check (20-30 ayahs spanning short/long/
  heavy-tajweed cases) hasn't run yet. Confidence scores are a relative
  signal from the model's own emission probabilities, not a calibrated
  accuracy estimate; treat p10-range ayahs (~0.53 and below) as
  "probably fine but unverified," not "confirmed correct."
- 2:282 (the longest ayah in the Quran) has the lowest confidence in the
  full run (~0.31) — consistent with the general expectation that very
  long, melismatic recitations are the hardest case, but not yet
  confirmed by manual review whether that specific ayah's boundaries
  are actually degraded or just naturally scored lower.
- v1 covers one reciter's timings (`minshawy_murattal`); switching
  reciters in the Recite tab either falls back to interpolated
  highlighting or is disabled until that reciter is aligned too.
- No cross-session memorization progress until user accounts exist.
