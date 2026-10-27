import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mylauncher/core/galaxy_layout_engine.dart';
import 'package:mylauncher/models/app_entry.dart';
import 'package:mylauncher/ui/theme/luminous_home_theme.dart';
import 'package:mylauncher/ui/widgets/app_action_dialog.dart';

/// Hiding an app is reversible, so the dialog styles it as a neutral action
/// and offers Undo afterwards instead of treating it as destructive.
void main() {
  final app = AppEntry(
    packageName: 'com.test.notes',
    label: 'Notes',
    category: AppCategory.productivity,
  );

  testWidgets('Hide app is neutral and its Undo unhides the app', (
    tester,
  ) async {
    final engine = GalaxyLayoutEngine()..assignApps([app]);
    var completed = 0;

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
                    layoutEngine: engine,
                    onActionCompleted: () => completed++,
                    loadShortcuts: (_) async => const [],
                  ),
                ),
                child: const Text('open dialog'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open dialog'));
    await tester.pumpAndSettle();

    expect(find.text('Hide from Galaxy'), findsNothing);
    final label = tester.widget<Text>(find.text('Hide app'));
    expect(label.style?.color, LuminousHomeTheme.textSecondary);

    await tester.tap(find.text('Hide app'));
    await tester.pumpAndSettle();
    expect(engine.isAppHidden(app.packageName), isTrue);
    expect(find.text('Notes hidden'), findsOneWidget);
    expect(completed, 1);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(engine.isAppHidden(app.packageName), isFalse);
    expect(completed, 2);
  });
}

