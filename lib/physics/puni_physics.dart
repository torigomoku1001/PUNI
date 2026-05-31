import 'dart:math';
import 'package:flutter/material.dart';

class PuniPhysics {
  static const int nodeCount = 12;
  static const double baseRadius = 38.0;

  // Center node state
  Offset center = const Offset(200, 400);
  Offset centerVelocity = Offset.zero;

  // Boundary nodes state (offsets relative to the center)
  List<Offset> nodePositions = [];
  List<Offset> nodeVelocities = [];

  PuniPhysics() {
    _initializeNodes();
  }

  void _initializeNodes() {
    nodePositions = List.generate(nodeCount, (i) {
      double angle = i * 2 * pi / nodeCount;
      return Offset(cos(angle) * baseRadius, sin(angle) * baseRadius);
    });
    nodeVelocities = List.generate(nodeCount, (_) => Offset.zero);
  }

  /// Calculates target offsets relative to the center based on the shape type.
  List<Offset> getTargetOffsets(String shape, double radius) {
    return List.generate(nodeCount, (i) {
      double angle = i * 2 * pi / nodeCount;
      Offset offset;

      switch (shape) {
        case 'square':
          // Map circle to rounded square
          double x = cos(angle);
          double y = sin(angle);
          double sx = x.sign * (x.abs() > 0.1 ? 1.0 : x.abs()) * 0.9;
          double sy = y.sign * (y.abs() > 0.1 ? 1.0 : y.abs()) * 0.9;
          double factor = 0.35;
          offset = Offset(
            (sx * (1 - factor) + x * factor) * radius * 1.1,
            (sy * (1 - factor) + y * factor) * radius * 1.1,
          );
          break;

        case 'stretch':
          // Tall stretch (背伸ばし)
          offset = Offset(
            cos(angle) * radius * 0.65,
            sin(angle) * radius * 1.55,
          );
          break;

        case 'round':
          // Perfect sphere (球体)
          offset = Offset(cos(angle) * radius * 1.1, sin(angle) * radius * 1.1);
          break;

        case 'dent':
          // Cushion-like dent (凹ませ)
          double x = cos(angle);
          double y = sin(angle);
          double r = radius * (1.0 + 0.18 * cos(4 * angle));
          offset = Offset(x * r, y * r);
          break;

        case 'triangle':
          // Flat bottom, pointed top (三角・ピラミッド形)
          double x = cos(angle);
          double y = sin(
            angle,
          ); // Flutter Y is down (top is negative, bottom is positive)
          double tx = x * radius * 0.95 * (1.0 + y);
          double ty = y * radius * 0.85;
          if (y > 0.0) {
            ty = ty * 0.15 + (radius * 0.85) * 0.85; // Flatten bottom
          }
          offset = Offset(tx, ty);
          break;

        case 'heart':
          // Lobby top (y < 0), pointy bottom (y > 0) (ハート形)
          double x = cos(angle);
          double y = sin(angle);
          double tx = x * radius * 1.1;
          double ty = y * radius * 0.95;
          if (y < 0.0) {
            // Indent the top center
            double indent = 1.0 - 0.45 * exp(-6.0 * x * x);
            tx *= indent * 1.15;
            ty *= 1.1;
          } else {
            // Taper bottom point
            tx *= (1.0 - y * 0.45);
            ty *= 1.1;
          }
          offset = Offset(tx, ty);
          break;

        case 'star':
          // Five-pointed star (星形)
          double x = cos(angle);
          double y = sin(angle);
          double r = radius * (0.85 + 0.32 * cos(5.0 * angle));
          offset = Offset(x * r, y * r);
          break;

        case 'default':
        default:
          // Flat-bottomed trapezoid slime shape matching user's ASCII art:
          //      ------
          //     /      \
          //    /        \
          //  ------------
          double x = cos(angle);
          double y = sin(angle);
          double widthFactor =
              1.0 + y * 0.35; // wider at bottom, narrower at top
          double tx = x * radius * 1.15 * widthFactor;
          double ty = y * radius * 0.85;

          if (y > 0.1) {
            ty =
                ty * 0.25 +
                (radius * 0.85) * 0.75; // Flatten the bottom line cleanly
          }
          if (y < -0.1) {
            ty =
                ty * 0.45 -
                (radius * 0.6) * 0.55; // Flatten the top line cleanly
          }
          offset = Offset(tx, ty);
          break;
      }

      return offset;
    });
  }

  /// Reset physics state (e.g. when spawning, morphing shape)
  void reset(Offset newCenter, String shape) {
    center = newCenter;
    centerVelocity = Offset.zero;
    List<Offset> targets = getTargetOffsets(shape, baseRadius);
    for (int i = 0; i < nodeCount; i++) {
      nodePositions[i] = targets[i];
      nodeVelocities[i] = Offset.zero;
    }
  }

  /// Step the simulation forward.
  /// [dt] is elapsed time in seconds.
  /// [boundary] is the interactive container size.
  /// [softness] ranges from 0.0 (stiff rubber) to 100.0 (almost liquid).
  /// [gravityVector] allows accelerometer-based tilt gravity (or defaults to down).
  void update({
    required double dt,
    required Size boundary,
    required double softness,
    required String shape,
    required Offset? touchPosition,
    required bool isDragging,
    required bool isPetting,
    required Offset gravityVector,
    required bool isCharging,
    bool isPinching = false,
    Offset? pinchVector,
    double pinchDistanceRatio = 1.0,
    double inflationScale = 1.0,
    bool isFollowing = false,
    Offset? followPosition,
    bool isSleeping = false,
    VoidCallback? onBounce,
  }) {
    // Avoid division by zero or huge time steps
    if (dt <= 0.0) return;
    if (dt > 0.03) dt = 0.016; // Cap at ~60fps to prevent instability

    double breathingMultiplier = 1.0;
    final timeSec = DateTime.now().millisecondsSinceEpoch / 1000.0;
    if (isSleeping) {
      // Slower, deeper breathing in sleep mode
      breathingMultiplier = 1.0 + 0.04 * sin(timeSec * 1.8);
    } else {
      // Regular gentle breathing
      breathingMultiplier = 1.0 + 0.015 * sin(timeSec * 3.5);
    }

    double currentRadius = baseRadius * inflationScale * breathingMultiplier;

    // Define physics parameters based on softness
    // Softness scale: 0.0 (stiff/elastic) -> 100.0 (soft/watery)
    double softnessPct = (softness / 100.0).clamp(0.0, 1.0);

    // Spring constants: how fast it snaps back to target shape
    // Non-linear power scale: extremely stiff at Lv 1 (1180+), and incredibly soft/watery at Lv 100 (10.5)
    double springCenter = 1200.0 * pow(1.0 - softnessPct, 1.8).toDouble() + 5.0;
    double springNeighbors =
        900.0 * pow(1.0 - softnessPct, 1.8).toDouble() + 3.0;

    // Damping: energy loss (viscosity)
    // Low damping at high softness allows for beautiful, persistent wobbles and jiggles!
    double dampingOuter = 3.2 - softnessPct * 1.6;
    double dampingCenter = 1.2 - softnessPct * 0.6;

    // Pressure/Volume preservation factor (tries to keep the area constant)
    double pressureCoefficient = 12.0 + (2.5 - 12.0) * softnessPct;

    // Static Physical Boundaries of the Screen
    const double margin = 20.0;
    final double leftWall = margin;
    final double rightWall = boundary.width - margin;
    final double ceilingY = margin + 40.0; // Margin + HUD space
    final double floorY =
        boundary.height -
        margin -
        190.0; // Raised bottom margin to clear menu bar (height - 210.0)

    // Allow the center of mass to go closer to the walls at high softness
    // At Lv 1 (softness 1%): center limit is nearly 100% of currentRadius away (no squish)
    // At Lv 100 (softness 95%): center limit can get down to 12% of currentRadius away (allowing huge flat squish!)
    double centerMargin = currentRadius * (1.0 - softnessPct * 0.72);
    double left = leftWall + centerMargin;
    double right = rightWall - centerMargin;
    double top = ceilingY + centerMargin;
    double bottom = floorY - centerMargin;

    // 1. UPDATE CENTER NODE
    bool isPulling = isDragging || (isFollowing && followPosition != null);
    Offset? pullTarget = isDragging ? touchPosition : followPosition;

    if (isPulling && pullTarget != null) {
      // Follow the touch/follow point with easing
      Offset targetCenter = pullTarget;
      // Clamp target center to boundary to keep creature from being dragged offscreen
      targetCenter = Offset(
        targetCenter.dx.clamp(left, right),
        targetCenter.dy.clamp(top, bottom),
      );

      if (isDragging) {
        Offset pullForce = (targetCenter - center) * 30.0;
        centerVelocity = Offset.lerp(centerVelocity, pullForce, 0.35)!;
        final pullSpeed = centerVelocity.distance;
        const maxPullSpeed = 2500.0;
        if (pullSpeed > maxPullSpeed) {
          centerVelocity = (centerVelocity / pullSpeed) * maxPullSpeed;
        }
        center += centerVelocity * dt;
      } else {
        // Living creature follow behavior (gentle drift + swim wiggle)
        double dist = (targetCenter - center).distance;
        if (dist > 5.0) {
          Offset dir = (targetCenter - center) / dist;
          // Limit maximum speed to ~140.0 pixels per second (very gentle and cute)
          double targetSpeed = (dist * 2.5).clamp(0.0, 140.0);

          // Add a tiny sinusoidal perpendicular swimming wiggle to make it look alive!
          // Frequency: ~3.5Hz, Amplitude: ~25.0 pixels/sec
          double timeSec = DateTime.now().millisecondsSinceEpoch / 1000.0;
          Offset wiggle = Offset(-dir.dy, dir.dx) * sin(timeSec * 7.0) * 25.0;

          Offset desiredVelocity = dir * targetSpeed + wiggle;
          centerVelocity = Offset.lerp(centerVelocity, desiredVelocity, 0.08)!;
        } else {
          // Arrived: hover/hovering float
          double timeSec = DateTime.now().millisecondsSinceEpoch / 1000.0;
          Offset hover = Offset(cos(timeSec * 2.0) * 8.0, sin(timeSec * 1.5) * 8.0);
          centerVelocity = Offset.lerp(centerVelocity, hover, 0.05)!;
        }
        center += centerVelocity * dt;
      }
    } else {
      // Free falling/sliding
      centerVelocity += gravityVector * dt;
      centerVelocity *= (1.0 - dampingCenter * dt);
      center += centerVelocity * dt;
    }

    // Bounce center from boundaries to prevent escaping
    bool didBounce = false;
    if (center.dy > bottom) {
      if (centerVelocity.dy.abs() > 120.0) didBounce = true;
      center = Offset(center.dx, bottom);
      centerVelocity = Offset(
        centerVelocity.dx * 0.8,
        -centerVelocity.dy.abs() * 0.5,
      );
    } else if (center.dy < top) {
      if (centerVelocity.dy.abs() > 120.0) didBounce = true;
      center = Offset(center.dx, top);
      centerVelocity = Offset(
        centerVelocity.dx * 0.8,
        centerVelocity.dy.abs() * 0.5,
      );
    }
    if (center.dx < left) {
      if (centerVelocity.dx.abs() > 120.0) didBounce = true;
      center = Offset(left, center.dy);
      centerVelocity = Offset(
        centerVelocity.dx.abs() * 0.5,
        centerVelocity.dy * 0.8,
      );
    } else if (center.dx > right) {
      if (centerVelocity.dx.abs() > 120.0) didBounce = true;
      center = Offset(right, center.dy);
      centerVelocity = Offset(
        -centerVelocity.dx.abs() * 0.5,
        centerVelocity.dy * 0.8,
      );
    }

    if (didBounce && onBounce != null) {
      onBounce();
    }

    // 2. CALC TARGET SHAPE OFFSETS
    List<Offset> targetOffsets = getTargetOffsets(shape, currentRadius);

    // Apply taffy pinch-to-stretch if pinching (two fingers) or dragging (one finger)
    if (isPinching && pinchVector != null) {
      double dist = pinchVector.distance;
      if (dist > 8.0) {
        Offset pinchDir = pinchVector / dist;
        // Clamp stretch factor: from 0.5 (contracted) up to 2.2x (highly stretched)
        double scaleParallel = pinchDistanceRatio.clamp(0.5, 2.2);
        double scalePerpendicular = 1.0 / sqrt(scaleParallel);

        for (int i = 0; i < nodeCount; i++) {
          Offset baseOffset = targetOffsets[i];
          double dot = baseOffset.dx * pinchDir.dx + baseOffset.dy * pinchDir.dy;
          Offset parallelPart = pinchDir * dot;
          Offset perpPart = baseOffset - parallelPart;
          targetOffsets[i] =
              parallelPart * scaleParallel + perpPart * scalePerpendicular;
        }
      }
    } else if (isDragging && touchPosition != null) {
      Offset dragVec = touchPosition - center;
      double dragDistance = dragVec.distance;
      if (dragDistance > 8.0) {
        Offset dragDir = dragVec / dragDistance;
        double stretchFactor = (dragDistance / currentRadius).clamp(0.0, 0.8);
        double scaleParallel =
            1.0 + stretchFactor * 0.55; // Stretch up to 1.44x
        double scalePerpendicular =
            1.0 / sqrt(scaleParallel); // Compress to preserve 2D area

        for (int i = 0; i < nodeCount; i++) {
          Offset baseOffset = targetOffsets[i];
          double dot = baseOffset.dx * dragDir.dx + baseOffset.dy * dragDir.dy;
          Offset parallelPart = dragDir * dot;
          Offset perpPart = baseOffset - parallelPart;
          targetOffsets[i] =
              parallelPart * scaleParallel + perpPart * scalePerpendicular;
        }
      }
    }

    double targetArea = pi * currentRadius * currentRadius;

    // Calculate current polygon area for volume conservation
    double currentArea = 0.0;
    for (int i = 0; i < nodeCount; i++) {
      Offset p1 = center + nodePositions[i];
      Offset p2 = center + nodePositions[(i + 1) % nodeCount];
      currentArea += (p1.dx * p2.dy - p2.dx * p1.dy);
    }
    currentArea = currentArea.abs() / 2.0;
    if (currentArea < 0.1) currentArea = 0.1;

    // Pressure force magnitude: pushes nodes outward if compressed
    double areaDiff = targetArea - currentArea;
    double pressureForce = areaDiff * pressureCoefficient;

    // 3. CALCULATE FORCES ON OUTER NODES
    List<Offset> nodeForces = List.generate(nodeCount, (_) => Offset.zero);

    for (int i = 0; i < nodeCount; i++) {
      Offset pos = nodePositions[i];

      // Force 1: Center restoration spring (pulls towards target offset relative to center)
      Offset targetOffset = targetOffsets[i];
      Offset springForceCenter = (targetOffset - pos) * springCenter;
      nodeForces[i] += springForceCenter;

      // Force 2: Neighboring springs (maintains perimeter tension)
      Offset nextPos = nodePositions[(i + 1) % nodeCount];
      Offset prevPos = nodePositions[(i - 1 + nodeCount) % nodeCount];

      double targetNeighborDist =
          (targetOffsets[(i + 1) % nodeCount] - targetOffset).distance;
      Offset toNext = nextPos - pos;
      double nextDist = toNext.distance;
      if (nextDist > 0.001) {
        nodeForces[i] +=
            (toNext / nextDist) *
            (nextDist - targetNeighborDist) *
            springNeighbors;
      }

      double targetPrevNeighborDist =
          (targetOffsets[(i - 1 + nodeCount) % nodeCount] - targetOffset)
              .distance;
      Offset toPrev = prevPos - pos;
      double prevDist = toPrev.distance;
      if (prevDist > 0.001) {
        nodeForces[i] +=
            (toPrev / prevDist) *
            (prevDist - targetPrevNeighborDist) *
            springNeighbors;
      }

      // Force 3: Volume / Pressure Force (points radially outward in target direction to prevent inversion flips)
      double targetDist = targetOffset.distance;
      if (targetDist > 0.001) {
        Offset outwardDir = targetOffset / targetDist;
        nodeForces[i] += outwardDir * pressureForce;
      }

      // Force 4: User Petting interaction (gentle ripple vibration)
      if (isPetting && touchPosition != null) {
        Offset absPos = center + pos;
        double distToFinger = (absPos - touchPosition).distance;
        if (distToFinger < 100.0) {
          // Rippling push away from finger
          Offset pushDir = absPos - touchPosition;
          double pushDist = pushDir.distance;
          if (pushDist > 0.1) {
            // High frequency rippling vibration force
            double rippleForce =
                (1.0 - (pushDist / 100.0)) *
                600.0 *
                sin(pos.dx * 0.15 + pos.dy * 0.15);
            nodeForces[i] += (pushDir / pushDist) * rippleForce;
          }
        }
      }

      // Force 5: Charging electrical jitter/shiver
      if (isCharging) {
        double time = DateTime.now().millisecondsSinceEpoch / 1000.0;
        double jitterX = sin(time * 65.0 + i * 2.0) * 160.0;
        double jitterY = cos(time * 65.0 - i * 2.0) * 160.0;
        nodeForces[i] += Offset(jitterX, jitterY);
      }
    }

    // 4. INTEGRATE & COLLIDE OUTER NODES
    for (int i = 0; i < nodeCount; i++) {
      // Update velocities
      nodeVelocities[i] += nodeForces[i] * dt;

      // Node gravity is added if not dragging center (inertia lag)
      if (!isDragging) {
        nodeVelocities[i] += gravityVector * 0.2 * dt;
      }

      // Apply damping
      nodeVelocities[i] *= (1.0 - dampingOuter * dt);

      // Clamp node velocity to prevent high-impact explosions
      double speed = nodeVelocities[i].distance;
      const double maxSpeed = 750.0;
      if (speed > maxSpeed) {
        nodeVelocities[i] = (nodeVelocities[i] / speed) * maxSpeed;
      }

      // Update relative positions
      nodePositions[i] += nodeVelocities[i] * dt;

      // RIGIDITY AND TARGET SHAPE ENFORCEMENT BASED ON LEVEL/SOFTNESS
      double rigidityFactor = pow(1.0 - softnessPct, 3.2).toDouble();
      Offset targetOffset = targetOffsets[i];
      nodePositions[i] = Offset.lerp(
        nodePositions[i],
        targetOffset,
        rigidityFactor * 0.95,
      )!;
      nodeVelocities[i] = Offset.lerp(
        nodeVelocities[i],
        Offset.zero,
        rigidityFactor * 0.95,
      )!;

      // Keep nodes within a safe physical distance from center to prevent collapse/explosion
      double distFromCenter = nodePositions[i].distance;
      if (distFromCenter < 6.0) {
        nodePositions[i] =
            (nodePositions[i] /
                (distFromCenter > 0.01 ? distFromCenter : 1.0)) *
            6.0;
      } else if (distFromCenter > currentRadius * 2.2) {
        nodePositions[i] =
            (nodePositions[i] / distFromCenter) * (currentRadius * 2.2);
      }

      // Wall collision for absolute node positions using the exact physical wall boundaries:
      // This allows soft Punis to squish/deform heavily against walls, while rigid ones keep their shapes.
      Offset absPos = center + nodePositions[i];

      double nodeBounce = 0.45;
      double slideDamp = 0.75;

      if (absPos.dy > floorY) {
        double overlap = absPos.dy - floorY;
        nodePositions[i] = Offset(
          nodePositions[i].dx,
          nodePositions[i].dy - overlap,
        );
        // Bounce and slow down sliding
        double vY = -nodeVelocities[i].dy.abs() * nodeBounce;
        double vX = nodeVelocities[i].dx * slideDamp;
        nodeVelocities[i] = Offset(vX, vY);
      } else if (absPos.dy < ceilingY) {
        double overlap = ceilingY - absPos.dy;
        nodePositions[i] = Offset(
          nodePositions[i].dx,
          nodePositions[i].dy + overlap,
        );
        double vY = nodeVelocities[i].dy.abs() * nodeBounce;
        double vX = nodeVelocities[i].dx * slideDamp;
        nodeVelocities[i] = Offset(vX, vY);
      }

      if (absPos.dx < leftWall) {
        double overlap = leftWall - absPos.dx;
        nodePositions[i] = Offset(
          nodePositions[i].dx + overlap,
          nodePositions[i].dy,
        );
        double vX = nodeVelocities[i].dx.abs() * nodeBounce;
        double vY = nodeVelocities[i].dy * slideDamp;
        nodeVelocities[i] = Offset(vX, vY);
      } else if (absPos.dx > rightWall) {
        double overlap = absPos.dx - rightWall;
        nodePositions[i] = Offset(
          nodePositions[i].dx - overlap,
          nodePositions[i].dy,
        );
        double vX = -nodeVelocities[i].dx.abs() * nodeBounce;
        double vY = nodeVelocities[i].dy * slideDamp;
        nodeVelocities[i] = Offset(vX, vY);
      }
    }
  }

  double lerpDouble(double a, double b, double t) {
    return a + (b - a) * t;
  }
}
