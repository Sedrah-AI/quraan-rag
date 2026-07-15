import 'dart:async';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../models/ayah_data.dart';
import '../services/pronunciation_socket.dart';
import 'three_step_indicator.dart';
import 'word_practice_sheet.dart';
import 'word_tracker.dart';

enum _Phase { idle, playingTeacher, playingStudent, recording, feedback }

/// One ayah's full practice loop (listen to teacher, listen to peer, your
/// turn, tap a word) - focused-mode: only one of these is ever on screen
/// at a time (see AyahPracticeScreen's PageView), so there's a single
/// dynamic call-to-action instead of three always-visible buttons, and the
/// [ThreeStepIndicator] up top both shows where the child is in the loop
/// and lets them replay an earlier step.
class AyahPracticeCard extends StatefulWidget {
  final AyahData ayah;
  final bool autoAdvance;
  final bool hideText;
  final bool isLastAyah;

  /// Called once the first time this ayah's recitation is judged
  /// complete (used by the parent screen to light up its progress dots).
  final VoidCallback? onCompleted;

  /// Called when the child (or the auto-advance timer) is ready to move
  /// on to the next ayah.
  final VoidCallback? onNextAyah;

  const AyahPracticeCard({
    super.key,
    required this.ayah,
    this.autoAdvance = true,
    this.hideText = false,
    this.isLastAyah = false,
    this.onCompleted,
    this.onNextAyah,
  });

  @override
  State<AyahPracticeCard> createState() => _AyahPracticeCardState();
}

class _AyahPracticeCardState extends State<AyahPracticeCard> {
  _Phase _phase = _Phase.idle;
  bool _teacherDone = false;
  bool _friendDone = false;
  int _activeWordPosition = -1;
  int _matchedCount = 0;
  int? _countdown; // seconds remaining until the next auto-step, null = none pending

  final _player = AudioPlayer();
  PronunciationSocket? _socket;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<PronunciationUpdate>? _updateSub;
  Timer? _countdownTimer;

  static const _autoAdvanceSeconds = 6;
  static const _nextAyahSeconds = 5;

  AyahData get _ayah => widget.ayah;

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _positionSub?.cancel();
    _updateSub?.cancel();
    _socket?.dispose();
    _player.dispose();
    super.dispose();
  }

  void _cancelCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = null;
    if (_countdown != null && mounted) setState(() => _countdown = null);
  }

  /// Starts a cancelable, visible countdown before an auto-advance step -
  /// any manual tap in the meantime (a step avatar, the CTA, "Next Ayah")
  /// cancels it first, so a deliberate action always wins over a pending
  /// automatic one.
  void _startCountdown(int seconds, VoidCallback onDone) {
    _cancelCountdown();
    setState(() => _countdown = seconds);
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      final remaining = (_countdown ?? 1) - 1;
      if (remaining <= 0) {
        timer.cancel();
        _countdownTimer = null;
        if (mounted) setState(() => _countdown = null);
        onDone();
      } else if (mounted) {
        setState(() => _countdown = remaining);
      }
    });
  }

  Future<void> _playSegment(_Phase phase, String assetPath, List<WordTiming> timings) async {
    if (timings.isEmpty) return;
    setState(() {
      _phase = phase;
      _activeWordPosition = -1;
    });
    final endMs = timings.last.endMs;
    final done = Completer<void>();

    await _positionSub?.cancel();
    await _player.setAsset(assetPath);
    await _player.seek(Duration(milliseconds: timings.first.startMs));

    _positionSub = _player.positionStream.listen((pos) {
      final ms = pos.inMilliseconds;
      if (ms >= endMs) {
        if (!done.isCompleted) done.complete();
        return;
      }
      var current = -1;
      for (final t in timings) {
        if (ms >= t.startMs && ms < t.endMs) {
          current = t.position;
          break;
        }
      }
      if (current != _activeWordPosition && mounted) {
        setState(() => _activeWordPosition = current);
      }
    });
    await _player.play();
    await done.future;
    await _player.pause();
  }

  Future<void> _listenToTeacher() async {
    _cancelCountdown();
    await _playSegment(_Phase.playingTeacher, _ayah.audioAsset, _ayah.teacherTimings);
    if (!mounted) return;
    setState(() {
      _phase = _Phase.idle;
      _teacherDone = true;
    });
    if (widget.autoAdvance && !_friendDone) _startCountdown(_autoAdvanceSeconds, _listenToPeer);
  }

  Future<void> _listenToPeer() async {
    _cancelCountdown();
    await _playSegment(_Phase.playingStudent, _ayah.audioAsset, _ayah.studentTimings);
    if (!mounted) return;
    setState(() {
      _phase = _Phase.idle;
      _friendDone = true;
    });
    if (widget.autoAdvance) _startCountdown(_autoAdvanceSeconds, _startYourTurn);
  }

  Future<void> _startYourTurn() async {
    _cancelCountdown();
    final socket = PronunciationSocket(_ayah.reference);
    if (!await socket.hasMicPermission()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Microphone permission is needed to practice.')),
        );
      }
      return;
    }
    setState(() {
      _phase = _Phase.recording;
      _matchedCount = 0;
      _activeWordPosition = -1;
    });
    _socket = socket;
    _updateSub = socket.updates.listen((update) {
      if (!mounted) return;
      setState(() {
        _matchedCount = update.matchedPrefixLen;
        _activeWordPosition = update.matchedPrefixLen;
      });
      if (update.done) _stopYourTurn(showFeedback: true);
    });
    await socket.start();
  }

  Future<void> _stopYourTurn({bool showFeedback = false}) async {
    await _updateSub?.cancel();
    await _socket?.stop();
    if (!mounted) return;
    setState(() => _phase = showFeedback ? _Phase.feedback : _Phase.idle);
    if (showFeedback) {
      widget.onCompleted?.call();
      if (widget.autoAdvance) _startCountdown(_nextAyahSeconds, () => widget.onNextAyah?.call());
    }
  }

  void _tryAgain() {
    _cancelCountdown();
    setState(() {
      _phase = _Phase.idle;
      _matchedCount = 0;
      _activeWordPosition = -1;
    });
  }

  void _onWordTap(int position) {
    _cancelCountdown();
    showModalBottomSheet(
      context: context,
      builder: (_) => WordPracticeSheet(ayah: _ayah, wordPosition: position),
    );
  }

  bool get _isBusy => _phase == _Phase.playingTeacher || _phase == _Phase.playingStudent;

  LoopStepState get _teacherStepState {
    if (_phase == _Phase.playingTeacher) return LoopStepState.active;
    if (_teacherDone) return LoopStepState.completed;
    return _phase == _Phase.idle ? LoopStepState.active : LoopStepState.upcoming;
  }

  LoopStepState get _friendStepState {
    if (_phase == _Phase.playingStudent) return LoopStepState.active;
    if (_friendDone) return LoopStepState.completed;
    if (!_teacherDone) return LoopStepState.upcoming;
    return (_phase == _Phase.idle) ? LoopStepState.active : LoopStepState.upcoming;
  }

  LoopStepState get _meStepState {
    if (_phase == _Phase.recording || _phase == _Phase.feedback) return LoopStepState.active;
    if (!_friendDone) return LoopStepState.upcoming;
    return LoopStepState.active;
  }

  @override
  Widget build(BuildContext context) {
    final wordsTappable = _phase == _Phase.idle || _phase == _Phase.feedback;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ThreeStepIndicator(
            teacher: _teacherStepState,
            friend: _friendStepState,
            me: _phase == _Phase.feedback ? LoopStepState.completed : _meStepState,
            onTapTeacher: _isBusy || _phase == _Phase.recording ? null : _listenToTeacher,
            onTapFriend: _isBusy || _phase == _Phase.recording || !_teacherDone ? null : _listenToPeer,
            onTapMe: _isBusy || _phase == _Phase.recording || !_friendDone ? null : _startYourTurn,
          ),
          const SizedBox(height: 28),
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
              child: Column(
                children: [
                  Text('${_ayah.surahId}:${_ayah.ayahId}', style: Theme.of(context).textTheme.labelLarge),
                  const SizedBox(height: 12),
                  WordTracker(
                    words: _ayah.words,
                    activeIndex: _activeWordPosition,
                    hideText: widget.hideText,
                    onWordTap: wordsTappable ? _onWordTap : null,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 28),
          if (_phase == _Phase.feedback) _buildFeedback() else _buildPrimaryAction(),
        ],
      ),
    );
  }

  Widget _buildPrimaryAction() {
    if (_phase == _Phase.recording) return _buildRecordingProgress();

    late final Color color;
    late final IconData icon;
    late final String label;
    late final VoidCallback? onPressed;

    if (_phase == _Phase.playingTeacher) {
      color = teacherStepColor;
      icon = Icons.volume_up;
      label = 'Listening to the Teacher...';
      onPressed = null;
    } else if (_phase == _Phase.playingStudent) {
      color = friendStepColor;
      icon = Icons.volume_up;
      label = 'Listening to your Friend...';
      onPressed = null;
    } else if (!_teacherDone) {
      color = teacherStepColor;
      icon = Icons.volume_up;
      label = 'Hear the Teacher';
      onPressed = _listenToTeacher;
    } else if (!_friendDone) {
      color = friendStepColor;
      icon = Icons.emoji_people;
      label = 'Hear your Friend';
      onPressed = _listenToPeer;
    } else {
      color = meStepColor;
      icon = Icons.mic;
      label = 'Your turn! Tap to record';
      onPressed = _startYourTurn;
    }

    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: onPressed,
            style: ElevatedButton.styleFrom(
              backgroundColor: color,
              foregroundColor: Colors.white,
              disabledBackgroundColor: color.withValues(alpha: 0.6),
              disabledForegroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 18),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            icon: Icon(icon, size: 26),
            label: Text(label),
          ),
        ),
        if (_countdown != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: TextButton(
              onPressed: _cancelCountdown,
              child: Text('Next step in $_countdown... (tap to pause)', style: const TextStyle(fontSize: 13)),
            ),
          ),
      ],
    );
  }

  Widget _buildRecordingProgress() {
    final total = _ayah.words.length;
    return Column(
      children: [
        Text('Listening... $_matchedCount / $total words', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: total == 0 ? 0 : _matchedCount / total,
            minHeight: 10,
            color: meStepColor,
            backgroundColor: meStepColor.withValues(alpha: 0.15),
          ),
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: () => _stopYourTurn(),
          icon: const Icon(Icons.stop),
          label: const Text('Stop'),
        ),
      ],
    );
  }

  Widget _buildFeedback() {
    return Column(
      children: [
        const Text('🌟 Great job! 🌟', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            OutlinedButton(onPressed: _tryAgain, child: const Text('Try again')),
            const SizedBox(width: 12),
            ElevatedButton(
              onPressed: widget.onNextAyah,
              style: ElevatedButton.styleFrom(backgroundColor: teacherStepColor, foregroundColor: Colors.white),
              child: Text(widget.isLastAyah ? 'Finish' : 'Next Ayah'),
            ),
          ],
        ),
        if (_countdown != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: TextButton(
              onPressed: _cancelCountdown,
              child: Text(
                '${widget.isLastAyah ? 'Finishing' : 'Next ayah'} in $_countdown... (tap to pause)',
                style: const TextStyle(fontSize: 13),
              ),
            ),
          ),
      ],
    );
  }
}
