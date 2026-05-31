import 'dart:collection';
import 'dart:io';
import 'dart:math';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

class AudioController {
  static const int _poolSize = 6;
  final List<AudioPlayer> _playerPool = [];
  final List<File?> _tempAudioFiles = List.filled(_poolSize, null);
  int _currentPlayerIndex = 0;

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
    iOS: AudioContextIOS(
      category: AVAudioSessionCategory.playback,
      options: {AVAudioSessionOptions.mixWithOthers},
    ),
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
    'free5.wav',
    'free6.wav',
  ];

  AudioController() {
    _initPlayer();
  }

  void _initPlayer() {
    _playerPool.clear();
    for (int i = 0; i < _poolSize; i++) {
      final player = AudioPlayer();
      player.setReleaseMode(ReleaseMode.stop);
      player.setPlayerMode(PlayerMode.mediaPlayer);
      player.setAudioContext(_audioContext);
      player.setVolume(1.0);
      _playerPool.add(player);
    }
  }

  Future<void> _resetPlayer() async {
    for (var player in _playerPool) {
      try {
        await player.dispose();
      } catch (_) {
        // Ignore dispose errors
      }
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

  File? _tempAudioFile;

  Uint8List _applyFadeInOut(Uint8List wavBytes) {
    if (wavBytes.length < 44) return wavBytes;

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
      final size = bd.getUint32(ptr + 4, Endian.little);
      if (ptr + 8 > wavBytes.length) break;
      final idBytes = wavBytes.sublist(ptr, ptr + 4);
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

    final int totalSamples = bitsPerSample == 8
        ? (safeDataEnd - dataOffset)
        : (safeDataEnd - dataOffset) ~/ 2;

    // Fade out the last 4410 samples (~100ms at 44.1kHz) or 15% of the file, whichever is smaller.
    final int fadeOutSamples = min(4410, (totalSamples * 0.15).round());
    // Fade in the first 441 samples (~10ms) or 5% of the file, whichever is smaller.
    final int fadeInSamples = min(441, (totalSamples * 0.05).round());

    if (bitsPerSample == 8) {
      // Apply Fade In
      final int fadeInCount = min(fadeInSamples, totalSamples);
      for (int i = 0; i < fadeInCount; i++) {
        final int index = dataOffset + i;
        final double volume = i / fadeInCount;
        final int centered = out[index] - 128;
        final int faded = (centered * volume).round().clamp(-128, 127);
        out[index] = faded + 128;
      }

      // Apply Fade Out
      final int fadeOutCount = min(fadeOutSamples, totalSamples);
      final int fadeOutStart = safeDataEnd - fadeOutCount;
      for (int i = 0; i < fadeOutCount; i++) {
        final int index = fadeOutStart + i;
        final double volume = 1.0 - (i / fadeOutCount);
        final int centered = out[index] - 128;
        final int faded = (centered * volume).round().clamp(-128, 127);
        out[index] = faded + 128;
      }
    } else if (bitsPerSample == 16) {
      final byteDataOut = out.buffer.asByteData();

      // Apply Fade In
      final int fadeInCount = min(fadeInSamples, totalSamples);
      for (int i = 0; i < fadeInCount; i++) {
        final int byteIndex = dataOffset + i * 2;
        if (byteIndex + 1 < safeDataEnd) {
          final double volume = i / fadeInCount;
          final int s = bd.getInt16(byteIndex, Endian.little);
          final int faded = (s * volume).round().clamp(-32768, 32767);
          byteDataOut.setInt16(byteIndex, faded, Endian.little);
        }
      }

      // Apply Fade Out
      final int fadeOutCount = min(fadeOutSamples, totalSamples);
      final int fadeOutStartSample = totalSamples - fadeOutCount;
      for (int i = 0; i < fadeOutCount; i++) {
        final int sampleIndex = fadeOutStartSample + i;
        final int byteIndex = dataOffset + sampleIndex * 2;
        if (byteIndex + 1 < safeDataEnd) {
          final double volume = 1.0 - (i / fadeOutCount);
          final int s = bd.getInt16(byteIndex, Endian.little);
          final int faded = (s * volume).round().clamp(-32768, 32767);
          byteDataOut.setInt16(byteIndex, faded, Endian.little);
        }
      }
    }

    return out;
  }

  int _getWavDurationMs(Uint8List wavBytes) {
    if (wavBytes.length < 44) return 0;
    final bd = ByteData.sublistView(wavBytes);

    bool matchesText(int start, String text) {
      if (start + text.length > wavBytes.length) return false;
      for (int i = 0; i < text.length; i++) {
        if (wavBytes[start + i] != text.codeUnitAt(i)) return false;
      }
      return true;
    }

    if (!matchesText(0, 'RIFF') || !matchesText(8, 'WAVE')) {
      return 0;
    }

    final int channels = bd.getUint16(22, Endian.little);
    final int sampleRate = bd.getUint32(24, Endian.little);
    final int bitsPerSample = bd.getUint16(34, Endian.little);

    int dataSize = 0;
    int ptr = 12;
    while (ptr + 8 <= wavBytes.length) {
      final size = bd.getUint32(ptr + 4, Endian.little);
      if (ptr + 8 > wavBytes.length) break;
      final idBytes = wavBytes.sublist(ptr, ptr + 4);
      final id = String.fromCharCodes(idBytes);
      if (id == 'data') {
        dataSize = size;
        break;
      }
      ptr += 8 + size;
      if (size.isOdd) ptr += 1;
    }

    if (dataSize <= 0 ||
        sampleRate <= 0 ||
        channels <= 0 ||
        bitsPerSample <= 0) {
      return 0;
    }

    final int bytesPerSample = bitsPerSample ~/ 8;
    final int bytesPerSecond = sampleRate * channels * bytesPerSample;
    if (bytesPerSecond == 0) return 0;

    return (dataSize * 1000) ~/ bytesPerSecond;
  }

  Future<void> _playBytesNow(Uint8List bytes) async {
    int playerIndex = -1;
    for (int i = 0; i < _poolSize; i++) {
      if (_playerPool[i].state != PlayerState.playing) {
        playerIndex = i;
        break;
      }
    }
    if (playerIndex == -1) {
      playerIndex = _currentPlayerIndex;
      _currentPlayerIndex = (_currentPlayerIndex + 1) % _poolSize;
    }
    final AudioPlayer player = _playerPool[playerIndex];

    try {
      if (player.state == PlayerState.playing) {
        await player.stop();
      }
      await player.setVolume(1.0);

      // Smoothly fade in/out both ends of the audio to prevent pop/click noise
      final fadedBytes = _applyFadeInOut(bytes);

      Source source;
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        if (_tempAudioFiles[playerIndex] == null) {
          final tempDir = await getTemporaryDirectory();
          _tempAudioFiles[playerIndex] = File(
            '${tempDir.path}/temp_voice_$playerIndex.wav',
          );
        }
        await _tempAudioFiles[playerIndex]!.writeAsBytes(
          fadedBytes,
          flush: true,
        );
        source = DeviceFileSource(_tempAudioFiles[playerIndex]!.path);
      } else {
        source = BytesSource(fadedBytes);
      }

      await player.play(source);
      // Wait a tiny bit (25ms) to serialize platform-channel triggers
      await Future<void>.delayed(const Duration(milliseconds: 25));
    } catch (e) {
      debugPrint('Audio route recovery(bytes): $e');
      await _resetPlayer();
      try {
        final AudioPlayer recoveredPlayer = _playerPool[playerIndex];
        if (recoveredPlayer.state == PlayerState.playing) {
          await recoveredPlayer.stop();
        }
        await recoveredPlayer.setVolume(1.0);

        final fadedBytes = _applyFadeInOut(bytes);

        Source source;
        if (defaultTargetPlatform == TargetPlatform.iOS) {
          if (_tempAudioFiles[playerIndex] == null) {
            final tempDir = await getTemporaryDirectory();
            _tempAudioFiles[playerIndex] = File(
              '${tempDir.path}/temp_voice_$playerIndex.wav',
            );
          }
          await _tempAudioFiles[playerIndex]!.writeAsBytes(
            fadedBytes,
            flush: true,
          );
          source = DeviceFileSource(_tempAudioFiles[playerIndex]!.path);
        } else {
          source = BytesSource(fadedBytes);
        }

        await recoveredPlayer.play(source);
        await Future<void>.delayed(const Duration(milliseconds: 25));
      } catch (innerErr) {
        debugPrint('Failed to play audio in recovery: $innerErr');
      }
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
    // Grabbing sound removed per design decision.
  }

  Future<void> playFlingVoice({required bool hasEnergy}) async {
    // Flinging sound removed per design decision.
  }

  Future<void> playPetEndVoice({required bool hasEnergy}) async {
    _enqueue(() => _playAssetNow('zeronade.wav'), highPriority: true);
  }

  Future<void> playWallHitVoice({
    required int level,
    required bool hasEnergy,
  }) async {
    // Wall hit sound removed per design decision.
  }

  Future<void> playLevelUpVoice() async {
    _enqueue(() => _playAssetNow('free3.wav'), highPriority: true);
  }

  Future<void> playFeedVoice() async {
    _enqueue(() => _playAssetNow('free3.wav'), highPriority: true);
  }

  /// Plays puni sound (disabled - using real voice samples instead)
  void playPuni(double softness) {
    // Synthesized puni sound disabled - using asset-based voice samples only
  }

  /// Plays muni sound (disabled - using real voice samples instead)
  void playMuni(double softness) {
    // Synthesized muni sound disabled - using asset-based voice samples only
  }

  /// Plays boyo sound (disabled - using real voice samples instead)
  void playBoyo(double softness) {
    // Synthesized boyo sound disabled - using asset-based voice samples only
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
    for (var player in _playerPool) {
      try {
        player.dispose();
      } catch (_) {}
    }
  }
}
