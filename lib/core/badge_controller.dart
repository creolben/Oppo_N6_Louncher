import 'dart:async';

import 'package:flutter/foundation.dart';

import 'launcher_bridge.dart';

/// Per-package notification counts for the launcher's badges.
///
/// The counts come from the platform's notification listener as a map of
/// package name to unread count; the platform emits only non-zero packages, and
/// an empty map while its notification access is not granted. This controller
/// owns one subscription to that stream and exposes a synchronous
/// [countFor] the widget tree can ask during build.
///
/// [stream] is injectable so a test can drive badge changes without a platform
/// channel.
class BadgeController extends ChangeNotifier {
  BadgeController({Stream<Map<String, dynamic>>? stream})
      : _stream = stream ?? LauncherBridge.badgesStream {
    _subscription = _stream.listen(
      _onBadges,
      onError: (Object error, StackTrace stack) {
        debugPrint('CF_BADGE: badge stream error: $error');
      },
    );
  }

  final Stream<Map<String, dynamic>> _stream;
  StreamSubscription<Map<String, dynamic>>? _subscription;

  Map<String, int> _counts = const {};

  /// Whether the platform has ever answered. A UI that has never heard from the
  /// platform should leave its own sample counts alone; one that has heard an
  /// empty map must apply that emptiness rather than keep stale numbers.
  bool _hasReceivedEvent = false;

  /// The current counts, keyed by package name.
  Map<String, int> get counts => _counts;

  /// Whether at least one count map has arrived from the platform.
  bool get hasReceivedEvent => _hasReceivedEvent;

  /// The badge count for [packageName], or zero when it has none.
  int countFor(String packageName) => _counts[packageName] ?? 0;

  void _onBadges(Map<String, dynamic> event) {
    final Map<String, int> next = <String, int>{};
    event.forEach((Object? key, Object? value) {
      if (key is! String) return;
      final int? count = value is int ? value : int.tryParse('$value');
      if (count != null && count > 0) next[key] = count;
    });

    final bool changed = !_hasReceivedEvent || !mapEquals(_counts, next);
    _hasReceivedEvent = true;
    if (!changed) return;
    _counts = next;
    notifyListeners();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _subscription = null;
    super.dispose();
  }
}
