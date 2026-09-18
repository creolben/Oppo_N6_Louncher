import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

enum DevicePosture {
  folded, // Closed cover screen (angle ~ 0°-30°)
  halfOpened, // Book posture (angle ~ 30°-70° or 120°-160°)
  tabletop, // Flex mode (angle ~ 70°-115°)
  flat, // Fully opened main screen (angle ~ 160°-180°)
}

class FoldableController extends ChangeNotifier {
  static const EventChannel _hingeEventChannel =
      EventChannel('com.launcher.chronofold/hinge');

  StreamSubscription? _hingeSubscription;

  double _hingeAngle = 180.0; // Defaults to fully open
  bool _isSimulated = false;
  DevicePosture _posture = DevicePosture.flat;
  Rect? _creaseBounds;
  bool _isVerticalHinge = true;

  double get hingeAngle => _hingeAngle;
  bool get isSimulated => _isSimulated;
  DevicePosture get posture => _posture;
  Rect? get creaseBounds => _creaseBounds;
  bool get isVerticalHinge => _isVerticalHinge;

  bool get isFolded => _posture == DevicePosture.folded;
  bool get isTabletop => _posture == DevicePosture.tabletop;
  bool get isFlat => _posture == DevicePosture.flat;

  FoldableController() {
    _initNativeSensor();
  }

  void _initNativeSensor() {
    if (!kIsWeb && Platform.isAndroid) {
      try {
        _hingeSubscription = _hingeEventChannel
            .receiveBroadcastStream()
            .listen((dynamic rawAngle) {
          if (!_isSimulated && rawAngle is num) {
            setHingeAngle(rawAngle.toDouble(), fromSimulation: false);
          }
        }, onError: (dynamic error) {
          debugPrint('Hinge sensor error: $error');
        });
      } catch (e) {
        debugPrint('Failed to subscribe to hinge sensor: $e');
      }
    }
  }

  void updateFromMediaQuery(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final displayFeatures = mediaQuery.displayFeatures;

    Rect? foundCrease;
    for (final feature in displayFeatures) {
      if (feature.type == DisplayFeatureType.hinge ||
          feature.type == DisplayFeatureType.fold) {
        foundCrease = feature.bounds;
        _isVerticalHinge = feature.bounds.height > feature.bounds.width;
        break;
      }
    }

    if (foundCrease != _creaseBounds) {
      _creaseBounds = foundCrease;
      notifyListeners();
    }

    // If on narrow screen (cover screen aspect ratio > 1.8), and not simulated
    if (!_isSimulated) {
      final aspect = mediaQuery.size.height / mediaQuery.size.width;
      if (aspect > 1.85 && foundCrease == null) {
        _updatePostureFromAngle(0.0);
      }
    }
  }

  void setHingeAngle(double angle, {bool fromSimulation = true}) {
    _isSimulated = fromSimulation;
    _hingeAngle = angle.clamp(0.0, 180.0);
    _updatePostureFromAngle(_hingeAngle);
    notifyListeners();
  }

  void setPosture(DevicePosture posture) {
    _isSimulated = true;
    _posture = posture;
    switch (posture) {
      case DevicePosture.folded:
        _hingeAngle = 0.0;
        break;
      case DevicePosture.halfOpened:
        _hingeAngle = 60.0;
        break;
      case DevicePosture.tabletop:
        _hingeAngle = 90.0;
        break;
      case DevicePosture.flat:
        _hingeAngle = 180.0;
        break;
    }
    notifyListeners();
  }

  void _updatePostureFromAngle(double angle) {
    if (angle <= 35.0) {
      _posture = DevicePosture.folded;
    } else if (angle >= 70.0 && angle <= 115.0) {
      _posture = DevicePosture.tabletop;
    } else if (angle >= 155.0) {
      _posture = DevicePosture.flat;
    } else {
      _posture = DevicePosture.halfOpened;
    }
  }

  @override
  void dispose() {
    _hingeSubscription?.cancel();
    super.dispose();
  }
}
