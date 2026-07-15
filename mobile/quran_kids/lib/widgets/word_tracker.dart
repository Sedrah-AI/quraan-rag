import 'package:flutter/material.dart';

/// Renders an ayah's words with the currently-playing/matched word
/// highlighted, and an optional hide-text mode (the web app's
/// "Recite from memory" toggle, same idea: word positions/layout stay,
/// only the glyphs disappear, so a highlighted position is still visible
/// without giving the word away).
///
/// When [onWordTap] is given, each word becomes tappable (0-based
/// position) - used for "tap a word to hear it or practice just that
/// word." Left null (e.g. during teacher/peer playback, when a tap
/// shouldn't fight with the highlight-follow behavior) to render
/// non-interactive, same as before this was added.
class WordTracker extends StatelessWidget {
  final List<String> words;
  final int activeIndex; // 0-based position, -1 for none
  final bool hideText;
  final void Function(int position)? onWordTap;

  const WordTracker({
    super.key,
    required this.words,
    required this.activeIndex,
    this.hideText = false,
    this.onWordTap,
  });

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 10,
        runSpacing: 8,
        children: [
          for (var i = 0; i < words.length; i++)
            GestureDetector(
              onTap: onWordTap == null ? null : () => onWordTap!(i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: i == activeIndex ? const Color(0xFFF7E8A0) : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  words[i],
                  style: TextStyle(
                    fontSize: 26,
                    fontFamily: 'Amiri',
                    color: hideText ? Colors.transparent : const Color(0xFF1A3A28),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
