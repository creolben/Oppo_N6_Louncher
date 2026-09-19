import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import '../models/app_entry.dart';
import '../models/constellation.dart';
import '../core/launcher_bridge.dart';
import '../core/foldable_controller.dart';
import '../core/galaxy_layout_engine.dart';
import 'camera_controller.dart';
import 'galaxy_custom_painter.dart';

class GalaxyInteractiveCanvas extends StatefulWidget {
  final List<AppEntry> apps;
  final FoldableController foldable;
  final CameraController camera;
  final GalaxyLayoutEngine layoutEngine;
  final Function(AppEntry app)? onAppSelected;
  final Function(AppEntry app, Offset screenPosition)? onAppLongPressed;
  final Function(Constellation constellation)? onConstellationLongPressed;
  final VoidCallback? onSwipeDown;

  const GalaxyInteractiveCanvas({
    super.key,
    required this.apps,
    required this.foldable,
    required this.camera,
    required this.layoutEngine,
    this.onAppSelected,
    this.onAppLongPressed,
    this.onConstellationLongPressed,
    this.onSwipeDown,
  });

  @override
  State<GalaxyInteractiveCanvas> createState() => _GalaxyInteractiveCanvasState();
}

class _GalaxyInteractiveCanvasState extends State<GalaxyInteractiveCanvas>
    with TickerProviderStateMixin {
  late Ticker _renderLoopTicker;
  final ChangeNotifier _paintRepaintNotifier = ChangeNotifier();
  double _animationTime = 0.0;
  Duration _lastFrameTime = Duration.zero;

  // Starfield particles in fixed world space
  final List<CosmicParticle> _starfield = [];
  final List<ShootingStar> _shootingStars = [];
  double _nextMeteorSpawnTime = 1.5;
  final math.Random _rng = math.Random(1337);

  // Touch and Gesture State
  Offset? _magneticTouchWorld;
  Offset? _lastFocalPoint;
  double _lastScale = 1.0;
  double _accumulatedPanDy = 0.0;
  double _accumulatedPanDx = 0.0;
  SupernovaAnimation? _activeSupernova;
  AppEntry? _focusedApp;

  @override
  void initState() {
    super.initState();
    widget.camera.init(this);
    _generateWorldStarfield(420);

    widget.camera.addListener(_onCameraChange);
    _renderLoopTicker = createTicker(_onRenderTick);
    _renderLoopTicker.start();
  }

  void _onCameraChange() {
    // ignore: invalid_use_of_visible_for_testing_member, invalid_use_of_protected_member
    _paintRepaintNotifier.notifyListeners();
  }

  void _generateWorldStarfield(int count) {
    _starfield.clear();
    const colors = [
      Color(0xFFFFFFFF), // Diamond white
      Color(0xFFB3E5FC), // Icy cyan
      Color(0xFFFFE082), // Warm solar gold
      Color(0xFFFF80AB), // Soft nebula rose
      Color(0xFFE1BEE7), // Ethereal violet
      Color(0xFF80D8FF), // Stellar blue
    ];

    // 1. Layer of distant micro-stardust particles (faint, sharp depth)
    final int microCount = (count * 0.70).round();
    for (int i = 0; i < microCount; i++) {
      final z = 0.3 + _rng.nextDouble() * 0.8;
      _starfield.add(
        CosmicParticle(
          x: _rng.nextDouble() * 4800 - 2400,
          y: _rng.nextDouble() * 4800 - 2400,
          z: z,
          radius: 0.4 + _rng.nextDouble() * 0.65,
          baseBrightness: 0.20 + _rng.nextDouble() * 0.40,
          twinkleSpeed: 0.4 + _rng.nextDouble() * 1.4,
          color: colors[_rng.nextInt(colors.length)],
        ),
      );
    }

    // 2. Main sequence stars (medium brightness & size)
    final int mainCount = (count * 0.24).round();
    for (int i = 0; i < mainCount; i++) {
      final z = 0.8 + _rng.nextDouble() * 1.0;
      _starfield.add(
        CosmicParticle(
          x: _rng.nextDouble() * 4400 - 2200,
          y: _rng.nextDouble() * 4400 - 2200,
          z: z,
          radius: 0.9 + _rng.nextDouble() * 1.1,
          baseBrightness: 0.50 + _rng.nextDouble() * 0.40,
          twinkleSpeed: 0.6 + _rng.nextDouble() * 1.2,
          color: colors[_rng.nextInt(colors.length)],
        ),
      );
    }

    // 3. Bright beacon stars with diffraction cross spikes
    final int beaconCount = count - microCount - mainCount;
    for (int i = 0; i < beaconCount; i++) {
      final z = 1.2 + _rng.nextDouble() * 0.8;
      _starfield.add(
        CosmicParticle(
          x: _rng.nextDouble() * 3800 - 1900,
          y: _rng.nextDouble() * 3800 - 1900,
          z: z,
          radius: 1.8 + _rng.nextDouble() * 1.3,
          baseBrightness: 0.85 + _rng.nextDouble() * 0.15,
          twinkleSpeed: 0.8 + _rng.nextDouble() * 1.5,
          color: colors[_rng.nextInt(colors.length)],
          hasSpikes: true,
        ),
      );
    }
  }

  void _updateShootingStars(double dt) {
    if (_animationTime >= _nextMeteorSpawnTime) {
      _spawnShootingStar();
      _nextMeteorSpawnTime = _animationTime + 2.5 + _rng.nextDouble() * 4.0;
    }

    for (int i = _shootingStars.length - 1; i >= 0; i--) {
      final s = _shootingStars[i];
      s.progress += s.speed * dt;
      if (s.progress >= 1.0) {
        _shootingStars.removeAt(i);
      }
    }
  }

  void _spawnShootingStar() {
    final startX = _rng.nextDouble() * 2600 - 1300;
    final startY = _rng.nextDouble() * 1800 - 1200;
    final angle = (math.pi / 4) + (_rng.nextDouble() - 0.5) * 0.45;
    final dist = 320.0 + _rng.nextDouble() * 300.0;
    final endX = startX + math.cos(angle) * dist;
    final endY = startY + math.sin(angle) * dist;

    const meteorColors = [
      Color(0xFFFFFFFF),
      Color(0xFF80D8FF),
      Color(0xFFFFD54F),
      Color(0xFFA7FFEB),
    ];

    _shootingStars.add(
      ShootingStar(
        start: Offset(startX, startY),
        end: Offset(endX, endY),
        speed: 0.75 + _rng.nextDouble() * 0.75,
        length: 75.0 + _rng.nextDouble() * 65.0,
        thickness: 1.2 + _rng.nextDouble() * 0.9,
        color: meteorColors[_rng.nextInt(meteorColors.length)],
      ),
    );
  }

  void _onRenderTick(Duration elapsed) {
    if (_lastFrameTime == Duration.zero) {
      _lastFrameTime = elapsed;
      return;
    }

    final double dt = (elapsed.inMicroseconds - _lastFrameTime.inMicroseconds) / 1e6;
    _lastFrameTime = elapsed;
    _animationTime += dt;

    _updateShootingStars(dt);

    widget.layoutEngine.updateGalaxyMorph(
      posture: widget.foldable.posture,
      hingeAngle: widget.foldable.hingeAngle,
      dt: dt,
      magneticTouchPoint: _magneticTouchWorld,
    );

    if (_activeSupernova != null &&
        _activeSupernova!.getProgress(_animationTime) >= 1.0) {
      _activeSupernova = null;
    }

    // ignore: invalid_use_of_visible_for_testing_member, invalid_use_of_protected_member
    _paintRepaintNotifier.notifyListeners();
  }

  Constellation? _hitTestConstellation(Offset screenPos) {
    final worldTap = widget.camera.screenToWorld(screenPos);
    for (final c in widget.layoutEngine.constellations) {
      final hitRadius = (c.id == 'core') ? 70.0 : 45.0;
      if ((worldTap - c.center).distance <= hitRadius) {
        return c;
      }
    }
    return null;
  }

  AppEntry? _hitTestApp(Offset screenPos) {
    final worldTap = widget.camera.screenToWorld(screenPos);
    AppEntry? closest;
    double minDistance = double.infinity;

    // Check if any outer constellation is active/expanded
    final activeOuter = widget.layoutEngine.constellations.where(
      (c) => c.id != 'core' && (c.isExpanded || c.expansionProgress > 0.25),
    ).firstOrNull;

    for (final c in widget.layoutEngine.constellations) {
      // If an outer constellation is opened, ONLY its apps are interactive
      if (activeOuter != null) {
        if (c.id != activeOuter.id) continue;
      } else {
        // When no outer constellation is open, only test outer apps if blooming
        if (c.id != 'core' && c.expansionProgress < 0.3) continue;
        // If core is closed or condensing, don't test core apps so center hub can be tapped cleanly!
        if (c.id == 'core' && (c.expansionProgress < 0.35 || !c.isExpanded)) continue;
      }

      for (final app in c.apps) {
        final d = (worldTap - app.worldPosition).distance;
        final hitRadius = (32.0 / widget.camera.zoom).clamp(28.0, 56.0);
        if (d < hitRadius && d < minDistance) {
          minDistance = d;
          closest = app;
        }
      }
    }
    return closest;
  }

  void _handleTapUp(TapUpDetails details) {
    // 1. Check if user tapped an active app
    final tappedApp = _hitTestApp(details.localPosition);
    if (tappedApp != null) {
      HapticFeedback.mediumImpact();
      _focusedApp = tappedApp;
      _activeSupernova = SupernovaAnimation(
        worldPosition: tappedApp.worldPosition,
        color: tappedApp.accentColor,
        startTime: _animationTime,
      );

      widget.onAppSelected?.call(tappedApp);

      Future.delayed(const Duration(milliseconds: 300), () {
        LauncherBridge.launchApp(tappedApp);
      });
      return;
    }

    // 2. Check if user tapped a constellation cluster hub
    final tappedConstellation = _hitTestConstellation(details.localPosition);
    if (tappedConstellation != null) {
      HapticFeedback.lightImpact();
      if (tappedConstellation.id == 'core') {
        final anyOuterExpanded = widget.layoutEngine.constellations.any(
          (c) => c.id != 'core' && (c.isExpanded || c.expansionProgress > 0.25),
        );
        if (anyOuterExpanded) {
          widget.layoutEngine.expandOnly('core');
          widget.camera.flyTo(Offset.zero, targetZoom: 1.25);
        } else {
          // Toggle center constellation between open and closed
          final willExpand = !tappedConstellation.isExpanded;
          tappedConstellation.isExpanded = willExpand;
          if (willExpand) {
            widget.camera.flyTo(Offset.zero, targetZoom: 1.25);
          } else {
            widget.camera.flyTo(Offset.zero, targetZoom: 1.05);
          }
        }
      } else {
        final willExpand = !tappedConstellation.isExpanded;
        if (willExpand) {
          widget.layoutEngine.expandOnly(tappedConstellation.id);
          widget.camera.flyTo(tappedConstellation.center, targetZoom: 1.4);
        } else {
          tappedConstellation.isExpanded = false;
          widget.camera.flyTo(Offset.zero, targetZoom: 1.05);
        }
      }
      return;
    }

    // 3. Tapped empty space: smoothly collapse expanded outer constellations back to clean state
    _focusedApp = null;
    final anyOuterExpanded = widget.layoutEngine.constellations.any(
      (c) => c.id != 'core' && (c.isExpanded || c.expansionProgress > 0.25),
    );
    if (anyOuterExpanded) {
      widget.layoutEngine.collapseAllExceptCore();
      widget.camera.flyTo(Offset.zero, targetZoom: 1.05);
    }
  }

  void _handleLongPress(LongPressStartDetails details) {
    final app = _hitTestApp(details.localPosition);
    if (app != null) {
      HapticFeedback.heavyImpact();
      widget.onAppLongPressed?.call(app, details.localPosition);
      return;
    }

    // If long pressing constellation emblem / center hub
    final constellation = _hitTestConstellation(details.localPosition);
    if (constellation != null) {
      if (constellation.isExpanded || constellation.id == 'core') {
        HapticFeedback.heavyImpact();
        widget.onConstellationLongPressed?.call(constellation);
      }
    }
  }

  @override
  void dispose() {
    widget.camera.removeListener(_onCameraChange);
    _renderLoopTicker.dispose();
    _paintRepaintNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        widget.camera.updateViewportSize(constraints.biggest);

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: _handleTapUp,
          onLongPressStart: _handleLongPress,
          onScaleStart: (details) {
            _lastFocalPoint = details.localFocalPoint;
            _lastScale = 1.0;
            _accumulatedPanDy = 0.0;
            _accumulatedPanDx = 0.0;
            _magneticTouchWorld = widget.camera.screenToWorld(details.localFocalPoint);
          },
          onScaleUpdate: (details) {
            if (_lastFocalPoint != null) {
              final delta = details.localFocalPoint - _lastFocalPoint!;
              _accumulatedPanDy += delta.dy;
              _accumulatedPanDx += delta.dx;
              widget.camera.applyPan(delta);
              _lastFocalPoint = details.localFocalPoint;
            }

            if (details.scale != 1.0) {
              final scaleDelta = details.scale / _lastScale;
              widget.camera.applyScale(scaleDelta, details.localFocalPoint);
              _lastScale = details.scale;
            }

            _magneticTouchWorld = widget.camera.screenToWorld(details.localFocalPoint);
          },
          onScaleEnd: (details) {
            final vy = details.velocity.pixelsPerSecond.dy;
            final vx = details.velocity.pixelsPerSecond.dx.abs();
            final isFastSwipeDown = vy > 480 && vy > vx * 1.5;
            final isIntentionalDragDown = _accumulatedPanDy > 140 && _accumulatedPanDy > _accumulatedPanDx.abs() * 2.0;

            if ((isFastSwipeDown || isIntentionalDragDown) && widget.onSwipeDown != null) {
              HapticFeedback.mediumImpact();
              widget.onSwipeDown!();
            } else {
              widget.camera.onDragEnd(details.velocity);
            }

            _lastFocalPoint = null;
            _lastScale = 1.0;
            _accumulatedPanDy = 0.0;
            _accumulatedPanDx = 0.0;
            _magneticTouchWorld = null;
          },
          child: RepaintBoundary(
            child: CustomPaint(
              size: Size.infinite,
              painter: GalaxyCustomPainter(
                repaint: _paintRepaintNotifier,
                camera: widget.camera,
                constellations: widget.layoutEngine.constellations,
                foldable: widget.foldable,
                animationTime: _animationTime,
                starfield: _starfield,
                shootingStars: _shootingStars,
                activeSupernova: _activeSupernova,
                activeTouchScreenPoint: _lastFocalPoint,
                focusedApp: _focusedApp,
              ),
            ),
          ),
        );
      },
    );
  }
}
