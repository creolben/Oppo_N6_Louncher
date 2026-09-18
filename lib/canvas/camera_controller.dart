import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/scheduler.dart';

class CameraController extends ChangeNotifier {
  Offset _translation = Offset.zero;
  double _zoom = 1.0;
  Size _viewportSize = Size.zero;

  // Zoom Limits
  static const double minZoom = 0.45;
  static const double maxZoom = 2.4;

  // Kinetic Physics
  Ticker? _ticker;
  FrictionSimulation? _panSimulationX;
  FrictionSimulation? _panSimulationY;
  double _panSimTime = 0.0;
  SpringSimulation? _zoomSpring;
  double _springStartZoom = 1.0;
  double _springTargetZoom = 1.0;
  double _springTime = 0.0;
  Duration _lastTickTime = Duration.zero;

  // Fly-To animation
  AnimationController? _flyController;
  Animation<Offset>? _flyOffsetAnim;
  Animation<double>? _flyZoomAnim;

  Offset get translation => _translation;
  double get zoom => _zoom;
  Size get viewportSize => _viewportSize;

  void init(TickerProvider vsync) {
    _ticker = vsync.createTicker(_onTick);
    _flyController = AnimationController(
      vsync: vsync,
      duration: const Duration(milliseconds: 550),
    )..addListener(() {
        if (_flyOffsetAnim != null && _flyZoomAnim != null) {
          _translation = _flyOffsetAnim!.value;
          _zoom = _flyZoomAnim!.value;
          notifyListeners();
        }
      });
  }

  void updateViewportSize(Size size) {
    if (_viewportSize == size) return;
    _viewportSize = size;
    if (_translation == Offset.zero && size != Size.zero) {
      _translation = Offset(size.width / 2, size.height / 2);
    }
  }

  Offset _clampTranslation(Offset t) {
    if (_viewportSize == Size.zero) return t;
    // Allow panning up to 750px from center in world space
    final double maxPan = 750.0 * _zoom;
    final double cx = _viewportSize.width / 2;
    final double cy = _viewportSize.height / 2;
    return Offset(
      t.dx.clamp(cx - maxPan, cx + maxPan),
      t.dy.clamp(cy - maxPan, cy + maxPan),
    );
  }

  Offset worldToScreen(Offset world) {
    return Offset(
      world.dx * _zoom + _translation.dx,
      world.dy * _zoom + _translation.dy,
    );
  }

  Offset screenToWorld(Offset screen) {
    return Offset(
      (screen.dx - _translation.dx) / _zoom,
      (screen.dy - _translation.dy) / _zoom,
    );
  }

  Rect get visibleWorldBounds {
    if (_viewportSize == Size.zero || _zoom <= 0) return Rect.zero;
    final topLeft = screenToWorld(Offset.zero);
    final bottomRight = screenToWorld(Offset(_viewportSize.width, _viewportSize.height));
    return Rect.fromPoints(topLeft, bottomRight);
  }

  void applyPan(Offset delta) {
    _stopPhysics();
    _translation = _clampTranslation(_translation + delta);
    notifyListeners();
  }

  void applyScale(double scaleDelta, Offset focalScreenPoint) {
    _stopPhysics();
    final double newZoom = (_zoom * scaleDelta).clamp(minZoom * 0.8, maxZoom * 1.2);

    final worldFocal = screenToWorld(focalScreenPoint);
    _zoom = newZoom;
    _translation = _clampTranslation(focalScreenPoint - (worldFocal * _zoom));

    notifyListeners();
  }

  void onDragEnd(Velocity velocity) {
    final double vx = velocity.pixelsPerSecond.dx;
    final double vy = velocity.pixelsPerSecond.dy;

    // Check zoom snap back if overzoomed
    if (_zoom < minZoom || _zoom > maxZoom) {
      final target = _zoom.clamp(minZoom, maxZoom);
      _springStartZoom = _zoom;
      _springTargetZoom = target;
      _springTime = 0.0;
      _zoomSpring = SpringSimulation(
        const SpringDescription(mass: 1.0, stiffness: 240.0, damping: 25.0),
        0.0,
        1.0,
        0.0,
      );
    }

    if (vx.abs() > 60 || vy.abs() > 60 || _zoomSpring != null) {
      // Natural kinetic drag coefficient
      const drag = 0.135;
      _panSimulationX = FrictionSimulation(drag, _translation.dx, vx);
      _panSimulationY = FrictionSimulation(drag, _translation.dy, vy);
      _panSimTime = 0.0;

      _lastTickTime = Duration.zero;
      _ticker?.stop();
      _ticker?.start();
    }
  }

  void _onTick(Duration elapsed) {
    if (_lastTickTime == Duration.zero) {
      _lastTickTime = elapsed;
      return;
    }

    final double dt = (elapsed.inMicroseconds - _lastTickTime.inMicroseconds) / 1e6;
    _lastTickTime = elapsed;

    bool stillRunning = false;

    if (_panSimulationX != null && _panSimulationY != null) {
      _panSimTime += dt;
      final double nextX = _panSimulationX!.x(_panSimTime);
      final double nextY = _panSimulationY!.x(_panSimTime);
      _translation = _clampTranslation(Offset(nextX, nextY));

      if (_panSimulationX!.isDone(_panSimTime) && _panSimulationY!.isDone(_panSimTime)) {
        _panSimulationX = null;
        _panSimulationY = null;
      } else {
        stillRunning = true;
      }
    }

    if (_zoomSpring != null) {
      _springTime += dt;
      final double t = _zoomSpring!.x(_springTime);
      _zoom = _springStartZoom + (_springTargetZoom - _springStartZoom) * t;

      if (!_zoomSpring!.isDone(_springTime)) {
        stillRunning = true;
      } else {
        _zoom = _springTargetZoom;
        _zoomSpring = null;
      }
    }

    notifyListeners();

    if (!stillRunning) {
      _ticker?.stop();
    }
  }

  void _stopPhysics() {
    _ticker?.stop();
    _panSimulationX = null;
    _panSimulationY = null;
    _zoomSpring = null;
    _flyController?.stop();
  }

  void flyTo(Offset worldTarget, {double targetZoom = 1.30}) {
    _stopPhysics();
    if (_viewportSize == Size.zero) return;

    final targetTranslation = _clampTranslation(Offset(
      _viewportSize.width / 2 - (worldTarget.dx * targetZoom),
      _viewportSize.height / 2 - (worldTarget.dy * targetZoom),
    ));

    final curve = CurvedAnimation(
      parent: _flyController!,
      curve: Curves.easeOutCubic,
    );

    _flyOffsetAnim = Tween<Offset>(
      begin: _translation,
      end: targetTranslation,
    ).animate(curve);

    _flyZoomAnim = Tween<double>(
      begin: _zoom,
      end: targetZoom,
    ).animate(curve);

    _flyController?.forward(from: 0.0);
  }

  void resetView() {
    flyTo(Offset.zero, targetZoom: 1.0);
  }

  @override
  void dispose() {
    _ticker?.dispose();
    _flyController?.dispose();
    super.dispose();
  }
}
