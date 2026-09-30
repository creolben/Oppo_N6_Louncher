import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mylauncher/core/foldable_controller.dart';
import 'package:mylauncher/features/lockscreen/bouncing_physics_engine.dart';
import 'package:mylauncher/features/lockscreen/cosmic_lock_screen.dart';
import 'package:mylauncher/features/lockscreen/now_playing_card.dart';
import 'package:mylauncher/models/app_entry.dart';
import 'package:mylauncher/models/now_playing.dart';

/// The bubble band must follow the measured HUD even when the app list arrives
/// after the panel has already measured it.
///
/// The real mount order is `lock_main.dart`'s: the panel starts with
/// `apps: const []`, the post-frame measurement pins the band, and the apps
/// land on a later build. If that second `initializeBubbles` falls back to the
/// provisional `size.height * 0.28` padding, the first bubble row is painted
/// under the now-playing card. This test reproduces that order at the cover
/// display's size and refuses it.

List<AppEntry> _apps() {
  const List<String> labels = ['Alpha', 'Beta', 'Gamma', 'Delta'];
  return [
    for (int i = 0; i < labels.length; i++)
      AppEntry(
        packageName: 'com.test.ambient$i',
        label: labels[i],
        category: AppCategory.tools,
        accentColor: Colors.primaries[i % Colors.primaries.length],
        fallbackIcon: Icons.circle,
        // The field only draws apps with real icon bytes, and none of these
        // resolve to the phone/camera corner shortcuts.
        iconBytes: Uint8List.fromList(const [1, 2, 3, 4]),
      ),
  ];
}

NowPlaying _media() => NowPlaying(
  packageName: 'com.test.music',
  appLabel: 'Music',
  title: 'A Long Track Title That Wraps Across Two Lines',
  artist: 'Artist One',
  durationMs: 180000,
  positionMs: 30000,
  state: 'playing',
  canPrev: true,
  canNext: true,
  canPlayPause: true,
);

/// Pumps the panel in place. Reusing the same tree shape (and position) keeps
/// the [CosmicLockScreen]'s State across calls, which is what lets the app list
/// arrive on a later build without remounting the panel.
Future<void> _pump(
  WidgetTester tester, {
  required List<AppEntry> apps,
  required Stream<NowPlaying?> media,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: CosmicLockScreen(
          foldable: FoldableController(),
          apps: apps,
          onUnlock: () {},
          isDeviceSecure: () async => true,
          fingerprintEvents: () => const Stream.empty(),
          startFingerprintScan: () async => false,
          isKeyguardLocked: () async => true,
          dismissKeyguard: () async => false,
          battery: () async => null,
          mediaStream: media,
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 16));
}

void main() {
  testWidgets('re-measures the band when the app list arrives late', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(351, 805);
    addTearDown(tester.view.reset);

    final controller = StreamController<NowPlaying?>.broadcast();
    addTearDown(controller.close);

    // Frame 1: the panel mounts with no apps and measures the real band.
    await _pump(tester, apps: const [], media: controller.stream);
    controller.add(_media());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(NowPlayingCard), findsOneWidget);

    // Apps arrive on a later build; the State is kept.
    await _pump(tester, apps: _apps(), media: controller.stream);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();

    final State<CosmicLockScreen> panel = tester
        .state<State<CosmicLockScreen>>(find.byType(CosmicLockScreen));
    final BouncingPhysicsEngine physics = panel.physicsForTesting;
    expect(physics.bubbles, isNotEmpty);

    final Rect card = tester.getRect(find.byType(NowPlayingCard));
    final double hintTop = tester.getRect(find.text('Swipe up to unlock')).top;

    // The engine's band is the single source of truth; a stale widget-side
    // cache would leave it on the provisional top instead.
    expect(
      physics.bounds?.top,
      closeTo(card.bottom + 24.0, 1.0),
      reason: 'the band must be the measured gap below the card',
    );

    for (final bubble in physics.bubbles) {
      final double painted = BouncingPhysicsEngine.paintedRadius(bubble.radius);
      expect(
        bubble.position.dy - painted,
        greaterThanOrEqualTo(card.bottom + 16.0),
        reason: '${bubble.app.label} paints under the now-playing card',
      );
      expect(
        bubble.position.dy + painted,
        lessThanOrEqualTo(hintTop - 16.0),
        reason: '${bubble.app.label} paints over the unlock hint',
      );
    }

    // Dispose the panel so its ticker and periodic timer do not leak.
    await tester.pumpWidget(const SizedBox());
  });
}
