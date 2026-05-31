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
  static const String _keyExp = 'puni_exp';
  static const String _keyMorningPoints = 'puni_morning_points';
  static const String _keyNightPoints = 'puni_night_points';
  static const String _keyFeedPoints = 'puni_feed_points';
  static const String _keyAdPoints = 'puni_ad_points';
  static const String _keyEnergy = 'puni_energy';
  static const String _keyFeedCount = 'puni_feed_count';
  static const String _keyFeedCountDate = 'puni_feed_count_date';
  static const String _keyAdLevelUpCount = 'puni_ad_levelup_count';
  static const String _keyAdLevelUpCountDate = 'puni_ad_levelup_count_date';
  static const String _keyIntimacy = 'puni_intimacy';
  static const String _keyColorLocked = 'puni_color_locked';
  static const String _keyLockedColorR = 'puni_locked_color_r';
  static const String _keyLockedColorG = 'puni_locked_color_g';
  static const String _keyLockedColorB = 'puni_locked_color_b';
  static const String _keyPinchPoints = 'puni_pinch_points';
  static const String _keyBalloonPoints = 'puni_balloon_points';
  static const String _keyOrangePoints = 'puni_orange_points';
  static const String _keyBluePoints = 'puni_blue_points';
  static const String _keyWhitePoints = 'puni_white_points';
  static const String _keyBlackPoints = 'puni_black_points';
  static const String _keyPuniCoins = 'puni_coins';
  static const String _keyPlayerName = 'puni_player_name';
  static const String _keyPuniName = 'puni_puni_name';

  // Properties
  int _level = 1;
  String _shape = 'default';
  String _mood = 'normal';
  int _stepsToday = 0;
  String _stepsDate = '';
  int _sleepMinutes = 0; // Yesterday's sleep duration in minutes
  String _sleepDate = ''; // Date of last sleep sync (YYYY-MM-DD)
  double _exp = 0.0; // Current experience points in the current level
  double _growthToday = 0.0; // Legacy compatibility (0.0 to 1.0)
  double _energy = 100.0; // Puni Energy (0.0 to 100.0)
  double _intimacy = 0.0; // Puni Intimacy (0.0 to 100.0)
  bool _isColorLocked = false;
  Color? _lockedColor;
  int _puniCoins = 0;
  String _playerName = 'ぷにマスター';
  String _puniName = 'ぷにちゃん';

  // Care interaction stats (growth points contributed by activity)
  double _morningPoints = 0.0;
  double _nightPoints = 0.0;
  double _feedPoints = 0.0;
  double _adPoints = 0.0;
  double _pinchPoints = 0.0;
  double _balloonPoints = 0.0;
  double _orangePoints = 0.0;
  double _bluePoints = 0.0;
  double _whitePoints = 0.0;
  double _blackPoints = 0.0;
  int _feedCountToday = 0;
  String _feedCountDate = '';
  int _adLevelUpCountToday = 0;
  String _adLevelUpCountDate = '';

  static const int maxFeedPerDay = 15;
  static const int maxAdLevelUpPerDay = 5;

  // Boost States (Rainbow mode kept internally as fallback or for visual effects)
  bool _isRainbow = false;
  int _boostTimeRemaining = 0;
  Timer? _boostTimer;

  // Active touch details
  Offset? _touchPosition;
  bool _isDragging = false;
  bool _isPetting = false;
  bool _isPinching = false;
  bool _isInflating = false;

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
  double get exp => _exp;
  int get requiredExp => getRequiredExpForLevel(_level);
  double get growthToday {
    final req = requiredExp;
    if (req <= 0) return 0.0;
    return (_exp / req).clamp(0.0, 1.0);
  }

  int getRequiredExpForLevel(int lvl) {
    if (lvl <= 1) return 30; // Lv1→Lv2: 30経験値
    if (lvl <= 5) return 50; // Lv2-5: 50経験値
    if (lvl <= 10) return 100; // Lv6-10: 100経験値
    if (lvl <= 20) return 200; // Lv11-20: 200経験値
    if (lvl <= 30) return 400; // Lv21-30: 400経験値
    if (lvl <= 50) return 800; // Lv31-50: 800経験値
    if (lvl <= 75) return 1300; // Lv51-75: 1300経験値
    return 2000; // Lv76+: 2000経験値
  }

  double get energy => _energy;
  bool get isRainbow => _isRainbow;
  int get boostTimeRemaining => _boostTimeRemaining;
  Offset? get touchPosition => _touchPosition;
  bool get isDragging => _isDragging;
  bool get isPetting => _isPetting;
  bool get isPinching => _isPinching;
  bool get isInflating => _isInflating;
  double get morningPoints => _morningPoints;
  double get nightPoints => _nightPoints;
  double get feedPoints => _feedPoints;
  double get adPoints => _adPoints;
  double get pinchPoints => _pinchPoints;
  double get balloonPoints => _balloonPoints;
  double get orangePoints => _orangePoints;
  double get bluePoints => _bluePoints;
  double get whitePoints => _whitePoints;
  double get blackPoints => _blackPoints;
  int get feedCountToday => _feedCountToday;
  int get adLevelUpCountToday => _adLevelUpCountToday;
  int get feedRemainingToday => max(0, maxFeedPerDay - _feedCountToday);
  int get adLevelUpRemainingToday =>
      max(0, maxAdLevelUpPerDay - _adLevelUpCountToday);
  double get intimacy => _intimacy;
  bool get isColorLocked => _isColorLocked;
  Color? get lockedColor => _lockedColor;
  int get puniCoins => _puniCoins;
  String get playerName => _playerName;
  String get puniName => _puniName;

  void addCoins(int amount) {
    _puniCoins += amount;
    notifyListeners();
    _saveState();
  }

  bool spendCoins(int amount) {
    if (_puniCoins < amount) return false;
    _puniCoins -= amount;
    notifyListeners();
    _saveState();
    return true;
  }

  void setPlayerName(String name) {
    _playerName = name;
    notifyListeners();
    _saveState();
  }

  void setPuniName(String name) {
    _puniName = name;
    notifyListeners();
    _saveState();
  }

  void setMood(String mood) {
    _mood = mood;
    notifyListeners();
  }

  // Dynamic Mixed Color based on training activity distribution (starting at Grey, transitioning to vibrant)
  Color get creatureColor {
    if (_isColorLocked && _lockedColor != null) {
      return _lockedColor!;
    }
    // Target colors for care style
    const morningColor = Color(0xFFFF8DA1); // Pink (桃色)
    const nightColor = Color(0xFFB388FF); // Purple (紫色)
    const adColor = Color(0xFF80D8FF); // Sky Blue (水色)
    const feedColor = Color(0xFFFFD740); // Yellow (黄色)
    const pinchColor = Color(0xFFFF2D55); // Red (赤色)
    const balloonColor = Color(0xFF2ECC71); // Green (緑色)
    const orangeColor = Color(0xFFFF9F0A); // Orange (オレンジ色)
    const blueColor = Color(0xFF007AFF); // Blue (青色)
    const whiteColor = Color(0xFFFFFFFF); // White (白色)

    double total =
        _morningPoints +
        _nightPoints +
        _adPoints +
        _feedPoints +
        _pinchPoints +
        _balloonPoints +
        _orangePoints +
        _bluePoints +
        _whitePoints;

    // Balanced defaults if total is 0 (e.g. at start)
    double pMorning = total == 0 ? 1 / 9 : _morningPoints / total;
    double pNight = total == 0 ? 1 / 9 : _nightPoints / total;
    double pAd = total == 0 ? 1 / 9 : _adPoints / total;
    double pFeed = total == 0 ? 1 / 9 : _feedPoints / total;
    double pPinch = total == 0 ? 1 / 9 : _pinchPoints / total;
    double pBalloon = total == 0 ? 1 / 9 : _balloonPoints / total;
    double pOrange = total == 0 ? 1 / 9 : _orangePoints / total;
    double pBlue = total == 0 ? 1 / 9 : _bluePoints / total;
    double pWhite = total == 0 ? 1 / 9 : _whitePoints / total;

    // Blend the RGB values
    double r =
        morningColor.red * pMorning +
        nightColor.red * pNight +
        adColor.red * pAd +
        feedColor.red * pFeed +
        pinchColor.red * pPinch +
        balloonColor.red * pBalloon +
        orangeColor.red * pOrange +
        blueColor.red * pBlue +
        whiteColor.red * pWhite;
    double g =
        morningColor.green * pMorning +
        nightColor.green * pNight +
        adColor.green * pAd +
        feedColor.green * pFeed +
        pinchColor.green * pPinch +
        balloonColor.green * pBalloon +
        orangeColor.green * pOrange +
        blueColor.green * pBlue +
        whiteColor.green * pWhite;
    double b =
        morningColor.blue * pMorning +
        nightColor.blue * pNight +
        adColor.blue * pAd +
        feedColor.blue * pFeed +
        pinchColor.blue * pPinch +
        balloonColor.blue * pBalloon +
        orangeColor.blue * pOrange +
        blueColor.blue * pBlue +
        whiteColor.blue * pWhite;

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
      _exp = (prefs.getDouble(_keyExp) ?? (prefs.getInt(_keyExp) ?? 0))
          .toDouble();
      _growthToday = prefs.getDouble(_keyGrowth) ?? 0.0;
      _energy = prefs.getDouble(_keyEnergy) ?? 100.0;
      _morningPoints = prefs.getDouble(_keyMorningPoints) ?? 0.0;
      _nightPoints = prefs.getDouble(_keyNightPoints) ?? 0.0;
      _feedPoints = prefs.getDouble(_keyFeedPoints) ?? 0.0;
      _adPoints = prefs.getDouble(_keyAdPoints) ?? 0.0;
      _pinchPoints = prefs.getDouble(_keyPinchPoints) ?? 0.0;
      _balloonPoints = prefs.getDouble(_keyBalloonPoints) ?? 0.0;
      _orangePoints = prefs.getDouble(_keyOrangePoints) ?? 0.0;
      _bluePoints = prefs.getDouble(_keyBluePoints) ?? 0.0;
      _whitePoints = prefs.getDouble(_keyWhitePoints) ?? 0.0;
      _blackPoints = prefs.getDouble(_keyBlackPoints) ?? 0.0;
      _feedCountToday = prefs.getInt(_keyFeedCount) ?? 0;
      _feedCountDate = prefs.getString(_keyFeedCountDate) ?? '';
      _adLevelUpCountToday = prefs.getInt(_keyAdLevelUpCount) ?? 0;
      _adLevelUpCountDate = prefs.getString(_keyAdLevelUpCountDate) ?? '';
      _intimacy = prefs.getDouble(_keyIntimacy) ?? 0.0;
      _isColorLocked = prefs.getBool(_keyColorLocked) ?? false;
      _puniCoins = prefs.getInt(_keyPuniCoins) ?? 0;
      _playerName = prefs.getString(_keyPlayerName) ?? 'ぷにマスター';
      _puniName = prefs.getString(_keyPuniName) ?? 'ぷにちゃん';
      final r = prefs.getInt(_keyLockedColorR);
      final g = prefs.getInt(_keyLockedColorG);
      final b = prefs.getInt(_keyLockedColorB);
      if (r != null && g != null && b != null) {
        _lockedColor = Color.fromARGB(255, r, g, b);
      }
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
      await prefs.setDouble(_keyExp, _exp);
      await prefs.setDouble(_keyGrowth, _growthToday);
      await prefs.setDouble(_keyEnergy, _energy);
      await prefs.setDouble(_keyMorningPoints, _morningPoints);
      await prefs.setDouble(_keyNightPoints, _nightPoints);
      await prefs.setDouble(_keyFeedPoints, _feedPoints);
      await prefs.setDouble(_keyAdPoints, _adPoints);
      await prefs.setDouble(_keyPinchPoints, _pinchPoints);
      await prefs.setDouble(_keyBalloonPoints, _balloonPoints);
      await prefs.setDouble(_keyOrangePoints, _orangePoints);
      await prefs.setDouble(_keyBluePoints, _bluePoints);
      await prefs.setDouble(_keyWhitePoints, _whitePoints);
      await prefs.setDouble(_keyBlackPoints, _blackPoints);
      await prefs.setInt(_keyFeedCount, _feedCountToday);
      await prefs.setString(_keyFeedCountDate, _feedCountDate);
      await prefs.setInt(_keyAdLevelUpCount, _adLevelUpCountToday);
      await prefs.setString(_keyAdLevelUpCountDate, _adLevelUpCountDate);
      await prefs.setDouble(_keyIntimacy, _intimacy);
      await prefs.setBool(_keyColorLocked, _isColorLocked);
      await prefs.setInt(_keyPuniCoins, _puniCoins);
      await prefs.setString(_keyPlayerName, _playerName);
      await prefs.setString(_keyPuniName, _puniName);
      if (_lockedColor != null) {
        await prefs.setInt(_keyLockedColorR, _lockedColor!.red);
        await prefs.setInt(_keyLockedColorG, _lockedColor!.green);
        await prefs.setInt(_keyLockedColorB, _lockedColor!.blue);
      } else {
        await prefs.remove(_keyLockedColorR);
        await prefs.remove(_keyLockedColorG);
        await prefs.remove(_keyLockedColorB);
      }
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

  // Debug intimacy selector
  void debugSetIntimacy(double val) {
    _intimacy = val.clamp(0.0, 100.0);
    _saveState();
    notifyListeners();
  }

  // Set interaction state
  void setInteraction({
    required bool isDragging,
    required bool isPetting,
    bool isPinching = false,
    bool isInflating = false,
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
    } else if (isPinching && !_isPinching) {
      _mood = 'happy'; // Blushing/happy when pinched
    } else if (isInflating && !_isInflating) {
      _mood = 'happy'; // Happy when inflating
    } else if (!isDragging &&
        !isPetting &&
        !isPinching &&
        !isInflating &&
        (_isDragging || _isPetting || _isPinching || _isInflating)) {
      _mood = 'normal'; // Released -> Normal
    }

    _isDragging = isDragging;
    _isPetting = isPetting;
    _isPinching = isPinching;
    _isInflating = isInflating;
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
  void addGrowth(
    double amount, {
    required String source,
    String foodType = 'default',
  }) {
    bool requiresEnergy =
        (source == 'petting' ||
        source == 'fling' ||
        source == 'pinch' ||
        source == 'balloon');

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

    // Apply color channel points ONLY via food source and when NOT color-locked
    if (source == 'feed' && !_isColorLocked) {
      const double foodColorWeight = 10.0; // Flat weight per color feed
      if (foodType == 'red') {
        _pinchPoints += foodColorWeight;
      } else if (foodType == 'green') {
        _balloonPoints += foodColorWeight;
      } else if (foodType == 'yellow') {
        _feedPoints += foodColorWeight;
      } else if (foodType == 'pink') {
        _morningPoints += foodColorWeight;
      } else if (foodType == 'purple') {
        _nightPoints += foodColorWeight;
      } else if (foodType == 'cyan') {
        _adPoints += foodColorWeight;
      } else if (foodType == 'orange') {
        _orangePoints += foodColorWeight;
      } else if (foodType == 'blue') {
        _bluePoints += foodColorWeight;
      } else if (foodType == 'white') {
        _whitePoints += foodColorWeight;
      } else if (foodType == 'black') {
        _blackPoints += foodColorWeight;
      }
    }

    // Add experience points (scaled for consistency)
    // 0.002 growth = 0.2 exp (preserves precision with double)
    double expGain = actualAmount * 100.0;
    _exp += expGain;

    // Check for level up
    while (_exp >= requiredExp) {
      _levelUp();
    }
    notifyListeners();
    _saveState();
  }

  void _levelUp() {
    _level++;
    _exp -= requiredExp
        .toDouble(); // Reduce exp by the required amount for the old level
    _growthToday = max(0.0, _growthToday - 1.0); // Legacy compatibility
    triggerMood('levelup', duration: const Duration(milliseconds: 100));
    notifyListeners();
    _saveState();
  }

  // Watch ad to get coins instead of level up
  void rewardAdCoins() {
    _puniCoins += 50;
    notifyListeners();
    _saveState();
  }

  void addIntimacy(double amount) {
    _intimacy = (_intimacy + amount).clamp(0.0, 100.0);
    notifyListeners();
    _saveState();
  }

  void toggleColorLock() {
    if (_isColorLocked) {
      _isColorLocked = false;
      _lockedColor = null;
    } else {
      _lockedColor = creatureColor;
      _isColorLocked = true;
    }
    notifyListeners();
    _saveState();
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
