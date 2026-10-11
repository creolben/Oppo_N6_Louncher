import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mylauncher/canvas/camera_controller.dart';
import 'package:mylauncher/canvas/galaxy_interactive_canvas.dart';
import 'package:mylauncher/core/foldable_controller.dart';
import 'package:mylauncher/core/galaxy_layout_engine.dart';
import 'package:mylauncher/core/system_gestures.dart';
import 'package:mylauncher/features/lockscreen/cosmic_lock_screen.dart';
import 'package:mylauncher/main.dart';
import 'package:mylauncher/models/app_entry.dart';
import 'package:mylauncher/ui/widgets/search_overlay.dart';

/// Records what the launcher asked the optional accessibility service to do,
/// standing in for the platform so none of this needs a device.
class _FakeGestures implements SystemGesturesBackend {
  bool enabled = true;
  bool performResult = true;
  final List<String> actions = <String>[];
  int settingsOpened = 0;

  @override
  Future<bool> isAccessibilityEnabled() async => enabled;

  @override
  Future<bool> openAccessibilitySettings() async {
    settingsOpened++;
    return true;
  }

  @override
  Future<bool> performGlobalAction(String action) async {
    actions.add(action);
    return performResult;
  }
}

List<AppEntry> _coreApps() => [
      AppEntry(
        packageName: 'com.test.phone',
        label: 'Phone',
        category: AppCategory.core,
        accentColor: Colors.green,
      ),
      AppEntry(
        packageName: 'com.test.messages',
        label: 'Messages',
        category: AppCategory.core,
        accentColor: Colors.blue,
      ),
    ];

/// An empty screen point: far from every constellation hub and every app, in
/// the top-left corner of the canvas. Verified against the layout engine's own
/// geometry rather than guessed, so a layout change cannot silently turn this
/// into a node tap.
Offset _emptyPoint(CameraController camera, GalaxyLayoutEngine engine) {
  for (double x = 20; x < 200; x += 20) {
    for (double y = 20; y < 200; y += 20) {
      final Offset screen = Offset(x, y);
      final Offset world = camera.screenToWorld(screen);
      bool occupied = false;
      for (final constellation in engine.constellations) {
        final double hubRadius = constellation.id == 'core' ? 70.0 : 45.0;
        if ((world - constellation.center).distance <= hubRadius + 20) {
          occupied = true;
          break;
        }
        for (final app in constellation.apps) {
          if ((world - app.worldPosition).distance <= 70) {
            occupied = true;
            break;
          }
        }
        if (occupied) break;
      }
      if (!occupied) return screen;
    }
  }
  fail('the galaxy has no empty corner to tap');
}

class _CanvasHarness {
  _CanvasHarness() {
    layoutEngine.assignApps(apps);
    layoutEngine.constellations.firstWhere((c) => c.id == 'core').isExpanded =
        true;
  }

  final List<AppEntry> apps = _coreApps();
  final FoldableController foldable = FoldableController();
  final CameraController camera = CameraController();
  final GalaxyLayoutEngine layoutEngine = GalaxyLayoutEngine();
}

Future<_CanvasHarness> _pumpCanvas(
  WidgetTester tester, {
  required bool doubleTapToSleep,
  void Function(AppEntry app)? onAppSelected,
}) async {
  final harness = _CanvasHarness();
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: GalaxyInteractiveCanvas(
          apps: harness.apps,
          foldable: harness.foldable,
          camera: harness.camera,
          layoutEngine: harness.layoutEngine,
          doubleTapToSleep: doubleTapToSleep,
          onAppSelected: onAppSelected,
        ),
      ),
    ),
  );
  // A fixed pump: the render loop never settles, so pumpAndSettle would hang.
  await tester.pump(const Duration(milliseconds: 16));
  return harness;
}

void main() {
  late _FakeGestures fake;

  setUp(() {
    fake = _FakeGestures();
    SystemGestures.debugBackend = fake;
  });

  tearDown(() {
    SystemGestures.debugBackend = null;
  });

  group('Double tap on empty space', () {
    testWidgets('locks the screen when the service is enabled', (tester) async {
      final harness = await _pumpCanvas(tester, doubleTapToSleep: true);
      final Offset empty = _emptyPoint(harness.camera, harness.layoutEngine);

      await tester.tapAt(empty);
      await tester.pump();
      await tester.tapAt(empty);
      await tester.pump();

      expect(fake.actions, <String>[SystemGestures.actionLockScreen]);
    });

    testWidgets('does nothing when the service is off', (tester) async {
      fake.enabled = false;
      final harness = await _pumpCanvas(tester, doubleTapToSleep: true);
      final Offset empty = _emptyPoint(harness.camera, harness.layoutEngine);

      await tester.tapAt(empty);
      await tester.pump();
      await tester.tapAt(empty);
      await tester.pump();

      expect(fake.actions, isEmpty);
    });

    testWidgets('does nothing when the preference is off', (tester) async {
      final harness = await _pumpCanvas(tester, doubleTapToSleep: false);
      final Offset empty = _emptyPoint(harness.camera, harness.layoutEngine);

      await tester.tapAt(empty);
      await tester.pump();
      await tester.tapAt(empty);
      await tester.pump();

      expect(fake.actions, isEmpty);
    });

    testWidgets('a single tap on empty space never locks', (tester) async {
      final harness = await _pumpCanvas(tester, doubleTapToSleep: true);
      final Offset empty = _emptyPoint(harness.camera, harness.layoutEngine);

      await tester.tapAt(empty);
      await tester.pump();

      expect(fake.actions, isEmpty);
    });
  });

  group('Node taps stay immediate', () {
    testWidgets('a single tap on a node launches without waiting for a second',
        (tester) async {
      final semantics = tester.ensureSemantics();
      final List<String> selected = <String>[];
      await _pumpCanvas(
        tester,
        doubleTapToSleep: true,
        onAppSelected: (app) => selected.add(app.packageName),
      );

      final Rect node = tester.getRect(find.bySemanticsLabel('Phone'));
      await tester.tapAt(node.center);
      // A zero-duration pump: a double-tap recognizer would still be holding the
      // gesture here, and the launch would not have happened yet.
      await tester.pump();

      expect(selected, <String>['com.test.phone']);
      expect(fake.actions, isEmpty,
          reason: 'tapping a node is not the sleep gesture');

      // Drain the launch's own deferred supernova delay so no timer outlives
      // the test; the assertion above already proved it did not wait on one.
      await tester.pump(const Duration(milliseconds: 350));

      semantics.dispose();
    });
  });

  group('Swipe down', () {
    Future<void> pumpHome(WidgetTester tester, String? action) async {
      await tester.pumpWidget(
        ChronoFoldApp(
          isKeyguardLocked: () async => false,
          swipeDownAction: action,
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(GalaxyInteractiveCanvas), findsOneWidget);
    }

    Future<void> swipe(WidgetTester tester) async {
      await tester.fling(
        find.byType(GalaxyInteractiveCanvas),
        const Offset(0, 320),
        1200,
      );
      await tester.pump();
      await tester.pump();
    }

    testWidgets('opens search by default', (tester) async {
      await pumpHome(tester, SwipeDownAction.search);

      await swipe(tester);

      expect(find.byType(SearchOverlay), findsOneWidget);
      expect(fake.actions, isEmpty);
    });

    testWidgets('opens the notification shade when configured and enabled',
        (tester) async {
      await pumpHome(tester, SwipeDownAction.notifications);

      await swipe(tester);

      expect(fake.actions, <String>[SystemGestures.actionNotifications]);
      expect(find.byType(SearchOverlay), findsNothing);
    });

    testWidgets('falls back to search when configured but the service is off',
        (tester) async {
      fake.enabled = false;
      await pumpHome(tester, SwipeDownAction.notifications);

      await swipe(tester);

      expect(find.byType(SearchOverlay), findsOneWidget);
      expect(fake.actions, isEmpty);
    });

    testWidgets('an unknown stored action behaves like search', (tester) async {
      await pumpHome(tester, 'shade');

      await swipe(tester);

      expect(find.byType(SearchOverlay), findsOneWidget);
      expect(fake.actions, isEmpty);
    });
  });

  group('Lock buttons on the launcher', () {
    Future<void> pumpLauncher(WidgetTester tester) async {
      await tester.pumpWidget(
        ChronoFoldApp(isKeyguardLocked: () async => false),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(GalaxyInteractiveCanvas), findsOneWidget);
    }

    /// Taps the cockpit shelf's Lock control. The shelf is a horizontal
    /// scroller and its lock button sits near the end, so it must be brought
    /// into view before the tap lands.
    Future<void> tapLock(WidgetTester tester) async {
      final Finder lock = find.byTooltip('Lock screen');
      expect(lock, findsOneWidget);
      await tester.ensureVisible(lock);
      await tester.pump();
      await tester.tap(lock);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
    }

    testWidgets(
        'locks through the service without mounting the cosmic panel',
        (tester) async {
      await pumpLauncher(tester);

      await tapLock(tester);

      expect(fake.actions, <String>[SystemGestures.actionLockScreen]);
      expect(
        find.byType(CosmicLockScreen),
        findsNothing,
        reason: 'the real screen-off broadcast mounts the panel, not the tap',
      );
    });

    testWidgets('a disabled service points at Accessibility instead',
        (tester) async {
      fake.enabled = false;
      await pumpLauncher(tester);

      await tapLock(tester);

      expect(fake.actions, isEmpty);
      expect(find.byType(CosmicLockScreen), findsNothing);
      expect(
        find.text('Turn on ChronoFold in Accessibility to lock instantly'),
        findsOneWidget,
      );

      // The action is the one grant that turns instant locking on. Invoke it
      // directly: the floating snack bar overlaps the cockpit shelf, so its
      // action is not reliably hit-testable from the test surface.
      final SnackBarAction action = tester.widget<SnackBarAction>(
        find.byType(SnackBarAction),
      );
      action.onPressed();
      await tester.pump();
      expect(fake.settingsOpened, 1);
      expect(find.byType(CosmicLockScreen), findsNothing);

      // Drain the snack bar's auto-dismiss timer.
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('a service that refuses the lock shows the same guidance',
        (tester) async {
      fake.performResult = false;
      await pumpLauncher(tester);

      await tapLock(tester);

      expect(fake.actions, <String>[SystemGestures.actionLockScreen]);
      expect(find.byType(CosmicLockScreen), findsNothing);
      expect(
        find.text('Turn on ChronoFold in Accessibility to lock instantly'),
        findsOneWidget,
      );

      // Drain the snack bar's auto-dismiss timer.
      await tester.pump(const Duration(seconds: 5));
    });
  });
}
