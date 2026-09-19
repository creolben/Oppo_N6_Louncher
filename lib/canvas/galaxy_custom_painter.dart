import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../models/app_entry.dart';
import '../models/constellation.dart';
import '../core/foldable_controller.dart';
import 'camera_controller.dart';

class CosmicParticle {
  double x;
  double y;
  double z;
  double radius;
  double baseBrightness;
  double twinkleSpeed;
  Color color;
  bool hasSpikes;

  CosmicParticle({
    required this.x,
    required this.y,
    required this.z,
    required this.radius,
    required this.baseBrightness,
    required this.twinkleSpeed,
    required this.color,
    this.hasSpikes = false,
  });
}

class ShootingStar {
  Offset start;
  Offset end;
  double progress; // 0.0 to 1.0
  double speed;
  double length;
  double thickness;
  Color color;

  ShootingStar({
    required this.start,
    required this.end,
    required this.speed,
    required this.length,
    required this.thickness,
    required this.color,
    this.progress = 0.0,
  });
}

class SupernovaAnimation {
  final Offset worldPosition;
  final Color color;
  final double startTime;
  final double duration;

  SupernovaAnimation({
    required this.worldPosition,
    required this.color,
    required this.startTime,
    this.duration = 0.65,
  });

  double getProgress(double currentTime) {
    return ((currentTime - startTime) / duration).clamp(0.0, 1.0);
  }
}

class GalaxyCustomPainter extends CustomPainter {
  final CameraController camera;
  final List<Constellation> constellations;
  final FoldableController foldable;
  final double animationTime;
  final List<CosmicParticle> starfield;
  final List<ShootingStar> shootingStars;
  final SupernovaAnimation? activeSupernova;
  final Offset? activeTouchScreenPoint;
  final AppEntry? focusedApp;

  // Statically allocated Paint objects
  static final Paint _bgPaint = Paint();
  static final Paint _nebulaPaint = Paint();
  static final Paint _gridPaint = Paint()..style = PaintingStyle.stroke;
  static final Paint _starPaint = Paint()..style = PaintingStyle.fill;
  static final Paint _spikePaint = Paint()..strokeWidth = 0.8;
  static final Paint _meteorPaint = Paint()..strokeCap = StrokeCap.round;
  static final Paint _auraPaint = Paint();
  static final Paint _coreRingPaint = Paint()..style = PaintingStyle.stroke;
  static final Paint _trackPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.0;
  static final Paint _tickPaint = Paint()..strokeWidth = 1.0;
  static final Paint _filamentPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round;
  static final Paint _haloPaint = Paint();
  static final Paint _nodeFillPaint = Paint()..style = PaintingStyle.fill;
  static final Paint _nodeStrokePaint = Paint()..style = PaintingStyle.stroke;
  static final Paint _badgePaint = Paint()..style = PaintingStyle.fill;
  static final Paint _badgeGlowPaint = Paint()..style = PaintingStyle.fill;
  static final Paint _iconPaint = Paint()..filterQuality = FilterQuality.medium;
  static final Paint _shockwavePaint = Paint()..style = PaintingStyle.stroke;
  static final Paint _burstPaint = Paint();
  static final Paint _streakPaint = Paint();
  static final Paint _seamPaint = Paint();
  static final Paint _linePaint = Paint()..strokeWidth = 1.2;

  static final Path _path = Path();
  static final Path _starPath = Path();

  GalaxyCustomPainter({
    required Listenable repaint,
    required this.camera,
    required this.constellations,
    required this.foldable,
    required this.animationTime,
    required this.starfield,
    this.shootingStars = const [],
    this.activeSupernova,
    this.activeTouchScreenPoint,
    this.focusedApp,
  }) : super(repaint: repaint);

  @override
  void paint(Canvas canvas, Size size) {
    _paintDeepSpace(canvas, size);

    canvas.save();
    canvas.translate(camera.translation.dx, camera.translation.dy);
    canvas.scale(camera.zoom, camera.zoom);

    _paintWorldStarfield(canvas);
    _paintConstellationAuras(canvas);
    _paintBezierFilaments(canvas);
    _paintAppNodes(canvas);

    if (activeSupernova != null) {
      _paintSupernova(canvas);
    }

    canvas.restore();

    _paintScreenSpaceElements(canvas, size);
  }

  void _paintDeepSpace(Canvas canvas, Size size) {
    final bgRect = Offset.zero & size;

    // 1. Deep OLED Obsidian Abyss
    _bgPaint.shader = ui.Gradient.radial(
      Offset(size.width * 0.5, size.height * 0.5),
      size.longestSide * 0.90,
      const [
        Color(0xFF090D1A), // Deep interstellar navy
        Color(0xFF04060C), // Deep void abyss
        Color(0xFF010204), // Pure OLED pitch black
      ],
      const [0.0, 0.55, 1.0],
    );
    canvas.drawRect(bgRect, _bgPaint);

    // 2. Volumetric Interstellar Nebulae (Organic living cosmic dust clouds)
    final double driftX1 = math.sin(animationTime * 0.12) * 25.0;
    final double driftY1 = math.cos(animationTime * 0.10) * 20.0;
    final double driftX2 = math.cos(animationTime * 0.09) * 30.0;
    final double driftY2 = math.sin(animationTime * 0.11) * 25.0;

    // Nebula Cloud 1: Deep Cosmic Indigo/Violet (Upper-left sector)
    _nebulaPaint.shader = ui.Gradient.radial(
      Offset(size.width * 0.30 + driftX1, size.height * 0.35 + driftY1),
      size.longestSide * 0.58,
      const [
        Color(0x2A3E1E74), // Ethereal violet luminosity
        Color(0x121B0E3C),
        Colors.transparent,
      ],
      const [0.0, 0.45, 1.0],
    );
    canvas.drawRect(bgRect, _nebulaPaint);

    // Nebula Cloud 2: Cygnus Cyan / Stellar Gas (Lower-right sector)
    _nebulaPaint.shader = ui.Gradient.radial(
      Offset(size.width * 0.70 + driftX2, size.height * 0.65 + driftY2),
      size.longestSide * 0.52,
      const [
        Color(0x22007799), // Deep cyan-teal glow
        Color(0x0C042533),
        Colors.transparent,
      ],
      const [0.0, 0.42, 1.0],
    );
    canvas.drawRect(bgRect, _nebulaPaint);

    // Nebula Cloud 3: Warm Solar Amber Corona (Anchoring the center galaxy origin)
    final double corePulse = 0.05 + 0.02 * math.sin(animationTime * 1.5);
    _nebulaPaint.shader = ui.Gradient.radial(
      Offset(size.width * 0.5, size.height * 0.5),
      size.longestSide * 0.36,
      [
        Color(0xFFFFB300).withValues(alpha: corePulse * 1.6),
        Color(0xFFFF6F00).withValues(alpha: corePulse * 0.7),
        Colors.transparent,
      ],
      const [0.0, 0.48, 1.0],
    );
    canvas.drawRect(bgRect, _nebulaPaint);
  }

  void _paintWorldStarfield(Canvas canvas) {
    _paintAstrogationGrid(canvas);

    final visible = camera.visibleWorldBounds.inflate(120.0);

    for (final star in starfield) {
      if (star.x < visible.left ||
          star.x > visible.right ||
          star.y < visible.top ||
          star.y > visible.bottom) {
        continue;
      }

      final double wave = math.sin(animationTime * star.twinkleSpeed + star.x * 0.05);
      final double alpha = star.baseBrightness * (0.70 + wave * 0.25);

      final pos = Offset(star.x, star.y);
      _starPaint.color = star.color.withValues(alpha: alpha.clamp(0.18, 0.98));
      canvas.drawCircle(pos, star.radius, _starPaint);

      // 4-point diffraction cross spikes for bright beacon stars
      if (star.hasSpikes && alpha > 0.60) {
        final double spikeLen = star.radius * 4.2 * (0.85 + wave * 0.25);
        _spikePaint.color = star.color.withValues(alpha: (alpha * 0.45).clamp(0.0, 0.70));
        canvas.drawLine(pos - Offset(spikeLen, 0), pos + Offset(spikeLen, 0), _spikePaint);
        canvas.drawLine(pos - Offset(0, spikeLen), pos + Offset(0, spikeLen), _spikePaint);
      }
    }

    _paintShootingStars(canvas);
  }

  void _paintAstrogationGrid(Canvas canvas) {
    final double zoomAlpha = (camera.zoom * 0.8).clamp(0.35, 1.0);
    _gridPaint.color = const Color(0xFF64B5F6).withValues(alpha: 0.035 * zoomAlpha);
    _gridPaint.strokeWidth = 0.75;

    // Faint concentric celestial coordinate rings
    canvas.drawCircle(Offset.zero, 180.0, _gridPaint);
    canvas.drawCircle(Offset.zero, 340.0, _gridPaint);
    canvas.drawCircle(Offset.zero, 520.0, _gridPaint);

    // Subtle radial observatory degree ticks
    _gridPaint.color = const Color(0xFF00E5FF).withValues(alpha: 0.04 * zoomAlpha);
    for (int i = 0; i < 12; i++) {
      final double a = i * math.pi / 6;
      final cosA = math.cos(a);
      final sinA = math.sin(a);
      canvas.drawLine(
        Offset(cosA * 165.0, sinA * 165.0),
        Offset(cosA * 540.0, sinA * 540.0),
        _gridPaint,
      );
    }
  }

  void _paintShootingStars(Canvas canvas) {
    for (final meteor in shootingStars) {
      final double p = meteor.progress.clamp(0.0, 1.0);
      final head = Offset.lerp(meteor.start, meteor.end, p)!;
      final dir = meteor.end - meteor.start;
      final dist = dir.distance;
      if (dist <= 0) continue;
      final norm = dir / dist;

      final double tailLen = meteor.length * (p < 0.2 ? (p / 0.2) : (p > 0.8 ? (1.0 - p) / 0.2 : 1.0));
      final tail = head - (norm * tailLen);
      final double fade = math.sin(p * math.pi); // Smooth attack and release

      _meteorPaint.shader = ui.Gradient.linear(
        head,
        tail,
        [
          Colors.white.withValues(alpha: 0.95 * fade),
          meteor.color.withValues(alpha: 0.65 * fade),
          Colors.transparent,
        ],
        const [0.0, 0.35, 1.0],
      );
      _meteorPaint.strokeWidth = meteor.thickness;
      canvas.drawLine(head, tail, _meteorPaint);
      _meteorPaint.shader = null;

      // Bright incandescent meteor core point
      _starPaint.color = Colors.white.withValues(alpha: fade);
      canvas.drawCircle(head, meteor.thickness * 1.3, _starPaint);
    }
  }

  void _paintConstellationAuras(Canvas canvas) {
    // Find the highest expansion progress among outer constellations
    final double maxOuterProgress = constellations
        .where((c) => c.id != 'core')
        .map((c) => c.expansionProgress)
        .fold(0.0, math.max);

    // Fade factor for other hubs/core (completely disappears as a constellation blooms)
    final double othersFade = (1.0 - maxOuterProgress * 1.5).clamp(0.0, 1.0);

    for (final c in constellations) {
      c.ensurePainters();
      final double progress = c.expansionProgress;
      final bool isCore = c.id == 'core';

      // If core, render dedicated artistic celestial astrolabe centerpiece
      if (isCore) {
        if (othersFade > 0.01) {
          _paintCenterConstellationCore(canvas, c, othersFade);
        }
        continue;
      }

      // Soft ambient nebula aura for outer constellations
      final double auraRadius = progress > 0.5 ? c.radius * 1.4 : 70.0;
      final double auraAlphaScale = c.isExpanded ? 1.0 : othersFade;
      if (auraAlphaScale > 0.01) {
        _auraPaint.shader = ui.Gradient.radial(
          c.center,
          auraRadius,
          [
            c.glowColor.withValues(alpha: (progress > 0.3 ? 0.22 : 0.35) * auraAlphaScale),
            c.glowColor.withValues(alpha: 0.06 * auraAlphaScale),
            Colors.transparent,
          ],
          const [0.0, 0.55, 1.0],
        );
        canvas.drawCircle(c.center, auraRadius, _auraPaint);
      }

      // Collapsed: Modern Frosted Pod Orb (fades away completely if another constellation is open)
      if (!isCore && progress < 0.85) {
        final double orbAlpha = (1.0 - progress).clamp(0.0, 1.0) * othersFade;
        if (orbAlpha > 0.01) {
          final double postureScale = foldable.isFolded ? 0.76 : 1.0;
          double podSize = 70.0 * postureScale;

          // Mac Dock Style Fish-Eye Magnification on finger glide
          if (activeTouchScreenPoint != null) {
            final touchWorld = camera.screenToWorld(activeTouchScreenPoint!);
            final dist = (c.center - touchWorld).distance;
            if (dist < 130.0) {
              final dockMag = 1.0 + 0.35 * math.exp(-((dist * dist) / (2 * 55.0 * 55.0)));
              podSize *= dockMag;
            }
          }

          final podRect = Rect.fromCenter(center: c.center, width: podSize, height: podSize);
          final podRRect = RRect.fromRectAndRadius(podRect, Radius.circular(podSize * 0.34));

          // Soft drop shadow
          _haloPaint.color = c.glowColor.withValues(alpha: 0.25 * orbAlpha);
          canvas.drawRRect(podRRect.inflate(5.0), _haloPaint);

          // Frosted Glass Pod Body
          _nodeFillPaint.color = const Color(0xFF0F1424).withValues(alpha: 0.94 * orbAlpha);
          canvas.drawRRect(podRRect, _nodeFillPaint);

          // Illuminated Rim Border
          _nodeStrokePaint
            ..shader = ui.Gradient.linear(
              podRect.topLeft,
              podRect.bottomRight,
              [
                c.primaryColor.withValues(alpha: 0.85 * orbAlpha),
                c.secondaryColor.withValues(alpha: 0.25 * orbAlpha),
              ],
            )
            ..strokeWidth = 1.4;
          canvas.drawRRect(podRRect, _nodeStrokePaint);

          // Center Emblem Icon
          if (c.iconPainter != null) {
            final ip = c.iconPainter!;
            ip.paint(canvas, c.center - Offset(ip.width / 2, ip.height / 2));
          }
        }
      }

      // Expanded center header badge for the active opened constellation
      if (!isCore && progress > 0.40) {
        final double centerAlpha = ((progress - 0.40) / 0.60).clamp(0.0, 1.0);
        if (centerAlpha > 0.05) {
          // Center Emblem Icon
          if (c.iconPainter != null) {
            final ip = c.iconPainter!;
            ip.paint(canvas, c.center - Offset(ip.width / 2, ip.height / 2 + 10.0));
          }
          // Constellation Title
          if (c.titlePainter != null) {
            final tp = c.titlePainter!;
            tp.paint(canvas, c.center - Offset(tp.width / 2, -18.0));
          }
          // Star count badge
          if (c.countBadgePainter != null) {
            final bp = c.countBadgePainter!;
            bp.paint(canvas, c.center - Offset(bp.width / 2, -34.0));
          }
        }
      }

      // Subtle Orbital Compass Rings for outer constellations
      if (progress > 0.15) {
        final double trackAlpha = progress * 0.45;
        if (trackAlpha > 0.01) {
          _trackPaint.color = c.primaryColor.withValues(alpha: 0.05 * trackAlpha);
          canvas.drawCircle(c.center, c.radius * 0.75, _trackPaint);
          canvas.drawCircle(c.center, c.radius * 1.0, _trackPaint);

          final double rot = c.rotation;
          _tickPaint.color = c.primaryColor.withValues(alpha: 0.08 * trackAlpha);
          for (int i = 0; i < 8; i++) {
            final double a = rot + (i * math.pi / 4);
            final cosA = math.cos(a);
            final sinA = math.sin(a);
            final p1 = c.center + Offset(cosA * (c.radius - 2.0), sinA * (c.radius - 2.0));
            final p2 = c.center + Offset(cosA * (c.radius + 2.0), sinA * (c.radius + 2.0));
            canvas.drawLine(p1, p2, _tickPaint);
          }
        }
      }
    }
  }

  void _paintCenterConstellationCore(Canvas canvas, Constellation core, double othersFade) {
    final double progress = core.expansionProgress.clamp(0.0, 1.0);
    final double alpha = othersFade;
    if (alpha < 0.01) return;

    final center = core.center;
    final double breath = math.sin(animationTime * 2.2);

    // 1. Radiant Solar Nebula Corona
    final double coronaRadius = (38.0 + progress * 24.0) + breath * 3.0;
    _auraPaint.shader = ui.Gradient.radial(
      center,
      coronaRadius * 1.6,
      [
        core.primaryColor.withValues(alpha: (0.35 + 0.08 * breath) * alpha),
        core.secondaryColor.withValues(alpha: (0.12 + 0.04 * breath) * alpha),
        Colors.transparent,
      ],
      const [0.0, 0.50, 1.0],
    );
    canvas.drawCircle(center, coronaRadius * 1.6, _auraPaint);

    // 2. Concentric Astrolabe Gyroscope Rings (Counter-Rotating Celestial Chrono Rings)
    // Ring 1: Inner Gyro Ring with cardinal tick marks (rotates clockwise)
    final double innerRot = animationTime * 0.35;
    const double innerR = 33.0;
    _coreRingPaint
      ..color = core.primaryColor.withValues(alpha: (0.50 + 0.15 * progress) * alpha)
      ..strokeWidth = 1.0;
    canvas.drawCircle(center, innerR, _coreRingPaint);

    // Inner ring tick marks
    _tickPaint.color = core.primaryColor.withValues(alpha: (0.40 + 0.15 * progress) * alpha);
    _tickPaint.strokeWidth = 1.0;
    for (int i = 0; i < 8; i++) {
      final double a = innerRot + (i * math.pi / 4);
      final cosA = math.cos(a);
      final sinA = math.sin(a);
      final p1 = center + Offset(cosA * (innerR - 3.5), sinA * (innerR - 3.5));
      final p2 = center + Offset(cosA * (innerR + 3.5), sinA * (innerR + 3.5));
      canvas.drawLine(p1, p2, _tickPaint);
    }

    // Orbiting Golden Micro-Photons on Inner Ring
    for (int i = 0; i < 2; i++) {
      final a = innerRot + (i * math.pi);
      final photonPos = center + Offset(math.cos(a) * innerR, math.sin(a) * innerR);
      _starPaint.color = Colors.white.withValues(alpha: 0.95 * alpha);
      canvas.drawCircle(photonPos, 1.8, _starPaint);
      _haloPaint.color = core.primaryColor.withValues(alpha: 0.60 * alpha);
      canvas.drawCircle(photonPos, 4.0, _haloPaint);
    }

    // Ring 2: Outer Calibrated Astrolabe Ring (rotates counter-clockwise, expands dynamically with progress)
    final double outerR = 44.0 + progress * 14.0;
    final double outerRot = -animationTime * 0.22;
    _coreRingPaint
      ..color = core.primaryColor.withValues(alpha: (0.35 + 0.20 * progress) * alpha)
      ..strokeWidth = 1.2;
    canvas.drawCircle(center, outerR, _coreRingPaint);

    // Outer ring diamond nodes at 4 cardinal points
    for (int i = 0; i < 4; i++) {
      final a = outerRot + (i * math.pi / 2);
      final nodePos = center + Offset(math.cos(a) * outerR, math.sin(a) * outerR);
      _drawDiamond(canvas, nodePos, 3.2, core.primaryColor.withValues(alpha: 0.85 * alpha));
    }

    // 3. Collapsed State Visuals: Radiant Singularity Orb & Breathing Beacon Ripple
    if (progress < 0.80) {
      final double closedAlpha = ((1.0 - progress) / 1.0).clamp(0.0, 1.0) * alpha;

      // Sonar / Beacon Ripple Wave expanding from center
      final double rippleT = (animationTime * 0.55) % 1.0;
      final double rippleRadius = 24.0 + rippleT * 42.0;
      final double rippleAlpha = (1.0 - rippleT) * 0.45 * closedAlpha;
      if (rippleAlpha > 0.01) {
        _coreRingPaint
          ..color = core.primaryColor.withValues(alpha: rippleAlpha)
          ..strokeWidth = 1.2;
        canvas.drawCircle(center, rippleRadius, _coreRingPaint);
      }

      // Elegant Singularity Label underneath: "ESSENTIALS"
      if (closedAlpha > 0.1) {
        if (core.titlePainter != null) {
          final tp = core.titlePainter!;
          canvas.saveLayer(
            Rect.fromLTWH(center.dx - tp.width / 2, center.dy + 34.0, tp.width, tp.height),
            Paint()..color = Colors.white.withValues(alpha: closedAlpha * 0.90),
          );
          tp.paint(canvas, center + Offset(-tp.width / 2, 34.0));
          canvas.restore();
        }
      }
    }

    // 4. Center Singularity Core Disc (Glassmorphic Obsidian-Gold Jewel)
    double coreScale = 1.0;
    if (activeTouchScreenPoint != null) {
      final touchWorld = camera.screenToWorld(activeTouchScreenPoint!);
      final dist = (center - touchWorld).distance;
      if (dist < 100.0) {
        coreScale = 1.0 + 0.28 * math.exp(-((dist * dist) / (2 * 45.0 * 45.0)));
      }
    }

    final double discRadius = (22.0 + progress * 3.0) * coreScale;
    final discRect = Rect.fromCircle(center: center, radius: discRadius);

    // Deep drop glow
    _haloPaint.color = core.glowColor.withValues(alpha: (0.45 + 0.15 * breath) * alpha);
    canvas.drawCircle(center, discRadius * 1.25, _haloPaint);

    // Obsidian Dark Glass Body
    _nodeFillPaint.color = const Color(0xFF0D1222).withValues(alpha: 0.95 * alpha);
    canvas.drawCircle(center, discRadius, _nodeFillPaint);

    // Inner Satin Gradient
    _auraPaint.shader = ui.Gradient.radial(
      center - Offset(discRadius * 0.25, discRadius * 0.25),
      discRadius * 0.9,
      [
        core.primaryColor.withValues(alpha: (0.28 + 0.08 * breath) * alpha),
        Colors.transparent,
      ],
      const [0.0, 1.0],
    );
    canvas.drawCircle(center, discRadius, _auraPaint);

    // Polished Radiant Gold Rim
    _nodeStrokePaint
      ..shader = ui.Gradient.linear(
        discRect.topLeft,
        discRect.bottomRight,
        [
          const Color(0xFFFFFFFF).withValues(alpha: 0.90 * alpha),
          core.primaryColor.withValues(alpha: 0.95 * alpha),
          core.secondaryColor.withValues(alpha: 0.40 * alpha),
        ],
        const [0.0, 0.45, 1.0],
      )
      ..strokeWidth = 1.5 * coreScale;
    canvas.drawCircle(center, discRadius, _nodeStrokePaint);

    // 5. Central Artistic Motif: Radiant Celestial 8-Point Compass Star
    _drawCelestialCompassStar(
      canvas,
      center,
      radius: (10.0 + progress * 2.0) * coreScale,
      color: Colors.white.withValues(alpha: (0.95 + 0.05 * breath) * alpha),
      accentColor: core.primaryColor.withValues(alpha: 0.85 * alpha),
      rotation: animationTime * 0.15,
    );
  }

  void _drawDiamond(Canvas canvas, Offset pos, double size, Color color) {
    _starPath.reset();
    _starPath.moveTo(pos.dx, pos.dy - size);
    _starPath.lineTo(pos.dx + size * 0.65, pos.dy);
    _starPath.lineTo(pos.dx, pos.dy + size);
    _starPath.lineTo(pos.dx - size * 0.65, pos.dy);
    _starPath.close();
    _nodeFillPaint.color = color;
    canvas.drawPath(_starPath, _nodeFillPaint);
  }

  void _drawCelestialCompassStar(
    Canvas canvas,
    Offset center, {
    required double radius,
    required Color color,
    required Color accentColor,
    required double rotation,
  }) {
    _starPath.reset();
    const int points = 8;
    for (int i = 0; i < points * 2; i++) {
      final double angle = rotation + (i * math.pi / points);
      final bool isMajor = (i % 4 == 0);
      final bool isMinor = (i % 2 == 0);
      final double r = isMajor ? radius : (isMinor ? radius * 0.55 : radius * 0.28);
      final double x = center.dx + math.cos(angle) * r;
      final double y = center.dy + math.sin(angle) * r;
      if (i == 0) {
        _starPath.moveTo(x, y);
      } else {
        _starPath.lineTo(x, y);
      }
    }
    _starPath.close();

    _nodeFillPaint.color = accentColor;
    canvas.drawPath(_starPath, _nodeFillPaint);

    // Inner diamond core point
    _drawDiamond(canvas, center, radius * 0.38, color);
  }

  void _paintBezierFilaments(Canvas canvas) {
    final Constellation core = constellations.firstWhere((c) => c.id == 'core');

    // Find the highest expansion progress among outer constellations
    final double maxOuterProgress = constellations
        .where((c) => c.id != 'core')
        .map((c) => c.expansionProgress)
        .fold(0.0, math.max);

    // Fade factor for background connections when a constellation is opening
    final double othersFade = (1.0 - maxOuterProgress * 1.5).clamp(0.0, 1.0);

    // 1. Filaments connecting sectors to Essentials Core (fade out when a constellation opens)
    if (othersFade > 0.01) {
      for (final c in constellations) {
        if (c.id == 'core') continue;

        _path.reset();
        _path.moveTo(core.center.dx, core.center.dy);

        final mid = (core.center + c.center) / 2;
        final double wave = math.sin(animationTime * 1.0 + c.center.dx * 0.01) * 12.0;
        final normal = Offset(-(c.center.dy - core.center.dy), c.center.dx - core.center.dx);
        final normalNormalized = normal.distance > 0 ? normal / normal.distance : Offset.zero;
        final controlPoint = mid + (normalNormalized * wave);

        _path.quadraticBezierTo(controlPoint.dx, controlPoint.dy, c.center.dx, c.center.dy);

        final double filamentAlpha = (c.isExpanded ? 0.6 : (c.isCustom ? 0.40 : 0.25)) * othersFade;
        _filamentPaint
          ..shader = null
          ..color = c.primaryColor.withValues(alpha: 0.06 * filamentAlpha)
          ..strokeWidth = c.isCustom ? 3.0 : 2.5;
        canvas.drawPath(_path, _filamentPaint);

        _filamentPaint
          ..color = c.primaryColor.withValues(alpha: 0.28 * filamentAlpha)
          ..strokeWidth = c.isCustom ? 1.4 : 1.0;
        canvas.drawPath(_path, _filamentPaint);
      }
    }

    // 2. Inter-constellation filaments connecting outer constellations to each other (fade out when a constellation opens)
    if (othersFade > 0.01) {
      final List<Constellation> outer = constellations.where((c) => c.id != 'core').toList();
      if (outer.length >= 2) {
        // Sort in circular polar angle order around the core center to connect adjacent neighbors seamlessly
        outer.sort((a, b) {
          final angleA = math.atan2(a.center.dy - core.center.dy, a.center.dx - core.center.dx);
          final angleB = math.atan2(b.center.dy - core.center.dy, b.center.dx - core.center.dx);
          return angleA.compareTo(angleB);
        });

        final int count = outer.length;
        for (int i = 0; i < count; i++) {
          final c1 = outer[i];
          final c2 = outer[(i + 1) % count];

          _path.reset();
          _path.moveTo(c1.center.dx, c1.center.dy);

          final mid = (c1.center + c2.center) / 2;
          // Subtle bow outward away from the center core
          final midDir = mid.distance > 0 ? mid / mid.distance : const Offset(0, 1);
          final double wave = math.sin(animationTime * 0.9 + i * 1.5) * 8.0;
          final controlPoint = mid + (midDir * (20.0 + wave));

          _path.quadraticBezierTo(controlPoint.dx, controlPoint.dy, c2.center.dx, c2.center.dy);

          // Highlight if either constellation is custom (newly created) or expanded
          final bool involvesCustom = c1.isCustom || c2.isCustom;
          final bool involvesExpanded = c1.isExpanded || c2.isExpanded;
          final double baseAlpha = (involvesCustom
              ? 0.42
              : (involvesExpanded ? 0.35 : 0.22)) * othersFade;

          // Dual-color gradient blending the two connected constellations
          final bridgeShader = ui.Gradient.linear(
            c1.center,
            c2.center,
            [
              c1.primaryColor.withValues(alpha: 0.12 * baseAlpha),
              c2.primaryColor.withValues(alpha: 0.12 * baseAlpha),
            ],
          );

          _filamentPaint
            ..shader = bridgeShader
            ..strokeWidth = involvesCustom ? 2.6 : 1.8;
          canvas.drawPath(_path, _filamentPaint);

          final coreShader = ui.Gradient.linear(
            c1.center,
            c2.center,
            [
              c1.primaryColor.withValues(alpha: 0.50 * baseAlpha),
              c2.primaryColor.withValues(alpha: 0.50 * baseAlpha),
            ],
          );

          _filamentPaint
            ..shader = coreShader
            ..strokeWidth = involvesCustom ? 1.3 : 0.9;
          canvas.drawPath(_path, _filamentPaint);
          _filamentPaint.shader = null;

          // Flowing stardust pulse node travelling along the connection between constellations
          final double pulseT = ((animationTime * 0.32) + (i * 0.25)) % 1.0;
          final double invT = 1.0 - pulseT;
          final pulsePos = (c1.center * (invT * invT)) +
              (controlPoint * (2.0 * invT * pulseT)) +
              (c2.center * (pulseT * pulseT));

          final Color pulseColor = Color.lerp(c1.primaryColor, c2.primaryColor, pulseT) ?? c1.primaryColor;
          _haloPaint.color = pulseColor.withValues(alpha: (involvesCustom ? 0.65 : 0.40) * othersFade);
          canvas.drawCircle(pulsePos, involvesCustom ? 3.8 : 2.5, _haloPaint);
          _nodeFillPaint.color = Colors.white.withValues(alpha: (involvesCustom ? 0.95 : 0.75) * othersFade);
          canvas.drawCircle(pulsePos, involvesCustom ? 1.8 : 1.2, _nodeFillPaint);
        }
      }
    }

    // 3. Intra-constellation filaments (only for active constellation)
    for (final c in constellations) {
      final double progress = c.id == 'core'
          ? (othersFade * c.expansionProgress)
          : c.expansionProgress;
      if (progress < 0.1) continue;

      for (final app in c.apps) {
        _path.reset();
        _path.moveTo(c.center.dx, c.center.dy);

        final mid = (c.center + app.worldPosition) / 2;
        final normal = Offset(-(app.worldPosition.dy - c.center.dy), app.worldPosition.dx - c.center.dx);
        final normalNormalized = normal.distance > 0 ? normal / normal.distance : Offset.zero;
        final double wave = math.sin(animationTime * 1.5 + app.orbitalAngle) * 3.5;
        final controlPoint = mid + (normalNormalized * wave);

        _path.quadraticBezierTo(controlPoint.dx, controlPoint.dy, app.worldPosition.dx, app.worldPosition.dy);

        if (c.id == 'core') {
          // Luminous golden energy flux filaments connecting core to essentials apps
          _filamentPaint
            ..shader = null
            ..color = c.primaryColor.withValues(alpha: 0.28 * progress)
            ..strokeWidth = 1.3;
          canvas.drawPath(_path, _filamentPaint);

          // Flowing stardust pulse toward app
          final double pulseT = ((animationTime * 0.42) + (app.orbitalAngle / (2 * math.pi))) % 1.0;
          final double invT = 1.0 - pulseT;
          final pulsePos = (c.center * (invT * invT)) +
              (controlPoint * (2.0 * invT * pulseT)) +
              (app.worldPosition * (pulseT * pulseT));
          _starPaint.color = Colors.white.withValues(alpha: 0.90 * progress);
          canvas.drawCircle(pulsePos, 1.4, _starPaint);
          _haloPaint.color = c.primaryColor.withValues(alpha: 0.50 * progress);
          canvas.drawCircle(pulsePos, 3.0, _haloPaint);
        } else {
          _filamentPaint
            ..shader = null
            ..color = app.accentColor.withValues(alpha: 0.16 * progress)
            ..strokeWidth = 1.0;
          canvas.drawPath(_path, _filamentPaint);
        }
      }
    }
  }

  void _paintAppNodes(Canvas canvas) {
    final double zoom = camera.zoom;
    final visible = camera.visibleWorldBounds.inflate(60.0);

    // Find highest expansion progress among outer constellations
    final double maxOuterProgress = constellations
        .where((c) => c.id != 'core')
        .map((c) => c.expansionProgress)
        .fold(0.0, math.max);

    // Fade factor for center core apps: completely disappears (alpha = 0.0) as soon as an outer constellation opens
    final double coreAlpha = (1.0 - maxOuterProgress * 1.5).clamp(0.0, 1.0);

    for (final c in constellations) {
      final bool isCore = c.id == 'core';

      // Effective alpha for this constellation's apps:
      // - Core apps fade cleanly to 0.0 when outer constellation opened, AND scale with core.expansionProgress
      // - Outer constellation apps only show based on their own expansionProgress
      final double effectiveAlpha = isCore
          ? (coreAlpha * c.expansionProgress)
          : c.expansionProgress;

      // Strictly skip if alpha is essentially zero:
      // Completely prevents any other icons from showing underneath!
      if (effectiveAlpha < 0.01) continue;

      for (final app in c.apps) {
        final pos = app.worldPosition;

        if (pos.dx < visible.left ||
            pos.dx > visible.right ||
            pos.dy < visible.top ||
            pos.dy > visible.bottom) {
          continue;
        }

        final isFocused = focusedApp == app;
        final double postureScale = foldable.isFolded ? 0.76 : 1.0;
        // Center Essentials apps are primary daily drivers: render them larger (58px) for high usability
        final double baseSize = (isCore ? 58.0 : 50.0) * postureScale;
        double nodeSize = (isFocused ? baseSize * 1.16 : baseSize) * (0.45 + effectiveAlpha * 0.55);

        // Mac Dock Fish-Eye Magnification on finger glide across galaxy
        double dockMagnification = 1.0;
        if (activeTouchScreenPoint != null) {
          final touchWorld = camera.screenToWorld(activeTouchScreenPoint!);
          final dist = (pos - touchWorld).distance;
          if (dist < 130.0) {
            // Gaussian bell curve: peak magnification +42% under touch, tapering off smoothly within 130px
            dockMagnification = 1.0 + 0.42 * math.exp(-((dist * dist) / (2 * 52.0 * 52.0)));
            nodeSize *= dockMagnification;
          }
        }

        final double halfSize = nodeSize / 2;

        app.ensurePainters(halfSize);

        final nodeRect = Rect.fromCenter(center: pos, width: nodeSize, height: nodeSize);
        final nodeRRect = RRect.fromRectAndRadius(nodeRect, Radius.circular(nodeSize * 0.30));

        // Outer glow halo - dynamically amplified when dock zoomed
        final double haloAlphaBoost = (dockMagnification - 1.0) * 0.8;
        _haloPaint.shader = ui.Gradient.radial(
          pos,
          nodeSize * 1.15,
          [
            app.accentColor.withValues(alpha: ((isFocused ? 0.50 : 0.18) + haloAlphaBoost).clamp(0.0, 0.75) * effectiveAlpha),
            app.accentColor.withValues(alpha: 0.04 * effectiveAlpha),
            Colors.transparent,
          ],
          const [0.0, 0.60, 1.0],
        );
        canvas.drawCircle(pos, nodeSize * 1.15, _haloPaint);

        // Modern Glassmorphic Squircle Body
        _nodeFillPaint.color = const Color(0xFF13182A).withValues(alpha: 0.94 * effectiveAlpha);
        canvas.drawRRect(nodeRRect, _nodeFillPaint);

        // Satin illuminated rim border
        _nodeStrokePaint
          ..shader = ui.Gradient.linear(
            nodeRect.topLeft,
            nodeRect.bottomRight,
            [
              app.accentColor.withValues(alpha: ((isFocused ? 1.0 : 0.75) + haloAlphaBoost).clamp(0.0, 1.0) * effectiveAlpha),
              app.accentColor.withValues(alpha: 0.18 * effectiveAlpha),
            ],
          )
          ..strokeWidth = isFocused ? 2.0 : (1.2 * (dockMagnification > 1.1 ? 1.4 : 1.0));
        canvas.drawRRect(nodeRRect, _nodeStrokePaint);

        // App Icon
        if (app.decodedIcon != null) {
          final icon = app.decodedIcon!;
          final iconSize = nodeSize * 0.64;
          final srcRect = Rect.fromLTWH(0, 0, icon.width.toDouble(), icon.height.toDouble());
          final dstRect = Rect.fromCenter(center: pos, width: iconSize, height: iconSize);
          _iconPaint.color = Colors.white.withValues(alpha: effectiveAlpha);

          // Circular cosmic disc normalization for third-party & OEM icons
          canvas.save();
          final Path discClip = Path()
            ..addOval(Rect.fromCircle(center: pos, radius: iconSize / 2));
          canvas.clipPath(discClip);
          canvas.drawImageRect(icon, srcRect, dstRect, _iconPaint);
          canvas.restore();

          // Luminous celestial rim around icon disc
          final Paint iconRim = Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.0
            ..color = app.accentColor.withValues(alpha: 0.38 * effectiveAlpha);
          canvas.drawCircle(pos, iconSize / 2, iconRim);
        } else if (app.iconPainter != null) {
          final p = app.iconPainter!;
          p.paint(canvas, pos - Offset(p.width / 2, p.height / 2));
        }

        // Notification Pip Badge
        if (app.notificationCount > 0 && app.badgePainter != null && effectiveAlpha > 0.6) {
          final badgeCenter = pos + Offset(halfSize * 0.85, -halfSize * 0.85);
          const badgeR = 8.0;
          _badgePaint.color = const Color(0xFFFF3366).withValues(alpha: effectiveAlpha);
          canvas.drawCircle(badgeCenter, badgeR, _badgePaint);

          _badgeGlowPaint.color = const Color(0x55FF3366).withValues(alpha: effectiveAlpha);
          canvas.drawCircle(badgeCenter, badgeR * 1.3, _badgeGlowPaint);

          final bp = app.badgePainter!;
          bp.paint(canvas, badgeCenter - Offset(bp.width / 2, bp.height / 2));
        }

        // App Label Logic:
        // - In center galaxy: when outer star groupings are closed, show app labels with crystal-clear contrast
        // - When outer star groupings ARE displaying: strictly hide center galaxy labels so the expanded cluster is focused
        // - In outer constellations: show label when focused or zoomed in (zoom > 1.10)
        final bool showLabel = isCore
            ? (maxOuterProgress < 0.10 && c.expansionProgress > 0.65)
            : (isFocused || (zoom > 1.10 && effectiveAlpha > 0.70));

        if (showLabel && app.labelPainter != null) {
          final double labelAlpha = isCore
              ? (coreAlpha * c.expansionProgress * 0.95)
              : (isFocused ? 1.0 : ((zoom - 1.10) / 0.35).clamp(0.0, 1.0) * effectiveAlpha);

          if (labelAlpha > 0.05) {
            final lp = app.labelPainter!;
            canvas.saveLayer(
              Rect.fromLTWH(pos.dx - lp.width / 2, pos.dy + halfSize + 5.0, lp.width, lp.height),
              Paint()..color = Colors.white.withValues(alpha: labelAlpha),
            );
            lp.paint(canvas, Offset(pos.dx - lp.width / 2, pos.dy + halfSize + 5.0));
            canvas.restore();
          }
        }
      }
    }
  }

  void _paintSupernova(Canvas canvas) {
    final supernova = activeSupernova!;
    final p = supernova.getProgress(animationTime);
    if (p >= 1.0) return;

    final pos = supernova.worldPosition;
    final easeP = Curves.easeOutQuart.transform(p);

    _shockwavePaint
      ..color = supernova.color.withValues(alpha: (1.0 - p) * 0.8)
      ..strokeWidth = (1.0 - p) * 5.0 + 1.0;
    canvas.drawCircle(pos, easeP * 280.0, _shockwavePaint);

    _burstPaint.shader = ui.Gradient.radial(
      pos,
      easeP * 200.0,
      [
        Colors.white.withValues(alpha: 1.0 - p),
        supernova.color.withValues(alpha: (1.0 - p) * 0.6),
        Colors.transparent,
      ],
      const [0.0, 0.4, 1.0],
    );
    canvas.drawCircle(pos, easeP * 200.0, _burstPaint);

    _streakPaint
      ..color = Colors.white.withValues(alpha: (1.0 - p) * 0.75)
      ..strokeWidth = 1.6;
    for (int i = 0; i < 12; i++) {
      final a = (i * math.pi / 6) + (p * 0.5);
      final r1 = easeP * 30.0;
      final r2 = easeP * 220.0;
      final start = pos + Offset(math.cos(a) * r1, math.sin(a) * r1);
      final end = pos + Offset(math.cos(a) * r2, math.sin(a) * r2);
      canvas.drawLine(start, end, _streakPaint);
    }
  }

  void _paintScreenSpaceElements(Canvas canvas, Size size) {
    final crease = foldable.creaseBounds;
    if (crease != null || (foldable.isTabletop && foldable.isSimulated)) {
      final creaseRect = crease ?? Rect.fromLTWH(0, size.height * 0.5 - 2, size.width, 4);

      _seamPaint.shader = ui.Gradient.linear(
        creaseRect.topLeft,
        creaseRect.bottomLeft,
        const [
          Color(0x0000E5FF),
          Color(0x4400E5FF),
          Color(0x0000E5FF),
        ],
        const [0.0, 0.5, 1.0],
      );
      canvas.drawRect(
        Rect.fromLTRB(0, creaseRect.top - 10, size.width, creaseRect.bottom + 10),
        _seamPaint,
      );

      _linePaint.color = const Color(0x9900E5FF);
      canvas.drawLine(
        Offset(0, creaseRect.center.dy),
        Offset(size.width, creaseRect.center.dy),
        _linePaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant GalaxyCustomPainter oldDelegate) {
    return false;
  }
}
