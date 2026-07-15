import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import '../models/ayah_data.dart';

/// Loads a bundled surah manifest (offline - no network needed for
/// playback/reading, only the "your turn" recording step calls the real
/// backend - see PronunciationSocket).
Future<SurahData> loadBundledSurah(String assetPath) async {
  final raw = await rootBundle.loadString(assetPath);
  final json = jsonDecode(raw) as Map<String, dynamic>;
  return SurahData.fromJson(json);
}
