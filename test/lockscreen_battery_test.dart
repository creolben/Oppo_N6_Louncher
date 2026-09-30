import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mylauncher/core/foldable_controller.dart';
import 'package:mylauncher/core/launcher_bridge.dart';
import 'package:mylauncher/features/lockscreen/cosmic_lock_screen.dart';
import 'package:mylauncher/models/app_entry.dart';

/// The lock surface's battery cluster.
///
/// The panel used to hardcode `92%` under a charging glyph that never went
/// out — a lock screen that lies about the battery is the opposite of
/// feeling native. Two rules are pinned here: the percentage shows only a
/// level the platform actually reported, and an unknown level hides it
/// rather than inventing a number.

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

  group('Lock screen battery row (through the seam)', () {
    testWidgets('a known level shows the percentage from the seam', (
      tester,
    ) async {
      await _pumpLockScreen(
        tester,
        battery: () async => const BatteryState(level: 92, charging: true),
      );

      expect(find.text('92%'), findsOneWidget);
      expect(find.byIcon(Icons.battery_charging_full_rounded), findsOneWidget);
    });

    testWidgets('an unknown level hides the percentage but keeps the row up', (
      tester,
    ) async {
      await _pumpLockScreen(tester, battery: () async => null);

      // No invented number: the platform could not report a level.
      expect(find.textContaining('%'), findsNothing);
      // The cluster keeps its glyph, so the telemetry row does not collapse.
      expect(find.byIcon(Icons.battery_std_rounded), findsOneWidget);
      expect(find.byIcon(Icons.battery_charging_full_rounded), findsNothing);
    });

    testWidgets('a known level on battery power shows the plain glyph', (
      tester,
    ) async {
      await _pumpLockScreen(
        tester,
        battery: () async => const BatteryState(level: 47, charging: false),
      );

      expect(find.text('47%'), findsOneWidget);
      expect(find.byIcon(Icons.battery_std_rounded), findsOneWidget);
      expect(find.byIcon(Icons.battery_charging_full_rounded), findsNothing);
    });
  });
}