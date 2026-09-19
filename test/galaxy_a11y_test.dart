import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mylauncher/canvas/camera_controller.dart';
import 'package:mylauncher/canvas/galaxy_interactive_canvas.dart';
import 'package:mylauncher/core/foldable_controller.dart';
import 'package:mylauncher/core/galaxy_layout_engine.dart';
import 'package:mylauncher/models/app_entry.dart';

/// The galaxy home screen paints everything into one canvas, so without an
/// explicit semantic layer a screen reader finds nothing to focus and the core
/// task — launch an app — is impossible. These tests hold that layer in place.

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

/// Captures what [LauncherBridge.launchApp] was asked to open: on a non-Android
/// test host the bridge prints instead of calling the platform.
class _LaunchSpy {
  final List<String> lines = [];
  late void Function(String? message, {int? wrapWidth}) _original;

  Future<void> capture(Future<void> Function() body) async {
    _original = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) lines.add(message);
    };
    try {
      await body();
    } finally {
      debugPrint = _original;
    }
  }

  bool launched(String packageName) =>
      lines.any((l) => l.startsWith('Simulating launching app:') &&
          l.contains('($packageName)'));
}

class _Harness {
  final FoldableController foldable = FoldableController();
  final CameraController camera = CameraController();
  final GalaxyLayoutEngine layoutEngine = GalaxyLayoutEngine();

  /// The canvas only exposes the apps of the constellation that is open, so
  /// tests open the centre one explicitly rather than depending on a default.
  void openCore(List<AppEntry> apps) {
    layoutEngine.assignApps(apps);
    layoutEngine.constellations.firstWhere((c) => c.id == 'core').isExpanded =
        true;
  }
}

Future<_Harness> _pumpCanvas(WidgetTester tester, List<AppEntry> apps) async {
  final harness = _Harness();
  harness.openCore(apps);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: GalaxyInteractiveCanvas(
          apps: apps,
          foldable: harness.foldable,
          camera: harness.camera,
          layoutEngine: harness.layoutEngine,
        ),
      ),
    ),
  );
  // A fixed pump: the render loop never settles, so pumpAndSettle would hang.
  await tester.pump(const Duration(milliseconds: 16));
  return harness;
}

void main() {
  group('Galaxy canvas screen reader support', () {
    testWidgets('exposes every app of the open constellation as a node',
        (tester) async {
      final semantics = tester.ensureSemantics();
      await _pumpCanvas(tester, _coreApps());

      expect(find.bySemanticsLabel('Phone'), findsOneWidget);
      expect(find.bySemanticsLabel('Messages'), findsOneWidget);

      semantics.dispose();
    });

    testWidgets('exposes the constellation itself so a reader can open it',
        (tester) async {
      final semantics = tester.ensureSemantics();
      final harness = _Harness();
      harness.layoutEngine.assignApps(_coreApps());
      // Deliberately collapsed: a reader must still have a way in, because the
      // hub is the only thing on screen to focus.
      final core =
          harness.layoutEngine.constellations.firstWhere((c) => c.id == 'core');
      core.isExpanded = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GalaxyInteractiveCanvas(
              apps: _coreApps(),
              foldable: harness.foldable,
              camera: harness.camera,
              layoutEngine: harness.layoutEngine,
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 16));

      expect(find.bySemanticsLabel(core.name), findsOneWidget);
      // Its apps are condensed into the hub, so they must not be announced as
      // separate targets sitting on top of each other.
      expect(find.bySemanticsLabel('Phone'), findsNothing);

      semantics.dispose();
    });

    testWidgets('activating an app node launches that app', (tester) async {
      final semantics = tester.ensureSemantics();
      final spy = _LaunchSpy();
      await _pumpCanvas(tester, _coreApps());

      await spy.capture(() async {
        final node = tester.getSemantics(find.bySemanticsLabel('Phone'));
        tester.binding.pipelineOwner.semanticsOwner!
            .performAction(node.id, SemanticsAction.tap);
        await tester.pump();
        // The launch is deliberately deferred behind the tap animation.
        await tester.pump(const Duration(milliseconds: 350));
      });

      expect(spy.launched('com.test.phone'), isTrue,
          reason: 'a TalkBack activation must reach the same launch path');
      expect(spy.launched('com.test.messages'), isFalse);

      semantics.dispose();
    });

    testWidgets('nodes are actionable and describe what they will do',
        (tester) async {
      final semantics = tester.ensureSemantics();
      await _pumpCanvas(tester, _coreApps());

      // A label alone leaves a reader unable to act; the node must carry the
      // tap action TalkBack invokes on double-tap.
      final appNode =
          tester.getSemantics(find.bySemanticsLabel('Phone')).getSemanticsData();
      expect(appNode.hasAction(SemanticsAction.tap), isTrue);

      final hub = tester
          .getSemantics(find.bySemanticsLabel('Essentials'))
          .getSemanticsData();
      expect(hub.hasAction(SemanticsAction.tap), isTrue,
          reason: 'the hub is the only way to open a collapsed constellation');
      expect(hub.hint, contains('apps'));

      semantics.dispose();
    });

    testWidgets('nodes sit over the apps and do not swallow canvas touches',
        (tester) async {
      final semantics = tester.ensureSemantics();
      final spy = _LaunchSpy();
      await _pumpCanvas(tester, _coreApps());

      // Touch exploration finds a node by where it sits on screen, so the focus
      // rectangle must be over the painted bubble rather than at the origin.
      final rect = tester.getRect(find.bySemanticsLabel('Phone'));
      expect(rect.center.dx, greaterThan(0));
      expect(rect.center.dy, greaterThan(0));

      await spy.capture(() async {
        // A real finger on the same spot must still reach the canvas gesture
        // handler: the accessibility layer is an overlay, not an obstacle.
        await tester.tapAt(rect.center);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));
      });

      expect(spy.launched('com.test.phone'), isTrue,
          reason: 'the semantics overlay swallowed a canvas tap');

      semantics.dispose();
    });
  });
}
