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
  static const String _keyStepsDate = 'puni_steps_date';
  static const String _keySleepMinutes = 'puni_sleep_minutes';
  static const String _keySleepDate = 'puni_sleep_date';
  static const String _keyGrowth = 'puni_growth';
  static const String _keyMorningPoints = 'puni_morning_points';
  static const String _keyNightPoints = 'puni_night_points';
  static const String _keyFeedPoints = 'puni_feed_points';
  static const String _keyAdPoints = 'puni_ad_points';
  static const String _keyEnergy = 'puni_energy';
  static const String _keyFeedCount = 'puni_feed_count';
  static const String _keyFeedCountDate = 'puni_feed_count_date';
  static const String _keyAdLevelUpCount = 'puni_ad_levelup_count';
  static const String _keyAdLevelUpCountDate = 'puni_ad_levelup_count_date';

  // Properties
  int _level = 1;
  String _shape = 'default';
  String _mood = 'normal';
  int _stepsToday = 0;
  String _stepsDate = '';
  int _sleepMinutes = 0; // Yesterday's sleep duration in minutes
  String _sleepDate = ''; // Date of last sleep sync (YYYY-MM-DD)
  double _growthToday = 0.0; // 0.0 to 1.0 (level progress)
  double _energy = 100.0; // Puni Energy (0.0 to 100.0)

  // Care interaction stats (growth points contributed by activity)
  double _morningPoints = 0.0;
  double _nightPoints = 0.0;
  double _feedPoints = 0.0;
  double _adPoints = 0.0;
  int _feedCountToday = 0;
  String _feedCountDate = '';
  int _adLevelUpCountToday = 0;
  String _adLevelUpCountDate = '';

  static const int maxFeedPerDay = 15;
  static const int maxAdLevelUpPerDay = 8;

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
  int get sleepMinutes => _sleepMinutes;
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
  int get feedCountToday => _feedCountToday;
  int get adLevelUpCountToday => _adLevelUpCountToday;
  int get feedRemainingToday => max(0, maxFeedPerDay - _feedCountToday);
  int get adLevelUpRemainingToday =>
      max(0, maxAdLevelUpPerDay - _adLevelUpCountToday);

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
  // Lv5: 少しぷに (18.0%)
  // Lv15: ゼリー (40.0%)
  // Lv30: 水風船 (62.0%)
  // Lv50: 液体系 (78.0%)
  // Lv75: とろとろ (88.0%)
  // Lv100: ほぼスライム (95.0%)
  double getSoftnessForLevel(int lvl) {
    if (lvl <= 1) return 1.0;
    if (lvl <= 5) {
      // Interpolate 1.0 -> 18.0
      return 1.0 + (lvl - 1) / 4.0 * (18.0 - 1.0);
    }
    if (lvl <= 15) {
      // Interpolate 18.0 -> 40.0
      return 18.0 + (lvl - 5) / 10.0 * (40.0 - 18.0);
    }
    if (lvl <= 30) {
      // Interpolate 40.0 -> 62.0
      return 40.0 + (lvl - 15) / 15.0 * (62.0 - 40.0);
    }
    if (lvl <= 50) {
      // Interpolate 62.0 -> 78.0
      return 62.0 + (lvl - 30) / 20.0 * (78.0 - 62.0);
    }
    if (lvl <= 75) {
      // Interpolate 78.0 -> 88.0
      return 78.0 + (lvl - 50) / 25.0 * (88.0 - 78.0);
    }
    if (lvl <= 100) {
      // Interpolate 88.0 -> 95.0
      return 88.0 + (lvl - 75) / 25.0 * (95.0 - 88.0);
    }
    return 95.0; // Cap at 95.0% softness
  }

  // Label text matching level state
  String get softnessLabel {
    if (_level < 5) return 'ほぼ石';
    if (_level < 15) return 'ぷについてきた';
    if (_level < 30) return 'ゼリーレベル';
    if (_level < 50) return '水風船レベル';
    if (_level < 75) return '液体に近づいてきた';
    if (_level < 100) return 'もうぶにょぶにょ';
    return 'Top of PUNI（限界点）';
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
      _stepsDate = prefs.getString(_keyStepsDate) ?? '';
      _sleepMinutes = prefs.getInt(_keySleepMinutes) ?? 0;
      _sleepDate = prefs.getString(_keySleepDate) ?? '';
      _growthToday = prefs.getDouble(_keyGrowth) ?? 0.0;
      _energy = prefs.getDouble(_keyEnergy) ?? 100.0;
      _morningPoints = prefs.getDouble(_keyMorningPoints) ?? 0.0;
      _nightPoints = prefs.getDouble(_keyNightPoints) ?? 0.0;
      _feedPoints = prefs.getDouble(_keyFeedPoints) ?? 0.0;
      _adPoints = prefs.getDouble(_keyAdPoints) ?? 0.0;
      _feedCountToday = prefs.getInt(_keyFeedCount) ?? 0;
      _feedCountDate = prefs.getString(_keyFeedCountDate) ?? '';
      _adLevelUpCountToday = prefs.getInt(_keyAdLevelUpCount) ?? 0;
      _adLevelUpCountDate = prefs.getString(_keyAdLevelUpCountDate) ?? '';
      _resetStepsIfDayChanged();
      _resetActionCountsIfDayChanged();
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
      await prefs.setString(_keyStepsDate, _stepsDate);
      await prefs.setInt(_keySleepMinutes, _sleepMinutes);
      await prefs.setString(_keySleepDate, _sleepDate);
      await prefs.setDouble(_keyGrowth, _growthToday);
      await prefs.setDouble(_keyEnergy, _energy);
      await prefs.setDouble(_keyMorningPoints, _morningPoints);
      await prefs.setDouble(_keyNightPoints, _nightPoints);
      await prefs.setDouble(_keyFeedPoints, _feedPoints);
      await prefs.setDouble(_keyAdPoints, _adPoints);
      await prefs.setInt(_keyFeedCount, _feedCountToday);
      await prefs.setString(_keyFeedCountDate, _feedCountDate);
      await prefs.setInt(_keyAdLevelUpCount, _adLevelUpCountToday);
      await prefs.setString(_keyAdLevelUpCountDate, _adLevelUpCountDate);
    } catch (e) {
      debugPrint("Error saving SharedPreferences: $e");
    }
  }

  String _currentDateKey() {
    final now = DateTime.now();
    final month = now.month.toString().padLeft(2, '0');
    final day = now.day.toString().padLeft(2, '0');
    return '${now.year}-$month-$day';
  }

  void _resetStepsIfDayChanged() {
    final today = _currentDateKey();
    if (_stepsDate == today) return;
    _stepsDate = today;
    _stepsToday = 0;
  }

  bool _resetActionCountsIfDayChanged() {
    final today = _currentDateKey();
    var changed = false;

    if (_feedCountDate != today) {
      _feedCountDate = today;
      _feedCountToday = 0;
      changed = true;
    }

    if (_adLevelUpCountDate != today) {
      _adLevelUpCountDate = today;
      _adLevelUpCountToday = 0;
      changed = true;
    }

    return changed;
  }

  void refreshDailyActionLimits() {
    if (!_resetActionCountsIfDayChanged()) return;
    notifyListeners();
    _saveState();
  }

  bool consumeFeedAction() {
    _resetActionCountsIfDayChanged();
    if (_feedCountToday >= maxFeedPerDay) {
      return false;
    }

    _feedCountToday++;
    notifyListeners();
    _saveState();
    return true;
  }

  bool consumeAdLevelUpAction() {
    _resetActionCountsIfDayChanged();
    if (_adLevelUpCountToday >= maxAdLevelUpPerDay) {
      return false;
    }

    _adLevelUpCountToday++;
    notifyListeners();
    _saveState();
    return true;
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
    } else if (source == 'petting') {
      // Petting always grows the pink channel.
      _morningPoints += actualAmount;
    } else if (source == 'fling') {
      // Throwing/flicking always grows the purple channel.
      _nightPoints += actualAmount;
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
    _resetStepsIfDayChanged();
    _stepsToday += count;
    _energy = (_energy + count * 0.02).clamp(0.0, 100.0);
    notifyListeners();
    _saveState();
  }

  int syncTodaySteps(int totalSteps) {
    _resetStepsIfDayChanged();
    final safeTotal = max(0, totalSteps);
    final gainedSteps = max(0, safeTotal - _stepsToday);
    _stepsToday = safeTotal;
    if (gainedSteps > 0) {
      _energy = (_energy + gainedSteps * 0.02).clamp(0.0, 100.0);
    }
    notifyListeners();
    _saveState();
    return gainedSteps;
  }

  /// Sleep sync is currently record-only. No energy conversion is applied.
  /// Returns sync status and always 0 energy gain.
  ({bool synced, double energyGained}) syncYesterdaySleep(int minutes) {
    final today = _currentDateKey();

    // Only allow one sync per day
    if (_sleepDate == today) {
      debugPrint('Sleep already synced today');
      return (synced: false, energyGained: 0.0);
    }

    _sleepMinutes = max(0, minutes);
    _sleepDate = today;

    notifyListeners();
    _saveState();
    return (synced: true, energyGained: 0.0);
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
