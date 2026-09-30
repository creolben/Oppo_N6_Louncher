import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mylauncher/core/foldable_controller.dart';
import 'package:mylauncher/features/lockscreen/cosmic_lock_screen.dart';
import 'package:mylauncher/models/app_entry.dart';

/// The F1 self-heal: a panel mounted for a lock must not stay up over an
/// unlocked device just because one broadcast was dropped.
///
/// The native side now records the locked state at process start (cold
/// boot), so the first `USER_PRESENT` is no longer gated away — but a single
/// dropped broadcast must not be able to strand the panel again. The
/// belt-and-braces is Dart-side: when the panel's lifecycle returns to
/// `resumed` — the moment the launcher regains the screen after the
/// platform unlock — a panel that stands for a keyguard
/// (`reconcileOnMount: true`) asks the keyguard again and clears itself if
/// the lock is gone. A panel mounted by the LOCK buttons
/// (`reconcileOnMount: false`) stands for the user's wish, not for a
/// keyguard state, and must survive the same transition on an unlocked
/// device.

List<AppEntry> _apps() => [
  AppEntry(
    packageName: 'com.test.camera',
    label: 'Camera',
    category: AppCategory.core,
    accentColor: Colors.amber,
    fallbackIcon: Icons.camera_alt_rounded,
  ),
];

/// Drives the resumed transition the way the platform would: the binding
/// starts resumed, so the transition passes through `inactive` first to
/// make a genuine return.
Future<void> _regainScreen(WidgetTester tester) async {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  // Let the keyguard seam's answer land and the panel act on it.
  await tester.pump(const Duration(milliseconds: 16));
}

void main() {
  group('Lifecycle self-heal on resumed', () {
    testWidgets(
      'a reconcile-on-mount panel clears itself when the keyguard unlocked while it was away',
      (tester) async {
        var keyguardLocked = true;
        var unlocked = false;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: CosmicLockScreen(
                foldable: FoldableController(),
                apps: _apps(),
                onUnlock: () => unlocked = true,
                reconcileOnMount: true,
                isKeyguardLocked: () async => keyguardLocked,
              ),
            ),
          ),
        );

        // The mount-time reconciliation saw a locked keyguard and stayed.
        await tester.pump(const Duration(milliseconds: 16));
        expect(unlocked, isFalse);

        // The platform authenticates while the launcher is paused; whether
        // the unlock broadcast arrives is exactly what this self-heal must
        // not depend on.
        keyguardLocked = false;

        await _regainScreen(tester);

        expect(unlocked, isTrue);
      },
    );

    testWidgets(
      'a panel mounted by the LOCK buttons survives the resumed transition unlocked',
      (tester) async {
        var keyguardLocked = false;
        var unlocked = false;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: CosmicLockScreen(
                foldable: FoldableController(),
                apps: _apps(),
                onUnlock: () => unlocked = true,
                reconcileOnMount: false,
                isKeyguardLocked: () async => keyguardLocked,
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 16));

        // The device is unlocked and the panel knows it — the user raised
        // it, so that is not grounds to clear it.
        await _regainScreen(tester);

        expect(unlocked, isFalse);
        expect(find.byType(CosmicLockScreen), findsOneWidget);
      },
    );
  });
}