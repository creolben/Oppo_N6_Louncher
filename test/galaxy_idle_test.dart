import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mylauncher/canvas/camera_controller.dart';
import 'package:mylauncher/canvas/galaxy_interactive_canvas.dart';
import 'package:mylauncher/core/foldable_controller.dart';
import 'package:mylauncher/core/galaxy_layout_engine.dart';
import 'package:mylauncher/models/app_entry.dart';

/// The galaxy render loop is the launcher's largest steady cost, so it rests
/// on its last frame once nobody is touching the canvas and nothing is moving,
/// and wakes on any activity. These tests hold both halves of that in place.

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

class _Harness {
  final FoldableController foldable = FoldableController();
  final CameraController camera = CameraController();
  final GalaxyLayoutEngine layoutEngine = GalaxyLayoutEngine();
  final List<AppEntry> apps = _coreApps();
  final ValueNotifier<bool> tickerEnabled = ValueNotifier(true);

  _Harness() {
    layoutEngine.assignApps(apps);
    layoutEngine.constellations.firstWhere((c) => c.id == 'core').isExpanded =
        true;
  }

  AppEntry get firstCoreApp =>
      layoutEngine.constellations.firstWhere((c) => c.id == 'core').apps.first;
}

Future<_Harness> _pumpCanvas(
  WidgetTester tester, {
  bool reduceMotion = false,
}) async {
  final harness = _Harness();
  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduceMotion),
        child: Scaffold(
          body: ValueListenableBuilder<bool>(
            valueListenable: harness.tickerEnabled,
            builder: (context, enabled, child) =>
                TickerMode(enabled: enabled, child: child!),
            child: GalaxyInteractiveCanvas(
              apps: harness.apps,
              foldable: harness.foldable,
              camera: harness.camera,
              layoutEngine: harness.layoutEngine,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 16));
  return harness;
}

/// Whether anything (the render loop, a camera animation) wants another frame.
bool _ticking(WidgetTester tester) =>
    tester.binding.transientCallbackCount > 0;

/// Pumps real frames, 100ms apart, for [duration].
Future<void> _run(WidgetTester tester, Duration duration) async {
  const step = Duration(milliseconds: 100);
  for (var t = Duration.zero; t < duration; t += step) {
    await tester.pump(step);
  }
}

/// Lets the canvas run past its idle window so the loop is resting.
Future<void> _goIdle(WidgetTester tester) => _run(
      tester,
      GalaxyInteractiveCanvas.idleTimeout + const Duration(seconds: 4),
    );

void main() {
  group('Galaxy render loop idle pause', () {
    testWidgets('keeps rendering inside the idle window', (tester) async {
      await _pumpCanvas(tester);
      await _run(tester, const Duration(seconds: 5));
      expect(_ticking(tester), isTrue);
    });

    testWidgets('stops after the idle window with no input', (tester) async {
      await _pumpCanvas(tester);
      await _goIdle(tester);

      expect(_ticking(tester), isFalse);
      expect(tester.binding.hasScheduledFrame, isFalse);
      // And it stays at rest.
      await tester.pump(const Duration(seconds: 5));
      expect(_ticking(tester), isFalse);
    });

    testWidgets('pumpAndSettle now settles on the canvas', (tester) async {
      await _pumpCanvas(tester);
      await tester.pumpAndSettle();
      expect(_ticking(tester), isFalse);
    });

    testWidgets('a pointer down restarts the loop immediately', (tester) async {
      await _pumpCanvas(tester);
      await _goIdle(tester);
      expect(_ticking(tester), isFalse);

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(GalaxyInteractiveCanvas)),
      );
      // On the down event itself, before any frame or gesture decision.
      expect(_ticking(tester), isTrue);

      // A finger held still keeps it awake past the window.
      await _goIdle(tester);
      expect(_ticking(tester), isTrue);

      await gesture.up();
      await _goIdle(tester);
      expect(_ticking(tester), isFalse);
    });

    testWidgets('a programmatic resetView restarts the loop', (tester) async {
      final harness = await _pumpCanvas(tester);
      await _goIdle(tester);
      expect(_ticking(tester), isFalse);

      harness.camera.resetView();
      expect(_ticking(tester), isTrue);

      // Once the 550ms fly has landed the camera is still, but the render
      // loop's idle window started over with the fly.
      await _run(tester, const Duration(seconds: 2));
      expect(harness.camera.isAnimating, isFalse);
      expect(_ticking(tester), isTrue);

      await _goIdle(tester);
      expect(_ticking(tester), isFalse);
    });

    testWidgets('a camera fly restarts the loop', (tester) async {
      final harness = await _pumpCanvas(tester);
      await _goIdle(tester);

      harness.camera.flyTo(const Offset(80, 40), targetZoom: 1.4);
      expect(_ticking(tester), isTrue);
      await _run(tester, const Duration(seconds: 2));
      expect(_ticking(tester), isTrue);
    });

    testWidgets('a drag right after idle moves the camera exactly as when awake',
        (tester) async {
      Future<Offset> dragDelta({required bool idleFirst}) async {
        final harness = await _pumpCanvas(tester);
        if (idleFirst) {
          await _goIdle(tester);
          expect(_ticking(tester), isFalse);
        } else {
          await _run(tester, const Duration(seconds: 1));
          expect(_ticking(tester), isTrue);
        }
        final before = harness.camera.translation;
        final gesture = await tester.startGesture(
          tester.getCenter(find.byType(GalaxyInteractiveCanvas)),
        );
        for (var i = 0; i < 6; i++) {
          await gesture.moveBy(const Offset(12, 8));
          await tester.pump(const Duration(milliseconds: 16));
        }
        final after = harness.camera.translation;
        await gesture.up();
        await tester.pumpWidget(const SizedBox());
        return after - before;
      }

      final awake = await dragDelta(idleFirst: false);
      final idle = await dragDelta(idleFirst: true);
      expect(awake.distance, greaterThan(0));
      expect(idle, awake);
    });

    testWidgets('waking does not replay the rest as a jump in the orbits',
        (tester) async {
      final harness = await _pumpCanvas(tester);
      await _goIdle(tester);
      expect(_ticking(tester), isFalse);

      final app = harness.firstCoreApp;
      final angleAtRest = app.orbitalAngle;
      await tester.pump(const Duration(seconds: 60));

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(GalaxyInteractiveCanvas)),
      );
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      await gesture.up();

      // Three 16ms frames at most, not the minute spent resting.
      final maxStep = app.orbitalSpeed * 60 * 0.05;
      expect((app.orbitalAngle - angleAtRest).abs(), lessThanOrEqualTo(maxStep));
    });

    testWidgets('unmuting after an overlay resumes without a time jump',
        (tester) async {
      final harness = await _pumpCanvas(tester);
      await _run(tester, const Duration(seconds: 1));

      harness.tickerEnabled.value = false;
      await tester.pump(const Duration(milliseconds: 16));
      final app = harness.firstCoreApp;
      final angleMuted = app.orbitalAngle;
      await tester.pump(const Duration(seconds: 60));
      expect(app.orbitalAngle, angleMuted);

      harness.tickerEnabled.value = true;
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(_ticking(tester), isTrue);
      final maxStep = app.orbitalSpeed * 60 * 0.05;
      expect((app.orbitalAngle - angleMuted).abs(), lessThanOrEqualTo(maxStep));
    });

    testWidgets('reduce motion still never runs the loop', (tester) async {
      final harness = await _pumpCanvas(tester, reduceMotion: true);
      expect(_ticking(tester), isFalse);

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(GalaxyInteractiveCanvas)),
      );
      expect(_ticking(tester), isFalse);
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 16));

      // The camera still animates its own fly; the render loop stays off.
      harness.camera.resetView();
      await _run(tester, const Duration(seconds: 1));
      expect(harness.camera.isAnimating, isFalse);
      expect(_ticking(tester), isFalse);
    });
  });
}
