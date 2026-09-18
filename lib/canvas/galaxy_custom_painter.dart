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
  double z; // Parallax depth: 0.3 (far) to 2.0 (close)
  double radius;
  double brightness;
  double twinkleSpeed;
  Color color;

  CosmicParticle({
    required this.x,
    required this.y,
    required this.z,
    required this.radius,
    required this.brightness,
    required this.twinkleSpeed,
    required this.color,
  });
}

class SupernovaAnimation {
  final Offset worldPosition;
  final Color color;
  final double startTime; // elapsed seconds
  final double duration;

  SupernovaAnimation({
    required this.worldPosition,
    required this.color,
    required this.startTime,
    this.duration = 0.85,
  });

  double getProgress(double currentTime) {
    return ((currentTime - startTime) / duration).clamp(0.0, 1.0);
  }
}

class GalaxyCustomPainter extends CustomPainter {
  final CameraController camera;
  final List<Constellation> constellations;
  final FoldableController foldable;
  final double animationTime; // continuously running seconds
  final List<CosmicParticle> starfield;
  final SupernovaAnimation? activeSupernova;
  final Offset? activeTouchScreenPoint;
  final AppEntry? focusedApp;

  GalaxyCustomPainter({
    required this.camera,
    required this.constellations,
    required this.foldable,
    required this.animationTime,
    required this.starfield,
    this.activeSupernova,
    this.activeTouchScreenPoint,
    this.focusedApp,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Render Deep Space Background & Starfield Parallax
    _paintDeepSpace(canvas, size);

    // 2. Setup Camera Transform for World Space
    canvas.save();
    canvas.translate(camera.translation.dx, camera.translation.dy);
    canvas.scale(camera.zoom, camera.zoom);

    // 3. Render Constellation Nebular Auras & Orbital Tracks
    _paintConstellationAuras(canvas);

    // 4. Render Luminous Bezier Filaments
    _paintBezierFilaments(canvas);

    // 5. Render App Celestial Nodes (Icons, Badges, Labels)
    _paintAppNodes(canvas);

    // 6. Render Supernova Launch Animation (if triggered)
    if (activeSupernova != null) {
      _paintSupernova(canvas);
    }

    canvas.restore();

    // 7. Screen-Space Overlays (Hinge Crease Refraction, Touch Ripples)
    _paintScreenSpaceElements(canvas, size);
  }

  void _paintDeepSpace(Canvas canvas, Size size) {
    // Gradient cosmic background
    final bgRect = Offset.zero & size;
    final bgPaint = Paint()
      ..shader = ui.Gradient.radial(
        Offset(size.width * 0.5, size.height * 0.5),
        size.longestSide * 0.8,
        [
          const Color(0xFF0D111F), // Deep cosmic navy
          const Color(0xFF06080F), // Midnight void
          const Color(0xFF020306), // Pitch black
        ],
        [0.0, 0.6, 1.0],
      );
    canvas.drawRect(bgRect, bgPaint);

    // 3D Parallax Starfield
    final starPaint = Paint()..style = PaintingStyle.fill;
    final double camX = camera.translation.dx;
    final double camY = camera.translation.dy;

    for (final star in starfield) {
      // Parallax shift based on star depth Z
      final double sx = (star.x + camX * (0.12 / star.z)) % size.width;
      final double sy = (star.y + camY * (0.12 / star.z)) % size.height;
      final double px = sx < 0 ? sx + size.width : sx;
      final double py = sy < 0 ? sy + size.height : sy;

      final double twinkle = (math.sin(animationTime * star.twinkleSpeed + star.x) + 1.0) * 0.5;
      final double alpha = (star.brightness * (0.4 + twinkle * 0.6)).clamp(0.1, 1.0);

      starPaint.color = star.color.withOpacity(alpha);
      canvas.drawCircle(Offset(px, py), star.radius * star.z, starPaint);
    }
  }

  void _paintConstellationAuras(Canvas canvas) {
    for (final c in constellations) {
      // Ambient radial nebula aura
      final auraPaint = Paint()
        ..shader = ui.Gradient.radial(
          c.center,
          c.radius * 1.5,
          [
            c.glowColor.withOpacity(0.35),
            c.glowColor.withOpacity(0.12),
            Colors.transparent,
          ],
          [0.0, 0.5, 1.0],
        );
      canvas.drawCircle(c.center, c.radius * 1.5, auraPaint);

      // Fine orbital compass track (History of Everything celestial styling)
      final trackPaint = Paint()
        ..color = c.primaryColor.withOpacity(0.15)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0;
      canvas.drawCircle(c.center, c.radius * 0.6, trackPaint);
      canvas.drawCircle(c.center, c.radius * 1.0, trackPaint);

      // Rotating celestial tick ring
      final double rot = c.rotation;
      final tickPaint = Paint()
        ..color = c.primaryColor.withOpacity(0.28)
        ..strokeWidth = 1.2;
      for (int i = 0; i < 12; i++) {
        final double a = rot + (i * math.pi / 6);
        final p1 = c.center + Offset(math.cos(a) * (c.radius * 1.0 - 4), math.sin(a) * (c.radius * 1.0 - 4));
        final p2 = c.center + Offset(math.cos(a) * (c.radius * 1.0 + 4), math.sin(a) * (c.radius * 1.0 + 4));
        canvas.drawLine(p1, p2, tickPaint);
      }

      // Constellation Header Title in World Space (Fades out when zoomed far out)
      if (camera.zoom > 0.45) {
        final textSpan = TextSpan(
          text: c.name.toUpperCase(),
          style: TextStyle(
            color: c.primaryColor.withOpacity(0.75),
            fontSize: 10.0,
            fontWeight: FontWeight.w700,
            letterSpacing: 2.2,
            shadows: [
              Shadow(
                color: c.primaryColor.withOpacity(0.8),
                blurRadius: 8.0,
              ),
            ],
          ),
        );
        final textPainter = TextPainter(
          text: textSpan,
          textDirection: TextDirection.ltr,
        )..layout();
        textPainter.paint(
          canvas,
          c.center - Offset(textPainter.width / 2, c.radius * 1.1 + textPainter.height),
        );
      }
    }
  }

  void _paintBezierFilaments(Canvas canvas) {
    // 1. Bridge filaments connecting constellations to Solar Core
    final Constellation core = constellations.firstWhere((c) => c.id == 'core');
    final filamentPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    for (final c in constellations) {
      if (c.id == 'core') continue;

      final path = Path();
      path.moveTo(core.center.dx, core.center.dy);

      // Organic curved spline with wave perturbation
      final mid = (core.center + c.center) / 2;
      final double wave = math.sin(animationTime * 1.5 + c.center.dx * 0.01) * 24.0;
      final normal = Offset(-(c.center.dy - core.center.dy), c.center.dx - core.center.dx);
      final normalNormalized = normal.distance > 0 ? normal / normal.distance : Offset.zero;
      final controlPoint = mid + (normalNormalized * wave);

      path.quadraticBezierTo(controlPoint.dx, controlPoint.dy, c.center.dx, c.center.dy);

      // Glowing multi-pass stroke
      filamentPaint
        ..color = c.primaryColor.withOpacity(0.12)
        ..strokeWidth = 3.5;
      canvas.drawPath(path, filamentPaint);

      filamentPaint
        ..color = c.primaryColor.withOpacity(0.4)
        ..strokeWidth = 1.2;
      canvas.drawPath(path, filamentPaint);
    }

    // 2. Intra-constellation filaments connecting apps to their cluster hub
    for (final c in constellations) {
      for (final app in c.apps) {
        final path = Path();
        path.moveTo(c.center.dx, c.center.dy);

        // Smooth cubic curve bending towards app
        final mid = (c.center + app.worldPosition) / 2;
        final double pulse = math.sin(animationTime * 2.0 + app.orbitalAngle) * 6.0;
        final control = mid + Offset(pulse, -pulse);

        path.quadraticBezierTo(control.dx, control.dy, app.worldPosition.dx, app.worldPosition.dy);

        filamentPaint
          ..color = app.accentColor.withOpacity(0.25)
          ..strokeWidth = 1.0;
        canvas.drawPath(path, filamentPaint);
      }
    }
  }

  void _paintAppNodes(Canvas canvas) {
    final double zoom = camera.zoom;
    final nodePaint = Paint();

    for (final c in constellations) {
      for (final app in c.apps) {
        final pos = app.worldPosition;
        final isFocused = focusedApp == app;
        final double nodeRadius = isFocused ? 32.0 : 26.0;

        // Outer glow halo
        final haloPaint = Paint()
          ..shader = ui.Gradient.radial(
            pos,
            nodeRadius * 2.2,
            [
              app.accentColor.withOpacity(isFocused ? 0.6 : 0.28),
              app.accentColor.withOpacity(0.08),
              Colors.transparent,
            ],
            [0.0, 0.55, 1.0],
          );
        canvas.drawCircle(pos, nodeRadius * 2.2, haloPaint);

        // Glassmorphic node body
        nodePaint
          ..color = const Color(0xFF131728).withOpacity(0.92)
          ..style = PaintingStyle.fill;
        canvas.drawCircle(pos, nodeRadius, nodePaint);

        // Illuminated rim border
        nodePaint
          ..shader = ui.Gradient.linear(
            pos - Offset(nodeRadius, nodeRadius),
            pos + Offset(nodeRadius, nodeRadius),
            [
              app.accentColor.withOpacity(isFocused ? 1.0 : 0.8),
              app.accentColor.withOpacity(0.25),
            ],
          )
          ..style = PaintingStyle.stroke
          ..strokeWidth = isFocused ? 2.5 : 1.5;
        canvas.drawCircle(pos, nodeRadius, nodePaint);

        // Render App Icon
        if (app.decodedIcon != null) {
          final icon = app.decodedIcon!;
          final iconSize = nodeRadius * 1.35;
          final srcRect = Rect.fromLTWH(0, 0, icon.width.toDouble(), icon.height.toDouble());
          final dstRect = Rect.fromCenter(center: pos, width: iconSize, height: iconSize);
          canvas.drawImageRect(icon, srcRect, dstRect, Paint()..isAntiAlias = true);
        } else {
          // Vector Icon glyph painter
          final iconPainter = TextPainter(
            text: TextSpan(
              text: String.fromCharCode(app.fallbackIcon.codePoint),
              style: TextStyle(
                fontSize: nodeRadius * 1.15,
                fontFamily: app.fallbackIcon.fontFamily,
                package: app.fallbackIcon.fontPackage,
                color: app.accentColor,
              ),
            ),
            textDirection: TextDirection.ltr,
          )..layout();
          iconPainter.paint(
            canvas,
            pos - Offset(iconPainter.width / 2, iconPainter.height / 2),
          );
        }

        // Notification Pip Badge
        if (app.notificationCount > 0) {
          final badgeCenter = pos + Offset(nodeRadius * 0.72, -nodeRadius * 0.72);
          const badgeR = 8.5;
          final badgePaint = Paint()
            ..color = const Color(0xFFFF3366)
            ..style = PaintingStyle.fill;
          canvas.drawCircle(badgeCenter, badgeR, badgePaint);

          // Badge glow
          canvas.drawCircle(
            badgeCenter,
            badgeR * 1.5,
            Paint()..color = const Color(0x66FF3366),
          );

          final countPainter = TextPainter(
            text: TextSpan(
              text: '${app.notificationCount}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 8.5,
                fontWeight: FontWeight.bold,
              ),
            ),
            textDirection: TextDirection.ltr,
          )..layout();
          countPainter.paint(
            canvas,
            badgeCenter - Offset(countPainter.width / 2, countPainter.height / 2),
          );
        }

        // App Label (LOD - Level of Detail based on Zoom)
        if (zoom > 0.55 || isFocused) {
          final double labelAlpha = ((zoom - 0.55) / 0.35).clamp(0.0, 1.0);
          final labelPainter = TextPainter(
            text: TextSpan(
              text: app.label,
              style: TextStyle(
                color: Colors.white.withOpacity(isFocused ? 1.0 : (labelAlpha * 0.9)),
                fontSize: 9.5,
                fontWeight: isFocused ? FontWeight.bold : FontWeight.w500,
                letterSpacing: 0.4,
                shadows: const [
                  Shadow(color: Colors.black, blurRadius: 4.0),
                ],
              ),
            ),
            textDirection: TextDirection.ltr,
          )..layout();

          labelPainter.paint(
            canvas,
            pos + Offset(-labelPainter.width / 2, nodeRadius + 5.0),
          );
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
    final shockwavePaint = Paint()
      ..color = supernova.color.withOpacity((1.0 - p) * 0.9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = (1.0 - p) * 8.0 + 1.0;
    canvas.drawCircle(pos, easeP * 320.0, shockwavePaint);

    // Luminous expansion ball
    final burstPaint = Paint()
      ..shader = ui.Gradient.radial(
        pos,
        easeP * 240.0,
        [
          Colors.white.withOpacity((1.0 - p)),
          supernova.color.withOpacity((1.0 - p) * 0.7),
          Colors.transparent,
        ],
        [0.0, 0.4, 1.0],
      );
    canvas.drawCircle(pos, easeP * 240.0, burstPaint);

    // Radiating photon streaks
    final streakPaint = Paint()
      ..color = Colors.white.withOpacity((1.0 - p) * 0.8)
      ..strokeWidth = 2.0;
    for (int i = 0; i < 16; i++) {
      final a = (i * math.pi / 8) + (p * 0.8);
      final r1 = easeP * 40.0;
      final r2 = easeP * 260.0;
      final start = pos + Offset(math.cos(a) * r1, math.sin(a) * r1);
      final end = pos + Offset(math.cos(a) * r2, math.sin(a) * r2);
      canvas.drawLine(start, end, streakPaint);
    }
  }

  void _paintScreenSpaceElements(Canvas canvas, Size size) {
    // 1. Fold Crease Holographic Seam Line
    final crease = foldable.creaseBounds;
    if (crease != null || (foldable.isTabletop && foldable.isSimulated)) {
      final creaseRect = crease ?? Rect.fromLTWH(0, size.height * 0.5 - 2, size.width, 4);
      final seamPaint = Paint()
        ..shader = ui.Gradient.linear(
          creaseRect.topLeft,
          creaseRect.bottomLeft,
          [
            const Color(0x0000E5FF),
            const Color(0x6600E5FF),
            const Color(0x0000E5FF),
          ],
        );
      canvas.drawRect(
        Rect.fromLTRB(0, creaseRect.top - 12, size.width, creaseRect.bottom + 12),
        seamPaint,
      );

      final linePaint = Paint()
        ..color = const Color(0xAA00E5FF)
        ..strokeWidth = 1.0;
      canvas.drawLine(
        Offset(0, creaseRect.center.dy),
        Offset(size.width, creaseRect.center.dy),
        linePaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant GalaxyCustomPainter oldDelegate) {
    return true; // Continuously animated 120 FPS game loop
  }
}
