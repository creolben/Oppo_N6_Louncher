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
  final SupernovaAnimation? activeSupernova;
  final Offset? activeTouchScreenPoint;
  final AppEntry? focusedApp;

  // Statically allocated Paint objects
  static final Paint _bgPaint = Paint();
  static final Paint _starPaint = Paint()..style = PaintingStyle.fill;
  static final Paint _auraPaint = Paint();
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
    _bgPaint.shader = ui.Gradient.radial(
      Offset(size.width * 0.5, size.height * 0.45),
      size.longestSide * 0.85,
      const [
        Color(0xFF0D1222), // Obsidian navy
        Color(0xFF060912), // Deep void
        Color(0xFF010206), // True OLED pitch black
      ],
      const [0.0, 0.60, 1.0],
    );
    canvas.drawRect(bgRect, _bgPaint);
  }

  void _paintWorldStarfield(Canvas canvas) {
    final visible = camera.visibleWorldBounds.inflate(120.0);

    for (final star in starfield) {
      if (star.x < visible.left ||
          star.x > visible.right ||
          star.y < visible.top ||
          star.y > visible.bottom) {
        continue;
      }

      final double wave = math.sin(animationTime * star.twinkleSpeed + star.x * 0.05);
      final double alpha = star.baseBrightness * (0.70 + wave * 0.20);

      _starPaint.color = star.color.withValues(alpha: alpha.clamp(0.2, 0.95));
      canvas.drawCircle(Offset(star.x, star.y), star.radius, _starPaint);
    }
  }

  void _paintConstellationAuras(Canvas canvas) {
    for (final c in constellations) {
      c.ensurePainters();
      final double progress = c.expansionProgress;

      // Soft ambient nebula aura
      final double auraRadius = (c.id == 'core' || progress > 0.5) ? c.radius * 1.4 : 70.0;
      _auraPaint.shader = ui.Gradient.radial(
        c.center,
        auraRadius,
        [
          c.glowColor.withValues(alpha: progress > 0.3 ? 0.22 : 0.35),
          c.glowColor.withValues(alpha: 0.06),
          Colors.transparent,
        ],
        const [0.0, 0.55, 1.0],
      );
      canvas.drawCircle(c.center, auraRadius, _auraPaint);

      // Collapsed: Modern Frosted Pod Orb
      if (c.id != 'core' && progress < 0.85) {
        final double orbAlpha = (1.0 - progress).clamp(0.0, 1.0);
        const double podSize = 72.0;
        final podRect = Rect.fromCenter(center: c.center, width: podSize, height: podSize);
        final podRRect = RRect.fromRectAndRadius(podRect, const Radius.circular(22.0));

        // Soft drop shadow
        _haloPaint.color = c.glowColor.withValues(alpha: 0.20 * orbAlpha);
        canvas.drawRRect(podRRect.inflate(6.0), _haloPaint);

        // Frosted Glass Pod Body
        _nodeFillPaint.color = const Color(0xFF13192B).withValues(alpha: 0.92 * orbAlpha);
        canvas.drawRRect(podRRect, _nodeFillPaint);

        // Illuminated Rim Border
        _nodeStrokePaint
          ..shader = ui.Gradient.linear(
            podRect.topLeft,
            podRect.bottomRight,
            [
              c.primaryColor.withValues(alpha: 0.85 * orbAlpha),
              c.secondaryColor.withValues(alpha: 0.30 * orbAlpha),
            ],
          )
          ..strokeWidth = 1.6;
        canvas.drawRRect(podRRect, _nodeStrokePaint);

        // Center Emblem Icon
        if (c.iconPainter != null) {
          final ip = c.iconPainter!;
          ip.paint(canvas, c.center - Offset(ip.width / 2, ip.height / 2 + 2));
        }

        // Subtitle badge below pod
        if (c.countBadgePainter != null) {
          final cbp = c.countBadgePainter!;
          cbp.paint(canvas, c.center + Offset(-cbp.width / 2, podSize / 2 + 8.0));
        }
      }

      // Expanded: Subtle Orbital Compass Rings
      if (progress > 0.15 || c.id == 'core') {
        final double trackAlpha = c.id == 'core' ? 0.9 : progress;

        _trackPaint.color = c.primaryColor.withValues(alpha: 0.10 * trackAlpha);
        canvas.drawCircle(c.center, c.radius * 0.75, _trackPaint);
        canvas.drawCircle(c.center, c.radius * 1.0, _trackPaint);

        final double rot = c.rotation;
        _tickPaint.color = c.primaryColor.withValues(alpha: 0.18 * trackAlpha);
        for (int i = 0; i < 8; i++) {
          final double a = rot + (i * math.pi / 4);
          final cosA = math.cos(a);
          final sinA = math.sin(a);
          final p1 = c.center + Offset(cosA * (c.radius - 2.5), sinA * (c.radius - 2.5));
          final p2 = c.center + Offset(cosA * (c.radius + 2.5), sinA * (c.radius + 2.5));
          canvas.drawLine(p1, p2, _tickPaint);
        }
      }

      // Constellation Title
      if (c.titlePainter != null) {
        final painter = c.titlePainter!;
        final double titleY = (c.id == 'core' || progress > 0.4)
            ? c.radius * 1.06 + painter.height
            : 52.0 + painter.height;
        painter.paint(
          canvas,
          c.center - Offset(painter.width / 2, titleY),
        );
      }
    }
  }

  void _paintBezierFilaments(Canvas canvas) {
    final Constellation core = constellations.firstWhere((c) => c.id == 'core');

    // 1. Filaments connecting sectors to Essentials Core
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

      final double filamentAlpha = c.isExpanded ? 0.6 : 0.25;
      _filamentPaint
        ..color = c.primaryColor.withValues(alpha: 0.06 * filamentAlpha)
        ..strokeWidth = 2.5;
      canvas.drawPath(_path, _filamentPaint);

      _filamentPaint
        ..color = c.primaryColor.withValues(alpha: 0.28 * filamentAlpha)
        ..strokeWidth = 1.0;
      canvas.drawPath(_path, _filamentPaint);
    }

    // 2. Intra-constellation filaments
    for (final c in constellations) {
      final double progress = c.id == 'core' ? 1.0 : c.expansionProgress;
      if (progress < 0.1) continue;

      for (final app in c.apps) {
        _path.reset();
        _path.moveTo(c.center.dx, c.center.dy);

        final mid = (c.center + app.worldPosition) / 2;
        _path.quadraticBezierTo(mid.dx, mid.dy, app.worldPosition.dx, app.worldPosition.dy);

        _filamentPaint
          ..color = app.accentColor.withValues(alpha: 0.16 * progress)
          ..strokeWidth = 1.0;
        canvas.drawPath(_path, _filamentPaint);
      }
    }
  }

  void _paintAppNodes(Canvas canvas) {
    final double zoom = camera.zoom;
    final visible = camera.visibleWorldBounds.inflate(60.0);

    for (final c in constellations) {
      final double progress = c.id == 'core' ? 1.0 : c.expansionProgress;
      if (progress < 0.08) continue;

      for (final app in c.apps) {
        final pos = app.worldPosition;

        if (pos.dx < visible.left ||
            pos.dx > visible.right ||
            pos.dy < visible.top ||
            pos.dy > visible.bottom) {
          continue;
        }

        final isFocused = focusedApp == app;
        final double nodeSize = (isFocused ? 58.0 : 50.0) * (0.45 + progress * 0.55);
        final double halfSize = nodeSize / 2;

        app.ensurePainters(halfSize);

        final nodeRect = Rect.fromCenter(center: pos, width: nodeSize, height: nodeSize);
        final nodeRRect = RRect.fromRectAndRadius(nodeRect, Radius.circular(nodeSize * 0.30));

        // Outer glow halo
        _haloPaint.shader = ui.Gradient.radial(
          pos,
          nodeSize * 1.1,
          [
            app.accentColor.withValues(alpha: (isFocused ? 0.50 : 0.18) * progress),
            app.accentColor.withValues(alpha: 0.03 * progress),
            Colors.transparent,
          ],
          const [0.0, 0.60, 1.0],
        );
        canvas.drawCircle(pos, nodeSize * 1.1, _haloPaint);

        // Modern Glassmorphic Squircle Body
        _nodeFillPaint.color = const Color(0xFF13182A).withValues(alpha: 0.94 * progress);
        canvas.drawRRect(nodeRRect, _nodeFillPaint);

        // Satin illuminated rim border
        _nodeStrokePaint
          ..shader = ui.Gradient.linear(
            nodeRect.topLeft,
            nodeRect.bottomRight,
            [
              app.accentColor.withValues(alpha: (isFocused ? 1.0 : 0.75) * progress),
              app.accentColor.withValues(alpha: 0.18 * progress),
            ],
          )
          ..strokeWidth = isFocused ? 2.0 : 1.2;
        canvas.drawRRect(nodeRRect, _nodeStrokePaint);

        // App Icon
        if (app.decodedIcon != null) {
          final icon = app.decodedIcon!;
          final iconSize = nodeSize * 0.64;
          final srcRect = Rect.fromLTWH(0, 0, icon.width.toDouble(), icon.height.toDouble());
          final dstRect = Rect.fromCenter(center: pos, width: iconSize, height: iconSize);
          _iconPaint.color = Colors.white.withValues(alpha: progress);
          canvas.drawImageRect(icon, srcRect, dstRect, _iconPaint);
        } else if (app.iconPainter != null) {
          final p = app.iconPainter!;
          p.paint(canvas, pos - Offset(p.width / 2, p.height / 2));
        }

        // Notification Pip Badge
        if (app.notificationCount > 0 && app.badgePainter != null && progress > 0.6) {
          final badgeCenter = pos + Offset(halfSize * 0.85, -halfSize * 0.85);
          const badgeR = 8.0;
          _badgePaint.color = const Color(0xFFFF3366).withValues(alpha: progress);
          canvas.drawCircle(badgeCenter, badgeR, _badgePaint);

          _badgeGlowPaint.color = const Color(0x55FF3366).withValues(alpha: progress);
          canvas.drawCircle(badgeCenter, badgeR * 1.3, _badgeGlowPaint);

          final bp = app.badgePainter!;
          bp.paint(canvas, badgeCenter - Offset(bp.width / 2, bp.height / 2));
        }

        // App Label
        if ((zoom > 0.52 || isFocused) && app.labelPainter != null && progress > 0.75) {
          final lp = app.labelPainter!;
          lp.paint(canvas, pos + Offset(-lp.width / 2, halfSize + 5.0));
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
