import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mylauncher/core/foldable_controller.dart';
import 'package:mylauncher/core/galaxy_layout_engine.dart';
import 'package:mylauncher/canvas/galaxy_interactive_canvas.dart';
import 'package:mylauncher/models/app_entry.dart';
import 'package:mylauncher/ui/screens/folded_cover_screen.dart';
import 'package:mylauncher/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final testApps = [
    AppEntry(
      packageName: 'com.test.phone',
      label: 'Phone',
      category: AppCategory.core,
      accentColor: const Color(0xFF4CAF50),
    ),
    AppEntry(
      packageName: 'com.test.messages',
      label: 'Messages',
      category: AppCategory.core,
      accentColor: const Color(0xFF2196F3),
    ),
    AppEntry(
      packageName: 'com.test.chat',
      label: 'Chat',
      category: AppCategory.social,
      accentColor: const Color(0xFFFF4081),
    ),
    AppEntry(
      packageName: 'com.test.work',
      label: 'Workspace',
      category: AppCategory.productivity,
      accentColor: const Color(0xFF00E5FF),
    ),
  ];

  group('FoldedCoverScreen Widget Tests', () {
    testWidgets('Renders all folded screen elements on narrow viewport', (tester) async {
      // Set narrow foldable cover screen dimensions (360 x 800)
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final foldable = FoldableController();
      foldable.setPosture(DevicePosture.folded);

      final layoutEngine = GalaxyLayoutEngine();
      layoutEngine.assignApps(testApps);

      await tester.pumpWidget(
        MaterialApp(
          home: FoldedCoverScreen(
            apps: testApps,
            foldable: foldable,
            layoutEngine: layoutEngine,
            onOpenSearch: () {},
            onOpenSettings: () {},
            onLock: () {},
          ),
        ),
      );
      await tester.pump();

      // Check header elements
      expect(find.text('COVER'), findsOneWidget);
      expect(find.text('ESSENTIALS'), findsOneWidget);
      expect(find.text('SECTORS'), findsOneWidget);

      // Check search pill
      expect(find.text('Search apps or cosmos...'), findsOneWidget);

      // Check Core apps rendered
      expect(find.text('Phone'), findsOneWidget);
      expect(find.text('Messages'), findsOneWidget);

      // Check dock icons
      expect(find.byIcon(Icons.search_rounded), findsWidgets);
      expect(find.byIcon(Icons.splitscreen_rounded), findsOneWidget);
      expect(find.byIcon(Icons.lock_outline_rounded), findsOneWidget);
      expect(find.byIcon(Icons.settings_outlined), findsOneWidget);
    });

    testWidgets('Tapping sector chips switches visible constellation apps', (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final foldable = FoldableController();
      foldable.setPosture(DevicePosture.folded);

      final layoutEngine = GalaxyLayoutEngine();
      layoutEngine.assignApps(testApps);

      await tester.pumpWidget(
        MaterialApp(
          home: FoldedCoverScreen(
            apps: testApps,
            foldable: foldable,
            layoutEngine: layoutEngine,
            onOpenSearch: () {},
            onOpenSettings: () {},
            onLock: () {},
          ),
        ),
      );
      await tester.pump();

      // Tap on Connect sector chip
      final connectChip = find.text('Connect');
      expect(connectChip, findsOneWidget);
      await tester.tap(connectChip);
      await tester.pump();

      // The Connect sector should now be displayed
      expect(find.text('CONNECT'), findsOneWidget);
      expect(find.text('Chat'), findsOneWidget);
    });

    testWidgets('Tapping simulator toggle reveals fold posture controls', (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final foldable = FoldableController();
      foldable.setPosture(DevicePosture.folded);

      final layoutEngine = GalaxyLayoutEngine();
      layoutEngine.assignApps(testApps);

      await tester.pumpWidget(
        MaterialApp(
          home: FoldedCoverScreen(
            apps: testApps,
            foldable: foldable,
            layoutEngine: layoutEngine,
            onOpenSearch: () {},
            onOpenSettings: () {},
            onLock: () {},
          ),
        ),
      );
      await tester.pump();

      // Initially, controls sheet is not shown
      expect(find.text('Cover (0°)'), findsNothing);

      // Tap the simulator toggle in the bottom dock
      await tester.tap(find.byIcon(Icons.splitscreen_rounded));
      await tester.pump();

      // Fold controls should now be visible
      expect(find.text('Cover (0°)'), findsOneWidget);
      expect(find.text('Tabletop (90°)'), findsOneWidget);
      expect(find.text('Main (180°)'), findsOneWidget);
    });
  });

  group('ChronoFold App Adaptive Posture Switching Tests', () {
    testWidgets('Switches between FoldedCoverScreen and GalaxyInteractiveCanvas on fold/unfold', (tester) async {
      tester.view.physicalSize = const Size(700, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(const ChronoFoldApp());
      await tester.pump(const Duration(milliseconds: 100));

      // Initially wide flat mode -> GalaxyInteractiveCanvas is displayed
      expect(find.byType(GalaxyInteractiveCanvas), findsOneWidget);
      expect(find.byType(FoldedCoverScreen), findsNothing);

      // Now simulate folding the device by resizing viewport to tall narrow cover screen
      tester.view.physicalSize = const Size(360, 800);
      await tester.pumpWidget(const ChronoFoldApp());
      await tester.pump(const Duration(milliseconds: 500));

      // Posture detection switches to folded -> FoldedCoverScreen is displayed
      expect(find.byType(FoldedCoverScreen), findsOneWidget);
      expect(find.byType(GalaxyInteractiveCanvas), findsNothing);
    });
  });
}
