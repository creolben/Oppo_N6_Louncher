import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../models/app_entry.dart';

/// Represents an interactive bouncing app sphere on the lock screen.
class AppBubble {
  final AppEntry app;
  Offset position;
  Offset velocity;
  double radius;
  double mass;
  Color color;

  // Visual effects
  double bounceSquash = 1.0; // 1.0 = round, < 1.0 = squashed along collision
  double glowIntensity = 0.0;
  bool isBeingDragged = false;
  Offset? dragOffset;

  AppBubble({
    required this.app,
    required this.position,
    required this.velocity,
    this.radius = 32.0,
    this.mass = 1.0,
    Color? color,
  }) : color = color ?? app.accentColor;
}

/// Dynamic spark particle generated on bubble collision or shake.
class BubbleSpark {
  Offset position;
  Offset velocity;
  Color color;
  double age = 0.0;
  final double maxAge;
  final double initialSize;

  BubbleSpark({
    required this.position,
    required this.velocity,
    required this.color,
    this.maxAge = 0.45,
    this.initialSize = 3.5,
  });

  bool get isDead => age >= maxAge;

  void update(double dt) {
    age += dt;
    position += velocity * dt;
    velocity *= 0.94; // Air resistance
  }
}

/// Expanding celestial shockwave ripple.
class CosmicRipple {
  final Offset center;
  final Color color;
  final double maxRadius;
  final double duration;
  double age = 0.0;

  CosmicRipple({
    required this.center,
    required this.color,
    this.maxRadius = 140.0,
    this.duration = 0.6,
  });

  bool get isDead => age >= duration;
  double get progress => (age / duration).clamp(0.0, 1.0);
  double get currentRadius => maxRadius * Curves.easeOutQuad.transform(progress);
  double get opacity => (1.0 - progress).clamp(0.0, 1.0);

  void update(double dt) {
    age += dt;
  }
}

/// Physics engine governing 2D circular collisions, boundary bounces,
/// ambient cosmic drifts, and explosive shake dispersion.
/// Physics simulation for the lock screen's bouncing app bubbles.
///
/// A [ChangeNotifier] so the painter can repaint from it directly
/// (`CustomPainter(repaint: engine)`): the widget tree stays still while the
/// canvas repaints, instead of the whole lock screen rebuilding per frame.
class BouncingPhysicsEngine extends ChangeNotifier {
  final List<AppBubble> bubbles = [];
  final List<BubbleSpark> sparks = [];
  final List<CosmicRipple> ripples = [];
  final math.Random _random = math.Random();

  Size _viewportSize = Size.zero;
  EdgeInsets _safePadding = EdgeInsets.zero;

  // Accelerometer Gravity Tilt Vector (-1.0 to 1.0)
  Offset tiltVector = Offset.zero;

  Size get viewportSize => _viewportSize;
  EdgeInsets get safePadding => _safePadding;

  void initializeBubbles({
    required List<AppEntry> apps,
    required Size size,
    EdgeInsets padding = const EdgeInsets.symmetric(horizontal: 24, vertical: 80),
  }) {
    _viewportSize = size;
    _safePadding = padding;
    bubbles.clear();
    sparks.clear();
    ripples.clear();

    if (apps.isEmpty || size.width <= 0 || size.height <= 0) return;

    // Sort and prioritize apps: Core & User apps first, obscure system packages last
    final sortedApps = List<AppEntry>.from(apps)..sort((a, b) {
      if (a.category == AppCategory.core && b.category != AppCategory.core) return -1;
      if (b.category == AppCategory.core && a.category != AppCategory.core) return 1;
      if (!a.isSystemApp && b.isSystemApp) return -1;
      if (a.isSystemApp && !b.isSystemApp) return 1;
      return a.label.compareTo(b.label);
    });

    // Curate count so the lockscreen remains elegant, clean, and interactive
    final bool isWide = size.width > 550;
    final int maxApps = isWide ? 18 : 12;
    final curatedApps = sortedApps.take(maxApps).toList();

    // Generous, premium sphere sizing
    final double baseRadius = isWide ? 35.0 : 32.0;

    final double availableWidth = (size.width - padding.horizontal).clamp(100.0, size.width);
    final double availableHeight = (size.height - padding.vertical).clamp(100.0, size.height);

    final double centerX = size.width / 2;
    final double centerY = padding.top + availableHeight * 0.48;

    for (int i = 0; i < curatedApps.length; i++) {
      final app = curatedApps[i];
      final double angle = i * 2.3999632; // Golden ratio angle
      final double distance = 36.0 + (i * 22.0).clamp(0.0, math.min(availableWidth, availableHeight) * 0.40);

      final double x = (centerX + math.cos(angle) * distance)
          .clamp(padding.left + baseRadius, size.width - padding.right - baseRadius);
      final double y = (centerY + math.sin(angle) * distance)
          .clamp(padding.top + baseRadius, size.height - padding.bottom - baseRadius);

      // Tranquil, graceful initial cosmic drift
      final double speed = 18.0 + _random.nextDouble() * 24.0;
      final double moveAngle = _random.nextDouble() * 2 * math.pi;

      bubbles.add(
        AppBubble(
          app: app,
          position: Offset(x, y),
          velocity: Offset(math.cos(moveAngle) * speed, math.sin(moveAngle) * speed),
          radius: baseRadius,
          color: app.accentColor,
        ),
      );
    }

    notifyListeners();
  }

  void resize(Size newSize, {EdgeInsets? padding}) {
    _viewportSize = newSize;
    if (padding != null) _safePadding = padding;
    notifyListeners();
  }

  void update(double dt) {
    if (bubbles.isEmpty || _viewportSize == Size.zero) return;

    // Clamp dt to avoid tunneling
    final double clampedDt = math.min(dt, 0.033);

    final double minX = _safePadding.left;
    final double maxX = _viewportSize.width - _safePadding.right;
    final double minY = _safePadding.top;
    final double maxY = _viewportSize.height - _safePadding.bottom;

    const double restitution = 0.85;
    const double minDriftSpeed = 20.0;
    const double maxSpeed = 1200.0;

    // 1. Position & velocity update + wall bouncing
    for (final bubble in bubbles) {
      if (bubble.isBeingDragged) continue;

      // Apply accelerometer gravity tilt (gently accelerates bubbles in direction of phone tilt)
      if (tiltVector != Offset.zero) {
        bubble.velocity += tiltVector * (320.0 * clampedDt);
      }

      // Update position
      bubble.position += bubble.velocity * clampedDt;

      // Decay glow & squash recovery
      if (bubble.glowIntensity > 0) {
        bubble.glowIntensity = math.max(0.0, bubble.glowIntensity - clampedDt * 2.0);
      }
      if (bubble.bounceSquash < 1.0) {
        bubble.bounceSquash = math.min(1.0, bubble.bounceSquash + clampedDt * 3.5);
      }

      // Smooth deceleration: high-speed fling/shake smoothly relaxes to tranquil drift
      double speed = bubble.velocity.distance;
      if (speed > maxSpeed) {
        bubble.velocity = (bubble.velocity / speed) * maxSpeed;
        speed = maxSpeed;
      } else if (speed > 40.0) {
        // Natural air damping
        bubble.velocity *= math.pow(0.94, clampedDt * 60.0).toDouble();
      } else if (speed < minDriftSpeed && speed > 0.001) {
        // Keep tranquil cosmic floating alive
        bubble.velocity = (bubble.velocity / speed) * minDriftSpeed;
      } else if (speed <= 0.001) {
        final angle = _random.nextDouble() * 2 * math.pi;
        bubble.velocity = Offset(math.cos(angle) * minDriftSpeed, math.sin(angle) * minDriftSpeed);
      }

      // Left boundary
      if (bubble.position.dx - bubble.radius < minX) {
        bubble.position = Offset(minX + bubble.radius, bubble.position.dy);
        bubble.velocity = Offset(-bubble.velocity.dx * restitution, bubble.velocity.dy);
        _triggerWallSpark(bubble.position, const Offset(1, 0), bubble.color);
      }
      // Right boundary
      else if (bubble.position.dx + bubble.radius > maxX) {
        bubble.position = Offset(maxX - bubble.radius, bubble.position.dy);
        bubble.velocity = Offset(-bubble.velocity.dx * restitution, bubble.velocity.dy);
        _triggerWallSpark(bubble.position, const Offset(-1, 0), bubble.color);
      }

      // Top boundary
      if (bubble.position.dy - bubble.radius < minY) {
        bubble.position = Offset(bubble.position.dx, minY + bubble.radius);
        bubble.velocity = Offset(bubble.velocity.dx, -bubble.velocity.dy * restitution);
        _triggerWallSpark(bubble.position, const Offset(0, 1), bubble.color);
      }
      // Bottom boundary
      else if (bubble.position.dy + bubble.radius > maxY) {
        bubble.position = Offset(bubble.position.dx, maxY - bubble.radius);
        bubble.velocity = Offset(bubble.velocity.dx, -bubble.velocity.dy * restitution);
        _triggerWallSpark(bubble.position, const Offset(0, -1), bubble.color);
      }
    }

    // 2. Circle-to-Circle Elastic Collisions
    for (int i = 0; i < bubbles.length; i++) {
      final b1 = bubbles[i];
      for (int j = i + 1; j < bubbles.length; j++) {
        final b2 = bubbles[j];

        final double dx = b2.position.dx - b1.position.dx;
        final double dy = b2.position.dy - b1.position.dy;
        final double distSq = dx * dx + dy * dy;
        final double minDist = b1.radius + b2.radius;

        if (distSq < minDist * minDist) {
          final double dist = math.sqrt(distSq);
          final Offset normal = dist > 0.001
              ? Offset(dx / dist, dy / dist)
              : const Offset(1.0, 0.0);

          // Position De-penetration
          final double overlap = minDist - dist;
          if (!b1.isBeingDragged && !b2.isBeingDragged) {
            b1.position -= normal * (overlap * 0.5);
            b2.position += normal * (overlap * 0.5);
          } else if (b1.isBeingDragged) {
            b2.position += normal * overlap;
          } else if (b2.isBeingDragged) {
            b1.position -= normal * overlap;
          }

          // Elastic collision momentum exchange
          final Offset relVelocity = b2.velocity - b1.velocity;
          final double velAlongNormal = relVelocity.dx * normal.dx + relVelocity.dy * normal.dy;

          // Only resolve if moving towards each other
          if (velAlongNormal < 0) {
            const double bounceRestitution = 0.94;
            final double impulseMag = -(1 + bounceRestitution) * velAlongNormal /
                (1 / b1.mass + 1 / b2.mass);
            final Offset impulse = normal * impulseMag;

            if (!b1.isBeingDragged) b1.velocity -= impulse / b1.mass;
            if (!b2.isBeingDragged) b2.velocity += impulse / b2.mass;

            // Visual impact reactions
            final double impactIntensity = (-velAlongNormal / 250.0).clamp(0.2, 1.0);
            b1.bounceSquash = (1.0 - impactIntensity * 0.18).clamp(0.78, 1.0);
            b2.bounceSquash = (1.0 - impactIntensity * 0.18).clamp(0.78, 1.0);
            b1.glowIntensity = math.min(1.0, b1.glowIntensity + impactIntensity * 0.8);
            b2.glowIntensity = math.min(1.0, b2.glowIntensity + impactIntensity * 0.8);

            // Spawn collision contact sparks
            final Offset contactPoint = b1.position + normal * b1.radius;
            _spawnCollisionSparks(contactPoint, b1.color, b2.color, impactIntensity);
          }
        }
      }
    }

    // 3. Update sparks
    for (int i = sparks.length - 1; i >= 0; i--) {
      final spark = sparks[i];
      spark.update(clampedDt);
      if (spark.isDead) sparks.removeAt(i);
    }

    // 4. Update ripples
    for (int i = ripples.length - 1; i >= 0; i--) {
      final ripple = ripples[i];
      ripple.update(clampedDt);
      if (ripple.isDead) ripples.removeAt(i);
    }

    // The painter listens to this and repaints only its own layer.
    notifyListeners();
  }

  /// Explosively scatter all app bubbles outwards when the phone is shaken.
  void triggerShakeScatter({
    Offset? focalPoint,
    double strength = 1.0,
  }) {
    if (bubbles.isEmpty) return;

    final Offset center = focalPoint ??
        Offset(_viewportSize.width / 2, _viewportSize.height * 0.52);

    // Spawn massive shockwave ripple
    ripples.add(
      CosmicRipple(
        center: center,
        color: const Color(0xFF00E5FF),
        maxRadius: math.max(_viewportSize.width, _viewportSize.height) * 0.85,
        duration: 0.75,
      ),
    );

    // Secondary warm ripple
    ripples.add(
      CosmicRipple(
        center: center,
        color: const Color(0xFF7C4DFF),
        maxRadius: math.max(_viewportSize.width, _viewportSize.height) * 0.65,
        duration: 0.85,
      ),
    );

    for (int i = 0; i < bubbles.length; i++) {
      final bubble = bubbles[i];
      final double dx = bubble.position.dx - center.dx;
      final double dy = bubble.position.dy - center.dy;
      final double dist = math.sqrt(dx * dx + dy * dy);

      double angle;
      if (dist < 10.0) {
        // Centered bubble gets random direction
        angle = (i * (2 * math.pi / bubbles.length)) + _random.nextDouble() * 0.5;
      } else {
        angle = math.atan2(dy, dx) + (_random.nextDouble() - 0.5) * 0.6;
      }

      // Scatter impulse: explosive fling velocity
      final double speed = (700.0 + _random.nextDouble() * 850.0) * strength;
      bubble.velocity = Offset(math.cos(angle) * speed, math.sin(angle) * speed);
      bubble.glowIntensity = 1.0;
      bubble.bounceSquash = 0.82;

      // Spawn trail of sparks per bubble
      _spawnCollisionSparks(bubble.position, bubble.color, const Color(0xFF00E5FF), 1.0, count: 5);
    }

    notifyListeners();
  }

  /// Asks the painter to redraw without simulating a step.
  ///
  /// Direct manipulation (a drag moving a bubble) changes what is on screen
  /// without going through [update], so it has to repaint even when the
  /// simulation ticker is stopped for reduce-motion.
  void markDirty() => notifyListeners();

  AppBubble? findBubbleAt(Offset screenPos) {
    for (int i = bubbles.length - 1; i >= 0; i--) {
      final b = bubbles[i];
      final double distSq = (b.position - screenPos).distanceSquared;
      // Generous hit box for touch accuracy
      if (distSq <= (b.radius * 1.3) * (b.radius * 1.3)) {
        return b;
      }
    }
    return null;
  }

  void _triggerWallSpark(Offset pos, Offset normal, Color color) {
    if (sparks.length > 80) return;
    for (int i = 0; i < 3; i++) {
      final double angle = math.atan2(normal.dy, normal.dx) +
          (_random.nextDouble() - 0.5) * 1.2;
      final double speed = 50.0 + _random.nextDouble() * 100.0;
      sparks.add(
        BubbleSpark(
          position: pos,
          velocity: Offset(math.cos(angle) * speed, math.sin(angle) * speed),
          color: color,
          maxAge: 0.35,
          initialSize: 3.0,
        ),
      );
    }
  }

  void _spawnCollisionSparks(
    Offset contactPoint,
    Color color1,
    Color color2,
    double intensity, {
    int count = 4,
  }) {
    if (sparks.length > 90) return;
    final int actualCount = (count * intensity).clamp(2, 6).toInt();
    for (int i = 0; i < actualCount; i++) {
      final double angle = _random.nextDouble() * 2 * math.pi;
      final double speed = (60.0 + _random.nextDouble() * 160.0) * intensity;
      final Color sparkColor = _random.nextBool() ? color1 : color2;
      sparks.add(
        BubbleSpark(
          position: contactPoint,
          velocity: Offset(math.cos(angle) * speed, math.sin(angle) * speed),
          color: sparkColor,
          maxAge: 0.28 + _random.nextDouble() * 0.15,
          initialSize: 2.5 + intensity * 1.5,
        ),
      );
    }
  }
}
