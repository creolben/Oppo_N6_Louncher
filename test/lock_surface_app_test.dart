import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mylauncher/core/launcher_bridge.dart';
import 'package:mylauncher/features/lockscreen/cosmic_lock_screen.dart';
import 'package:mylauncher/lock_main.dart';
import 'package:mylauncher/models/app_entry.dart';

/// The lock activity's Dart surface.
///
/// `LockSurfaceApp` exists only to wire the cosmic panel's injectable seams for
/// a surface that is not the launcher: the app inventory, the keyguard
/// question, and what "unlock" means (finish the lock task, revealing the app
/// underneath). These tests pin the two decisions the panel must not make for
/// itself — that it reconciles on mount, and that a reconciled-away lock
/// finishes the activity through the injected finisher rather than a channel.

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
  for (int i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

void main() {
  // The request-frame listener is process-global state on the bridge; a test
  // that leaves it set would hand the next one's frames to a disposed surface.
  tearDown(() => LauncherBridge.setRequestFrameListener(null));

  testWidgets('hosts the cosmic panel in reconcile mode with the loaded apps', (
    tester,
  ) async {
    await tester.pumpWidget(
      LockSurfaceApp(
        loadApps: () async => _apps(),
        isKeyguardLocked: () async => true,
        onFinish: () async => true,
      ),
    );
    await tester.pump(const Duration(milliseconds: 16));
    await _settle(tester);

    final panel = tester.widget<CosmicLockScreen>(
      find.byType(CosmicLockScreen),
    );
    // A screen-off lock, not a user-raised privacy panel: it must clear
    // itself if the platform already satisfied the keyguard.
    expect(panel.reconcileOnMount, isTrue);
    // The injected inventory reaches the panel instead of a platform channel.
    expect(
      panel.apps.map((app) => app.packageName),
      contains('com.test.camera'),
    );
  });

  testWidgets('a keyguard already unlocked on mount finishes the lock', (
    tester,
  ) async {
    var finished = 0;
    await tester.pumpWidget(
      LockSurfaceApp(
        loadApps: () async => _apps(),
        isKeyguardLocked: () async => false,
        onFinish: () async {
          finished++;
          return true;
        },
      ),
    );
    await tester.pump(const Duration(milliseconds: 16));
    await _settle(tester);

    // The reconcile path's `onUnlock` is the finisher, once.
    expect(finished, equals(1));
  });

  testWidgets('two unlock signals finish the lock exactly once', (tester) async {
    var finished = 0;
    await tester.pumpWidget(
      LockSurfaceApp(
        loadApps: () async => _apps(),
        isKeyguardLocked: () async => true,
        onFinish: () async {
          finished++;
          return true;
        },
      ),
    );
    await tester.pump(const Duration(milliseconds: 16));
    await _settle(tester);

    // The panel can be cleared by more than one path in the same unlock (the
    // mount reconcile, a swipe, a shortcut). Each used to reach the finisher;
    // the surface must collapse them to one request.
    final panel = tester.widget<CosmicLockScreen>(find.byType(CosmicLockScreen));
    panel.onUnlock();
    panel.onUnlock();
    await tester.pump();

    expect(finished, equals(1));
  });

  testWidgets('a native requestFrame forces a frame from the lock surface', (
    tester,
  ) async {
    var frames = 0;
    await tester.pumpWidget(
      LockSurfaceApp(
        loadApps: () async => _apps(),
        isKeyguardLocked: () async => true,
        onFinish: () async => true,
        requestFrame: () => frames++,
      ),
    );
    await tester.pump(const Duration(milliseconds: 16));
    await _settle(tester);
    final int before = frames;

    // The native lock activity asks on every wake; the surface answers with a
    // forced frame so Android can finally draw the DRAW_PENDING window.
    LauncherBridge.dispatchRequestFrameForTesting();
    await tester.pump();

    expect(frames, equals(before + 1));
  });

  testWidgets('a resumed lifecycle change forces a frame', (tester) async {
    var frames = 0;
    await tester.pumpWidget(
      LockSurfaceApp(
        loadApps: () async => _apps(),
        isKeyguardLocked: () async => true,
        onFinish: () async => true,
        requestFrame: () => frames++,
      ),
    );
    await tester.pump(const Duration(milliseconds: 16));
    await _settle(tester);
    final int before = frames;

    // Coming back from a screen-off, the engine resumed but may still hold the
    // first-draw gate closed; the surface must schedule a frame on resume.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    expect(frames, equals(before + 1));
  });
}
