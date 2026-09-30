import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mylauncher/core/foldable_controller.dart';
import 'package:mylauncher/features/lockscreen/cosmic_lock_screen.dart';
import 'package:mylauncher/features/lockscreen/now_playing_card.dart';
import 'package:mylauncher/models/app_entry.dart';
import 'package:mylauncher/models/now_playing.dart';

/// The lock surface must lay out at any aspect ratio.
///
/// Android 16 ignores the manifest's portrait lock once the smallest width
/// reaches 600dp, so the cover display (sw351dp) stays portrait while the inner
/// display (sw692dp) can present the panel — and a playing card — landscape.
/// These tests pin the three real shapes and prove nothing overflows or falls
/// off screen.

// The panel uses the platform's 12/24-hour setting; the test MediaQuery
// defaults to 12-hour, so match the optional `AM`/`pm` suffix too.
final RegExp _clockPattern = RegExp(r'^\d{1,2}:\d{2}(\s?[AaPp]\.?[Mm]\.?)?$');

List<AppEntry> _apps() => [
  AppEntry(
    packageName: 'com.test.camera',
    activityName: 'com.test.camera.Camera',
    label: 'Camera',
    category: AppCategory.core,
    accentColor: Colors.amber,
    fallbackIcon: Icons.camera_alt_rounded,
  ),
  AppEntry(
    packageName: 'com.test.notes',
    label: 'Notes',
    category: AppCategory.tools,
    accentColor: Colors.teal,
    fallbackIcon: Icons.edit_note_rounded,
    iconBytes: Uint8List.fromList(const [1, 2, 3, 4]),
  ),
];

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

Future<void> _pumpPanel(WidgetTester tester, Stream<NowPlaying?> media) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: CosmicLockScreen(
          foldable: FoldableController(),
          apps: _apps(),
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

void _expectOnScreen(WidgetTester tester, Finder finder, Size size) {
  expect(finder, findsOneWidget);
  final Rect rect = tester.getRect(finder);
  expect(rect.left, greaterThanOrEqualTo(-0.01));
  expect(rect.top, greaterThanOrEqualTo(-0.01));
  expect(rect.right, lessThanOrEqualTo(size.width + 0.01));
  expect(rect.bottom, lessThanOrEqualTo(size.height + 0.01));
}

void main() {
  const List<Size> sizes = <Size>[
    Size(351, 805), // cover display, portrait (sw351dp)
    Size(692, 763), // inner display, portrait (sw692dp)
    Size(763, 692), // inner display, landscape
  ];

  for (final Size size in sizes) {
    testWidgets(
      'lays out without overflow at '
      '${size.width.toInt()}x${size.height.toInt()}',
      (tester) async {
        tester.view.devicePixelRatio = 1.0;
        tester.view.physicalSize = size;
        addTearDown(tester.view.reset);

        // Enable semantics before the pumps so the tree is built by the time
        // the shortcut labels are read. flutter_test checks for active handles
        // at the end of the body, so this one is disposed explicitly below
        // rather than through addTearDown (which runs after that check).
        final semantics = tester.ensureSemantics();

        final controller = StreamController<NowPlaying?>.broadcast();
        addTearDown(controller.close);

        await _pumpPanel(tester, controller.stream);
        controller.add(_media());
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump();

        // A RenderFlex overflow is reported as a frame exception, not a crash.
        expect(tester.takeException(), isNull);
        expect(find.byType(NowPlayingCard), findsOneWidget);

        // The clock is the only time-shaped string at display size; the card's
        // own `0:30` is 10pt and must not be mistaken for it.
        final clock = find.byWidgetPredicate(
          (w) =>
              w is Text &&
              w.data != null &&
              _clockPattern.hasMatch(w.data!) &&
              (w.style?.fontSize ?? 0) > 40,
        );

        _expectOnScreen(tester, clock, size);
        _expectOnScreen(tester, find.text('Swipe up to unlock'), size);
        _expectOnScreen(tester, find.bySemanticsLabel('Phone'), size);
        _expectOnScreen(tester, find.bySemanticsLabel('Camera'), size);

        // Dispose the panel so its ticker and periodic timer do not leak into
        // the next test.
        await tester.pumpWidget(const SizedBox());
        semantics.dispose();
      },
    );
  }
}
