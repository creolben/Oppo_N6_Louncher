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

  /// The centre of the cell this sphere was laid out in. The drift is gently
  /// pulled back toward it, and the cell cap in [BouncingPhysicsEngine.update]
  /// is measured from it.
  Offset homePosition = Offset.zero;

  /// How far the sphere may drift from [homePosition] on each axis. The cap
  /// also intersects this with the band, so a sphere laid out on the band edge
  /// can still drift inward but never paints past the edge.
  Offset homeRange = Offset.zero;

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

/// Physics engine governing 2D circular collisions, boundary bounces,
/// ambient cosmic drifts, and explosive shake dispersion.
/// Physics simulation for the lock screen's bouncing app bubbles.
///
/// A [ChangeNotifier] so the painter can repaint from it directly
/// (`CustomPainter(repaint: engine)`): the widget tree stays still while the
/// canvas repaints, instead of the whole lock screen rebuilding per frame.
class BouncingPhysicsEngine extends ChangeNotifier {
  final List<AppBubble> bubbles = [];
  final math.Random _random = math.Random();

  Size _viewportSize = Size.zero;
  EdgeInsets _safePadding = EdgeInsets.zero;

  /// The empty space kept between two ring edges.
  ///
  /// The initial grid leaves it, the band change re-establishes it, and the
  /// per-frame collision pass treats it as part of the collision distance so
  /// the gap survives the drift instead of closing as soon as spheres move.
  static const double minBubbleSeparation = 12.0;

  /// How far the painted aura reaches past a sphere's core radius.
  ///
  /// The painter draws the glow at [paintedRadius], so confinement has to use
  /// the same extent or the aura bleeds under the HUD.
  static const double auraScale = 1.55;

  /// The radius the painter actually covers for a sphere of [radius].
  static double paintedRadius(double radius) => radius * auraScale;

  /// A band change larger than this on any side re-runs the cell placement
  /// instead of clamping the old grid against one edge.
  static const double rebandThreshold = 8.0;

  /// Spring pull toward the cell centre. Deliberately weak: the drift must
  /// still read as drift, not as spheres snapping to a lattice.
  static const double _cellSpring = 0.05;

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

    if (apps.isEmpty || size.width <= 0 || size.height <= 0) return;

    // Sort and prioritize apps: Core & User apps first, obscure system packages last
    final sortedApps = List<AppEntry>.from(apps)..sort((a, b) {
      if (a.category == AppCategory.core && b.category != AppCategory.core) return -1;
      if (b.category == AppCategory.core && a.category != AppCategory.core) return 1;
      if (!a.isSystemApp && b.isSystemApp) return -1;
      if (a.isSystemApp && !b.isSystemApp) return 1;
      return a.label.compareTo(b.label);
    });

    // The field is ambient decoration now, not a touch surface: eight spheres
    // are enough to read as a constellation, and more would only collide into
    // visual noise behind the HUD.
    final int maxApps = 8;
    for (final app in sortedApps.take(maxApps)) {
      bubbles.add(
        AppBubble(
          app: app,
          position: Offset(size.width / 2, size.height / 2),
          velocity: Offset.zero,
          color: app.accentColor,
        ),
      );
    }

    _placeInBand(preserveVelocity: false);
    notifyListeners();
  }

  /// Lays the spheres out in evenly spaced cells across the current band.
  ///
  /// Each row spans the full usable width — one sphere per slot, the outermost
  /// flush with the usable edge — so the field reads across the band instead of
  /// piling against one side after a re-band. A little vertical jitter keeps a
  /// row from looking ruled. [preserveVelocity] carries the existing drift
  /// through a re-band; a fresh field gets a new slow drift instead.
  void _placeInBand({bool preserveVelocity = true}) {
    final int count = bubbles.length;
    if (count == 0 || _viewportSize == Size.zero) return;

    final bool isWide = _viewportSize.width > 550;
    final double radius = isWide ? 30.0 : 26.0;
    final double painted = paintedRadius(radius);
    final double minX = _safePadding.left;
    final double maxX = _viewportSize.width - _safePadding.right;
    final double minY = _safePadding.top;
    final double maxY = _viewportSize.height - _safePadding.bottom;
    final double usableLeft = minX + painted;
    final double usableRight = maxX - painted;
    final double usableTop = minY + painted;
    final double usableBottom = maxY - painted;
    final double usableW = math.max(0.0, usableRight - usableLeft);
    final double usableH = math.max(0.0, usableBottom - usableTop);

    // A near-square column count keeps the rows balanced whatever the band.
    int cols = 1;
    if (count > 1 && usableW > 0 && usableH > 0) {
      cols = math.sqrt(count * usableW / usableH).ceil().clamp(1, count);
    }
    final int rows = (count / cols).ceil();
    final double cellH = rows > 0 ? usableH / rows : usableH;

    for (int i = 0; i < count; i++) {
      final bubble = bubbles[i];
      bubble.radius = radius;

      final int row = i ~/ cols;
      final int col = i % cols;
      final int rowCount = math.min(cols, count - row * cols);

      final double centreY = usableH <= 0
          ? (usableTop + usableBottom) / 2
          : usableTop + cellH * (row + 0.5);
      final double centreX = rowCount <= 1
          ? usableLeft + usableW / 2
          : usableLeft + usableW * col / (rowCount - 1);

      // A sphere may drift half a cell from home on each axis; the cap in
      // [update] intersects that with the band so the painted aura stays in.
      final double halfSpacing = rowCount > 1
          ? (usableW / (rowCount - 1)) / 2
          : usableW / 2;
      final double jitterY = cellH * 0.25;

      bubble.homePosition = Offset(centreX, centreY);
      bubble.homeRange = Offset(halfSpacing, cellH / 2);
      bubble.position = Offset(
        centreX,
        _clamp(
          centreY + (_random.nextDouble() * 2 - 1) * jitterY,
          usableTop,
          usableBottom,
        ),
      );

      if (!preserveVelocity || bubble.velocity == Offset.zero) {
        // A slow, tidal drift — the field should look alive, never busy.
        final double speed = 7.0 + _random.nextDouble() * 10.0;
        final double angle = _random.nextDouble() * 2 * math.pi;
        bubble.velocity = Offset(math.cos(angle) * speed, math.sin(angle) * speed);
      }
    }

    _resolveOverlaps();
  }

  void resize(Size newSize, {EdgeInsets? padding}) {
    final bool sizeChanged = _viewportSize != newSize;
    _viewportSize = newSize;
    if (padding != null) _safePadding = padding;
    if (sizeChanged && bubbles.isNotEmpty) {
      // A different viewport is a different grid, not a clamp.
      _placeInBand();
    } else {
      _clampAllToBounds();
      _resolveOverlaps();
    }
    notifyListeners();
  }

  /// Confines the simulation to [bounds] in viewport coordinates.
  ///
  /// The lock surface hands the physics layer the rectangle between its last
  /// HUD element and the unlock hint, measured after layout. A band that
  /// changes (the now-playing card appearing, a text-scale change) re-lays the
  /// spheres out inside the new band, so the field spreads across it instead of
  /// clamping the old grid against one edge; only a band that barely moved is
  /// handled by a fresh clamp.
  void setBounds(Rect bounds, {Size? viewport}) {
    final Size size = viewport ?? _viewportSize;
    if (size.width <= 0 || size.height <= 0) return;
    final EdgeInsets next = EdgeInsets.fromLTRB(
      bounds.left,
      bounds.top,
      size.width - bounds.right,
      size.height - bounds.bottom,
    );
    if (_viewportSize == size && _safePadding == next) return;
    final bool sizeChanged = _viewportSize != size;
    final bool bandMoved =
        (_safePadding.left - next.left).abs() > rebandThreshold ||
        (_safePadding.right - next.right).abs() > rebandThreshold ||
        (_safePadding.top - next.top).abs() > rebandThreshold ||
        (_safePadding.bottom - next.bottom).abs() > rebandThreshold;
    _viewportSize = size;
    _safePadding = next;
    if (bubbles.isNotEmpty && (sizeChanged || bandMoved)) {
      // The old grid is the wrong shape for this band: lay it out again
      // instead of clamping every sphere against the nearer edge.
      _placeInBand();
    } else {
      _clampAllToBounds();
      _resolveOverlaps();
    }
    notifyListeners();
  }

  /// Keeps a value inside [lower]..[upper], tolerating an inverted pair.
  ///
  /// A band narrower than a sphere's diameter would otherwise make
  /// `num.clamp` throw; the midpoint is the only honest answer there, and the
  /// panel never leaves the band that tight in practice.
  static double _clamp(double value, double lower, double upper) {
    if (upper <= lower) return (lower + upper) / 2;
    return value.clamp(lower, upper);
  }

  void _clampAllToBounds() {
    if (_viewportSize == Size.zero) return;
    for (final bubble in bubbles) {
      final double painted = paintedRadius(bubble.radius);
      bubble.position = Offset(
        _clamp(
          bubble.position.dx,
          _safePadding.left + painted,
          _viewportSize.width - _safePadding.right - painted,
        ),
        _clamp(
          bubble.position.dy,
          _safePadding.top + painted,
          _viewportSize.height - _safePadding.bottom - painted,
        ),
      );
    }
  }

  /// Pushes apart any pair closer than their radii plus [minBubbleSeparation].
  ///
  /// Used when the band changes rather than per frame: a re-clamp can squeeze
  /// the outer row inward, and waiting for the ticker to untangle it would show
  /// overlapping rings for one frame. A handful of passes settles <= 8 spheres;
  /// the per-frame collision pass in [update] holds the gap afterwards.
  void _resolveOverlaps() {
    if (bubbles.length < 2) return;
    for (int pass = 0; pass < 4; pass++) {
      var moved = false;
      for (int i = 0; i < bubbles.length; i++) {
        for (int j = i + 1; j < bubbles.length; j++) {
          final b1 = bubbles[i];
          final b2 = bubbles[j];
          final double dx = b2.position.dx - b1.position.dx;
          final double dy = b2.position.dy - b1.position.dy;
          final double distSq = dx * dx + dy * dy;
          final double minDist =
              b1.radius + b2.radius + minBubbleSeparation;
          if (distSq >= minDist * minDist) continue;

          final double dist = math.sqrt(distSq);
          final Offset normal = dist > 0.001
              ? Offset(dx / dist, dy / dist)
              : const Offset(1.0, 0.0);
          final double overlap = (minDist - dist) * 0.5;
          b1.position -= normal * overlap;
          b2.position += normal * overlap;
          moved = true;
        }
      }
      _clampAllToBounds();
      if (!moved) break;
    }
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
    const double minDriftSpeed = 7.0;
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

      // A weak spring pulls the drift back toward the sphere's own cell. Weak
      // on purpose: the field must still read as drift, not as a lattice.
      if (bubble.homeRange != Offset.zero) {
        bubble.velocity +=
            (bubble.homePosition - bubble.position) * _cellSpring * clampedDt;
      }

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

      // The aura is what the eye reads as the sphere, so the wall bounce keeps
      // the painted extent inside the band, not just the core.
      final double painted = paintedRadius(bubble.radius);

      // Left boundary
      if (bubble.position.dx - painted < minX) {
        bubble.position = Offset(minX + painted, bubble.position.dy);
        bubble.velocity = Offset(-bubble.velocity.dx * restitution, bubble.velocity.dy);
      }
      // Right boundary
      else if (bubble.position.dx + painted > maxX) {
        bubble.position = Offset(maxX - painted, bubble.position.dy);
        bubble.velocity = Offset(-bubble.velocity.dx * restitution, bubble.velocity.dy);
      }

      // Top boundary
      if (bubble.position.dy - painted < minY) {
        bubble.position = Offset(bubble.position.dx, minY + painted);
        bubble.velocity = Offset(bubble.velocity.dx, -bubble.velocity.dy * restitution);
      }
      // Bottom boundary
      else if (bubble.position.dy + painted > maxY) {
        bubble.position = Offset(bubble.position.dx, maxY - painted);
        bubble.velocity = Offset(bubble.velocity.dx, -bubble.velocity.dy * restitution);
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
        final double minDist =
            b1.radius + b2.radius + minBubbleSeparation;

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
          }
        }
      }
    }

    // 3. Cap each sphere to its own cell, intersected with the band. Applied
    // after the collision pass so a resolution is never undone by the cap; a
    // sphere laid out on the band edge can still drift inward, but its painted
    // aura never leaves the band.
    for (final bubble in bubbles) {
      if (bubble.isBeingDragged || bubble.homeRange == Offset.zero) continue;
      final double painted = paintedRadius(bubble.radius);
      bubble.position = Offset(
        _clamp(
          bubble.position.dx,
          math.max(
            bubble.homePosition.dx - bubble.homeRange.dx,
            minX + painted,
          ),
          math.min(
            bubble.homePosition.dx + bubble.homeRange.dx,
            maxX - painted,
          ),
        ),
        _clamp(
          bubble.position.dy,
          math.max(
            bubble.homePosition.dy - bubble.homeRange.dy,
            minY + painted,
          ),
          math.min(
            bubble.homePosition.dy + bubble.homeRange.dy,
            maxY - painted,
          ),
        ),
      );
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
}
