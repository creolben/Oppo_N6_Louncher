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
  double z; // Parallax depth layer
  double radius;
  double baseBrightness;
  double twinkleSpeed;
  Color color;

  CosmicParticle({
    required this.x,
    required this.y,
    required this.z,
    required this.radius,
    required this.baseBrightness,
    required this.twinkleSpeed,
    required this.color,
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
    this.duration = 0.7,
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
  final SupernovaAnimation? activeSupernova;
  final Offset? activeTouchScreenPoint;
  final AppEntry? focusedApp;

  // Reusable Paint objects to completely eliminate GC churn & frame drops
  static final Paint _bgPaint = Paint();
  static final Paint _starPaint = Paint()..style = PaintingStyle.fill;
  static final Paint _auraPaint = Paint();
  static final Paint _trackPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.0;
  static final Paint _tickPaint = Paint()..strokeWidth = 1.2;
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

  // Reusable Path
  static final Path _path = Path();

  GalaxyCustomPainter({
    required Listenable repaint,
    required this.camera,
    required this.constellations,
    required this.foldable,
    required this.animationTime,
    required this.starfield,
    this.activeSupernova,
    this.activeTouchScreenPoint,
    this.focusedApp,
  }) : super(repaint: repaint);

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Deep cosmic gradient background
    _paintDeepSpace(canvas, size);

    // 2. Setup World Space Camera Transform
    canvas.save();
    canvas.translate(camera.translation.dx, camera.translation.dy);
    canvas.scale(camera.zoom, camera.zoom);

    // 3. Render Starfield in world space (flicker-free, perfectly stable)
    _paintWorldStarfield(canvas);

    // 4. Render Constellation Nebular Auras & Astronomical Rings
    _paintConstellationAuras(canvas);

    // 5. Render Luminous Bezier Filaments
    _paintBezierFilaments(canvas);

    // 6. Render App Celestial Nodes
    _paintAppNodes(canvas);

    // 7. Render Supernova Launch Animation (if triggered)
    if (activeSupernova != null) {
      _paintSupernova(canvas);
    }

    canvas.restore();

    // 8. Screen-Space Overlays (Hinge Crease Refraction)
    _paintScreenSpaceElements(canvas, size);
  }

  void _paintDeepSpace(Canvas canvas, Size size) {
    final bgRect = Offset.zero & size;
    _bgPaint.shader = ui.Gradient.radial(
      Offset(size.width * 0.5, size.height * 0.5),
      size.longestSide * 0.85,
      const [
        Color(0xFF0C1020),
        Color(0xFF05070E),
        Color(0xFF010205),
      ],
      const [0.0, 0.65, 1.0],
    );
    canvas.drawRect(bgRect, _bgPaint);
  }

  void _paintWorldStarfield(Canvas canvas) {
    // Visible world boundary plus margin for culling
    final visible = camera.visibleWorldBounds.inflate(120.0);

    for (final star in starfield) {
      // Fast bounding box culling
      if (star.x < visible.left ||
          star.x > visible.right ||
          star.y < visible.top ||
          star.y > visible.bottom) {
        continue;
      }

      // Smooth, gentle ambient twinkle (no abrupt strobing)
      final double wave = math.sin(animationTime * star.twinkleSpeed + star.x * 0.05);
      final double alpha = star.baseBrightness * (0.65 + wave * 0.25);

      _starPaint.color = star.color.withValues(alpha: alpha.clamp(0.2, 0.95));
      canvas.drawCircle(Offset(star.x, star.y), star.radius, _starPaint);
    }
  }

  void _paintConstellationAuras(Canvas canvas) {
    for (final c in constellations) {
      // Ambient radial nebula aura
      _auraPaint.shader = ui.Gradient.radial(
        c.center,
        c.radius * 1.5,
        [
          c.glowColor.withValues(alpha: 0.28),
          c.glowColor.withValues(alpha: 0.08),
          Colors.transparent,
        ],
        const [0.0, 0.5, 1.0],
      );
      canvas.drawCircle(c.center, c.radius * 1.5, _auraPaint);

      // Fine orbital compass track
      _trackPaint.color = c.primaryColor.withValues(alpha: 0.12);
      canvas.drawCircle(c.center, c.radius * 0.6, _trackPaint);
      canvas.drawCircle(c.center, c.radius * 1.0, _trackPaint);

      // Rotating celestial tick ring
      final double rot = c.rotation;
      _tickPaint.color = c.primaryColor.withValues(alpha: 0.22);
      for (int i = 0; i < 12; i++) {
        final double a = rot + (i * math.pi / 6);
        final cosA = math.cos(a);
        final sinA = math.sin(a);
        final p1 = c.center + Offset(cosA * (c.radius - 3), sinA * (c.radius - 3));
        final p2 = c.center + Offset(cosA * (c.radius + 3), sinA * (c.radius + 3));
        canvas.drawLine(p1, p2, _tickPaint);
      }

      // Constellation Header Title (Zero per-frame layout overhead)
      if (camera.zoom > 0.45) {
        c.ensureTitlePainter();
        final painter = c.titlePainter!;
        painter.paint(
          canvas,
          c.center - Offset(painter.width / 2, c.radius * 1.08 + painter.height),
        );
      }
    }
  }

  void _paintBezierFilaments(Canvas canvas) {
    final Constellation core = constellations.firstWhere((c) => c.id == 'core');

    // 1. Filaments connecting other constellations to the Solar Core
    for (final c in constellations) {
      if (c.id == 'core') continue;

      _path.reset();
      _path.moveTo(core.center.dx, core.center.dy);

      final mid = (core.center + c.center) / 2;
      final double wave = math.sin(animationTime * 1.2 + c.center.dx * 0.01) * 18.0;
      final normal = Offset(-(c.center.dy - core.center.dy), c.center.dx - core.center.dx);
      final normalNormalized = normal.distance > 0 ? normal / normal.distance : Offset.zero;
      final controlPoint = mid + (normalNormalized * wave);

      _path.quadraticBezierTo(controlPoint.dx, controlPoint.dy, c.center.dx, c.center.dy);

      // Soft outer glow pass
      _filamentPaint
        ..color = c.primaryColor.withValues(alpha: 0.10)
        ..strokeWidth = 3.0;
      canvas.drawPath(_path, _filamentPaint);

      // Core electric thread pass
      _filamentPaint
        ..color = c.primaryColor.withValues(alpha: 0.35)
        ..strokeWidth = 1.0;
      canvas.drawPath(_path, _filamentPaint);
    }

    // 2. Intra-constellation filaments connecting apps to their hub
    for (final c in constellations) {
      for (final app in c.apps) {
        _path.reset();
        _path.moveTo(c.center.dx, c.center.dy);

        final mid = (c.center + app.worldPosition) / 2;
        final double pulse = math.sin(animationTime * 1.5 + app.orbitalAngle) * 4.0;
        final control = mid + Offset(pulse, -pulse);

        _path.quadraticBezierTo(control.dx, control.dy, app.worldPosition.dx, app.worldPosition.dy);

        _filamentPaint
          ..color = app.accentColor.withValues(alpha: 0.20)
          ..strokeWidth = 1.0;
        canvas.drawPath(_path, _filamentPaint);
      }
    }
  }

  void _paintAppNodes(Canvas canvas) {
    final double zoom = camera.zoom;
    final visible = camera.visibleWorldBounds.inflate(60.0);

    for (final c in constellations) {
      for (final app in c.apps) {
        final pos = app.worldPosition;

        // Viewport culling
        if (pos.dx < visible.left ||
            pos.dx > visible.right ||
            pos.dy < visible.top ||
            pos.dy > visible.bottom) {
          continue;
        }

        final isFocused = focusedApp == app;
        final double nodeRadius = isFocused ? 31.0 : 25.0;

        // Ensure cached TextPainters are initialized once
        app.ensurePainters(nodeRadius);

        // Outer glow halo
        _haloPaint.shader = ui.Gradient.radial(
          pos,
          nodeRadius * 2.0,
          [
            app.accentColor.withValues(alpha: isFocused ? 0.55 : 0.22),
            app.accentColor.withValues(alpha: 0.05),
            Colors.transparent,
          ],
          const [0.0, 0.55, 1.0],
        );
        canvas.drawCircle(pos, nodeRadius * 2.0, _haloPaint);

        // Glassmorphic node body
        _nodeFillPaint.color = const Color(0xFF111524);
        canvas.drawCircle(pos, nodeRadius, _nodeFillPaint);

        // Illuminated rim border
        _nodeStrokePaint
          ..shader = ui.Gradient.linear(
            pos - Offset(nodeRadius, nodeRadius),
            pos + Offset(nodeRadius, nodeRadius),
            [
              app.accentColor.withValues(alpha: isFocused ? 1.0 : 0.75),
              app.accentColor.withValues(alpha: 0.2),
            ],
          )
          ..strokeWidth = isFocused ? 2.2 : 1.4;
        canvas.drawCircle(pos, nodeRadius, _nodeStrokePaint);

        // Render App Icon
        if (app.decodedIcon != null) {
          final icon = app.decodedIcon!;
          final iconSize = nodeRadius * 1.35;
          final srcRect = Rect.fromLTWH(0, 0, icon.width.toDouble(), icon.height.toDouble());
          final dstRect = Rect.fromCenter(center: pos, width: iconSize, height: iconSize);
          canvas.drawImageRect(icon, srcRect, dstRect, _iconPaint);
        } else if (app.iconPainter != null) {
          final p = app.iconPainter!;
          p.paint(canvas, pos - Offset(p.width / 2, p.height / 2));
        }

        // Notification Pip Badge
        if (app.notificationCount > 0 && app.badgePainter != null) {
          final badgeCenter = pos + Offset(nodeRadius * 0.70, -nodeRadius * 0.70);
          const badgeR = 8.5;
          _badgePaint.color = const Color(0xFFFF3366);
          canvas.drawCircle(badgeCenter, badgeR, _badgePaint);

          _badgeGlowPaint.color = const Color(0x55FF3366);
          canvas.drawCircle(badgeCenter, badgeR * 1.4, _badgeGlowPaint);

          final bp = app.badgePainter!;
          bp.paint(canvas, badgeCenter - Offset(bp.width / 2, bp.height / 2));
        }

        // App Label (LOD - Level of Detail based on Zoom)
        if ((zoom > 0.55 || isFocused) && app.labelPainter != null) {
          final lp = app.labelPainter!;
          lp.paint(canvas, pos + Offset(-lp.width / 2, nodeRadius + 4.0));
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

    // Shockwave Ring
    _shockwavePaint
      ..color = supernova.color.withValues(alpha: (1.0 - p) * 0.8)
      ..strokeWidth = (1.0 - p) * 6.0 + 1.0;
    canvas.drawCircle(pos, easeP * 300.0, _shockwavePaint);

    // Luminous expansion flare
    _burstPaint.shader = ui.Gradient.radial(
      pos,
      easeP * 220.0,
      [
        Colors.white.withValues(alpha: 1.0 - p),
        supernova.color.withValues(alpha: (1.0 - p) * 0.6),
        Colors.transparent,
      ],
      const [0.0, 0.4, 1.0],
    );
    canvas.drawCircle(pos, easeP * 220.0, _burstPaint);

    // Photon streaks
    _streakPaint
      ..color = Colors.white.withValues(alpha: (1.0 - p) * 0.75)
      ..strokeWidth = 1.8;
    for (int i = 0; i < 12; i++) {
      final a = (i * math.pi / 6) + (p * 0.6);
      final r1 = easeP * 35.0;
      final r2 = easeP * 240.0;
      final start = pos + Offset(math.cos(a) * r1, math.sin(a) * r1);
      final end = pos + Offset(math.cos(a) * r2, math.sin(a) * r2);
      canvas.drawLine(start, end, _streakPaint);
    }
  }

  void _paintScreenSpaceElements(Canvas canvas, Size size) {
    // Fold Crease Holographic Seam Line (Flex / Tabletop mode)
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
    // Repainting is strictly driven by the Listenable repaint argument passed to super
    return false;
  }
}
