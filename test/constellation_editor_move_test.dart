import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mylauncher/core/galaxy_layout_engine.dart';
import 'package:mylauncher/models/app_entry.dart';
import 'package:mylauncher/ui/widgets/constellation_editor_modal.dart';

void main() {
  testWidgets('constellation picker moves an Essentials app into Connect', (
    tester,
  ) async {
    final engine = GalaxyLayoutEngine();
    // A Connect app pinned into Essentials, as the reported bug describes.
    final photo = AppEntry(
      packageName: 'com.test.photo',
      label: 'Photo',
      category: AppCategory.social,
    );
    final chat = AppEntry(
      packageName: 'com.test.chat',
      label: 'Chat',
      category: AppCategory.social,
    );
    engine.assignApps([photo, chat]);
    engine.setCorePackageNames([photo.packageName]);

    final core = engine.constellations.firstWhere((c) => c.id == 'core');
    final social = engine.constellations.firstWhere((c) => c.id == 'social');
    expect(core.apps.map((a) => a.packageName), contains(photo.packageName));
    expect(
      social.apps.map((a) => a.packageName),
      isNot(contains(photo.packageName)),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ConstellationEditorModal(
            constellation: social,
            layoutEngine: engine,
            allApps: [photo, chat],
            onUpdated: () {},
          ),
        ),
      ),
    );

    // Open the add picker from the Connect editor.
    expect(find.text('Add app'), findsOneWidget);
    await tester.tap(find.text('Add app'));
    await tester.pumpAndSettle();

    // The Essentials app advertises its current group and a move affordance.
    expect(find.text('In Essentials'), findsOneWidget);
    expect(find.byIcon(Icons.swap_horiz_rounded), findsOneWidget);
    expect(find.byIcon(Icons.add_circle_outline_rounded), findsNothing);

    await tester.tap(find.text('In Essentials'));
    await tester.pumpAndSettle();

    expect(social.apps.map((a) => a.packageName), contains(photo.packageName));
    expect(
      core.apps.map((a) => a.packageName),
      isNot(contains(photo.packageName)),
    );
  });
}
