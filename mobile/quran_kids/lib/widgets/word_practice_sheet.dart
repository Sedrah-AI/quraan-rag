import 'dart:async';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../models/ayah_data.dart';
import '../services/pronunciation_socket.dart';
import '../services/word_audio.dart';

/// Opened when a word is tapped in the WordTracker - lets the child hear
/// just that one word's reference pronunciation, or record just that one
/// word and get the same tolerant matched/done feedback as a whole-ayah
/// attempt, scoped down to a single word via /ws/pronunciation's new
/// optional word_index param (see pronunciation-service/app/main.py).
class WordPracticeSheet extends StatefulWidget {
  final AyahData ayah;
  final int wordPosition; // 0-based

  const WordPracticeSheet({super.key, required this.ayah, required this.wordPosition});

  @override
  State<WordPracticeSheet> createState() => _WordPracticeSheetState();
}

enum _SheetPhase { idle, playingWord, recording, done }

class _WordPracticeSheetState extends State<WordPracticeSheet> {
  _SheetPhase _phase = _SheetPhase.idle;
  final _player = AudioPlayer();
  PronunciationSocket? _socket;
  StreamSubscription<PronunciationUpdate>? _updateSub;

  String get _word => widget.ayah.words[widget.wordPosition];

  @override
  void dispose() {
    _updateSub?.cancel();
    _socket?.dispose();
    _player.dispose();
    super.dispose();
  }

  Future<void> _hearIt() async {
    setState(() => _phase = _SheetPhase.playingWord);
    try {
      await _player.setUrl(wordAudioUrl(widget.ayah.surahId, widget.ayah.ayahId, widget.wordPosition + 1));
      await _player.play();
      await _player.playerStateStream.firstWhere((s) => s.processingState == ProcessingState.completed);
    } catch (_) {
      // Word audio not reachable (offline, or no clip for this word) -
      // fail quietly, "Try it" doesn't depend on this working.
    }
    if (mounted) setState(() => _phase = _SheetPhase.idle);
  }

  Future<void> _tryIt() async {
    final socket = PronunciationSocket(widget.ayah.reference, wordIndex: widget.wordPosition + 1);
    if (!await socket.hasMicPermission()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Microphone permission is needed to practice.')),
        );
      }
      return;
    }
    setState(() => _phase = _SheetPhase.recording);
    _socket = socket;
    _updateSub = socket.updates.listen((update) {
      if (!mounted || !update.done) return;
      setState(() => _phase = _SheetPhase.done);
      socket.stop();
    });
    await socket.start();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Directionality(
              textDirection: TextDirection.rtl,
              child: Text(_word, style: const TextStyle(fontSize: 32, fontFamily: 'Amiri')),
            ),
            const SizedBox(height: 20),
            if (_phase == _SheetPhase.recording) const Text('Listening...'),
            if (_phase == _SheetPhase.done)
              const Text('🌟 Nicely said! 🌟', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              alignment: WrapAlignment.center,
              children: [
                ElevatedButton.icon(
                  onPressed: _phase == _SheetPhase.idle || _phase == _SheetPhase.done ? _hearIt : null,
                  icon: const Icon(Icons.volume_up),
                  label: const Text('Hear it'),
                ),
                ElevatedButton.icon(
                  onPressed: _phase == _SheetPhase.idle || _phase == _SheetPhase.done ? _tryIt : null,
                  icon: const Icon(Icons.mic),
                  label: const Text('Try it'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
