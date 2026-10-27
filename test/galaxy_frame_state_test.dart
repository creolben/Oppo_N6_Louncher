import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mylauncher/canvas/camera_controller.dart';
import 'package:mylauncher/canvas/galaxy_custom_painter.dart';
import 'package:mylauncher/canvas/galaxy_interactive_canvas.dart';
import 'package:mylauncher/core/foldable_controller.dart';
import 'package:mylauncher/core/galaxy_layout_engine.dart';
import 'package:mylauncher/models/app_entry.dart';

/// The canvas repaints through a listenable without rebuilding, so the
/// painter must read per-frame values live. It used to copy them at build
/// time, which froze every time-driven effect between rebuilds and left the
/// launch supernova unseen. Separately, reduce-motion runs no loop, so a hub
/// tap must land its expansion directly or groups can never open.

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

GalaxyCustomPainter _painter(WidgetTester tester) {
  final paint = tester.widget<CustomPaint>(
    find.descendant(
      of: find.byType(GalaxyInteractiveCanvas),
      matching: find.byType(CustomPaint),
    ).first,
  );
  return paint.painter! as GalaxyCustomPainter;
}

void main() {
  group('Painter reads the frame live', () {
    testWidgets('animation time advances on the same painter between rebuilds',
        (tester) async {
      await _pumpCanvas(tester);
      final painter = _painter(tester);
      final double before = painter.animationTime;

      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      expect(identical(_painter(tester), painter), isTrue,
          reason: 'the loop repaints without rebuilding the painter');
      expect(painter.animationTime, greaterThan(before + 0.4));
    });

    testWidgets('a launch shows its supernova on the next frame',
        (tester) async {
      final semantics = tester.ensureSemantics();
      await _pumpCanvas(tester);
      final painter = _painter(tester);
      expect(painter.activeSupernova, isNull);

      final node = tester.getSemantics(find.bySemanticsLabel('Phone'));
      tester.binding.pipelineOwner.semanticsOwner!
          .performAction(node.id, SemanticsAction.tap);
      await tester.pump(const Duration(milliseconds: 16));

      expect(_painter(tester).activeSupernova, isNotNull);
      expect(_painter(tester).focusedApp?.packageName, 'com.test.phone');

      // Let the deferred launch and the burst run out.
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(_painter(tester).activeSupernova, isNull);
      semantics.dispose();
    });
  });

  group('Reduce motion', () {
    testWidgets('a hub tap opens and closes the group at once', (tester) async {
      final harness = await _pumpCanvas(tester, reduceMotion: true);
      final core =
          harness.layoutEngine.constellations.firstWhere((c) => c.id == 'core');
      // The mount settled the resting arrangement: core open.
      expect(core.expansionProgress, closeTo(1.0, 1e-6));

      Future<void> tapHub() async {
        await tester.tapAt(harness.camera.worldToScreen(core.center));
        await tester.pump(const Duration(milliseconds: 16));
      }

      await tapHub();
      expect(core.isExpanded, isFalse);
      expect(core.expansionProgress, closeTo(0.0, 1e-6));

      await tapHub();
      expect(core.isExpanded, isTrue);
      expect(core.expansionProgress, closeTo(1.0, 1e-6));
      for (final app in core.apps) {
        expect((app.worldPosition - app.basePosition).distance, lessThan(1e-6));
      }
    });

    testWidgets('settling does not spin the orbits', (tester) async {
      final harness = await _pumpCanvas(tester, reduceMotion: true);
      final app = harness.firstCoreApp;
      final double angle = app.orbitalAngle;
      harness.layoutEngine.settleGalaxyMorph(
        posture: harness.foldable.posture,
        hingeAngle: harness.foldable.hingeAngle,
      );
      expect(app.orbitalAngle, angle);
    });

    testWidgets('a launch draws no frozen burst', (tester) async {
      final semantics = tester.ensureSemantics();
      await _pumpCanvas(tester, reduceMotion: true);
      final node = tester.getSemantics(find.bySemanticsLabel('Phone'));
      tester.binding.pipelineOwner.semanticsOwner!
          .performAction(node.id, SemanticsAction.tap);
      await tester.pump(const Duration(milliseconds: 16));
      expect(_painter(tester).activeSupernova, isNull);
      await tester.pump(const Duration(milliseconds: 400));
      semantics.dispose();
    });
  });
}
