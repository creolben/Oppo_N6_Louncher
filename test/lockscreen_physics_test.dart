import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mylauncher/core/foldable_controller.dart';
import 'package:mylauncher/features/lockscreen/bouncing_physics_engine.dart';
import 'package:mylauncher/features/lockscreen/cosmic_lock_screen.dart';
import 'package:mylauncher/models/app_entry.dart';

void main() {
  group('BouncingPhysicsEngine Tests', () {
    late BouncingPhysicsEngine engine;
    late List<AppEntry> testApps;

    setUp(() {
      engine = BouncingPhysicsEngine();
      testApps = [
        AppEntry(
          packageName: 'com.test.app1',
          label: 'App One',
          category: AppCategory.productivity,
          accentColor: Colors.cyan,
        ),
        AppEntry(
          packageName: 'com.test.app2',
          label: 'App Two',
          category: AppCategory.social,
          accentColor: Colors.purple,
        ),
        AppEntry(
          packageName: 'com.test.app3',
          label: 'App Three',
          category: AppCategory.games,
          accentColor: Colors.amber,
        ),
      ];
    });

    test('Initializes bubbles matching app count within viewport', () {
      const size = Size(400, 800);
      engine.initializeBubbles(apps: testApps, size: size);

      expect(engine.bubbles.length, equals(3));
      for (final bubble in engine.bubbles) {
        expect(bubble.position.dx, greaterThan(0));
        expect(bubble.position.dx, lessThan(size.width));
        expect(bubble.position.dy, greaterThan(0));
        expect(bubble.position.dy, lessThan(size.height));
        expect(bubble.radius, greaterThan(20.0));
      }
    });

    test('Physics step updates positions and handles wall bouncing', () {
      const size = Size(400, 800);
      engine.initializeBubbles(
        apps: testApps,
        size: size,
        padding: const EdgeInsets.all(20),
      );

      // Place bubble near right boundary moving right
      final b = engine.bubbles.first;
      b.position = const Offset(370, 400);
      b.velocity = const Offset(100, 0);

      // Step physics
      engine.update(0.1);

      // Should have bounced off right boundary and reversed horizontal velocity
      expect(b.velocity.dx, lessThan(0));
      expect(b.position.dx, lessThanOrEqualTo(size.width - 20));
      expect(engine.sparks.isNotEmpty, isTrue);
    });

    test('Circle-to-circle collision resolves overlap and exchanges momentum', () {
      const size = Size(500, 500);
      engine.initializeBubbles(apps: testApps, size: size);

      final b1 = engine.bubbles[0];
      final b2 = engine.bubbles[1];
      engine.bubbles[2].position = const Offset(450, 450);
      engine.bubbles[2].velocity = Offset.zero;

      b1.radius = 30.0;
      b2.radius = 30.0;
      b1.position = const Offset(200, 200);
      b2.position = const Offset(240, 200); // Distance = 40 < 60 (overlap!)
      b1.velocity = const Offset(100, 0); // Moving right towards b2
      b2.velocity = const Offset(-100, 0); // Moving left towards b1

      engine.update(0.016);

      // Overlap should be separated
      final newDist = (b2.position - b1.position).distance;
      expect(newDist, greaterThanOrEqualTo(59.0));

      // Velocities should reflect away from each other
      expect(b1.velocity.dx, lessThan(0)); // Now moving left
      expect(b2.velocity.dx, greaterThan(0)); // Now moving right
    });

    test('triggerShakeScatter disperses all bubbles outwards with high speed', () {
      const size = Size(600, 800);
      engine.initializeBubbles(apps: testApps, size: size);

      engine.triggerShakeScatter(strength: 1.5);

      expect(engine.ripples.isNotEmpty, isTrue);
      for (final bubble in engine.bubbles) {
        // High dispersion velocity after shake
        expect(bubble.velocity.distance, greaterThan(500.0));
        expect(bubble.glowIntensity, equals(1.0));
      }
    });

    test('findBubbleAt accurately detects target bubble within touch radius', () {
      const size = Size(500, 500);
      engine.initializeBubbles(apps: testApps, size: size);

      final target = engine.bubbles[1];
      target.position = const Offset(250, 300);
      target.radius = 30.0;

      final hit = engine.findBubbleAt(const Offset(255, 305));
      expect(hit, isNotNull);
      expect(hit!.app.packageName, equals(target.app.packageName));

      final miss = engine.findBubbleAt(const Offset(50, 50));
      expect(miss, isNull);
    });
  });

  group('CosmicLockScreen Widget Tests', () {
    testWidgets('Renders bouncing apps lock screen and triggers shake button',
        (tester) async {
      final foldable = FoldableController();
      bool unlocked = false;

      final apps = [
        AppEntry(
          packageName: 'com.test.phone',
          label: 'Phone',
          category: AppCategory.core,
          accentColor: Colors.green,
          fallbackIcon: Icons.phone,
        ),
        AppEntry(
          packageName: 'com.test.chat',
          label: 'Chat',
          category: AppCategory.social,
          accentColor: Colors.blue,
          fallbackIcon: Icons.chat,
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CosmicLockScreen(
              foldable: foldable,
              apps: apps,
              onUnlock: () => unlocked = true,
              initialAuthenticated: true,
            ),
          ),
        ),
      );

      // Verify custom painter is present
      expect(find.byType(CustomPaint), findsWidgets);
      expect(find.text('SHAKE'), findsOneWidget);
      expect(find.text('TAP APP TO LAUNCH • SWIPE UP TO ENTER'), findsOneWidget);

      // Tap SHAKE button
      await tester.tap(find.text('SHAKE'));
      await tester.pump(const Duration(milliseconds: 100));

      // Verify turbulence indicator appears
      expect(
        find.text('⚡ COSMIC SHAKE DETECTED • APPS DISPERSED'),
        findsOneWidget,
      );

      // Perform swipe up from the bottom unlock area
      await tester.dragFrom(const Offset(400, 550), const Offset(0, -300));
      for (int i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 40));
      }

      expect(unlocked, isTrue);
    });

    testWidgets('Bouncing apps and category chips are immediately accessible on lock screen',
        (tester) async {
      final foldable = FoldableController();
      bool unlocked = false;

      final apps = [
        AppEntry(
          packageName: 'com.test.phone',
          label: 'Phone',
          category: AppCategory.core,
          accentColor: Colors.green,
          fallbackIcon: Icons.phone,
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CosmicLockScreen(
              foldable: foldable,
              apps: apps,
              onUnlock: () => unlocked = true,
            ),
          ),
        ),
      );

      // Bouncing apps canvas and category chips are always visible
      expect(find.byType(CustomPaint), findsWidgets);
      expect(find.text('★ Featured'), findsOneWidget);
      expect(find.text('Core'), findsOneWidget);
      expect(find.text('Social'), findsOneWidget);
      expect(find.text('TAP APP TO LAUNCH • SWIPE UP TO ENTER'), findsOneWidget);
      expect(find.text('LOCKED'), findsOneWidget);

      // Swipe up allows direct access to launcher
      await tester.dragFrom(const Offset(400, 550), const Offset(0, -300));
      for (int i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 40));
      }
      expect(unlocked, isTrue);
    });

    testWidgets('Tapping quick phone shortcut invokes unlock and launches app',
        (tester) async {
      final foldable = FoldableController();
      bool unlocked = false;

      final apps = [
        AppEntry(
          packageName: 'com.android.phone',
          label: 'Phone',
          category: AppCategory.core,
          accentColor: Colors.green,
          fallbackIcon: Icons.phone,
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CosmicLockScreen(
              foldable: foldable,
              apps: apps,
              onUnlock: () => unlocked = true,
            ),
          ),
        ),
      );

      // Tap the quick action phone icon at the bottom left
      await tester.tap(find.byIcon(Icons.phone_rounded));
      for (int i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 40));
      }

      // Non-Android/test environment simulates successful authentication, unlocking and launching
      expect(unlocked, isTrue);
    });
  });
}
