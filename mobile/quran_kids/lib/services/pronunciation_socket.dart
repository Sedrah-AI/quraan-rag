import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:record/record.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'api_config.dart';
import 'wav.dart';

/// One live-feedback update from /ws/pronunciation - same shape the web
/// app's Pronunciation Practice tab already consumes (matched_prefix_len
/// is a 0-based position into the ayah's word list, expected_word_count
/// is the total, done means the whole ayah matched).
class PronunciationUpdate {
  final int matchedPrefixLen;
  final int expectedWordCount;
  final bool done;

  const PronunciationUpdate({
    required this.matchedPrefixLen,
    required this.expectedWordCount,
    required this.done,
  });

  factory PronunciationUpdate.fromJson(Map<String, dynamic> json) => PronunciationUpdate(
        matchedPrefixLen: json['matched_prefix_len'] as int,
        expectedWordCount: json['expected_word_count'] as int,
        done: json['done'] as bool,
      );
}

/// Streams the mic to pronunciation-service's existing /ws/pronunciation
/// endpoint and surfaces live word-match progress - the "your turn, keep
/// trying" engine, reused unmodified from the web app's live pronunciation
/// check.
///
/// Protocol note: browsers stream MediaRecorder's incrementally-appendable
/// WebM chunks (the backend just does buffer.extend(chunk) for those).
/// Flutter's mic plugins have no equivalent - `record`'s raw PCM stream
/// gives true deltas, but headerless PCM isn't itself a decodable file.
/// Instead of appending, this accumulates all captured PCM locally and
/// sends a fresh, complete, self-contained WAV snapshot ("everything
/// recorded so far") on every tick - pronunciation-service was given a
/// small, backward-compatible addition to treat `content_type=audio/wav`
/// messages as a full replacement of its buffer rather than a delta to
/// append (the WebM/browser path is completely unchanged).
class PronunciationSocket {
  final String reference; // "surah:ayah"
  final int? wordIndex; // 1-based - null means "check the whole ayah"
  final _recorder = AudioRecorder();
  WebSocketChannel? _channel;
  StreamSubscription<Uint8List>? _micSub;
  Timer? _sendTimer;
  final BytesBuilder _pcmSoFar = BytesBuilder(copy: false);

  final _updates = StreamController<PronunciationUpdate>.broadcast();
  Stream<PronunciationUpdate> get updates => _updates.stream;

  static const _sampleRate = 16000;

  PronunciationSocket(this.reference, {this.wordIndex});

  Future<bool> hasMicPermission() => _recorder.hasPermission();

  Future<void> start() async {
    final wordParam = wordIndex != null ? '&word_index=$wordIndex' : '';
    _channel = WebSocketChannel.connect(
      Uri.parse('$kWsBaseUrl/ws/pronunciation?reference=$reference&content_type=audio%2Fwav$wordParam'),
    );
    _channel!.stream.listen(
      (message) {
        final json = jsonDecode(message as String) as Map<String, dynamic>;
        if (json.containsKey('error')) return;
        _updates.add(PronunciationUpdate.fromJson(json));
      },
      onError: (_) {},
    );

    final micStream = await _recorder.startStream(
      const RecordConfig(encoder: AudioEncoder.pcm16bits, sampleRate: _sampleRate, numChannels: 1),
    );
    // Accumulate every raw PCM callback (cheap - just buffers bytes), but
    // only actually send the growing WAV snapshot on a 1s tick, matching
    // the web client's MediaRecorder.start(1000) cadence - sending on
    // every raw callback (which fires far more often than 1s) would mean
    // re-transmitting an ever-larger "everything so far" blob many times
    // a second, an O(n^2) waste of bandwidth as the recording grows.
    _micSub = micStream.listen((chunk) => _pcmSoFar.add(chunk));
    _sendTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_pcmSoFar.length == 0) return;
      final wav = wrapPcm16AsWav(_pcmSoFar.toBytes(), sampleRate: _sampleRate);
      _channel?.sink.add(wav);
    });
  }

  Future<void> stop() async {
    _sendTimer?.cancel();
    _sendTimer = null;
    await _micSub?.cancel();
    await _recorder.stop();
    await _channel?.sink.close();
    _channel = null;
    _pcmSoFar.clear();
  }

  void dispose() {
    stop();
    _updates.close();
    _recorder.dispose();
  }
}
