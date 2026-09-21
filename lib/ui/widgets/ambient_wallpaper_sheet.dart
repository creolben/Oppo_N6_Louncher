import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A transparent handoff between ChronoFold's animated visual language and
/// Android's OEM-owned wallpaper picker.
///
/// The sheet is intentionally shown before leaving the launcher so a user does
/// not mistake ColorOS's lock-screen-shaped system preview for a ChronoFold
/// keyguard replacement.
class AmbientWallpaperSheet extends StatefulWidget {
  const AmbientWallpaperSheet({super.key, required this.onOpenSystemPreview});

  final VoidCallback onOpenSystemPreview;

  @override
  State<AmbientWallpaperSheet> createState() => _AmbientWallpaperSheetState();
}

class _AmbientWallpaperSheetState extends State<AmbientWallpaperSheet>
    with SingleTickerProviderStateMixin {
  late final AnimationController _motion;

  @override
  void initState() {
    super.initState();
    _motion = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduceMotion) {
      _motion.stop();
    } else if (!_motion.isAnimating) {
      _motion.repeat();
    }
  }

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF090D1A),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: const Color(0x6600E5FF)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x99000000),
                blurRadius: 36,
                offset: Offset(0, -8),
              ),
            ],
          ),
          // The sheet has to survive a 360dp-wide cover screen and a 2x font
          // scale, where the full explanation is taller than the panel. The
          // narrative scrolls; the grabber and the two actions stay pinned so
          // the primary button is reachable without a scroll.
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 38,
                height: 4,
                margin: const EdgeInsets.only(top: 12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  primary: false,
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _Eyebrow(label: 'CHRONOFOLD AMBIENT LAYER'),
                      const SizedBox(height: 12),
                      _AmbientPreview(
                        animation: _motion,
                        reduceMotion: reduceMotion,
                      ),
                      const SizedBox(height: 18),
                      const Text(
                        'Your galaxy, beyond Home.',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 7),
                      Text(
                        'ChronoFold keeps the interactive constellation launcher. '
                        'The optional live wallpaper carries only the ambient stars, '
                        'nebulae, meteors, and astrolabe core into ColorOS.',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.68),
                          fontSize: 13.5,
                          height: 1.42,
                        ),
                      ),
                      const SizedBox(height: 16),
                      const _OwnershipRow(),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0x1418BFEA),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0x3300E5FF)),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(
                              Icons.info_outline_rounded,
                              color: Color(0xFF00E5FF),
                              size: 18,
                            ),
                            const SizedBox(width: 9),
                            Expanded(
                              child: Text(
                                'ColorOS owns the secure lock screen, biometrics, '
                                'and notifications. In the chooser, select '
                                'ChronoFold Ambient Galaxy; ColorOS then owns its '
                                'native preview and apply screen. That does not '
                                'replace your ChronoFold launcher.',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.77),
                                  fontSize: 12.5,
                                  height: 1.38,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                child: Column(
                  children: [
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: widget.onOpenSystemPreview,
                        icon: const Icon(Icons.wallpaper_rounded, size: 18),
                        label: const Text(
                          'OPEN COLOROS WALLPAPER CHOOSER',
                          textAlign: TextAlign.center,
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF00B8D4),
                          foregroundColor: const Color(0xFF00141A),
                          minimumSize: const Size.fromHeight(52),
                          textStyle: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('KEEP CHRONOFOLD OPEN'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Eyebrow extends StatelessWidget {
  const _Eyebrow({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: const BoxDecoration(
            color: Color(0xFF00E5FF),
            shape: BoxShape.circle,
            boxShadow: [BoxShadow(color: Color(0xFF00E5FF), blurRadius: 8)],
          ),
        ),
        const SizedBox(width: 8),
        // Wide letter spacing makes this label outgrow a 360dp cover screen on
        // its own, so it wraps rather than running past the panel edge.
        Flexible(
          child: Text(
            label,
            style: const TextStyle(
              color: Color(0xFF00E5FF),
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.45,
            ),
          ),
        ),
      ],
    );
  }
}

class _AmbientPreview extends StatelessWidget {
  const _AmbientPreview({required this.animation, required this.reduceMotion});

  final Animation<double> animation;
  final bool reduceMotion;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      image: true,
      label: 'Animated preview of the ChronoFold ambient galaxy wallpaper',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: AspectRatio(
          aspectRatio: 1.82,
          child: AnimatedBuilder(
            animation: animation,
            builder: (context, _) => CustomPaint(
              painter: _AmbientPreviewPainter(
                progress: animation.value,
                reduceMotion: reduceMotion,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _OwnershipRow extends StatelessWidget {
  const _OwnershipRow();

  @override
  Widget build(BuildContext context) {
    const home = _OwnershipCell(
      icon: Icons.home_rounded,
      label: 'HOME',
      value: 'ChronoFold',
      color: Color(0xFF00E5FF),
    );
    const lock = _OwnershipCell(
      icon: Icons.lock_outline_rounded,
      label: 'LOCK',
      value: 'ColorOS',
      color: Color(0xFFB388FF),
    );

    // Two cells side by side stop fitting once the font scale grows, so past a
    // threshold the pair stacks instead of squeezing "ChronoFold" to nothing.
    final scaledLabel = MediaQuery.textScalerOf(context).scale(12);
    if (scaledLabel > 16) {
      return const Column(
        children: [home, SizedBox(height: 8), lock],
      );
    }

    return const Row(
      children: [
        Expanded(child: home),
        SizedBox(width: 8),
        Expanded(child: lock),
      ],
    );
  }
}

class _OwnershipCell extends StatelessWidget {
  const _OwnershipCell({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 17),
          const SizedBox(width: 8),
          // The label stack has to give way inside a ~119dp cell, otherwise the
          // owner name runs past the cell border.
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.48),
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.1,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: color,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AmbientPreviewPainter extends CustomPainter {
  const _AmbientPreviewPainter({
    required this.progress,
    required this.reduceMotion,
  });

  final double progress;
  final bool reduceMotion;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..isAntiAlias = true;
    final time = reduceMotion ? 0.0 : progress * math.pi * 2;
    final bounds = Offset.zero & size;

    paint.shader = RadialGradient(
      center: const Alignment(0, 0.15),
      radius: 1.05,
      colors: const [Color(0xFF111B37), Color(0xFF060914), Color(0xFF010204)],
      stops: const [0, 0.54, 1],
    ).createShader(bounds);
    canvas.drawRect(bounds, paint);

    _drawNebula(
      canvas,
      paint,
      size,
      Offset(
        size.width * (0.25 + math.sin(time * 0.18) * 0.025),
        size.height * (0.30 + math.cos(time * 0.16) * 0.03),
      ),
      const Color(0xFF5830AF),
      0.28,
    );
    _drawNebula(
      canvas,
      paint,
      size,
      Offset(
        size.width * (0.76 + math.cos(time * 0.14) * 0.025),
        size.height * (0.70 + math.sin(time * 0.17) * 0.035),
      ),
      const Color(0xFF007D9F),
      0.22,
    );

    final stars = 46;
    for (var index = 0; index < stars; index++) {
      final seed = index * 37.0;
      final x = ((seed * 53) % 101) / 101 * size.width;
      final y = ((seed * 29 + 13) % 97) / 97 * size.height;
      final twinkle = 0.5 + math.sin(time * (0.8 + index % 3) + seed) * 0.22;
      final radius = 0.6 + (index % 4) * 0.34;
      paint
        ..shader = null
        ..color = const Color(0xFFE9F8FF).withValues(alpha: twinkle);
      canvas.drawCircle(Offset(x, y), radius, paint);
    }

    final center = Offset(size.width * 0.5, size.height * 0.53);
    final coreRadius = size.shortestSide * 0.13;
    paint.shader = RadialGradient(
      colors: [
        const Color(0xFFFFD54F).withValues(alpha: 0.34),
        const Color(0xFFFF8A00).withValues(alpha: 0.1),
        Colors.transparent,
      ],
    ).createShader(Rect.fromCircle(center: center, radius: coreRadius * 3.2));
    canvas.drawCircle(center, coreRadius * 3.2, paint);

    paint
      ..shader = null
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1;
    for (final multiplier in [1.0, 1.48, 2.0]) {
      paint.color = const Color(0xFF64B5F6)
          .withValues(alpha: multiplier == 1 ? 0.42 : 0.18);
      canvas.drawCircle(center, coreRadius * multiplier, paint);
    }

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(time * 9);
    canvas.translate(-center.dx, -center.dy);
    paint.color = const Color(0xFF00E5FF).withValues(alpha: 0.44);
    for (var index = 0; index < 8; index++) {
      final angle = index * math.pi / 4;
      final start = Offset(
        center.dx + math.cos(angle) * coreRadius * 1.62,
        center.dy + math.sin(angle) * coreRadius * 1.62,
      );
      final end = Offset(
        center.dx + math.cos(angle) * coreRadius * 1.86,
        center.dy + math.sin(angle) * coreRadius * 1.86,
      );
      canvas.drawLine(start, end, paint);
    }
    canvas.restore();

    paint
      ..style = PaintingStyle.fill
      ..shader = RadialGradient(
        colors: const [Color(0xFFFFF7D2), Color(0xFFFFB300), Color(0xFF10172B)],
        stops: const [0, 0.44, 1],
      ).createShader(Rect.fromCircle(center: center, radius: coreRadius));
    canvas.drawCircle(center, coreRadius * 0.62, paint);

    if (!reduceMotion) {
      final travel = (progress * 1.3) % 1;
      final head = Offset(
        size.width * (-0.12 + travel * 1.12),
        size.height * (0.2 + travel * 0.34),
      );
      final tail = head - Offset(size.width * 0.13, size.height * 0.07);
      paint
        ..shader = LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [
            Colors.white.withValues(alpha: 0.9),
            const Color(0xFF8DEBFF).withValues(alpha: 0.42),
            Colors.transparent,
          ],
        ).createShader(Rect.fromPoints(tail, head))
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(head, tail, paint);
    }
  }

  void _drawNebula(
    Canvas canvas,
    Paint paint,
    Size size,
    Offset center,
    Color color,
    double opacity,
  ) {
    paint.shader =
        RadialGradient(
          colors: [
            color.withValues(alpha: opacity),
            color.withValues(alpha: opacity * 0.18),
            Colors.transparent,
          ],
          stops: const [0, 0.48, 1],
        ).createShader(
          Rect.fromCircle(center: center, radius: size.longestSide * 0.52),
        );
    canvas.drawRect(Offset.zero & size, paint);
  }

  @override
  bool shouldRepaint(covariant _AmbientPreviewPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.reduceMotion != reduceMotion;
  }
}
