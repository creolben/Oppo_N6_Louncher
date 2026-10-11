import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mylauncher/core/launcher_haptics.dart';

/// The named haptics are only as good as their mapping to the platform's types,
/// and a platform that refuses the call must still land on Flutter's own
/// feedback. Both are driven through the bridge's test seam.
void main() {
  const channel = MethodChannel('com.launcher.chronofold/apps');

  tearDown(() {
    LauncherHaptics.debugUsePlatformChannels = false;
  });

  testWidgets('each named haptic sends its platform type', (tester) async {
    final types = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      if (call.method == 'performHaptic') {
        types.add((call.arguments as Map)['type'] as String);
      }
      return true;
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );

    LauncherHaptics.debugUsePlatformChannels = true;
    await LauncherHaptics.tick();
    await LauncherHaptics.click();
    await LauncherHaptics.lowTick();
    await LauncherHaptics.heavyClick();
    await LauncherHaptics.confirm();
    await LauncherHaptics.reject();

    expect(types, ['tick', 'click', 'lowTick', 'heavyClick', 'confirm', 'reject']);
  });

  testWidgets('a refused channel call falls back to HapticFeedback',
      (tester) async {
    final haptics = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      throw PlatformException(code: 'NO_HAPTIC', message: 'refused');
    });
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'HapticFeedback.vibrate') {
          haptics.add(call.arguments as String);
        }
        return null;
      },
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      );
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      );
    });

    LauncherHaptics.debugUsePlatformChannels = true;
    await LauncherHaptics.click();
    await LauncherHaptics.heavyClick();

    expect(haptics, [
      'HapticFeedbackType.lightImpact',
      'HapticFeedbackType.heavyImpact',
    ]);
  });
}
