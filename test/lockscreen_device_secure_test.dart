import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mylauncher/core/foldable_controller.dart';
import 'package:mylauncher/core/launcher_bridge.dart';
import 'package:mylauncher/features/lockscreen/cosmic_lock_screen.dart';
import 'package:mylauncher/features/lockscreen/fingerprint_prompt.dart';
import 'package:mylauncher/models/app_entry.dart';

/// F5: a device with no secure lock.
///
/// The product decision is settled — full lock ownership: the panel mounts
/// on such a device too, and that is intended. What must change there is
/// honesty: with no credential no fingerprint can ever be enrolled, so the
/// panel must not pretend there is a finger to read — no reader armed, no
/// locked badge, no authentication ask. On a secure device nothing changes.

List<AppEntry> _apps() => [
  AppEntry(
    packageName: 'com.test.camera',
    activityName: 'com.test.camera.Camera',
    label: 'Camera',
    category: AppCategory.core,
    accentColor: Colors.amber,
    fallbackIcon: Icons.camera_alt_rounded,
  ),
];

/// Advances far enough for the panel's platform round trips to land.
Future<void> _settle(WidgetTester tester) async {
  for (int i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

/// Records what [LauncherBridge.launchApp] was asked to open. On a
/// non-Android host the bridge short-circuits to a debugPrint, so the
/// printed line is the observable record of the launch target.
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

  List<String> get launchedPackages => [
    for (final line in lines)
      if (line.startsWith('Simulating launching app:'))
        RegExp(r'\(([^()]*)\)$').firstMatch(line)?.group(1) ?? '',
  ];
}

void main() {
  group('Device without a secure lock', () {
    testWidgets('mounts the panel, arms no reader, claims no lock', (
      tester,
    ) async {
      var capabilityProbes = 0;
      var scanStarts = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CosmicLockScreen(
              foldable: FoldableController(),
              apps: _apps(),
              onUnlock: () {},
              isDeviceSecure: () async => false,
              // A reader that is, on paper, perfectly capable — so the only
              // thing that can stop the panel arming it is the secure
              // answer under test.
              fingerprintCapability: () async {
                capabilityProbes++;
                return const FingerprintCapability(
                  hardware: true,
                  enrolled: true,
                );
              },
              startFingerprintScan: () async {
                scanStarts++;
                return true;
              },
              fingerprintEvents: () => const Stream.empty(),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 16));
      await _settle(tester);

      // The arm was skipped entirely — not even the capability was probed
      // for it — and no scan session was started: with no credential, no
      // fingerprint can be enrolled, so arming could only ask a question
      // nothing on this device can answer.
      expect(capabilityProbes, equals(0));
      expect(scanStarts, equals(0));
      // Full lock ownership: the panel is up...
      expect(find.byType(CosmicLockScreen), findsOneWidget);
      // ...but it does not claim a lock that does not exist...
      expect(find.text('Locked'), findsNothing);
      // ...and its unlock affordance is the plain dismiss it always was.
      expect(find.text('Swipe up to open'), findsOneWidget);
    });

    testWidgets('a shortcut tap resolves through the platform with no ask', (
      tester,
    ) async {
      var scanStarts = 0;
      final spy = _LaunchSpy();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CosmicLockScreen(
              foldable: FoldableController(),
              apps: _apps(),
              onUnlock: () {},
              isDeviceSecure: () async => false,
              fingerprintCapability: () async =>
                  const FingerprintCapability(
                    hardware: true,
                    enrolled: true,
                  ),
              startFingerprintScan: () async {
                scanStarts++;
                return true;
              },
              fingerprintEvents: () => const Stream.empty(),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 16));
      await _settle(tester);

      await spy.capture(() async {
        // The camera quick shortcut is the remaining app target; a bubble is
        // decoration and launches nothing. Tapping the shortcut asks to open
        // the camera.
        await tester.tap(find.byIcon(Icons.camera_alt_rounded));
        for (int i = 0; i < 10; i++) {
          await tester.pump(const Duration(milliseconds: 40));
        }
      });

      // No card — nothing on this device could answer it — and no scan was
      // started for the request either.
      expect(find.byType(FingerprintAuthPrompt), findsNothing);
      expect(scanStarts, equals(0));
      expect(find.text('AUTH REQUIRED TO LAUNCH CAMERA'), findsNothing);
      // The request still resolved: the launch went through the platform
      // bridge, which on such a device dismisses silently — no credential
      // exists to ask for.
      expect(spy.launchedPackages, equals(['com.test.camera']));
    });
  });

  group('Device with a secure lock', () {
    testWidgets('arms the reader and badges the panel as before', (
      tester,
    ) async {
      // No `isDeviceSecure` seam: the production default. On the test host
      // the bridge answers secure (it simulates a locked keyguard, which
      // implies a credential), so this is also the regression pin that the
      // secure path is untouched: the mount arm still happens and the locked
      // badge still draws.
      var scanStarts = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CosmicLockScreen(
              foldable: FoldableController(),
              apps: _apps(),
              onUnlock: () {},
              fingerprintCapability: () async =>
                  const FingerprintCapability(
                    hardware: true,
                    enrolled: true,
                  ),
              startFingerprintScan: () async {
                scanStarts++;
                return true;
              },
              fingerprintEvents: () => const Stream.empty(),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 16));
      await _settle(tester);

      // Exactly the one mount-time arm, and the badge with it.
      expect(scanStarts, equals(1));
      expect(find.text('Locked'), findsOneWidget);
    });
  });
}