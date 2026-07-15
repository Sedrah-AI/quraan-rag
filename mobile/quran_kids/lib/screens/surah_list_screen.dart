import 'package:flutter/material.dart';

import '../models/ayah_data.dart';
import '../services/manifest_loader.dart';
import 'ayah_practice_screen.dart';

/// Just Al-Fatiha for this phase - surahs 87-114 are already aligned
/// (see scripts/align_teacher_ayah_words.py in the main repo) and can be
/// added here later purely by bundling more assets, no code changes.
class SurahListScreen extends StatefulWidget {
  const SurahListScreen({super.key});

  @override
  State<SurahListScreen> createState() => _SurahListScreenState();
}

class _SurahListScreenState extends State<SurahListScreen> {
  SurahData? _surah;

  @override
  void initState() {
    super.initState();
    loadBundledSurah('assets/data/al_fatiha.json').then((s) {
      if (mounted) setState(() => _surah = s);
    });
  }

  @override
  Widget build(BuildContext context) {
    final surah = _surah;
    return Scaffold(
      appBar: AppBar(title: const Text('Quran for Kids')),
      body: surah == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                ListTile(
                  title: Text('${surah.surahId}. ${surah.surahNameEn}'),
                  subtitle: Text(surah.surahNameAr, textDirection: TextDirection.rtl),
                  trailing: Text('${surah.ayahs.length} verses'),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => AyahPracticeScreen(ayahs: surah.ayahs),
                      ),
                    );
                  },
                ),
              ],
            ),
    );
  }
}
