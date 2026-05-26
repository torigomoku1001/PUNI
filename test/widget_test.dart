import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:puni_project/physics/puni_physics.dart';
import 'package:puni_project/main.dart';

void main() {
  group('PuniPhysics Engine Tests', () {
    test('Initializes with nodes and velocities', () {
      final physics = PuniPhysics();
      expect(physics.nodePositions.length, equals(PuniPhysics.nodeCount));
      expect(physics.nodeVelocities.length, equals(PuniPhysics.nodeCount));
      expect(physics.center, equals(const Offset(200, 400)));
    });

    test('Step update changes position', () {
      final physics = PuniPhysics();
      final initialCenter = physics.center;
      
      physics.update(
        dt: 0.016,
        boundary: const Size(400, 800),
        softness: 30.0,
        shape: 'default',
        touchPosition: null,
        isDragging: false,
        isPetting: false,
        gravityVector: const Offset(0, 400),
        isCharging: false,
      );

      // Center should fall under gravity
      expect(physics.center.dy, greaterThan(initialCenter.dy));
    });

    test('Bounce collision prevents escaping floor boundary', () {
      final physics = PuniPhysics();
      // Position center near bottom boundary
      physics.center = const Offset(200, 780);
      physics.centerVelocity = const Offset(0, 500);

      physics.update(
        dt: 0.016,
        boundary: const Size(400, 800),
        softness: 30.0,
        shape: 'default',
        touchPosition: null,
        isDragging: false,
        isPetting: false,
        gravityVector: const Offset(0, 400),
        isCharging: false,
      );

      // Floor boundary limit with softness 30.0 is 562.032
      expect(physics.center.dy, lessThanOrEqualTo(562.1));
      expect(physics.centerVelocity.dy, lessThanOrEqualTo(0.0)); // bounced up (negative y velocity)
    });
  });

  group('Puni Widget Smoke Tests', () {
    testWidgets('App builds and loads home screen successfully', (WidgetTester tester) async {
      await tester.pumpWidget(const MyApp());
      await tester.pump(const Duration(seconds: 3));
      await tester.pump(const Duration(milliseconds: 500));
      
      // Verify level text HUD exists
      expect(find.textContaining('Lv '), findsOneWidget);
      // Verify step count HUD exists
      expect(find.textContaining('歩'), findsAtLeastNWidgets(1));

      // Unmount the widget tree to cleanly trigger dispose on CreatureState and cancel timers
      await tester.pumpWidget(Container());
      await tester.pump();
    });
  });
}
