import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mylauncher/features/shopping/data/shopping_store.dart';
import 'package:mylauncher/features/shopping/models/quantity.dart';
import 'package:mylauncher/features/shopping/models/shopping_item.dart';
import 'package:mylauncher/features/shopping/models/shopping_list.dart';
import 'package:mylauncher/features/shopping/models/unit.dart';
import 'package:mylauncher/features/shopping/parsing/document_parser.dart';
import 'package:mylauncher/features/shopping/parsing/ingredient_parser.dart';
import 'package:mylauncher/features/shopping/parsing/menu_kit_parser.dart';
import 'package:mylauncher/features/shopping/shopping_controller.dart';
import 'package:mylauncher/features/shopping/ui/menu_kit_sheet.dart';

import 'menu_kit_fixture.dart';

const String _kitText = kMenuKitText;

MenuKitRecipe _recipe(MenuKit kit, String title) =>
    kit.recipes.singleWhere((MenuKitRecipe recipe) => recipe.title == title);

MenuKitItem _named(List<MenuKitItem> items, String name) =>
    items.singleWhere((MenuKitItem item) => item.name == name);

void main() {
  group('MenuKitParser', () {
    late MenuKit kit;

    setUp(() => kit = const MenuKitParser().tryParse(_kitText)!);

    test('reads the page header, place and both menus', () {
      expect(kit.title, 'Mediterranean');
      expect(kit.week, 'October 2nd, 2026');
      expect(kit.place, 'Patras, Greece');
      expect(kit.variants, <MenuVariant>[
        MenuVariant.regular,
        MenuVariant.vegetarian,
        MenuVariant.both,
      ]);
      final regular = kit.menuFor(MenuVariant.regular);
      expect(regular.map((MenuDay day) => day.day), <String>['Mon', 'Tue']);
      expect(regular[1].dishes.first, 'Patra Baked Cod and Roasted Fennel');
      expect(
        kit.menuFor(MenuVariant.vegetarian)[1].dishes.first,
        'Patra Baked Halloumi and Roasted Fennel',
      );
    });

    test('splits a table row into days, name, amount, note and cost', () {
      final items = kit.itemsFor(MenuVariant.regular);
      final tomatoes = _named(items, 'Cherry tomatoes');
      expect(tomatoes.days, <String>['Tue', 'Wed']);
      expect(tomatoes.note, 'Halve just before cooking');
      expect(tomatoes.costCents, 350);
      expect(tomatoes.aisle, 'Produce');

      final fennel = _named(items, 'Fennel');
      expect(fennel.amountText, '4 medium bulbs');
      expect(fennel.quantity, isNull);

      final lemon = _named(items, 'Lemon');
      expect(lemon.quantity, const Quantity(4, Unit.piece));
      expect(lemon.note, isNull);
      expect(lemon.days, <String>['Mon', 'Tue', 'Wed', 'Fri']);
    });

    test('keeps package sizes rather than flattening them', () {
      final items = kit.itemsFor(MenuVariant.regular);
      expect(
        _named(items, 'Pomegranate arils').displayAmount,
        '1 package (4.4 oz)',
      );
      expect(_named(items, 'Cod fillets').displayAmount, '12 oz (¾ lb)');
      final phyllo = _named(items, 'Phyllo dough');
      expect(phyllo.displayAmount, '1 (1#) box, thawed');
      expect(phyllo.note, 'Thaw overnight in the fridge');
    });

    test('maps sections to aisles without trusting misleading names', () {
      final items = kit.itemsFor(MenuVariant.regular);
      expect(_named(items, 'Cod fillets').aisle, 'Meat & Fish');
      expect(_named(items, 'Feta cheese').aisle, 'Dairy & Eggs');
      // "Butter" must not pull a shelf-stable can into Dairy.
      expect(_named(items, 'Butter beans, canned').aisle, 'Pantry');
    });

    test('reads both pantry columns, with units printed in capitals', () {
      final pantry = kit
          .itemsFor(MenuVariant.regular)
          .where((MenuKitItem item) => item.pantry)
          .toList();
      expect(pantry.map((MenuKitItem item) => item.name), <String>[
        'Canned chickpeas (Garbanzo)',
        'Capers',
        'Canned tomatoes',
        'Sea salt',
        'Kalamata olives',
        'Red pepper flakes',
        'Bay leaves',
      ]);
      expect(_named(pantry, 'Capers').displayAmount, '');
      expect(_named(pantry, 'Sea salt').displayAmount, 'As needed');
      expect(
        _named(pantry, 'Kalamata olives').displayAmount,
        '1/3 cup plus 2 Tablespoons',
      );
      expect(
        _named(pantry, 'Bay leaves').quantity,
        const Quantity(1, Unit.piece),
      );
      expect(
        pantry.every((MenuKitItem item) => item.aisle == 'Pantry'),
        isTrue,
      );
    });

    test('each printed list stands on its own', () {
      final regular = kit.itemsFor(MenuVariant.regular);
      final vegetarian = kit.itemsFor(MenuVariant.vegetarian);
      expect(regular.where((MenuKitItem i) => !i.pantry), hasLength(8));
      expect(vegetarian.where((MenuKitItem i) => !i.pantry), hasLength(9));
      expect(
        vegetarian.any((MenuKitItem i) => i.name == 'Cod fillets'),
        isFalse,
      );
      expect(_named(vegetarian, 'Halloumi').costCents, 800);
    });

    test('both takes shared lines once and marks menu-only lines', () {
      final both = kit.itemsFor(MenuVariant.both);
      expect(both.where((MenuKitItem i) => i.name == 'Fennel'), hasLength(1));
      expect(
        _named(both, 'Cod fillets').note,
        'Regular menu · Ask for skinless, center-cut',
      );
      expect(
        _named(both, 'Halloumi').note,
        'Vegetarian menu · Slice into planks',
      );
      // Printed as `12 ounces` and `12 oz`: the same amount.
      expect(_named(both, 'Feta cheese').note, 'Block, crumble by hand');
      expect(both.where((MenuKitItem i) => i.pantry), hasLength(7));
      expect(
        kit.menuFor(MenuVariant.both)[1].dishes,
        contains('Patra Baked Halloumi and Roasted Fennel'),
      );
    });

    test('names lists after the cuisine, week and variant', () {
      expect(kit.listName(MenuVariant.regular), 'Mediterranean · Oct 2');
      expect(
        kit.listName(MenuVariant.vegetarian),
        'Mediterranean · Oct 2 · Vegetarian',
      );
      expect(kit.listName(MenuVariant.both), 'Mediterranean · Oct 2 · Both');
    });

    test('ignores text without a meal-kit shopping list', () {
      expect(const MenuKitParser().tryParse('milk\neggs\n2 kg flour'), isNull);
      expect(
        const MenuKitParser().tryParse(
          'Pancakes\nServes 4\nIngredients\n'
          '2 eggs\nMethod\nWhisk.',
        ),
        isNull,
      );
    });

    test('reads each recipe page from the left column', () {
      expect(kit.recipes.map((MenuKitRecipe recipe) => recipe.title), <String>[
        'Patra Baked Cod and Roasted Fennel',
        'Patra Baked Halloumi and Roasted Fennel',
        'Warm Greek Lentil and Spinach Salad',
      ]);
      final cod = _recipe(kit, 'Patra Baked Cod and Roasted Fennel');
      expect(cod.servings, 4);
      expect(cod.side, isFalse);
      expect(
        cod.ingredients.map((ParsedIngredient i) => i.name),
        <String>[
          'fennel bulb',
          'cherry tomatoes',
          'extra virgin olive oil',
          'cod fillets',
          'lemon',
        ].map((String name) => contains(name)).toList(),
      );
      // The instruction glued onto the lemon line is cut off, and the
      // wrapped `Tablespoons)` rejoins it.
      final lemon = cod.ingredients.last;
      expect(lemon.note, contains('about 2 Tablespoons'));
      expect(lemon.note, isNot(contains('Drizzle')));
      expect(_recipe(kit, 'Warm Greek Lentil and Spinach Salad').side, isTrue);
    });

    test('rejoins wrapped ingredients and keeps descriptors in the name', () {
      final salad = _recipe(kit, 'Warm Greek Lentil and Spinach Salad');
      expect(salad.ingredients, hasLength(2));
      final chicken = salad.ingredients.first;
      expect(chicken.name, 'boneless skinless chicken thighs');
      expect(chicken.note, contains('cook to 165°F internal'));
    });

    test('assigns recipes to the menus that cook them', () {
      List<String> titles(MenuVariant variant) => kit
          .recipesFor(variant)
          .map((MenuKitRecipe recipe) => recipe.title)
          .toList();
      expect(titles(MenuVariant.regular), <String>[
        'Patra Baked Cod and Roasted Fennel',
        'Warm Greek Lentil and Spinach Salad',
      ]);
      expect(titles(MenuVariant.vegetarian), <String>[
        'Patra Baked Halloumi and Roasted Fennel',
        'Warm Greek Lentil and Spinach Salad',
      ]);
      expect(titles(MenuVariant.both), hasLength(3));
    });

    test('skips recipes when the extractor gave no column tabs', () {
      final untabbed = const MenuKitParser().tryParse(
        _kitText.replaceAll('\t', ' '),
      )!;
      expect(untabbed.recipes, isEmpty);
      expect(untabbed.itemsFor(MenuVariant.regular), hasLength(15));
    });

    test('reads tab-separated table rows like space-separated ones', () {
      final tabbed = const MenuKitParser().tryParse(
        'MEDITERRANEAN | FALL | OCTOBER 2ND, 2026\n'
        'SHOPPING LIST\n'
        'RECIPE\tPRODUCE\tQTY\tNOTES\tEST.  COST\n'
        'T, W\tCherry tomatoes\t1 pint\tHalve just before cooking\t\$3.50\n',
      )!;
      final tomatoes = tabbed.itemsFor(MenuVariant.regular).single;
      expect(tomatoes.name, 'Cherry tomatoes');
      expect(tomatoes.note, 'Halve just before cooking');
      expect(tomatoes.costCents, 350);
    });

    test('DocumentParser hands meal kits to the kit parser', () {
      final document = const DocumentParser().parseDocument(_kitText);
      expect(document.menuKit, isNotNull);
      expect(document.isEmpty, isFalse);
      expect(document.items, isEmpty);
    });
  });

  group('similarNames', () {
    test('matches typos and plurals, not different foods', () {
      expect(similarNames('Anchovies', 'Ancovies'), isTrue);
      expect(similarNames('Leeks', 'Leek'), isTrue);
      expect(
        similarNames(
          'Gnocchi Niçois and Roasted Squash',
          'Gnocchi Niçois and Roasted Squashs',
        ),
        isTrue,
      );
      expect(similarNames('Lemon', 'Melon'), isFalse);
      expect(similarNames('Pear', 'Peas'), isFalse);
      expect(similarNames('Raisins', 'Radishes'), isFalse);
    });

    test('Both pairs a misspelt line with its regular twin', () {
      final kit = const MenuKitParser().tryParse(
        'MEDITERRANEAN | FALL | OCTOBER 16, 2026\n'
        'SHOPPING LIST\n'
        'RECIPE BAKERY | MISC QTY NOTES EST. COST\n'
        'F Anchovies 2 oz can Shelf-stable \$3.00\n'
        'VEGETARIAN SHOPPING LIST\n'
        'RECIPE BAKERY | MISC QTY NOTES EST. COST\n'
        'F Ancovies 2 oz can Shelf-stable \$3.00\n',
      )!;
      final both = kit.itemsFor(MenuVariant.both);
      expect(both, hasLength(1));
      expect(both.single.name, 'Anchovies');
      expect(both.single.note, 'Shelf-stable');
    });
  });

  group('ShoppingItem import fields', () {
    test('round-trip through JSON and show the imported amount', () {
      const item = ShoppingItem(
        id: 'a',
        name: 'Fennel',
        amountText: '4 medium bulbs',
        costCents: 700,
        days: <String>['Mon', 'Wed'],
      );
      final restored = ShoppingItem.fromJson(item.toJson());
      expect(restored, item);
      expect(restored.displayAmount, '4 medium bulbs');
      expect(
        ShoppingItem.fromJson(const <String, dynamic>{
          'id': 'b',
          'name': 'Milk',
        }).days,
        isEmpty,
      );
    });

    test('a merge keeps both amounts, sums costs and unions days', () {
      final now = DateTime(2026, 10, 28);
      final list =
          ShoppingList(id: 'l', name: 'Week', createdAt: now, updatedAt: now)
              .addOrMerge(
                const ShoppingItem(
                  id: 'a',
                  name: 'Garlic',
                  amountText: '1 head',
                  costCents: 100,
                  days: <String>['Wed'],
                ),
              )
              .addOrMerge(
                const ShoppingItem(
                  id: 'b',
                  name: 'Garlic',
                  amountText: '2 heads',
                  costCents: 200,
                  days: <String>['Mon'],
                ),
              );
      final garlic = list.items.single;
      expect(garlic.amountText, '1 head + 2 heads');
      expect(garlic.costCents, 300);
      expect(garlic.days, <String>['Mon', 'Wed']);
      expect(list.estimatedCostCents(), 300);
    });

    test('estimated cost can count only what is still to buy', () {
      final now = DateTime(2026, 10, 28);
      final list = ShoppingList(
        id: 'l',
        name: 'Week',
        createdAt: now,
        updatedAt: now,
        items: const <ShoppingItem>[
          ShoppingItem(id: 'a', name: 'Cod', costCents: 900, checked: true),
          ShoppingItem(id: 'b', name: 'Feta', costCents: 700),
          ShoppingItem(id: 'c', name: 'Salt'),
        ],
      );
      expect(list.estimatedCostCents(), 1600);
      expect(list.estimatedCostCents(uncheckedOnly: true), 700);
      expect(
        ShoppingList(
          id: 'e',
          name: 'E',
          createdAt: now,
          updatedAt: now,
        ).estimatedCostCents(),
        isNull,
      );
    });
  });

  group('ShoppingController.importMenuKit', () {
    late Directory directory;
    late ShoppingController controller;

    setUp(() async {
      directory = Directory.systemTemp.createTempSync('menu_kit_test');
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

    test('creates a new active list carrying every imported field', () {
      final existing = controller.createList('Groceries');
      controller.quickAdd('milk');
      final kit = const MenuKitParser().tryParse(_kitText)!;

      final list = controller.importMenuKit(
        kit.listName(MenuVariant.vegetarian),
        kit.itemsFor(MenuVariant.vegetarian),
      )!;

      expect(controller.activeList!.id, list.id);
      expect(list.name, 'Mediterranean · Oct 2 · Vegetarian');
      expect(controller.listById(existing.id)!.items, hasLength(1));
      final fennel = list.items.singleWhere(
        (ShoppingItem item) => item.name == 'Fennel',
      );
      expect(fennel.amountText, '4 medium bulbs');
      expect(fennel.costCents, 700);
      expect(fennel.days, <String>['Mon', 'Tue', 'Wed']);
      expect(fennel.aisle, 'Produce');
      expect(list.estimatedCostCents(), isPositive);
    });

    test('saves recipes once, however often the week is imported', () {
      final kit = const MenuKitParser().tryParse(_kitText)!;
      controller.importMenuKit(
        kit.listName(MenuVariant.regular),
        kit.itemsFor(MenuVariant.regular),
        recipes: kit.recipesFor(MenuVariant.regular),
      );
      expect(controller.recipes, hasLength(2));
      final cod = controller.recipes.first;
      expect(cod.title, 'Patra Baked Cod and Roasted Fennel');
      expect(cod.baseServings, 4);
      expect(cod.targetServings, 4);
      expect(cod.ingredients, hasLength(5));
      // Nothing is opened for scaling: the kit import lands on the list.
      expect(controller.pendingRecipeId, isNull);

      controller.importMenuKit(
        kit.listName(MenuVariant.vegetarian),
        kit.itemsFor(MenuVariant.vegetarian),
        recipes: kit.recipesFor(MenuVariant.vegetarian),
      );
      expect(controller.recipes.map((recipe) => recipe.title), <String>[
        'Patra Baked Cod and Roasted Fennel',
        'Warm Greek Lentil and Spinach Salad',
        'Patra Baked Halloumi and Roasted Fennel',
      ]);
    });

    test('an empty selection creates nothing', () {
      expect(controller.importMenuKit('Empty', const <MenuKitItem>[]), isNull);
      expect(controller.lists, isEmpty);
    });
  });

  group('MenuKitSheet', () {
    testWidgets('starts on Regular with pantry staples unselected', (
      WidgetTester tester,
    ) async {
      final kit = const MenuKitParser().tryParse(_kitText)!;
      MenuVariant? confirmedVariant;
      List<MenuKitItem>? confirmed;
      List<MenuKitRecipe>? confirmedRecipes;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MenuKitSheet(
              kit: kit,
              onConfirm:
                  (
                    MenuVariant variant,
                    List<MenuKitItem> items,
                    List<MenuKitRecipe> recipes,
                  ) {
                    confirmedVariant = variant;
                    confirmed = items;
                    confirmedRecipes = recipes;
                  },
            ),
          ),
        ),
      );

      expect(find.text('Mediterranean meal plan'), findsOneWidget);
      // 8 regular lines, $40.50 in all; pantry staples are left out.
      expect(find.text('Create list · 8 items · ~\$40.50'), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey<String>('menu_variant_vegetarian')),
      );
      await tester.pump();
      expect(find.text('Create list · 9 items · ~\$43.50'), findsOneWidget);

      await tester.tap(find.text('Create list · 9 items · ~\$43.50'));
      await tester.pump();
      expect(confirmedVariant, MenuVariant.vegetarian);
      expect(confirmed!.any((MenuKitItem item) => item.pantry), isFalse);
      expect(
        confirmed!.map((MenuKitItem item) => item.name),
        contains('Halloumi'),
      );
      expect(
        confirmedRecipes!.map((MenuKitRecipe recipe) => recipe.title),
        <String>[
          'Patra Baked Halloumi and Roasted Fennel',
          'Warm Greek Lentil and Spinach Salad',
        ],
      );
    });

    testWidgets('saving recipes can be turned off', (
      WidgetTester tester,
    ) async {
      final kit = const MenuKitParser().tryParse(_kitText)!;
      List<MenuKitRecipe>? confirmedRecipes;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MenuKitSheet(
              kit: kit,
              onConfirm: (_, _, List<MenuKitRecipe> recipes) =>
                  confirmedRecipes = recipes,
            ),
          ),
        ),
      );

      expect(find.text('Also save 2 recipes'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey<String>('menu_kit_save_recipes')),
      );
      await tester.pump();
      await tester.tap(find.text('Create list · 8 items · ~\$40.50'));
      await tester.pump();
      expect(confirmedRecipes, isEmpty);
    });
  });
}
