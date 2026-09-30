import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mylauncher/core/foldable_controller.dart';
import 'package:mylauncher/features/lockscreen/cosmic_lock_screen.dart';
import 'package:mylauncher/features/lockscreen/now_playing_card.dart';
import 'package:mylauncher/models/app_entry.dart';
import 'package:mylauncher/models/now_playing.dart';

/// The lock screen's now-playing card, driven through the injected media
/// stream. No real platform channel is touched: every other seam the panel
/// reaches at mount is injected too, so the test observes only the media rule —
/// a card on a session, nothing on `null`.

NowPlaying _media() {
  return NowPlaying(
    packageName: 'com.test.music',
    appLabel: 'Music',
    title: 'Track One',
    artist: 'Artist One',
    durationMs: 180000,
    positionMs: 30000,
    state: 'playing',
    canPrev: true,
    canNext: true,
    canPlayPause: true,
  );
}

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

Future<void> _pump(
  WidgetTester tester,
  Stream<NowPlaying?> media, {
  Future<bool> Function(String command)? mediaCommand,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: CosmicLockScreen(
          foldable: FoldableController(),
          apps: _apps(),
          onUnlock: () {},
          // No credential: the panel never arms the reader, which keeps the
          // fingerprint path out of this test entirely.
          isDeviceSecure: () async => false,
          fingerprintEvents: () => const Stream.empty(),
          startFingerprintScan: () async => false,
          isKeyguardLocked: () async => true,
          dismissKeyguard: () async => false,
          battery: () async => null,
          mediaStream: media,
          mediaCommand: mediaCommand,
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 16));
}

/// Settles the 250 ms card switcher and the frame after it.
Future<void> _settleSwitcher(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump();
}

void main() {
  testWidgets('the card appears when a playing session arrives', (
    tester,
  ) async {
    final controller = StreamController<NowPlaying?>.broadcast();
    addTearDown(controller.close);

    await _pump(tester, controller.stream);
    expect(find.byType(NowPlayingCard), findsNothing);

    controller.add(_media());
    await _settleSwitcher(tester);

    expect(find.byType(NowPlayingCard), findsOneWidget);
    expect(find.text('Track One'), findsOneWidget);

    // Dispose the tree so the card's progress timer is cancelled.
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the card disappears when the session goes away', (tester) async {
    final controller = StreamController<NowPlaying?>.broadcast();
    addTearDown(controller.close);

    await _pump(tester, controller.stream);

    controller.add(_media());
    await _settleSwitcher(tester);
    expect(find.byType(NowPlayingCard), findsOneWidget);

    controller.add(null);
    await _settleSwitcher(tester);
    expect(find.byType(NowPlayingCard), findsNothing);

    await tester.pumpWidget(const SizedBox());
  });
}
