import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import '../models/app_entry.dart';
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

  const GalaxyInteractiveCanvas({
    super.key,
    required this.apps,
    required this.foldable,
    required this.camera,
    required this.layoutEngine,
    this.onAppSelected,
    this.onAppLongPressed,
  });

  @override
  State<GalaxyInteractiveCanvas> createState() => _GalaxyInteractiveCanvasState();
}

class _GalaxyInteractiveCanvasState extends State<GalaxyInteractiveCanvas>
    with TickerProviderStateMixin {
  late Ticker _renderLoopTicker;
  double _animationTime = 0.0;
  Duration _lastFrameTime = Duration.zero;

  // Starfield particles
  final List<CosmicParticle> _starfield = [];
  final math.Random _rng = math.Random(42);

  // Touch and Gesture State
  Offset? _magneticTouchWorld;
  Offset? _lastFocalPoint;
  double _lastScale = 1.0;
  SupernovaAnimation? _activeSupernova;
  AppEntry? _focusedApp;

  @override
  void initState() {
    super.initState();
    widget.camera.init(this);
    _generateStarfield(180);

    _renderLoopTicker = createTicker(_onRenderTick);
    _renderLoopTicker.start();
  }

  void _generateStarfield(int count) {
    _starfield.clear();
    const colors = [
      Color(0xFFFFFFFF),
      Color(0xFF90CAF9),
      Color(0xFFFFCC80),
      Color(0xFFF48FB1),
      Color(0xFFE1BEE7),
    ];

    for (int i = 0; i < count; i++) {
      final z = 0.3 + _rng.nextDouble() * 1.5; // depth
      _starfield.add(
        CosmicParticle(
          x: _rng.nextDouble() * 2400 - 1200,
          y: _rng.nextDouble() * 2400 - 1200,
          z: z,
          radius: (0.7 + _rng.nextDouble() * 1.6),
          brightness: 0.3 + _rng.nextDouble() * 0.7,
          twinkleSpeed: 0.8 + _rng.nextDouble() * 2.2,
          color: colors[_rng.nextInt(colors.length)],
        ),
      );
    }
  }

  void _onRenderTick(Duration elapsed) {
    if (_lastFrameTime == Duration.zero) {
      _lastFrameTime = elapsed;
      return;
    }

    final double dt = (elapsed.inMicroseconds - _lastFrameTime.inMicroseconds) / 1e6;
    _lastFrameTime = elapsed;
    _animationTime += dt;

    // Update galaxy physics, orbits & posture morphing
    widget.layoutEngine.updateGalaxyMorph(
      posture: widget.foldable.posture,
      hingeAngle: widget.foldable.hingeAngle,
      dt: dt,
      magneticTouchPoint: _magneticTouchWorld,
    );

    // Clean up expired supernova
    if (_activeSupernova != null &&
        _activeSupernova!.getProgress(_animationTime) >= 1.0) {
      _activeSupernova = null;
    }

    if (mounted) {
      setState(() {});
    }
  }

  AppEntry? _hitTestApp(Offset screenPos) {
    final worldTap = widget.camera.screenToWorld(screenPos);
    AppEntry? closest;
    double minDistance = double.infinity;

    for (final app in widget.layoutEngine.allApps) {
      final d = (worldTap - app.worldPosition).distance;
      // Hit radius scales slightly with zoom to remain comfortably touchable
      final hitRadius = (32.0 / widget.camera.zoom).clamp(28.0, 56.0);
      if (d < hitRadius && d < minDistance) {
        minDistance = d;
        closest = app;
      }
    }
    return closest;
  }

  void _handleTapUp(TapUpDetails details) {
    final tappedApp = _hitTestApp(details.localPosition);
    if (tappedApp != null) {
      HapticFeedback.mediumImpact();
      setState(() {
        _focusedApp = tappedApp;
        _activeSupernova = SupernovaAnimation(
          worldPosition: tappedApp.worldPosition,
          color: tappedApp.accentColor,
          startTime: _animationTime,
        );
      });

      widget.onAppSelected?.call(tappedApp);

      // Launch application after brief dramatic supernova expansion
      Future.delayed(const Duration(milliseconds: 320), () {
        LauncherBridge.launchApp(tappedApp);
      });
    } else {
      // Tapped space: reset focus
      setState(() {
        _focusedApp = null;
      });
    }
  }

  void _handleLongPress(LongPressStartDetails details) {
    final app = _hitTestApp(details.localPosition);
    if (app != null) {
      HapticFeedback.heavyImpact();
      widget.onAppLongPressed?.call(app, details.localPosition);
    }
  }

  @override
  void dispose() {
    _renderLoopTicker.dispose();
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
            _magneticTouchWorld = widget.camera.screenToWorld(details.localFocalPoint);
          },
          onScaleUpdate: (details) {
            if (_lastFocalPoint != null) {
              final delta = details.localFocalPoint - _lastFocalPoint!;
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
            _lastFocalPoint = null;
            _lastScale = 1.0;
            _magneticTouchWorld = null;
            widget.camera.onDragEnd(details.velocity);
          },
          child: CustomPaint(
            size: Size.infinite,
            painter: GalaxyCustomPainter(
              camera: widget.camera,
              constellations: widget.layoutEngine.constellations,
              foldable: widget.foldable,
              animationTime: _animationTime,
              starfield: _starfield,
              activeSupernova: _activeSupernova,
              activeTouchScreenPoint: _lastFocalPoint,
              focusedApp: _focusedApp,
            ),
          ),
        );
      },
    );
  }
}
