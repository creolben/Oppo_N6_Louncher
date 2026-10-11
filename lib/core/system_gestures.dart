import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The persisted answers to "what does a swipe down on the galaxy open?".
abstract final class SwipeDownAction {
  /// Opens app search — the launcher's behaviour before this preference
  /// existed, and the fallback whenever notifications cannot be shown.
  static const String search = 'search';

  /// Opens the notification shade through the optional accessibility service.
  static const String notifications = 'notifications';

  /// Every stored value the launcher understands, in display order.
  static const List<String> values = [search, notifications];

  /// [raw] when it is a known action, otherwise [search].
  ///
  /// A stored value this build does not understand must never take the gesture
  /// away: the launcher falls back to what it has always done.
  static String normalise(Object? raw) =>
      raw == notifications ? notifications : search;
}

/// Timestamp-based double-tap detection.
///
/// Used instead of a `DoubleTapGestureRecognizer` wherever a single tap must
/// still run the moment the finger lifts: that recognizer keeps the gesture
/// arena open after the first tap, so every node tap would wait out the
/// double-tap timeout before it could launch. This tracker decides after the
/// fact, so it adds no delay at all.
class DoubleTapTracker {
  DoubleTapTracker({
    this.window = const Duration(milliseconds: 300),
    this.slop = 48.0,
  });

  /// How long after the first tap a second one still counts.
  final Duration window;

  /// How far the second tap may land from the first, in logical pixels.
  final double slop;

  DateTime? _at;
  Offset? _position;

  /// Records a candidate first tap.
  void record(Offset position) {
    _at = DateTime.now();
    _position = position;
  }

  /// Forgets any candidate first tap.
  void clear() {
    _at = null;
    _position = null;
  }

  /// Whether [position] completes a double tap with the recorded first one.
  bool matches(Offset position) {
    final DateTime? at = _at;
    final Offset? last = _position;
    if (at == null || last == null) return false;
    return DateTime.now().difference(at) <= window &&
        (position - last).distance <= slop;
  }
}

/// The platform surface behind [SystemGestures].
///
/// Production uses the `com.launcher.chronofold/apps` method channel, shared
/// with the rest of the launcher. Tests install a fake through
/// [SystemGestures.debugBackend] so the three actions can be observed on a host
/// with no device.
abstract class SystemGesturesBackend {
  const SystemGesturesBackend();

  /// Whether the optional accessibility service is connected.
  Future<bool> isAccessibilityEnabled();

  /// Opens Android's accessibility settings. The user owns this grant.
  Future<bool> openAccessibilitySettings();

  /// Runs one of the three whitelisted global actions.
  Future<bool> performGlobalAction(String action);
}

/// The real backend: thin method-channel calls, nothing else.
class _ChannelSystemGesturesBackend extends SystemGesturesBackend {
  const _ChannelSystemGesturesBackend();

  @override
  Future<bool> isAccessibilityEnabled() async =>
      await SystemGestures._channel.invokeMethod<bool>(
        'isAccessibilityEnabled',
      ) ??
      false;

  @override
  Future<bool> openAccessibilitySettings() async =>
      await SystemGestures._channel.invokeMethod<bool>(
        'openAccessibilitySettings',
      ) ??
      false;

  @override
  Future<bool> performGlobalAction(String action) async =>
      await SystemGestures._channel.invokeMethod<bool>('performGlobalAction', {
        'action': action,
      }) ??
      false;
}

/// The launcher's bridge to its optional accessibility service.
///
/// The service is off by default and is limited to exactly three global
/// actions: open the notification shade, lock the screen and show recent apps.
/// It never reads window content, so nothing here can query or observe the
/// screen. Every method answers `false` — and never throws — when the host is
/// not Android, when the service is not enabled, or when the platform refuses.
///
/// Shaped after [LauncherBridge]: a static facade over one method channel, a
/// `debugUsePlatformChannels` seam for the real channel path on a test host, and
/// an injectable backend for widget tests.
class SystemGestures {
  SystemGestures._();

  static const MethodChannel _channel = MethodChannel(
    'com.launcher.chronofold/apps',
  );

  /// The exact action names the native service accepts. These are the only
  /// strings that ever cross the channel.
  static const String actionNotifications = 'notifications';
  static const String actionLockScreen = 'lockScreen';
  static const String actionRecents = 'recents';

  /// The whitelist, in the order the native service maps it.
  static const List<String> globalActions = [
    actionNotifications,
    actionLockScreen,
    actionRecents,
  ];

  /// Test seam: on a host that is not Android (the unit-test binary on a
  /// desktop) the bridge normally never touches the platform channel. A test
  /// that asserts the exact channel payload or its failure handling sets this
  /// so the same code path runs; production never does.
  @visibleForTesting
  static bool debugUsePlatformChannels = false;

  /// Test seam: a fake backend replacing the platform channel entirely.
  ///
  /// Preferred by widget tests, which would otherwise have to mock a channel
  /// they cannot observe the arguments of as easily. Null in production.
  @visibleForTesting
  static SystemGesturesBackend? debugBackend;

  /// Whether the platform channel is the way to reach the service.
  static bool get _usePlatformChannels =>
      !kIsWeb && (Platform.isAndroid || debugUsePlatformChannels);

  static SystemGesturesBackend get _backend =>
      debugBackend ?? const _ChannelSystemGesturesBackend();

  /// Whether the optional accessibility service is connected.
  ///
  /// This is the gate for every gesture that needs the service. A test host, a
  /// disabled service and a native failure all answer false, so nothing that
  /// depends on it can fire by accident.
  static Future<bool> isEnabled() async {
    if (debugBackend == null && !_usePlatformChannels) return false;
    try {
      return await _backend.isAccessibilityEnabled();
    } catch (e) {
      debugPrint('CF_A11Y: checking the accessibility service failed: $e');
      return false;
    }
  }

  /// Opens Android's accessibility settings so the user can enable the service.
  ///
  /// The platform owns this grant and only the user can give it, so this is a
  /// handoff, not a request dialog. Returns whether the settings screen could be
  /// opened.
  static Future<bool> openSettings() async {
    if (debugBackend == null && !_usePlatformChannels) return false;
    try {
      return await _backend.openAccessibilitySettings();
    } catch (e) {
      debugPrint('CF_A11Y: opening accessibility settings failed: $e');
      return false;
    }
  }

  /// Opens the notification shade.
  static Future<bool> notifications() => perform(actionNotifications);

  /// Locks the screen.
  ///
  /// Reports false where the platform has no such global action (below API 28)
  /// or where the service is not connected.
  static Future<bool> lockScreen() => perform(actionLockScreen);

  /// Shows the recent-apps overview.
  static Future<bool> recents() => perform(actionRecents);

  /// Runs one of [globalActions].
  ///
  /// Anything else is refused here as well as natively, so an unknown name can
  /// never reach the platform even if a future caller passes one. Returns false
  /// when the service is not connected or the platform declines.
  static Future<bool> perform(String action) async {
    if (!globalActions.contains(action)) return false;
    if (debugBackend == null && !_usePlatformChannels) return false;
    try {
      return await _backend.performGlobalAction(action);
    } catch (e) {
      debugPrint('CF_A11Y: global action "$action" failed: $e');
      return false;
    }
  }
}
