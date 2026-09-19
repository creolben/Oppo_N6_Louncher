import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mylauncher/core/foldable_controller.dart';
import 'package:mylauncher/features/lockscreen/cosmic_lock_screen.dart';
import 'package:mylauncher/models/app_entry.dart';

/// The lock screen's apps are painted into a canvas, so without a semantic
/// layer a screen reader cannot launch anything from it. These hold that layer
/// in place, and the stillness it depends on.

List<AppEntry> _apps() => [
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
      AppEntry(
        packageName: 'com.test.notes',
        label: 'Notes',
        category: AppCategory.tools,
        accentColor: Colors.amber,
      ),
    ];

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

Future<void> _pumpLockScreen(
  WidgetTester tester, {
  Future<bool> Function({String? appName})? authenticate,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: CosmicLockScreen(
          foldable: FoldableController(),
          apps: _apps(),
          onUnlock: () {},
          authenticate: authenticate,
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 16));
}

/// Finds the node a screen reader would actually land on, by walking the
/// semantics tree rather than the widget tree.
SemanticsNode? _nodeLabelled(WidgetTester tester, String label) {
  SemanticsNode? found;
  void visit(SemanticsNode node) {
    if (found != null) return;
    if (node.getSemanticsData().label == label) {
      found = node;
      return;
    }
    node.visitChildren((child) {
      visit(child);
      return true;
    });
  }

  final root = tester.binding.pipelineOwner.semanticsOwner?.rootSemanticsNode;
  if (root != null) visit(root);
  return found;
}

void main() {
  group('Lock screen screen reader support', () {
    testWidgets('exposes every app bubble as a focusable node', (tester) async {
      final semantics = tester.ensureSemantics();
      await _pumpLockScreen(tester);

      expect(find.bySemanticsLabel('Phone'), findsOneWidget);
      expect(find.bySemanticsLabel('Messages'), findsOneWidget);
      expect(find.bySemanticsLabel('Notes'), findsOneWidget);

      semantics.dispose();
    });

    testWidgets('bubble nodes are actionable and describe what they do',
        (tester) async {
      final semantics = tester.ensureSemantics();
      await _pumpLockScreen(tester);

      final data = tester
          .getSemantics(find.bySemanticsLabel('Notes'))
          .getSemanticsData();
      expect(data.hasAction(SemanticsAction.tap), isTrue,
          reason: 'a reader could hear the app but not open it');
      expect(data.hint, 'Open app');

      semantics.dispose();
    });

    testWidgets('activating a bubble node opens that app', (tester) async {
      final semantics = tester.ensureSemantics();
      final spy = _LaunchSpy();
      await _pumpLockScreen(
        tester,
        authenticate: ({String? appName}) async => true,
      );

      await spy.capture(() async {
        final node = tester.getSemantics(find.bySemanticsLabel('Notes'));
        tester.binding.pipelineOwner.semanticsOwner!
            .performAction(node.id, SemanticsAction.tap);
        // Authentication resolves, then the panel slides away before launch.
        for (int i = 0; i < 16; i++) {
          await tester.pump(const Duration(milliseconds: 40));
        }
      });

      expect(spy.launched('com.test.notes'), isTrue);
      expect(spy.launched('com.test.phone'), isFalse);

      semantics.dispose();
    });

    testWidgets('holds the bubbles still while a reader is active',
        (tester) async {
      // A moving target is not just hard to touch: its node rectangle would
      // have to be rebuilt every frame to stay truthful.
      final semantics = tester.ensureSemantics();
      await _pumpLockScreen(tester);
      await tester.pump(const Duration(milliseconds: 100));

      final before = tester
          .getRect(find.bySemanticsLabel('Phone'))
          .center;

      for (int i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 40));
      }

      final after = tester.getRect(find.bySemanticsLabel('Phone')).center;
      expect(after, equals(before),
          reason: 'the simulation kept running under the screen reader');

      semantics.dispose();
    });

    testWidgets('the SHAKE control is announced as a button', (tester) async {
      final semantics = tester.ensureSemantics();
      await _pumpLockScreen(tester);

      // Previously the text was readable but carried no button trait, so the
      // node a reader landed on could not be activated.
      final node = _nodeLabelled(tester, 'Scatter apps');
      expect(node, isNotNull, reason: 'no node carries the SHAKE label');
      expect(node!.getSemanticsData().hasAction(SemanticsAction.tap), isTrue,
          reason: 'the SHAKE control is announced but not actionable');

      semantics.dispose();
    });
  });
}
