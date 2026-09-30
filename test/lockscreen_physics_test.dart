import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mylauncher/core/foldable_controller.dart';
import 'package:mylauncher/features/lockscreen/bouncing_physics_engine.dart';
import 'package:mylauncher/features/lockscreen/cosmic_lock_screen.dart';
import 'package:mylauncher/models/app_entry.dart';

/// Eight ambient apps, enough to fill the engine's cap and exercise the grid.
List<AppEntry> _eightApps() => List<AppEntry>.generate(
  8,
  (i) => AppEntry(
    packageName: 'com.test.ambient$i',
    label: 'Ambient $i',
    category: AppCategory.tools,
    accentColor: Colors.primaries[i % Colors.primaries.length],
  ),
);

/// The smallest surface-to-surface distance between any two rings.
double _minRingGap(List<AppBubble> bubbles) {
  var gap = double.infinity;
  for (int i = 0; i < bubbles.length; i++) {
    for (int j = i + 1; j < bubbles.length; j++) {
      final double centre = (bubbles[i].position - bubbles[j].position).distance;
      final double surface = centre - bubbles[i].radius - bubbles[j].radius;
      if (surface < gap) gap = surface;
    }
  }
  return gap;
}

/// Asserts every sphere's painted aura lies inside [band].
void _expectPaintedInside(
  BouncingPhysicsEngine engine,
  Rect band, {
  double tolerance = 0.01,
}) {
  for (final bubble in engine.bubbles) {
    final double painted = BouncingPhysicsEngine.paintedRadius(bubble.radius);
    expect(
      bubble.position.dx - painted,
      greaterThanOrEqualTo(band.left - tolerance),
      reason: '${bubble.app.label} paints past the left edge',
    );
    expect(
      bubble.position.dx + painted,
      lessThanOrEqualTo(band.right + tolerance),
      reason: '${bubble.app.label} paints past the right edge',
    );
    expect(
      bubble.position.dy - painted,
      greaterThanOrEqualTo(band.top - tolerance),
      reason: '${bubble.app.label} paints past the top edge',
    );
    expect(
      bubble.position.dy + painted,
      lessThanOrEqualTo(band.bottom + tolerance),
      reason: '${bubble.app.label} paints past the bottom edge',
    );
  }
}

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
      // The bounce confines the painted aura, not just the core ring.
      expect(
        b.position.dx,
        lessThanOrEqualTo(
          size.width - 20 - BouncingPhysicsEngine.paintedRadius(b.radius) + 0.001,
        ),
      );
    });

    test(
      'Circle-to-circle collision resolves overlap and exchanges momentum',
      () {
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
      },
    );

    test('initial placement keeps the rings separated', () {
      const size = Size(800, 600);
      engine.initializeBubbles(apps: _eightApps(), size: size);
      engine.setBounds(
        const Rect.fromLTRB(60, 120, 740, 520),
        viewport: size,
      );

      expect(
        _minRingGap(engine.bubbles),
        greaterThanOrEqualTo(
          BouncingPhysicsEngine.minBubbleSeparation - 0.5,
        ),
      );
    });

    test('re-lays a band 300 dp wide across its width, not one edge', () {
      const size = Size(400, 900);
      engine.initializeBubbles(apps: _eightApps(), size: size);

      // A band much narrower than the provisional one is exactly the case
      // that used to end with every sphere clamped against one edge.
      engine.setBounds(
        const Rect.fromLTRB(50, 200, 350, 700),
        viewport: size,
      );

      final xs = engine.bubbles.map((bubble) => bubble.position.dx).toList();
      final double span =
          xs.reduce((a, b) => a > b ? a : b) -
          xs.reduce((a, b) => a < b ? a : b);

      expect(
        span,
        greaterThanOrEqualTo(0.60 * 300.0),
        reason: 'a re-band must spread the grid across the band',
      );
    });

    test('painted auras stay inside the band through init, re-band and drift', () {
      const size = Size(400, 900);
      engine.initializeBubbles(
        apps: _eightApps(),
        size: size,
        padding: const EdgeInsets.all(40),
      );
      _expectPaintedInside(engine, const Rect.fromLTRB(40, 40, 360, 860));

      const band = Rect.fromLTRB(50, 200, 350, 700);
      engine.setBounds(band, viewport: size);
      _expectPaintedInside(engine, band);

      for (int i = 0; i < 600; i++) {
        engine.update(0.016);
      }
      _expectPaintedInside(engine, band);
    });

    test('collision handling keeps two drifting rings separated', () {
      const size = Size(500, 500);
      engine.initializeBubbles(
        apps: testApps.take(2).toList(),
        size: size,
        padding: const EdgeInsets.all(20),
      );

      final b1 = engine.bubbles[0]..radius = 30.0;
      final b2 = engine.bubbles[1]..radius = 30.0;
      // Start overlapped and closing: the first step must part them to the
      // separation and every later collision must hold it.
      b1.position = const Offset(200, 250);
      b2.position = const Offset(250, 250);
      b1.velocity = const Offset(80, 0);
      b2.velocity = const Offset(-80, 0);

      for (int i = 0; i < 120; i++) {
        engine.update(0.016);
        final double gap =
            (b2.position - b1.position).distance - b1.radius - b2.radius;
        expect(
          gap,
          greaterThanOrEqualTo(
            BouncingPhysicsEngine.minBubbleSeparation - 0.5,
          ),
          reason: 'the rings must keep the separation at frame $i',
        );
      }
    });

    test(
      'triggerShakeScatter disperses all bubbles outwards with high speed',
      () {
        const size = Size(600, 800);
        engine.initializeBubbles(apps: testApps, size: size);

        engine.triggerShakeScatter(strength: 1.5);

        expect(engine.bubbles, isNotEmpty);
        for (final bubble in engine.bubbles) {
          // High dispersion velocity after shake
          expect(bubble.velocity.distance, greaterThan(500.0));
          expect(bubble.glowIntensity, equals(1.0));
        }
      },
    );

    test(
      'findBubbleAt accurately detects target bubble within touch radius',
      () {
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
      },
    );

    test(
      'notifies listeners per simulation step so the canvas can repaint',
      () {
        // The lock screen's canvas repaints from this notifier instead of the
        // widget rebuilding every frame. If the engine stops notifying, the
        // bubbles silently freeze while every test above still passes.
        const size = Size(400, 800);
        engine.initializeBubbles(apps: testApps, size: size);

        var notifications = 0;
        engine.addListener(() => notifications++);

        engine.update(0.016);
        expect(notifications, equals(1));

        engine.update(0.016);
        expect(notifications, equals(2));
      },
    );

    test('notifies on a direct-manipulation repaint request', () {
      const size = Size(400, 800);
      engine.initializeBubbles(apps: testApps, size: size);

      var notifications = 0;
      engine.addListener(() => notifications++);

      // A drag moves a bubble without stepping the simulation, so it needs its
      // own repaint path — it must work even with the ticker stopped.
      engine.markDirty();
      expect(notifications, equals(1));
    });

    test('notifies when a shake scatters the field', () {
      const size = Size(400, 800);
      engine.initializeBubbles(apps: testApps, size: size);

      var notifications = 0;
      engine.addListener(() => notifications++);

      engine.triggerShakeScatter(strength: 1.5);
      expect(notifications, greaterThan(0));
    });
  });

  group('CosmicLockScreen Widget Tests', () {
    testWidgets('Renders the calm lock screen and swipes up once unlocked', (
      tester,
    ) async {
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
              // This test is about rendering and the swipe. The swipe only
              // clears the panel for someone the platform has authenticated,
              // so the device is reported unlocked here to keep the assertion
              // about the gesture rather than about the keyguard. The keyguard
              // contract has its own tests.
              isKeyguardLocked: () async => false,
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      // The field is painted; the chip row and the SHAKE control are gone;
      // the hint names only the gesture the panel actually owns.
      expect(find.byType(CustomPaint), findsWidgets);
      expect(find.text('SHAKE'), findsNothing);
      expect(find.text('★ Featured'), findsNothing);
      expect(find.text('Core'), findsNothing);
      expect(find.text('Locked'), findsOneWidget);
      expect(find.text('Swipe up to unlock'), findsOneWidget);

      // Perform swipe up from the bottom unlock area.
      await tester.dragFrom(const Offset(400, 550), const Offset(0, -300));
      for (int i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 40));
      }

      expect(unlocked, isTrue);
    });

    testWidgets(
      'Swipe up does NOT enter the launcher while the device is locked',
      (tester) async {
        // The panel is drawn over the keyguard in COSMIC mode, so a swipe that
        // cleared it unconditionally exposed the launcher — the full app
        // inventory, search over every app name, and the editors that persist
        // layout — on a locked device. The panel cannot authenticate anyone
        // itself, so it must ask the platform and honour the answer.
        bool unlocked = false;
        var dismissalRequested = false;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: CosmicLockScreen(
                foldable: FoldableController(),
                apps: [
                  AppEntry(
                    packageName: 'com.test.bank',
                    label: 'Bank',
                    category: AppCategory.core,
                    accentColor: Colors.green,
                    fallbackIcon: Icons.account_balance,
                  ),
                ],
                onUnlock: () => unlocked = true,
                isKeyguardLocked: () async => true,
                // The user backs out of the platform's bouncer.
                dismissKeyguard: () async {
                  dismissalRequested = true;
                  return false;
                },
              ),
            ),
          ),
        );

        await tester.dragFrom(const Offset(400, 550), const Offset(0, -300));
        for (int i = 0; i < 12; i++) {
          await tester.pump(const Duration(milliseconds: 40));
        }

        expect(
          dismissalRequested,
          isTrue,
          reason: 'the swipe must ask the platform to authenticate',
        );
        expect(
          unlocked,
          isFalse,
          reason: 'a declined platform prompt must leave the panel up',
        );
        expect(find.text('UNLOCK TO ENTER THE LAUNCHER'), findsOneWidget);
      },
    );

    testWidgets(
      'Swipe up enters the launcher when the platform authenticates',
      (tester) async {
        bool unlocked = false;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: CosmicLockScreen(
                foldable: FoldableController(),
                apps: [
                  AppEntry(
                    packageName: 'com.test.bank',
                    label: 'Bank',
                    category: AppCategory.core,
                    accentColor: Colors.green,
                    fallbackIcon: Icons.account_balance,
                  ),
                ],
                onUnlock: () => unlocked = true,
                isKeyguardLocked: () async => true,
                // The platform raised its bouncer and the user passed it.
                dismissKeyguard: () async => true,
              ),
            ),
          ),
        );

        await tester.dragFrom(const Offset(400, 550), const Offset(0, -300));
        for (int i = 0; i < 12; i++) {
          await tester.pump(const Duration(milliseconds: 40));
        }

        expect(unlocked, isTrue);
      },
    );

    testWidgets('Tapping quick phone shortcut launches the app', (
      tester,
    ) async {
      final foldable = FoldableController();
      bool unlocked = false;
      final launched = <String>[];
      final previousDebugPrint = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null &&
            message.startsWith('Simulating launching app:')) {
          launched.add(message);
        }
      };

      final apps = [
        AppEntry(
          packageName: 'com.android.phone',
          label: 'Phone',
          category: AppCategory.core,
          accentColor: Colors.green,
          fallbackIcon: Icons.phone,
        ),
      ];

      try {
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
      } finally {
        debugPrint = previousDebugPrint;
      }

      // Non-Android/test environment simulates successful authentication and launching.
      expect(launched, hasLength(1));
      expect(launched.single, contains('com.android.phone'));

      // A successful launch clears the custom overlay so closing the app
      // returns to the cover or home content. Keeping it mounted here would
      // recreate the fingerprint surface over the launcher.
      expect(unlocked, isTrue);
    });

    testWidgets(
      'Draws no fingerprint affordance: the panel is not the reader',
      (tester) async {
        final foldable = FoldableController();
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
                onUnlock: () {},
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 300));

        // The reader is the side power button, so nothing on the panel may look
        // like a fingerprint target the user could press.
        expect(find.byIcon(Icons.fingerprint_rounded), findsNothing);
        expect(find.byIcon(Icons.lock_open_rounded), findsNothing);
        expect(find.text('TOUCH SENSOR TO UNLOCK'), findsNothing);
        expect(find.text('NOT RECOGNIZED • TOUCH AGAIN'), findsNothing);
        expect(find.text('FINGERPRINT UNAVAILABLE'), findsNothing);

        // The quick shortcuts survive the removal, at both ends of the row.
        expect(find.byIcon(Icons.phone_rounded), findsOneWidget);
        expect(find.byIcon(Icons.camera_alt_rounded), findsOneWidget);
      },
    );
  });
}
