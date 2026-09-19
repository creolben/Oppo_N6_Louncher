import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Palette for the comet web-search surface.
///
/// These are not new colours. Every value here is derived from the galaxy
/// core in `galaxy_custom_painter.dart` — the amber `#FFB300` → `#FF6F00`
/// halo and the `#0F1424` node fill — because in this launcher amber already
/// means "origin / emits light". The cockpit bar is uniformly cyan, so a gold
/// control reads as the one thing that reaches outside the galaxy without
/// needing a label to say so.
class CometPalette {
  const CometPalette._();

  /// Primary amber. Matches the core halo in the galaxy painter.
  static const Color amber = Color(0xFFFFB300);

  /// Deep amber used for gradient tails and the orbit trail's far end.
  static const Color amberDeep = Color(0xFFFF6F00);

  /// Near-white hot centre of the comet head.
  static const Color ember = Color(0xFFFFF3D6);

  /// Glass fill, matching the app-search capsule's `#141A30` family.
  static const Color glass = Color(0xFF141A30);

  /// Node fill, lifted from the galaxy's app nodes.
  static const Color nodeFill = Color(0xFF0F1424);

  /// Panel fill for the answer card.
  static const Color panel = Color(0xFF101528);

  /// The scrim used by the app-search overlay, reused verbatim so the two
  /// palettes are visibly siblings.
  static const Color scrim = Color(0xCC04060E);

  /// Border tint shared with app search, so the capsules match.
  static const Color borderCool = Color(0xFF64B5F6);
}

/// The comet sigil: the control that summons web search.
///
/// One gold point inside a slowly rotating elliptical trail. It is the only
/// warm control in a cold bar, which is what makes it findable without a label.
/// Motion is subtle and continuous — this is a launcher, so it has to be
/// ignorable while idle and alive when noticed.
class CometOrb extends StatefulWidget {
  final double size;

  /// Whether the orb is currently the active mode. Drives the flare.
  final bool isActive;

  const CometOrb({super.key, this.size = 22, this.isActive = false});

  @override
  State<CometOrb> createState() => _CometOrbState();
}

class _CometOrbState extends State<CometOrb> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 6000),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Honour the platform's reduced-motion setting: an orbital animation that
    // runs regardless is exactly the kind of thing that makes a launcher feel
    // hostile to users who disabled animations.
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;

    if (reduceMotion) {
      return SizedBox(
        width: widget.size,
        height: widget.size,
        child: CustomPaint(
          painter: _CometOrbPainter(
            progress: 0,
            isActive: widget.isActive,
            animate: false,
          ),
        ),
      );
    }

    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => CustomPaint(
          painter: _CometOrbPainter(
            progress: _controller.value,
            isActive: widget.isActive,
            animate: true,
          ),
        ),
      ),
    );
  }
}

class _CometOrbPainter extends CustomPainter {
  final double progress;
  final bool isActive;
  final bool animate;

  _CometOrbPainter({
    required this.progress,
    required this.isActive,
    required this.animate,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    // Breathing: a slow 3s-equivalent pulse, doubled by the 6s controller so
    // the head swells twice per orbit. Active state flares it further.
    final breath = animate ? 0.5 + 0.5 * math.sin(progress * 2 * math.pi * 2) : 0.5;
    final flare = isActive ? 1.35 : 1.0;
    final headR = radius * (0.30 + 0.05 * breath) * flare;

    // Outer bloom. Radial gradient rather than a blurred circle so this stays
    // cheap enough to sit in a bar that rebuilds on every camera frame.
    final bloomPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          CometPalette.amber.withValues(alpha: (isActive ? 0.42 : 0.26) * (0.85 + 0.15 * breath)),
          CometPalette.amberDeep.withValues(alpha: 0.10),
          Colors.transparent,
        ],
        stops: const [0.0, 0.55, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius, bloomPaint);

    // Elliptical orbit trail: an arc whose opacity ramps along its length, so
    // the comet appears to be travelling rather than sitting in a ring.
    final orbitRect = Rect.fromCenter(
      center: center,
      width: radius * 1.62,
      height: radius * 0.92,
    );
    final rotation = animate ? progress * 2 * math.pi : 0.0;
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(-0.42);
    canvas.translate(-center.dx, -center.dy);

    const segments = 22;
    for (var i = 0; i < segments; i++) {
      final t = i / segments;
      final startAngle = rotation + t * 2 * math.pi;
      final sweep = (2 * math.pi / segments) * 0.85;
      // The tail fades from the head backwards.
      final tail = math.pow(1.0 - t, 2.4).toDouble();
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.15
        ..strokeCap = StrokeCap.round
        ..color = Color.lerp(CometPalette.amberDeep, CometPalette.amber, tail)!
            .withValues(alpha: (isActive ? 0.85 : 0.52) * tail);
      canvas.drawArc(orbitRect, startAngle, sweep, false, paint);
    }
    canvas.restore();

    // Comet head: a hot ember core inside the amber disc.
    canvas.drawCircle(center, headR, Paint()..color = CometPalette.amber);
    canvas.drawCircle(
      center,
      headR * 0.52,
      Paint()..color = CometPalette.ember.withValues(alpha: 0.95),
    );

    // A single satellite mote, offset along the trail.
    if (animate) {
      final moteAngle = rotation * 1.0 + math.pi * 0.75;
      final mote = Offset(
        center.dx + math.cos(moteAngle) * orbitRect.width / 2,
        center.dy + math.sin(moteAngle) * orbitRect.height / 2,
      );
      canvas.drawCircle(
        mote,
        0.9,
        Paint()..color = CometPalette.amber.withValues(alpha: 0.75),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CometOrbPainter old) =>
      old.progress != progress || old.isActive != isActive;
}
