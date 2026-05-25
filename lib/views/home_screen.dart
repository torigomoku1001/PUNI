import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:battery_plus/battery_plus.dart';
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

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  late final PuniPhysics _physics;
  late final CreatureState _state;
  late final AudioController _audioController;

  // Game Loop
  late final AnimationController _gameLoopController;
  double _lastElapsedTime = 0.0;

  // Interactive gravity & Pedometer
  Offset _gravity = const Offset(0, 480);
  StreamSubscription? _accelerometerSub;
  double _prevMagnitude = 9.8;
  DateTime _lastStepTime = DateTime.now();

  // Battery monitoring for charging state
  final Battery _battery = Battery();
  bool _isCharging = false;
  StreamSubscription<BatteryState>? _batterySub;

  // Idle movement timers
  double _timeSinceLastJump = 0.0;
  bool _wasFlungByUser = false;

  // Interactive touch mode: 'drag' or 'pet'
  String _interactionMode = 'drag';

  // Food bubbles
  final List<FoodBubble> _foodBubbles = [];

  // Puni Colors (Peach / Rose base)
  Color _primaryColor = const Color(0xFFD2D2D8);
  Color _secondaryColor = const Color(0xFF8E8E93);

  // Eye blinking state
  bool _isBlinking = false;
  Timer? _blinkTimer;

  // Ad simulation states
  bool _showInterstitialAd = false;
  int _adCountdown = 4;
  Timer? _adTimer;

  @override
  void initState() {
    super.initState();
    _physics = PuniPhysics();
    _state = CreatureState();
    _audioController = AudioController();

    _state.addListener(_onStateChange);

    // Initialize 60fps physics game loop
    _gameLoopController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..addListener(_tickPhysics);
    _gameLoopController.repeat();

    // 1. Pedometer & Tilt Gravity (Pure-Dart Accelerometer)
    _accelerometerSub = accelerometerEventStream().listen(
      (AccelerometerEvent event) {
        // Step counter peak detection
        double magnitude = sqrt(
          event.x * event.x + event.y * event.y + event.z * event.z,
        );
        if (magnitude > 12.2 && _prevMagnitude <= 12.2) {
          DateTime now = DateTime.now();
          if (now.difference(_lastStepTime).inMilliseconds > 360) {
            _state.addSteps(1);
            _lastStepTime = now;

            // Downward squash impulse upon stepping
            for (int i = 0; i < PuniPhysics.nodeCount; i++) {
              double angle = i * 2 * pi / PuniPhysics.nodeCount;
              _physics.nodeVelocities[i] += Offset(
                cos(angle) * 35.0,
                sin(angle) * 75.0 + 35.0,
              );
            }
          }
        }
        _prevMagnitude = magnitude;

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

    _startBlinkCycle();
  }

  void _onStateChange() {
    if (!_state.isRainbow) {
      setState(() {
        _primaryColor = _state.creatureColor;
        _secondaryColor = _state.creatureColor.withOpacity(0.7);
      });
    }
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
        _audioController.playBoyo(_state.softness);
        _state.triggerMood('happy', duration: const Duration(seconds: 2));
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

    // Detect high-impact wall/floor collision to trigger 'sad' pain expression
    final speed = _physics.centerVelocity.distance;
    if (speed > 220.0 && !_state.isDragging) {
      double leftBoundary = 20.0 + PuniPhysics.baseRadius;
      double rightBoundary = boundarySize.width - 20.0 - PuniPhysics.baseRadius;
      double bottomBoundary =
          boundarySize.height - 20.0 - PuniPhysics.baseRadius - 190.0;

      bool hitWall =
          (_physics.center.dx <= leftBoundary + 8.0) ||
          (_physics.center.dx >= rightBoundary - 8.0);
      bool hitFloor = (_physics.center.dy >= bottomBoundary - 8.0);

      if (hitWall || hitFloor) {
        if (_wasFlungByUser) {
          // Thrown by user: painful look!
          _state.triggerMood(
            'sad',
            duration: const Duration(milliseconds: 1500),
          );
        } else {
          // Autonomous jump/hop: happy / excited look!
          _state.triggerMood(
            'happy',
            duration: const Duration(milliseconds: 1000),
          );
        }
        _audioController.playBoyo(_state.softness); // Extra bounce feedback
        _wasFlungByUser = false; // Reset fling status after bounce impact
      }
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
    _audioController.playChime();
    _state.triggerMood('happy', duration: const Duration(seconds: 3));
    _state.addGrowth(0.12, source: 'feed'); // Growth from eating

    // Push boundary nodes outward wobbly
    for (int i = 0; i < PuniPhysics.nodeCount; i++) {
      double angle = i * 2 * pi / PuniPhysics.nodeCount;
      _physics.nodeVelocities[i] += Offset(
        cos(angle) * 300.0,
        sin(angle) * 300.0,
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
    _wasFlungByUser = false;
    if (_showInterstitialAd) return;
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
        _audioController.playPuni(_state.softness);
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
    if (_showInterstitialAd) return;
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
          _audioController.playMuni(_state.softness);
        } else {
          _audioController.playPuni(_state.softness);
          _state.addGrowth(0.002, source: 'petting'); // Tiny petting growth
        }
      }
    }
  }

  void _handlePointerUp(PointerUpEvent event) {
    if (_state.isDragging) {
      double flingSpeed = _physics.centerVelocity.distance;
      if (flingSpeed > 320.0) {
        _wasFlungByUser = true;
        _audioController.playBoyo(_state.softness);
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
  }

  void _spawnFood() {
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
    setState(() {
      _showInterstitialAd = true;
      _adCountdown = 4;
    });

    _adTimer?.cancel();
    _adTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_adCountdown > 1) {
        setState(() {
          _adCountdown--;
        });
      } else {
        _adTimer?.cancel();
        setState(() {
          _showInterstitialAd = false;
        });
        _state.performAdLevelUp();
        _audioController.playLevelUp();
      }
    });
  }

  void _showAppleHealthSyncDialog() {
    DateTime bedtime = DateTime.now().subtract(
      const Duration(hours: 8),
    ); // Default 8 hours bedtime
    DateTime wakeTime = DateTime.now();
    double sleepHours = 8.0;

    showCupertinoModalPopup(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            // Recalculate sleep duration
            Duration diff = wakeTime.difference(bedtime);
            double calculatedHours = diff.inMinutes / 60.0;
            if (calculatedHours < 0) {
              calculatedHours += 24.0; // handle cross-midnight
            }
            sleepHours = double.parse(calculatedHours.toStringAsFixed(1));

            return Container(
              height: 480,
              padding: const EdgeInsets.only(top: 6.0),
              color: CupertinoColors.systemBackground.resolveFrom(context),
              child: SafeArea(
                top: false,
                child: Column(
                  children: [
                    // Pull bar
                    Container(
                      height: 5,
                      width: 40,
                      decoration: BoxDecoration(
                        color: CupertinoColors.inactiveGray,
                        borderRadius: BorderRadius.circular(2.5),
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Title
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          CupertinoIcons.heart_fill,
                          color: Color(0xFFFF2D55),
                          size: 22,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          "Apple Health 同期",
                          style: GoogleFonts.notoSansJp(
                            fontSize: 19,
                            fontWeight: FontWeight.bold,
                            color: CupertinoColors.label.resolveFrom(context),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    // Steps status
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 20),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: CupertinoColors.secondarySystemBackground
                            .resolveFrom(context),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "今日の歩数同期",
                                style: GoogleFonts.notoSansJp(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: CupertinoColors.label.resolveFrom(
                                    context,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                "ヘルスケア歩数: ${_state.stepsToday} 歩",
                                style: GoogleFonts.notoSansJp(
                                  fontSize: 12,
                                  color: CupertinoColors.secondaryLabel
                                      .resolveFrom(context),
                                ),
                              ),
                            ],
                          ),
                          Text(
                            "+${(_state.stepsToday * 0.02).toStringAsFixed(1)} ⚡️",
                            style: GoogleFonts.outfit(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: CupertinoColors.activeGreen,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Sleep selection heading
                    Text(
                      "昨夜の睡眠時間を選択して同期:",
                      style: GoogleFonts.notoSansJp(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: CupertinoColors.label.resolveFrom(context),
                      ),
                    ),
                    const SizedBox(height: 10),
                    // Time pickers
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        Column(
                          children: [
                            Text(
                              "就寝時刻",
                              style: GoogleFonts.notoSansJp(
                                fontSize: 11,
                                color: CupertinoColors.secondaryLabel
                                    .resolveFrom(context),
                              ),
                            ),
                            SizedBox(
                              width: 140,
                              height: 100,
                              child: CupertinoDatePicker(
                                mode: CupertinoDatePickerMode.time,
                                initialDateTime: bedtime,
                                use24hFormat: true,
                                onDateTimeChanged: (DateTime newDateTime) {
                                  setModalState(() {
                                    bedtime = newDateTime;
                                  });
                                },
                              ),
                            ),
                          ],
                        ),
                        Column(
                          children: [
                            Text(
                              "起床時刻",
                              style: GoogleFonts.notoSansJp(
                                fontSize: 11,
                                color: CupertinoColors.secondaryLabel
                                    .resolveFrom(context),
                              ),
                            ),
                            SizedBox(
                              width: 140,
                              height: 100,
                              child: CupertinoDatePicker(
                                mode: CupertinoDatePickerMode.time,
                                initialDateTime: wakeTime,
                                use24hFormat: true,
                                onDateTimeChanged: (DateTime newDateTime) {
                                  setModalState(() {
                                    wakeTime = newDateTime;
                                  });
                                },
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      "睡眠時間: $sleepHours 時間 (エネルギー: +${(sleepHours * 10.0).toStringAsFixed(0)} ⚡️)",
                      style: GoogleFonts.notoSansJp(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFFFF2D55),
                      ),
                    ),
                    const Spacer(),
                    // Action button
                    Padding(
                      padding: const EdgeInsets.only(
                        left: 20,
                        right: 20,
                        bottom: 20,
                      ),
                      child: CupertinoButton(
                        color: const Color(0xFFFF2D55),
                        borderRadius: BorderRadius.circular(16),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              CupertinoIcons.heart_fill,
                              color: Colors.white,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              "Apple Health 睡眠データを同期",
                              style: GoogleFonts.notoSansJp(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        onPressed: () {
                          // Show Apple Health style syncing indicator dialog
                          showCupertinoDialog(
                            context: context,
                            builder: (loaderCtx) {
                              Future.delayed(
                                const Duration(milliseconds: 1400),
                                () {
                                  if (!mounted) return;
                                  Navigator.pop(loaderCtx); // Dismiss loader
                                  Navigator.pop(context); // Dismiss sheet

                                  // Award sleep energy to state
                                  _state.addSleepEnergy(sleepHours);
                                  _audioController.playChime();
                                  _state.triggerMood(
                                    'happy',
                                    duration: const Duration(seconds: 3),
                                  );

                                  ScaffoldMessenger.of(
                                    this.context,
                                  ).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        "睡眠データを同期しました！エネルギー +${(sleepHours * 10.0).toStringAsFixed(0)} ⚡️",
                                        style: GoogleFonts.notoSansJp(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      backgroundColor:
                                          CupertinoColors.activeGreen,
                                      behavior: SnackBarBehavior.floating,
                                    ),
                                  );
                                },
                              );

                              return const CupertinoAlertDialog(
                                title: Text("ヘルスケア同期"),
                                content: Padding(
                                  padding: EdgeInsets.only(top: 16.0),
                                  child: CupertinoActivityIndicator(radius: 14),
                                ),
                              );
                            },
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

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final textThemeColor = _getTextColor();

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
                            Text(
                              "🚶 ${_state.stepsToday} 歩",
                              style: GoogleFonts.notoSansJp(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: textThemeColor,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              "柔らかさ: ${_state.softness.toStringAsFixed(0)}%",
                              style: GoogleFonts.notoSansJp(
                                fontSize: 11,
                                color: textThemeColor.withOpacity(0.7),
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

                    // Puni Energy Display & iOS Health Sync
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.bolt,
                              color: Colors.amber,
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
                        GestureDetector(
                          onTap: _showAppleHealthSyncDialog,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFF2D55).withOpacity(0.15),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: const Color(0xFFFF2D55).withOpacity(0.4),
                                width: 1.0,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  CupertinoIcons.heart_fill,
                                  color: Color(0xFFFF2D55),
                                  size: 12,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  "ヘルスケア同期",
                                  style: GoogleFonts.notoSansJp(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: textThemeColor,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
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
                        Row(
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
                          label: "エサ",
                          isActive: false,
                          textThemeColor: textThemeColor,
                          onPressed: _spawnFood,
                        ),
                        _buildActionButton(
                          icon: Icons.play_circle_filled,
                          label: "動画でLvUP",
                          isActive: true,
                          textThemeColor: textThemeColor,
                          onPressed: _watchAdToLevelUp,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // Static Premium Glassmorphic Banner Ad
                _buildBannerAd(textThemeColor),
              ],
            ),
          ),

          // 7. Video Interstitial Ad Simulator Overlay
          if (_showInterstitialAd)
            Positioned.fill(
              child: Container(
                color: Colors.black.withOpacity(0.85),
                child: Center(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: Container(
                      width: min(media.size.width * 0.85, 330.0),
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.grey[950],
                        border: Border.all(
                          color: Colors.white.withOpacity(0.15),
                        ),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox(
                            width: 44,
                            height: 44,
                            child: CircularProgressIndicator(
                              color: Color(0xFFFF2A6D),
                              strokeWidth: 4,
                            ),
                          ),
                          const SizedBox(height: 24),
                          Text(
                            "Puni Pop Adventure Ad",
                            style: GoogleFonts.outfit(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            "Watch to gain an instant level up!",
                            textAlign: TextAlign.center,
                            style: GoogleFonts.outfit(
                              color: Colors.grey[400],
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 24),
                          Container(
                            decoration: BoxDecoration(
                              color: const Color(0xFFFF2A6D).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: const Color(0xFFFF2A6D).withOpacity(0.3),
                              ),
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 12,
                            ),
                            child: Text(
                              "Close video in: $_adCountdown",
                              style: GoogleFonts.outfit(
                                color: const Color(0xFFFF2A6D),
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required bool isActive,
    required Color textThemeColor,
    required VoidCallback onPressed,
  }) {
    final activeColor = const Color(0xFFFF2A6D);
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: isActive ? activeColor : textThemeColor.withOpacity(0.8),
              size: 24,
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: GoogleFonts.notoSansJp(
                fontSize: 11,
                fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                color: isActive ? activeColor : textThemeColor.withOpacity(0.7),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBannerAd(Color textThemeColor) {
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
    _gameLoopController.dispose();
    _accelerometerSub?.cancel();
    _batterySub?.cancel();
    _adTimer?.cancel();
    _blinkTimer?.cancel();
    _state.removeListener(_onStateChange);
    _state.dispose();
    super.dispose();
  }
}
