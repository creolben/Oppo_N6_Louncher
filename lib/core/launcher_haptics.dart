import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// ChronoFold's named touch haptics.
///
/// Every haptic in the launcher chrome goes through here so the feel is named
/// once instead of being a scattered `HapticFeedback.*` call: the platform side
/// maps each name to a composed vibration primitive where the device supports
/// it, and falls back to a predefined or short one-shot effect where it does
/// not. On any error — a missing channel, a refused vibration — the call falls
/// back to Flutter's own [HapticFeedback], so a device that cannot serve the
/// richer effect still gets an acknowledgement.
///
/// The lock screen keeps its own `HapticFeedback.*` calls; this is the launcher
/// chrome's bridge only.
abstract final class LauncherHaptics {
  static const MethodChannel _channel =
      MethodChannel('com.launcher.chronofold/apps');

  /// Test seam: the unit-test binary runs on a desktop host, where the bridge
  /// would otherwise short-circuit. Setting this makes the channel path run.
  @visibleForTesting
  static bool debugUsePlatformChannels = false;

  /// A named touch acknowledgement.
  static Future<void> tick() => _perform('tick');

  /// A normal tap acknowledgement.
  static Future<void> click() => _perform('click');

  /// A quieter, lower tap acknowledgement.
  static Future<void> lowTick() => _perform('lowTick');

  /// A firm acknowledgement for a destructive or deliberate action.
  static Future<void> heavyClick() => _perform('heavyClick');

  /// A positive confirmation.
  static Future<void> confirm() => _perform('confirm');

  /// A negative acknowledgement.
  static Future<void> reject() => _perform('reject');

  static Future<void> _perform(String type) async {
    if (!kIsWeb && (Platform.isAndroid || debugUsePlatformChannels)) {
      try {
        await _channel.invokeMethod('performHaptic', {'type': type});
        return;
      } catch (e) {
        debugPrint('CF_HAPTIC: "$type" failed, falling back: $e');
      }
    }
    _fallback(type);
  }

  /// Flutter's own haptic, used when the platform cannot serve [type].
  static void _fallback(String type) {
    switch (type) {
      case 'tick':
        HapticFeedback.selectionClick();
        break;
      case 'click':
        HapticFeedback.lightImpact();
        break;
      case 'lowTick':
        HapticFeedback.selectionClick();
        break;
      case 'heavyClick':
        HapticFeedback.heavyImpact();
        break;
      case 'confirm':
        HapticFeedback.mediumImpact();
        break;
      case 'reject':
        HapticFeedback.heavyImpact();
        break;
    }
  }
}
