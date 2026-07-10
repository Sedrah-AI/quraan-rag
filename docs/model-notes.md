Model recommendation (modular, no single model owns everything)
Task	Model	Why
Recitation correction / multimodal tutoring	Qwen/Qwen3-Omni-30B-A3B-Thinking	Apache-2.0, native audio+text multimodal, supports Arabic speech input, 30B MoE (~3B active) fits comfortably on your 8x H100 80GB rig
ASR / forced alignment specialist	Whisper large-v3, fine-tuned on Quran-MD ayah audio	Strong public baseline, smaller/easier to fine-tune than the omni model, used as an independent signal alongside Qwen3-Omni
Text retrieval / embeddings	BAAI/bge-m3	1024-dim, supports dense + sparse + ColBERT-style multi-vector retrieval, 100+ languages, 8192-token context, better Arabic fit than MiniLM
Key principle agreed: Qwen3-Omni should never be the canonical Quran text source or sole tajweed judge — it consumes ASR/alignment evidence and produces coaching feedback, but the Quran text itself always comes from the validated DB.

Pre-fine-tuned Quran recitation models (no need to fine-tune Whisper from scratch — start by benchmarking these)
Model	What it does	Notes
tarteel-ai/whisper-base-ar-quran	Whisper-base fine-tuned by Tarteel AI on Quran recitation	5.75% WER, official Tarteel org, small/fast, good baseline
IJyad/whisper-large-v3-Tarteel	Whisper-large-v3 fine-tuned on Tarteel's Everyayah dataset	Higher capacity than base, still Quran-specific
MaddoggProduction/whisper-l-v3-turbo-quran-lora-dataset-mix	Whisper-large-v3-turbo + LoRA fine-tuned on Quranic Arabic (with tashkeel)	12.69% WER, fast inference, trained with audio augmentation for robustness
obadx/recitation-segmenter-v2	Fine-tuned wav2vec2-BERT for waqf (pause-point) segmentation	Useful for splitting recitation audio into ayah/word boundaries before scoring
HamzaSidhu786/wav2vec2-base-word-by-word-quran-asr	wav2vec2 fine-tuned for word-level Quran ASR	Good fit for word-level alignment/scoring rather than full-ayah transcription

Tajweed-specific scoring/mispronunciation-detection models are still an active research area (see the IqraEval shared task, e.g. "ANPLers" adapting Whisper-large-v3 as speech-to-phoneme for mispronunciation detection) rather than a single production-ready off-the-shelf model — plan to benchmark a couple of these before committing.