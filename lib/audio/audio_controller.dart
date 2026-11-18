import 'dart:collection';
import 'dart:math';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

class AudioController {
  static const int _poolSize = 6;
  final List<AudioPlayer> _playerPool = [];
  int _currentPlayerIndex = 0;

  final Queue<Future<void> Function()> _queue =
      Queue<Future<void> Function()>();
  bool _isDrainingQueue = false;
  final Map<String, int> _lastEventMs = <String, int>{};
  final Random _random = Random();
  bool isMuted = false;

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
    'Guni-.wav',
  ];

  AudioController() {
    _initPlayer();
  }

  void _initPlayer() {
    _playerPool.clear();
    for (int i = 0; i < _poolSize; i++) {
      final player = AudioPlayer();
      player.setReleaseMode(ReleaseMode.stop);
      // Use lowLatency mode to prevent pop/click sounds when audio stops
      player.setPlayerMode(PlayerMode.lowLatency);
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

  Future<void> _playAssetNow(String fileName) async {
    if (isMuted) return;
    debugPrint('Voice try: $fileName');
    
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
      
      // Override the default 'assets/' prefix to load directly from lib/audio/
      player.audioCache.prefix = '';
      
      // Play the asset directly to prevent disk I/O pop noises
      await player.play(AssetSource('lib/audio/$fileName'));
      
      // Short delay for sequence buffering
      await Future<void>.delayed(const Duration(milliseconds: 25));
    } catch (e) {
      debugPrint('Audio playback error: $e');
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
    _enqueueRandom(_idleVoices, key: 'idle', minIntervalMs: 0);
  }

  Future<void> playGrabVoice({required bool hasEnergy}) async {
    // Grabbing sound removed per design decision.
  }

  Future<void> playFlingVoice({required bool hasEnergy}) async {
    // Flinging sound removed per design decision.
  }

  Future<void> playPetEndVoice({required bool hasEnergy}) async {
    if (hasEnergy) {
      _enqueue(() => _playAssetNow('Nyo-n.wav'), highPriority: true);
    } else {
      _enqueue(() => _playAssetNow('zeronade.wav'), highPriority: true);
    }
  }

  Future<void> playPinchReleaseVoice() async {
    _enqueue(() => _playAssetNow('Byui-n.wav'), highPriority: true);
  }

  Future<void> playInflateReleaseVoice() async {
    _enqueue(() => _playAssetNow('bo-n.wav'), highPriority: true);
  }


  Future<void> playWallHitVoice({
    required int level,
    required bool hasEnergy,
  }) async {
    // Wall hit sound removed per design decision.
  }

  Future<void> playLevelUpVoice() async {
    if (!_canTrigger('levelup', 1000)) return;
    _enqueue(() => _playAssetNow('free3.wav'), highPriority: true);
  }

  Future<void> playFeedVoice() async {
    // Suppress level-up voice from playing simultaneously when feeding causes a level up
    _lastEventMs['levelup'] = DateTime.now().millisecondsSinceEpoch;
    _enqueue(() => _playAssetNow('Myu-n-.wav'), highPriority: true);
  }

  void playPuni(double softness) {}
  void playMuni(double softness) {}
  void playBoyo(double softness) {}
  void playChime() {}
  void playLevelUp() {}

  void dispose() {
    _queue.clear();
    for (var player in _playerPool) {
      try {
        player.dispose();
      } catch (_) {}
    }
  }
}
