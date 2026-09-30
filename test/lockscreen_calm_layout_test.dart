import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mylauncher/core/foldable_controller.dart';
import 'package:mylauncher/core/launcher_bridge.dart';
import 'package:mylauncher/features/lockscreen/bouncing_apps_painter.dart';
import 'package:mylauncher/features/lockscreen/cosmic_lock_screen.dart';
import 'package:mylauncher/models/app_entry.dart';

/// P3: the calm lock screen.
///
/// The panel is a lock surface now, not a playground: one swipe surface, three
/// transport buttons and two corner shortcuts, an ambient field that launches
/// nothing, and no chip row or SHAKE toy. These hold that shape.

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
    // The field only draws apps with real icon bytes; the camera above is
    // excluded because the corner shortcut already stands for it.
    iconBytes: Uint8List.fromList(const [1, 2, 3, 4]),
  ),
];

Future<void> _pumpCalm(
  WidgetTester tester, {
  Future<bool> Function()? isDeviceSecure,
  Future<FingerprintCapability> Function()? fingerprintCapability,
  Future<bool> Function()? startFingerprintScan,
  Future<BatteryState?> Function()? battery,
  Future<bool> Function(AppEntry app)? launchApp,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: CosmicLockScreen(
          foldable: FoldableController(),
          apps: _apps(),
          onUnlock: () {},
          isDeviceSecure: isDeviceSecure,
          fingerprintCapability: fingerprintCapability,
          startFingerprintScan: startFingerprintScan,
          battery: battery,
          launchApp: launchApp,
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 16));
}

void main() {
  testWidgets('lays out the calm HUD with no chips and no SHAKE control', (
    tester,
  ) async {
    await _pumpCalm(tester, isDeviceSecure: () async => true);
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byIcon(Icons.vibration_rounded), findsNothing);
    expect(find.text('SHAKE'), findsNothing);
    expect(find.text('★ Featured'), findsNothing);
    expect(find.text('Core'), findsNothing);
    expect(find.text('Social'), findsNothing);
    expect(find.text('Tools'), findsNothing);

    // The field is still painted, and the hint asks only for the swipe.
    expect(
      find.byWidgetPredicate(
        (w) => w is CustomPaint && w.painter is BouncingAppsPainter,
      ),
      findsOneWidget,
    );
    expect(find.text('Swipe up to unlock'), findsOneWidget);
  });

  testWidgets('tapping where a bubble is painted launches nothing', (
    tester,
  ) async {
    final launched = <String>[];
    await _pumpCalm(
      tester,
      isDeviceSecure: () async => true,
      launchApp: (app) async {
        launched.add(app.packageName);
        return true;
      },
    );
    await tester.pump(const Duration(milliseconds: 100));

    final field = find.byWidgetPredicate(
      (w) => w is CustomPaint && w.painter is BouncingAppsPainter,
    );
    final painter =
        tester.widget<CustomPaint>(field).painter! as BouncingAppsPainter;
    final bubble = painter.physics.bubbles.first;
    final box = tester.renderObject<RenderBox>(field);
    final target = box.localToGlobal(bubble.position);

    // The tap really lands on the field, not off the edge of the screen.
    expect(box.paintBounds.contains(box.globalToLocal(target)), isTrue);

    await tester.tapAt(target);
    await tester.pump(const Duration(milliseconds: 400));

    expect(
      launched,
      isEmpty,
      reason: 'the ambient field must not be a launch target',
    );
  });

  testWidgets('names the side power key when a reader is enrolled', (
    tester,
  ) async {
    await _pumpCalm(
      tester,
      isDeviceSecure: () async => true,
      fingerprintCapability: () async =>
          const FingerprintCapability(hardware: true, enrolled: true),
      startFingerprintScan: () async => true,
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Swipe up or touch the power key'), findsOneWidget);
    expect(find.text('Locked'), findsOneWidget);
  });

  testWidgets('promises only the swipe on a device with no credential', (
    tester,
  ) async {
    await _pumpCalm(tester, isDeviceSecure: () async => false);
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Swipe up to open'), findsOneWidget);
    expect(find.text('Locked'), findsNothing);
  });

  testWidgets('shows "Charging · 80 %" while charging', (tester) async {
    await _pumpCalm(
      tester,
      isDeviceSecure: () async => true,
      battery: () async => const BatteryState(level: 80, charging: true),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Charging · 80 %'), findsOneWidget);
  });

  testWidgets('shows no battery line on battery power', (tester) async {
    await _pumpCalm(
      tester,
      isDeviceSecure: () async => true,
      battery: () async => const BatteryState(level: 80, charging: false),
    );
    await tester.pump(const Duration(milliseconds: 100));
    // The discharging line would be the only `%` on the panel; assert on that
    // rather than the level number, which the wall clock can also contain.
    expect(find.textContaining('%'), findsNothing);
    expect(find.textContaining('Charg'), findsNothing);
  });

  testWidgets('stops scheduling frames after 10 s with no input', (
    tester,
  ) async {
    await _pumpCalm(tester, isDeviceSecure: () async => true);
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      tester.binding.hasScheduledFrame,
      isTrue,
      reason: 'the field should be drifting while the idle window is open',
    );

    await tester.pump(const Duration(seconds: 11));
    expect(
      tester.binding.hasScheduledFrame,
      isFalse,
      reason: 'the idle field must stop ticking, not just slow down',
    );
  });
}
