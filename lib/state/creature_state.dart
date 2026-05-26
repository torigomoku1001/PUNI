import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CreatureState extends ChangeNotifier {
  // Persistence Keys
  static const String _keyLevel = 'puni_level';
  static const String _keyShape = 'puni_shape';
  static const String _keyMood = 'puni_mood';
  static const String _keySteps = 'puni_steps';
  static const String _keyGrowth = 'puni_growth';
  static const String _keyMorningPoints = 'puni_morning_points';
  static const String _keyNightPoints = 'puni_night_points';
  static const String _keyFeedPoints = 'puni_feed_points';
  static const String _keyAdPoints = 'puni_ad_points';
  static const String _keyEnergy = 'puni_energy';

  // Properties
  int _level = 1;
  String _shape = 'default';
  String _mood = 'normal';
  int _stepsToday = 0;
  double _growthToday = 0.0; // 0.0 to 1.0 (level progress)
  double _energy = 100.0; // Puni Energy (0.0 to 100.0)

  // Care interaction stats (growth points contributed by activity)
  double _morningPoints = 0.0;
  double _nightPoints = 0.0;
  double _feedPoints = 0.0;
  double _adPoints = 0.0;

  // Boost States (Rainbow mode kept internally as fallback or for visual effects)
  bool _isRainbow = false;
  int _boostTimeRemaining = 0;
  Timer? _boostTimer;

  // Active touch details
  Offset? _touchPosition;
  bool _isDragging = false;
  bool _isPetting = false;

  // Timers
  Timer? _moodResetTimer;
  Timer? _poseTimer;
  Timer? _poseResetTimer;

  // Getters
  int get level => _level;
  double get softness => _isRainbow ? 98.0 : getSoftnessForLevel(_level);
  String get shape => _shape;
  String get mood => _mood;
  int get stepsToday => _stepsToday;
  double get growthToday => _growthToday;
  double get energy => _energy;
  bool get isRainbow => _isRainbow;
  int get boostTimeRemaining => _boostTimeRemaining;
  Offset? get touchPosition => _touchPosition;
  bool get isDragging => _isDragging;
  bool get isPetting => _isPetting;
  double get morningPoints => _morningPoints;
  double get nightPoints => _nightPoints;
  double get feedPoints => _feedPoints;
  double get adPoints => _adPoints;

  // Dynamic Mixed Color based on training activity distribution (starting at Grey, transitioning to vibrant)
  Color get creatureColor {
    // Target colors for care style
    const morningColor = Color(0xFFFF8DA1); // Pink (桃色)
    const nightColor = Color(0xFFB388FF); // Purple (紫色)
    const adColor = Color(0xFF80D8FF); // Sky Blue (水色)
    const feedColor = Color(0xFFFFD740); // Yellow (黄色)

    double total = _morningPoints + _nightPoints + _adPoints + _feedPoints;

    // Balanced defaults if total is 0 (e.g. at start)
    double pMorning = total == 0 ? 0.25 : _morningPoints / total;
    double pNight = total == 0 ? 0.25 : _nightPoints / total;
    double pAd = total == 0 ? 0.25 : _adPoints / total;
    double pFeed = total == 0 ? 0.25 : _feedPoints / total;

    // Blend the RGB values
    double r =
        morningColor.red * pMorning +
        nightColor.red * pNight +
        adColor.red * pAd +
        feedColor.red * pFeed;
    double g =
        morningColor.green * pMorning +
        nightColor.green * pNight +
        adColor.green * pAd +
        feedColor.green * pFeed;
    double b =
        morningColor.blue * pMorning +
        nightColor.blue * pNight +
        adColor.blue * pAd +
        feedColor.blue * pFeed;

    Color trainedColor = Color.fromARGB(255, r.round(), g.round(), b.round());

    // Transition from Grey (0xFFD2D2D8) to the trainedColor as level rises from 1 to 100+
    double colorBlendPct = ((_level - 1) / 99.0).clamp(0.0, 1.0);
    return Color.lerp(const Color(0xFFD2D2D8), trainedColor, colorBlendPct)!;
  }

  // Softness mapping based on level:
  // Lv1: 木みたいに硬い (1.0%)
  // Lv5: 少しぷに (20.0%)
  // Lv15: ゼリー (45.0%)
  // Lv30: 水風船 (65.0%)
  // Lv50: 液体系 (80.0%)
  // Lv100: ほぼスライム (95.0%)
  double getSoftnessForLevel(int lvl) {
    if (lvl <= 1) return 1.0;
    if (lvl <= 5) {
      // Interpolate 1.0 -> 20.0
      return 1.0 + (lvl - 1) / 4.0 * (20.0 - 1.0);
    }
    if (lvl <= 15) {
      // Interpolate 20.0 -> 45.0
      return 20.0 + (lvl - 5) / 10.0 * (45.0 - 20.0);
    }
    if (lvl <= 30) {
      // Interpolate 45.0 -> 65.0
      return 45.0 + (lvl - 15) / 15.0 * (65.0 - 45.0);
    }
    if (lvl <= 50) {
      // Interpolate 65.0 -> 80.0
      return 65.0 + (lvl - 30) / 20.0 * (80.0 - 65.0);
    }
    if (lvl <= 100) {
      // Interpolate 80.0 -> 95.0
      return 80.0 + (lvl - 50) / 50.0 * (95.0 - 80.0);
    }
    return 95.0; // Cap at 95.0% softness
  }

  // Label text matching level state
  String get softnessLabel {
    if (_level < 5) return '木みたいに硬い';
    if (_level < 15) return '少しぷに';
    if (_level < 30) return 'ゼリー';
    if (_level < 50) return '水風船';
    if (_level < 100) return '液体系';
    return 'ほぼスライム';
  }

  CreatureState() {
    _loadState();
    _startPoseTimer();
  }

  // Load from local storage
  Future<void> _loadState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _level = prefs.getInt(_keyLevel) ?? 1;
      _shape = prefs.getString(_keyShape) ?? 'default';
      _mood = prefs.getString(_keyMood) ?? 'normal';
      _stepsToday = prefs.getInt(_keySteps) ?? 0;
      _growthToday = prefs.getDouble(_keyGrowth) ?? 0.0;
      _energy = prefs.getDouble(_keyEnergy) ?? 100.0;
      _morningPoints = prefs.getDouble(_keyMorningPoints) ?? 0.0;
      _nightPoints = prefs.getDouble(_keyNightPoints) ?? 0.0;
      _feedPoints = prefs.getDouble(_keyFeedPoints) ?? 0.0;
      _adPoints = prefs.getDouble(_keyAdPoints) ?? 0.0;
      notifyListeners();
    } catch (e) {
      debugPrint("Error loading SharedPreferences: $e");
    }
  }

  // Save to local storage
  Future<void> _saveState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_keyLevel, _level);
      await prefs.setString(_keyShape, _shape);
      await prefs.setString(_keyMood, _mood);
      await prefs.setInt(_keySteps, _stepsToday);
      await prefs.setDouble(_keyGrowth, _growthToday);
      await prefs.setDouble(_keyEnergy, _energy);
      await prefs.setDouble(_keyMorningPoints, _morningPoints);
      await prefs.setDouble(_keyNightPoints, _nightPoints);
      await prefs.setDouble(_keyFeedPoints, _feedPoints);
      await prefs.setDouble(_keyAdPoints, _adPoints);
    } catch (e) {
      debugPrint("Error saving SharedPreferences: $e");
    }
  }

  // Debug level selector
  void debugSetLevel(int lv) {
    _level = lv;
    _saveState();
    notifyListeners();
  }

  // Set interaction state
  void setInteraction({
    required bool isDragging,
    required bool isPetting,
    Offset? touchPosition,
  }) {
    if (isDragging && !_isDragging) {
      if (_energy <= 0.0) {
        _mood = 'sad'; // Out of energy: Surprised/Painful/Sad when grabbed
      } else {
        _mood = 'happy'; // Energetic: happy when grabbed/held
      }
    } else if (isPetting && !_isPetting) {
      if (_energy <= 0.0) {
        _mood = 'angry'; // Out of energy: annoyed (嫌そう)
      } else {
        _mood = 'happy'; // Shy/happy (照れる)
      }
    } else if (!isDragging && !isPetting && (_isDragging || _isPetting)) {
      _mood = 'normal'; // Released -> Normal
    }

    _isDragging = isDragging;
    _isPetting = isPetting;
    _touchPosition = touchPosition;
    notifyListeners();
  }

  // Trigger temporary mood
  void triggerMood(
    String newMood, {
    Duration duration = const Duration(seconds: 4),
  }) {
    _moodResetTimer?.cancel();
    _mood = newMood;
    notifyListeners();
    _saveState();

    _moodResetTimer = Timer(duration, () {
      _mood = 'normal';
      notifyListeners();
      _saveState();
    });
  }

  // Gain growth progress with source tracking and Puni Energy check
  void addGrowth(double amount, {required String source}) {
    bool requiresEnergy = (source == 'petting' || source == 'fling');

    if (requiresEnergy) {
      if (_energy <= 0.0) {
        // No energy, reject experience growth
        return;
      }

      // Calculate energy cost. 1.0 growth = 100.0 energy
      double cost = amount * 100.0;
      if (cost > _energy) {
        amount = _energy / 100.0;
        cost = _energy;
      }

      _energy -= cost;
      if (_energy < 0.0) _energy = 0.0;
    }

    double multiplier = _isRainbow ? 2.5 : 1.0;
    double actualAmount = amount * multiplier;
    _growthToday += actualAmount;

    // Apply color channel points
    if (source == 'feed') {
      _feedPoints += actualAmount;
    } else if (source == 'ad') {
      _adPoints += actualAmount;
    } else if (source == 'petting' || source == 'fling') {
      // Determine color channel by time of day
      int hour = DateTime.now().hour;
      if (hour >= 5 && hour < 18) {
        _morningPoints += actualAmount; // Morning: 5am to 6pm
      } else {
        _nightPoints += actualAmount; // Night: 6pm to 5am
      }
    }

    if (_growthToday >= 1.0) {
      _levelUp();
    } else {
      notifyListeners();
      _saveState();
    }
  }

  void _levelUp() {
    _level++;
    _growthToday = max(0.0, _growthToday - 1.0);
    triggerMood('levelup', duration: const Duration(milliseconds: 100));
    notifyListeners();
    _saveState();
  }

  // Instant level up triggered by interstitial ad watch (rewards 1.0 full growth under ad source)
  void performAdLevelUp() {
    addGrowth(1.0, source: 'ad');
  }

  // Set shape manually (kept internally)
  void setShape(String newShape) {
    _shape = newShape;
    triggerMood('surprised', duration: const Duration(seconds: 2));
    notifyListeners();
    _saveState();
  }

  // Ambient/Ad trigger for temporary rainbow effects
  void activateAdBoost() {
    _boostTimer?.cancel();
    _isRainbow = true;
    _boostTimeRemaining = 15;
    triggerMood('happy', duration: const Duration(seconds: 4));
    notifyListeners();

    _boostTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_boostTimeRemaining > 1) {
        _boostTimeRemaining--;
        notifyListeners();
      } else {
        _isRainbow = false;
        _boostTimeRemaining = 0;
        _boostTimer?.cancel();
        _mood = 'normal';
        notifyListeners();
        _saveState();
      }
    });
  }

  // Add steps and gain energy (+0.02 energy per step, i.e. 100 steps = 2.0 energy)
  void addSteps(int count) {
    _stepsToday += count;
    _energy = (_energy + count * 0.02).clamp(0.0, 100.0);
    notifyListeners();
    _saveState();
  }

  // Add sleep duration and convert to energy (+10.0 energy per hour)
  void addSleepEnergy(double hours) {
    _energy = (_energy + hours * 10.0).clamp(0.0, 100.0);
    notifyListeners();
    _saveState();
  }

  // Add charging duration and convert to energy (+0.5 energy per minute)
  void addChargingEnergySeconds(double seconds) {
    if (seconds <= 0.0) return;
    final next = (_energy + seconds * (0.5 / 60.0)).clamp(0.0, 100.0);
    if ((next - _energy).abs() < 0.0001) return;
    _energy = next;
    notifyListeners();
    _saveState();
  }

  void _startPoseTimer() {
    _poseTimer?.cancel();
    _poseTimer = Timer.periodic(const Duration(seconds: 7), (timer) {
      if (_isDragging) return; // Don't morph while user is playing with it

      // Randomly choose a pose / shape
      final poses = [
        'default',
        'square',
        'round',
        'stretch',
        'dent',
        'star',
        'heart',
        'triangle',
      ];
      final nextPose = poses[Random().nextInt(poses.length)];

      _shape = nextPose;

      // Select an expressive mood matching the pose
      if (nextPose == 'stretch' || nextPose == 'heart') {
        _mood = 'happy';
      } else if (nextPose == 'dent' || nextPose == 'star') {
        _mood = 'surprised';
      } else if (nextPose == 'square' || nextPose == 'triangle') {
        _mood = 'angry';
      } else {
        _mood = 'normal';
      }

      notifyListeners();

      // Reset back to default trapezoid and normal mood after 3.2 seconds
      _poseResetTimer?.cancel();
      _poseResetTimer = Timer(const Duration(milliseconds: 3200), () {
        if (!_isDragging) {
          _shape = 'default';
          _mood = 'normal';
          notifyListeners();
        }
      });
    });
  }

  @override
  void dispose() {
    _poseTimer?.cancel();
    _poseResetTimer?.cancel();
    _boostTimer?.cancel();
    _moodResetTimer?.cancel();
    super.dispose();
  }
}
