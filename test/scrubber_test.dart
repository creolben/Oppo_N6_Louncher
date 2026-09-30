import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mylauncher/canvas/camera_controller.dart';
import 'package:mylauncher/core/galaxy_layout_engine.dart';
import 'package:mylauncher/models/app_entry.dart';
import 'package:mylauncher/ui/widgets/search_overlay.dart';

/// The A-Z rail used to be 27 taps on ~13px glyphs. It is now one drag surface
/// with a 48dp-wide corridor, so a finger can scrub without aiming. These hold
/// that: the corridor has to be where the rail is, and dragging it has to
/// actually move the list.

/// Enough apps, spread across the alphabet, that the results list really scrolls.
List<AppEntry> _manyApps() => [
      for (final letter in 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'.split(''))
        for (int i = 0; i < 3; i++)
          AppEntry(
            packageName: 'com.test.${letter.toLowerCase()}$i',
            label: '$letter${i}pp',
            category: AppCategory.tools,
          ),
    ];

Future<void> _pumpOverlay(
  WidgetTester tester,
  Size size, {
  double keyboardInset = 0,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  tester.view.viewInsets = FakeViewPadding(bottom: keyboardInset);
  addTearDown(tester.view.reset);

  final engine = GalaxyLayoutEngine()..assignApps(_manyApps());

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SearchOverlay(
          allApps: _manyApps(),
          camera: CameraController(),
          layoutEngine: engine,
          onClose: () {},
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// The results list's scroll offset — the observable that proves the rail did
/// something.
double _scrollOffset(WidgetTester tester) {
  final scrollable = tester.state<ScrollableState>(
    find
        .descendant(of: find.byType(GridView), matching: find.byType(Scrollable))
        .first,
  );
  return scrollable.position.pixels;
}

void main() {
  group('A-Z scrubber rail', () {
    testWidgets('dragging the rail corridor scrubs the list',
        (tester) async {
      const size = Size(400, 800);
      await _pumpOverlay(tester, size);

      expect(_scrollOffset(tester), 0, reason: 'list should start at the top');

      // The corridor is 48dp wide against the right edge, vertically centred.
      final corridorX = size.width - 24;
      await tester.dragFrom(
        Offset(corridorX, size.height * 0.5),
        const Offset(0, 90),
      );
      await tester.pumpAndSettle();

      expect(
        _scrollOffset(tester),
        greaterThan(0),
        reason: 'dragging the rail down did not advance the list',
      );
    });

    testWidgets('the drag corridor is 48dp wide', (tester) async {
      const size = Size(400, 800);
      await _pumpOverlay(tester, size);

      // A drag that starts 47dp from the edge must still land on the rail,
      // because that is the width the corridor promises.
      final corridorX = size.width - 47;
      await tester.dragFrom(
        Offset(corridorX, size.height * 0.5),
        const Offset(0, 90),
      );
      await tester.pumpAndSettle();

      expect(_scrollOffset(tester), greaterThan(0),
          reason: 'the corridor is narrower than 48dp in practice');
    });

    testWidgets('every letter is still individually tappable',
        (tester) async {
      await _pumpOverlay(tester, const Size(400, 800));

      // Letters stay reachable as individual targets, which is what a screen
      // reader navigates; the drag is for fingers.
      expect(find.text('A'), findsAtLeastNWidgets(1));
      expect(find.text('Z'), findsAtLeastNWidgets(1));

      await tester.tap(find.text('Z'));
      await tester.pumpAndSettle();

      expect(_scrollOffset(tester), greaterThan(0),
          reason: 'tapping the Z rail letter did not jump the list');
    });

    testWidgets('the rail shrinks instead of overflowing with the keyboard up',
        (tester) async {
      // The cover display with the keyboard up: 27 fixed 12dp rows no longer
      // fit, which used to overflow the rail's column.
      await _pumpOverlay(tester, const Size(351, 805), keyboardInset: 300);

      expect(
        tester.takeException(),
        isNull,
        reason: 'the rail overflowed its column with the keyboard up',
      );

      // The rows are shorter now, but a tap still maps to the letter under
      // the finger: the rail's vertical middle is index 13, 'M'.
      final rail = find.byWidgetPredicate(
        (w) => w is GestureDetector && w.onVerticalDragUpdate != null,
      );
      expect(rail, findsOneWidget);
      await tester.tapAt(tester.getRect(rail).center);
      await tester.pumpAndSettle();

      expect(
        find.text('M0pp'),
        findsOneWidget,
        reason: 'a tap at the rail middle did not jump to M',
      );
    });

    testWidgets('the results never paint under the rail', (tester) async {
      // The rail is a 48dp overlay on the right edge; the grid must reserve
      // that width so its right column cannot slide underneath it.
      await _pumpOverlay(tester, const Size(351, 805));

      final rail = find.byWidgetPredicate(
        (w) => w is GestureDetector && w.onVerticalDragUpdate != null,
      );
      expect(rail, findsOneWidget);
      final double railLeft = tester.getRect(rail).left;

      final tiles = find.descendant(
        of: find.byType(GridView),
        matching: find.byType(InkWell),
      );
      expect(tiles, findsWidgets);
      for (int i = 0; i < tiles.evaluate().length; i++) {
        expect(
          tester.getRect(tiles.at(i)).right,
          lessThanOrEqualTo(railLeft + 0.001),
          reason: 'a grid tile paints under the A-Z rail',
        );
      }
    });
  });
}
