import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart' hide Image;
import 'package:flutter_test/flutter_test.dart';
import 'package:puni_project/physics/puni_physics.dart';
import 'package:puni_project/views/creature_painter.dart';

void main() {
  test('Generate app icon PNG', () async {
    // 1. Initialize PuniPhysics and set center to (256, 256)
    final physics = PuniPhysics();
    physics.center = const Offset(256, 256);

    // Use the gorgeous pastel pink/purple colors of Puni
    final primaryColor = const Color(0xFFFF8DA1); // Pink
    final secondaryColor = const Color(0xFFB388FF); // Purple

    // Update physics simulation so Puni rests naturally
    for (int i = 0; i < 120; i++) {
      physics.update(
        dt: 1 / 60,
        boundary: const Size(512, 512),
        softness: 40.0,
        shape: 'default',
        touchPosition: null,
        isDragging: false,
        isPetting: false,
        gravityVector: const Offset(0, 480),
        isCharging: false,
      );
    }

    // Make sure center is exactly at (256, 280) so it's perfectly centered vertically
    physics.center = const Offset(256, 275);
    // Recalculate node positions relative to the new center
    final baseOffsets = physics.getTargetOffsets(
      'default',
      PuniPhysics.baseRadius,
    );
    for (int i = 0; i < PuniPhysics.nodeCount; i++) {
      physics.nodePositions[i] = baseOffsets[i];
    }

    // 2. Create the PictureRecorder and Canvas
    final recorder = PictureRecorder();
    final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, 512, 512));

    // Draw a nice modern rounded square icon background (gradient from pastel pink to soft purple-blue)
    final bgPaint = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFFFFEEF3), Color(0xFFF3E8FF)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(const Rect.fromLTWH(0, 0, 512, 512));
    canvas.drawRect(const Rect.fromLTWH(0, 0, 512, 512), bgPaint);

    // Scale the Puni drawing up to look premium on the app icon
    canvas.save();
    canvas.translate(256, 275);
    canvas.scale(4.0); // Scale up by 4x to fill the icon
    canvas.translate(-256, -275);

    // Paint Puni
    final painter = CreaturePainter(
      physics: physics,
      mood: 'normal',
      shape: 'default',
      softness: 40.0,
      energy: 100.0,
      primaryColor: primaryColor,
      secondaryColor: secondaryColor,
      touchPosition: null,
      isBlinking: false,
      isCharging: false,
      intimacy: 0.0,
      isColorLocked: false,
      touchParticles: const [],
    );

    // Set custom size for painter layout
    painter.paint(canvas, const Size(512, 512));

    canvas.restore();

    // 3. Convert recorder to Image
    final picture = recorder.endRecording();
    final image = await picture.toImage(512, 512);
    final byteData = await image.toByteData(format: ImageByteFormat.png);
    final buffer = byteData!.buffer.asUint8List();

    // 4. Save to file
    final file = File('assets/icon/app_icon.png');
    await file.create(recursive: true);
    await file.writeAsBytes(buffer);
    print("SAVED REAL PUNI APP ICON SUCCESS");
  });
}
