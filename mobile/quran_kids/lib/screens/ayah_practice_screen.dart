import 'package:flutter/material.dart';

import '../models/ayah_data.dart';
import '../widgets/ayah_practice_card.dart';

/// Focused mode: one ayah's practice card fills the screen at a time,
/// swiped/advanced through with a PageView, instead of the whole surah in
/// a long scrollable list - less visual noise for a kid to parse. The
/// "Auto"/"Hide" toggles that used to repeat on every card now live once,
/// behind the parent-lock icon in the AppBar (see _openSettings).
class AyahPracticeScreen extends StatefulWidget {
  final List<AyahData> ayahs;

  const AyahPracticeScreen({super.key, required this.ayahs});

  @override
  State<AyahPracticeScreen> createState() => _AyahPracticeScreenState();
}

class _AyahPracticeScreenState extends State<AyahPracticeScreen> {
  final _pageController = PageController();
  int _currentIndex = 0;
  bool _autoAdvance = true;
  bool _hideText = false;
  final Set<String> _completedRefs = {};

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _goToPage(int index) {
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeInOut,
    );
  }

  void _onNextAyah(int fromIndex) {
    if (fromIndex < widget.ayahs.length - 1) {
      _goToPage(fromIndex + 1);
    } else {
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('🎉 Surah complete!'),
          content: const Text('Great work - you finished every ayah in this surah.'),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Practice again')),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                Navigator.of(context).pop();
              },
              child: const Text('Back to surahs'),
            ),
          ],
        ),
      );
    }
  }

  void _openSettings() {
    showModalBottomSheet(
      context: context,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text('Parent settings', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ),
                SwitchListTile(
                  title: const Text('Auto-advance'),
                  subtitle: const Text('Move to the next step and ayah automatically'),
                  value: _autoAdvance,
                  onChanged: (v) {
                    setState(() => _autoAdvance = v);
                    setSheetState(() {});
                  },
                ),
                SwitchListTile(
                  title: const Text('Hide Arabic text'),
                  subtitle: const Text('Recite from memory - word highlight still shows'),
                  value: _hideText,
                  onChanged: (v) {
                    setState(() => _hideText = v);
                    setSheetState(() {});
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ayahs = widget.ayahs;
    return Scaffold(
      appBar: AppBar(
        title: Text('Surah ${ayahs.isNotEmpty ? ayahs.first.surahId : ''}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.lock_outline),
            tooltip: 'Parent settings',
            onPressed: _openSettings,
          ),
        ],
      ),
      body: Column(
        children: [
          const SizedBox(height: 12),
          _ProgressDots(
            count: ayahs.length,
            currentIndex: _currentIndex,
            completed: (i) => _completedRefs.contains(ayahs[i].reference),
          ),
          const SizedBox(height: 4),
          Text(
            'Ayah ${_currentIndex + 1} of ${ayahs.length}',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
          Expanded(
            child: PageView.builder(
              controller: _pageController,
              itemCount: ayahs.length,
              onPageChanged: (i) => setState(() => _currentIndex = i),
              itemBuilder: (context, index) => Center(
                child: SingleChildScrollView(
                  child: AyahPracticeCard(
                    key: ValueKey(ayahs[index].reference),
                    ayah: ayahs[index],
                    autoAdvance: _autoAdvance,
                    hideText: _hideText,
                    isLastAyah: index == ayahs.length - 1,
                    onCompleted: () => setState(() => _completedRefs.add(ayahs[index].reference)),
                    onNextAyah: () => _onNextAyah(index),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProgressDots extends StatelessWidget {
  final int count;
  final int currentIndex;
  final bool Function(int index) completed;

  const _ProgressDots({required this.count, required this.currentIndex, required this.completed});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < count; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: const EdgeInsets.symmetric(horizontal: 3),
            width: i == currentIndex ? 12 : 8,
            height: i == currentIndex ? 12 : 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: i == currentIndex
                  ? const Color(0xFF2D6A4F)
                  : completed(i)
                      ? const Color(0xFF2D6A4F).withValues(alpha: 0.5)
                      : Colors.grey.shade300,
            ),
          ),
      ],
    );
  }
}
