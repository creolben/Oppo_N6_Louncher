import 'package:flutter_test/flutter_test.dart';
import 'package:mylauncher/features/shopping/ui/shopping_surface.dart';
import 'package:mylauncher/main.dart';

void main() {
  testWidgets('system Back closes the shopping surface before anything else',
      (WidgetTester tester) async {
    // Unlocked keyguard so the home surface, not the lock panel, is showing.
    await tester.pumpWidget(
      ChronoFoldApp(isKeyguardLocked: () async => false),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(ChronoFoldHomeScreen), findsOneWidget);
    expect(find.byType(ShoppingSurface), findsNothing);

    // Open the shopping surface from the cockpit shelf.
    await tester.tap(find.byTooltip('Shopping list'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(ShoppingSurface), findsOneWidget);

    // Back is consumed by the shopping surface first: it must close rather than
    // recenter the galaxy and leave the surface up.
    await tester.binding.handlePopRoute();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(ShoppingSurface), findsNothing);
    expect(find.byType(ChronoFoldHomeScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
