import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mylauncher/core/foldable_controller.dart';
import 'package:mylauncher/core/launcher_bridge.dart';
import 'package:mylauncher/features/lockscreen/cosmic_lock_screen.dart';
import 'package:mylauncher/main.dart';
import 'package:mylauncher/models/app_entry.dart';

class _LaunchSpy {
  final List<String> lines = [];
  late void Function(String? message, {int? wrapWidth}) _original;

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

  String? get launchedPackage {
    final match = _launchPattern.firstMatch(_lastLaunchLine ?? '');
    return match?.group(2);
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

List<AppEntry> _testApps() => [
      AppEntry(
        packageName: 'com.android.chrome',
        label: 'Chrome',
        category: AppCategory.core,
        accentColor: Colors.blue,
        fallbackIcon: Icons.language_rounded,
      ),
      AppEntry(
        packageName: 'com.oplus.camera',
        label: 'Camera',
        category: AppCategory.core,
        accentColor: Colors.amber,
        fallbackIcon: Icons.camera_alt_rounded,
      ),
    ];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Native Launcher Mode & Keyguard Bypass Tests', () {
    test('LauncherBridge isKeyguardLocked reports boolean', () async {
      final locked = await LauncherBridge.isKeyguardLocked();
      expect(locked, isA<bool>());
    });

    test('LauncherBridge setLockScreenOverlayEnabled executes cleanly', () async {
      final success = await LauncherBridge.setLockScreenOverlayEnabled(false);
      expect(success, isTrue);
    });

    testWidgets(
        'Lockscreen bypasses biometric prompt when device is already unlocked',
        (tester) async {
      final spy = _LaunchSpy();
      var authPrompted = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CosmicLockScreen(
              foldable: FoldableController(),
              apps: _testApps(),
              onUnlock: () {},
              // Explicitly signal the device keyguard was already satisfied:
              isKeyguardLocked: () async => false,
              authenticate: ({String? appName}) async {
                authPrompted = true;
                return true;
              },
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 16));

      await spy.capture(() async {
        // Tap the Camera bubble via semantics
        final node = tester.getSemantics(find.bySemanticsLabel('Camera'));
        tester.binding.pipelineOwner.semanticsOwner!
            .performAction(node.id, SemanticsAction.tap);

        // Advance frames
        for (int i = 0; i < 5; i++) {
          await tester.pump(const Duration(milliseconds: 20));
        }
      });

      // App should launch directly
      expect(spy.launchedPackage, equals('com.oplus.camera'));
      // In-app authentication should have been bypassed because device was unlocked!
      expect(authPrompted, isFalse,
          reason: 'Bypasses redundant auth when keyguard is already unlocked');
    });

    testWidgets('CosmicHeaderHud displays SET DEFAULT button when not default',
        (tester) async {
      var requestedDefault = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CosmicHeaderHud(
              foldable: FoldableController(),
              isDefaultLauncher: false,
              onSetDefaultLauncher: () => requestedDefault = true,
              nativeMode: true,
              onToggleNativeMode: () {},
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('SET DEFAULT'), findsOneWidget);
      await tester.tap(find.text('SET DEFAULT'));
      await tester.pump();

      expect(requestedDefault, isTrue);
    });

    testWidgets('CosmicHeaderHud displays and toggles NATIVE / COSMIC mode',
        (tester) async {
      var toggled = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CosmicHeaderHud(
              foldable: FoldableController(),
              isDefaultLauncher: true,
              nativeMode: true,
              onToggleNativeMode: () => toggled = true,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('NATIVE'), findsOneWidget);
      expect(find.text('SET DEFAULT'), findsNothing);

      await tester.tap(find.text('NATIVE'));
      await tester.pump();

      expect(toggled, isTrue);
    });

    testWidgets('CosmicHeaderHud displays LOCK button in Cosmic mode',
        (tester) async {
      var locked = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CosmicHeaderHud(
              foldable: FoldableController(),
              isDefaultLauncher: true,
              nativeMode: false,
              onLockScreen: () => locked = true,
              onToggleNativeMode: () {},
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('COSMIC'), findsOneWidget);
      expect(find.text('LOCK'), findsOneWidget);

      await tester.tap(find.text('LOCK'));
      await tester.pump();

      expect(locked, isTrue);
    });
  });
}
