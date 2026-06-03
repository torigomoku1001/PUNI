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
  int _sleepMinutes = 0;
  String _sleepDate = '';
  double _exp = 0.0;
  double _growthToday = 0.0;
  double _energy = 100.0;
  double _intimacy = 0.0;
  bool _isColorLocked = false;
  Color? _lockedColor;
  int _puniCoins = 0;
  String _playerName = 'ぷにマスター';
  String _puniName = 'ぷにちゃん';

  // ーーー 色の成分管理システム ーーー
  final Map<String, double> _colorComponents = {
    'red': 0.0,
    'orange': 0.0,
    'yellow': 0.0,
    'green': 0.0,
    'cyan': 0.0,
    'blue': 0.0,
    'purple': 0.0,
    'pink': 0.0,
    'default': 0.0,
  };

  double _transparency = 0.0;
  double _saturationModifier = 1.0;

  // Care interaction stats
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
  double get softness => getSoftnessForLevel(_level); // ➔ レインボーを撤廃して一本化！
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

      
  // ★5レベルごとに1000ずつ増える階段方式システム
  int getRequiredExpForLevel(int lvl) {
    if (lvl <= 1) return 1000;
    if (lvl >= 100) return 20000;

    int step = (lvl - 1) ~/ 5;
    int cleanExp = 1000 + (step * 1000);

    return cleanExp;
  }

  double get energy => _energy;
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

  // 初の1色投入でシースルーに変わるカラーレンダリング
  Color get creatureColor {
    if (_isColorLocked && _lockedColor != null) {
      return _lockedColor!;
    }

    double totalAmount = 0.0;
    _colorComponents.forEach((_, amount) => totalAmount += amount);

    if (totalAmount == 0.0) {
      return const Color(0xFFD2D2D8);
    }

    double rSum = 0.0;
    double gSum = 0.0;
    double bSum = 0.0;

    _colorComponents.forEach((color, amount) {
      if (amount <= 0) return;
      if (color == 'default') return;

      switch (color) {
        case 'red':
          rSum += 255 * amount;
          gSum += 45 * amount;
          bSum += 85 * amount;
          break;
        case 'orange':
          rSum += 255 * amount;
          gSum += 159 * amount;
          bSum += 10 * amount;
          break;
        case 'yellow':
          rSum += 255 * amount;
          gSum += 204 * amount;
          bSum += 0 * amount;
          break;
        case 'green':
          rSum += 46 * amount;
          gSum += 204 * amount;
          bSum += 113 * amount;
          break;
        case 'cyan':
          rSum += 90 * amount;
          gSum += 200 * amount;
          bSum += 250 * amount;
          break;
        case 'blue':
          rSum += 0 * amount;
          gSum += 122 * amount;
          bSum += 255 * amount;
          break;
        case 'purple':
          rSum += 175 * amount;
          gSum += 82 * amount;
          bSum += 222 * amount;
          break;
        case 'pink':
          rSum += 255 * amount;
          gSum += 45 * amount;
          bSum += 133 * amount;
          break;
      }
    });

    if (rSum == 0.0 && gSum == 0.0 && bSum == 0.0) {
      rSum = 210;
      gSum = 210;
      bSum = 216;
      totalAmount = 1.0;
    }

    int r = (rSum / totalAmount).round().clamp(0, 255);
    int g = (gSum / totalAmount).round().clamp(0, 255);
    int b = (bSum / totalAmount).round().clamp(0, 255);

    HSLColor hsl = HSLColor.fromColor(Color.fromARGB(255, r, g, b));

    // 混色時にくすむ（グレーに近づく）のを防ぐため、彩度を少しブーストして鮮やかにする
    double boostedSaturation = (hsl.saturation * 1.5).clamp(0.0, 1.0);

    // 食べたご飯の「総量」ベースで彩度を決定する（混色時も鮮やかさをキープ）
    // 最初の1個（約0.067）でも最低30%の彩度を持たせてパステル調で綺麗に見せる
    double foodLevel = totalAmount.clamp(0.0, 1.0);
    double vibrancyCurve = 0.3 + 0.7 * foodLevel;

    double dynamicSaturation = boostedSaturation * vibrancyCurve * _saturationModifier;
    
    // ★茶色っぽく濁るのを防ぐため、明度（Lightness）を高く保ち「綺麗なパステル〜ビビッド」にする
    // 最低でも75%の明度を確保し、暗くならないようにする
    double displayLightness = max(hsl.lightness, 0.75);

    return HSLColor.fromAHSL(
      _transparency.clamp(0.0, 1.0),
      hsl.hue,
      dynamicSaturation.clamp(0.0, 1.0),
      displayLightness.clamp(0.0, 1.0),
    ).toColor();
  }

  double getSoftnessForLevel(int lvl) {
    if (lvl <= 1) return 1.0;
    if (lvl <= 5) return 1.0 + (lvl - 1) / 4.0 * (18.0 - 1.0);
    if (lvl <= 15) return 18.0 + (lvl - 5) / 10.0 * (40.0 - 18.0);
    if (lvl <= 30) return 40.0 + (lvl - 15) / 15.0 * (62.0 - 40.0);
    if (lvl <= 50) return 62.0 + (lvl - 30) / 20.0 * (78.0 - 62.0);
    if (lvl <= 75) return 78.0 + (lvl - 50) / 25.0 * (88.0 - 78.0);
    if (lvl <= 100) return 88.0 + (lvl - 75) / 25.0 * (95.0 - 88.0);
    return 95.0;
  }

  String get softnessLabel {
    if (_level < 5) return 'ほぼ石';
    if (_level < 15) return 'ぷについてきた';
    if (_level < 30) return 'ゼリーレベル';
    if (_level < 50) return '水風sensorレベル';
    if (_level < 75) return '液体に近づいてきた';
    if (_level < 100) return 'もうぶにょぶにょ';
    return 'Top of PUNI（限界点）';
  }

  CreatureState() {
    _loadState();
    _startPoseTimer();
  }

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

      for (final key in _colorComponents.keys.toList()) {
        final val = prefs.getDouble('puni_color_component_$key');
        if (val != null) {
          _colorComponents[key] = val;
        }
      }
      _transparency = prefs.getDouble('puni_transparency') ?? 0.0;
      _saturationModifier = prefs.getDouble('puni_saturation_mod') ?? 1.0;
      _resetStepsIfDayChanged();
      _resetActionCountsIfDayChanged();
      notifyListeners();
    } catch (e) {
      debugPrint("Error loading SharedPreferences: $e");
    }
  }

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

      for (final entry in _colorComponents.entries) {
        await prefs.setDouble('puni_color_component_${entry.key}', entry.value);
      }
      await prefs.setDouble('puni_transparency', _transparency);
      await prefs.setDouble('puni_saturation_mod', _saturationModifier);
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

  void debugSetLevel(int lv) {
    _level = lv;
    _saveState();
    notifyListeners();
  }

  void debugSetIntimacy(double val) {
    _intimacy = max(0.0, val);
    _saveState();
    notifyListeners();
  }

  void setInteraction({
    required bool isDragging,
    required bool isPetting,
    bool isPinching = false,
    bool isInflating = false,
    Offset? touchPosition,
  }) {
    if (isDragging && !_isDragging) {
      _mood = (_energy <= 0.0) ? 'sad' : 'happy';
    } else if (isPetting && !_isPetting) {
      _mood = (_energy <= 0.0) ? 'angry' : 'happy';
    } else if (isPinching && !_isPinching) {
      _mood = 'happy';
    } else if (isInflating && !_isInflating) {
      _mood = 'happy';
    } else if (!isDragging &&
        !isPetting &&
        !isPinching &&
        !isInflating &&
        (_isDragging || _isPetting || _isPinching || _isInflating)) {
      _mood = 'normal';
    }

    _isDragging = isDragging;
    _isPetting = isPetting;
    _isPinching = isPinching;
    _isInflating = isInflating;
    _touchPosition = touchPosition;
    notifyListeners();
  }

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

  // ★新仕様お世話システム（レインボー処理を完全排除して軽量化）
  void addGrowth(
    double amount, {
    required String source,
    String foodType = 'default',
    double? customIntimacy,
    double? customExp,
  }) {
    double energyCost = 0.0;
    double intimacyGain = 0.0;
    double expGain = 0.0;

    switch (source) {
      case 'petting':
        energyCost = 0.2;
        intimacyGain = 0.05;
        expGain = 10.0;
        break;
      case 'pinch':
        energyCost = 1.0;
        intimacyGain = 0.25;
        expGain = 50.0;
        break;
      case 'balloon':
        energyCost = 1.0;
        intimacyGain = 0.25;
        expGain = 50.0;
        break;
      case 'feed':
        energyCost = 0.0;
        intimacyGain = 1.0;
        expGain = 200.0;
        break;
      case 'fling':
        energyCost = 2.0;
        intimacyGain = (customIntimacy ?? 0.75);
        expGain = (customExp ?? 100.0);
        break;
    }

    // 画面表示（四捨五入）と一致するように丸めた値で判定する
    double displayEnergy = double.parse(_energy.toStringAsFixed(1));
    bool hasEnergy = displayEnergy >= energyCost;

    // エネルギーが足りない場合、親密度の上がり幅を1/5にする
    if (!hasEnergy && source != 'feed') {
      intimacyGain /= 5.0;
    }

    // 1. 親密度は無条件で加算
    if (intimacyGain > 0.0) {
      _intimacy = min(999999.0, _intimacy + intimacyGain);
    }

    if (hasEnergy) {
      // 2. エネルギーがあれば消費する
      if (energyCost > 0.0) {
        _energy = max(0.0, _energy - energyCost);
      }
      
      // 3. 経験値加算はエネルギーがある場合のみ実行
      _exp += expGain;
    }

    // 4. 色の変化処理
    if (source == 'feed' && !_isColorLocked) {
      if (foodType != 'default') {
        if (_transparency < 1.0) {
          _transparency = min(1.0, _transparency + 0.334);
        }
        _colorComponents.forEach((key, value) {
          if (key == foodType) {
            _colorComponents[key] = min(1.0, value + 0.067);
          } else {
            _colorComponents[key] = max(0.0, value - 0.01);
          }
        });
      }
    }

    // 5. レベルアップ判定
    while (_exp >= requiredExp) {
      _levelUp();
    }

    notifyListeners();
    _saveState();
  }

  void applyMedicine(String type) {
    if (type == 'bleach') {
      _transparency = 0.0;
      _colorComponents.updateAll((key, value) => 0.0);
      _saturationModifier = 1.0;
    } else if (type == 'desaturate') {
      // グレーにくすませるのではなく、絵の具を水で薄めるように透明度と色成分全体を減らす
      _transparency = max(0.0, _transparency - 0.2);
      _colorComponents.updateAll((key, value) => max(0.0, value * 0.6));
    }
    notifyListeners();
    _saveState();
  }

  void _levelUp() {
    final requiredBeforeLevelUp = requiredExp.toDouble();
    _exp = max(0.0, _exp - requiredBeforeLevelUp);
    _level++;
    _growthToday = max(0.0, _growthToday - 1.0);
    triggerMood('levelup', duration: const Duration(milliseconds: 100));
    notifyListeners();
    _saveState();
  }

  void rewardAdCoins() {
    _puniCoins += 25;
    notifyListeners();
    _saveState();
  }

  void toggleColorLock() {
    if (_intimacy < 50.0) return;

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

  void setShape(String newShape) {
    _shape = newShape;
    triggerMood('surprised', duration: const Duration(seconds: 2));
    notifyListeners();
    _saveState();
  }

  void addSteps(int count) {
    _resetStepsIfDayChanged();
    _stepsToday += count;
    _energy = (_energy + count * 0.02).clamp(
      0.0,
      100.0,
    );
    notifyListeners();
    _saveState();
  }

  int syncTodaySteps(int totalSteps) {
    _resetStepsIfDayChanged();
    final safeTotal = max(0, totalSteps);
    final gainedSteps = max(0, safeTotal - _stepsToday);
    _stepsToday = safeTotal;
    if (gainedSteps > 0) {
      _energy = (_energy + gainedSteps * 0.02).clamp(
        0.0,
        100.0,
      );
    }
    notifyListeners();
    _saveState();
    return gainedSteps;
  }

  ({bool synced, double energyGained}) syncYesterdaySleep(int minutes) {
    final today = _currentDateKey();
    if (_sleepDate == today) return (synced: false, energyGained: 0.0);

    _sleepMinutes = max(0, minutes);
    _sleepDate = today;
    notifyListeners();
    _saveState();
    return (synced: true, energyGained: 0.0);
  }

  void addSleepEnergy(double hours) {
    _energy = (_energy + hours * 10.0).clamp(
      0.0,
      100.0,
    );
    notifyListeners();
    _saveState();
  }

  void addChargingEnergySeconds(double seconds) {
    if (seconds <= 0.0) return;
    final next = (_energy + seconds * (0.5 / 60.0)).clamp(
      0.0,
      100.0,
    );
    if ((next - _energy).abs() < 0.0001) return;
    _energy = next;
    notifyListeners();
    _saveState();
  }

  void _startPoseTimer() {
    _poseTimer?.cancel();
    _poseTimer = Timer.periodic(const Duration(seconds: 7), (timer) {
      if (_isDragging) return;

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
    _moodResetTimer?.cancel(); // ➔ レインボーターマーの消去
    super.dispose();
  }
}
