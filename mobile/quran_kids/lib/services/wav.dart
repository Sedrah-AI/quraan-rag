import 'dart:typed_data';

/// Wraps raw 16-bit PCM samples in a standard 44-byte WAV header, producing
/// one complete, self-contained, decodable file. Used to send a fresh
/// "everything captured so far" snapshot to /ws/pronunciation on every
/// tick - see PronunciationSocket's docstring for why (Flutter's mic
/// plugins have no equivalent of the browser's incrementally-appendable
/// MediaRecorder chunks, so the client resends the whole growing
/// recording each time instead of true deltas).
Uint8List wrapPcm16AsWav(Uint8List pcmData, {int sampleRate = 16000, int numChannels = 1}) {
  const bitsPerSample = 16;
  final byteRate = sampleRate * numChannels * bitsPerSample ~/ 8;
  final blockAlign = numChannels * bitsPerSample ~/ 8;
  final dataLength = pcmData.length;

  final header = ByteData(44);
  void writeString(int offset, String s) {
    for (var i = 0; i < s.length; i++) {
      header.setUint8(offset + i, s.codeUnitAt(i));
    }
  }

  writeString(0, 'RIFF');
  header.setUint32(4, 36 + dataLength, Endian.little);
  writeString(8, 'WAVE');
  writeString(12, 'fmt ');
  header.setUint32(16, 16, Endian.little); // fmt chunk size
  header.setUint16(20, 1, Endian.little); // PCM
  header.setUint16(22, numChannels, Endian.little);
  header.setUint32(24, sampleRate, Endian.little);
  header.setUint32(28, byteRate, Endian.little);
  header.setUint16(32, blockAlign, Endian.little);
  header.setUint16(34, bitsPerSample, Endian.little);
  writeString(36, 'data');
  header.setUint32(40, dataLength, Endian.little);

  return Uint8List(44 + dataLength)
    ..setRange(0, 44, header.buffer.asUint8List())
    ..setRange(44, 44 + dataLength, pcmData);
}
