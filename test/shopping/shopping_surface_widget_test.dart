import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mylauncher/core/foldable_controller.dart';
import 'package:mylauncher/features/shopping/data/shopping_store.dart';
import 'package:mylauncher/features/shopping/models/quantity.dart';
import 'package:mylauncher/features/shopping/models/recipe.dart';
import 'package:mylauncher/features/shopping/models/shopping_item.dart';
import 'package:mylauncher/features/shopping/models/shopping_list.dart';
import 'package:mylauncher/features/shopping/models/unit.dart';
import 'package:mylauncher/features/shopping/parsing/document_parser.dart';
import 'package:mylauncher/features/shopping/shopping_controller.dart';
import 'package:mylauncher/features/shopping/ui/import_review_sheet.dart';
import 'package:mylauncher/features/shopping/ui/list_pane.dart';
import 'package:mylauncher/features/shopping/ui/lists_pane.dart';
import 'package:mylauncher/features/shopping/ui/quick_add_capsule.dart';
import 'package:mylauncher/features/shopping/ui/recipe_pane.dart';
import 'package:mylauncher/features/shopping/ui/shopping_surface.dart';
import 'package:mylauncher/features/shopping/ui/unit_converter_sheet.dart';
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
    ValueChanged<bool>? onKeepScreenOn,
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
          onKeepScreenOn: onKeepScreenOn,
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

      expect(find.text('+ 1 checked item'), findsNothing);
      expect(
        find.bySemanticsLabel('2 kg chicken, unchecked'),
        findsOneWidget,
      );

      await tester.tap(find.text('chicken'));
      await tester.pump();
      expect(controller.activeList!.items.single.checked, isTrue);

      await tester.pump(const Duration(milliseconds: 240));
      expect(find.text('+ 1 checked item'), findsOneWidget);
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

  group('Keep-style list behaviors', () {
    testWidgets('the overflow offers the unit converter and it shows a result',
        (WidgetTester tester) async {
      size(tester, const Size(360, 800));
      controller.createList('Groceries');
      await flushController(tester);

      await tester.pumpWidget(host(posture(DevicePosture.folded)));
      await tester.pump();

      await tester.tap(find.byTooltip('Shopping options'));
      await tester.pumpAndSettle();
      expect(find.text('Unit converter'), findsOneWidget);

      await tester.tap(find.text('Unit converter'));
      await tester.pumpAndSettle();
      expect(find.byType(UnitConverterSheet), findsOneWidget);

      await tester.enterText(
        find.byKey(const ValueKey<String>('unit_converter_input')),
        '16',
      );
      await tester.pump();
      expect(find.text('453.592 g'), findsOneWidget);

      await flushController(tester);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the Done header collapses and expands the checked items',
        (WidgetTester tester) async {
      size(tester, const Size(360, 800));
      final ShoppingList list = controller.createList('Groceries');
      controller.quickAdd('2 kg chicken');
      controller.toggleChecked(list.id, controller.activeList!.items.single.id);
      await flushController(tester);

      await tester.pumpWidget(host(posture(DevicePosture.folded)));
      await tester.pump();

      expect(find.text('+ 1 checked item'), findsOneWidget);
      expect(find.text('chicken'), findsOneWidget);

      await tester.tap(find.text('+ 1 checked item'));
      await tester.pump();
      expect(controller.activeList!.checkedCollapsed, isTrue);
      expect(find.text('chicken'), findsNothing);
      expect(find.text('+ 1 checked item'), findsOneWidget);

      await tester.tap(find.text('+ 1 checked item'));
      await tester.pump();
      expect(controller.activeList!.checkedCollapsed, isFalse);
      expect(find.text('chicken'), findsOneWidget);

      await flushController(tester);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the unit chip overrides the parsed unit in the preview',
        (WidgetTester tester) async {
      size(tester, const Size(360, 800));
      controller.createList('Groceries');
      await flushController(tester);

      await tester.pumpWidget(host(posture(DevicePosture.folded)));
      await tester.pump();

      await tester.enterText(find.byType(TextField).first, '2 chicken');
      await tester.pump();
      expect(find.text('2 pieces chicken · Meat & Fish'), findsOneWidget);

      // A count amount shows the count chips; kg is behind "More".
      final Finder more = find.byKey(const ValueKey<String>('unit_chip_more'));
      await tester.ensureVisible(more);
      await tester.pumpAndSettle();
      await tester.tap(more);
      await tester.pumpAndSettle();

      final Finder kilograms = find.byKey(const ValueKey<String>('unit_chip_kg'));
      await tester.ensureVisible(kilograms);
      await tester.pumpAndSettle();
      await tester.tap(kilograms);
      await tester.pump();
      expect(find.text('2 kg chicken · Meat & Fish'), findsOneWidget);

      await flushController(tester);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the unit chip row is context aware and needs an amount',
        (WidgetTester tester) async {
      size(tester, const Size(360, 800));
      controller.createList('Groceries');
      await flushController(tester);

      await tester.pumpWidget(host(posture(DevicePosture.folded)));
      await tester.pump();

      final Finder field = find.byType(TextField).first;
      // Focus alone does not open the row.
      await tester.tap(field);
      await tester.pump();
      expect(find.byKey(const ValueKey<String>('unit_chip_pc')), findsNothing);

      await tester.enterText(field, 'milk');
      await tester.pump();
      expect(find.byKey(const ValueKey<String>('unit_chip_pc')), findsNothing);

      // A bare number shows the count/packaging family.
      await tester.enterText(field, '2 milk');
      await tester.pump();
      expect(find.byKey(const ValueKey<String>('unit_chip_pc')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('unit_chip_more')), findsOneWidget);

      // A mass parse shows the mass family.
      await tester.enterText(field, '2 kg flour');
      await tester.pump();
      expect(find.byKey(const ValueKey<String>('unit_chip_g')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('unit_chip_kg')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('unit_chip_pc')), findsNothing);

      // A volume parse shows the volume family.
      await tester.enterText(field, '2 cups water');
      await tester.pump();
      expect(find.byKey(const ValueKey<String>('unit_chip_ml')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('unit_chip_cup')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('unit_chip_g')), findsNothing);

      await flushController(tester);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the frozen toggle forces the Frozen aisle and then resets',
        (WidgetTester tester) async {
      size(tester, const Size(360, 800));
      controller.createList('Groceries');
      await flushController(tester);

      await tester.pumpWidget(host(posture(DevicePosture.folded)));
      await tester.pump();

      await tester.enterText(find.byType(TextField).first, '2 chicken');
      await tester.pump();
      expect(find.text('2 pieces chicken · Meat & Fish'), findsOneWidget);

      final Finder frozen =
          find.byKey(const ValueKey<String>('frozen_toggle'));
      expect(frozen, findsOneWidget);
      await tester.tap(frozen);
      await tester.pump();
      expect(find.text('2 pieces chicken · Frozen'), findsOneWidget);

      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(controller.activeList!.items.single.aisle, 'Frozen');

      // The toggle resets after submit, so the next entry is not frozen.
      await tester.enterText(find.byType(TextField).first, 'banana');
      await tester.pump();
      expect(find.text('banana · Produce'), findsOneWidget);

      await flushController(tester);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the preview chip shows a remembered aisle',
        (WidgetTester tester) async {
      size(tester, const Size(360, 800));
      final ShoppingList list = controller.createList('Groceries');
      controller.quickAdd('quinoa');
      controller.updateItem(
        list.id,
        controller.activeList!.items.single.copyWith(aisle: 'Pantry'),
      );
      await flushController(tester);

      await tester.pumpWidget(host(posture(DevicePosture.folded)));
      await tester.pump();

      await tester.enterText(find.byType(TextField).first, 'quinoa');
      await tester.pump();
      expect(find.text('quinoa · Pantry'), findsOneWidget);

      await flushController(tester);
      expect(tester.takeException(), isNull);
    });

    testWidgets('tapping the quantity text toggles the row instead of opening '
        'the converter', (WidgetTester tester) async {
      size(tester, const Size(360, 800));
      controller.createList('Groceries');
      controller.quickAdd('16 oz butter');
      await flushController(tester);

      final SemanticsHandle semantics = tester.ensureSemantics();
      await tester.pumpWidget(host(posture(DevicePosture.folded)));
      await tester.pump();
      expect(controller.activeList!.items.single.checked, isFalse);

      // The entered unit stays primary; the preferred system is the caption,
      // and both join the row's semantic label.
      expect(find.text('16 ounces'), findsOneWidget);
      expect(find.text('≈ 450 g'), findsOneWidget);
      expect(
        find.bySemanticsLabel('16 ounces ≈ 450 g butter, unchecked'),
        findsOneWidget,
      );

      await tester.tap(find.text('16 ounces').first);
      await tester.pump();

      expect(controller.activeList!.items.single.checked, isTrue);
      expect(find.byType(UnitConverterSheet), findsNothing);

      semantics.dispose();
      await flushController(tester);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the edit sheet Convert button opens the unit converter',
        (WidgetTester tester) async {
      size(tester, const Size(360, 800));
      controller.createList('Groceries');
      controller.quickAdd('2 kg chicken');
      await flushController(tester);

      await tester.pumpWidget(host(posture(DevicePosture.folded)));
      await tester.pump();

      await tester.longPress(find.text('chicken'));
      await tester.pumpAndSettle();

      final Finder convert =
          find.byKey(const ValueKey<String>('item_convert'));
      await tester.ensureVisible(convert);
      await tester.pumpAndSettle();
      await tester.tap(convert);
      await tester.pumpAndSettle();

      expect(find.byType(UnitConverterSheet), findsOneWidget);
      final TextField field = tester.widget<TextField>(
        find.byKey(const ValueKey<String>('unit_converter_input')),
      );
      expect(field.controller!.text, '2');

      await flushController(tester);
      expect(tester.takeException(), isNull);
    });
  });

  group('Keep-style sub-items and reordering', () {
    testWidgets('a child row renders indented under its parent',
        (WidgetTester tester) async {
      size(tester, const Size(360, 800));
      final ShoppingList list = controller.createList('Groceries');
      controller.addItem(
        list.id,
        const ShoppingItem(id: 'p', name: 'apple', aisle: 'Produce'),
      );
      controller.addItem(
        list.id,
        const ShoppingItem(id: 'c', name: 'banana', aisle: 'Produce'),
      );
      controller.indentItem(list.id, 'c');
      await flushController(tester);

      await tester.pumpWidget(host(posture(DevicePosture.folded)));
      await tester.pump();

      final double parentX = tester.getTopLeft(find.text('apple')).dx;
      final double childX = tester.getTopLeft(find.text('banana')).dx;
      expect(childX - parentX, closeTo(32, 1));
      expect(find.text('banana'), findsOneWidget);

      await flushController(tester);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Indent from the edit sheet moves the row under its parent',
        (WidgetTester tester) async {
      size(tester, const Size(360, 800));
      final ShoppingList list = controller.createList('Groceries');
      controller.addItem(
        list.id,
        const ShoppingItem(id: 'p', name: 'apple', aisle: 'Produce'),
      );
      controller.addItem(
        list.id,
        const ShoppingItem(id: 'c', name: 'banana', aisle: 'Produce'),
      );
      await flushController(tester);

      await tester.pumpWidget(host(posture(DevicePosture.folded)));
      await tester.pump();

      await tester.longPress(find.text('banana'));
      await tester.pumpAndSettle();
      expect(find.text('Indent'), findsOneWidget);

      final Finder indent = find.byKey(const ValueKey<String>('item_indent'));
      await tester.ensureVisible(indent);
      await tester.pumpAndSettle();
      await tester.tap(indent);
      await tester.pump();
      expect(controller.activeList!.itemById('c')!.parentId, 'p');

      // Close the sheet and confirm the row is now indented on the list.
      await tester.tap(find.byTooltip('Close edit item'));
      await tester.pumpAndSettle();

      final double parentX = tester.getTopLeft(find.text('apple')).dx;
      final double childX = tester.getTopLeft(find.text('banana')).dx;
      expect(childX - parentX, closeTo(32, 1));

      await flushController(tester);
      expect(tester.takeException(), isNull);
    });

    testWidgets('dragging the handle reorders rows in My order',
        (WidgetTester tester) async {
      size(tester, const Size(360, 800));
      final ShoppingList list = controller.createList('Groceries');
      controller.addItem(
        list.id,
        const ShoppingItem(id: 'a', name: 'apple', aisle: 'Produce'),
      );
      controller.addItem(
        list.id,
        const ShoppingItem(id: 'b', name: 'banana', aisle: 'Produce'),
      );
      controller.addItem(
        list.id,
        const ShoppingItem(id: 'c', name: 'carrot', aisle: 'Produce'),
      );
      controller.setSortMode(list.id, ShoppingSortMode.manual);
      await flushController(tester);

      await tester.pumpWidget(host(posture(DevicePosture.folded)));
      await tester.pump();

      final Finder handle =
          find.byKey(const ValueKey<String>('drag_handle_a'));
      expect(handle, findsOneWidget);

      final TestGesture gesture =
          await tester.startGesture(tester.getCenter(handle));
      await tester.pump();
      await gesture.moveBy(const Offset(0, 60));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      final List<String> ids = controller.activeList!.items
          .map((ShoppingItem item) => item.id)
          .toList();
      expect(ids, <String>['b', 'a', 'c']);

      await flushController(tester);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the Move down semantics action reorders the row',
        (WidgetTester tester) async {
      size(tester, const Size(360, 800));
      final ShoppingList list = controller.createList('Groceries');
      controller.addItem(
        list.id,
        const ShoppingItem(id: 'a', name: 'apple', aisle: 'Produce'),
      );
      controller.addItem(
        list.id,
        const ShoppingItem(id: 'b', name: 'banana', aisle: 'Produce'),
      );
      controller.addItem(
        list.id,
        const ShoppingItem(id: 'c', name: 'carrot', aisle: 'Produce'),
      );
      await flushController(tester);

      final SemanticsHandle semantics = tester.ensureSemantics();
      await tester.pumpWidget(host(posture(DevicePosture.folded)));
      await tester.pump();

      final SemanticsNode node = tester.getSemantics(
        find.bySemanticsLabel('apple, unchecked'),
      );
      final SemanticsData data = node.getSemanticsData();
      final int actionId = data.customSemanticsActionIds!.firstWhere(
        (int id) => CustomSemanticsAction.getAction(id)?.label == 'Move down',
      );
      tester.binding.pipelineOwner.semanticsOwner!.performAction(
        node.id,
        SemanticsAction.customAction,
        actionId,
      );
      await tester.pump();

      final List<String> ids = controller.activeList!.items
          .map((ShoppingItem item) => item.id)
          .toList();
      expect(ids, <String>['b', 'a', 'c']);

      semantics.dispose();
      await flushController(tester);
      expect(tester.takeException(), isNull);
    });
  });

  group('Header switcher, sort mode and store mode', () {
    testWidgets(
        'the header shows the active list name, progress and opens the switcher',
        (WidgetTester tester) async {
      size(tester, const Size(360, 800));
      final ShoppingList list = controller.createList('Hardware run');
      controller.addItem(
        list.id,
        const ShoppingItem(id: 'i1', name: 'screws', aisle: 'Other'),
      );
      controller.addItem(
        list.id,
        const ShoppingItem(id: 'i2', name: 'nails', aisle: 'Other'),
      );
      controller.toggleChecked(list.id, 'i1');
      await flushController(tester);

      final SemanticsHandle semantics = tester.ensureSemantics();
      await tester.pumpWidget(host(posture(DevicePosture.folded)));
      await tester.pump();

      expect(find.text('Hardware run'), findsOneWidget);
      expect(find.text('1 of 2'), findsOneWidget);
      expect(
        find.bySemanticsLabel('Switch list, current Hardware run, 1 of 2 done'),
        findsOneWidget,
      );

      await tester.tap(find.text('Hardware run'));
      await tester.pumpAndSettle();
      expect(find.byType(ListsPane), findsOneWidget);

      semantics.dispose();
      await flushController(tester);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the header ellipsizes a long name at 360dp without overflow',
        (WidgetTester tester) async {
      size(tester, const Size(360, 800));
      final ShoppingList list = controller.createList(
        'A very long shopping list name that cannot fit in the capsule',
      );
      for (var i = 0; i < 12; i++) {
        controller.addItem(
          list.id,
          ShoppingItem(id: 'i$i', name: 'item $i', aisle: 'Other'),
        );
      }
      await flushController(tester);

      await tester.pumpWidget(host(posture(DevicePosture.folded)));
      await tester.pump();

      expect(find.text('0 of 12'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await flushController(tester);
    });

    testWidgets('the overflow switches to My order and reveals drag handles',
        (WidgetTester tester) async {
      size(tester, const Size(360, 800));
      controller.createList('Groceries');
      controller.quickAdd('2 kg chicken');
      controller.quickAdd('milk');
      await flushController(tester);

      final String firstId = controller.activeList!.items.first.id;

      await tester.pumpWidget(host(posture(DevicePosture.folded)));
      await tester.pump();

      // By aisle: sticky headers, no drag handles.
      expect(find.byType(SliverPersistentHeader), findsWidgets);
      expect(
        find.byKey(ValueKey<String>('drag_handle_$firstId')),
        findsNothing,
      );

      await tester.tap(find.byTooltip('Shopping options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sort: My order'));
      await tester.pumpAndSettle();

      expect(controller.activeList!.sortMode, ShoppingSortMode.manual);
      expect(find.byType(SliverPersistentHeader), findsNothing);
      expect(
        find.byKey(ValueKey<String>('drag_handle_$firstId')),
        findsOneWidget,
      );

      await flushController(tester);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'store mode pins the screen awake, collapses quick add and removes swipe delete',
        (WidgetTester tester) async {
      size(tester, const Size(360, 800));
      controller.createList('Groceries');
      controller.quickAdd('milk');
      await flushController(tester);

      final List<bool> keepScreenOn = <bool>[];
      await tester.pumpWidget(
        host(posture(DevicePosture.folded), onKeepScreenOn: keepScreenOn.add),
      );
      await tester.pump();

      expect(find.byType(QuickAddCapsule), findsOneWidget);
      expect(keepScreenOn, isEmpty);
      expect(find.byType(Dismissible), findsOneWidget);

      await tester.tap(find.byTooltip('Shopping options'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ListTile, 'Store mode'));
      await tester.pumpAndSettle();

      expect(controller.storeMode, isTrue);
      expect(keepScreenOn, <bool>[true]);
      // The capsule collapses to a single Add item button.
      expect(find.byType(QuickAddCapsule), findsNothing);
      expect(
        find.byKey(const ValueKey<String>('store_add_item')),
        findsOneWidget,
      );
      // A clear exit control is in the header, and swipe-delete is gone.
      expect(find.byTooltip('Exit store mode'), findsOneWidget);
      expect(find.byType(Dismissible), findsNothing);

      // Expanding brings the full capsule back.
      await tester.tap(find.byKey(const ValueKey<String>('store_add_item')));
      await tester.pump();
      expect(find.byType(QuickAddCapsule), findsOneWidget);

      await tester.tap(find.byTooltip('Exit store mode'));
      await tester.pumpAndSettle();
      expect(controller.storeMode, isFalse);
      expect(keepScreenOn, <bool>[true, false]);
      expect(find.byType(Dismissible), findsOneWidget);

      await flushController(tester);
      expect(tester.takeException(), isNull);
    });

    testWidgets('closing the surface releases keep-screen-on',
        (WidgetTester tester) async {
      size(tester, const Size(360, 800));
      controller.createList('Groceries');
      controller.quickAdd('milk');
      await flushController(tester);

      final List<bool> keepScreenOn = <bool>[];
      await tester.pumpWidget(
        host(posture(DevicePosture.folded), onKeepScreenOn: keepScreenOn.add),
      );
      await tester.pump();

      controller.setStoreMode(true);
      await tester.pump();
      expect(keepScreenOn, <bool>[true]);

      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: SizedBox.shrink())),
      );
      await tester.pump();
      expect(keepScreenOn, <bool>[true, false]);

      await flushController(tester);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the cover-display hint turns store mode on',
        (WidgetTester tester) async {
      size(tester, const Size(360, 800));
      controller.createList('Groceries');
      controller.quickAdd('milk');
      await flushController(tester);

      await tester.pumpWidget(host(posture(DevicePosture.folded)));
      await tester.pump();
      expect(find.text('Store mode'), findsOneWidget);

      await tester.tap(find.text('Store mode'));
      await tester.pump();

      expect(controller.storeMode, isTrue);
      expect(find.text('Store mode'), findsNothing);

      await flushController(tester);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the hint can be dismissed without turning store mode on',
        (WidgetTester tester) async {
      size(tester, const Size(360, 800));
      controller.createList('Groceries');
      controller.quickAdd('milk');
      await flushController(tester);

      await tester.pumpWidget(host(posture(DevicePosture.folded)));
      await tester.pump();
      expect(find.text('Store mode'), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey<String>('dismiss_store_hint')),
      );
      await tester.pump();

      expect(find.text('Store mode'), findsNothing);
      expect(controller.storeMode, isFalse);

      await flushController(tester);
      expect(tester.takeException(), isNull);
    });
  });
}
