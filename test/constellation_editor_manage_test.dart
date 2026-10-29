import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mylauncher/core/galaxy_layout_engine.dart';
import 'package:mylauncher/models/app_entry.dart';
import 'package:mylauncher/ui/widgets/constellation_editor_modal.dart';

void main() {
  final chat = AppEntry(
    packageName: 'com.test.chat',
    label: 'Chat',
    category: AppCategory.social,
  );
  final mail = AppEntry(
    packageName: 'com.test.mail',
    label: 'Mail',
    category: AppCategory.productivity,
  );

  Future<void> pumpEditor(
    WidgetTester tester,
    GalaxyLayoutEngine engine,
    String id,
  ) async {
    final constellation = engine.constellations.firstWhere((c) => c.id == id);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => ConstellationEditorModal(
                    constellation: constellation,
                    layoutEngine: engine,
                    allApps: [chat, mail],
                    onUpdated: () {},
                  ),
                ),
                child: const Text('edit'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('edit'));
    await tester.pumpAndSettle();
  }

  testWidgets('removing an app offers Undo, which puts it back', (
    tester,
  ) async {
    final engine = GalaxyLayoutEngine()..assignApps([chat, mail]);
    final group = engine.createCustomConstellation(
      name: 'Daily',
      primaryColor: Colors.teal,
      emblemIcon: Icons.star,
      packageNames: [chat.packageName, mail.packageName],
    );
    await pumpEditor(tester, engine, group.id);

    List<String> members() => engine.constellations
        .firstWhere((c) => c.id == group.id)
        .apps
        .map((a) => a.packageName)
        .toList();
    expect(members(), [chat.packageName, mail.packageName]);

    // The first close icon is the editor's own close button; the next one is
    // the first app's remove badge.
    await tester.tap(find.byIcon(Icons.close_rounded).at(1));
    await tester.pumpAndSettle();
    expect(members(), [mail.packageName]);
    expect(find.text('Chat removed from Daily'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(members(), [chat.packageName, mail.packageName]);
  });

  testWidgets('built-in groups do not offer rename or delete', (tester) async {
    final engine = GalaxyLayoutEngine()..assignApps([chat, mail]);
    await pumpEditor(tester, engine, 'social');
    expect(find.text('Rename'), findsNothing);
    expect(find.text('Delete group'), findsNothing);
  });

  testWidgets('a custom group can be renamed and deleted after confirming', (
    tester,
  ) async {
    final engine = GalaxyLayoutEngine()..assignApps([chat, mail]);
    final group = engine.createCustomConstellation(
      name: 'Daily',
      primaryColor: Colors.teal,
      emblemIcon: Icons.star,
      packageNames: [chat.packageName],
    );
    await pumpEditor(tester, engine, group.id);

    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Morning');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    final renamed = engine.constellations.firstWhere((c) => c.id == group.id);
    expect(renamed.name, 'Morning');
    expect(renamed.customPackageNames, [chat.packageName]);
    expect(find.text('Morning'), findsOneWidget);

    // Cancelling the confirmation keeps the group.
    await tester.tap(find.text('Delete group'));
    await tester.pumpAndSettle();
    expect(find.text('Delete “Morning”?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(engine.constellations.any((c) => c.id == group.id), isTrue);

    await tester.tap(find.text('Delete group'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(engine.constellations.any((c) => c.id == group.id), isFalse);
    // The editor closed with the group.
    expect(find.byType(ConstellationEditorModal), findsNothing);
  });
}
