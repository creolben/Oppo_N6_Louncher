import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mylauncher/core/foldable_controller.dart';
import 'package:mylauncher/core/launcher_bridge.dart';
import 'package:mylauncher/features/lockscreen/cosmic_lock_screen.dart';
import 'package:mylauncher/models/app_entry.dart';

/// The lock surface's battery line.
///
/// The panel used to hardcode `92%` under a charging glyph that never went
/// out — a lock screen that lies about the battery is the opposite of
/// feeling native. The line is now shown only while charging, because the
/// status bar already carries a discharging percentage; an unknown level
/// hides the number rather than inventing one.

List<AppEntry> _apps() => [
  AppEntry(
    packageName: 'com.test.camera',
    label: 'Camera',
    category: AppCategory.core,
    accentColor: Colors.amber,
    fallbackIcon: Icons.camera_alt_rounded,
  ),
];

Future<void> _pumpLockScreen(
  WidgetTester tester, {
  required Future<BatteryState?> Function() battery,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: CosmicLockScreen(
          foldable: FoldableController(),
          apps: _apps(),
          onUnlock: () {},
          battery: battery,
        ),
      ),
    ),
  );
  // Let the mount-time sample land and the telemetry row rebuild.
  await tester.pump(const Duration(milliseconds: 16));
}

void main() {
  group('BatteryState presentation (pure decision)', () {
    test('a reported level renders as a percentage', () {
      const state = BatteryState(level: 92, charging: true);
      expect(state.percentage, equals('92%'));
    });

    test('an unknown level hides the percentage instead of inventing one', () {
      const state = BatteryState(level: null, charging: false);
      expect(state.percentage, isNull);
    });

    test('the glyph follows the charger, not the old always-on bolt', () {
      const charging = BatteryState(level: 47, charging: true);
      const discharging = BatteryState(level: 47, charging: false);
      expect(charging.icon, equals(Icons.battery_charging_full_rounded));
      expect(discharging.icon, equals(Icons.battery_std_rounded));
    });
  });

  group('Lock screen battery line (through the seam)', () {
    testWidgets('a charging level shows one line under the date', (
      tester,
    ) async {
      await _pumpLockScreen(
        tester,
        battery: () async => const BatteryState(level: 92, charging: true),
      );

      expect(find.text('Charging · 92 %'), findsOneWidget);
    });

    testWidgets('a full charge reads as Charged', (tester) async {
      await _pumpLockScreen(
        tester,
        battery: () async => const BatteryState(level: 100, charging: true),
      );

      expect(find.text('Charged'), findsOneWidget);
      expect(find.textContaining('%'), findsNothing);
    });

    testWidgets('an unknown charging level keeps the line without a number', (
      tester,
    ) async {
      await _pumpLockScreen(
        tester,
        battery: () async => const BatteryState(level: null, charging: true),
      );

      expect(find.text('Charging'), findsOneWidget);
      expect(find.textContaining('%'), findsNothing);
    });

    testWidgets('discharging shows no line at all', (tester) async {
      await _pumpLockScreen(
        tester,
        battery: () async => const BatteryState(level: 47, charging: false),
      );

      // The status bar owns the discharging percentage; repeating it on the
      // lock screen would be noise. Assert on the `%` the line would carry
      // rather than the level number, which the wall clock can also contain.
      expect(find.textContaining('%'), findsNothing);
      expect(find.textContaining('Charg'), findsNothing);
    });

    testWidgets('no battery answer shows no line at all', (tester) async {
      await _pumpLockScreen(tester, battery: () async => null);

      expect(find.textContaining('%'), findsNothing);
      expect(find.textContaining('Charg'), findsNothing);
    });
  });
}