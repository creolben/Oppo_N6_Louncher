import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../models/app_entry.dart';

/// One app sphere in the lock screen's ambient field.
///
/// The sphere lives in a grid slot ([homePosition]) and only ever moves within
/// a few dp of it: the field is a calm grid that breathes in place, not a
/// simulation. There is no velocity to keep, because there is nowhere to go.
class AppBubble {
  final AppEntry app;
  Offset position;
  double radius;
  Color color;

  /// The centre of this sphere's grid slot. The ambient breath is measured
  /// from here and the painted aura is confined to the band around it.
  Offset homePosition = Offset.zero;

  /// This sphere's phase (radians) in the ambient breath. One per bubble so
  /// neighbours breathe out of step instead of marching in lockstep.
  double breathPhase = 0.0;

  AppBubble({
    required this.app,
    required this.position,
    this.radius = 32.0,
    Color? color,
  }) : color = color ?? app.accentColor;
}

/// The lock screen's ambient grid.
///
/// The field is decoration: every sphere sits in a fixed grid slot and only
/// breathes a few dp around it. It is deliberately *not* a physics simulation —
/// a free-drift sim walked the spheres off their rows on the device, which is
/// what this replaces. The grid itself is still laid out by
/// [AppBubble.homePosition] so the block stays centred in the band.
///
/// A [ChangeNotifier] so the painter can repaint from it directly
/// (`CustomPainter(repaint: engine)`): the widget tree stays still while the
/// canvas repaints, instead of the whole lock screen rebuilding per frame.
class BouncingPhysicsEngine extends ChangeNotifier {
  final List<AppBubble> bubbles = [];

  /// Seconds of breath elapsed. Only advances inside [update], so when the
  /// ticker idles the field freezes exactly where it is and resumes there.
  double _elapsed = 0.0;

  Size _viewportSize = Size.zero;
  EdgeInsets _safePadding = EdgeInsets.zero;

  /// The empty space the grid leaves between two ring edges.
  ///
  /// No longer enforced by a collision pass — the layout guarantees it by
  /// construction, and a test holds the gap so a future tweak cannot quietly
  /// close it.
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

  /// The breathe envelope and its primary period.
  ///
  /// A sphere never leaves this radius around its home slot. The horizontal
  /// swing uses the full amplitude; the vertical uses half of it so the two
  /// axes together stay inside the envelope and a row never visibly pulls
  /// apart.
  static const double breathAmplitude = 4.0;
  static const double _breathPeriod = 6.0;
  static const double _breathW = 2 * math.pi / _breathPeriod;

  /// Golden-angle phase step: neighbouring slots breathe out of step without
  /// the field ever repeating a simple march.
  static const double _phaseStep = 2.399963229728653;

  Size get viewportSize => _viewportSize;
  EdgeInsets get safePadding => _safePadding;

  /// The band the simulation is currently confined to, or null before any
  /// bounds have been applied.
  ///
  /// Derived from [_viewportSize] and [_safePadding] rather than cached: the
  /// engine is the single source of truth, so a caller that reset the padding
  /// (a late [initializeBubbles] after the app list arrives) cannot leave a
  /// stale copy behind.
  Rect? get bounds {
    if (_viewportSize == Size.zero) return null;
    return Rect.fromLTRB(
      _safePadding.left,
      _safePadding.top,
      _viewportSize.width - _safePadding.right,
      _viewportSize.height - _safePadding.bottom,
    );
  }

  void initializeBubbles({
    required List<AppEntry> apps,
    required Size size,
    EdgeInsets padding = const EdgeInsets.symmetric(horizontal: 24, vertical: 80),
  }) {
    _viewportSize = size;
    _safePadding = padding;
    _elapsed = 0.0;
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
    // are enough to read as a constellation, and more would only crowd the
    // grid behind the HUD.
    final int maxApps = 8;
    for (final app in sortedApps.take(maxApps)) {
      bubbles.add(
        AppBubble(
          app: app,
          position: Offset(size.width / 2, size.height / 2),
          color: app.accentColor,
        ),
      );
    }

    _placeInBand();
    notifyListeners();
  }

  /// Lays the spheres out in evenly spaced cells across the current band.
  ///
  /// Each row spans the full usable width — one sphere per slot, the outermost
  /// flush with the usable edge — so the field reads across the band instead of
  /// piling against one side after a re-band. Every sphere starts exactly on
  /// its slot: the ambient breath in [update] is what moves it, and only a few
  /// dp. Nothing is jittered, so rows are ruled straight.
  void _placeInBand() {
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

    // One pitch shared by every row. The widest row spans the usable width;
    // a shorter row is centred on that same pitch instead of stretching its
    // own edges, which is what stops the block leaning when row counts differ.
    final double pitch = cols > 1 ? usableW / (cols - 1) : 0.0;

    // A cell taller than this leaves a hole above the field. Cap it and centre
    // the block, so the clear space above and below matches.
    final double maxCellH = 2.6 * painted;
    final double cellH = rows > 0
        ? math.min(usableH / rows, maxCellH)
        : usableH;
    final double blockH = cellH * rows;
    final double blockTop = usableTop + (usableH - blockH) / 2;

    for (int i = 0; i < count; i++) {
      final bubble = bubbles[i];
      bubble.radius = radius;

      final int row = i ~/ cols;
      final int col = i % cols;
      final int rowCount = math.min(cols, count - row * cols);

      final double centreY = blockTop + cellH * (row + 0.5);
      final double centreX;
      if (cols > 1) {
        // A short row keeps the shared pitch and is centred under the widest.
        final double rowInset = (cols - rowCount) * pitch / 2;
        centreX = usableLeft + rowInset + col * pitch;
      } else {
        centreX = usableLeft + usableW / 2;
      }

      bubble.homePosition = Offset(centreX, centreY);
      bubble.position = bubble.homePosition;
      // A distinct breath phase per slot: neighbours never march in lockstep.
      bubble.breathPhase = i * _phaseStep;
    }
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

  /// Advances the ambient breath by [dt] seconds and repaints.
  ///
  /// This is the whole simulation: every sphere is placed on a deterministic
  /// breath around its home slot. There is no velocity, no collision and no
  /// wall bounce — a free simulation is what walked the grid off its rows on
  /// the device. The painted aura is still clamped to the band.
  void update(double dt) {
    if (bubbles.isEmpty || _viewportSize == Size.zero) return;

    // A long frame (a stalled ticker, a resume) must not jump the breath.
    _elapsed += math.min(dt, 0.033);

    for (final bubble in bubbles) {
      final double phase = bubble.breathPhase;
      final Offset drift = Offset(
        math.sin(_elapsed * _breathW + phase) * breathAmplitude,
        // A different frequency on the vertical keeps the path open rather
        // than a closed circle. Half the amplitude keeps both axes together
        // inside the 4 dp envelope, so a row never visibly pulls apart.
        math.cos(_elapsed * _breathW * 0.8 + phase) * (breathAmplitude * 0.5),
      );
      bubble.position = _confine(bubble.homePosition + drift, bubble.radius);
    }

    // The painter listens to this and repaints only its own layer.
    notifyListeners();
  }

  /// Parks every sphere on its home slot.
  ///
  /// Used when motion is disabled: reduce-motion gets the static grid, not a
  /// frozen frame part-way through the breath.
  void settleToHome() {
    for (final bubble in bubbles) {
      bubble.position = bubble.homePosition;
    }
    notifyListeners();
  }

  /// Pulls [position] inside the band's painted extent for [radius].
  Offset _confine(Offset position, double radius) {
    final double painted = paintedRadius(radius);
    return Offset(
      _clamp(
        position.dx,
        _safePadding.left + painted,
        _viewportSize.width - _safePadding.right - painted,
      ),
      _clamp(
        position.dy,
        _safePadding.top + painted,
        _viewportSize.height - _safePadding.bottom - painted,
      ),
    );
  }
}
