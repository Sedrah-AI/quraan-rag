import 'package:flutter/material.dart';

import 'screens/surah_list_screen.dart';

void main() {
  runApp(const QuranKidsApp());
}

class QuranKidsApp extends StatelessWidget {
  const QuranKidsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Quran for Kids',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2D6A4F)),
        useMaterial3: true,
      ),
      home: const SurahListScreen(),
    );
  }
}
