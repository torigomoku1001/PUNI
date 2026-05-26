import 'dart:collection';
import 'dart:math';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class AudioController {
  late AudioPlayer _voicePlayer;
  final Queue<Future<void> Function()> _queue =
      Queue<Future<void> Function()>();
  bool _isDrainingQueue = false;
  final Map<String, int> _lastEventMs = <String, int>{};
  final Random _random = Random();

  static final AudioContext _audioContext = AudioContext(
    android: AudioContextAndroid(
      isSpeakerphoneOn: false,
      stayAwake: false,
      contentType: AndroidContentType.music,
      usageType: AndroidUsageType.media,
      audioFocus: AndroidAudioFocus.gain,
    ),
    iOS: AudioContextIOS(category: AVAudioSessionCategory.ambient, options: {}),
  );

  // Voice files.
  static const List<String> _startupVoices = [
    'start1.wav',
    'start2.wav',
    'start3.wav',
    'start4.wav',
    'start5.wav',
  ];
  static const List<String> _idleVoices = [
    'free1.wav',
    'free2.wav',
    'free3.wav',
    'free4.wav',
    'free5.wav',
    'free6.wav',
    'free7.wav',
  ];

  AudioController() {
    _initPlayer();
  }

  void _initPlayer() {
    _voicePlayer = AudioPlayer();
    _voicePlayer.setReleaseMode(ReleaseMode.stop);
    _voicePlayer.setPlayerMode(PlayerMode.mediaPlayer);
    _voicePlayer.setAudioContext(_audioContext);
    _voicePlayer.setVolume(1.0);
  }

  Future<void> _resetPlayer() async {
    try {
      await _voicePlayer.dispose();
    } catch (_) {
      // Ignore dispose errors and recreate anyway.
    }
    _initPlayer();
  }

  bool _canTrigger(String key, int minIntervalMs) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final last = _lastEventMs[key] ?? 0;
    if (now - last < minIntervalMs) return false;
    _lastEventMs[key] = now;
    return true;
  }

  void _enqueue(Future<void> Function() task, {bool highPriority = false}) {
    if (highPriority) {
      _queue.addFirst(task);
    } else {
      _queue.addLast(task);
    }
    _drainQueue();
  }

  Future<void> _drainQueue() async {
    if (_isDrainingQueue) return;
    _isDrainingQueue = true;

    while (_queue.isNotEmpty) {
      final task = _queue.removeFirst();
      try {
        await task();
      } catch (e) {
        debugPrint('Audio queue task error: $e');
      }
    }

    _isDrainingQueue = false;
  }

  Future<void> _playAssetNow(String fileName, {double pcmGain = 1.0}) async {
    debugPrint('Voice try: $fileName');
    try {
      final data = await rootBundle.load('lib/audio/$fileName');
      final rawBytes = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );
      final bytes = _maybeBoostPcmWav(rawBytes, gain: pcmGain);
      await _playBytesNow(bytes);
    } catch (e) {
      debugPrint('Audio route recovery(asset): $e');
      await _resetPlayer();
      final data = await rootBundle.load('lib/audio/$fileName');
      final rawBytes = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );
      final bytes = _maybeBoostPcmWav(rawBytes, gain: pcmGain);
      await _playBytesNow(bytes);
    }
  }

  Future<void> _playBytesNow(Uint8List bytes) async {
    try {
      await _voicePlayer.stop();
      await _voicePlayer.setAudioContext(_audioContext);
      await _voicePlayer.setVolume(1.0);
      await _voicePlayer.play(BytesSource(bytes));
      await _voicePlayer.onPlayerComplete.first.timeout(
        const Duration(seconds: 4),
        onTimeout: () => null,
      );
    } catch (e) {
      debugPrint('Audio route recovery(bytes): $e');
      await _resetPlayer();
      await _voicePlayer.stop();
      await _voicePlayer.setAudioContext(_audioContext);
      await _voicePlayer.setVolume(1.0);
      await _voicePlayer.play(BytesSource(bytes));
      await _voicePlayer.onPlayerComplete.first.timeout(
        const Duration(seconds: 4),
        onTimeout: () => null,
      );
    }
  }

  Future<void> resetAudioSession() async {
    _queue.clear();
    await _resetPlayer();
  }

  void _enqueueRandom(
    List<String> files, {
    required String key,
    required int minIntervalMs,
    bool highPriority = false,
  }) {
    if (files.isEmpty) return;
    if (!_canTrigger(key, minIntervalMs)) return;
    final selected = files[_random.nextInt(files.length)];
    _enqueue(() => _playAssetNow(selected), highPriority: highPriority);
  }

  Future<void> playStartupVoice() async {
    _enqueueRandom(
      _startupVoices,
      key: 'startup',
      minIntervalMs: 0,
      highPriority: true,
    );
  }

  Future<void> playIdleVoice() async {
    _enqueueRandom(_idleVoices, key: 'idle', minIntervalMs: 4000);
  }

  Future<void> playGrabVoice({required bool hasEnergy}) async {
    _enqueue(
      () => _playAssetNow(hasEnergy ? 'pulusdrag.wav' : 'zerodrag.wav'),
      highPriority: true,
    );
  }

  Future<void> playFlingVoice({required bool hasEnergy}) async {
    _enqueue(
      () => _playAssetNow(hasEnergy ? 'plussrrow.wav' : 'iya-.wav'),
      highPriority: true,
    );
  }

  Future<void> playPetEndVoice({required bool hasEnergy}) async {
    _enqueue(
      () => _playAssetNow(hasEnergy ? 'plusnade.wav' : 'zeronade.wav'),
      highPriority: true,
    );
  }

  Future<void> playWallHitVoice({
    required int level,
    required bool hasEnergy,
  }) async {
    // Wall hit sound removed per design decision.
  }

  Future<void> playLevelUpVoice() async {
    _enqueue(() => _playAssetNow('waho-i.wav'), highPriority: true);
  }

  Future<void> playFeedVoice() async {
    _enqueue(() => _playAssetNow('food.wav'), highPriority: true);
  }

  /// Synthesizes and plays a "puni" (squishy squeeze) sound.
  /// Lower softness = higher, tighter pitch. Higher softness = lower, wetter pitch.
  void playPuni(double softness) {
    if (!_canTrigger('puni', 90)) return;

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

    _enqueue(() => _playBytesNow(wavBytes));
  }

  /// Synthesizes and plays a "muni" (stretch/pull) sound.
  void playMuni(double softness) {
    if (!_canTrigger('muni', 100)) return;

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

    _enqueue(() => _playBytesNow(wavBytes));
  }

  /// Synthesizes and plays a "boyo" (wall bounce) sound.
  void playBoyo(double softness) {
    if (!_canTrigger('boyo', 150)) return;

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

    _enqueue(() => _playBytesNow(wavBytes));
  }

  /// Synthesizes and plays a happy chime on feeding or level up.
  void playChime() {
    if (!_canTrigger('chime', 220)) return;

    // Generate a simple dual-tone chime
    final wavBytes = _generateWav(
      frequencyStart: 523.25, // C5
      frequencyEnd: 783.99, // G5
      durationSeconds: 0.4,
      softness: 20.0,
      vibrato: false,
    );
    _enqueue(() => _playBytesNow(wavBytes), highPriority: true);
  }

  void playLevelUp() {
    if (!_canTrigger('levelUpSynth', 350)) return;

    // Sequence of rising tones
    final wavBytes = _generateWav(
      frequencyStart: 440.0, // A4
      frequencyEnd: 880.0, // A5
      durationSeconds: 0.6,
      softness: 10.0,
      vibrato: true,
    );
    _enqueue(() => _playBytesNow(wavBytes), highPriority: true);
  }

  Uint8List _maybeBoostPcmWav(Uint8List wavBytes, {required double gain}) {
    if (gain <= 1.0 || wavBytes.length < 44) return wavBytes;

    final bd = ByteData.sublistView(wavBytes);

    bool matchesText(int start, String text) {
      if (start + text.length > wavBytes.length) return false;
      for (int i = 0; i < text.length; i++) {
        if (wavBytes[start + i] != text.codeUnitAt(i)) return false;
      }
      return true;
    }

    if (!matchesText(0, 'RIFF') || !matchesText(8, 'WAVE')) {
      return wavBytes;
    }

    final int bitsPerSample = bd.getUint16(34, Endian.little);
    if (bitsPerSample != 8 && bitsPerSample != 16) return wavBytes;

    int dataOffset = -1;
    int dataSize = 0;
    int ptr = 12;
    while (ptr + 8 <= wavBytes.length) {
      final idBytes = wavBytes.sublist(ptr, ptr + 4);
      final size = bd.getUint32(ptr + 4, Endian.little);
      final id = String.fromCharCodes(idBytes);
      if (id == 'data') {
        dataOffset = ptr + 8;
        dataSize = size;
        break;
      }
      ptr += 8 + size;
      if (size.isOdd) ptr += 1;
    }

    if (dataOffset < 0 || dataOffset >= wavBytes.length) return wavBytes;
    final safeDataEnd = min(wavBytes.length, dataOffset + dataSize);
    final out = Uint8List.fromList(wavBytes);

    if (bitsPerSample == 8) {
      for (int i = dataOffset; i < safeDataEnd; i++) {
        final centered = out[i] - 128;
        final boosted = (centered * gain).round().clamp(-128, 127);
        out[i] = boosted + 128;
      }
      return out;
    }

    for (int i = dataOffset; i + 1 < safeDataEnd; i += 2) {
      final s = bd.getInt16(i, Endian.little);
      final boosted = (s * gain).round().clamp(-32768, 32767);
      out.buffer.asByteData().setInt16(i, boosted, Endian.little);
    }
    return out;
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
    _queue.clear();
    _voicePlayer.dispose();
  }
}
