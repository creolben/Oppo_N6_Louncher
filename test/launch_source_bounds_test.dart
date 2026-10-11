import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mylauncher/core/launcher_bridge.dart';
import 'package:mylauncher/models/app_entry.dart';

/// `launchApp` is the one bridge call whose channel payload carries a tap's
/// geometry. These tests drive the real channel path (via the bridge's test
/// seam) and assert the logical-pixel rect becomes physical pixels — and that a
/// launch with no bounds sends none at all, which is the lock-screen path.
void main() {
  const channel = MethodChannel('com.launcher.chronofold/apps');

  final app = AppEntry(
    packageName: 'com.test.messages',
    activityName: 'com.test.messages.Main',
    label: 'Messages',
  );

  tearDown(() {
    LauncherBridge.debugUsePlatformChannels = false;
  });

  testWidgets('launchApp converts a logical sourceBounds to physical pixels',
      (tester) async {
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.resetDevicePixelRatio);

    Map<Object?, Object?>? arguments;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      if (call.method == 'launchApp') {
        arguments = call.arguments as Map<Object?, Object?>;
      }
      return true;
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );

    LauncherBridge.debugUsePlatformChannels = true;
    final launched = await LauncherBridge.launchApp(
      app,
      sourceBounds: const Rect.fromLTWH(10, 20, 30, 40),
    );

    expect(launched, isTrue);
    expect(arguments!['packageName'], 'com.test.messages');
    final bounds = arguments!['sourceBounds'] as Map<Object?, Object?>;
    expect(bounds['left'], 20);
    expect(bounds['top'], 40);
    expect(bounds['right'], 80);
    expect(bounds['bottom'], 120);
  });

  testWidgets('launchApp omits sourceBounds when none was given',
      (tester) async {
    Map<Object?, Object?>? arguments;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      if (call.method == 'launchApp') {
        arguments = call.arguments as Map<Object?, Object?>;
      }
      return true;
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );

    LauncherBridge.debugUsePlatformChannels = true;
    await LauncherBridge.launchApp(app);

    expect(arguments!.containsKey('sourceBounds'), isFalse);
    expect(arguments!['packageName'], 'com.test.messages');
  });
}
