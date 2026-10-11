import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mylauncher/core/system_gestures.dart';

/// The optional accessibility service is a security boundary: three global
/// actions, no window content, and no way for an unknown action or a failing
/// channel to reach the platform as anything but a plain "no".

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const MethodChannel channel = MethodChannel('com.launcher.chronofold/apps');
  final List<MethodCall> log = <MethodCall>[];

  TestDefaultBinaryMessenger messenger() =>
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  void installHandler(Future<Object?>? Function(MethodCall call)? handler) {
    messenger().setMockMethodCallHandler(channel, handler);
  }

  setUp(() {
    log.clear();
    SystemGestures.debugUsePlatformChannels = true;
    SystemGestures.debugBackend = null;
  });

  tearDown(() {
    SystemGestures.debugUsePlatformChannels = false;
    SystemGestures.debugBackend = null;
    installHandler(null);
  });

  group('SystemGestures channel mapping', () {
    setUp(() {
      installHandler((call) async {
        log.add(call);
        switch (call.method) {
          case 'isAccessibilityEnabled':
            return true;
          case 'openAccessibilitySettings':
            return true;
          case 'performGlobalAction':
            return true;
        }
        return null;
      });
    });

    test('the three named actions cross the channel under their exact names',
        () async {
      expect(await SystemGestures.notifications(), isTrue);
      expect(await SystemGestures.lockScreen(), isTrue);
      expect(await SystemGestures.recents(), isTrue);

      expect(log.map((call) => call.method), everyElement('performGlobalAction'));
      expect(
        log.map((call) => (call.arguments as Map)['action']).toList(),
        <String>[
          SystemGestures.actionNotifications,
          SystemGestures.actionLockScreen,
          SystemGestures.actionRecents,
        ],
      );
    });

    test('an action outside the whitelist is refused before the channel',
        () async {
      expect(await SystemGestures.perform('unlockScreen'), isFalse);

      expect(
        log,
        isEmpty,
        reason: 'an unknown action must never reach the platform',
      );
    });

    test('isEnabled and openSettings read their own exact methods', () async {
      expect(await SystemGestures.isEnabled(), isTrue);
      expect(await SystemGestures.openSettings(), isTrue);

      expect(
        log.map((call) => call.method).toList(),
        <String>['isAccessibilityEnabled', 'openAccessibilitySettings'],
      );
    });

    test('a disconnected service answers false for every action', () async {
      installHandler((call) async {
        log.add(call);
        return false;
      });

      expect(await SystemGestures.isEnabled(), isFalse);
      expect(await SystemGestures.notifications(), isFalse);
      expect(await SystemGestures.lockScreen(), isFalse);
      expect(await SystemGestures.recents(), isFalse);
    });
  });

  group('SystemGestures failure handling', () {
    test('a channel that throws answers false instead of throwing', () async {
      installHandler((call) async {
        throw PlatformException(code: 'UNAVAILABLE', message: 'no service');
      });

      expect(await SystemGestures.isEnabled(), isFalse);
      expect(await SystemGestures.openSettings(), isFalse);
      expect(await SystemGestures.notifications(), isFalse);
      expect(await SystemGestures.lockScreen(), isFalse);
      expect(await SystemGestures.recents(), isFalse);
    });

    test('a non-platform failure answers false too', () async {
      installHandler((call) async => throw StateError('engine gone'));

      expect(await SystemGestures.isEnabled(), isFalse);
      expect(await SystemGestures.perform(SystemGestures.actionRecents), isFalse);
    });

    test('a host that is not Android answers false without touching the channel',
        () async {
      SystemGestures.debugUsePlatformChannels = false;
      installHandler((call) async {
        log.add(call);
        return true;
      });

      expect(await SystemGestures.isEnabled(), isFalse);
      expect(await SystemGestures.notifications(), isFalse);
      expect(log, isEmpty);
    });
  });

  group('SwipeDownAction', () {
    test('keeps search as the fallback for anything unknown', () {
      expect(SwipeDownAction.normalise(null), SwipeDownAction.search);
      expect(SwipeDownAction.normalise('notifications'),
          SwipeDownAction.notifications);
      expect(SwipeDownAction.normalise('shade'), SwipeDownAction.search);
      expect(SwipeDownAction.normalise(7), SwipeDownAction.search);
    });
  });

  group('DoubleTapTracker', () {
    test('matches a nearby second tap inside the window', () {
      final tracker = DoubleTapTracker();
      tracker.record(const Offset(10, 10));

      expect(tracker.matches(const Offset(20, 20)), isTrue);
      expect(tracker.matches(const Offset(200, 200)), isFalse);
    });

    test('does not match after the window has elapsed', () async {
      final tracker = DoubleTapTracker(window: Duration.zero);
      tracker.record(const Offset(10, 10));
      await Future<void>.delayed(const Duration(milliseconds: 2));

      expect(tracker.matches(const Offset(10, 10)), isFalse);
    });

    test('never matches before a first tap, and clear forgets one', () {
      final tracker = DoubleTapTracker();
      expect(tracker.matches(Offset.zero), isFalse);

      tracker.record(Offset.zero);
      tracker.clear();
      expect(tracker.matches(Offset.zero), isFalse);
    });
  });
}
