import 'package:flutter_test/flutter_test.dart';
import 'package:mylauncher/main.dart';
import 'package:mylauncher/canvas/galaxy_interactive_canvas.dart';
import 'package:mylauncher/ui/widgets/comet_search_surface.dart';

void main() {
  testWidgets('system Back closes the comet search before resetting the camera',
      (tester) async {
    // Unlocked keyguard so the home surface, not the lock panel, is showing.
    await tester.pumpWidget(
      ChronoFoldApp(isKeyguardLocked: () async => false),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(ChronoFoldHomeScreen), findsOneWidget);
    expect(find.byType(CometSearchSurface), findsNothing);

    // Open the comet web-search surface from the cockpit bar.
    await tester.tap(find.byTooltip('Search the web'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(CometSearchSurface), findsOneWidget);

    // Back is consumed by the comet surface: it must close rather than recenter
    // the galaxy and leave the comet up.
    await tester.binding.handlePopRoute();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(CometSearchSurface), findsNothing);
    expect(find.byType(ChronoFoldHomeScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('system Back on the bare home surface leaves the galaxy alone',
      (tester) async {
    await tester.pumpWidget(
      ChronoFoldApp(isKeyguardLocked: () async => false),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));

    // Pan the galaxy away from its resting view.
    final GalaxyInteractiveCanvas canvas = tester
        .widget<GalaxyInteractiveCanvas>(find.byType(GalaxyInteractiveCanvas));
    canvas.camera.applyPan(const Offset(160, -90));
    await tester.pump();
    final Offset panned = canvas.camera.translation;

    // A native home ignores Back on its own surface: nothing recenters.
    await tester.binding.handlePopRoute();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    expect(canvas.camera.translation, panned);
    expect(find.byType(ChronoFoldHomeScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
