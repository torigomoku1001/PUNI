import 'dart:math';
import 'package:flutter/material.dart';
import '../physics/puni_physics.dart';
import 'home_screen.dart';
import '../state/creature_state.dart';

class CreaturePainter extends CustomPainter {
  final PuniPhysics physics;
  final String mood;
  final String shape;
  final double softness;
  final double energy;
  final Color primaryColor;
  final Color secondaryColor;
  final Offset? touchPosition;
  final bool isBlinking;
  final bool isCharging;
  final bool isPetting;
  final bool isPinching;
  final bool isInflating;
  final double intimacy;
  final bool isColorLocked;
  final List<TouchParticle> touchParticles;
  final bool isFollowing;
  final Offset? followTarget;
  final double renderScale;
  final double hunger;
  final bool isDragging;

  CreaturePainter({
    required this.physics,
    required this.mood,
    required this.shape,
    required this.softness,
    required this.energy,
    required this.primaryColor,
    required this.secondaryColor,
    required this.touchPosition,
    required this.isBlinking,
    required this.isCharging,
    this.isPetting = false,
    this.isPinching = false,
    this.isInflating = false,
    required this.intimacy,
    required this.isColorLocked,
    required this.touchParticles,
    this.isFollowing = false,
    this.followTarget,
    this.renderScale = 1.0,
    required this.hunger,
    this.isDragging = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (physics.nodePositions.isEmpty) return;

    final center = physics.center;
    final nodeCount = PuniPhysics.nodeCount;

    // 0. DRAW GROUND DROP SHADOW ON THE FLOOR
    final floorY = size.height - 210.0;
    
    if (hunger <= 0.0) {
      canvas.save();
      double visualBottom = center.dy + PuniPhysics.baseRadius;
      canvas.translate(center.dx, visualBottom - 15.0); // メニューバーに被らないよう15px上に持ち上げる
      canvas.scale(1.15, 0.5); // 少しだけ横に広げて潰す
      canvas.translate(-center.dx, -visualBottom);
    }

    final distToFloor = floorY - center.dy;
    final distancePct = ((distToFloor - PuniPhysics.baseRadius) / 350.0).clamp(
      0.0,
      1.0,
    );

    final shadowWidth =
        PuniPhysics.baseRadius * 2.3 * renderScale * (1.0 - distancePct * 0.45);
    final shadowHeight =
        PuniPhysics.baseRadius *
        0.35 *
        renderScale *
        (1.0 - distancePct * 0.55);
    final shadowOpacity = 0.35 * (1.0 - distancePct * 0.7);
    final shadowColor = Colors.black.withOpacity(shadowOpacity * 0.9);

    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(center.dx, floorY - 2.0),
        width: shadowWidth,
        height: shadowHeight,
      ),
      Paint()..color = shadowColor,
    );

    // 1. GENERATE BODY PATH
    final bodyPath = Path();
    final firstMid = (physics.nodePositions[0] + physics.nodePositions[1]) / 2;
    bodyPath.moveTo(center.dx + firstMid.dx, center.dy + firstMid.dy);

    for (int i = 1; i < nodeCount; i++) {
      final current = physics.nodePositions[i];
      final next = physics.nodePositions[(i + 1) % nodeCount];
      final mid = (current + next) / 2;
      bodyPath.quadraticBezierTo(
        center.dx + current.dx,
        center.dy + current.dy,
        center.dx + mid.dx,
        center.dy + mid.dy,
      );
    }
    final firstNode = physics.nodePositions[0];
    bodyPath.quadraticBezierTo(
      center.dx + firstNode.dx,
      center.dy + firstNode.dy,
      center.dx + firstMid.dx,
      center.dy + firstMid.dy,
    );
    bodyPath.close();

    // 2. CHOOSE BODY COLOR
    final bodyPaint = Paint()
      ..color = primaryColor
      ..style = PaintingStyle.fill;

    final currentOpacity = primaryColor.opacity;

    // 100% Intimacy Neon Glow Aura
    if (intimacy >= 350.0 &&
        currentOpacity > 0.0) {
      final glowColor = primaryColor;
      final glowPaint1 = Paint()
        ..color = glowColor.withOpacity(0.18 * currentOpacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 24.0
        ..strokeJoin = StrokeJoin.round;
      final glowPaint2 = Paint()
        ..color = glowColor.withOpacity(0.35 * currentOpacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 14.0
        ..strokeJoin = StrokeJoin.round;
      final glowPaint3 = Paint()
        ..color = glowColor.withOpacity(0.6 * currentOpacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6.0
        ..strokeJoin = StrokeJoin.round;

      canvas.drawPath(bodyPath, glowPaint1);
      canvas.drawPath(bodyPath, glowPaint2);
      canvas.drawPath(bodyPath, glowPaint3);
    }

    // Draw creature body
    canvas.drawPath(bodyPath, bodyPaint);

    if (!isCharging) {
      final borderPaint = Paint()
        ..color = const Color(0xFF3C3C40)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.0
        ..strokeJoin = StrokeJoin.round;
      canvas.drawPath(bodyPath, borderPaint);
    } else {
      final electricOutlinePaint = Paint()
        ..color = const Color(0xFF8CE3FF).withOpacity(0.35 * currentOpacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeJoin = StrokeJoin.round;
      canvas.drawPath(bodyPath, electricOutlinePaint);
    }

    // 4. DRAW EYES
    _drawEyes(canvas, center, size);

    // 5. DRAW ELECTRIC SPARKS
    _drawElectricSparks(canvas, center);

    // 潰れたスケールをリセット（吹き出しやZzzなどが潰れないようにする）
    if (hunger <= 0.0) {
      canvas.restore();
    }

    // 6. DRAW TOUCH PARTICLES
    _drawTouchParticles(canvas);

    // 7. DRAW SLEEP Zzz EFFECTS
    if (mood == 'sleep') {
      final double time = DateTime.now().millisecondsSinceEpoch / 1000.0;
      final textPainter = TextPainter(textDirection: TextDirection.ltr);

      for (int i = 0; i < 3; i++) {
        final double progress = ((time * 0.45 - i * 0.3) % 1.0);
        final double xOffset = 25.0 * sin(progress * 2 * pi + i * 2.0);
        final double yOffset = -55.0 * progress - 35.0;
        final double opacity = 1.0 - progress;
        final double scale = 0.5 + 0.6 * (1.0 - progress);

        final zStyle = TextStyle(
          color: const Color(
            0xFF6C5CE7,
          ).withOpacity(opacity * 0.7 * currentOpacity),
          fontSize: 18.0 * scale,
          fontWeight: FontWeight.bold,
        );

        textPainter.text = TextSpan(
          text: i == 0 ? 'Z' : (i == 1 ? 'Zz' : 'Zzz'),
          style: zStyle,
        );
        textPainter.layout();
        textPainter.paint(
          canvas,
          center +
              Offset(
                xOffset - textPainter.width / 2,
                yOffset - textPainter.height / 2,
              ),
        );
      }
    }

    // 7b. DRAW HUNGRY EFFECT - 3-circle speech bubble with onigiri loop
    // 空中・ドラッグ中は非表示
    final bool isAirborne = distToFloor > PuniPhysics.baseRadius * 1.5;
    if (hunger <= 0.0 && !isDragging && !isAirborne) {
      final double time = DateTime.now().millisecondsSinceEpoch / 1000.0;
      // 全体4.0秒周期: 小丸→中丸→大丸+おにぎり→消える→繰り返し
      final double cycle = (time % 4.0);
      // 各フェーズ境界 (秒)
      // 0.0〜0.5: 小丸フェードイン
      // 0.5〜1.0: 中丸フェードイン
      // 1.0〜1.5: 大丸フェードイン + おにぎりフェードイン
      // 1.5〜2.8: 全部表示
      // 2.8〜3.3: フェードアウト
      // 3.3〜4.0: 休止

      double _fade(double start, double duration) {
        if (cycle < start) return 0.0;
        if (cycle < start + duration) return (cycle - start) / duration;
        return 1.0;
      }
      double _fadeOut(double start, double duration) {
        if (cycle < start) return 1.0;
        if (cycle < start + duration) return 1.0 - (cycle - start) / duration;
        return 0.0;
      }

      // フェードアウト開始: 2.8秒, 持続: 0.5秒
      final double fadeOutFactor = cycle >= 2.8 ? _fadeOut(2.8, 0.5) : 1.0;

      // 各丸のオパシティ
      final double dot1Op = _fade(0.0, 0.35) * fadeOutFactor;
      final double dot2Op = _fade(0.5, 0.35) * fadeOutFactor;
      final double dot3Op = _fade(1.0, 0.35) * fadeOutFactor;
      final double onigiOp = _fade(1.2, 0.35) * fadeOutFactor;

      // 基準位置: ぷにの右上
      final Offset base = center + const Offset(20, -42);

      // 円の描画ヘルパー
      void drawCircle(Offset pos, double r, double opacity) {
        if (opacity <= 0.01) return;
        final fill = Paint()
          ..color = Colors.white.withOpacity(opacity * 0.93)
          ..style = PaintingStyle.fill;
        final border = Paint()
          ..color = const Color(0xFFCCCCCC).withOpacity(opacity * 0.65)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2;
        canvas.drawCircle(pos, r, fill);
        canvas.drawCircle(pos, r, border);
      }

      // 小丸 (左下)
      drawCircle(base + const Offset(-14, 12), 5.0, dot1Op);
      // 中丸 (少し上)
      drawCircle(base + const Offset(-4, 4), 8.0, dot2Op);
      // 大丸 (メイン吹き出し)
      drawCircle(base + const Offset(10, -8), 18.0, dot3Op);

      // おにぎり絵文字 (大丸の中)
      if (onigiOp > 0.01) {
        final textPainter = TextPainter(textDirection: TextDirection.ltr);
        textPainter.text = const TextSpan(
          text: '\u{1F359}',
          style: TextStyle(fontSize: 18),
        );
        textPainter.layout();
        final onigiCenter = base + const Offset(10, -8);
        textPainter.paint(
          canvas,
          onigiCenter + Offset(-textPainter.width / 2, -textPainter.height / 2),
        );
      }
    }




    // 8. DRAW VORTEX ATTRACTION RIPPLES
    if (isFollowing && followTarget != null) {
      final double time = DateTime.now().millisecondsSinceEpoch / 1000.0;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.0;

      for (int i = 0; i < 3; i++) {
        final double progress = ((time * 1.5 - i * 0.33) % 1.0);
        final double radius = 70.0 * (1.0 - progress);
        if (radius > 1.5) {
          paint.color = primaryColor.withOpacity(
            progress * 0.7 * currentOpacity,
          );
          canvas.drawCircle(followTarget!, radius, paint);
        }
      }

      final corePaint = Paint()
        ..color = primaryColor.withOpacity(
          (0.5 + 0.3 * sin(time * 10.0)) * currentOpacity,
        )
        ..style = PaintingStyle.fill;
      canvas.drawCircle(followTarget!, 7.0, corePaint);
    }
  }

  void _drawRectEye(
    Canvas canvas,
    Offset eyeCenter,
    double width,
    double height,
    double radius,
    double rotationAngle,
    Paint paint,
  ) {
    if (rotationAngle != 0.0) {
      canvas.save();
      canvas.translate(eyeCenter.dx, eyeCenter.dy);
      canvas.rotate(rotationAngle);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset.zero, width: width, height: height),
          Radius.circular(radius),
        ),
        paint,
      );
      canvas.restore();
    } else {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: eyeCenter, width: width, height: height),
          Radius.circular(radius),
        ),
        paint,
      );
    }
  }

  Offset _apply3DSpinAndLift(Offset offset, double spinAngle, double radius) {
    double px = -radius * 1.15;
    double py = radius * 0.85;

    double tx = px + (offset.dx - px) * cos(spinAngle);
    double ty = offset.dy;

    double rollAngle = -0.28 * sin(spinAngle).abs();
    double cosR = cos(rollAngle);
    double sinR = sin(rollAngle);

    double dx = tx - px;
    double dy = ty - py;

    double finalX = px + dx * cosR - dy * sinR;
    double finalY = py + dx * sinR + dy * cosR;

    return Offset(finalX, finalY);
  }

  void _drawEyes(Canvas canvas, Offset center, Size size) {
    double eyeSpacing = 7.5;
    double eyeHeightOffset = -8.0;

    Offset lookOffset = Offset.zero;
    if (touchPosition != null) {
      Offset toTouch = touchPosition! - center;
      double dist = toTouch.distance;
      if (dist > 0.1) {
        lookOffset = (toTouch / dist) * min(7.0, dist * 0.04);
      }
    } else {
      double vx = physics.centerVelocity.dx;
      double vy = physics.centerVelocity.dy;
      double speed = sqrt(vx * vx + vy * vy);
      if (speed > 5.0) {
        lookOffset = Offset(vx, vy) / speed * min(4.0, speed * 0.01);
      }
    }

    Offset leftEyeCenter;
    Offset rightEyeCenter;

    if (shape == 'rotate') {
      double time = DateTime.now().millisecondsSinceEpoch / 1000.0;
      double theta = time * 3.5;
      double cosVal = cos(theta);

      if (cosVal < -0.15) return;

      Offset leftRaw = Offset(-eyeSpacing, eyeHeightOffset) + lookOffset;
      Offset rightRaw = Offset(eyeSpacing, eyeHeightOffset) + lookOffset;

      leftEyeCenter =
          center + _apply3DSpinAndLift(leftRaw, theta, PuniPhysics.baseRadius);
      rightEyeCenter =
          center + _apply3DSpinAndLift(rightRaw, theta, PuniPhysics.baseRadius);
    } else {
      leftEyeCenter =
          center + Offset(-eyeSpacing, eyeHeightOffset) + lookOffset;
      rightEyeCenter =
          center + Offset(eyeSpacing, eyeHeightOffset) + lookOffset;
    }

    final minX = 25.0;
    final maxX = size.width - 25.0;
    final minY = 25.0;
    final maxY = size.height - 210.0 - 8.0;

    leftEyeCenter = Offset(
      leftEyeCenter.dx.clamp(minX, maxX),
      leftEyeCenter.dy.clamp(minY, maxY),
    );
    rightEyeCenter = Offset(
      rightEyeCenter.dx.clamp(minX, maxX),
      rightEyeCenter.dy.clamp(minY, maxY),
    );

    final currentOpacity = primaryColor.opacity;
    final eyePaint = Paint()
      ..color = const Color(0xFF1E1E24)
      ..style = PaintingStyle.fill;

    if (isBlinking) {
      _drawRectEye(canvas, leftEyeCenter, 10, 2, 0.5, 0.0, eyePaint);
      _drawRectEye(canvas, rightEyeCenter, 10, 2, 0.5, 0.0, eyePaint);
      return;
    }

    if (mood == 'sleep' || mood == 'eating') {
      _drawArcEye(canvas, leftEyeCenter, 9.0, 7.0, true, eyePaint);
      _drawArcEye(canvas, rightEyeCenter, 9.0, 7.0, true, eyePaint);
      return;
    }

    if (mood == 'levelup') {
      _drawLevelUpBullseyeEye(canvas, leftEyeCenter, eyePaint);
      _drawLevelUpBullseyeEye(canvas, rightEyeCenter, eyePaint);
      return;
    }

    if (hunger <= 0.0) {
      _drawRectEye(canvas, leftEyeCenter, 14.0, 2.5, 0.5, pi / 8.0, eyePaint);
      _drawRectEye(canvas, rightEyeCenter, 14.0, 2.5, 0.5, -pi / 8.0, eyePaint);
      return;
    }

    if (energy <= 0.0) {
      if (mood == 'angry') {
        _drawRectEye(canvas, leftEyeCenter, 10, 2.5, 0.5, -pi / 10.0, eyePaint);
        _drawRectEye(canvas, rightEyeCenter, 10, 2.5, 0.5, pi / 10.0, eyePaint);
      } else if (mood == 'sad' || mood == 'surprised') {
        _drawRectEye(
          canvas,
          leftEyeCenter,
          5.5,
          13.5,
          1.0,
          -pi / 8.0,
          eyePaint,
        );
        _drawRectEye(
          canvas,
          rightEyeCenter,
          5.5,
          13.5,
          1.0,
          pi / 8.0,
          eyePaint,
        );
      } else {
        _drawRectEye(canvas, leftEyeCenter, 9.5, 4.0, 1.0, 0.0, eyePaint);
        _drawRectEye(canvas, rightEyeCenter, 9.5, 4.0, 1.0, 0.0, eyePaint);
      }
    } else {
      switch (mood) {
        case 'happy':
        case 'surprised':
          _drawArcEye(canvas, leftEyeCenter, 11.0, 8.0, false, eyePaint);
          _drawArcEye(canvas, rightEyeCenter, 11.0, 8.0, false, eyePaint);
          break;
        case 'sleepy':
          _drawRectEye(canvas, leftEyeCenter, 10, 2.0, 0.5, 0.0, eyePaint);
          _drawRectEye(canvas, rightEyeCenter, 10, 2.0, 0.5, 0.0, eyePaint);
          break;
        case 'angry':
        case 'sad':
          _drawRectEye(
            canvas,
            leftEyeCenter,
            5.5,
            13.5,
            1.0,
            -pi / 8.0,
            eyePaint,
          );
          _drawRectEye(
            canvas,
            rightEyeCenter,
            5.5,
            13.5,
            1.0,
            pi / 8.0,
            eyePaint,
          );
          break;
        case 'normal':
        default:
          if (isPetting) {
            _drawRectEye(canvas, leftEyeCenter, 11.0, 2.5, 0.8, 0.0, eyePaint);
            _drawRectEye(canvas, rightEyeCenter, 11.0, 2.5, 0.8, 0.0, eyePaint);
          } else {
            _drawRectEye(canvas, leftEyeCenter, 5.5, 13.5, 1.0, 0.0, eyePaint);
            _drawRectEye(canvas, rightEyeCenter, 5.5, 13.5, 1.0, 0.0, eyePaint);
          }
          break;
      }
    }

    if (intimacy >= 50.0 &&
        (mood == 'happy' || isPetting || isPinching || isInflating)) {
      final blushColor = (isPinching || isInflating)
          ? const Color(0xFFFF2D55).withOpacity(0.8 * currentOpacity)
          : const Color(0xFFFF8DA1).withOpacity(0.55 * currentOpacity);
      final blushPaint = Paint()
        ..color = blushColor
        ..style = PaintingStyle.fill;
      final cheekRadius = (isPinching || isInflating) ? 8.5 : 6.5;
      canvas.drawCircle(
        leftEyeCenter + const Offset(-6, 8),
        cheekRadius,
        blushPaint,
      );
      canvas.drawCircle(
        rightEyeCenter + const Offset(6, 8),
        cheekRadius,
        blushPaint,
      );
    }
  }

  void _drawElectricSparks(Canvas canvas, Offset center) {
    if (!isCharging) return;

    final currentOpacity = primaryColor.opacity;
    final ringPaint = Paint()
      ..color = const Color(0xFFCFF4FF).withOpacity(0.78 * currentOpacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.2
      ..strokeCap = StrokeCap.round;

    final sparkPaint = Paint()
      ..color = const Color(0xFFFFFFFF).withOpacity(0.95 * currentOpacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;

    final glowPaint = Paint()
      ..color = const Color(0xFFB8EEFF).withOpacity(0.85 * currentOpacity)
      ..style = PaintingStyle.fill;

    final nodeCount = PuniPhysics.nodeCount;
    if (nodeCount < 2) return;

    final tick = DateTime.now().millisecondsSinceEpoch;
    final head = (tick ~/ 36) % nodeCount;
    final head2 = (head + nodeCount ~/ 2) % nodeCount;
    const int trailLength = 8;

    Path buildSmoothOrbitPath(int movingHead) {
      final path = Path();
      final firstIdx = movingHead;
      final secondIdx = (movingHead + 1) % nodeCount;
      final firstMid =
          center +
          (physics.nodePositions[firstIdx] + physics.nodePositions[secondIdx]) /
              2;
      path.moveTo(firstMid.dx, firstMid.dy);

      for (int i = 1; i <= trailLength; i++) {
        final currentIdx = (movingHead + i) % nodeCount;
        final nextIdx = (movingHead + i + 1) % nodeCount;
        final current = center + physics.nodePositions[currentIdx];
        final mid =
            center +
            (physics.nodePositions[currentIdx] +
                    physics.nodePositions[nextIdx]) /
                2;
        path.quadraticBezierTo(current.dx, current.dy, mid.dx, mid.dy);
      }
      return path;
    }

    final orbitPath = buildSmoothOrbitPath(head);
    final orbitPath2 = buildSmoothOrbitPath(head2);
    final start = center + physics.nodePositions[head];
    final start2 = center + physics.nodePositions[head2];

    canvas.drawPath(orbitPath, ringPaint);
    canvas.drawPath(orbitPath2, ringPaint);

    final headPoint = start;
    final prevPoint =
        center + physics.nodePositions[(head - 1 + nodeCount) % nodeCount];
    final dir = headPoint - prevPoint;
    final len = dir.distance;
    if (len > 0.001) {
      final unit = dir / len;
      final perp = Offset(-unit.dy, unit.dx);
      final pulse = 0.7 + 0.3 * sin(tick / 90.0);
      final sparkLen = 14.0 * pulse;

      final a1 = headPoint + perp * 3.5;
      final b1 = a1 + unit * sparkLen;
      canvas.drawLine(a1, b1, sparkPaint);

      final a2 = headPoint - perp * 2.5;
      final b2 = a2 - unit * (sparkLen * 0.85);
      canvas.drawLine(a2, b2, sparkPaint);

      final headPoint2 = start2;
      final prevPoint2 =
          center + physics.nodePositions[(head2 - 1 + nodeCount) % nodeCount];
      final dir2 = headPoint2 - prevPoint2;
      final len2 = dir2.distance;
      if (len2 > 0.001) {
        final unit2 = dir2 / len2;
        final perp2 = Offset(-unit2.dy, unit2.dx);
        final a3 = headPoint2 + perp2 * 3.0;
        final b3 = a3 + unit2 * (sparkLen * 0.75);
        canvas.drawLine(a3, b3, sparkPaint);
      }

      canvas.drawCircle(headPoint, 3.2 * pulse, glowPaint);
      canvas.drawCircle(start2, 2.7 * pulse, glowPaint);
    }
  }

  void _drawArcEye(
    Canvas canvas,
    Offset center,
    double width,
    double height,
    bool isShy,
    Paint paint,
  ) {
    final rect = Rect.fromCenter(center: center, width: width, height: height);
    final prevStyle = paint.style;
    final prevStrokeCap = paint.strokeCap;
    final prevStrokeWidth = paint.strokeWidth;

    paint.style = PaintingStyle.stroke;
    paint.strokeWidth = 3.0;
    paint.strokeCap = StrokeCap.round;
    if (isShy) {
      canvas.drawArc(rect, 0.15, pi - 0.3, false, paint);
    } else {
      canvas.drawArc(rect, pi + 0.15, pi - 0.3, false, paint);
    }
    paint.style = prevStyle;
    paint.strokeCap = prevStrokeCap;
    paint.strokeWidth = prevStrokeWidth;
  }

  void _drawLevelUpBullseyeEye(Canvas canvas, Offset center, Paint paint) {
    final ringPaint = Paint()
      ..color = paint.color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2;

    final corePaint = Paint()
      ..color = paint.color
      ..style = PaintingStyle.fill;

    canvas.drawCircle(center, 5.4, ringPaint);
    canvas.drawCircle(center, 2.3, corePaint);
  }

  void _drawTouchParticles(Canvas canvas) {
    for (var particle in touchParticles) {
      final alpha = (particle.life / particle.maxLife).clamp(0.0, 1.0);
      final paint = Paint()
        ..color = particle.color.withOpacity(alpha)
        ..style = PaintingStyle.fill;

      if (particle.isCoin) {
        _drawCoin(canvas, particle.position, 28.0 * (0.5 + 0.5 * alpha), alpha);
      } else if (particle.isSpeedUp) {
        _drawSpeedUp(
          canvas,
          particle.position,
          24.0 * particle.sizeMultiplier * (0.5 + 0.5 * alpha),
          paint,
        );
      } else if (particle.isBubble) {
        _drawBubble(
          canvas,
          particle.position,
          14.0 * particle.sizeMultiplier * (0.5 + 0.5 * alpha),
          paint,
        );
      } else {
        _drawSparkle(
          canvas,
          particle.position,
          12.0 * particle.sizeMultiplier * (0.5 + 0.5 * alpha),
          paint,
        );
      }
    }
  }

  void _drawSpeedUp(Canvas canvas, Offset center, double size, Paint paint) {
    // Two upward chevrons (>> pointing up)
    final path = Path();
    
    // Bottom chevron
    path.moveTo(center.dx - size * 0.4, center.dy + size * 0.4);
    path.lineTo(center.dx, center.dy - size * 0.1);
    path.lineTo(center.dx + size * 0.4, center.dy + size * 0.4);
    
    // Top chevron
    path.moveTo(center.dx - size * 0.4, center.dy);
    path.lineTo(center.dx, center.dy - size * 0.5);
    path.lineTo(center.dx + size * 0.4, center.dy);

    final linePaint = Paint()
      ..color = paint.color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
      
    canvas.drawPath(path, linePaint);
  }

  void _drawCoin(Canvas canvas, Offset center, double size, double alpha) {
    final coinPaint = Paint()
      ..color = const Color(0xFFFFD700).withOpacity(alpha)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, size * 0.5, coinPaint);

    final borderPaint = Paint()
      ..color = const Color(0xFFDAA520).withOpacity(alpha)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8;
    canvas.drawCircle(center, size * 0.5, borderPaint);

    final textPainter = TextPainter(
      text: TextSpan(
        text: 'c',
        style: TextStyle(
          color: const Color(0xFF8B6508).withOpacity(alpha),
          fontSize: size * 0.65,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      center - Offset(textPainter.width / 2, textPainter.height * 0.58),
    );
  }

  void _drawBubble(Canvas canvas, Offset center, double size, Paint paint) {
    canvas.drawCircle(center, size * 0.45, paint);
    final strokePaint = Paint()
      ..color = Colors.white.withOpacity(paint.color.opacity * 0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    canvas.drawCircle(center, size * 0.4, strokePaint);

    final glintPaint = Paint()
      ..color = Colors.white.withOpacity(paint.color.opacity * 0.9)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(
      center + Offset(-size * 0.15, -size * 0.15),
      size * 0.08,
      glintPaint,
    );
  }

  void _drawSparkle(Canvas canvas, Offset center, double size, Paint paint) {
    final path = Path();
    final x = center.dx;
    final y = center.dy;
    final half = size / 2;

    path.moveTo(x, y - half);
    path.quadraticBezierTo(x, y, x + half, y);
    path.quadraticBezierTo(x, y, x, y + half);
    path.quadraticBezierTo(x, y, x - half, y);
    path.quadraticBezierTo(x, y, x, y - half);
    path.close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CreaturePainter oldDelegate) => true;
}

class CreaturePreviewPainter extends CustomPainter {
  final Color primaryColor;
  final Color secondaryColor;
  final double intimacy;

  CreaturePreviewPainter({
    required this.primaryColor,
    required this.secondaryColor,
    required this.intimacy,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2 + 5;
    final rx = size.width * 0.35;
    final ry = size.height * 0.28;

    final bodyPath = Path();
    bodyPath.moveTo(cx - rx, cy);
    bodyPath.cubicTo(
      cx - rx,
      cy - ry * 1.25,
      cx + rx,
      cy - ry * 1.25,
      cx + rx,
      cy,
    );
    bodyPath.cubicTo(
      cx + rx,
      cy + ry * 0.9,
      cx - rx,
      cy + ry * 0.9,
      cx - rx,
      cy,
    );
    bodyPath.close();

    if (intimacy >= 350.0) {
      final glowPaint1 = Paint()
        ..color = primaryColor.withOpacity(0.18)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 16.0
        ..strokeJoin = StrokeJoin.round;
      final glowPaint2 = Paint()
        ..color = primaryColor.withOpacity(0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 9.0
        ..strokeJoin = StrokeJoin.round;
      final glowPaint3 = Paint()
        ..color = primaryColor.withOpacity(0.6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4.0
        ..strokeJoin = StrokeJoin.round;

      canvas.drawPath(bodyPath, glowPaint1);
      canvas.drawPath(bodyPath, glowPaint2);
      canvas.drawPath(bodyPath, glowPaint3);
    }

    final bodyPaint = Paint()
      ..color = primaryColor
      ..style = PaintingStyle.fill;
    canvas.drawPath(bodyPath, bodyPaint);

    final borderPaint = Paint()
      ..color = const Color(0xFF3C3C40).withOpacity(primaryColor.opacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(bodyPath, borderPaint);

    final eyePaint = Paint()
      ..color = const Color(0xFF1E1E24).withOpacity(primaryColor.opacity)
      ..style = PaintingStyle.fill;

    final eyeSpacing = size.width * 0.1;
    final eyeHeightOffset = -size.height * 0.08;

    final leftEyeCenter = Offset(cx - eyeSpacing, cy + eyeHeightOffset);
    final rightEyeCenter = Offset(cx + eyeSpacing, cy + eyeHeightOffset);

    void drawEye(Offset center) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: center,
            width: size.width * 0.08,
            height: size.height * 0.16,
          ),
          Radius.circular(size.width * 0.02),
        ),
        eyePaint,
      );
    }

    drawEye(leftEyeCenter);
    drawEye(rightEyeCenter);

    if (intimacy >= 50.0) {
      final blushPaint = Paint()
        ..color = const Color(
          0xFFFF8DA1,
        ).withOpacity(0.55 * primaryColor.opacity)
        ..style = PaintingStyle.fill;
      final cheekRadius = size.width * 0.08;
      canvas.drawCircle(
        leftEyeCenter + Offset(-size.width * 0.07, size.height * 0.08),
        cheekRadius,
        blushPaint,
      );
      canvas.drawCircle(
        rightEyeCenter + Offset(size.width * 0.07, size.height * 0.08),
        cheekRadius,
        blushPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CreaturePreviewPainter oldDelegate) {
    return oldDelegate.primaryColor != primaryColor ||
        oldDelegate.secondaryColor != secondaryColor ||
        oldDelegate.intimacy != intimacy;
  }
}
