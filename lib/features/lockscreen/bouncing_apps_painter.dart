import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'bouncing_physics_engine.dart';

/// High-performance CustomPainter rendering cosmic glassmorphic bouncing app spheres,
/// constellation filaments, impact contact sparks, and shake shockwaves.
///
/// Repaints are driven by the physics engine's [ChangeNotifier] (`repaint:
/// physics`), so a simulation frame costs one canvas repaint — not a rebuild
/// of the lock screen widget tree around it.
class BouncingAppsPainter extends CustomPainter {
  final BouncingPhysicsEngine physics;
  final AppBubble? draggedBubble;

  /// Ambient system text scale, so painted app labels grow with the setting the
  /// same way widget text does.
  final TextScaler textScaler;

  // Statically allocated Paint objects to prevent GC pressure at 60/120 FPS
  static final Paint _filamentPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round;

  static final Paint _ripplePaint = Paint()
    ..style = PaintingStyle.stroke;

  static final Paint _sparkPaint = Paint()
    ..style = PaintingStyle.fill;

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

  BouncingAppsPainter({
    required this.physics,
    this.draggedBubble,
    this.textScaler = TextScaler.noScaling,
  }) : super(repaint: physics);

  @override
  void paint(Canvas canvas, Size size) {
    if (physics.bubbles.isEmpty) return;

    // 1. Draw Constellation Proximity Filaments between nearby bubbles
    _drawProximityFilaments(canvas);

    // 2. Draw Cosmic Shockwave Ripples (from shake or major collisions)
    _drawShockwaveRipples(canvas);

    // 3. Draw Collision Contact Sparks
    _drawSparks(canvas);

    // 4. Draw App Spheres (Icons, Orbs, Labels)
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

  void _drawShockwaveRipples(Canvas canvas) {
    for (final ripple in physics.ripples) {
      final double r = ripple.currentRadius;
      final double alpha = ripple.opacity;
      if (r <= 0.0 || alpha <= 0.0) continue;

      _ripplePaint
        ..strokeWidth = 3.5 * (1.0 - ripple.progress * 0.6)
        ..color = ripple.color.withValues(alpha: alpha * 0.85);

      canvas.drawCircle(ripple.center, r, _ripplePaint);

      // Inner faint harmonic echo
      if (r > 20.0) {
        _ripplePaint
          ..strokeWidth = 1.5
          ..color = ripple.color.withValues(alpha: alpha * 0.4);
        canvas.drawCircle(ripple.center, r * 0.75, _ripplePaint);
      }
    }
  }

  void _drawSparks(Canvas canvas) {
    for (final spark in physics.sparks) {
      final double progress = (spark.age / spark.maxAge).clamp(0.0, 1.0);
      final double alpha = (1.0 - progress);
      final double currentSize = spark.initialSize * (1.0 - progress * 0.5);

      _sparkPaint.color = spark.color.withValues(alpha: alpha);
      canvas.drawCircle(spark.position, currentSize, _sparkPaint);
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
      final bool isDragged = bubble.isBeingDragged;

      // A. Outer Radiant Cosmic Glow Aura
      final double auraGlow = (0.2 + bubble.glowIntensity * 0.6 + (isDragged ? 0.3 : 0.0))
          .clamp(0.0, 1.0);
      _auraPaint.shader = ui.Gradient.radial(
        Offset.zero,
        r * 1.55,
        [
          color.withValues(alpha: auraGlow * 0.6),
          color.withValues(alpha: auraGlow * 0.2),
          Colors.transparent,
        ],
        [0.35, 0.7, 1.0],
      );
      canvas.drawCircle(Offset.zero, r * 1.55, _auraPaint);

      // B. Glassmorphic Cosmic Sphere Body
      _bubbleFillPaint.shader = ui.Gradient.radial(
        Offset(-r * 0.32, -r * 0.32),
        r * 1.3,
        [
          const Color(0xFF1E2846).withValues(alpha: 0.95),
          const Color(0xFF0D1426).withValues(alpha: 0.92),
          const Color(0xFF050814).withValues(alpha: 0.96),
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

      // D. Glowing Neon Edge Border
      _bubbleBorderPaint
        ..strokeWidth = isDragged ? 2.8 : 1.8
        ..shader = ui.Gradient.linear(
          Offset(-r, -r),
          Offset(r, r),
          [
            color.withValues(alpha: isDragged ? 1.0 : 0.95),
            color.withValues(alpha: 0.45),
            color.withValues(alpha: isDragged ? 0.9 : 0.75),
          ],
          [0.0, 0.5, 1.0],
        );
      canvas.drawCircle(Offset.zero, r, _bubbleBorderPaint);

      // E. Render App Icon inside sphere
      _drawAppIcon(canvas, bubble, r);

      canvas.restore();

      // F. App Label (Rendered outside the transform matrix to keep text un-squashed)
      _drawAppLabel(canvas, bubble);
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

  void _drawAppLabel(Canvas canvas, AppBubble bubble) {
    final app = bubble.app;
    app.ensurePainters(bubble.radius, textScaler: textScaler);

    if (app.labelPainter != null) {
      final double labelX = bubble.position.dx - (app.labelPainter!.width / 2);
      final double labelY = bubble.position.dy + bubble.radius + 4.0;

      final bool isDragged = bubble.isBeingDragged;

      // Soft pill backdrop for label legibility over dark background
      final Rect pillRect = Rect.fromLTWH(
        labelX - (isDragged ? 6.0 : 4.0),
        labelY - (isDragged ? 2.0 : 1.0),
        app.labelPainter!.width + (isDragged ? 12.0 : 8.0),
        app.labelPainter!.height + (isDragged ? 4.0 : 2.0),
      );

      final Paint pillPaint = Paint()
        ..color = isDragged
            ? const Color(0xEE0B162C)
            : const Color(0x9903050B)
        ..style = PaintingStyle.fill;

      canvas.drawRRect(
        RRect.fromRectAndRadius(pillRect, Radius.circular(isDragged ? 8 : 5)),
        pillPaint,
      );

      if (isDragged) {
        final Paint pillBorder = Paint()
          ..color = bubble.color.withValues(alpha: 0.8)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0;
        canvas.drawRRect(
          RRect.fromRectAndRadius(pillRect, const Radius.circular(8)),
          pillBorder,
        );
      }

      app.labelPainter!.paint(canvas, Offset(labelX, labelY));
    }
  }

  @override
  bool shouldRepaint(covariant BouncingAppsPainter oldDelegate) {
    // Simulation frames arrive through the engine's repaint listenable, so a
    // rebuild only needs to repaint when what the painter reads from the tree
    // actually changed.
    return oldDelegate.draggedBubble != draggedBubble ||
        oldDelegate.physics != physics ||
        oldDelegate.textScaler != textScaler;
  }
}
