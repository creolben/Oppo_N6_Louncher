import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mylauncher/core/foldable_controller.dart';
import 'package:mylauncher/core/launcher_bridge.dart';
import 'package:mylauncher/features/lockscreen/cosmic_lock_screen.dart';
import 'package:mylauncher/main.dart';
import 'package:mylauncher/ui/widgets/search_overlay.dart';

/// The lock panel must keep hearing the platform's unlock.
///
/// The overlays used to be unkeyed siblings in one Stack, so closing one while
/// the panel was up shifted the panel into another element slot: a fresh panel
/// state was created, and the old state's dispose then nulled the static
/// unlock listeners the new one had just installed. The panel never cleared.

/// Delivers [method] the way the platform does, over the apps channel.
Future<void> _platformCall(WidgetTester tester, String method) async {
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    'com.launcher.chronofold/apps',
    const StandardMethodCodec().encodeMethodCall(MethodCall(method)),
    (_) {},
  );
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _pumpHome(WidgetTester tester) async {
  await tester.pumpWidget(ChronoFoldApp(isKeyguardLocked: () async => false));
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  testWidgets(
    'a disposed panel does not clear the unlock listener of its successor',
    (tester) async {
      var firstUnlocked = false;
      var secondUnlocked = false;
      Widget panel(Key key, VoidCallback onUnlock) => MaterialApp(
        home: Scaffold(
          body: CosmicLockScreen(
            key: key,
            foldable: FoldableController(),
            apps: const [],
            onUnlock: onUnlock,
            isKeyguardLocked: () async => true,
          ),
        ),
      );

      await tester.pumpWidget(
        panel(const ValueKey('first'), () => firstUnlocked = true),
      );
      await tester.pump(const Duration(milliseconds: 16));

      // Swapped in one frame: the new panel's initState installs its
      // listeners before the old panel's dispose runs.
      await tester.pumpWidget(
        panel(const ValueKey('second'), () => secondUnlocked = true),
      );
      await tester.pump(const Duration(milliseconds: 16));

      LauncherBridge.dispatchUserPresentForTesting();
      await _settle(tester);

      expect(secondUnlocked, isTrue);
      expect(firstUnlocked, isFalse);
    },
  );

  testWidgets('Back while locked leaves search open under the panel', (
    tester,
  ) async {
    await _pumpHome(tester);

    await tester.tap(find.byTooltip('Search apps'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(SearchOverlay), findsOneWidget);

    await _platformCall(tester, 'lockScreen');
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(CosmicLockScreen), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(CosmicLockScreen), findsOneWidget);
    expect(find.byType(SearchOverlay), findsOneWidget);
  });

  testWidgets('Home while locked leaves search open under the panel', (
    tester,
  ) async {
    await _pumpHome(tester);

    await tester.tap(find.byTooltip('Search apps'));
    await tester.pump(const Duration(milliseconds: 300));
    await _platformCall(tester, 'lockScreen');
    await tester.pump(const Duration(milliseconds: 100));

    await _platformCall(tester, 'onHomePressed');
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(CosmicLockScreen), findsOneWidget);
    expect(find.byType(SearchOverlay), findsOneWidget);
  });

  testWidgets(
    'the panel keeps its state when an overlay beneath it closes, and clears on unlock',
    (tester) async {
      await _pumpHome(tester);

      // Search open, then locked: search sits beneath the panel.
      await tester.tap(find.byTooltip('Search apps'));
      await tester.pump(const Duration(milliseconds: 300));
      await _platformCall(tester, 'lockScreen');
      await tester.pump(const Duration(milliseconds: 100));
      final State panelState = tester.state(find.byType(CosmicLockScreen));

      // Close the overlay beneath the panel through the search surface's own
      // close path, the one route that can still do it while locked.
      final SearchOverlay overlay = tester.widget(find.byType(SearchOverlay));
      overlay.onClose();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byType(SearchOverlay), findsNothing);
      expect(
        identical(tester.state(find.byType(CosmicLockScreen)), panelState),
        isTrue,
        reason: 'the panel was rebuilt as a new state',
      );

      LauncherBridge.dispatchUserPresentForTesting();
      await _settle(tester);

      expect(find.byType(CosmicLockScreen), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
