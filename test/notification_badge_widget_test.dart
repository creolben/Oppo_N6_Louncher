import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mylauncher/core/foldable_controller.dart';
import 'package:mylauncher/core/galaxy_layout_engine.dart';
import 'package:mylauncher/models/app_entry.dart';
import 'package:mylauncher/ui/screens/folded_cover_screen.dart';
import 'package:mylauncher/ui/widgets/notification_badge.dart';

/// A cover-grid app with unread notifications must both paint its badge and say
/// the count out loud; these tests pin the two together.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  List<AppEntry> apps() => [
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
          notificationCount: 3,
        ),
        AppEntry(
          packageName: 'com.test.chat',
          label: 'Chat',
          category: AppCategory.social,
          accentColor: const Color(0xFFFF4081),
        ),
      ];

  Future<void> pump(WidgetTester tester, List<AppEntry> entries) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final foldable = FoldableController();
    foldable.setPosture(DevicePosture.folded);
    final layoutEngine = GalaxyLayoutEngine();
    layoutEngine.assignApps(entries);

    await tester.pumpWidget(
      MaterialApp(
        home: FoldedCoverScreen(
          apps: entries,
          foldable: foldable,
          layoutEngine: layoutEngine,
          onOpenSearch: () {},
          onOpenSettings: () {},
          onLock: () {},
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('a cover-grid app with notifications paints its badge',
      (tester) async {
    final entries = apps();
    await pump(tester, entries);

    expect(
      find.byWidgetPredicate(
        (widget) => widget is NotificationBadge && widget.count == 3,
      ),
      findsOneWidget,
    );
    expect(find.text('3'), findsOneWidget);
    // The un-badged app keeps a clean tile.
    expect(
      find.byWidgetPredicate(
        (widget) => widget is NotificationBadge && widget.count > 0,
      ),
      findsOneWidget,
    );
  });

  testWidgets('the app semantics label carries the notification count',
      (tester) async {
    final semantics = tester.ensureSemantics();
    await pump(tester, apps());

    expect(
      find.bySemanticsLabel('Open Messages, 3 notifications'),
      findsOneWidget,
    );
    // An app with nothing unread keeps its plain label.
    expect(find.bySemanticsLabel('Open Phone'), findsOneWidget);

    semantics.dispose();
  });
}
