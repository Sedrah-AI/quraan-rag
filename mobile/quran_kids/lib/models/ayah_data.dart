/// One word's timing within a segment (teacher's recitation or the
/// child's repetition) - mirrors the shape returned by the backend's
/// `/api/ayahs/{s}/{a}/teacher-timings` endpoint.
class WordTiming {
  final int wordIndex;
  final int startMs;
  final int endMs;

  const WordTiming({required this.wordIndex, required this.startMs, required this.endMs});

  factory WordTiming.fromJson(Map<String, dynamic> json) => WordTiming(
        wordIndex: json['word_index'] as int,
        startMs: json['start_ms'] as int,
        endMs: json['end_ms'] as int,
      );

  /// 0-based position in playback order (matches how the aligner produced
  /// these - word_index is 1-based, position is word_index - 1).
  int get position => wordIndex - 1;
}

/// One ayah bundled for offline practice: its text, word list, the
/// Muallim clip's audio asset path, and both halves' word timings (from
/// the doubled-transcript alignment - see
/// scripts/align_teacher_ayah_words.py in the main repo).
class AyahData {
  final int surahId;
  final int ayahId;
  final String ayahAr;
  final String? ayahEn;
  final List<String> words;
  final String audioAsset;
  final List<WordTiming> teacherTimings;
  final List<WordTiming> studentTimings;

  const AyahData({
    required this.surahId,
    required this.ayahId,
    required this.ayahAr,
    required this.ayahEn,
    required this.words,
    required this.audioAsset,
    required this.teacherTimings,
    required this.studentTimings,
  });

  String get reference => '$surahId:$ayahId';

  factory AyahData.fromJson(Map<String, dynamic> json) => AyahData(
        surahId: json['surah_id'] as int,
        ayahId: json['ayah_id'] as int,
        ayahAr: json['ayah_ar'] as String,
        ayahEn: json['ayah_en'] as String?,
        words: (json['words'] as List).cast<String>(),
        audioAsset: json['audio_asset'] as String,
        teacherTimings: (json['teacher_timings'] as List)
            .map((w) => WordTiming.fromJson(w as Map<String, dynamic>))
            .toList(),
        studentTimings: (json['student_timings'] as List)
            .map((w) => WordTiming.fromJson(w as Map<String, dynamic>))
            .toList(),
      );
}

/// A bundled surah's worth of ayahs (just Al-Fatiha for this phase - see
/// assets/data/al_fatiha.json).
class SurahData {
  final int surahId;
  final String surahNameEn;
  final String surahNameAr;
  final List<AyahData> ayahs;

  const SurahData({
    required this.surahId,
    required this.surahNameEn,
    required this.surahNameAr,
    required this.ayahs,
  });

  factory SurahData.fromJson(Map<String, dynamic> json) => SurahData(
        surahId: json['surah_id'] as int,
        surahNameEn: json['surah_name_en'] as String,
        surahNameAr: json['surah_name_ar'] as String,
        ayahs: (json['ayahs'] as List).map((a) => AyahData.fromJson(a as Map<String, dynamic>)).toList(),
      );
}
