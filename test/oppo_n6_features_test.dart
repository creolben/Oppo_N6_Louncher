import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mylauncher/core/galaxy_layout_engine.dart';
import 'package:mylauncher/core/foldable_controller.dart';
import 'package:mylauncher/canvas/camera_controller.dart';
import 'package:mylauncher/models/app_entry.dart';
import 'package:mylauncher/features/lockscreen/bouncing_physics_engine.dart';
import 'package:mylauncher/ui/widgets/search_overlay.dart';
import 'package:mylauncher/ui/screens/tabletop_cockpit_view.dart';
import 'package:mylauncher/canvas/galaxy_interactive_canvas.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Oppo N6 Foldable Enhancements Tests', () {
    test('GalaxyLayoutEngine correctly hides and unhides applications', () {
      final engine = GalaxyLayoutEngine();
      final apps = [
        AppEntry(packageName: 'com.test.phone', label: 'Phone', category: AppCategory.core),
        AppEntry(packageName: 'com.test.chat', label: 'Chat', category: AppCategory.social),
        AppEntry(packageName: 'com.test.secret', label: 'Secret Notes', category: AppCategory.productivity),
      ];

      engine.assignApps(apps);
      expect(engine.hiddenPackageNames, isEmpty);

      // Hide app
      engine.hideApp('com.test.secret');
      expect(engine.hiddenPackageNames, contains('com.test.secret'));
      expect(engine.isAppHidden('com.test.secret'), isTrue);

      // Check that hidden app is not assigned to any constellation
      for (final c in engine.constellations) {
        expect(c.apps.any((a) => a.packageName == 'com.test.secret'), isFalse);
      }

      // Unhide app
      engine.unhideApp('com.test.secret');
      expect(engine.isAppHidden('com.test.secret'), isFalse);
      final prodConstellation = engine.constellations.firstWhere((c) => c.id == 'productivity');
      expect(prodConstellation.apps.any((a) => a.packageName == 'com.test.secret'), isTrue);
    });

    test('BouncingPhysicsEngine accelerates bubbles with gravity tilt vector', () {
      final engine = BouncingPhysicsEngine();
      final testApp = AppEntry(packageName: 'com.test.bubble', label: 'Test Bubble');
      engine.initializeBubbles(
        apps: [testApp],
        size: const Size(400, 800),
      );

      expect(engine.bubbles.length, 1);
      final bubble = engine.bubbles.first;
      bubble.velocity = Offset.zero;

      // Apply rightward tilt
      engine.tiltVector = const Offset(1.0, 0.0);
      engine.update(1.0 / 60.0);

      // Bubble should have gained positive dx velocity
      expect(bubble.velocity.dx, greaterThan(0.0));
    });

    testWidgets('SearchOverlay renders A-Z scrubber rail and Hidden sector tab', (tester) async {
      final camera = CameraController();
      final engine = GalaxyLayoutEngine();
      final apps = [
        AppEntry(packageName: 'com.test.alpha', label: 'Alpha', category: AppCategory.tools),
        AppEntry(packageName: 'com.test.beta', label: 'Beta', category: AppCategory.tools),
        AppEntry(packageName: 'com.test.zeta', label: 'Zeta', category: AppCategory.tools),
        AppEntry(packageName: 'com.test.hidden', label: 'Hidden Vault', category: AppCategory.tools),
      ];

      engine.setHiddenPackageNames(['com.test.hidden']);
      engine.assignApps(apps);

      tester.view.physicalSize = const Size(1200, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SearchOverlay(
              allApps: apps,
              camera: camera,
              layoutEngine: engine,
              onClose: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Check A-Z alphabet letters exist in the scrubber rail
      expect(find.text('A'), findsAtLeastNWidgets(1));
      expect(find.text('Z'), findsAtLeastNWidgets(1));

      // Scroll category sector filter to reveal Hidden tab
      await tester.drag(find.byType(ListView).first, const Offset(-600, 0));
      await tester.pumpAndSettle();

      // Check Hidden sector tab is rendered
      expect(find.text('Hidden'), findsOneWidget);

      // Tap Hidden category tab
      await tester.tap(find.text('Hidden'));
      await tester.pumpAndSettle();

      // Only 'Hidden Vault' should be visible
      expect(find.text('Hidden Vault'), findsOneWidget);
      expect(find.text('Alpha'), findsNothing);
    });

    testWidgets('TabletopCockpitView renders Top HUD and Bottom Cockpit', (tester) async {
      final foldable = FoldableController();
      foldable.setHingeAngle(90.0); // Half folded tabletop
      final engine = GalaxyLayoutEngine();
      final apps = [
        AppEntry(packageName: 'com.test.core1', label: 'Core 1', category: AppCategory.core),
        AppEntry(packageName: 'com.test.core2', label: 'Core 2', category: AppCategory.core),
      ];
      engine.assignApps(apps);

      tester.view.physicalSize = const Size(1200, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TabletopCockpitView(
              apps: apps,
              foldable: foldable,
              layoutEngine: engine,
              onOpenSearch: () {},
              onOpenSettings: () {},
              onLock: () {},
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      // Verify GalaxyInteractiveCanvas is rendered in the top constellation viewport
      expect(find.byType(GalaxyInteractiveCanvas), findsOneWidget);

      // Verify Telemetry badge
      expect(find.textContaining('OPPO N6 FLEX MODE'), findsOneWidget);

      // Verify Search trigger in top HUD
      expect(find.text('Search galaxy applications...'), findsOneWidget);

      // Verify Bottom Cockpit controls
      expect(find.text('Search'), findsOneWidget);
      expect(find.text('Lock'), findsOneWidget);
      expect(find.text('Settings'), findsOneWidget);
    });
  });
}
