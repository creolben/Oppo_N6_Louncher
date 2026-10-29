import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mylauncher/core/launcher_bridge.dart';

/// On a device, a failed or empty PackageManager scan must never turn into the
/// desktop mock inventory: real users would see fake apps with fake badges.
/// The bridge answers null and the caller keeps the inventory it has.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.launcher.chronofold/apps');

  void answerScan(Future<Object?> Function() answer) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'getInstalledApps') return answer();
          return null;
        });
  }

  tearDown(() {
    LauncherBridge.debugUsePlatformChannels = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('a scan error on the platform path yields null, not mocks', () async {
    LauncherBridge.debugUsePlatformChannels = true;
    answerScan(
      () async => throw PlatformException(code: 'SCAN_ERROR'),
    );

    expect(
      await LauncherBridge.getInstalledApps(includeIcons: false),
      isNull,
    );
  });

  test('an empty scan on the platform path yields null, not mocks', () async {
    LauncherBridge.debugUsePlatformChannels = true;
    answerScan(() async => <Object?>[]);

    expect(
      await LauncherBridge.getInstalledApps(includeIcons: false),
      isNull,
    );
  });

  test('a real scan is returned as-is', () async {
    LauncherBridge.debugUsePlatformChannels = true;
    answerScan(
      () async => <Object?>[
        <String, Object?>{
          'packageName': 'com.real.app',
          'label': 'Real',
          'category': -1,
        },
      ],
    );

    final apps = await LauncherBridge.getInstalledApps(includeIcons: false);
    expect(apps!.map((a) => a.packageName), ['com.real.app']);
  });

  test('a non-Android host still gets the simulation inventory', () async {
    final apps = await LauncherBridge.getInstalledApps(includeIcons: false);
    expect(apps, isNotNull);
    expect(apps, isNotEmpty);
  });
}
