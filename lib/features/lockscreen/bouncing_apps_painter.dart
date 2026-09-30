import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../../ui/theme/luminous_home_theme.dart';
import 'bouncing_physics_engine.dart';

/// High-performance CustomPainter rendering cosmic glassmorphic ambient app
/// spheres and their constellation filaments.
///
/// The field is decoration: the painter draws spheres and their ambient
/// effects and nothing else. It holds no labels and no touch affordances — the
/// lock surface's only app targets are the phone and camera shortcuts, so a
/// bubble is never a thing a user is invited to press.
///
/// Repaints are driven by the physics engine's [ChangeNotifier]
/// (`repaint: physics`), so a simulation frame costs one canvas repaint — not
/// a rebuild of the lock screen widget tree around it.
class BouncingAppsPainter extends CustomPainter {
  final BouncingPhysicsEngine physics;

  // Statically allocated Paint objects to prevent GC pressure at 60/120 FPS
  static final Paint _filamentPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round;

  static final Paint _auraPaint = Paint()
    ..style = PaintingStyle.fill;

  static final Paint _bubbleFillPaint = Paint()
    ..style = PaintingStyle.fill;

  static final Paint _bubbleBorderPaint = Paint()
    ..style = PaintingStyle.stroke;

  static final Paint _specularPaint = Paint()
    ..style = PaintingStyle.fill;

  static final Paint _iconImgPaint = Paint()
    ..filterQuality = FilterQuality.medium
    ..isAntiAlias = true;

  BouncingAppsPainter({required this.physics}) : super(repaint: physics);

  @override
  void paint(Canvas canvas, Size size) {
    if (physics.bubbles.isEmpty) return;

    // 1. Draw Constellation Proximity Filaments between nearby bubbles
    _drawProximityFilaments(canvas);

    // 2. Draw App Spheres (Icons and Orbs — never labels)
    _drawBubbles(canvas);
  }

  void _drawProximityFilaments(Canvas canvas) {
    final bubbles = physics.bubbles;
    const double maxConnectDist = 85.0;
    const double maxConnectDistSq = maxConnectDist * maxConnectDist;

    for (int i = 0; i < bubbles.length; i++) {
      final b1 = bubbles[i];
      int connections = 0;
      for (int j = i + 1; j < bubbles.length; j++) {
        if (connections >= 2) break;
        final b2 = bubbles[j];
        final double distSq = (b2.position - b1.position).distanceSquared;

        if (distSq < maxConnectDistSq) {
          final double dist = math.sqrt(distSq);
          final double proximityAlpha = (1.0 - (dist / maxConnectDist)).clamp(0.0, 1.0);
          final double alpha = proximityAlpha * 0.25;

          _filamentPaint
            ..strokeWidth = 0.8 + proximityAlpha * 1.0
            ..shader = ui.Gradient.linear(
              b1.position,
              b2.position,
              [
                b1.color.withValues(alpha: alpha),
                b2.color.withValues(alpha: alpha),
              ],
            );

          canvas.drawLine(b1.position, b2.position, _filamentPaint);
          connections++;
        }
      }
    }
  }

  void _drawBubbles(Canvas canvas) {
    for (final bubble in physics.bubbles) {
      canvas.save();
      canvas.translate(bubble.position.dx, bubble.position.dy);

      // Squash and stretch scale transform on bounce
      if (bubble.bounceSquash < 1.0) {
        canvas.scale(2.0 - bubble.bounceSquash, bubble.bounceSquash);
      }

      final double r = bubble.radius;
      final Color color = bubble.color;
      // The aura is what the eye reads as the sphere, so the engine confines
      // this painted extent (not just the core) to the band.
      final double painted = BouncingPhysicsEngine.paintedRadius(r);

      // A. Outer Radiant Cosmic Glow Aura
      final double auraGlow = (0.2 + bubble.glowIntensity * 0.6)
          .clamp(0.0, 1.0);
      _auraPaint.shader = ui.Gradient.radial(
        Offset.zero,
        painted,
        [
          color.withValues(alpha: auraGlow * 0.6),
          color.withValues(alpha: auraGlow * 0.2),
          Colors.transparent,
        ],
        [0.35, 0.7, 1.0],
      );
      canvas.drawCircle(Offset.zero, painted, _auraPaint);

      // B. Glassmorphic Cosmic Sphere Body
      _bubbleFillPaint.shader = ui.Gradient.radial(
        Offset(-r * 0.32, -r * 0.32),
        r * 1.3,
        [
          LuminousHomeTheme.bubbleShellTop.withValues(alpha: 0.95),
          LuminousHomeTheme.bubbleShellMid.withValues(alpha: 0.92),
          LuminousHomeTheme.bubbleShellDeep.withValues(alpha: 0.96),
        ],
        [0.0, 0.65, 1.0],
      );
      canvas.drawCircle(Offset.zero, r, _bubbleFillPaint);

      // C. Upper Specular Lens Glint
      _specularPaint.shader = ui.Gradient.radial(
        Offset(-r * 0.3, -r * 0.35),
        r * 0.6,
        [
          Colors.white.withValues(alpha: 0.35),
          Colors.white.withValues(alpha: 0.05),
          Colors.transparent,
        ],
        [0.0, 0.6, 1.0],
      );
      canvas.drawCircle(Offset(-r * 0.15, -r * 0.2), r * 0.55, _specularPaint);

      // D. Hairline edge ring. One theme tone instead of a per-app glow
      // gradient: the ring reads the same on every sphere against the dark
      // field, and the app's accent lives in the aura and the fill.
      _bubbleBorderPaint
        ..strokeWidth = 1.5
        ..shader = null
        ..color = LuminousHomeTheme.hairlineStrong;
      canvas.drawCircle(Offset.zero, r, _bubbleBorderPaint);

      // E. Render App Icon inside sphere. No label follows: the field is
      // ambient, and a label under a drifting sphere is unreadable anyway.
      _drawAppIcon(canvas, bubble, r);

      canvas.restore();
    }
  }

  void _drawAppIcon(Canvas canvas, AppBubble bubble, double r) {
    final app = bubble.app;
    final double iconDiameter = r * 1.22;
    final double iconRadius = iconDiameter / 2;

    if (app.decodedIcon != null) {
      canvas.save();
      // Clip to smooth rounded circle inside the bubble
      final Path clipPath = Path()
        ..addOval(Rect.fromCircle(center: Offset.zero, radius: iconRadius));
      canvas.clipPath(clipPath);

      final ui.Image img = app.decodedIcon!;
      final Rect srcRect = Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble());
      final Rect dstRect = Rect.fromCenter(
        center: Offset.zero,
        width: iconDiameter,
        height: iconDiameter,
      );
      canvas.drawImageRect(img, srcRect, dstRect, _iconImgPaint);
      canvas.restore();

      // Cosmic glow rim around the normalized circular icon
      _bubbleBorderPaint
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0
        ..shader = null
        ..color = bubble.color.withValues(alpha: 0.40);
      canvas.drawCircle(Offset.zero, iconRadius, _bubbleBorderPaint);
    } else {
      // Crisp Fallback Glyph
      final double fontSize = r * 0.95;
      final textPainter = TextPainter(
        text: TextSpan(
          text: String.fromCharCode(app.fallbackIcon.codePoint),
          style: TextStyle(
            inherit: false,
            color: bubble.color,
            fontSize: fontSize,
            fontFamily: app.fallbackIcon.fontFamily,
            package: app.fallbackIcon.fontPackage,
            shadows: [
              Shadow(
                color: bubble.color.withValues(alpha: 0.8),
                blurRadius: 10.0,
              ),
            ],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      textPainter.paint(
        canvas,
        Offset(-textPainter.width / 2, -textPainter.height / 2),
      );
    }
  }

  @override
  bool shouldRepaint(covariant BouncingAppsPainter oldDelegate) {
    // Simulation frames arrive through the engine's repaint listenable, so a
    // rebuild only needs to repaint when the engine it reads from changed.
    return oldDelegate.physics != physics;
  }
}
