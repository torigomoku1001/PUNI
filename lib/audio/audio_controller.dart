import 'dart:math';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

class AudioController {
  // Pool of AudioPlayers to allow overlapping sounds
  static const int _poolSize = 4;
  final List<AudioPlayer> _players = List.generate(
    _poolSize,
    (_) => AudioPlayer(),
  );
  int _currentPlayerIndex = 0;

  // Debounce intervals to avoid excessive audio focus churn and log spam.
  static const int _puniMinIntervalMs = 80;
  static const int _muniMinIntervalMs = 100;
  static const int _boyoMinIntervalMs = 150;
  static const int _chimeMinIntervalMs = 250;
  static const int _levelUpMinIntervalMs = 400;

  int _lastPuniMs = 0;
  int _lastMuniMs = 0;
  int _lastBoyoMs = 0;
  int _lastChimeMs = 0;
  int _lastLevelUpMs = 0;

  AudioController() {
    // Warm up players
    for (var player in _players) {
      player.setReleaseMode(ReleaseMode.release);
    }
  }

  AudioPlayer get _nextPlayer {
    final player = _players[_currentPlayerIndex];
    _currentPlayerIndex = (_currentPlayerIndex + 1) % _poolSize;
    return player;
  }

  bool _canPlay(int lastMs, int minIntervalMs) {
    final now = DateTime.now().millisecondsSinceEpoch;
    return now - lastMs >= minIntervalMs;
  }

  /// Synthesizes and plays a "puni" (squishy squeeze) sound.
  /// Lower softness = higher, tighter pitch. Higher softness = lower, wetter pitch.
  void playPuni(double softness) {
    if (!_canPlay(_lastPuniMs, _puniMinIntervalMs)) return;
    _lastPuniMs = DateTime.now().millisecondsSinceEpoch;

    // Softness goes 0 -> 100
    double pct = (softness / 100.0).clamp(0.0, 1.0);

    double startFreq = lerp(480.0, 180.0, pct);
    double endFreq = lerp(320.0, 120.0, pct);
    double duration = lerp(0.12, 0.28, pct);

    final wavBytes = _generateWav(
      frequencyStart: startFreq,
      frequencyEnd: endFreq,
      durationSeconds: duration,
      softness: softness,
      vibrato: false,
    );

    _playBytes(wavBytes);
  }

  /// Synthesizes and plays a "muni" (stretch/pull) sound.
  void playMuni(double softness) {
    if (!_canPlay(_lastMuniMs, _muniMinIntervalMs)) return;
    _lastMuniMs = DateTime.now().millisecondsSinceEpoch;

    double pct = (softness / 100.0).clamp(0.0, 1.0);

    double startFreq = lerp(350.0, 150.0, pct);
    double endFreq = lerp(450.0, 220.0, pct); // Sweep upwards
    double duration = lerp(0.15, 0.35, pct);

    final wavBytes = _generateWav(
      frequencyStart: startFreq,
      frequencyEnd: endFreq,
      durationSeconds: duration,
      softness: softness,
      vibrato: false,
    );

    _playBytes(wavBytes);
  }

  /// Synthesizes and plays a "boyo" (wall bounce) sound.
  void playBoyo(double softness) {
    if (!_canPlay(_lastBoyoMs, _boyoMinIntervalMs)) return;
    _lastBoyoMs = DateTime.now().millisecondsSinceEpoch;

    double pct = (softness / 100.0).clamp(0.0, 1.0);

    double startFreq = lerp(280.0, 110.0, pct);
    double endFreq = lerp(200.0, 90.0, pct);
    double duration = lerp(0.2, 0.5, pct);

    final wavBytes = _generateWav(
      frequencyStart: startFreq,
      frequencyEnd: endFreq,
      durationSeconds: duration,
      softness: softness,
      vibrato: true, // wobbles!
    );

    _playBytes(wavBytes);
  }

  /// Synthesizes and plays a happy chime on feeding or level up.
  void playChime() {
    if (!_canPlay(_lastChimeMs, _chimeMinIntervalMs)) return;
    _lastChimeMs = DateTime.now().millisecondsSinceEpoch;

    // Generate a simple dual-tone chime
    final wavBytes = _generateWav(
      frequencyStart: 523.25, // C5
      frequencyEnd: 783.99, // G5
      durationSeconds: 0.4,
      softness: 20.0,
      vibrato: false,
    );
    _playBytes(wavBytes);
  }

  void playLevelUp() {
    if (!_canPlay(_lastLevelUpMs, _levelUpMinIntervalMs)) return;
    _lastLevelUpMs = DateTime.now().millisecondsSinceEpoch;

    // Sequence of rising tones
    final wavBytes = _generateWav(
      frequencyStart: 440.0, // A4
      frequencyEnd: 880.0, // A5
      durationSeconds: 0.6,
      softness: 10.0,
      vibrato: true,
    );
    _playBytes(wavBytes);
  }

  Future<void> _playBytes(Uint8List bytes) async {
    try {
      final player = _nextPlayer;
      await player.play(BytesSource(bytes));
    } catch (e) {
      // Fail silently if audio is busy or not supported on this platform/simulator
      debugPrint("Audio playback error: $e");
    }
  }

  /// WAV file generator (8-bit Mono uncompressed PCM)
  Uint8List _generateWav({
    required double frequencyStart,
    required double frequencyEnd,
    required double durationSeconds,
    required double softness,
    required bool vibrato,
  }) {
    const int sampleRate = 16000;
    int totalSamples = (sampleRate * durationSeconds).toInt();
    int numChannels = 1;
    int bitsPerSample = 8;
    int byteRate = sampleRate * numChannels * (bitsPerSample ~/ 8);
    int blockAlign = numChannels * (bitsPerSample ~/ 8);
    int subChunk2Size = totalSamples * blockAlign;
    int chunkSize = 36 + subChunk2Size;

    final bytes = Uint8List(44 + subChunk2Size);
    final bd = ByteData.view(bytes.buffer);

    // RIFF Header
    bd.setUint8(0, 0x52); // R
    bd.setUint8(1, 0x49); // I
    bd.setUint8(2, 0x46); // F
    bd.setUint8(3, 0x46); // F
    bd.setUint32(4, chunkSize, Endian.little);
    bd.setUint8(8, 0x57); // W
    bd.setUint8(9, 0x41); // A
    bd.setUint8(10, 0x56); // V
    bd.setUint8(11, 0x45); // E

    // fmt subchunk
    bd.setUint8(12, 0x66); // f
    bd.setUint8(13, 0x6d); // m
    bd.setUint8(14, 0x74); // t
    bd.setUint8(15, 0x20); //
    bd.setUint32(16, 16, Endian.little);
    bd.setUint16(20, 1, Endian.little); // PCM
    bd.setUint16(22, numChannels, Endian.little);
    bd.setUint32(24, sampleRate, Endian.little);
    bd.setUint32(28, byteRate, Endian.little);
    bd.setUint16(32, blockAlign, Endian.little);
    bd.setUint16(34, bitsPerSample, Endian.little);

    // data subchunk
    bd.setUint8(36, 0x64); // d
    bd.setUint8(37, 0x61); // a
    bd.setUint8(38, 0x74); // t
    bd.setUint8(39, 0x61); // a
    bd.setUint32(40, subChunk2Size, Endian.little);

    // Generate samples
    for (int t = 0; t < totalSamples; t++) {
      double progress = t / totalSamples;

      // Phase frequency interpolation
      double freq = frequencyStart + (frequencyEnd - frequencyStart) * progress;

      if (vibrato) {
        // Wobble frequency (boyo sound)
        double speed = 12.0 + (100.0 - softness) * 0.1;
        double depth = 20.0 * (softness / 100.0);
        freq += sin(2 * pi * speed * (t / sampleRate)) * depth;
      }

      double tSec = t / sampleRate;
      double phase = 2 * pi * freq * tSec;

      double waveVal = sin(phase);

      // Sound Envelope (Fade in quickly, decay exponentially, fade out at end)
      double envelope = 1.0;
      if (progress < 0.1) {
        envelope = progress / 0.1;
      } else if (progress > 0.85) {
        envelope = (1.0 - progress) / 0.15;
      }

      // Softness dampens/filters high frequencies or volumes
      double expDecay = exp(-4.0 * progress);
      envelope *= expDecay;

      int sample = (128 + 127 * waveVal * envelope).round().clamp(0, 255);
      bytes[44 + t] = sample;
    }

    return bytes;
  }

  double lerp(double a, double b, double t) => a + (b - a) * t;

  void dispose() {
    for (var player in _players) {
      player.dispose();
    }
  }
}
