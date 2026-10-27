import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mylauncher/models/app_entry.dart';
import 'package:mylauncher/models/app_shortcut.dart';
import 'package:mylauncher/ui/widgets/app_action_dialog.dart';

/// The dialog grows its own shortcuts above the launcher's actions, loaded from
/// a bridge that a test supplies. These tests pin both the rows it shows and
/// that tapping one launches it through the injected bridge.
void main() {
  final app = AppEntry(
    packageName: 'com.test.messages',
    label: 'Messages',
    category: AppCategory.core,
    accentColor: const Color(0xFF2196F3),
  );

  List<AppShortcut> shortcuts() => const [
        AppShortcut(
          id: 'com.test.messages/compose',
          packageName: 'com.test.messages',
          shortLabel: 'New message',
          rank: 1,
        ),
        AppShortcut(
          id: 'com.test.messages/search',
          packageName: 'com.test.messages',
          longLabel: 'Search messages',
          rank: 2,
        ),
      ];

  Future<void> openDialog(
    WidgetTester tester, {
    required Future<List<AppShortcut>> Function(String) load,
    required Future<bool> Function(AppShortcut, {Rect? sourceBounds}) launch,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => AppActionDialog(
                    app: app,
                    loadShortcuts: load,
                    launchShortcut: launch,
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('shows the shortcuts the bridge returned above the actions',
      (tester) async {
    await openDialog(
      tester,
      load: (_) async => shortcuts(),
      launch: (_, {sourceBounds}) async => true,
    );

    expect(find.text('New message'), findsOneWidget);
    expect(find.text('Search messages'), findsOneWidget);
    // The launcher's own actions are still below them.
    expect(find.text('Open'), findsOneWidget);
    expect(find.text('App Details & Permissions'), findsOneWidget);
  });

  testWidgets('tapping a shortcut launches it and closes the dialog',
      (tester) async {
    final launched = <String>[];
    await openDialog(
      tester,
      load: (_) async => shortcuts(),
      launch: (shortcut, {sourceBounds}) async {
        launched.add(shortcut.id);
        return true;
      },
    );

    await tester.tap(find.text('New message'));
    await tester.pumpAndSettle();

    expect(launched, ['com.test.messages/compose']);
    expect(find.byType(AppActionDialog), findsNothing);
  });

  testWidgets('a package with no shortcuts shows no shortcut row',
      (tester) async {
    await openDialog(
      tester,
      load: (_) async => const <AppShortcut>[],
      launch: (_, {sourceBounds}) async => true,
    );

    expect(find.byIcon(Icons.bolt_rounded), findsNothing);
    expect(find.text('Open'), findsOneWidget);
  });
}
