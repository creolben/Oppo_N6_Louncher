import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mylauncher/core/foldable_controller.dart';
import 'package:mylauncher/features/shopping/data/shopping_store.dart';
import 'package:mylauncher/features/shopping/models/quantity.dart';
import 'package:mylauncher/features/shopping/models/recipe.dart';
import 'package:mylauncher/features/shopping/models/unit.dart';
import 'package:mylauncher/features/shopping/parsing/document_parser.dart';
import 'package:mylauncher/features/shopping/shopping_controller.dart';
import 'package:mylauncher/features/shopping/ui/import_review_sheet.dart';
import 'package:mylauncher/features/shopping/ui/list_pane.dart';
import 'package:mylauncher/features/shopping/ui/lists_pane.dart';
import 'package:mylauncher/features/shopping/ui/quick_add_capsule.dart';
import 'package:mylauncher/features/shopping/ui/recipe_pane.dart';
import 'package:mylauncher/features/shopping/ui/shopping_surface.dart';
import 'package:mylauncher/ui/theme/luminous_home_theme.dart';

void main() {
  late Directory directory;
  late ShoppingStore store;
  late ShoppingController controller;

  setUp(() async {
    directory = Directory.systemTemp.createTempSync('shopping_ui_test');
    store = ShoppingStore(directoryPath: directory.path);
    controller = ShoppingController(store: store);
    await controller.load();
  });

  tearDown(() async {
    await controller.flush();
    controller.dispose();
    if (directory.existsSync()) {
      directory.deleteSync(recursive: true);
    }
  });

  Future<void> flushController(WidgetTester tester) async {
    await tester.runAsync(() => controller.flush());
  }

  void size(WidgetTester tester, Size value) {
    tester.view.physicalSize = value;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  FoldableController posture(DevicePosture devicePosture) {
    final FoldableController foldable = FoldableController();
    addTearDown(foldable.dispose);
    foldable.setPosture(devicePosture);
    return foldable;
  }

  Widget host(
    FoldableController foldable, {
    VoidCallback? onClose,
    double textScale = 1.0,
  }) {
    return MaterialApp(
      theme: LuminousHomeTheme.buildTheme(),
      builder: (BuildContext context, Widget? child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
          ),
          child: child!,
        );
      },
      home: Scaffold(
        body: ShoppingSurface(
          controller: controller,
          foldable: foldable,
          onClose: onClose ?? () {},
        ),
      ),
    );
  }

  group('ShoppingSurface layout', () {
    testWidgets('cover size uses the narrow single-column layout',
        (WidgetTester tester) async {
      size(tester, const Size(360, 800));
      controller.createList('Groceries');
      await flushController(tester);

      await tester.pumpWidget(host(posture(DevicePosture.folded)));
      await tester.pump();

      expect(find.byKey(const ValueKey<String>('shopping_narrow')),
          findsOneWidget);
      expect(find.byKey(const ValueKey<String>('shopping_wide')), findsNothing);
      expect(find.byType(ListsPane), findsNothing);
      expect(find.byType(QuickAddCapsule), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('unfolded size uses the two-pane layout',
        (WidgetTester tester) async {
      size(tester, const Size(900, 1000));
      controller.createList('Groceries');
      await flushController(tester);

      await tester.pumpWidget(host(posture(DevicePosture.flat)));
      await tester.pump();

      expect(find.byKey(const ValueKey<String>('shopping_wide')),
          findsOneWidget);
      expect(find.byType(ListsPane), findsOneWidget);
      expect(find.byType(ListPane), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('tabletop splits the list above the quick-add and recipe half',
        (WidgetTester tester) async {
      size(tester, const Size(700, 1000));
      controller.createList('Groceries');
      controller.quickAdd('2 kg chicken');
      controller.addRecipe(
        const Recipe(
          id: 'r1',
          title: 'Pancakes',
          baseServings: 4,
          targetServings: 4,
          ingredients: <Ingredient>[
            Ingredient(name: 'flour', quantity: Quantity(2, Unit.cup)),
          ],
        ),
      );
      await flushController(tester);

      await tester.pumpWidget(host(posture(DevicePosture.tabletop)));
      await tester.pump();

      expect(find.byKey(const ValueKey<String>('shopping_tabletop')),
          findsOneWidget);
      expect(find.byType(ListPane), findsOneWidget);
      expect(find.byType(QuickAddCapsule), findsOneWidget);
      expect(find.byType(RecipePane), findsOneWidget);

      // No crease is reported in the test host, so the split is the midpoint.
      final Rect tabletop =
          tester.getRect(find.byKey(const ValueKey<String>('shopping_tabletop')));
      final Rect list = tester.getRect(find.byType(ListPane));
      expect(list.height, closeTo(tabletop.height / 2, 2));
      expect(tester.takeException(), isNull);
    });

    testWidgets('cover size at 2.0 text scale renders without overflow',
        (WidgetTester tester) async {
      size(tester, const Size(360, 800));
      controller.createList('Groceries');
      controller.quickAdd('2 kg chicken');
      await flushController(tester);

      await tester.pumpWidget(
        host(posture(DevicePosture.folded), textScale: 2.0),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
    });
  });

  group('ShoppingSurface interactions', () {
    testWidgets('quick add adds an item and shows it under the right aisle',
        (WidgetTester tester) async {
      size(tester, const Size(360, 800));
      controller.createList('Groceries');
      await flushController(tester);

      await tester.pumpWidget(host(posture(DevicePosture.folded)));
      await tester.pump();

      await tester.enterText(find.byType(TextField), '2 kg chicken');
      await tester.pump();
      expect(find.textContaining('Meat & Fish'), findsWidgets);

      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      expect(controller.activeList!.items, hasLength(1));
      expect(find.text('chicken'), findsOneWidget);
      expect(find.text('Meat & Fish'), findsOneWidget);
      expect(find.text('2 kg'), findsOneWidget);
      await flushController(tester);
      expect(tester.takeException(), isNull);
    });

    testWidgets('toggling a row checks it and sinks it to Done',
        (WidgetTester tester) async {
      size(tester, const Size(360, 800));
      controller.createList('Groceries');
      controller.quickAdd('2 kg chicken');
      await flushController(tester);

      final SemanticsHandle semantics = tester.ensureSemantics();

      await tester.pumpWidget(host(posture(DevicePosture.folded)));
      await tester.pump();

      expect(find.text('Done · 1'), findsNothing);
      expect(
        find.bySemanticsLabel('2 kg chicken, unchecked'),
        findsOneWidget,
      );

      await tester.tap(find.text('chicken'));
      await tester.pump();
      expect(controller.activeList!.items.single.checked, isTrue);

      await tester.pump(const Duration(milliseconds: 240));
      expect(find.text('Done · 1'), findsOneWidget);
      expect(
        find.bySemanticsLabel('2 kg chicken, checked'),
        findsOneWidget,
      );
      semantics.dispose();
      await flushController(tester);
      expect(tester.takeException(), isNull);
    });

    testWidgets('servings stepper changes the scaled amounts',
        (WidgetTester tester) async {
      size(tester, const Size(900, 1000));
      controller.createList('Groceries');
      controller.addRecipe(
        const Recipe(
          id: 'r1',
          title: 'Pancakes',
          baseServings: 4,
          targetServings: 4,
          ingredients: <Ingredient>[
            Ingredient(name: 'eggs', quantity: Quantity(3, Unit.piece)),
          ],
        ),
      );
      await flushController(tester);

      await tester.pumpWidget(host(posture(DevicePosture.flat)));
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey<String>('recipe_tile_r1')));
      await tester.pump();
      expect(find.text('3 pieces'), findsOneWidget);

      await tester.tap(find.byTooltip('Increase servings'));
      await tester.pump();
      expect(controller.recipeById('r1')!.targetServings, 5);
      expect(find.text('4 pieces'), findsOneWidget);

      await tester.tap(find.byTooltip('Decrease servings'));
      await tester.pump();
      expect(controller.recipeById('r1')!.targetServings, 4);
      expect(find.text('3 pieces'), findsOneWidget);

      await flushController(tester);
      expect(tester.takeException(), isNull);
    });
  });

  group('ImportReviewSheet', () {
    testWidgets('imports only the selected lines', (WidgetTester tester) async {
      size(tester, const Size(360, 800));
      controller.createList('Groceries');
      await flushController(tester);

      final ParsedDocument document =
          const DocumentParser().parseDocument('Milk\nEggs\nBread');
      expect(document.items, hasLength(3));

      await tester.pumpWidget(
        MaterialApp(
          theme: LuminousHomeTheme.buildTheme(),
          home: Scaffold(
            body: ImportReviewSheet(
              document: document,
              onConfirm: (List<int> indices) =>
                  controller.importParsedDocument(document, indices),
            ),
          ),
        ),
      );
      await tester.pump();

      // Drop the middle line before importing.
      await tester.tap(find.text('Eggs'));
      await tester.pump();

      await tester.tap(find.text('Import 2 items'));
      await tester.pump();

      final Set<String> names = controller.activeList!.items
          .map((item) => item.name.toLowerCase())
          .toSet();
      expect(names, <String>{'milk', 'bread'});
      await flushController(tester);
      expect(tester.takeException(), isNull);
    });

    testWidgets('surface overflow pastes clipboard text into the review sheet',
        (WidgetTester tester) async {
      size(tester, const Size(360, 800));
      controller.createList('Groceries');
      await flushController(tester);

      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (MethodCall call) async {
          if (call.method == 'Clipboard.getData') {
            return <String, dynamic>{'text': 'Milk\nEggs'};
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );

      await tester.pumpWidget(host(posture(DevicePosture.folded)));
      await tester.pump();

      await tester.tap(find.byTooltip('Shopping options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Paste text'));
      await tester.pumpAndSettle();

      expect(find.byType(ImportReviewSheet), findsOneWidget);
      expect(find.text('Milk'), findsOneWidget);
      expect(find.text('Eggs'), findsOneWidget);
      await flushController(tester);
      expect(tester.takeException(), isNull);
    });
  });
}
