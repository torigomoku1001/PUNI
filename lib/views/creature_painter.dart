import 'dart:math';
import 'package:flutter/material.dart';
import '../physics/puni_physics.dart';

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
  final bool isRainbow; // For boost effect
  final bool isCharging;

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
    required this.isRainbow,
    required this.isCharging,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (physics.nodePositions.isEmpty) return;

    final center = physics.center;
    final nodeCount = PuniPhysics.nodeCount;

    // 0. DRAW GROUND DROP SHADOW ON THE FLOOR (Y = size.height - 210.0)
    final floorY = size.height - 210.0;
    final distToFloor = floorY - center.dy;
    final distancePct = ((distToFloor - PuniPhysics.baseRadius) / 350.0).clamp(0.0, 1.0);

    final shadowWidth = PuniPhysics.baseRadius * 2.3 * (1.0 - distancePct * 0.45);
    final shadowHeight = PuniPhysics.baseRadius * 0.35 * (1.0 - distancePct * 0.55);
    final shadowOpacity = 0.35 * (1.0 - distancePct * 0.7);
    final blurRadius = 3.0 + distancePct * 15.0;

    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(center.dx, floorY - 2.0),
        width: shadowWidth,
        height: shadowHeight,
      ),
      Paint()
        ..color = Colors.black.withOpacity(shadowOpacity)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, blurRadius),
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

    // 2. CHOOSE BODY COLOR (Solid flat color, no gradients per user request)
    late Paint bodyPaint;
    if (isRainbow) {
      final time = DateTime.now().millisecondsSinceEpoch / 1000.0;
      final color = HSLColor.fromAHSL(1.0, (time * 60) % 360, 0.85, 0.65).toColor();
      bodyPaint = Paint()
        ..color = color
        ..style = PaintingStyle.fill;
    } else {
      bodyPaint = Paint()
        ..color = primaryColor
        ..style = PaintingStyle.fill;
    }

    // Draw creature body
    canvas.drawPath(bodyPath, bodyPaint);

    // Draw a subtle dark outline for flat styling
    final borderPaint = Paint()
      ..color = const Color(0xFF3C3C40)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(bodyPath, borderPaint);

    // 4. DRAW EYES
    _drawEyes(canvas, center, size);

    // 5. DRAW ELECTRIC SPARKS (if charging)
    _drawElectricSparks(canvas, center);
  }

  void _drawRectEye(Canvas canvas, Offset eyeCenter, double width, double height, double radius, double rotationAngle, Paint paint) {
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
    double py = radius * 0.85; // Pivot at bottom-left corner
    
    // 1. 3D horizontal compression
    double tx = px + (offset.dx - px) * cos(spinAngle);
    double ty = offset.dy;
    
    // 2. Lift/roll rotation around pivot (counter-clockwise roll lifts right side)
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

    // Dynamic Look Target (Eyes follow touch or drift with velocity)
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
      double theta = time * 3.5; // matching physics rotation speed
      double cosVal = cos(theta);
      
      if (cosVal < -0.15) {
        // Facing away, hide eyes completely
        return;
      }
      
      Offset leftRaw = Offset(-eyeSpacing, eyeHeightOffset) + lookOffset;
      Offset rightRaw = Offset(eyeSpacing, eyeHeightOffset) + lookOffset;
      
      leftEyeCenter = center + _apply3DSpinAndLift(leftRaw, theta, PuniPhysics.baseRadius);
      rightEyeCenter = center + _apply3DSpinAndLift(rightRaw, theta, PuniPhysics.baseRadius);
    } else {
      leftEyeCenter = center + Offset(-eyeSpacing, eyeHeightOffset) + lookOffset;
      rightEyeCenter = center + Offset(eyeSpacing, eyeHeightOffset) + lookOffset;
    }

    // Clamp eyes to stay strictly inside transparent wall boundaries
    final minX = 25.0;
    final maxX = size.width - 25.0;
    final minY = 25.0;
    final maxY = size.height - 210.0 - 8.0; // keep it above the action panel line
    
    leftEyeCenter = Offset(
      leftEyeCenter.dx.clamp(minX, maxX),
      leftEyeCenter.dy.clamp(minY, maxY),
    );
    rightEyeCenter = Offset(
      rightEyeCenter.dx.clamp(minX, maxX),
      rightEyeCenter.dy.clamp(minY, maxY),
    );

    final eyePaint = Paint()
      ..color = const Color(0xFF1E1E24)
      ..style = PaintingStyle.fill;





    if (isBlinking) {
      _drawRectEye(canvas, leftEyeCenter, 10, 2, 0.5, 0.0, eyePaint);
      _drawRectEye(canvas, rightEyeCenter, 10, 2, 0.5, 0.0, eyePaint);
      return;
    }

    if (energy <= 0.0) {
      // Annoyed or pain states when energy is depleted
      if (mood == 'angry') {
        // Dislikes it (ちょっと嫌そう) -> Slanted thin annoyed eyes (reverse-Ha shape \ /)
        _drawRectEye(canvas, leftEyeCenter, 10, 2.5, 0.5, -pi / 10.0, eyePaint);
        _drawRectEye(canvas, rightEyeCenter, 10, 2.5, 0.5, pi / 10.0, eyePaint);
      } else if (mood == 'sad' || mood == 'surprised') {
        // Painful (痛そう) -> "逆八の字" shape eyes (\ / shape)
        _drawRectEye(canvas, leftEyeCenter, 5.5, 13.5, 1.0, -pi / 8.0, eyePaint);
        _drawRectEye(canvas, rightEyeCenter, 5.5, 13.5, 1.0, pi / 8.0, eyePaint);
      } else {
        // Normal listless/low-energy look (dull horizontal slit eyes)
        _drawRectEye(canvas, leftEyeCenter, 9.5, 4.0, 1.0, 0.0, eyePaint);
        _drawRectEye(canvas, rightEyeCenter, 9.5, 4.0, 1.0, 0.0, eyePaint);
      }
    } else {
      // Energetic states when energy is available
      switch (mood) {
        case 'happy':
          // Shy / Embarrassed (照れ) -> Happy downward u u arcs
          _drawArcEye(canvas, leftEyeCenter, 10.0, 7.0, true, eyePaint);
          _drawArcEye(canvas, rightEyeCenter, 10.0, 7.0, true, eyePaint);
          break;

        case 'sleepy':
          _drawRectEye(canvas, leftEyeCenter, 10, 2.0, 0.5, 0.0, eyePaint);
          _drawRectEye(canvas, rightEyeCenter, 10, 2.0, 0.5, 0.0, eyePaint);
          break;

        case 'angry':
          _drawRectEye(canvas, leftEyeCenter, 5.5, 13.5, 1.0, -pi / 8.0, eyePaint);
          _drawRectEye(canvas, rightEyeCenter, 5.5, 13.5, 1.0, pi / 8.0, eyePaint);
          break;

        case 'surprised':
          // Fun / Excited (楽しそう) -> Happy upward ^ ^ arcs
          _drawArcEye(canvas, leftEyeCenter, 11.0, 8.0, false, eyePaint);
          _drawArcEye(canvas, rightEyeCenter, 11.0, 8.0, false, eyePaint);
          break;

        case 'sad':
          // Painful (痛そう) -> "逆八の字" shape eyes (\ / shape)
          _drawRectEye(canvas, leftEyeCenter, 5.5, 13.5, 1.0, -pi / 8.0, eyePaint);
          _drawRectEye(canvas, rightEyeCenter, 5.5, 13.5, 1.0, pi / 8.0, eyePaint);
          break;

        case 'normal':
        default:
          _drawRectEye(canvas, leftEyeCenter, 5.5, 13.5, 1.0, 0.0, eyePaint);
          _drawRectEye(canvas, rightEyeCenter, 5.5, 13.5, 1.0, 0.0, eyePaint);
          break;
      }
    }
  }

  void _drawElectricSparks(Canvas canvas, Offset center) {
    if (!isCharging) return;

    final sparkPaint = Paint()
      ..color = const Color(0xFFFFEE58) // Bright electric neon yellow
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.0);

    final nodeCount = PuniPhysics.nodeCount;
    final random = Random(DateTime.now().millisecondsSinceEpoch ~/ 80);
    
    // 3 perimeter sparks cycling around the body in a loop
    int baseIdx = (DateTime.now().millisecondsSinceEpoch ~/ 60) % nodeCount;

    for (int s = 0; s < 3; s++) {
      int startIdx = (baseIdx + s * 4) % nodeCount;
      Path sparkPath = Path();
      
      Offset startPos = center + physics.nodePositions[startIdx];
      sparkPath.moveTo(startPos.dx, startPos.dy);

      for (int step = 1; step <= 3; step++) {
        int fromIdx = (startIdx + step - 1) % nodeCount;
        int toIdx = (startIdx + step) % nodeCount;
        
        Offset pFrom = center + physics.nodePositions[fromIdx];
        Offset pTo = center + physics.nodePositions[toIdx];
        
        const int subdivisions = 3;
        for (int sub = 1; sub <= subdivisions; sub++) {
          double t = sub / subdivisions;
          Offset midPoint = Offset.lerp(pFrom, pTo, t)!;
          
          Offset segDir = pTo - pFrom;
          double segDist = segDir.distance;
          if (segDist > 0.1) {
            Offset perp = Offset(-segDir.dy / segDist, segDir.dx / segDist);
            double jitterAmount = (random.nextDouble() - 0.5) * 12.0;
            if (sub == subdivisions) jitterAmount = 0.0;
            
            midPoint += perp * jitterAmount;
          }
          sparkPath.lineTo(midPoint.dx, midPoint.dy);
        }
      }
      canvas.drawPath(sparkPath, sparkPaint);
    }
  }

  void _drawArcEye(Canvas canvas, Offset center, double width, double height, bool isShy, Paint paint) {
    final rect = Rect.fromCenter(center: center, width: width, height: height);
    final prevStyle = paint.style;
    final prevColor = paint.color;
    paint.style = PaintingStyle.stroke;
    paint.strokeWidth = 3.0;
    paint.strokeCap = StrokeCap.round;
    if (isShy) {
      canvas.drawArc(rect, 0.15, pi - 0.3, false, paint);
    } else {
      canvas.drawArc(rect, pi + 0.15, pi - 0.3, false, paint);
    }
    paint.style = prevStyle;
    paint.color = prevColor;
  }

  void _drawXEye(Canvas canvas, Offset center, double size, Paint paint) {
    final prevStyle = paint.style;
    final prevStrokeWidth = paint.strokeWidth;
    final prevStrokeCap = paint.strokeCap;
    
    paint.style = PaintingStyle.stroke;
    paint.strokeWidth = 3.0;
    paint.strokeCap = StrokeCap.round;
    
    canvas.drawLine(center + Offset(-size/2, -size/2), center + Offset(size/2, size/2), paint);
    canvas.drawLine(center + Offset(-size/2, size/2), center + Offset(size/2, -size/2), paint);
    
    paint.style = prevStyle;
    paint.strokeWidth = prevStrokeWidth;
    paint.strokeCap = prevStrokeCap;
  }

  void _drawSweatDrop(Canvas canvas, Offset position) {
    final paint = Paint()
      ..color = const Color(0xFF29B6F6)
      ..style = PaintingStyle.fill;
    
    Path path = Path();
    path.moveTo(position.dx, position.dy - 8.0);
    path.quadraticBezierTo(
      position.dx - 5.0, position.dy + 1.0,
      position.dx - 5.0, position.dy + 4.0,
    );
    path.arcToPoint(
      Offset(position.dx + 5.0, position.dy + 4.0),
      radius: const Radius.circular(5.0),
      clockwise: false,
    );
    path.quadraticBezierTo(
      position.dx + 5.0, position.dy + 1.0,
      position.dx, position.dy - 8.0,
    );
    path.close();
    canvas.drawPath(path, paint);
  }

  void _drawDizzySpirals(Canvas canvas, Offset position) {
    final paint = Paint()
      ..color = const Color(0xFF90A4AE)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;
      
    double time = DateTime.now().millisecondsSinceEpoch / 250.0;
    canvas.save();
    canvas.translate(position.dx, position.dy);
    canvas.rotate(time);
    
    canvas.drawLine(const Offset(-8, -8), const Offset(-2, -2), paint);
    canvas.drawLine(const Offset(-8, -2), const Offset(-2, -8), paint);
    
    canvas.drawLine(const Offset(2, 2), const Offset(8, 8), paint);
    canvas.drawLine(const Offset(2, 8), const Offset(8, 2), paint);
    
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CreaturePainter oldDelegate) {
    // Repaint on every tick for physics animation and rainbow gradients
    return true;
  }
}
