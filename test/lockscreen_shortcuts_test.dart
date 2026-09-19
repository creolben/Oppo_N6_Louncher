import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mylauncher/core/foldable_controller.dart';
import 'package:mylauncher/features/lockscreen/cosmic_lock_screen.dart';
import 'package:mylauncher/features/lockscreen/quick_shortcut_resolver.dart';
import 'package:mylauncher/models/app_entry.dart';

/// Captures what [LauncherBridge.launchApp] was asked to open.
///
/// On a non-Android test host the bridge short-circuits to a debugPrint
/// instead of a platform call, so the printed line is the observable record of
/// the launch target.
class _LaunchSpy {
  final List<String> lines = [];
  late void Function(String? message, {int? wrapWidth}) _original;

  /// Runs [body] with [debugPrint] captured.
  ///
  /// The restore has to happen inside the test body, not in `tearDown`:
  /// Flutter's binding asserts that no foundation debug variable is still
  /// changed before `tearDown` gets a chance to run.
  Future<void> capture(Future<void> Function() body) async {
    _original = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) lines.add(message);
    };
    try {
      await body();
    } finally {
      debugPrint = _original;
    }
  }

  /// The `(packageName)` of the last app handed to the launcher, if any.
  String? get launchedPackage {
    final match = _launchPattern.firstMatch(_lastLaunchLine ?? '');
    return match?.group(2);
  }

  /// The label of the last app handed to the launcher, if any.
  String? get launchedLabel {
    final match = _launchPattern.firstMatch(_lastLaunchLine ?? '');
    return match?.group(1);
  }

  String? get _lastLaunchLine {
    for (final line in lines.reversed) {
      if (line.startsWith('Simulating launching app:')) return line;
    }
    return null;
  }

  static final RegExp _launchPattern =
      RegExp(r'^Simulating launching app: (.*) \(([^()]*)\)$');
}

/// The launchable phone/camera entries the Fold N6 (CPH2765, ColorOS 16)
/// actually reports to `getInstalledApps`.
///
/// Two facts make this fixture the whole point of the repro:
///  * `com.android.phone` is installed but exposes **no** LAUNCHER activity,
///    so it is absent here — and `getLaunchIntentForPackage` returns null for
///    it. The dialer is `com.android.contacts/.DialtactsActivityAlias`.
///  * `com.android.camera` is not installed at all; the camera is
///    `com.oplus.camera/.Camera`.
///
/// `com.android.contacts` appears twice, as Phone and as Contacts, which is why
/// matching on package name alone cannot pick the dialer.
List<AppEntry> _deviceApps() => [
      // Sorted by ResolveInfo order, so an unrelated app legitimately leads.
      AppEntry(
        packageName: 'com.android.chrome',
        activityName: 'com.google.android.apps.chrome.Main',
        label: 'Chrome',
        category: AppCategory.core,
        fallbackIcon: Icons.language_rounded,
      ),
      AppEntry(
        packageName: 'com.android.contacts',
        activityName: 'com.android.contacts.DialtactsActivityAlias',
        label: 'Phone',
        category: AppCategory.core,
        fallbackIcon: Icons.phone_in_talk_rounded,
      ),
      AppEntry(
        packageName: 'com.android.contacts',
        activityName: 'com.android.contacts.PeopleActivityAlias',
        label: 'Contacts',
        category: AppCategory.core,
        fallbackIcon: Icons.contacts_rounded,
      ),
      AppEntry(
        packageName: 'com.oplus.camera',
        activityName: 'com.oplus.camera.Camera',
        label: 'Camera',
        category: AppCategory.core,
        fallbackIcon: Icons.camera_alt_rounded,
      ),
      AppEntry(
        packageName: 'com.oplus.phonemanager',
        activityName: 'com.oplus.phonemanager.FakeActivity',
        label: 'Phone Manager',
        category: AppCategory.tools,
        fallbackIcon: Icons.tune_rounded,
      ),
      AppEntry(
        packageName: 'com.paybyphone',
        activityName: 'com.paybyphone.MainActivity',
        label: 'PayByPhone',
        category: AppCategory.tools,
        fallbackIcon: Icons.local_parking_rounded,
      ),
    ];

Future<void> _pumpLockScreen(
  WidgetTester tester,
  List<AppEntry> apps, {
  Future<bool> Function({String? appName})? authenticate,
  VoidCallback? onUnlock,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: CosmicLockScreen(
          foldable: FoldableController(),
          apps: apps,
          onUnlock: onUnlock ?? () {},
          authenticate: authenticate,
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 16));
}

/// Delivers a native call into the app, exactly as the platform's
/// `onUserPresent` broadcast does.
Future<void> _deliverPlatformCall(String method) async {
  await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage(
    'com.launcher.chronofold/apps',
    const StandardMethodCodec().encodeMethodCall(MethodCall(method)),
    (_) {},
  );
}

/// Advances past the 360 ms unlock slide so the queued launch actually fires.
Future<void> _settleUnlock(WidgetTester tester) async {
  for (int i = 0; i < 16; i++) {
    await tester.pump(const Duration(milliseconds: 40));
  }
}

void main() {
  group('QuickShortcutResolver', () {
    AppEntry app(String pkg, String? activity, String label) => AppEntry(
          packageName: pkg,
          activityName: activity,
          label: label,
        );

    test('picks the dialer over the contacts alias in the same package', () {
      final apps = [
        app('com.android.contacts',
            'com.android.contacts.PeopleActivityAlias', 'Contacts'),
        app('com.android.contacts',
            'com.android.contacts.DialtactsActivityAlias', 'Phone'),
      ];

      final target = QuickShortcutResolver.phone(apps);

      expect(target?.activityName,
          equals('com.android.contacts.DialtactsActivityAlias'));
    });

    test('ignores packages that merely contain a phone keyword', () {
      final apps = [
        app('com.oplus.phonemanager', 'com.oplus.phonemanager.FakeActivity',
            'Phone Manager'),
        app('com.paybyphone', 'com.paybyphone.MainActivity', 'PayByPhone'),
        app('com.coloros.backuprestore',
            'com.oplus.phoneclone.PhoneCloneMainActivity', 'Phone Clone'),
      ];

      expect(QuickShortcutResolver.phone(apps), isNull);
    });

    test('finds the dialer by package when the activity name is unhelpful', () {
      final apps = [
        app('com.oplus.phonemanager', 'com.oplus.phonemanager.FakeActivity',
            'Phone Manager'),
        app('com.google.android.dialer',
            'com.android.dialer.main.impl.MainActivity', 'Phone'),
      ];

      expect(QuickShortcutResolver.phone(apps)?.packageName,
          equals('com.google.android.dialer'));
    });

    test('picks the camera app and not camera extensions', () {
      final apps = [
        app('com.android.cameraextensions',
            'com.android.cameraextensions.CameraExtensionsActivity',
            'Camera Extensions'),
        app('com.oplus.camera', 'com.oplus.camera.Camera', 'Camera'),
      ];

      expect(QuickShortcutResolver.camera(apps)?.packageName,
          equals('com.oplus.camera'));
    });

    test('does not offer a gallery or photo editor as the camera', () {
      final apps = [
        app('com.google.android.apps.photos',
            'com.google.android.apps.photos.home.HomeActivity', 'Photos'),
        app('com.coloros.gallery3d', 'com.coloros.gallery3d.app.Gallery',
            'Gallery'),
      ];

      expect(QuickShortcutResolver.camera(apps), isNull);
    });

    test('returns null rather than a wrong app when nothing matches', () {
      final apps = [
        app('com.android.chrome', 'com.google.android.apps.chrome.Main',
            'Chrome'),
        app('com.spotify.music', 'com.spotify.music.MainActivity', 'Spotify'),
      ];

      expect(QuickShortcutResolver.phone(apps), isNull);
      expect(QuickShortcutResolver.camera(apps), isNull);
    });

    test('returns null for an empty app list', () {
      expect(QuickShortcutResolver.phone(const []), isNull);
      expect(QuickShortcutResolver.camera(const []), isNull);
    });
  });

  group('Lock screen quick shortcuts', () {
    late _LaunchSpy spy;

    setUp(() => spy = _LaunchSpy());

    testWidgets('Phone shortcut opens the dialer on a real device app list',
        (tester) async {
      await _pumpLockScreen(tester, _deviceApps());

      await spy.capture(() async {
        await tester.tap(find.byIcon(Icons.phone_rounded));
        await _settleUnlock(tester);
      });

      // The dialer is com.android.contacts/.DialtactsActivityAlias, labelled
      // "Phone". Opening Chrome, Contacts or Phone Manager is the bug.
      expect(spy.launchedPackage, equals('com.android.contacts'));
      expect(spy.launchedLabel, equals('Phone'));
    });

    testWidgets('Camera shortcut opens the camera on a real device app list',
        (tester) async {
      await _pumpLockScreen(tester, _deviceApps());

      await spy.capture(() async {
        await tester.tap(find.byIcon(Icons.camera_alt_rounded));
        await _settleUnlock(tester);
      });

      expect(spy.launchedPackage, equals('com.oplus.camera'));
      expect(spy.launchedLabel, equals('Camera'));
    });

    testWidgets('A shortcut never falls back to an unrelated app',
        (tester) async {
      await _pumpLockScreen(tester, _deviceApps());

      await spy.capture(() async {
        await tester.tap(find.byIcon(Icons.camera_alt_rounded));
        await _settleUnlock(tester);
      });

      // `apps.first` is the exact app the old `orElse:` fallback launched.
      expect(spy.launchedLabel, isNot(equals('Chrome')));
    });

    testWidgets(
        'Phone still opens when the platform keyguard wins the auth race',
        (tester) async {
      // The reader is the side power button, so the platform keyguard answers
      // the touch and reports userPresent while this overlay's own prompt is
      // still open. Hold the prompt open to reproduce that ordering.
      final prompt = Completer<bool>();
      await _pumpLockScreen(
        tester,
        _deviceApps(),
        authenticate: ({String? appName}) => prompt.future,
      );

      await spy.capture(() async {
        await tester.tap(find.byIcon(Icons.phone_rounded));
        await tester.pump();

        // The keyguard authenticates and the platform unlocks the device.
        await _deliverPlatformCall('userPresent');
        for (int i = 0; i < 4; i++) {
          await tester.pump(const Duration(milliseconds: 40));
        }

        // The overlay's own prompt is then cancelled, as it is on device.
        prompt.complete(false);
        await _settleUnlock(tester);
      });

      expect(spy.launchedPackage, equals('com.android.contacts'));
      expect(spy.launchedLabel, equals('Phone'));
    });

    testWidgets(
        'Camera still opens when the platform keyguard wins the auth race',
        (tester) async {
      final prompt = Completer<bool>();
      await _pumpLockScreen(
        tester,
        _deviceApps(),
        authenticate: ({String? appName}) => prompt.future,
      );

      await spy.capture(() async {
        await tester.tap(find.byIcon(Icons.camera_alt_rounded));
        await tester.pump();

        await _deliverPlatformCall('userPresent');
        for (int i = 0; i < 4; i++) {
          await tester.pump(const Duration(milliseconds: 40));
        }

        prompt.complete(false);
        await _settleUnlock(tester);
      });

      expect(spy.launchedPackage, equals('com.oplus.camera'));
    });

    testWidgets('A swipe up launches nothing', (tester) async {
      await _pumpLockScreen(tester, _deviceApps());

      await spy.capture(() async {
        await tester.dragFrom(const Offset(400, 550), const Offset(0, -300));
        await _settleUnlock(tester);
      });

      expect(spy.launchedPackage, isNull);
    });

    testWidgets(
        'Opening an app from the lock screen keeps the panel up, so closing '
        'the app returns to the lock screen', (tester) async {
      // Closing the dialer must land back on this lock screen. Clearing the
      // panel on launch drops the user behind it instead — onto the launcher,
      // or onto whatever the system was covering.
      var unlocked = false;
      await _pumpLockScreen(
        tester,
        _deviceApps(),
        onUnlock: () => unlocked = true,
      );

      await spy.capture(() async {
        await tester.tap(find.byIcon(Icons.phone_rounded));
        await _settleUnlock(tester);
      });

      expect(spy.launchedPackage, equals('com.android.contacts'));
      expect(
        unlocked,
        isFalse,
        reason: 'the panel was cleared, so closing the dialer would not '
            'return to the lock screen',
      );
    });

    testWidgets('The panel is still live after coming back from a launched app',
        (tester) async {
      var unlocked = false;
      await _pumpLockScreen(
        tester,
        _deviceApps(),
        onUnlock: () => unlocked = true,
      );

      await spy.capture(() async {
        await tester.tap(find.byIcon(Icons.phone_rounded));
        await _settleUnlock(tester);

        // The app is closed and the launcher comes back to the front.
        tester.binding
            .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        await tester.pump();

        // Still locked, so it must still accept an unlock.
        expect(unlocked, isFalse);
        await tester.dragFrom(const Offset(400, 550), const Offset(0, -300));
        await _settleUnlock(tester);
      });

      expect(unlocked, isTrue);
    });
  });
}
