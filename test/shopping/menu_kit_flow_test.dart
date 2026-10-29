import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mylauncher/core/foldable_controller.dart';
import 'package:mylauncher/core/launcher_bridge.dart';
import 'package:mylauncher/features/shopping/data/shopping_store.dart';
import 'package:mylauncher/features/shopping/models/quantity.dart';
import 'package:mylauncher/features/shopping/models/recipe.dart';
import 'package:mylauncher/features/shopping/models/shopping_item.dart';
import 'package:mylauncher/features/shopping/models/shopping_list.dart';
import 'package:mylauncher/features/shopping/models/unit.dart';
import 'package:mylauncher/features/shopping/parsing/document_parser.dart';
import 'package:mylauncher/features/shopping/parsing/menu_kit_parser.dart';
import 'package:mylauncher/features/shopping/parsing/pdf_text_import.dart';
import 'package:mylauncher/features/shopping/shopping_controller.dart';
import 'package:mylauncher/features/shopping/ui/import_review_sheet.dart';
import 'package:mylauncher/features/shopping/ui/item_edit_sheet.dart';
import 'package:mylauncher/features/shopping/ui/list_pane.dart';
import 'package:mylauncher/features/shopping/ui/menu_kit_sheet.dart';
import 'package:mylauncher/features/shopping/ui/shopping_surface.dart';
import 'package:mylauncher/main.dart';
import 'package:mylauncher/ui/theme/luminous_home_theme.dart';

import 'menu_kit_fixture.dart';

final MenuKit _kit = const MenuKitParser().tryParse(kMenuKitText)!;

void main() {
  late Directory directory;
  late ShoppingController controller;

  setUp(() async {
    directory = Directory.systemTemp.createTempSync('menu_kit_flow_test');
    controller = ShoppingController(
      store: ShoppingStore(directoryPath: directory.path),
    );
    await controller.load();
  });

  tearDown(() async {
    await controller.flush();
    controller.dispose();
    if (directory.existsSync()) directory.deleteSync(recursive: true);
  });

  /// Imports the kit's [variant] list (and recipes) into [controller].
  ShoppingList importKit(MenuVariant variant, {bool recipes = true}) =>
      controller.importMenuKit(
        _kit.listName(variant),
        _kit.itemsFor(variant),
        recipes: recipes ? _kit.recipesFor(variant) : const <MenuKitRecipe>[],
      )!;

  ShoppingItem itemNamed(String name) => controller.activeList!.items
      .singleWhere((ShoppingItem item) => item.name == name);

  /// Writes the debounced save now, so no timer outlives the test.
  Future<void> flush(WidgetTester tester) async {
    await tester.runAsync(() => controller.flush());
  }

  void size(WidgetTester tester, Size value) {
    tester.view.physicalSize = value;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Widget app(Widget child) => MaterialApp(
    theme: LuminousHomeTheme.buildTheme(),
    home: Scaffold(body: child),
  );

  /// The active list, rebuilt whenever the controller changes.
  Widget livePane() => ListenableBuilder(
    listenable: controller,
    builder: (BuildContext context, _) =>
        ListPane(controller: controller, list: controller.activeList!),
  );

  group('ShoppingItem and ShoppingList', () {
    test('copyWith keeps import fields unless replaced', () {
      const item = ShoppingItem(
        id: 'a',
        name: 'Fennel',
        amountText: '4 medium bulbs',
        costCents: 700,
        days: <String>['Mon'],
      );
      final renamed = item.copyWith(name: 'Fennel bulbs');
      expect(renamed.amountText, '4 medium bulbs');
      expect(renamed.costCents, 700);
      expect(renamed.days, <String>['Mon']);
      expect(item.copyWith(days: <String>['Tue']).days, <String>['Tue']);
    });

    test('equality and hashing see every import field', () {
      const base = ShoppingItem(id: 'a', name: 'Fennel');
      expect(base, isNot(base.copyWith(amountText: '2')));
      expect(base, isNot(base.copyWith(costCents: 1)));
      expect(base, isNot(base.copyWith(days: <String>['Mon'])));
      expect(
        base.copyWith(days: <String>['Mon']).hashCode,
        base.copyWith(days: <String>['Mon']).hashCode,
      );
    });

    test('a structured quantity wins over the printed amount', () {
      const item = ShoppingItem(
        id: 'a',
        name: 'Feta',
        quantity: Quantity(12, Unit.ounce),
        amountText: '12 oz block',
      );
      expect(item.displayAmount, '12 ounces');
      expect(const ShoppingItem(id: 'b', name: 'Salt').displayAmount, '');
    });

    test('JSON tolerates older and odd stores', () {
      final item = ShoppingItem.fromJson(<String, dynamic>{
        'id': 'a',
        'name': 'Fennel',
        'costCents': 350.0,
        'days': <Object>['Mon', 3, 'Wed'],
      });
      expect(item.costCents, 350);
      expect(item.days, <String>['Mon', 'Wed']);
      // Unset fields are not written, so older readers see nothing new.
      expect(
        const ShoppingItem(id: 'b', name: 'Salt').toJson().keys,
        isNot(
          anyOf(
            contains('amountText'),
            contains('costCents'),
            contains('days'),
          ),
        ),
      );
    });

    test('merging a structured amount drops the printed one', () {
      final now = DateTime(2026, 10, 28);
      final list =
          ShoppingList(id: 'l', name: 'Week', createdAt: now, updatedAt: now)
              .addOrMerge(
                const ShoppingItem(
                  id: 'a',
                  name: 'Lemon',
                  quantity: Quantity(2, Unit.piece),
                ),
              )
              .addOrMerge(
                const ShoppingItem(
                  id: 'b',
                  name: 'Lemons',
                  quantity: Quantity(4, Unit.piece),
                  costCents: 200,
                ),
              );
      final lemon = list.items.single;
      expect(lemon.quantity, const Quantity(6, Unit.piece));
      expect(lemon.amountText, isNull);
      expect(lemon.costCents, 200);
    });

    test('re-adding a checked line brings back its import fields', () {
      final now = DateTime(2026, 10, 28);
      final list =
          ShoppingList(
            id: 'l',
            name: 'Week',
            createdAt: now,
            updatedAt: now,
            items: const <ShoppingItem>[
              ShoppingItem(id: 'a', name: 'Fennel', checked: true),
            ],
          ).addOrMerge(
            const ShoppingItem(
              id: 'b',
              name: 'Fennel',
              amountText: '4 medium bulbs',
              costCents: 700,
              days: <String>['Mon'],
            ),
          );
      final fennel = list.items.single;
      expect(fennel.id, 'a');
      expect(fennel.checked, isFalse);
      expect(fennel.amountText, '4 medium bulbs');
      expect(fennel.costCents, 700);
      expect(fennel.days, <String>['Mon']);
    });

    test('formatCents', () {
      expect(formatCents(0), '\$0.00');
      expect(formatCents(5), '\$0.05');
      expect(formatCents(1234), '\$12.34');
      expect(formatCents(-250), '-\$2.50');
    });
  });

  group('ShoppingController.importMenuKit', () {
    test('every variant builds its own named list', () {
      for (final MenuVariant variant in _kit.variants) {
        importKit(variant);
      }
      expect(controller.lists.map((ShoppingList l) => l.name), <String>[
        'Mediterranean · Oct 2',
        'Mediterranean · Oct 2 · Vegetarian',
        'Mediterranean · Oct 2 · Both',
      ]);
      expect(controller.activeList!.name, 'Mediterranean · Oct 2 · Both');
      // Halloumi only on the vegetarian lists, cod only on the regular ones.
      bool has(int list, String name) => controller.lists[list].items.any(
        (ShoppingItem item) => item.name == name,
      );
      expect(has(0, 'Cod fillets') && !has(0, 'Halloumi'), isTrue);
      expect(has(1, 'Halloumi') && !has(1, 'Cod fillets'), isTrue);
      expect(has(2, 'Halloumi') && has(2, 'Cod fillets'), isTrue);
    });

    test('a remembered aisle overrides the kit section', () {
      final first = importKit(MenuVariant.regular);
      final walnuts = first.items.singleWhere(
        (ShoppingItem item) => item.name == 'Phyllo dough',
      );
      controller.updateItem(first.id, walnuts.copyWith(aisle: 'Frozen'));

      importKit(MenuVariant.vegetarian);
      expect(itemNamed('Phyllo dough').aisle, 'Frozen');
    });

    test('recipes keep their ingredients, amounts and notes', () {
      importKit(MenuVariant.regular);
      final Recipe cod = controller.recipes.singleWhere(
        (Recipe r) => r.title == 'Patra Baked Cod and Roasted Fennel',
      );
      final Ingredient tomatoes = cod.ingredients.singleWhere(
        (Ingredient i) => i.name == 'cherry tomatoes',
      );
      expect(tomatoes.quantity, const Quantity(6, Unit.ounce));
      expect(tomatoes.note, 'halved');
      // Scaling works like any saved recipe.
      controller.setRecipeServings(cod.id, 8);
      final scaled = controller
          .recipeById(cod.id)!
          .scaledIngredients
          .singleWhere((Ingredient i) => i.name == 'cherry tomatoes');
      expect(scaled.quantity, const Quantity(12, Unit.ounce));
    });

    test('a recipe the user already saved under that title is kept', () {
      controller.addRecipe(
        const Recipe(
          id: 'mine',
          title: 'warm greek lentil and spinach salad',
          baseServings: 2,
          targetServings: 2,
        ),
      );
      importKit(MenuVariant.regular);
      final lentils = controller.recipes.where(
        (Recipe r) =>
            r.title.toLowerCase() == 'warm greek lentil and spinach salad',
      );
      expect(lentils.single.id, 'mine');
      expect(controller.recipes, hasLength(2));
    });

    test('opting out of recipes saves none', () {
      importKit(MenuVariant.both, recipes: false);
      expect(controller.recipes, isEmpty);
      expect(controller.activeList!.items, isNotEmpty);
    });

    test('an import survives a restart', () async {
      importKit(MenuVariant.vegetarian);
      await controller.flush();

      final reloaded = ShoppingController(
        store: ShoppingStore(directoryPath: directory.path),
      );
      addTearDown(reloaded.dispose);
      await reloaded.load();

      final list = reloaded.activeList!;
      expect(list.name, 'Mediterranean · Oct 2 · Vegetarian');
      expect(list.items, controller.activeList!.items);
      final fennel = list.items.singleWhere(
        (ShoppingItem i) => i.name == 'Fennel',
      );
      expect(fennel.amountText, '4 medium bulbs');
      expect(fennel.costCents, 700);
      expect(fennel.days, <String>['Mon', 'Tue', 'Wed']);
      expect(
        list.estimatedCostCents(),
        controller.activeList!.estimatedCostCents(),
      );
      expect(
        reloaded.recipes.map((Recipe r) => r.title),
        controller.recipes.map((Recipe r) => r.title),
      );
    });
  });

  group('List pane', () {
    testWidgets('rows show the printed amount, cooking days and price', (
      WidgetTester tester,
    ) async {
      importKit(MenuVariant.regular);
      await tester.pumpWidget(app(livePane()));

      expect(find.text('Fennel'), findsOneWidget);
      expect(find.text('4 medium bulbs'), findsOneWidget);
      expect(find.text('Mon · Tue · Wed'), findsWidgets);
      expect(find.text('Keep the fronds for garnish'), findsOneWidget);
      expect(find.text('\$7.00'), findsWidgets);
      expect(
        find.bySemanticsLabel(
          RegExp(r'^4 medium bulbs Fennel for Mon, Tue, Wed about \$7\.00$'),
        ),
        findsOneWidget,
      );
      await flush(tester);
    });

    testWidgets('the cost summary counts down as items are checked', (
      WidgetTester tester,
    ) async {
      importKit(MenuVariant.regular);
      await tester.pumpWidget(app(livePane()));
      expect(find.text('Est. \$40.50 left'), findsOneWidget);
      expect(find.text('of \$40.50'), findsOneWidget);
      expect(
        find.bySemanticsLabel('Estimated cost: \$40.50 left of \$40.50'),
        findsOneWidget,
      );

      controller.toggleChecked(
        controller.activeList!.id,
        itemNamed('Cod fillets').id,
      );
      await tester.pump();
      expect(find.text('Est. \$31.50 left'), findsOneWidget);
      expect(find.text('of \$40.50'), findsOneWidget);
      // Checking settles after a short delay; let it finish.
      await tester.pump(const Duration(seconds: 1));
      await flush(tester);
    });

    testWidgets('lists without prices show no summary', (
      WidgetTester tester,
    ) async {
      controller.createList('Groceries');
      controller.quickAdd('2 kg flour');
      await tester.pumpWidget(app(livePane()));
      expect(find.textContaining('Est. '), findsNothing);
      await flush(tester);
    });
  });

  group('Item edit sheet', () {
    Future<void> openEditor(WidgetTester tester, String name) async {
      size(tester, const Size(800, 1200));
      await tester.pumpWidget(
        app(
          Builder(
            builder: (BuildContext context) => TextButton(
              onPressed: () => showItemEditSheet(
                context,
                controller: controller,
                list: controller.activeList!,
                item: itemNamed(name),
              ),
              child: const Text('edit'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('edit'));
      await tester.pumpAndSettle();
    }

    testWidgets('shows the printed amount and keeps imports on save', (
      WidgetTester tester,
    ) async {
      importKit(MenuVariant.regular);
      await openEditor(tester, 'Fennel');
      expect(find.text('4 medium bulbs'), findsOneWidget);

      await tester.enterText(
        find.byKey(const ValueKey<String>('edit_item_note')),
        'Pick heavy bulbs',
      );
      await tester.tap(find.text('Save item'));
      await tester.pumpAndSettle();

      final fennel = itemNamed('Fennel');
      expect(fennel.note, 'Pick heavy bulbs');
      expect(fennel.amountText, '4 medium bulbs');
      expect(fennel.costCents, 700);
      expect(fennel.days, <String>['Mon', 'Tue', 'Wed']);
    });

    testWidgets('a typed amount replaces the printed one', (
      WidgetTester tester,
    ) async {
      importKit(MenuVariant.regular);
      await openEditor(tester, 'Fennel');
      await tester.enterText(
        find.byKey(const ValueKey<String>('edit_item_amount')),
        '3',
      );
      await tester.pump();
      await tester.tap(find.text('Save item'));
      await tester.pumpAndSettle();

      final fennel = itemNamed('Fennel');
      expect(fennel.quantity?.amount, 3);
      expect(fennel.amountText, isNull);
      expect(fennel.displayAmount, '3');
      expect(fennel.costCents, 700);
    });
  });

  group('Meal-kit sheet', () {
    Future<void> pumpSheet(
      WidgetTester tester, {
      MenuKitConfirm? onConfirm,
    }) async {
      size(tester, const Size(800, 2400));
      await tester.pumpWidget(
        app(MenuKitSheet(kit: _kit, onConfirm: onConfirm ?? (_, _, _) {})),
      );
    }

    String button(int items, String cost) =>
        'Create list · $items items · ~\$$cost';

    testWidgets('shows the week, place and each menu choice', (
      WidgetTester tester,
    ) async {
      await pumpSheet(tester);
      expect(find.text('Mediterranean meal plan'), findsOneWidget);
      expect(find.text('October 2nd, 2026 · Patras, Greece'), findsOneWidget);
      for (final String label in <String>['Regular', 'Vegetarian', 'Both']) {
        expect(find.text(label), findsOneWidget);
      }
      expect(find.bySemanticsLabel('Regular menu'), findsOneWidget);
    });

    testWidgets('lines are grouped by aisle with pantry staples last', (
      WidgetTester tester,
    ) async {
      await pumpSheet(tester);
      final double produce = tester.getTopLeft(find.text('PRODUCE')).dy;
      final double dairy = tester.getTopLeft(find.text('DAIRY & EGGS')).dy;
      final double pantry = tester
          .getTopLeft(find.text('PANTRY STAPLES — CHECK BEFORE YOU SHOP'))
          .dy;
      expect(produce, lessThan(dairy));
      expect(dairy, lessThan(pantry));
      // A row shows its days, note and price.
      expect(
        find.text('Tue · Wed — Halve just before cooking'),
        findsOneWidget,
      );
    });

    testWidgets('switching menus swaps the protein lines', (
      WidgetTester tester,
    ) async {
      await pumpSheet(tester);
      expect(find.text('Cod fillets'), findsOneWidget);
      expect(find.text('Halloumi'), findsNothing);

      await tester.tap(find.text('Vegetarian'));
      await tester.pump();
      expect(find.text('Cod fillets'), findsNothing);
      expect(find.text('Halloumi'), findsOneWidget);

      await tester.tap(find.text('Both'));
      await tester.pump();
      expect(find.text('Cod fillets'), findsOneWidget);
      expect(find.text('Halloumi'), findsOneWidget);
      expect(
        find.text('T — Regular menu · Ask for skinless, center-cut'),
        findsNothing,
      );
      expect(
        find.text('Tue — Regular menu · Ask for skinless, center-cut'),
        findsOneWidget,
      );
      expect(find.text(button(10, '52.50')), findsOneWidget);
    });

    testWidgets('a dropped line stays dropped across menus', (
      WidgetTester tester,
    ) async {
      await pumpSheet(tester);
      await tester.tap(find.text('Feta cheese'));
      await tester.pump();
      expect(find.text(button(7, '33.50')), findsOneWidget);

      await tester.tap(find.text('Vegetarian'));
      await tester.pump();
      expect(find.text(button(8, '36.50')), findsOneWidget);

      await tester.tap(find.text('Feta cheese'));
      await tester.pump();
      expect(find.text(button(9, '43.50')), findsOneWidget);
    });

    testWidgets('pantry staples can be added as a group', (
      WidgetTester tester,
    ) async {
      List<MenuKitItem>? confirmed;
      await pumpSheet(tester, onConfirm: (_, items, _) => confirmed = items);
      final Finder pantryToggle = find.descendant(
        of: find.ancestor(
          of: find.text('PANTRY STAPLES — CHECK BEFORE YOU SHOP'),
          matching: find.byType(Row),
        ),
        matching: find.text('Select all'),
      );
      await tester.tap(pantryToggle);
      await tester.pump();
      expect(find.text(button(15, '40.50')), findsOneWidget);

      await tester.tap(find.text(button(15, '40.50')));
      await tester.pump();
      expect(confirmed!.where((MenuKitItem i) => i.pantry), hasLength(7));
    });

    testWidgets('with nothing selected the list cannot be created', (
      WidgetTester tester,
    ) async {
      var confirmed = false;
      await pumpSheet(tester, onConfirm: (_, _, _) => confirmed = true);
      // Each group's "Select none" turns into "Select all" once tapped.
      while (find.text('Select none').evaluate().isNotEmpty) {
        await tester.tap(find.text('Select none').first);
        await tester.pump();
      }
      expect(find.text('Nothing selected'), findsOneWidget);
      await tester.tap(find.text('Nothing selected'));
      await tester.pump();
      expect(confirmed, isFalse);
    });

    testWidgets("the week's menu opens per variant", (
      WidgetTester tester,
    ) async {
      await pumpSheet(tester);
      expect(find.text('Mon'), findsNothing);
      await tester.tap(find.text("This week's menu"));
      await tester.pump();
      expect(find.text('Mon'), findsOneWidget);
      expect(
        find.text(
          'Patra Baked Cod and Roasted Fennel\n'
          'Warm Greek Lentil and Spinach Salad',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Vegetarian'));
      await tester.pump();
      expect(
        find.textContaining('Patra Baked Halloumi and Roasted Fennel'),
        findsOneWidget,
      );
    });

    testWidgets('the recipe count follows the chosen menu', (
      WidgetTester tester,
    ) async {
      List<MenuKitRecipe>? recipes;
      await pumpSheet(tester, onConfirm: (_, _, r) => recipes = r);
      expect(find.text('Also save 2 recipes'), findsOneWidget);
      await tester.tap(find.text('Both'));
      await tester.pump();
      expect(find.text('Also save 3 recipes'), findsOneWidget);
      await tester.tap(find.text(button(10, '52.50')));
      await tester.pump();
      expect(recipes, hasLength(3));
    });

    testWidgets('a kit without readable recipes hides the recipe option', (
      WidgetTester tester,
    ) async {
      size(tester, const Size(800, 2400));
      final untabbed = const MenuKitParser().tryParse(
        kMenuKitText.replaceAll('\t', ' '),
      )!;
      await tester.pumpWidget(
        app(MenuKitSheet(kit: untabbed, onConfirm: (_, _, _) {})),
      );
      expect(find.textContaining('Also save'), findsNothing);
    });
  });

  group('Import routing', () {
    testWidgets('reviewImportedDocument opens the right sheet', (
      WidgetTester tester,
    ) async {
      size(tester, const Size(800, 2400));
      late BuildContext context;
      await tester.pumpWidget(
        app(
          Builder(
            builder: (BuildContext c) {
              context = c;
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      reviewImportedDocument(
        context,
        controller: controller,
        document: const DocumentParser().parseDocument('Milk\nEggs'),
      );
      await tester.pumpAndSettle();
      expect(find.byType(ImportReviewSheet), findsOneWidget);
      expect(find.byType(MenuKitSheet), findsNothing);
      Navigator.of(context).pop();
      await tester.pumpAndSettle();

      reviewImportedDocument(
        context,
        controller: controller,
        document: const DocumentParser().parseDocument(kMenuKitText),
      );
      await tester.pumpAndSettle();
      expect(find.byType(MenuKitSheet), findsOneWidget);

      await tester.tap(find.text('Vegetarian'));
      await tester.pump();
      await tester.tap(find.text('Create list · 9 items · ~\$43.50'));
      await tester.pumpAndSettle();
      expect(find.byType(MenuKitSheet), findsNothing);
      expect(controller.activeList!.name, 'Mediterranean · Oct 2 · Vegetarian');
      expect(controller.activeList!.items, hasLength(9));
      expect(controller.recipes, hasLength(2));
    });

    testWidgets('Import PDF in the shopping surface builds the week list', (
      WidgetTester tester,
    ) async {
      size(tester, const Size(800, 1600));
      final foldable = FoldableController();
      addTearDown(foldable.dispose);
      foldable.setPosture(DevicePosture.folded);
      controller.createList('Groceries');

      await tester.pumpWidget(
        app(
          ShoppingSurface(
            controller: controller,
            foldable: foldable,
            onClose: () {},
            pdfImportService: PdfImportService(
              extract: (String path) async =>
                  const PdfTextResult(text: kMenuKitText, pageCount: 23),
              pick: () async => '/cache/imports/kit.pdf',
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.byTooltip('Shopping options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Import PDF'));
      await tester.pumpAndSettle();
      expect(find.byType(MenuKitSheet), findsOneWidget);

      await tester.tap(find.text('Create list · 8 items · ~\$40.50'));
      await tester.pumpAndSettle();

      expect(controller.lists, hasLength(2));
      expect(controller.activeList!.name, 'Mediterranean · Oct 2');
      expect(find.text('Est. \$40.50 left'), findsOneWidget);
      expect(find.text('4 medium bulbs'), findsOneWidget);
      await tester.runAsync(() => controller.flush());
      expect(tester.takeException(), isNull);
    });

    testWidgets('a shared meal-kit PDF opens the meal-kit sheet', (
      WidgetTester tester,
    ) async {
      addTearDown(() => LauncherBridge.setSharedPdfListener((_) {}));
      await tester.pumpWidget(
        ChronoFoldApp(
          isKeyguardLocked: () async => false,
          takePendingSharedPdf: () async => null,
          extractPdfText: (String path) async =>
              const PdfTextResult(text: kMenuKitText, pageCount: 23),
          pickPdf: () async => null,
        ),
      );
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      LauncherBridge.dispatchSharedPdfForTesting('/data/cache/imports/kit.pdf');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(ShoppingSurface), findsOneWidget);
      expect(find.byType(MenuKitSheet), findsOneWidget);
      expect(find.byType(ImportReviewSheet), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}
