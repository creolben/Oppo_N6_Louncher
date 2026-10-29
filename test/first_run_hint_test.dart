import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mylauncher/main.dart';
import 'package:mylauncher/ui/widgets/first_run_hint_card.dart';

Future<void> _pumpHome(WidgetTester tester, {bool? dismissed}) async {
  await tester.pumpWidget(
    ChronoFoldApp(
      isKeyguardLocked: () async => false,
      firstRunHintDismissed: dismissed,
    ),
  );
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  group('first-run hint on the home screen', () {
    testWidgets('shows on a fresh install and hides on Got it',
        (tester) async {
      await _pumpHome(tester);

      expect(find.byType(FirstRunHintCard), findsOneWidget);
      expect(find.text('Swipe down to search'), findsOneWidget);
      expect(find.text('Tap a group to open it'), findsOneWidget);
      expect(find.text('Long-press an app for options'), findsOneWidget);

      await tester.tap(find.text('Got it'));
      // The exit fade runs on the galaxy's frames; give it a few.
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.byType(FirstRunHintCard), findsNothing);
    });

    testWidgets('stays hidden once the dismissal is stored', (tester) async {
      await _pumpHome(tester, dismissed: true);
      expect(find.byType(FirstRunHintCard), findsNothing);
    });

    testWidgets('names the notifications gesture when swipe-down is set so',
        (tester) async {
      await tester.pumpWidget(
        ChronoFoldApp(
          isKeyguardLocked: () async => false,
          swipeDownAction: 'notifications',
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Swipe down for notifications'), findsOneWidget);
    });

    testWidgets('is not drawn while search is open', (tester) async {
      await _pumpHome(tester);
      expect(find.byType(FirstRunHintCard), findsOneWidget);

      await tester.tap(find.byTooltip('Search apps'));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 16));
      expect(find.byType(FirstRunHintCard), findsNothing);
    });

    testWidgets('offers Set as default only while not the home app',
        (tester) async {
      var setDefault = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FirstRunHintCard(
              swipeDownLabel: 'Swipe down to search',
              onDismiss: () {},
              onSetDefault: () => setDefault++,
            ),
          ),
        ),
      );
      await tester.tap(find.text('Set as default'));
      expect(setDefault, 1);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FirstRunHintCard(
              swipeDownLabel: 'Swipe down to search',
              onDismiss: () {},
            ),
          ),
        ),
      );
      expect(find.text('Set as default'), findsNothing);
    });
  });
}
