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
import '../models/title_badge.dart';
import '../audio/audio_controller.dart';
import 'dart:ui' as ui;
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/rendering.dart';

class FoodBubble {
  Offset position;
  Offset velocity;
  final double radius = 8.0; // Slightly smaller food
  int bounces = 0;
  double lifeTime = 0.0;
  final String foodType;
  final Color color;

  FoodBubble({
    required this.position,
    required this.velocity,
    this.foodType = 'none',
    this.color = const Color(0xFF9E9E9E),
  });

  void update(double dt, Offset gravity, double bottomLimit) {
    velocity += gravity * dt;
    position += velocity * dt;
    lifeTime += dt;

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
  final GlobalKey _profileCardKey = GlobalKey();

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
  // Petting touch particles
  final List<TouchParticle> _touchParticles = [];
  DateTime? _lastEatAt;
  DateTime? _pettingStartTime;

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
  bool _isInterstitialAdLoading = false;
  bool _isHealthSyncing = false;
  bool? _lastHealthSyncSucceeded;
  bool _lastHealthSyncPermissionDenied = false;
  bool _pendingHealthSyncOnResume = false;

  // Multi-touch tracking for pinch-to-stretch
  final Map<int, Offset> _activePointers = {};
  double _initialPinchDistance = 0.0;

  // Hold-to-inflate variables (Puni Balloon)
  Timer? _holdTimer;
  Offset? _holdStartPos;
  double _inflationScale = 1.0;

  // Follow-finger variables (Tap outside Puni)
  Timer? _followTimer;
  Offset? _followStartPos;
  Offset? _followTarget;
  bool _isFollowingFinger = false;

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

    if (_state.newlyUnlockedQueue.isNotEmpty) {
      for (var badge in _state.newlyUnlockedQueue) {
        _showBadgeUnlockedPopup(badge);
      }
      _state.clearNewlyUnlockedQueue();
    }

    setState(() {
      _primaryColor = _state.creatureColor;
      _secondaryColor = _state.creatureColor.withOpacity(0.7);
    });
  }

  void _showBadgeUnlockedPopup(TitleBadge badge) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            _buildBadgeWidget(badge, size: 40),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('称号バッジ獲得！', style: GoogleFonts.notoSansJp(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white70)),
                  Text(badge.name, style: GoogleFonts.notoSansJp(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                ],
              ),
            ),
          ],
        ),
        backgroundColor: Colors.black87,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.only(bottom: 24, left: 16, right: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        duration: const Duration(seconds: 4),
      ),
    );
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

    // Random Idle hops/jumps (disabled when starving)
    _timeSinceLastJump += dt;
    if (_state.hunger > 0.0 && _timeSinceLastJump > 4.5 && !_state.isDragging && !_state.isPetting) {
      if (Random().nextDouble() < 0.16) {
        _timeSinceLastJump = 0.0;
        double jumpImpulseX = (Random().nextDouble() - 0.5) * 320.0;
        _physics.centerVelocity = Offset(jumpImpulseX, -380.0); // Jump up!
        _state.triggerMood('happy', duration: const Duration(seconds: 2));
      }
    }

    // 満腹時限定のハッピーエフェクト（スピードアップエフェクト）
    if (_state.hunger >= 99.0 && Random().nextDouble() < 0.04) {
      final speed = 80.0 + Random().nextDouble() * 60.0; // 上に早く
      _touchParticles.add(
        TouchParticle(
          position: _physics.center + Offset((Random().nextDouble() - 0.5) * 80.0, 20.0),
          velocity: Offset(0, -speed), // 真上
          maxLife: 0.6 + Random().nextDouble() * 0.4,
          color: const Color(0xFF00FFFF), // 水色（スピードアップ感）
          isBubble: false,
          isSpeedUp: true,
          sizeMultiplier: 1.2,
        ),
      );
    }

    // Inactivity/Sleep logic
    if (_state.isDragging ||
        _state.isPetting ||
        _state.isPinching ||
        _state.isInflating) {
      if (_state.mood == 'sleep') {
        _state.setMood('normal');
      }
      _timeSinceNoInteraction = 0.0;
    } else {
      _timeSinceNoInteraction += dt;
      if (_state.mood == 'sleep') {
        _timeSinceLastJump = 0.0;
      } else {
        // ペコペコ時は眠らず「お腹すいた」状態をキープ
        if (_state.hunger <= 0.0) {
          _timeSinceNoInteraction = 0.0; // 放置タイマーをリセットして寝かせない
        } else if (_timeSinceNoInteraction >= 30.0) {
          _state.setMood('sleep');
        } else if (_timeSinceNoInteraction >= 6.0 &&
            _timeSinceNoInteraction - dt < 6.0) {
          _audioController.playIdleVoice();
        }
      }
    }

    Offset? pinchVector;
    double pinchDistanceRatio = 1.0;

    if (_state.isPinching && _activePointers.length >= 2) {
      final points = _activePointers.values.toList();
      final pos1 = points[0];
      final pos2 = points[1];
      pinchVector = pos2 - pos1;
      double dist = pinchVector.distance;
      if (_initialPinchDistance == 0.0) {
        _initialPinchDistance = dist;
      }
      pinchDistanceRatio = _initialPinchDistance > 0.0
          ? dist / _initialPinchDistance
          : 1.0;

      // Update center of mass to follow the midpoint of the two fingers with easing
      final midpoint = (pos1 + pos2) / 2;
      _physics.center = Offset.lerp(_physics.center, midpoint, 0.45)!;
      _physics.centerVelocity = Offset.zero;
    }

    if (_state.isInflating) {
      _inflationScale = min(1.6, _inflationScale + dt * 1.5);
    } else {
      _inflationScale = max(1.0, _inflationScale - dt * 2.5);
    }

    // Step physical integration
    _physics.update(
      dt: dt,
      boundary: boundarySize,
      softness: _state.softness,
      shape: _state.shape,
      touchPosition: _state.touchPosition,
      isDragging:
          (_state.isDragging && _interactionMode == 'drag') ||
          _state.isInflating,
      isPetting: _state.isPetting && _interactionMode == 'pet',
      gravityVector: _gravity,
      isCharging: _isCharging,
      isPinching: _state.isPinching,
      pinchVector: pinchVector,
      pinchDistanceRatio: pinchDistanceRatio,
      inflationScale: _inflationScale,
      isFollowing: _isFollowingFinger,
      followPosition: _followTarget,
      isSleeping: _state.mood == 'sleep',
      onBounce: () {
        _audioController.playBoyo(_state.softness);
      },
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

    // ★新仕様：スライムの物理挙動（PuniPhysics）と全く同じ位置に、ご飯用の「透明な壁」を定義します
    const double wallMargin = 20.0;
    final double leftWall = wallMargin;
    final double rightWall = boundarySize.width - wallMargin;

    final toRemove = <FoodBubble>[];
    for (var bubble in _foodBubbles) {
      bubble.update(dt, _gravity, bottomLimit);

      // ★新仕様：ご飯が左右の「透明な壁」にぶつかった時のバウンド処理
      if (bubble.position.dx < leftWall + bubble.radius) {
        // 左の壁にヒット
        bubble.position = Offset(leftWall + bubble.radius, bubble.position.dy);
        bubble.velocity = Offset(
          bubble.velocity.dx.abs() * 0.5,
          bubble.velocity.dy * 0.8,
        );
      } else if (bubble.position.dx > rightWall - bubble.radius) {
        // 右の壁にヒット
        bubble.position = Offset(rightWall - bubble.radius, bubble.position.dy);
        bubble.velocity = Offset(
          -bubble.velocity.dx.abs() * 0.5,
          bubble.velocity.dy * 0.8,
        );
      }

      final distToCreature = (bubble.position - _physics.center).distance;
      if (distToCreature < PuniPhysics.baseRadius * 1.3) {
        toRemove.add(bubble);
        _eatFood(bubble.foodType);
      } else if (bubble.lifeTime >= 5.0) {
        toRemove.add(bubble);
      }
    }
    _foodBubbles.removeWhere((b) => toRemove.contains(b));

    // Update touch particles
    for (var particle in _touchParticles) {
      particle.update(dt);
    }
    _touchParticles.removeWhere((p) => p.life <= 0.0);

    setState(() {});
  }

  void _eatFood(String foodType) {
    final now = DateTime.now();
    if (_lastEatAt != null &&
        now.difference(_lastEatAt!).inMilliseconds < 140) {
      return;
    }
    _lastEatAt = now;

    _audioController.playFeedVoice();
    _state.triggerMood('eating', duration: const Duration(seconds: 2));

    if (foodType == 'medicine_bleach') {
      _state.applyMedicine('bleach');
      _state.addGrowth(0.02, source: 'feed', foodType: 'default');
    } else if (foodType == 'medicine_desaturate') {
      _state.applyMedicine('desaturate');
      _state.addGrowth(0.02, source: 'feed', foodType: 'default');
    } else {
      _state.addGrowth(0.02, source: 'feed', foodType: foodType);
    }

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

  void _maybeDropCoin(Offset position) {
    // 30% chance to drop exactly 1 coin on PUNI interaction.
    if (Random().nextDouble() >= 0.30) return;

    _state.addCoins(1);
    final angle = -pi / 2.0 + (Random().nextDouble() - 0.5) * (pi / 3.0);
    final speed = 150.0 + Random().nextDouble() * 200.0;
    _touchParticles.add(
      TouchParticle(
        position: position,
        velocity: Offset(cos(angle) * speed, sin(angle) * speed),
        maxLife: 1.2 + Random().nextDouble() * 0.6,
        color: const Color(0xFFFFD700),
        isBubble: false,
        isCoin: true,
      ),
    );
  }

  void _handlePointerDown(PointerDownEvent event) {
    if (_state.mood == 'sleep') {
      _state.setMood('normal');
    }
    _timeSinceNoInteraction = 0.0;
    if (_isShowingInterstitialAd) return;
    final RenderBox? renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    final localPosition = renderBox.globalToLocal(event.position);

    _activePointers[event.pointer] = localPosition;

    // ペコペコ時は1本指ドラッグのみ有効（投げなし）
    if (_state.hunger <= 0.0) {
      if (_activePointers.length == 1) {
        // 潰れた時の視覚中心: x方向は1.15倍広がり、y方向は底辺(center.dy + baseRadius)を基準に0.5倍縮小し、15px上にシフト
        final visualCenterX = _physics.center.dx;
        final visualCenterY = _physics.center.dy + PuniPhysics.baseRadius * 0.5 - 15.0;
        final dx = (localPosition.dx - visualCenterX) / (PuniPhysics.baseRadius * 1.15 * 1.8);
        final dy = (localPosition.dy - visualCenterY) / (PuniPhysics.baseRadius * 0.5 * 1.8);
        final inEllipse = (dx * dx + dy * dy) < 1.0;
        if (inEllipse) {
          _state.setInteraction(
            isDragging: true,
            isPetting: false,
            touchPosition: localPosition,
          );
        }
      }
      return;
    }

    if (_activePointers.length >= 2 && _state.intimacy >= 100.0) {
      _holdTimer?.cancel();
      _holdTimer = null;
      _holdStartPos = null;

      _followTimer?.cancel();
      _followTimer = null;
      _followStartPos = null;
      _followTarget = null;
      setState(() {
        _isFollowingFinger = false;
      });

      _state.setInteraction(
        isDragging: false,
        isPetting: false,
        isPinching: true,
        isInflating: false,
        touchPosition: _physics.center,
      );
    } else if (_activePointers.length == 1) {
      final dist = (localPosition - _physics.center).distance;
      double touchThreshold = PuniPhysics.baseRadius * 1.8;
      if (dist < touchThreshold) {
        // Cancel follow mode when touching inside Puni
        _followTimer?.cancel();
        _followTimer = null;
        _followStartPos = null;
        _followTarget = null;
        setState(() {
          _isFollowingFinger = false;
        });

        if (_state.intimacy >= 150.0) {
          _holdStartPos = localPosition;
          _holdTimer?.cancel();
          _holdTimer = Timer(const Duration(milliseconds: 350), () {
            if (_activePointers.length == 1) {
              _state.setInteraction(
                isDragging: false,
                isPetting: false,
                isPinching: false,
                isInflating: true,
                touchPosition: localPosition,
              );
            }
          });
        }

        _audioController.playPuni(_state.softness);

        if (_interactionMode == 'drag') {
          _state.setInteraction(
            isDragging: true,
            isPetting: false,
            touchPosition: localPosition,
          );
        } else {
          _state.setInteraction(
            isDragging: false,
            isPetting: true,
            touchPosition: localPosition,
          );
          _pettingStartTime = DateTime.now();
          final displayEnergy = double.parse(_state.energy.toStringAsFixed(1));
          if (displayEnergy < 0.2) {
            _state.triggerMood('angry', duration: const Duration(seconds: 2));
          } else {
            _state.triggerMood('happy', duration: const Duration(seconds: 2));
          }
        }
      } else {
        // Outside Puni -> check follow mode (intimacy >= 80%)
        _holdTimer?.cancel();
        _holdTimer = null;
        _holdStartPos = null;

        if (_state.intimacy >= 200.0) {
          _followStartPos = localPosition;
          _followTimer?.cancel();
          _followTimer = Timer(const Duration(seconds: 1), () {
            if (_activePointers.length == 1) {
              setState(() {
                _isFollowingFinger = true;
                _followTarget = localPosition;
              });
            }
          });
        }
      }
    }
  }

  void _handlePointerMove(PointerMoveEvent event) {
    if (_isShowingInterstitialAd) return;
    final RenderBox? renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    final localPosition = renderBox.globalToLocal(event.position);
    _activePointers[event.pointer] = localPosition;

    // ペコペコ時は1本指ドラッグのみ（touchPositionを更新してすぐ返す）
    if (_state.hunger <= 0.0) {
      if (_activePointers.length == 1 && _state.isDragging) {
        _state.setInteraction(
          isDragging: true,
          isPetting: false,
          touchPosition: localPosition,
        );
      }
      return;
    }

    if (_holdStartPos != null &&
        (localPosition - _holdStartPos!).distance > 15.0) {
      _holdTimer?.cancel();
      _holdTimer = null;
    }

    if (_followStartPos != null &&
        (localPosition - _followStartPos!).distance > 20.0 &&
        !_isFollowingFinger) {
      _followTimer?.cancel();
      _followTimer = null;
      _followStartPos = null;
    }

    if (_isFollowingFinger) {
      _followTarget = localPosition;
      if (Random().nextDouble() < 0.25) {
        final angle = Random().nextDouble() * 2 * pi;
        final speed = 20.0 + Random().nextDouble() * 30.0;
        _touchParticles.add(
          TouchParticle(
            position: localPosition,
            velocity: Offset(cos(angle) * speed, sin(angle) * speed),
            maxLife: 0.5 + Random().nextDouble() * 0.3,
            color: const Color(0xFF80D8FF), // Cyan tracking particles
            isBubble: true,
          ),
        );
      }
    } else if (_state.isInflating) {
      _state.setInteraction(
        isDragging: false,
        isPetting: false,
        isPinching: false,
        isInflating: true,
        touchPosition: localPosition,
      );

      if (Random().nextDouble() < 0.35) {
        final angle = Random().nextDouble() * 2 * pi;
        final speed = 30.0 + Random().nextDouble() * 50.0;
        _touchParticles.add(
          TouchParticle(
            position: localPosition,
            velocity: Offset(cos(angle) * speed, sin(angle) * speed),
            maxLife: 0.6 + Random().nextDouble() * 0.4,
            color: const Color(0xFF2ECC71), // Emerald Green leaf bubbles
            isBubble: true,
          ),
        );
      }
    } else if (_state.isPinching) {
      _audioController.playMuni(_state.softness);
      if (Random().nextDouble() < 0.35) {
        final angle = Random().nextDouble() * 2 * pi;
        final speed = 30.0 + Random().nextDouble() * 50.0;
        _touchParticles.add(
          TouchParticle(
            position: localPosition,
            velocity: Offset(cos(angle) * speed, sin(angle) * speed),
            maxLife: 0.6 + Random().nextDouble() * 0.4,
            color: const Color(0xFFFF2D55), // Blushing pink/red hearts
            isBubble: true,
          ),
        );
      }
    } else if (_state.isDragging || _state.isPetting) {
      _state.setInteraction(
        isDragging: _state.isDragging,
        isPetting: _state.isPetting,
        touchPosition: localPosition,
      );

      _audioController.playPuni(_state.softness);

      if (_interactionMode == 'pet' && localPosition != null) {
        if (Random().nextDouble() < 0.35) {
          final isHighIntimacy = _state.intimacy >= 60.0;
          final angle = Random().nextDouble() * 2 * pi;
          final speed = 30.0 + Random().nextDouble() * 50.0;
          _touchParticles.add(
            TouchParticle(
              position: localPosition,
              velocity: Offset(cos(angle) * speed, sin(angle) * speed),
              maxLife: 0.6 + Random().nextDouble() * 0.4,
              color: isHighIntimacy
                  ? const Color(0xFFFF2D55)
                  : const Color(0xFFFFD740),
              isBubble: isHighIntimacy,
            ),
          );
        }
      }
    }
  }

  void _handlePointerUp(PointerUpEvent event) {
    if (_state.mood == 'sleep') {
      _state.setMood('normal');
    }
    _timeSinceNoInteraction = 0.0;
    _activePointers.remove(event.pointer);

    _holdTimer?.cancel();
    _holdTimer = null;
    _holdStartPos = null;

    _followTimer?.cancel();
    _followTimer = null;
    _followStartPos = null;
    _followTarget = null;
    setState(() {
      _isFollowingFinger = false;
    });

    final wasDragging = _state.isDragging;
    final wasPetting = _state.isPetting;
    final wasPinching = _state.isPinching;
    final wasInflating = _state.isInflating;
    final displayEnergy = double.parse(_state.energy.toStringAsFixed(1));
    final hasEnergyAtRelease = (wasPinching || wasInflating)
        ? displayEnergy >= 1.0
        : (wasPetting ? displayEnergy >= 0.2 : displayEnergy > 0.0);

    if (_activePointers.length < 2 && wasPinching) {
      _initialPinchDistance = 0.0;
      _state.setInteraction(
        isDragging: false,
        isPetting: false,
        isPinching: false,
        isInflating: false,
        touchPosition: null,
      );
      _audioController.playPetEndVoice(hasEnergy: hasEnergyAtRelease);

      // ★つまみアクション終了
      _state.addGrowth(0.0, source: 'pinch');

      if (_state.energy < 1.0) {
        _state.triggerMood('sad', duration: const Duration(seconds: 3));
      } else {
        _state.triggerMood('happy', duration: const Duration(seconds: 3));
        _maybeDropCoin(_physics.center);
      }
    } else if (_activePointers.isEmpty) {
      bool didPlayFling = false;
      if (wasDragging) {
        if (_state.hunger <= 0.0) {
          _physics.centerVelocity = Offset.zero; // ペコペコ時は投げられない（落とすだけ）
        } else {
          double flingSpeed = _physics.centerVelocity.distance;
          if (flingSpeed > 320.0) {
            // 満腹度がMAX（肉5個、99.0以上）の時は投げた時の加速度（速度倍率）が上がる
            double multiplier = (_state.hunger >= 99.0) ? 1.45 : 1.2;
            _physics.centerVelocity = _physics.centerVelocity * multiplier;
            
            _audioController.playFlingVoice(hasEnergy: _state.energy >= 2.0);
            didPlayFling = true;

          bool hadEnergy = _state.energy >= 2.0;

          double targetIntimacy = (flingSpeed < 1700.0)
              ? 0.5
              : (flingSpeed >= 2300.0 ? 1.0 : 0.75);
          double targetExp = (flingSpeed < 1700.0)
              ? 50.0
              : (flingSpeed >= 2300.0 ? 150.0 : 100.0);

          _state.addGrowth(
            0.0,
            source: 'fling',
            customIntimacy: targetIntimacy,
            customExp: targetExp,
          );

          if (!hadEnergy) {
            _state.triggerMood('sad', duration: const Duration(seconds: 3));
          } else {
            _state.triggerMood(
              'surprised',
              duration: const Duration(seconds: 3),
            );
            _maybeDropCoin(_physics.center);
          }
          }
        }
      }
      _state.setInteraction(
        isDragging: false,
        isPetting: false,
        isPinching: false,
        isInflating: false,
        touchPosition: null,
      );

      if (wasPetting || wasInflating || (wasDragging && !didPlayFling)) {
        _audioController.playPetEndVoice(hasEnergy: hasEnergyAtRelease);
      }
      if (wasPetting) {
        // ★撫でるアクション終了
        if (_pettingStartTime != null) {
          final duration = DateTime.now().difference(_pettingStartTime!);
          if (duration.inMilliseconds >= 800) {
            _state.addGrowth(0.0, source: 'petting');
          }
        }
        _pettingStartTime = null;
      }
      if (wasInflating) {
        // ★巨大化アクション終了
        _state.addGrowth(0.0, source: 'balloon');
        if (_state.energy < 1.0) {
          _state.triggerMood('sad', duration: const Duration(seconds: 3));
        } else {
          _state.triggerMood('happy', duration: const Duration(seconds: 3));
          _maybeDropCoin(_physics.center);
        }
      }
    }
  }

  void _handlePointerCancel(PointerCancelEvent event) {
    _timeSinceNoInteraction = 0.0;
    _activePointers.remove(event.pointer);

    _holdTimer?.cancel();
    _holdTimer = null;
    _holdStartPos = null;

    _followTimer?.cancel();
    _followTimer = null;
    _followStartPos = null;
    _followTarget = null;
    setState(() {
      _isFollowingFinger = false;
    });

    final wasDragging = _state.isDragging;
    final wasPetting = _state.isPetting;
    final wasPinching = _state.isPinching;
    final wasInflating = _state.isInflating;
    final displayEnergy = double.parse(_state.energy.toStringAsFixed(1));
    final hasEnergyAtRelease = (wasPinching || wasInflating)
        ? displayEnergy >= 1.0
        : (wasPetting ? displayEnergy >= 0.2 : displayEnergy > 0.0);

    if (_activePointers.length < 2 && wasPinching) {
      _initialPinchDistance = 0.0;
      _state.setInteraction(
        isDragging: false,
        isPetting: false,
        isPinching: false,
        isInflating: false,
        touchPosition: null,
      );

      // つまみアクション中断時も加算処理を通す
      _state.addGrowth(0.0, source: 'pinch');

      _audioController.playPetEndVoice(hasEnergy: hasEnergyAtRelease);
    } else if (_activePointers.isEmpty) {
      _state.setInteraction(
        isDragging: false,
        isPetting: false,
        isPinching: false,
        isInflating: false,
        touchPosition: null,
      );

      if (wasPetting) {
        if (_pettingStartTime != null) {
          final duration = DateTime.now().difference(_pettingStartTime!);
          if (duration.inMilliseconds >= 800) {
            _state.addGrowth(0.0, source: 'petting');
          }
        }
        _pettingStartTime = null;
      } else if (wasInflating) {
        _state.addGrowth(0.0, source: 'balloon');
      }

      if (wasPetting || wasInflating || wasDragging) {
        _audioController.playPetEndVoice(hasEnergy: hasEnergyAtRelease);
      }
    }
  }

  void _spawnColoredFood(String foodType, Color foodColor) {
    final mediaSize = MediaQuery.of(context).size;
    final randomX = 40.0 + Random().nextDouble() * (mediaSize.width - 80.0);
    setState(() {
      _foodBubbles.add(
        FoodBubble(
          position: Offset(randomX, 30.0),
          velocity: const Offset(0, 60.0),
          foodType: foodType,
          color: foodColor,
        ),
      );
    });
  }

  void _openFoodShopSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final theme = Theme.of(context);
            final coins = _state.puniCoins;
            final remaining = _state.feedRemainingToday;

            final foods = [
              {
                'name': 'ふつうのご飯',
                'type': 'default',
                'cost': 0,
                'color': const Color(0xFF9E9E9E),
              },
              {
                'name': '赤のご飯',
                'type': 'red',
                'cost': 10,
                'color': const Color(0xFFFF2D55),
              },
              {
                'name': 'オレンジのご飯',
                'type': 'orange',
                'cost': 10,
                'color': const Color(0xFFFF9F0A),
              },
              {
                'name': '黄のご飯',
                'type': 'yellow',
                'cost': 10,
                'color': const Color(0xFFFFCC00),
              },
              {
                'name': '緑のご飯',
                'type': 'green',
                'cost': 10,
                'color': const Color(0xFF2ECC71),
              },
              {
                'name': '水色のご飯',
                'type': 'cyan',
                'cost': 10,
                'color': const Color(0xFF5AC8FA),
              },
              {
                'name': '青のご飯',
                'type': 'blue',
                'cost': 10,
                'color': const Color(0xFF007AFF),
              },
              {
                'name': '紫のご飯',
                'type': 'purple',
                'cost': 10,
                'color': const Color(0xFFAF52DE),
              },
              {
                'name': 'ピンクのご飯',
                'type': 'pink',
                'cost': 10,
                'color': const Color(0xFFFF2D85),
              },
              {
                'name': '色無くナール',
                'type': 'medicine_bleach',
                'cost': 50,
                'color': const Color(0x00FFFFFF), // 透明
                'requiredIntimacy': 250.0,
              },
              {
                'name': '薄くナール',
                'type': 'medicine_desaturate',
                'cost': 15,
                'color': const Color(0xFFE0E0E0),
                'requiredIntimacy': 300.0,
              },
            ];

            return Container(
              decoration: BoxDecoration(
                color: theme.scaffoldBackgroundColor.withOpacity(0.95),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(28),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.15),
                    blurRadius: 10,
                    spreadRadius: 2,
                  ),
                ],
              ),
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 40,
                    height: 5,
                    decoration: BoxDecoration(
                      color: Colors.grey.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  const SizedBox(height: 16),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'ごはんショップ',
                        style: GoogleFonts.notoSansJp(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: theme.textTheme.bodyLarge?.color,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFD700).withOpacity(0.15),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: const Color(0xFFFFD700).withOpacity(0.5),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const PuniCoinWidget(size: 18),
                            const SizedBox(width: 4),
                            Text(
                              '$coins',
                              style: GoogleFonts.notoSansJp(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: const Color(0xFFB8860B),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '今日の残りごはん回数: $remaining / ${CreatureState.maxFeedPerDay}',
                      style: GoogleFonts.notoSansJp(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: remaining > 0 ? Colors.green : Colors.red,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: foods.length,
                      itemBuilder: (context, index) {
                        final food = foods[index];
                        final name = food['name'] as String;
                        final type = food['type'] as String;
                        final cost = food['cost'] as int;
                        final color = food['color'] as Color;
                        final requiredIntimacy =
                            food.containsKey('requiredIntimacy')
                            ? food['requiredIntimacy'] as double
                            : 0.0;
                        final isLocked = _state.intimacy < requiredIntimacy;
                        final canAfford = coins >= cost;

                        return Card(
                          margin: const EdgeInsets.symmetric(vertical: 6),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                            side: BorderSide(
                              color: (type == 'medicine_bleach' || type == 'medicine_desaturate')
                                  ? Colors.black.withOpacity(0.8)
                                  : color.withOpacity(0.3),
                              width: 1.5,
                            ),
                          ),
                          color: (type == 'medicine_bleach' || type == 'medicine_desaturate')
                              ? Colors.black.withOpacity(0.05)
                              : color.withOpacity(0.05),
                          child: ListTile(
                            leading: type == 'medicine_bleach'
                                ? ClipOval(
                                    child: Image.asset(
                                      'assets/images/medicine_bleach.png',
                                      width: 32,
                                      height: 32,
                                      fit: BoxFit.cover,
                                    ),
                                  )
                                : type == 'medicine_desaturate'
                                ? ClipOval(
                                    child: Image.asset(
                                      'assets/images/medicine_desaturate.png',
                                      width: 32,
                                      height: 32,
                                      fit: BoxFit.cover,
                                    ),
                                  )
                                : Container(
                                    width: 32,
                                    height: 32,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: color,
                                      boxShadow: [
                                        BoxShadow(
                                          color: color.withOpacity(0.5),
                                          blurRadius: 6,
                                          spreadRadius: 1,
                                        ),
                                      ],
                                    ),
                                  ),
                            title: Text(
                              name,
                              style: GoogleFonts.notoSansJp(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            subtitle: Text(
                              type == 'default'
                                  ? '配合色に影響なし'
                                  : type == 'medicine_bleach'
                                  ? 'PUNIが初期の色にリセット'
                                  : type == 'medicine_desaturate'
                                  ? '色の濃さを少し落とします'
                                  : '${name.replaceAll('のご飯', '')}の配合色を少し増やす',
                              style: GoogleFonts.notoSansJp(fontSize: 11),
                            ),
                            trailing: isLocked
                                ? Padding(
                                    padding: const EdgeInsets.only(right: 8.0),
                                    child: Text(
                                      '🔒 ${requiredIntimacy.toInt()}ptで解放',
                                      style: GoogleFonts.notoSansJp(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.grey.shade600,
                                      ),
                                    ),
                                  )
                                : ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: canAfford
                                          ? color
                                          : Colors.grey,
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                      ),
                                    ),
                                    onPressed: () {
                                      if (_state.feedRemainingToday <= 0) {
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              '今日のご飯上限(15回)に達しました。',
                                              style: GoogleFonts.notoSansJp(
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                            backgroundColor:
                                                CupertinoColors.systemRed,
                                            behavior: SnackBarBehavior.floating,
                                          ),
                                        );
                                        Navigator.pop(context);
                                        return;
                                      }

                                      if (cost > 0 && !canAfford) {
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              'ぷにコインが足りません！',
                                              style: GoogleFonts.notoSansJp(
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                            backgroundColor:
                                                CupertinoColors.systemRed,
                                            behavior: SnackBarBehavior.floating,
                                          ),
                                        );
                                        return;
                                      }
                                      final success = _state
                                          .consumeFeedAction();
                                      if (success) {
                                        if (cost > 0) {
                                          _state.spendCoins(cost);
                                        }

                                        _spawnColoredFood(type, color);

                                        setModalState(() {});
                                        setState(() {});
                                      }
                                      Navigator.pop(context);
                                    },
                                    child: cost == 0
                                        ? Text(
                                            '無料',
                                            style: GoogleFonts.notoSansJp(
                                              fontWeight: FontWeight.bold,
                                            ),
                                          )
                                        : Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Text(
                                                '$cost',
                                                style: GoogleFonts.notoSansJp(
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                              const SizedBox(width: 4),
                                              const PuniCoinWidget(size: 14),
                                            ],
                                          ),
                                  ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _shareProfileCard() async {
    try {
      final boundary =
          _profileCardKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary == null) return;

      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;

      final buffer = byteData.buffer.asUint8List();
      final tempDir = await getTemporaryDirectory();
      final file = await File('${tempDir.path}/puni_profile_card.png').create();
      await file.writeAsBytes(buffer);

      await Share.shareXFiles([
        XFile(file.path),
      ], text: 'みんなのPUNIは何色？一緒に遊ぼう！\n#PUNI #ぷにぷに');
    } catch (e) {
      debugPrint('Error sharing profile card: $e');
    }
  }

  String _colorToHex(Color color) {
    return '#${color.value.toRadixString(16).substring(2).toUpperCase()}';
  }

  Widget _buildCardStatItem({
    IconData? icon,
    Widget? customIcon,
    required String label,
    required String value,
  }) {
    return Column(
      children: [
        customIcon ?? Icon(icon!, color: Colors.white, size: 24),
        const SizedBox(height: 4),
        Text(
          label,
          style: GoogleFonts.notoSansJp(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: Colors.white.withOpacity(0.8),
          ),
        ),
        Text(
          value,
          style: GoogleFonts.outfit(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      ],
    );
  }

  void _openProfileCardSheet() {
    final playerNameController = TextEditingController(text: _state.playerName);
    final puniNameController = TextEditingController(text: _state.puniName);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final theme = Theme.of(context);

            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
              ),
              child: Container(
                decoration: BoxDecoration(
                  color: theme.scaffoldBackgroundColor.withOpacity(0.95),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(28),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.15),
                      blurRadius: 10,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                padding: const EdgeInsets.all(24),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 40,
                        height: 5,
                        decoration: BoxDecoration(
                          color: Colors.grey.withOpacity(0.3),
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      const SizedBox(height: 16),

                      Text(
                        'プロフィールカード',
                        style: GoogleFonts.notoSansJp(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: theme.textTheme.bodyLarge?.color,
                        ),
                      ),
                      const SizedBox(height: 16),

                      ListenableBuilder(
                        listenable: _state,
                        builder: (context, _) {
                          return RepaintBoundary(
                            key: _profileCardKey,
                        child: AspectRatio(
                          aspectRatio: 1.7, // Widescreen ratio for sharing on X
                          child: Container(
                            width: double.infinity,
                            clipBehavior:
                                Clip.antiAlias, // Clip the rotated X child
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  _primaryColor.withOpacity(0.85),
                                  _secondaryColor.withOpacity(0.85),
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: [
                                BoxShadow(
                                  color: _primaryColor.withOpacity(0.4),
                                  blurRadius: 16,
                                  spreadRadius: 2,
                                ),
                              ],
                              border: Border.all(
                                color: Colors.white.withOpacity(0.3),
                                width: 1.5,
                              ),
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 14,
                            ),
                            child: Stack(
                              children: [
                                if (_state.selectedTitleId != null)
                                  Positioned(
                                    top: 8,
                                    right: 8,
                                    child: _buildBadgeWidget(
                                      TitleBadge.allBadges.firstWhere((b) => b.id == _state.selectedTitleId, orElse: () => TitleBadge.allBadges.first),
                                      size: 56,
                                    ),
                                  ),
                                // Cool slanted X background logo
                                Positioned(
                                  right: -25,
                                  bottom: -35,
                                  child: Transform.rotate(
                                    angle: 0.25,
                                    child: Opacity(
                                      opacity: 0.12,
                                      child: Text(
                                        'X',
                                        style: GoogleFonts.outfit(
                                          fontSize: 180,
                                          fontWeight: FontWeight.w900,
                                          color: Colors.white,
                                          height: 1.0,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Expanded(
                                      child: Row(
                                        children: [
                                          Container(
                                            width: 84,
                                            height: 84,
                                            decoration: BoxDecoration(
                                              color: Colors.white.withOpacity(
                                                0.18,
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(14),
                                              border: Border.all(
                                                color: Colors.white.withOpacity(
                                                  0.4,
                                                ),
                                                width: 1.8,
                                              ),
                                              boxShadow: [
                                                BoxShadow(
                                                  color: Colors.black
                                                      .withOpacity(0.08),
                                                  blurRadius: 6,
                                                  offset: const Offset(0, 2),
                                                ),
                                              ],
                                            ),
                                            child: ClipRRect(
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                              child: CustomPaint(
                                                painter: CreaturePreviewPainter(
                                                  primaryColor: _primaryColor,
                                                  secondaryColor:
                                                      _secondaryColor,
                                                  intimacy: _state.intimacy,
                                                ),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 14),

                                          Expanded(
                                            child: Padding(
                                              padding: const EdgeInsets.only(right: 64),
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                mainAxisAlignment:
                                                    MainAxisAlignment.center,
                                                children: [
                                                  Text(
                                                    _state.puniName,
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                  style: GoogleFonts.notoSansJp(
                                                    fontSize: 20,
                                                    fontWeight: FontWeight.bold,
                                                    color: Colors.white,
                                                    shadows: [
                                                      Shadow(
                                                        color: Colors.black
                                                            .withOpacity(0.3),
                                                        blurRadius: 4,
                                                        offset: const Offset(
                                                          1,
                                                          1,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                                const SizedBox(height: 2),
                                                Text(
                                                  'オーナー: ${_state.playerName}',
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                  style: GoogleFonts.notoSansJp(
                                                    fontSize: 13,
                                                    fontWeight: FontWeight.bold,
                                                    color: Colors.white
                                                        .withOpacity(0.9),
                                                    shadows: [
                                                      Shadow(
                                                        color: Colors.black
                                                            .withOpacity(0.3),
                                                        blurRadius: 4,
                                                        offset: const Offset(
                                                          1,
                                                          1,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                                const SizedBox(height: 6),
                                                Row(
                                                  children: [
                                                    Text(
                                                      '現在の色: ',
                                                      style:
                                                          GoogleFonts.notoSansJp(
                                                            fontSize: 10,
                                                            fontWeight:
                                                                FontWeight.bold,
                                                            color: Colors.white
                                                                .withOpacity(
                                                                  0.8,
                                                                ),
                                                          ),
                                                    ),
                                                    Container(
                                                      width: 10,
                                                      height: 10,
                                                      decoration: BoxDecoration(
                                                        color: _primaryColor,
                                                        shape: BoxShape.circle,
                                                        border: Border.all(
                                                          color: Colors.white,
                                                          width: 1,
                                                        ),
                                                      ),
                                                    ),
                                                    const SizedBox(width: 4),
                                                    Text(
                                                      _colorToHex(
                                                        _primaryColor,
                                                      ),
                                                      style: GoogleFonts.outfit(
                                                        fontSize: 10,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        color: Colors.white,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ],
                                            ),
                                           ),
                                          ),
                                        ],
                                      ),
                                    ),

                                    const SizedBox(height: 10),
                                    Divider(
                                      color: Colors.white.withOpacity(0.3),
                                      thickness: 1,
                                    ),
                                    const SizedBox(height: 8),
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceAround,
                                      children: [
                                        _buildCardStatItem(
                                          icon: Icons.star,
                                          label: 'LEVEL',
                                          value: '${_state.level}',
                                        ),
                                        _buildCardStatItem(
                                          icon: Icons.favorite,
                                          label: '親密度',
                                          value: '${(_state.intimacy).toStringAsFixed(2)}pt',
                                        ),
                                        _buildCardStatItem(
                                          customIcon: const PuniCoinWidget(
                                            size: 24,
                                          ),
                                          label: 'コイン',
                                          value: '${_state.puniCoins}',
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),


                      const SizedBox(height: 20),

                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () {
                            // 称号一覧を開く
                            _showTitleListSheet();
                          },
                          icon: const Icon(Icons.military_tech, color: Color(0xFFFFD700)),
                          label: Text(
                            '称号バッジ一覧・設定',
                            style: GoogleFonts.notoSansJp(fontWeight: FontWeight.bold),
                          ),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: puniNameController,
                        maxLength: 8,
                        decoration: InputDecoration(
                          labelText: 'PUNIの名前',
                          labelStyle: GoogleFonts.notoSansJp(),
                          prefixIcon: const Icon(Icons.pets),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          counterText: '',
                        ),
                        onChanged: (val) {
                          _state.setPuniName(val);
                          setModalState(() {});
                          setState(() {});
                        },
                      ),
                      const SizedBox(height: 16),

                      TextField(
                        controller: playerNameController,
                        maxLength: 8,
                        decoration: InputDecoration(
                          labelText: 'プレイヤーの名前',
                          labelStyle: GoogleFonts.notoSansJp(),
                          prefixIcon: const Icon(Icons.person),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          counterText: '',
                        ),
                        onChanged: (val) {
                          _state.setPlayerName(val);
                          setModalState(() {});
                          setState(() {});
                        },
                      ),

                      const SizedBox(height: 20),

                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF1DA1F2),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                              onPressed: _shareProfileCard,
                              icon: const Icon(Icons.share),
                              label: Text(
                                'Xでシェアする',
                                style: GoogleFonts.notoSansJp(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildBadgeWidget(TitleBadge badge, {double size = 40}) {
    Color borderColor;
    List<Color> gradientColors;
    double glowRadius = 0;
    
    Color baseColor = badge.color;

    switch (badge.tier) {
      case 1: // ブロンズ
        borderColor = const Color(0xFFCD7F32);
        gradientColors = [baseColor.withOpacity(0.8), const Color(0xFFA0522D)];
        break;
      case 2: // シルバー
        borderColor = const Color(0xFFC0C0C0);
        gradientColors = [baseColor.withOpacity(0.9), const Color(0xFFA9A9A9)];
        glowRadius = 2;
        break;
      case 3: // ゴールド
        borderColor = const Color(0xFFFFD700);
        gradientColors = [baseColor, const Color(0xFFDAA520)];
        glowRadius = 4;
        break;
      case 4: // プラチナ・ダイヤ
      default:
        borderColor = const Color(0xFFE5E4E2);
        gradientColors = [baseColor, const Color(0xFFFF69B4), const Color(0xFF8A2BE2)];
        glowRadius = 8;
        break;
    }

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: gradientColors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: borderColor, width: size * 0.05),
        boxShadow: glowRadius > 0 ? [
          BoxShadow(
            color: borderColor.withOpacity(0.6),
            blurRadius: glowRadius,
            spreadRadius: glowRadius * 0.5,
          )
        ] : null,
      ),
      child: Center(
        child: Icon(
          badge.icon,
          color: Colors.white,
          size: size * 0.55,
          shadows: [
            Shadow(color: Colors.black.withOpacity(0.5), blurRadius: 3, offset: const Offset(1, 1))
          ],
        ),
      ),
    );
  }

  void _showTitleListSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final theme = Theme.of(context);
            final unlockedList = _state.unlockedTitles;
            TitleBadge? selectedBadgeInfo;
            if (_state.selectedTitleId != null) {
              selectedBadgeInfo = TitleBadge.allBadges.firstWhere((b) => b.id == _state.selectedTitleId, orElse: () => TitleBadge.allBadges.first);
            }
            
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
              ),
              child: Container(
                height: MediaQuery.of(context).size.height * 0.7,
                decoration: BoxDecoration(
                  color: theme.scaffoldBackgroundColor.withOpacity(0.95),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 10, spreadRadius: 2),
                  ],
                ),
                padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
                child: Column(
                  children: [
                    Container(
                      width: 40,
                      height: 5,
                      decoration: BoxDecoration(
                        color: Colors.grey.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '称号バッジ一覧',
                          style: GoogleFonts.notoSansJp(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: theme.textTheme.bodyLarge?.color,
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                            _state.debugUnlockAllTitles();
                            setModalState(() {});
                            setState(() {});
                          },
                          child: const Text('全部解放(テスト)'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (selectedBadgeInfo != null)
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: _primaryColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: _primaryColor.withOpacity(0.5)),
                        ),
                        child: Row(
                          children: [
                            _buildBadgeWidget(selectedBadgeInfo, size: 40),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    selectedBadgeInfo.name,
                                    style: GoogleFonts.notoSansJp(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                      color: theme.textTheme.bodyLarge?.color,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    selectedBadgeInfo.description,
                                    style: GoogleFonts.notoSansJp(
                                      fontSize: 12,
                                      color: theme.textTheme.bodyLarge?.color?.withOpacity(0.8),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: GridView.builder(
                        physics: const BouncingScrollPhysics(),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          childAspectRatio: 0.8,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                        ),
                        itemCount: TitleBadge.allBadges.length,
                        itemBuilder: (context, index) {
                          final badge = TitleBadge.allBadges[index];
                          final isUnlocked = unlockedList.contains(badge.id);
                          final isSelected = _state.selectedTitleId == badge.id;
                          
                          return InkWell(
                            onTap: isUnlocked ? () {
                              _state.setSelectedTitle(isSelected ? null : badge.id);
                              setModalState(() {});
                              setState(() {}); // Updates the profile card in the background immediately
                            } : null,
                            borderRadius: BorderRadius.circular(16),
                            child: Container(
                              decoration: BoxDecoration(
                                color: isUnlocked
                                    ? (isSelected ? _primaryColor.withOpacity(0.1) : Colors.transparent)
                                    : Colors.grey.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: isSelected 
                                      ? _primaryColor 
                                      : (isUnlocked ? Colors.grey.withOpacity(0.3) : Colors.transparent),
                                  width: isSelected ? 2 : 1,
                                ),
                              ),
                              padding: const EdgeInsets.all(8),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Opacity(
                                    opacity: isUnlocked ? 1.0 : 0.3,
                                    child: isUnlocked 
                                      ? _buildBadgeWidget(badge, size: 48)
                                      : Container(
                                          width: 48,
                                          height: 48,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: Colors.grey.shade400,
                                          ),
                                          child: const Icon(Icons.lock, color: Colors.white, size: 24),
                                        ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    badge.name,
                                    textAlign: TextAlign.center,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.notoSansJp(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: isUnlocked ? theme.textTheme.bodyLarge?.color : Colors.grey,
                                      height: 1.1,
                                    ),
                                  ),
                                  if (isSelected) ...[
                                    const SizedBox(height: 4),
                                    const Icon(Icons.check_circle, color: Color(0xFFFF2A6D), size: 16),
                                  ],
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // Watch interstitial ad to Level Up
  void _watchAdToLevelUp() {
    if (_isShowingInterstitialAd || _isInterstitialAdLoading) return;

    final ad = _interstitialAd;
    if (ad == null) return;

    final consumed = _state.consumeAdLevelUpAction();
    if (!consumed) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '動画でコインGETは1日${CreatureState.maxAdLevelUpPerDay}回までです。',
            style: GoogleFonts.notoSansJp(fontWeight: FontWeight.bold),
          ),
          backgroundColor: CupertinoColors.systemRed,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() {
      _isShowingInterstitialAd = true;
      _interstitialAd = null;
    });

    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        debugPrint("Interstitial ad dismissed.");
        ad.dispose();
        if (mounted) {
          setState(() {
            _isShowingInterstitialAd = false;
          });
        }
        _grantAdLevelUpResult();
        _loadInterstitialAd();
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        debugPrint("Interstitial ad failed to show: $error");
        ad.dispose();
        if (mounted) {
          setState(() {
            _isShowingInterstitialAd = false;
          });
        }
        _grantAdLevelUpResult();
        _loadInterstitialAd();
      },
    );
    ad.show();
  }

  void _grantAdLevelUpResult() {
    _state.rewardAdCoins();
    // Drop coin particles
    _maybeDropCoin(_physics.center);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '動画視聴特典！25ぷにコインを獲得しました！',
            style: GoogleFonts.notoSansJp(
              fontWeight: FontWeight.bold,
              color: Colors.black,
            ),
          ),
          backgroundColor: const Color(0xFFFFD700),
          behavior: SnackBarBehavior.floating,
        ),
      );
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
    if (_isInterstitialAdLoading) return;
    setState(() {
      _isInterstitialAdLoading = true;
    });

    InterstitialAd.load(
      adUnitId: _interstitialAdUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          debugPrint("InterstitialAd loaded successfully.");
          if (mounted) {
            setState(() {
              _interstitialAd = ad;
              _isInterstitialAdLoading = false;
            });
          } else {
            ad.dispose();
          }
        },
        onAdFailedToLoad: (error) {
          debugPrint("InterstitialAd failed to load: $error");
          if (mounted) {
            setState(() {
              _interstitialAd = null;
              _isInterstitialAdLoading = false;
            });
            Future.delayed(const Duration(seconds: 15), () {
              if (mounted &&
                  _interstitialAd == null &&
                  !_isInterstitialAdLoading) {
                _loadInterstitialAd();
              }
            });
          }
        },
      ),
    );
  }

  void _showEnergyRecoveryGuideDialog() {
    showDialog(
      context: context,
      builder: (ctx) {
        final textThemeColor = const Color(0xFF2C3E50);

        Widget buildSectionTitle(String title, IconData icon, Color iconColor) {
          return Row(
            children: [
              Icon(icon, color: iconColor, size: 20),
              const SizedBox(width: 8),
              Text(
                title,
                style: GoogleFonts.notoSansJp(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: textThemeColor,
                ),
              ),
            ],
          );
        }

        Widget buildCard(Widget child) {
          return Container(
            margin: const EdgeInsets.only(top: 8, bottom: 16),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.withOpacity(0.15)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.02),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: child,
          );
        }

        return Dialog(
          backgroundColor: const Color(0xFFF8F9FA),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 24,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'PUNIのあそびかた説明書',
                    style: GoogleFonts.notoSansJp(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: textThemeColor,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const Divider(height: 16),
                  Flexible(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Section 1: Recovery
                          buildSectionTitle(
                            'エネルギーの回復',
                            Icons.bolt,
                            const Color(0xFFFFCC00),
                          ),
                          buildCard(
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Icon(
                                      Icons.directions_walk,
                                      size: 16,
                                      color: Colors.green,
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        '散歩: 今日の歩数同期 (1歩 ＝ +0.02)',
                                        style: GoogleFonts.notoSansJp(
                                          fontSize: 12,
                                          color: textThemeColor,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    const Icon(
                                      Icons.power,
                                      size: 16,
                                      color: Colors.blue,
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        '充電: 放置または起動中 (1分 ＝ +0.5)',
                                        style: GoogleFonts.notoSansJp(
                                          fontSize: 12,
                                          color: textThemeColor,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  '※ ぷにエネルギーの上限は 100 です。エネルギーを消費してお世話するとPUNIが成長しレベルアップします。',
                                  style: GoogleFonts.notoSansJp(
                                    fontSize: 11,
                                    color: Colors.grey[600],
                                  ),
                                ),
                              ],
                            ),
                          ),

                          // Section 2: Play & Unlock
                          buildSectionTitle(
                            'PUNIとの触れ合い・遊び方',
                            Icons.emoji_emotions,
                            const Color(0xFFFF8DA1),
                          ),
                          buildCard(
                            Column(
                              children: [
                                _buildPlayRow(
                                  'なでる',
                                  'PUNIをなぞると気持ちよさそうにします。',
                                  '初期解放',
                                  true,
                                  textThemeColor,
                                ),
                                const Divider(height: 12),
                                _buildPlayRow(
                                  '投げる',
                                  'スワイプして投げると弾んで喜びます。',
                                  '初期解放',
                                  true,
                                  textThemeColor,
                                ),
                                const Divider(height: 12),
                                _buildPlayRow(
                                  '二本指つまみ',
                                  '2本指でつまんで引っ張り、離すと喜びます。',
                                  '親密度 100ptで解放', // ★ 40% ➔ 100%
                                  _state.intimacy >= 100.0,
                                  textThemeColor,
                                ),
                                const Divider(height: 12),
                                _buildPlayRow(
                                  '長押し巨大化',
                                  '1本指で長押しすると一時的に巨大化します。',
                                  '親密度 150ptで解放', // ★ 60% ➔ 150%
                                  _state.intimacy >= 150.0,
                                  textThemeColor,
                                ),
                                const Divider(height: 12),
                                _buildPlayRow(
                                  'タップ追従',
                                  '空き地を1秒間長押しすると指へ這い寄ります。',
                                  '親密度 200ptで解放', // ★ 80% ➔ 200%
                                  _state.intimacy >= 200.0,
                                  textThemeColor,
                                ),
                              ],
                            ),
                          ),

                          // Section 3: Colors
                          buildSectionTitle(
                            '色の育て方とごはん',
                            Icons.palette,
                            const Color(0xFF9B59B6),
                          ),
                          buildCard(
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '・ショップのご飯は親密度に関わらずいつでも食べられます！食べるとその色に徐々に変化します。\n・なでる・遊ぶなどの通常のお世話では色は変化しません。\n・「色ロック（親密度50ptで解放）」を有効にしている間は、ご飯を食べても今の色を綺麗にキープできます。',
                                  style: GoogleFonts.notoSansJp(
                                    fontSize: 12,
                                    color: textThemeColor,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  children: [
                                    _buildColorTag(
                                      'ふつうのご飯',
                                      const Color(0xFF9E9E9E),
                                      textThemeColor,
                                    ),
                                    _buildColorTag(
                                      '赤のご飯',
                                      const Color(0xFFFF2D55),
                                      textThemeColor,
                                    ),
                                    _buildColorTag(
                                      'オレンジのご飯',
                                      const Color(0xFFFF9F0A),
                                      textThemeColor,
                                    ),
                                    _buildColorTag(
                                      '黄のご飯',
                                      const Color(0xFFFFCC00),
                                      textThemeColor,
                                    ),
                                    _buildColorTag(
                                      '緑のご飯',
                                      const Color(0xFF2ECC71),
                                      textThemeColor,
                                    ),
                                    _buildColorTag(
                                      '水色のご飯',
                                      const Color(0xFF5AC8FA),
                                      textThemeColor,
                                    ),
                                    _buildColorTag(
                                      '青のご飯',
                                      const Color(0xFF007AFF),
                                      textThemeColor,
                                    ),
                                    _buildColorTag(
                                      '紫のご飯',
                                      const Color(0xFFAF52DE),
                                      textThemeColor,
                                    ),
                                    _buildColorTag(
                                      'ピンクのご飯',
                                      const Color(0xFFFF2D85),
                                      textThemeColor,
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.black,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: () => Navigator.pop(ctx),
                    child: Text(
                      'とじる',
                      style: GoogleFonts.notoSansJp(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildPlayRow(
    String name,
    String desc,
    String condition,
    bool isUnlocked,
    Color textColor,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    name,
                    style: GoogleFonts.notoSansJp(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: isUnlocked ? textColor : Colors.grey,
                    ),
                  ),
                  const SizedBox(width: 6),
                  if (!isUnlocked)
                    const Icon(Icons.lock, size: 12, color: Colors.grey)
                  else
                    const Icon(
                      Icons.check_circle,
                      size: 12,
                      color: Colors.green,
                    ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                desc,
                style: GoogleFonts.notoSansJp(
                  fontSize: 11,
                  color: isUnlocked ? textColor.withOpacity(0.7) : Colors.grey,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: isUnlocked
                ? Colors.green.withOpacity(0.1)
                : Colors.grey.withOpacity(0.1),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            isUnlocked ? '解放済' : condition,
            style: GoogleFonts.notoSansJp(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: isUnlocked ? Colors.green : Colors.grey[700],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildColorTag(String label, Color color, Color textColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.4), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: GoogleFonts.notoSansJp(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: textColor,
            ),
          ),
        ],
      ),
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
                  } else if (Platform.isIOS) {
                    await openAppSettings();
                    _pendingHealthSyncOnResume = true;
                  }
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        Platform.isAndroid
                            ? 'Health Connect を開きました。PUNI の歩数を許可して戻ると自動同期します。'
                            : '設定アプリを開きました。PUNI のヘルスケア許可（歩数）をオンにして戻ると自動同期します。',
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

    if (Platform.isIOS) {
      // iOS needs a short delay for HealthKit to propagate permission updates and allow database reading.
      await Future.delayed(const Duration(milliseconds: 600));
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

      if (Platform.isIOS && totalSteps == 0) {
        // If today's steps is 0 on iOS, check the past 30 days to distinguish
        // between "really walked 0 steps today" and "permission denied".
        final startOf30DaysAgo = now.subtract(const Duration(days: 30));
        final historicalSteps = await _health.getTotalStepsInInterval(
          startOf30DaysAgo,
          now,
        );
        if (historicalSteps == null || historicalSteps == 0) {
          // If 30 days history also returns 0, it is highly likely that permissions are denied.
          return const _HealthFetchResult.failure('ヘルスケアの歩数アクセスが許可されていません。');
        }
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

    // ★修正：_state.isRainbowのチェックを削除し、時間帯によるグラデーションのみにする
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
      // 夜間：夜らしい落ち着いた色合いにするか、引き続きライトな色にするかは自由です
      return const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFFE3F2FD), Color(0xFFF3E5F5)],
      );
    }
  }

  Color _getTextColor() {
    // ★修正：isRainbow の判定を削除し、常にメインの文字色を返すようにしました
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

  String? _getNextIntimacyEventText() {
    final intimacy = _state.intimacy;
    if (intimacy < 50 && intimacy >= 45) return 'もう少しで【色ロック】解放…！';
    if (intimacy < 100 && intimacy >= 95) return 'もう少しで【二本指つまみ】を覚えそう…！';
    if (intimacy < 150 && intimacy >= 145) return 'もう少しで【長押し巨大化】を覚えそう…！';
    if (intimacy < 200 && intimacy >= 195) return 'もう少しで【タップ追従】を覚えそう…！';
    if (intimacy < 250 && intimacy >= 245) return 'もう少しで【色無くナール】が入荷しそう…！';
    if (intimacy < 300 && intimacy >= 295) return 'もう少しで【薄くナール】が入荷しそう…！';
    if (intimacy < 350 && intimacy >= 345) return 'もう少しでPUNIの体が光りだすかも…！';
    return null;
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

      final needsSync =
          _pendingHealthSyncOnResume ||
          _lastHealthSyncSucceeded != true ||
          _lastHealthSyncPermissionDenied;

      if (needsSync && !_isHealthSyncing) {
        _pendingHealthSyncOnResume = false;
        Future.delayed(const Duration(milliseconds: 600), () async {
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

    // スライムの相対位置を計算
    final screenWidth = media.size.width;
    final screenHeight = media.size.height;

    final double relativeX = screenWidth > 0
        ? (_physics.center.dx / screenWidth).clamp(0.0, 1.0)
        : 0.5;
    final double relativeY = screenHeight > 0
        ? (_physics.center.dy / screenHeight).clamp(0.0, 1.0)
        : 0.5;

    final slimeAlignment = FractionalOffset(relativeX, relativeY);

    return Scaffold(
      // ★Scaffoldの直下は通常のStackにして、ボタンが拡大されないようにします
      body: Stack(
        children: [
          // ーーー 【拡大するエリア】ここから ーーー
          Positioned.fill(
            child: AnimatedScale(
              scale: _interactionMode == 'pet' ? 2.5 : 1.0,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutCubic,
              alignment: slimeAlignment,
              child: Stack(
                children: [
                  // 1. Dynamic Background
                  AnimatedContainer(
                    duration: const Duration(seconds: 2),
                    decoration: BoxDecoration(
                      gradient: _getBackgroundGradient(),
                    ),
                  ),

                  // 2. Main Painter Area
                  Positioned.fill(
                    child: Listener(
                      onPointerDown: _handlePointerDown,
                      onPointerMove: _handlePointerMove,
                      onPointerUp: _handlePointerUp,
                      onPointerCancel: _handlePointerCancel,
                      child: CustomPaint(
                        painter: CreaturePainter(
                          physics: _physics,
                          renderScale: _inflationScale,
                          mood: _state.mood,
                          shape: _state.shape,
                          softness: _state.softness,
                          energy: _state.energy,
                          primaryColor: _primaryColor,
                          secondaryColor: _secondaryColor,
                          touchPosition: _state.touchPosition,
                          isBlinking: _isBlinking,
                          isCharging: _isCharging,
                          isPetting: _state.isPetting,
                          isPinching: _state.isPinching,
                          isInflating: _state.isInflating,
                          intimacy: _state.intimacy,
                          isColorLocked: _state.isColorLocked,
                          touchParticles: _touchParticles,
                          isFollowing: _isFollowingFinger,
                          followTarget: _followTarget,
                          hunger: _state.hunger,
                          isDragging: _state.isDragging,
                        ),
                        child: Container(),
                      ),
                    ),
                  ),

                  // レベルアップのエフェクト
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

                  // 3. Food Particle Renderer（ご飯の粒）
                  ..._foodBubbles.map((bubble) {
                    return Positioned(
                      left: bubble.position.dx - bubble.radius,
                      top: bubble.position.dy - bubble.radius,
                      child:
                          bubble.foodType == 'medicine_bleach' ||
                              bubble.foodType == 'medicine_desaturate'
                          ? ClipOval(
                              child: Image.asset(
                                bubble.foodType == 'medicine_bleach'
                                    ? 'assets/images/medicine_bleach.png'
                                    : 'assets/images/medicine_desaturate.png',
                                width: bubble.radius * 2,
                                height: bubble.radius * 2,
                                fit: BoxFit.cover,
                              ),
                            )
                          : Container(
                              width: bubble.radius * 2,
                              height: bubble.radius * 2,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: RadialGradient(
                                  colors: [
                                    Colors.white,
                                    bubble.color.withOpacity(0.85),
                                  ],
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: bubble.color.withOpacity(0.4),
                                    blurRadius: 4,
                                  ),
                                ],
                              ),
                            ),
                    );
                  }),
                ],
              ),
            ),
          ),
          // ーーー 【拡大するエリア】ここまで ーーー

          // ーーー 【拡大しないエリア】UIやボタンは通常のサイズをキープ ーーー

          // 4. Top HUD（画面上のステータス等）
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
                            Row(
                              children: [
                                GestureDetector(
                                  onTap: _openProfileCardSheet,
                                  child: Container(
                                    clipBehavior: Clip.antiAlias,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 8,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.black,
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: Colors.white.withOpacity(0.2),
                                        width: 1.0,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withOpacity(0.15),
                                          blurRadius: 6,
                                          offset: const Offset(0, 2),
                                        ),
                                      ],
                                    ),
                                    child: Stack(
                                      clipBehavior: Clip.none,
                                      children: [
                                        Positioned(
                                          right: -8,
                                          bottom: -22,
                                          child: Transform.rotate(
                                            angle: 0.25,
                                            child: Opacity(
                                              opacity: 0.15,
                                              child: Text(
                                                'X',
                                                style: GoogleFonts.outfit(
                                                  fontSize: 54,
                                                  fontWeight: FontWeight.w900,
                                                  color: Colors.white,
                                                  height: 1.0,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(
                                              Icons.account_circle_outlined,
                                              color: Colors.white,
                                              size: 26,
                                            ),
                                            const SizedBox(width: 8),
                                            Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Container(
                                                  constraints: const BoxConstraints(maxWidth: 80),
                                                  child: Text(
                                                    _state.puniName,
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                    style: GoogleFonts.notoSansJp(
                                                      fontSize: 15,
                                                      fontWeight: FontWeight.bold,
                                                      color: Colors.white,
                                                      height: 1.2,
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(height: 2),
                                                Text(
                                                  "Lv ${_state.level}",
                                                  style: GoogleFonts.outfit(
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.bold,
                                                    color: Colors.white
                                                        .withOpacity(0.8),
                                                    height: 1.2,
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(width: 8),
                                            Icon(
                                              Icons.chevron_right_rounded,
                                              color: Colors.white.withOpacity(
                                                0.6,
                                              ),
                                              size: 18,
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                CupertinoButton(
                                  padding: EdgeInsets.zero,
                                  minSize: 24,
                                  onPressed: () {
                                    if (_state.intimacy < 50.0) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            '親密度が50pt以上で色ロック機能が解放されます。',
                                            style: GoogleFonts.notoSansJp(
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          backgroundColor:
                                              CupertinoColors.systemGrey,
                                          behavior: SnackBarBehavior.floating,
                                        ),
                                      );
                                      return;
                                    }
                                    _state.toggleColorLock();
                                  },
                                  child: _buildLockIcon(textThemeColor),
                                ),
                              ],
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
                            const SizedBox(height: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
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
                                    size: 12,
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
                            const SizedBox(height: 6),
                            // ぷにコイン表示
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const PuniCoinWidget(size: 20),
                                const SizedBox(width: 4),
                                Text(
                                  '${_state.puniCoins}',
                                  style: GoogleFonts.notoSansJp(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.amber.shade700,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        const Icon(
                          Icons.star,
                          color: Color(0xFFFFD700),
                          size: 16,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          "レベル進捗: ${_state.exp.round()}/${_state.requiredExp.round()}",
                          style: GoogleFonts.notoSansJp(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: textThemeColor,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Stack(
                        children: [
                          Container(
                            height: 8,
                            color: textThemeColor == Colors.white
                                ? Colors.white.withOpacity(0.15)
                                : Colors.black.withOpacity(0.05),
                          ),
                          AnimatedFractionallySizedBox(
                            duration: const Duration(milliseconds: 250),
                            widthFactor: (_state.exp / _state.requiredExp)
                                .clamp(0.0, 1.0),
                            child: Container(
                              height: 8,
                              decoration: const BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    Color(0xFF2F80ED),
                                    Color(0xFF56CCF2),
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
                      children: [
                        const Icon(
                          Icons.bolt,
                          color: Color(0xFF27AE60),
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
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Stack(
                        children: [
                          Container(
                            height: 8,
                            color: textThemeColor == Colors.white
                                ? Colors.white.withOpacity(0.15)
                                : Colors.black.withOpacity(0.05),
                          ),
                          AnimatedFractionallySizedBox(
                            duration: const Duration(milliseconds: 250),
                            widthFactor: (_state.energy / 100.0).clamp(
                              0.0,
                              1.0,
                            ),
                            child: Container(
                              height: 8,
                              decoration: const BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    Color(0xFF27AE60),
                                    Color(0xFF11998E),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.favorite,
                              color: Color(0xFFEC4899),
                              size: 16,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              "親密度: ${(_state.intimacy).toStringAsFixed(2)} pt",
                              style: GoogleFonts.notoSansJp(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: textThemeColor,
                              ),
                            ),
                            if (_getNextIntimacyEventText() != null) ...[
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _getNextIntimacyEventText()!,
                                  style: GoogleFonts.notoSansJp(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: const Color(0xFFEC4899),
                                  ),
                                  overflow: TextOverflow.visible,
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Icon(
                              Icons.restaurant,
                              color: Colors.orange,
                              size: 16,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              "満腹度:",
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: textThemeColor,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Row(
                              children: List.generate(5, (index) {
                                // 左から回復、右から減少するゲージ
                                // index=0が左端(最初に満たされる), index=4が右端
                                double meatThreshold = index * 20.0;
                                double fillRatio = (_state.hunger - meatThreshold).clamp(0.0, 20.0) / 20.0;
                                
                                return Stack(
                                  children: [
                                    // 背景（空のゲージ）：グレーアウト＆少し薄く
                                    ColorFiltered(
                                      colorFilter: const ColorFilter.matrix(<double>[
                                        0.2126, 0.7152, 0.0722, 0, 0,
                                        0.2126, 0.7152, 0.0722, 0, 0,
                                        0.2126, 0.7152, 0.0722, 0, 0,
                                        0,      0,      0,      1, 0,
                                      ]),
                                      child: Opacity(
                                        opacity: 0.3,
                                        child: const Text(
                                          '🍖',
                                          style: TextStyle(fontSize: 14),
                                        ),
                                      ),
                                    ),
                                    // 手前（現在の満腹度）：fillRatioに応じて左から右へクリップされる
                                    if (fillRatio > 0.0)
                                      ClipRect(
                                        child: Align(
                                          alignment: Alignment.centerLeft,
                                          widthFactor: fillRatio,
                                          child: const Text(
                                            '🍖',
                                            style: TextStyle(fontSize: 14),
                                          ),
                                        ),
                                      ),
                                  ],
                                );
                              }),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    /*
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
                                                  ? Colors.white.withOpacity(0.1)
                                                  : Colors.black.withOpacity(0.05)),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: isCurrent
                                              ? Colors.transparent
                                              : (textThemeColor == Colors.white
                                                    ? Colors.white.withOpacity(0.1)
                                                    : Colors.black.withOpacity(0.1)),
                                          width: 1,
                                        ),
                                      ),
                                      child: Text(
                                        "Lv$lv",
                                        style: GoogleFonts.outfit(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: isCurrent ? Colors.white : textThemeColor,
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
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          "テスト用親密度変更:",
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
                              children: [0, 50, 100, 150, 200, 250, 300, 350]
                                  .map((intimacyValue) {
                                    final intimacy = intimacyValue.toDouble();
                                    final isCurrent =
                                        (_state.intimacy - intimacy).abs() < 0.1;
                                    return Padding(
                                      padding: const EdgeInsets.only(left: 4),
                                      child: InkWell(
                                        onTap: () => _state.debugSetIntimacy(intimacy),
                                        borderRadius: BorderRadius.circular(12),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 4,
                                          ),
                                          decoration: BoxDecoration(
                                            color: isCurrent
                                                ? const Color(0xFFFF2D55)
                                                : (textThemeColor == Colors.white
                                                      ? Colors.white.withOpacity(0.1)
                                                      : Colors.black.withOpacity(0.05)),
                                            borderRadius: BorderRadius.circular(12),
                                            border: Border.all(
                                              color: isCurrent
                                                  ? Colors.transparent
                                                  : (textThemeColor == Colors.white
                                                        ? Colors.white.withOpacity(0.1)
                                                        : Colors.black.withOpacity(0.1)),
                                              width: 1,
                                            ),
                                          ),
                                          child: Text(
                                            "$intimacyValue pt",
                                            style: GoogleFonts.outfit(
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                              color: isCurrent ? Colors.white : textThemeColor,
                                            ),
                                          ),
                                        ),
                                      ),
                                    );
                                  })
                                  .toList(),
                            ),
                          ),
                        ),
                      ],
                    ),
                    */
                  ],
                ),
              ),
            ),
          ),

          // 6. Bottom Panels（画面下のボタン・広告エリア）
          Positioned(
            bottom: media.padding.bottom + 12,
            left: 20,
            right: 20,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
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
                          onPressed: _openFoodShopSheet,
                        ),
                        _buildActionButton(
                          icon: Icons.play_circle_filled,
                          label: "動画でコインGET",
                          subtitle: _state.adLevelUpRemainingToday <= 0
                              ? '残り 0/${CreatureState.maxAdLevelUpPerDay}'
                              : (_isInterstitialAdLoading
                                    ? '読み込み中...'
                                    : (_interstitialAd == null
                                          ? '準備中...'
                                          : '残り ${_state.adLevelUpRemainingToday}/${CreatureState.maxAdLevelUpPerDay}')),
                          isActive: true,
                          isEnabled:
                              _state.adLevelUpRemainingToday > 0 &&
                              _interstitialAd != null &&
                              !_isShowingInterstitialAd &&
                              !_isInterstitialAdLoading,
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
                _buildBannerAd(textThemeColor),
              ],
            ),
          ),
          // デバッグ用満腹度ボタン（コメントアウト）
          /*
          Positioned(
            top: 40,
            right: 16,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                ElevatedButton(
                  onPressed: () => _state.setHunger(0.0),
                  child: const Text('Hunger 0%', style: TextStyle(color: Colors.black)),
                ),
                ElevatedButton(
                  onPressed: () => _state.setHunger(60.0),
                  child: const Text('Hunger 60%', style: TextStyle(color: Colors.black)),
                ),
                ElevatedButton(
                  onPressed: () => _state.setHunger(100.0),
                  child: const Text('Hunger Max', style: TextStyle(color: Colors.black)),
                ),
              ],
            ),
          ),
          */
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

  Widget _buildLockIcon(Color textThemeColor) {
    final intimacy = _state.intimacy;
    final isLocked = _state.isColorLocked;

    if (intimacy < 20.0) {
      return Icon(
        CupertinoIcons.lock_open_fill,
        color: textThemeColor.withOpacity(0.25),
        size: 18,
      );
    }

    if (!isLocked) {
      return Icon(
        CupertinoIcons.lock_open_fill,
        color: textThemeColor.withOpacity(0.6),
        size: 18,
      );
    }

    final iconColor = _state.creatureColor;
    final shadows = [
      BoxShadow(
        color: iconColor.withOpacity(0.8),
        blurRadius: 8.0,
        spreadRadius: 2.0,
      ),
    ];

    return Container(
      decoration: BoxDecoration(shape: BoxShape.circle, boxShadow: shadows),
      child: Icon(CupertinoIcons.lock_fill, color: iconColor, size: 18),
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

class TouchParticle {
  Offset position;
  Offset velocity;
  double life;
  final double maxLife;
  final Color color;
  final bool isBubble;
  final bool isCoin;
  final bool isSpeedUp;

  TouchParticle({
    required this.position,
    required this.velocity,
    required this.maxLife,
    required this.color,
    required this.isBubble,
    this.isCoin = false,
    this.isSpeedUp = false,
    this.sizeMultiplier = 1.0,
  }) : life = maxLife;

  final double sizeMultiplier;

  void update(double dt) {
    position += velocity * dt;
    if (isCoin) {
      velocity += const Offset(0, 420.0) * dt;
      velocity *= 0.98;
    } else {
      velocity += const Offset(0, -50.0) * dt;
      velocity *= 0.94;
    }
    life -= dt;
  }
}

class PuniCoinWidget extends StatelessWidget {
  final double size;

  const PuniCoinWidget({Key? key, this.size = 16.0}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: const Color(0xFFFFD700),
        shape: BoxShape.circle,
        border: Border.all(color: const Color(0xFFDAA520), width: size * 0.08),
      ),
      child: Center(
        child: Text(
          'c',
          style: TextStyle(
            color: const Color(0xFF8B6508),
            fontSize: size * 0.62,
            fontWeight: FontWeight.bold,
            fontFamily: 'Outfit',
            height: 0.95,
          ),
        ),
      ),
    );
  }
}
