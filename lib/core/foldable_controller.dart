import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

enum DevicePosture {
  folded, // Closed cover screen (angle ~ 0°-35°)
  halfOpened, // Book posture (angle ~ 35°-70° or 115°-155°)
  tabletop, // Flex mode (angle ~ 70°-115°)
  flat, // Fully opened main screen (angle ~ 155°-180°)
}

/// Tracks the physical fold state of the device.
///
/// The hardware hinge sensor (`android.sensor.hinge_angle`, type 36) is
/// authoritative: posture always follows the real hinge unless the in-app
/// posture simulator is explicitly engaged, and the simulator releases itself
/// as soon as the hardware reports real movement.
class FoldableController extends ChangeNotifier {
  static const EventChannel _hingeEventChannel =
      EventChannel('com.launcher.chronofold/hinge');

  /// While the simulator is engaged, a real hinge movement of at least this
  /// many degrees means the user physically moved the device, so live hardware
  /// takes over again and the simulated posture is released.
  static const double simulationReleaseThreshold = 8.0;

  static const double _foldedMaxAngle = 35.0;
  static const double _tabletopMinAngle = 70.0;
  static const double _tabletopMaxAngle = 115.0;
  static const double _flatMinAngle = 155.0;

  /// Aspect ratio above which a display is treated as the tall, narrow cover
  /// screen. On the Find N-series the cover screen is ~2.29 while the inner
  /// display is close to square (~1.10).
  static const double _coverAspectThreshold = 1.65;

  StreamSubscription? _hingeSubscription;

  /// Last angle reported by the hardware hinge sensor.
  double _sensorAngle = 180.0;

  /// Angle forced by the posture simulator, or null when the hardware sensor
  /// is authoritative.
  double? _simulatedAngle;

  /// Sensor angle the simulation was baselined against, used to detect genuine
  /// hinge movement while simulated. Null until the first sensor reading.
  double? _simulationAnchor;

  bool _hasHingeSensor = false;
  DevicePosture _posture = DevicePosture.flat;
  Rect? _creaseBounds;
  bool _isVerticalHinge = true;
  bool _isOnCoverDisplay = false;
  int? _displayId;

  /// Effective hinge angle: the simulated value while simulating, otherwise the
  /// live hardware reading.
  double get hingeAngle => _simulatedAngle ?? _sensorAngle;

  /// True while the in-app posture simulator is overriding the hardware.
  bool get isSimulated => _simulatedAngle != null;

  /// True once the hardware hinge sensor has reported at least one reading.
  bool get hasHingeSensor => _hasHingeSensor;

  DevicePosture get posture => _posture;
  Rect? get creaseBounds => _creaseBounds;
  bool get isVerticalHinge => _isVerticalHinge;

  /// True when rendering on the tall, narrow cover screen.
  bool get isOnCoverDisplay => _isOnCoverDisplay;
  bool get isOnInnerDisplay => !_isOnCoverDisplay;

  /// Identifier of the [Display] currently rendering the launcher, when known.
  int? get displayId => _displayId;

  bool get isFolded => _posture == DevicePosture.folded;
  bool get isTabletop => _posture == DevicePosture.tabletop;
  bool get isFlat => _posture == DevicePosture.flat;

  FoldableController() {
    _initNativeSensor();
  }

  void _initNativeSensor() {
    if (kIsWeb || !Platform.isAndroid) {
      return;
    }
    try {
      _hingeSubscription = _hingeEventChannel.receiveBroadcastStream().listen(
        (dynamic rawAngle) {
          if (rawAngle is num) {
            _onSensorAngle(rawAngle.toDouble());
          }
        },
        onError: (dynamic error) {
          debugPrint('Hinge sensor error: $error');
        },
      );
    } catch (e) {
      debugPrint('Failed to subscribe to hinge sensor: $e');
    }
  }

  /// Applies a hardware reading. The reading is always recorded; it only drives
  /// posture when the simulator is not overriding it.
  void _onSensorAngle(double angle) {
    _hasHingeSensor = true;
    _sensorAngle = angle.clamp(0.0, 180.0);

    if (_simulatedAngle != null) {
      final anchor = _simulationAnchor;
      if (anchor == null) {
        // First reading after the simulation began becomes the baseline, so a
        // cold start cannot instantly cancel an intended simulated posture.
        _simulationAnchor = _sensorAngle;
        return;
      }
      if ((_sensorAngle - anchor).abs() >= simulationReleaseThreshold) {
        clearSimulation();
      }
      return;
    }

    _applyPosture(postureForAngle(_sensorAngle));
  }

  /// Reads fold features and display identity for the current view. Call from
  /// the root widget's build.
  void updateFromMediaQuery(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final features = mediaQuery.displayFeatures;

    Rect? foundCrease;
    var verticalHinge = _isVerticalHinge;
    for (final feature in features) {
      if (feature.type == DisplayFeatureType.hinge ||
          feature.type == DisplayFeatureType.fold) {
        foundCrease = feature.bounds;
        verticalHinge = feature.bounds.height > feature.bounds.width;
        break;
      }
    }

    final displayId = _resolveDisplayId(context);
    final onCover =
        _classifyDisplay(mediaQuery, hasFoldFeature: foundCrease != null);

    var changed = false;
    if (foundCrease != _creaseBounds) {
      _creaseBounds = foundCrease;
      changed = true;
    }
    if (verticalHinge != _isVerticalHinge) {
      _isVerticalHinge = verticalHinge;
      changed = true;
    }
    if (displayId != _displayId) {
      _displayId = displayId;
      changed = true;
    }
    if (onCover != _isOnCoverDisplay) {
      _isOnCoverDisplay = onCover;
      changed = true;
    }

    // Posture: hardware first, display identity only as the fallback for
    // devices that never report a hinge angle.
    final DevicePosture target;
    if (_simulatedAngle != null) {
      target = _posture;
    } else if (_hasHingeSensor) {
      target = postureForAngle(_sensorAngle);
    } else {
      target = onCover ? DevicePosture.folded : DevicePosture.flat;
    }
    if (target != _posture) {
      _posture = target;
      changed = true;
    }

    if (changed) {
      notifyListeners();
    }
  }

  int? _resolveDisplayId(BuildContext context) {
    try {
      return View.of(context).display.id;
    } catch (_) {
      // View/display not available (e.g. in tests): fall back to geometry.
      return null;
    }
  }

  bool _classifyDisplay(
    MediaQueryData mediaQuery, {
    required bool hasFoldFeature,
  }) {
    // A reported hinge/fold feature only exists on the folding inner display.
    if (hasFoldFeature) {
      return false;
    }
    final width = mediaQuery.size.width;
    if (width <= 0) {
      return _isOnCoverDisplay;
    }
    return mediaQuery.size.height / width > _coverAspectThreshold;
  }

  /// Engages the posture simulator, or feeds a hardware reading when
  /// [fromSimulation] is false.
  void setHingeAngle(double angle, {bool fromSimulation = true}) {
    if (!fromSimulation) {
      _onSensorAngle(angle);
      return;
    }
    _simulatedAngle = angle.clamp(0.0, 180.0);
    _simulationAnchor = _hasHingeSensor ? _sensorAngle : null;
    _applyPosture(postureForAngle(_simulatedAngle!));
  }

  /// Engages the posture simulator at the angle that represents [posture].
  void setPosture(DevicePosture posture) {
    _simulatedAngle = angleForPosture(posture);
    _simulationAnchor = _hasHingeSensor ? _sensorAngle : null;
    _applyPosture(posture);
  }

  /// Drops any simulated posture and hands control back to the hinge sensor.
  void clearSimulation() {
    if (_simulatedAngle == null) {
      return;
    }
    _simulatedAngle = null;
    _simulationAnchor = null;
    final target = _hasHingeSensor
        ? postureForAngle(_sensorAngle)
        : (_isOnCoverDisplay ? DevicePosture.folded : DevicePosture.flat);
    _applyPosture(target, forceNotify: true);
  }

  void _applyPosture(DevicePosture posture, {bool forceNotify = false}) {
    final changed = _posture != posture;
    _posture = posture;
    if (changed || forceNotify) {
      notifyListeners();
    }
  }

  /// Maps a hinge angle to a posture using the same bands the cockpit UI labels.
  static DevicePosture postureForAngle(double angle) {
    if (angle <= _foldedMaxAngle) {
      return DevicePosture.folded;
    }
    if (angle >= _tabletopMinAngle && angle <= _tabletopMaxAngle) {
      return DevicePosture.tabletop;
    }
    if (angle >= _flatMinAngle) {
      return DevicePosture.flat;
    }
    return DevicePosture.halfOpened;
  }

  /// Canonical hinge angle for a posture.
  static double angleForPosture(DevicePosture posture) {
    switch (posture) {
      case DevicePosture.folded:
        return 0.0;
      case DevicePosture.halfOpened:
        return 60.0;
      case DevicePosture.tabletop:
        return 90.0;
      case DevicePosture.flat:
        return 180.0;
    }
  }

  @override
  void dispose() {
    _hingeSubscription?.cancel();
    super.dispose();
  }
}
