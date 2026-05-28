import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:health/health.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../physics/puni_physics.dart';
import '../views/creature_painter.dart';
import '../state/creature_state.dart';
import '../audio/audio_controller.dart';

class FoodBubble {
  Offset position;
  Offset velocity;
  final double radius = 8.0; // Slightly smaller food
  int bounces = 0;

  FoodBubble({required this.position, required this.velocity});

  void update(double dt, Offset gravity, double bottomLimit) {
    velocity += gravity * dt;
    position += velocity * dt;

    if (position.dy > bottomLimit - radius) {
      position = Offset(position.dx, bottomLimit - radius);
      velocity = Offset(velocity.dx * 0.7, -velocity.dy.abs() * 0.4);
      bounces++;
    }
  }
}

class _HealthFetchResult {
  final int? value;
  final String? errorMessage;

  const _HealthFetchResult.success(this.value) : errorMessage = null;

  const _HealthFetchResult.failure(this.errorMessage) : value = null;

  bool get isSuccess => value != null && errorMessage == null;
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final PuniPhysics _physics;
  late final CreatureState _state;
  late final AudioController _audioController;

  // Game Loop
  late final AnimationController _gameLoopController;
  double _lastElapsedTime = 0.0;

  // Interactive gravity & Pedometer
  Offset _gravity = const Offset(0, 480);
  StreamSubscription? _accelerometerSub;
  final Health _health = Health();
  static const MethodChannel _healthConnectChannel = MethodChannel(
    'puni/health_connect',
  );

  // Battery monitoring for charging state
  final Battery _battery = Battery();
  bool _isCharging = false;
  StreamSubscription<BatteryState>? _batterySub;

  // Idle movement timers
  double _timeSinceLastJump = 0.0;
  double _timeSinceNoInteraction = 0.0;
  double _chargingRecoveryAccumulator = 0.0;
  int _lastKnownLevel = 1;
  bool _hasInitializedLevelTracking = false;
  double _levelUpSparkleTimer = 0.0;
  static const double _levelUpSparkleDuration = 1.5;

  // Interactive touch mode: 'drag' or 'pet'
  String _interactionMode = 'drag';

  // Food bubbles
  final List<FoodBubble> _foodBubbles = [];
  DateTime? _lastEatAt;

  // Puni Colors (Peach / Rose base)
  Color _primaryColor = const Color(0xFFD2D2D8);
  Color _secondaryColor = const Color(0xFF8E8E93);

  // Eye blinking state
  bool _isBlinking = false;
  Timer? _blinkTimer;

  // AdMob states
  BannerAd? _bannerAd;
  bool _isBannerAdReady = false;
  InterstitialAd? _interstitialAd;
  bool _isShowingInterstitialAd = false;
  bool _isHealthSyncing = false;
  bool? _lastHealthSyncSucceeded;
  bool _lastHealthSyncPermissionDenied = false;
  bool _pendingHealthSyncOnResume = false;

  String get _bannerAdUnitId {
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
        return 'ca-app-pub-3940256099942544/2934735716';
      default:
        return 'ca-app-pub-3940256099942544/6300978111';
    }
  }

  String get _interstitialAdUnitId {
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
        return 'ca-app-pub-3940256099942544/4411468910';
      default:
        return 'ca-app-pub-3940256099942544/1033173712';
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _physics = PuniPhysics();
    _state = CreatureState();
    _audioController = AudioController();

    _state.addListener(_onStateChange);
    _lastKnownLevel = _state.level;
    _hasInitializedLevelTracking = true;

    // Initialize 60fps physics game loop
    _gameLoopController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..addListener(_tickPhysics);
    _gameLoopController.repeat();

    // 1. Tilt Gravity from accelerometer
    _accelerometerSub = accelerometerEventStream().listen(
      (AccelerometerEvent event) {
        // Tilt gravity computation
        double targetGx = -event.x * 65.0;
        // Y（落下速度）は常に立てた時の固定値に保つ
        const double targetGy = 480.0;
        if (targetGx.isNaN) {
          targetGx = 0;
        }

        // Avoid extra rebuilds from sensor stream; the game loop already repaints.
        _gravity = Offset.lerp(_gravity, Offset(targetGx, targetGy), 0.12)!;
      },
      onError: (e) {
        _gravity = const Offset(0, 480);
      },
    );

    // 2. Battery monitor for charging shiver & sparks (ブルブル・ビリビリ)
    _batterySub = _battery.onBatteryStateChanged.listen((BatteryState state) {
      setState(() {
        _isCharging = (state == BatteryState.charging);
      });
    });
    // Check initial charging state
    _battery.batteryState.then((state) {
      setState(() {
        _isCharging = (state == BatteryState.charging);
      });
    });

    _loadBannerAd();
    _loadInterstitialAd();

    _startBlinkCycle();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _audioController.playStartupVoice();
      // Auto-sync step data on startup
      _autoSyncHealthData();
    });
  }

  void _onStateChange() {
    if (!_hasInitializedLevelTracking) {
      _lastKnownLevel = _state.level;
      _hasInitializedLevelTracking = true;
    } else if (_state.level > _lastKnownLevel) {
      _triggerLevelUpFeedback();
      _lastKnownLevel = _state.level;
    } else {
      _lastKnownLevel = _state.level;
    }

    if (!_state.isRainbow) {
      setState(() {
        _primaryColor = _state.creatureColor;
        _secondaryColor = _state.creatureColor.withOpacity(0.7);
      });
    }
  }

  void _triggerLevelUpFeedback() {
    _audioController.playLevelUpVoice();
    _levelUpSparkleTimer = _levelUpSparkleDuration;
  }

  void _tickPhysics() {
    final double totalElapsed = _gameLoopController.value;
    double dt = totalElapsed - _lastElapsedTime;
    if (dt < 0) dt += 1.0;
    _lastElapsedTime = totalElapsed;

    final mediaSize = MediaQuery.maybeOf(context)?.size ?? const Size(400, 800);
    final boundarySize = Size(mediaSize.width, mediaSize.height);

    // Random Idle hops/jumps
    _timeSinceLastJump += dt;
    if (_timeSinceLastJump > 4.5 && !_state.isDragging && !_state.isPetting) {
      if (Random().nextDouble() < 0.16) {
        _timeSinceLastJump = 0.0;
        double jumpImpulseX = (Random().nextDouble() - 0.5) * 320.0;
        _physics.centerVelocity = Offset(jumpImpulseX, -380.0); // Jump up!
        _state.triggerMood('happy', duration: const Duration(seconds: 2));
      }
    }

    // Idle voice: once every 5 seconds while there is no player interference.
    if (_state.isDragging || _state.isPetting) {
      _timeSinceNoInteraction = 0.0;
    } else {
      _timeSinceNoInteraction += dt;
      if (_timeSinceNoInteraction >= 5.0) {
        _timeSinceNoInteraction = 0.0;
        _audioController.playIdleVoice();
      }
    }

    // Step physical integration
    _physics.update(
      dt: dt,
      boundary: boundarySize,
      softness: _state.softness,
      shape: _state.shape,
      touchPosition: _state.touchPosition,
      isDragging: _state.isDragging && _interactionMode == 'drag',
      isPetting: _state.isPetting && _interactionMode == 'pet',
      gravityVector: _gravity,
      isCharging: _isCharging,
    );

    if (_levelUpSparkleTimer > 0.0) {
      _levelUpSparkleTimer = max(0.0, _levelUpSparkleTimer - dt);
    }

    if (_isCharging && _state.energy < 100.0) {
      _chargingRecoveryAccumulator += dt;
      if (_chargingRecoveryAccumulator >= 5.0) {
        _state.addChargingEnergySeconds(_chargingRecoveryAccumulator);
        _chargingRecoveryAccumulator = 0.0;
      }
    } else {
      _chargingRecoveryAccumulator = 0.0;
    }

    // Update food particles
    final bottomLimit =
        boundarySize.height - 210.0; // Keep food above action panel & banner ad
    final toRemove = <FoodBubble>[];
    for (var bubble in _foodBubbles) {
      bubble.update(dt, _gravity, bottomLimit);

      final distToCreature = (bubble.position - _physics.center).distance;
      if (distToCreature < PuniPhysics.baseRadius * 1.3) {
        toRemove.add(bubble);
        _eatFood();
      } else if (bubble.bounces > 2) {
        toRemove.add(bubble);
      }
    }
    _foodBubbles.removeWhere((b) => toRemove.contains(b));

    setState(() {});
  }

  void _eatFood() {
    final now = DateTime.now();
    if (_lastEatAt != null &&
        now.difference(_lastEatAt!).inMilliseconds < 140) {
      return;
    }
    _lastEatAt = now;

    _audioController.playFeedVoice();
    _state.triggerMood('eating', duration: const Duration(seconds: 2));
    _state.addGrowth(0.12, source: 'feed'); // Growth from eating

    // Push boundary nodes outward wobbly
    final impulse = _state.isDragging ? 180.0 : 260.0;
    for (int i = 0; i < PuniPhysics.nodeCount; i++) {
      double angle = i * 2 * pi / PuniPhysics.nodeCount;
      _physics.nodeVelocities[i] += Offset(
        cos(angle) * impulse,
        sin(angle) * impulse,
      );
    }
  }

  void _startBlinkCycle() {
    _blinkTimer = Timer.periodic(const Duration(milliseconds: 4500), (timer) {
      if (mounted) {
        setState(() => _isBlinking = true);
        Future.delayed(const Duration(milliseconds: 140), () {
          if (mounted) setState(() => _isBlinking = false);
        });
      }
    });
  }

  void _handlePointerDown(PointerDownEvent event) {
    _timeSinceNoInteraction = 0.0;
    if (_isShowingInterstitialAd) return;
    final RenderBox? renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    final localPosition = renderBox.globalToLocal(event.position);

    final dist = (localPosition - _physics.center).distance;

    // Tap response within base radius multiplier
    if (dist < PuniPhysics.baseRadius * 1.8) {
      if (_interactionMode == 'drag') {
        _state.setInteraction(
          isDragging: true,
          isPetting: false,
          touchPosition: localPosition,
        );
        _audioController.playGrabVoice(hasEnergy: _state.energy > 0.0);
      } else {
        _state.setInteraction(
          isDragging: false,
          isPetting: true,
          touchPosition: localPosition,
        );
        if (_state.energy <= 0.0) {
          _state.triggerMood('angry', duration: const Duration(seconds: 2));
        } else {
          _state.triggerMood('happy', duration: const Duration(seconds: 2));
        }
      }
    }
  }

  void _handlePointerMove(PointerMoveEvent event) {
    _timeSinceNoInteraction = 0.0;
    if (_isShowingInterstitialAd) return;
    final RenderBox? renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    final localPosition = renderBox.globalToLocal(event.position);

    if (_state.isDragging || _state.isPetting) {
      _state.setInteraction(
        isDragging: _state.isDragging,
        isPetting: _state.isPetting,
        touchPosition: localPosition,
      );

      if (Random().nextDouble() < 0.12) {
        if (_interactionMode == 'drag') {
        } else {
          _state.addGrowth(0.002, source: 'petting'); // Tiny petting growth
        }
      }
    }
  }

  void _handlePointerUp(PointerUpEvent event) {
    _timeSinceNoInteraction = 0.0;
    final wasPetting = _state.isPetting;
    final hasEnergyAtRelease = _state.energy > 0.0;

    if (_state.isDragging) {
      double flingSpeed = _physics.centerVelocity.distance;
      if (flingSpeed > 320.0) {
        _audioController.playFlingVoice(hasEnergy: _state.energy > 0.0);
        if (_state.energy <= 0.0) {
          // Out of energy: hurts (痛そう) -> sad/X-eyes mood
          _state.triggerMood('sad', duration: const Duration(seconds: 3));
        } else {
          // Energetic: fun (楽しそう) -> excited ^ ^ eyes and award growth
          _state.triggerMood('surprised', duration: const Duration(seconds: 3));
          _state.addGrowth(0.05, source: 'fling'); // Plays with energy!
        }
      }
    }
    _state.setInteraction(
      isDragging: false,
      isPetting: false,
      touchPosition: null,
    );

    if (wasPetting) {
      _audioController.playPetEndVoice(hasEnergy: hasEnergyAtRelease);
    }
  }

  void _spawnFood() {
    final consumed = _state.consumeFeedAction();
    if (!consumed) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'ご飯は1日${CreatureState.maxFeedPerDay}回までです。',
            style: GoogleFonts.notoSansJp(fontWeight: FontWeight.bold),
          ),
          backgroundColor: CupertinoColors.systemRed,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final mediaSize = MediaQuery.of(context).size;
    final randomX = 40.0 + Random().nextDouble() * (mediaSize.width - 80.0);
    setState(() {
      _foodBubbles.add(
        FoodBubble(
          position: Offset(randomX, 30.0),
          velocity: const Offset(0, 60.0),
        ),
      );
    });
  }

  // Watch interstitial ad to Level Up
  void _watchAdToLevelUp() {
    if (_isShowingInterstitialAd) return;

    final consumed = _state.consumeAdLevelUpAction();
    if (!consumed) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '動画でLvUPは1日${CreatureState.maxAdLevelUpPerDay}回までです。',
            style: GoogleFonts.notoSansJp(fontWeight: FontWeight.bold),
          ),
          backgroundColor: CupertinoColors.systemRed,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final ad = _interstitialAd;

    if (ad == null) {
      debugPrint(
        "Interstitial ad was null when level up clicked. Loading a new one.",
      );
      _loadInterstitialAd();

      // Inform user via SnackBar that the ad is still loading, but reward them as a fallback
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "広告の準備ができていません。再読み込み中ですが、今回はスキップしてレベルアップします。",
            style: GoogleFonts.notoSansJp(fontWeight: FontWeight.bold),
          ),
          backgroundColor: Colors.orange,
          duration: const Duration(seconds: 3),
        ),
      );
      _grantAdLevelUpResult();
      return;
    }

    _isShowingInterstitialAd = true;
    _interstitialAd = null;
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        debugPrint("Interstitial ad dismissed.");
        ad.dispose();
        _isShowingInterstitialAd = false;
        _grantAdLevelUpResult();
        _loadInterstitialAd();
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        debugPrint("Interstitial ad failed to show: $error");
        ad.dispose();
        _isShowingInterstitialAd = false;
        _grantAdLevelUpResult();
        _loadInterstitialAd();
      },
    );
    ad.show();
  }

  void _grantAdLevelUpResult() {
    final beforeLevel = _state.level;
    _state.performAdLevelUp();
    if (_state.level > beforeLevel) {
      _triggerLevelUpFeedback();
      _lastKnownLevel = _state.level;
      _hasInitializedLevelTracking = true;
    }
  }

  void _loadBannerAd() {
    final ad = BannerAd(
      adUnitId: _bannerAdUnitId,
      request: const AdRequest(),
      size: AdSize.banner,
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          debugPrint("BannerAd loaded successfully.");
          if (!mounted) {
            ad.dispose();
            return;
          }
          setState(() {
            _bannerAd = ad as BannerAd;
            _isBannerAdReady = true;
          });
        },
        onAdFailedToLoad: (ad, error) {
          debugPrint("BannerAd failed to load: $error");
          ad.dispose();
          if (!mounted) return;
          setState(() {
            _bannerAd = null;
            _isBannerAdReady = false;
          });
        },
      ),
    );

    ad.load();
  }

  void _loadInterstitialAd() {
    InterstitialAd.load(
      adUnitId: _interstitialAdUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          debugPrint("InterstitialAd loaded successfully.");
          _interstitialAd = ad;
        },
        onAdFailedToLoad: (error) {
          debugPrint("InterstitialAd failed to load: $error");
          _interstitialAd = null;
        },
      ),
    );
  }

  void _showEnergyRecoveryGuideDialog() {
    showCupertinoDialog(
      context: context,
      builder: (ctx) {
        return CupertinoTheme(
          data: const CupertinoThemeData(brightness: Brightness.light),
          child: CupertinoAlertDialog(
            title: Text(
              'PUNIの説明',
              style: GoogleFonts.notoSansJp(fontWeight: FontWeight.bold),
            ),
            content: Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'エネルギー回復',
                    style: GoogleFonts.notoSansJp(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '・散歩: 今日 0:00-23:59 の歩数を同期\n  1歩ごとに +0.02',
                    style: GoogleFonts.notoSansJp(fontSize: 13),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '・充電: 1分ごとに +0.5',
                    style: GoogleFonts.notoSansJp(fontSize: 13),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '※ ぷにエネルギーの上限は 100 です。',
                    style: GoogleFonts.notoSansJp(
                      fontSize: 12,
                      color: CupertinoColors.systemGrey,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '回復したエネルギーの使い道',
                    style: GoogleFonts.notoSansJp(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '・エネルギーを使ってPUNIと触れ合うと成長してレベルが上がります。',
                    style: GoogleFonts.notoSansJp(fontSize: 13),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    '色の育ち方',
                    style: GoogleFonts.notoSansJp(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '・ご飯・なでる・遊ぶ・動画LvUPのバランスで色が少しずつ変わります。\n  好みの色を目標に、いつものお世話の配分を調整して育ててみてください。',
                    style: GoogleFonts.notoSansJp(fontSize: 13),
                  ),
                  const SizedBox(height: 10),
                  _buildInfoColorRow(
                    color: const Color(0xFFFFD740),
                    label: 'ご飯',
                    description: '黄色寄り',
                  ),
                  const SizedBox(height: 6),
                  _buildInfoColorRow(
                    color: const Color(0xFFFF8DA1),
                    label: 'なでる',
                    description: 'ピンク寄り',
                  ),
                  const SizedBox(height: 6),
                  _buildInfoColorRow(
                    color: const Color(0xFFB388FF),
                    label: '投げる・つまんで遊ぶ',
                    description: '紫寄り',
                  ),
                  const SizedBox(height: 6),
                  _buildInfoColorRow(
                    color: const Color(0xFF80D8FF),
                    label: '動画LvUP',
                    description: '水色寄り',
                  ),
                ],
              ),
            ),
            actions: [
              CupertinoDialogAction(
                onPressed: () => Navigator.of(ctx).pop(),
                child: Text(
                  'とじる',
                  style: GoogleFonts.notoSansJp(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildInfoColorRow({
    required Color color,
    required String label,
    required String description,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            '$label: $description',
            style: GoogleFonts.notoSansJp(fontSize: 12.5),
          ),
        ),
      ],
    );
  }

  String get _healthServiceLabel {
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
        return 'ヘルスケア';
      case TargetPlatform.android:
        return 'Health Connect';
      default:
        return 'ヘルスデータ';
    }
  }

  Future<bool> _hasHealthReadPermissionNow() async {
    try {
      if (!Platform.isAndroid && !Platform.isIOS) {
        return false;
      }

      await _health.configure();

      if (Platform.isAndroid) {
        final permission = await Permission.activityRecognition.status;
        if (!permission.isGranted) {
          return false;
        }
      }

      final hasGranted = await _health.hasPermissions(
        [HealthDataType.STEPS],
        permissions: const [HealthDataAccess.READ],
      );
      return hasGranted == true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _refreshHealthPermissionDeniedFlag() async {
    if (!_lastHealthSyncPermissionDenied) return;
    final hasPermissionNow = await _hasHealthReadPermissionNow();
    if (!mounted) return;
    if (hasPermissionNow) {
      setState(() {
        _lastHealthSyncPermissionDenied = false;
      });
    }
  }

  Future<bool> _requestActivityRecognitionPermission() async {
    if (!Platform.isAndroid) return true;
    final permission = await Permission.activityRecognition.request();
    return permission.isGranted;
  }

  Future<bool> _requestHealthConnectReadPermission() async {
    if (!Platform.isAndroid && !Platform.isIOS) return false;

    try {
      await _health.configure();

      if (Platform.isAndroid) {
        final sdkStatus = await _health.getHealthConnectSdkStatus();
        if (sdkStatus != HealthConnectSdkStatus.sdkAvailable) {
          debugPrint('Health Connect SDK unavailable: $sdkStatus');
          await _health.installHealthConnect();
          return false;
        }
      }

      final hasGranted = await _health.hasPermissions(
        [HealthDataType.STEPS],
        permissions: const [HealthDataAccess.READ],
      );
      if (hasGranted == true) {
        return true;
      }

      final granted = await _health.requestAuthorization(
        [HealthDataType.STEPS],
        permissions: const [HealthDataAccess.READ],
      );
      if (granted) {
        return true;
      }

      // Some devices return false even when state updates shortly after dialog close.
      final hasGrantedAfterRequest = await _health.hasPermissions(
        [HealthDataType.STEPS],
        permissions: const [HealthDataAccess.READ],
      );
      return hasGrantedAfterRequest == true;
    } catch (error) {
      debugPrint('Health Connect permission request failed: $error');
      return false;
    }
  }

  Future<bool> _openHealthConnectApp() async {
    if (!Platform.isAndroid) return false;
    try {
      final opened = await _healthConnectChannel.invokeMethod<bool>(
        'openHealthConnectApp',
      );
      _pendingHealthSyncOnResume = opened == true;
      return opened == true;
    } catch (error) {
      debugPrint('Failed to open Health Connect app: $error');
      return false;
    }
  }

  Future<void> _showHealthPermissionRetryDialog() async {
    if (!mounted || _isHealthSyncing) return;

    await showCupertinoDialog(
      context: context,
      builder: (ctx) {
        return CupertinoAlertDialog(
          title: Text(
            'PUNIで許可を取り直す',
            style: GoogleFonts.notoSansJp(fontWeight: FontWeight.bold),
          ),
          content: Text(
            Platform.isIOS
                ? 'PUNI内でヘルスケアの許可をもう一度要求します。\nもし再表示されない場合は、iPhoneの「設定」>「ヘルスケア」>「PUNI」で許可を見直してください。'
                : 'PUNI内で身体活動とHealth Connectの許可をもう一度要求します。\n許可できたら、そのまま同期をやり直せます。',
            style: GoogleFonts.notoSansJp(fontSize: 13),
          ),
          actions: [
            CupertinoDialogAction(
              onPressed: () async {
                Navigator.of(ctx).pop();
                if (Platform.isAndroid) {
                  final activityGranted =
                      await _requestActivityRecognitionPermission();
                  if (!activityGranted) {
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          '身体活動の許可がまだ必要です。',
                          style: GoogleFonts.notoSansJp(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        backgroundColor: CupertinoColors.systemRed,
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                    return;
                  }

                  // Give Android a moment to settle after the runtime permission dialog.
                  await Future.delayed(const Duration(milliseconds: 250));
                }

                final healthConnectGranted =
                    await _requestHealthConnectReadPermission();
                if (!healthConnectGranted && Platform.isAndroid) {
                  // Retry once because the first HC request can fail right after
                  // closing the activity recognition permission sheet.
                  await Future.delayed(const Duration(milliseconds: 250));
                }

                final finalHealthConnectGranted =
                    healthConnectGranted ||
                    (Platform.isAndroid &&
                        await _requestHealthConnectReadPermission());

                if (!finalHealthConnectGranted) {
                  if (Platform.isAndroid) {
                    await _openHealthConnectApp();
                  }
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        Platform.isAndroid
                            ? 'Health Connect を開きました。PUNI の歩数を許可して戻ると自動同期します。'
                            : 'ヘルスケアの歩数許可がまだ必要です。',
                        style: GoogleFonts.notoSansJp(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      backgroundColor: CupertinoColors.systemRed,
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                  return;
                }

                await _autoSyncHealthData();
              },
              child: Text(
                '再試行',
                style: GoogleFonts.notoSansJp(fontWeight: FontWeight.bold),
              ),
            ),
            CupertinoDialogAction(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text('とじる', style: GoogleFonts.notoSansJp()),
            ),
          ],
        );
      },
    );
  }

  bool _isPermissionDeniedMessage(String? message) {
    if (message == null) return false;
    return message.contains('許可されていません');
  }

  Future<_HealthFetchResult> _ensureHealthReadPermissions() async {
    if (!Platform.isAndroid && !Platform.isIOS) {
      return const _HealthFetchResult.failure('この端末ではヘルス同期に対応していません。');
    }

    await _health.configure();

    if (Platform.isAndroid) {
      final permission = await Permission.activityRecognition.request();
      if (!permission.isGranted) {
        return const _HealthFetchResult.failure('アクティビティ認識の権限が許可されていません。');
      }
    }

    final types = [HealthDataType.STEPS];

    final hasGranted = await _health.hasPermissions(
      types,
      permissions: const [HealthDataAccess.READ],
    );

    if (hasGranted == true) {
      return const _HealthFetchResult.success(1);
    }

    final granted = await _health.requestAuthorization(
      types,
      permissions: const [HealthDataAccess.READ],
    );

    if (!granted) {
      return _HealthFetchResult.failure(
        '$_healthServiceLabel の歩数アクセスが許可されていません。',
      );
    }

    return const _HealthFetchResult.success(1);
  }

  Future<_HealthFetchResult> _fetchTodayHealthSteps() async {
    try {
      final permissionResult = await _ensureHealthReadPermissions();
      if (!permissionResult.isSuccess) {
        return permissionResult;
      }

      final now = DateTime.now();
      final startOfDay = DateTime(now.year, now.month, now.day);
      final totalSteps = await _health.getTotalStepsInInterval(startOfDay, now);
      if (totalSteps == null) {
        return const _HealthFetchResult.failure('歩数データが見つかりませんでした。');
      }

      return _HealthFetchResult.success(totalSteps);
    } catch (error) {
      debugPrint('Health step sync error: $error');
      return _HealthFetchResult.failure('歩数同期エラー: $error');
    }
  }

  /// Auto-sync step data on app startup.
  Future<void> _autoSyncHealthData() async {
    if (mounted) {
      setState(() {
        _isHealthSyncing = true;
        _lastHealthSyncPermissionDenied = false;
      });
    }

    final failures = <String>[];
    bool permissionDenied = false;
    // Sync today's steps
    final stepsResult = await _fetchTodayHealthSteps();
    if (stepsResult.isSuccess) {
      final stepsTotal = stepsResult.value!;
      final gained = _state.syncTodaySteps(stepsTotal);
      debugPrint('Steps synced: $stepsTotal total, +$gained new steps');
    } else if (stepsResult.errorMessage != null) {
      failures.add('歩数: ${stepsResult.errorMessage!}');
      permissionDenied = _isPermissionDeniedMessage(stepsResult.errorMessage);
    }

    if (mounted) {
      setState(() {
        _isHealthSyncing = false;
        _lastHealthSyncSucceeded = failures.isEmpty;
        _lastHealthSyncPermissionDenied = permissionDenied;
      });
    }

    if (failures.isNotEmpty && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            failures.join('\n'),
            style: GoogleFonts.notoSansJp(fontWeight: FontWeight.bold),
          ),
          backgroundColor: CupertinoColors.systemRed,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 5),
          action: permissionDenied
              ? SnackBarAction(
                  label: '再試行',
                  textColor: Colors.white,
                  onPressed: () async {
                    await _showHealthPermissionRetryDialog();
                  },
                )
              : null,
        ),
      );
    }
  }

  LinearGradient _getBackgroundGradient() {
    int hour = DateTime.now().hour;
    if (_state.isRainbow) {
      return const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF23023B), Color(0xFF07000F)],
      );
    }

    if (hour >= 5 && hour < 10) {
      return const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFFFFE5EC), Color(0xFFFFF2E6)],
      );
    } else if (hour >= 10 && hour < 17) {
      return const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFFE3F2FD), Color(0xFFF3E5F5)],
      );
    } else if (hour >= 17 && hour < 20) {
      return const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFFFCE4EC), Color(0xFFE8EAF6)],
      );
    } else {
      return const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF1E1E3F), Color(0xFF0D0D1E)],
      );
    }
  }

  Color _getTextColor() {
    int hour = DateTime.now().hour;
    if (_state.isRainbow || hour < 5 || hour >= 20) {
      return Colors.white.withOpacity(0.9);
    }
    return const Color(0xFF2C3E50);
  }

  String _buildHealthSyncStatusText() {
    if (_isHealthSyncing) {
      return 'ヘルス同期中';
    }
    if (_lastHealthSyncSucceeded == null) {
      return 'ヘルス未同期';
    }

    return _lastHealthSyncSucceeded! ? '同期OK' : '同期NG';
  }

  Color _getHealthSyncStatusColor() {
    if (_isHealthSyncing) {
      return const Color(0xFFFF9500);
    }
    if (_lastHealthSyncSucceeded == null) {
      return CupertinoColors.systemGrey;
    }
    return _lastHealthSyncSucceeded!
        ? const Color(0xFF34C759)
        : const Color(0xFFFF3B30);
  }

  IconData _getHealthSyncStatusIcon() {
    if (_isHealthSyncing) {
      return CupertinoIcons.clock;
    }
    if (_lastHealthSyncSucceeded == null) {
      return CupertinoIcons.question_circle_fill;
    }
    return _lastHealthSyncSucceeded!
        ? CupertinoIcons.check_mark_circled_solid
        : CupertinoIcons.exclamationmark_circle_fill;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _state.refreshDailyActionLimits();
      _refreshHealthPermissionDeniedFlag();
      if (_pendingHealthSyncOnResume && !_isHealthSyncing) {
        _pendingHealthSyncOnResume = false;
        Future.delayed(const Duration(milliseconds: 300), () async {
          if (!mounted || _isHealthSyncing) return;
          await _autoSyncHealthData();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final textThemeColor = _getTextColor();
    final sparkleProgress = (_levelUpSparkleTimer / _levelUpSparkleDuration)
        .clamp(0.0, 1.0);

    return Scaffold(
      body: Stack(
        children: [
          // 1. Dynamic Background
          AnimatedContainer(
            duration: const Duration(seconds: 2),
            decoration: BoxDecoration(gradient: _getBackgroundGradient()),
          ),

          // 2. Main Painter Area
          Positioned.fill(
            child: Listener(
              onPointerDown: _handlePointerDown,
              onPointerMove: _handlePointerMove,
              onPointerUp: _handlePointerUp,
              child: CustomPaint(
                painter: CreaturePainter(
                  physics: _physics,
                  mood: _state.mood,
                  shape: _state.shape,
                  softness: _state.softness,
                  energy: _state.energy,
                  primaryColor: _primaryColor,
                  secondaryColor: _secondaryColor,
                  touchPosition: _state.touchPosition,
                  isBlinking: _isBlinking,
                  isRainbow: _state.isRainbow,
                  isCharging: _isCharging,
                  isPetting: _state.isPetting,
                ),
                child: Container(),
              ),
            ),
          ),

          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _LevelUpSparklePainter(
                  center: _physics.center,
                  progress: sparkleProgress,
                  baseRadius: PuniPhysics.baseRadius,
                ),
              ),
            ),
          ),

          // 3. Food Particle Renderer
          ..._foodBubbles.map((bubble) {
            return Positioned(
              left: bubble.position.dx - bubble.radius,
              top: bubble.position.dy - bubble.radius,
              child: Container(
                width: bubble.radius * 2,
                height: bubble.radius * 2,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      Colors.white,
                      const Color(0xFFFFC107).withOpacity(0.85),
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFFFC107).withOpacity(0.4),
                      blurRadius: 4,
                    ),
                  ],
                ),
              ),
            );
          }),

          // 4. Top HUD
          Positioned(
            top: media.padding.top + 16,
            left: 20,
            right: 20,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: Container(
                decoration: BoxDecoration(
                  color: textThemeColor == Colors.white
                      ? Colors.white.withOpacity(0.08)
                      : Colors.white.withOpacity(0.4),
                  border: Border.all(
                    color: textThemeColor == Colors.white
                        ? Colors.white.withOpacity(0.12)
                        : Colors.white.withOpacity(0.25),
                  ),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 16,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "Lv ${_state.level}",
                              style: GoogleFonts.outfit(
                                fontSize: 26,
                                fontWeight: FontWeight.bold,
                                color: textThemeColor,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              "状態: ${_state.softnessLabel}",
                              style: GoogleFonts.notoSansJp(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: textThemeColor.withOpacity(0.85),
                              ),
                            ),
                          ],
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(
                                  0xFFFFD740,
                                ).withOpacity(0.18),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 18,
                                    height: 18,
                                    clipBehavior: Clip.antiAlias,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(9),
                                    ),
                                    child: SvgPicture.asset(
                                      'assets/icon/walk_badge_option4.svg',
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                  const SizedBox(width: 5),
                                  Text(
                                    "さんぽ ${_state.stepsToday} 歩",
                                    style: GoogleFonts.notoSansJp(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: textThemeColor,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    // Level Up progress indicator
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Stack(
                        children: [
                          Container(
                            height: 8,
                            color: textThemeColor == Colors.white
                                ? Colors.white.withOpacity(0.1)
                                : Colors.black.withOpacity(0.05),
                          ),
                          AnimatedFractionallySizedBox(
                            duration: const Duration(milliseconds: 250),
                            widthFactor: _state.growthToday.clamp(0.0, 1.0),
                            child: Container(
                              height: 8,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [_primaryColor, _secondaryColor],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Puni Energy Display & Auto Sync status
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.bolt,
                              color: Color(0xFFFF7A9D),
                              size: 16,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              "ぷにエネルギー: ${_state.energy.toStringAsFixed(1)} / 100",
                              style: GoogleFonts.notoSansJp(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: textThemeColor,
                              ),
                            ),
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: _getHealthSyncStatusColor().withOpacity(
                              0.12,
                            ),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _getHealthSyncStatusIcon(),
                                color: _getHealthSyncStatusColor(),
                                size: 13,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                _buildHealthSyncStatusText(),
                                style: GoogleFonts.notoSansJp(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: _getHealthSyncStatusColor(),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Align(
                      alignment: Alignment.centerRight,
                      child: CupertinoButton(
                        padding: EdgeInsets.zero,
                        onPressed: _isHealthSyncing
                            ? null
                            : () async {
                                await _autoSyncHealthData();
                              },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFF2D55).withOpacity(0.12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (_isHealthSyncing)
                                const CupertinoActivityIndicator(radius: 6)
                              else
                                const Icon(
                                  CupertinoIcons.arrow_clockwise_circle_fill,
                                  color: Color(0xFFFF2D55),
                                  size: 13,
                                ),
                              const SizedBox(width: 4),
                              Text(
                                _isHealthSyncing ? '同期中...' : '手動同期',
                                style: GoogleFonts.notoSansJp(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: const Color(0xFFFF2D55),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    // Energy progress bar
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Stack(
                        children: [
                          Container(
                            height: 6,
                            color: textThemeColor == Colors.white
                                ? Colors.white.withOpacity(0.1)
                                : Colors.black.withOpacity(0.05),
                          ),
                          AnimatedFractionallySizedBox(
                            duration: const Duration(milliseconds: 250),
                            widthFactor: (_state.energy / 100.0).clamp(
                              0.0,
                              1.0,
                            ),
                            child: Container(
                              height: 6,
                              decoration: const BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    Color(0xFF34C759),
                                    Color(0xFF4CD964),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          "テスト用Lv変更:",
                          style: GoogleFonts.notoSansJp(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: textThemeColor.withOpacity(0.7),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            physics: const BouncingScrollPhysics(),
                            child: Row(
                              children: [1, 25, 50, 75, 100].map((lv) {
                                final isCurrent = _state.level == lv;
                                return Padding(
                                  padding: const EdgeInsets.only(left: 4),
                                  child: InkWell(
                                    onTap: () => _state.debugSetLevel(lv),
                                    borderRadius: BorderRadius.circular(12),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: isCurrent
                                            ? _primaryColor
                                            : (textThemeColor == Colors.white
                                                  ? Colors.white.withOpacity(
                                                      0.1,
                                                    )
                                                  : Colors.black.withOpacity(
                                                      0.05,
                                                    )),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: isCurrent
                                              ? Colors.transparent
                                              : (textThemeColor == Colors.white
                                                    ? Colors.white.withOpacity(
                                                        0.1,
                                                      )
                                                    : Colors.black.withOpacity(
                                                        0.1,
                                                      )),
                                          width: 1,
                                        ),
                                      ),
                                      child: Text(
                                        "Lv$lv",
                                        style: GoogleFonts.outfit(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: isCurrent
                                              ? Colors.white
                                              : textThemeColor,
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),

          // 6. Bottom Panels (Actions + Banner Ad)
          Positioned(
            bottom: media.padding.bottom + 12,
            left: 20,
            right: 20,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Minimalist Action panel
                ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: Container(
                    decoration: BoxDecoration(
                      color: textThemeColor == Colors.white
                          ? Colors.white.withOpacity(0.08)
                          : Colors.white.withOpacity(0.4),
                      border: Border.all(
                        color: textThemeColor == Colors.white
                            ? Colors.white.withOpacity(0.12)
                            : Colors.white.withOpacity(0.25),
                      ),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _buildActionButton(
                          icon: _interactionMode == 'drag'
                              ? Icons.touch_app
                              : Icons.front_hand,
                          label: _interactionMode == 'drag' ? "触る" : "撫でる",
                          subtitle: '制限なし',
                          isActive: _interactionMode == 'pet',
                          textThemeColor: textThemeColor,
                          onPressed: () {
                            setState(() {
                              _interactionMode = _interactionMode == 'drag'
                                  ? 'pet'
                                  : 'drag';
                            });
                          },
                        ),
                        _buildActionButton(
                          icon: Icons.cookie,
                          label: "ご飯",
                          subtitle:
                              '残り ${_state.feedRemainingToday}/${CreatureState.maxFeedPerDay}',
                          isActive: false,
                          isEnabled: _state.feedRemainingToday > 0,
                          textThemeColor: textThemeColor,
                          onPressed: _spawnFood,
                        ),
                        _buildActionButton(
                          icon: Icons.play_circle_filled,
                          label: "動画でLvUP",
                          subtitle:
                              '残り ${_state.adLevelUpRemainingToday}/${CreatureState.maxAdLevelUpPerDay}',
                          isActive: true,
                          isEnabled: _state.adLevelUpRemainingToday > 0,
                          textThemeColor: textThemeColor,
                          onPressed: _watchAdToLevelUp,
                        ),
                        _buildActionButton(
                          icon: Icons.info_outline,
                          label: "説明",
                          subtitle: 'ヘルプ',
                          isActive: false,
                          textThemeColor: textThemeColor,
                          onPressed: _showEnergyRecoveryGuideDialog,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // AdMob test banner ad
                _buildBannerAd(textThemeColor),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required String subtitle,
    required bool isActive,
    required Color textThemeColor,
    bool isEnabled = true,
    required VoidCallback onPressed,
  }) {
    final activeColor = const Color(0xFFFF2A6D);
    return InkWell(
      onTap: isEnabled ? onPressed : null,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: isEnabled
                  ? (isActive ? activeColor : textThemeColor.withOpacity(0.8))
                  : textThemeColor.withOpacity(0.35),
              size: 24,
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: GoogleFonts.notoSansJp(
                fontSize: 11,
                fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                color: isEnabled
                    ? (isActive ? activeColor : textThemeColor.withOpacity(0.7))
                    : textThemeColor.withOpacity(0.35),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: GoogleFonts.notoSansJp(
                fontSize: 9,
                fontWeight: FontWeight.w600,
                color: isEnabled
                    ? textThemeColor.withOpacity(0.55)
                    : textThemeColor.withOpacity(0.35),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBannerAd(Color textThemeColor) {
    if (_isBannerAdReady && _bannerAd != null) {
      return SizedBox(
        width: _bannerAd!.size.width.toDouble(),
        height: _bannerAd!.size.height.toDouble(),
        child: AdWidget(ad: _bannerAd!),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Container(
        height: 52,
        decoration: BoxDecoration(
          color: textThemeColor == Colors.white
              ? Colors.white.withOpacity(0.08)
              : Colors.white.withOpacity(0.4),
          border: Border.all(
            color: textThemeColor == Colors.white
                ? Colors.white.withOpacity(0.12)
                : Colors.white.withOpacity(0.25),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.amber[700],
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                "AD",
                style: GoogleFonts.outfit(
                  color: Colors.white,
                  fontSize: 8,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "超癒やしスライム玩具 PuniPop2!",
                    style: GoogleFonts.notoSansJp(
                      color: textThemeColor,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    "触感が２倍になって新登場！今すぐDL",
                    style: GoogleFonts.notoSansJp(
                      color: textThemeColor.withOpacity(0.6),
                      fontSize: 9,
                    ),
                  ),
                ],
              ),
            ),
            ElevatedButton(
              onPressed: () {},
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF2A6D),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                minimumSize: const Size(40, 28),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: Text(
                "入手",
                style: GoogleFonts.notoSansJp(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _gameLoopController.dispose();
    _accelerometerSub?.cancel();
    _batterySub?.cancel();
    _bannerAd?.dispose();
    _interstitialAd?.dispose();
    _blinkTimer?.cancel();
    _state.removeListener(_onStateChange);
    _audioController.dispose();
    _state.dispose();
    super.dispose();
  }
}

class _LevelUpSparklePainter extends CustomPainter {
  final Offset center;
  final double progress;
  final double baseRadius;

  _LevelUpSparklePainter({
    required this.center,
    required this.progress,
    required this.baseRadius,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0.0) return;

    final now = DateTime.now().millisecondsSinceEpoch / 1000.0;
    final fade = Curves.easeOut.transform(progress);
    final twinkle = 0.72 + 0.28 * sin(now * 16.0);
    final alpha = (0.54 * fade * twinkle).clamp(0.0, 1.0);

    final ringRadius = baseRadius * (1.45 + (1.0 - progress) * 0.28);
    final ringPaint = Paint()
      ..color = const Color(0xFFFDFCF7).withValues(alpha: alpha)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2;
    canvas.drawCircle(center, ringRadius, ringPaint);

    final outerRingPaint = Paint()
      ..color = const Color(0xFFFFFFFF).withValues(alpha: alpha * 0.52)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3;
    canvas.drawCircle(center, ringRadius + 10.0, outerRingPaint);

    final sparklePaint = Paint()
      ..color = const Color(
        0xFFFFF8D6,
      ).withValues(alpha: (alpha * 1.15).clamp(0.0, 1.0))
      ..style = PaintingStyle.fill;

    const int sparkleCount = 18;
    for (int i = 0; i < sparkleCount; i++) {
      final angle = (2 * pi * i / sparkleCount) + now * 0.9;
      final radialJitter = 8.0 * sin(now * 5.1 + i * 0.8);
      final sparkleCenter =
          center + Offset(cos(angle), sin(angle)) * (ringRadius + radialJitter);

      final pulse = 0.65 + 0.35 * sin(now * 10.0 + i);
      final r = (1.7 + 2.4 * fade * pulse).clamp(1.0, 4.6);
      canvas.drawCircle(sparkleCenter, r, sparklePaint);

      // Four-point tiny star for subtle glitter.
      final lineLength = r * 2.2;
      final starPaint = Paint()
        ..color = const Color(
          0xFFFFFFFF,
        ).withValues(alpha: (alpha * 0.9 * pulse).clamp(0.0, 1.0))
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.1
        ..strokeCap = StrokeCap.round;

      canvas.drawLine(
        sparkleCenter + Offset(-lineLength, 0),
        sparkleCenter + Offset(lineLength, 0),
        starPaint,
      );
      canvas.drawLine(
        sparkleCenter + Offset(0, -lineLength),
        sparkleCenter + Offset(0, lineLength),
        starPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _LevelUpSparklePainter oldDelegate) {
    return oldDelegate.center != center ||
        oldDelegate.progress != progress ||
        oldDelegate.baseRadius != baseRadius;
  }
}
