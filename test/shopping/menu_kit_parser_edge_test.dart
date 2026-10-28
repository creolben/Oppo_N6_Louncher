import 'package:flutter_test/flutter_test.dart';
import 'package:mylauncher/features/shopping/models/quantity.dart';
import 'package:mylauncher/features/shopping/models/unit.dart';
import 'package:mylauncher/features/shopping/parsing/document_parser.dart';
import 'package:mylauncher/features/shopping/parsing/ingredient_parser.dart';
import 'package:mylauncher/features/shopping/parsing/menu_kit_parser.dart';

import 'menu_kit_fixture.dart';

const String _header = 'MEDITERRANEAN | FALL | OCTOBER 2ND, 2026';

/// A kit with one list built from [rows] under a `PRODUCE` section.
String _list(List<String> rows, {String heading = 'SHOPPING LIST'}) => <String>[
  _header,
  heading,
  'RECIPE PRODUCE QTY NOTES EST. COST',
  ...rows,
].join('\n');

MenuKit _parse(String text) => const MenuKitParser().tryParse(text)!;

MenuKitItem _only(String text) =>
    _parse(text).itemsFor(MenuVariant.regular).single;

MenuKitItem _named(List<MenuKitItem> items, String name) =>
    items.singleWhere((MenuKitItem item) => item.name == name);

void main() {
  group('detection', () {
    test('returns null for text with no meal-kit list', () {
      const parser = MenuKitParser();
      expect(parser.tryParse(''), isNull);
      expect(parser.tryParse('Milk\nEggs\nBread'), isNull);
      // A heading with no rows under it is not a kit.
      expect(parser.tryParse('$_header\nSHOPPING LIST\nThanks!'), isNull);
      // Rows without a shopping-list heading are not a kit either.
      expect(
        parser.tryParse('M Fennel 2 medium - \$3.00\nT Lemon 4 - \$2.00'),
        isNull,
      );
    });

    test('reads Windows line endings the same as Unix ones', () {
      final unix = _parse(kMenuKitText);
      final windows = _parse(kMenuKitText.replaceAll('\n', '\r\n'));
      for (final MenuVariant variant in unix.variants) {
        expect(
          windows.itemsFor(variant).map((MenuKitItem i) => i.toString()),
          unix.itemsFor(variant).map((MenuKitItem i) => i.toString()),
        );
      }
      expect(windows.recipes, hasLength(unix.recipes.length));
    });

    test('a kit without a page header still parses, with a fallback title', () {
      final kit = _parse(
        'SHOPPING LIST\n'
        'RECIPE PRODUCE QTY NOTES EST. COST\n'
        'M Fennel 2 medium - \$3.00',
      );
      expect(kit.title, 'Meal plan');
      expect(kit.week, isNull);
      expect(kit.place, isNull);
      expect(kit.listName(MenuVariant.regular), 'Meal plan');
    });
  });

  group('variants', () {
    test('a regular-only kit offers no vegetarian or combined list', () {
      final kit = _parse(_list(<String>['M Fennel 2 medium - \$3.00']));
      expect(kit.variants, <MenuVariant>[MenuVariant.regular]);
      expect(kit.itemsFor(MenuVariant.vegetarian), isEmpty);
    });

    test('a vegetarian-only kit offers just that list', () {
      final kit = _parse(
        _list(<String>[
          'M Fennel 2 medium - \$3.00',
        ], heading: 'VEGETARIAN SHOPPING LIST'),
      );
      expect(kit.variants, <MenuVariant>[MenuVariant.vegetarian]);
      expect(
        kit.listName(MenuVariant.vegetarian),
        'Mediterranean · Oct 2 · Vegetarian',
      );
    });

    test('vegan headings count as the vegetarian menu', () {
      final kit = _parse(
        _list(<String>[
          'M Fennel 2 medium - \$3.00',
        ], heading: 'VEGAN SHOPPING LIST'),
      );
      expect(kit.variants, <MenuVariant>[MenuVariant.vegetarian]);
    });
  });

  group('table rows', () {
    test('day codes map to weekdays in week order', () {
      expect(_only(_list(<String>['F, M Fennel 2 - \$3.00'])).days, <String>[
        'Mon',
        'Fri',
      ]);
      expect(
        _only(_list(<String>['Sa, Su, Th Fennel 2 - \$3.00'])).days,
        <String>['Thu', 'Sat', 'Sun'],
      );
      expect(_only(_list(<String>['Mo, Tu Fennel 2 - \$3.00'])).days, <String>[
        'Mon',
        'Tue',
      ]);
      expect(_only(_list(<String>['M,W Fennel 2 - \$3.00'])).days, <String>[
        'Mon',
        'Wed',
      ]);
    });

    test('prices parse with or without cents', () {
      expect(_only(_list(<String>['M Fennel 2 - \$3'])).costCents, 300);
      expect(_only(_list(<String>['M Fennel 2 - \$3.5'])).costCents, 350);
      expect(_only(_list(<String>['M Fennel 2 - \$12.99'])).costCents, 1299);
      expect(_only(_list(<String>['M Fennel 2 - \$ 4.25'])).costCents, 425);
    });

    test('a dash note is no note', () {
      final item = _only(_list(<String>['M Garlic 1 head - \$1.00']));
      expect(item.note, isNull);
      expect(item.displayAmount, '1 head');
    });

    test('plain amounts become quantities, packaged ones stay as printed', () {
      expect(
        _only(_list(<String>['M Lemon 4 - \$2.00'])).quantity,
        const Quantity(4, Unit.piece),
      );
      expect(
        _only(_list(<String>['M Feta 12 ounces - \$7.00'])).quantity,
        const Quantity(12, Unit.ounce),
      );
      final package = _only(
        _list(<String>['M Dill 1 (¾ oz) package - \$1.75']),
      );
      expect(package.quantity, isNull);
      expect(package.amountText, '1 (¾ oz) package');
      final ranged = _only(
        _list(<String>['M Pumpkin 1 small (~ 2 lb) - \$3.00']),
      );
      expect(ranged.amountText, '1 small (~ 2 lb)');
    });

    test('names with commas and parentheses stay whole', () {
      final item = _only(
        _list(<String>[
          'M, W Butter beans, canned 3 (15.5 oz ea) cans Stands in for gigantes \$4.50',
        ]),
      );
      expect(item.name, 'Butter beans, canned');
      expect(item.amountText, '3 (15.5 oz ea) cans');
      expect(item.note, 'Stands in for gigantes');
    });

    test('a note that starts with a capitalized unit word is still a note', () {
      // `Lb` is a unit, so it continues the amount; `Ask` starts the note.
      final item = _only(
        _list(<String>['T Cod 12 oz Ask for center-cut \$9.00']),
      );
      expect(item.displayAmount, '12 ounces');
      expect(item.note, 'Ask for center-cut');
    });

    test('a prose line ends the table', () {
      final kit = _parse(
        _list(<String>[
          'M Fennel 2 - \$3.00',
          'Prices are estimates and vary by store.',
          'T Lemon 4 - \$2.00',
        ]),
      );
      expect(
        kit.itemsFor(MenuVariant.regular).map((MenuKitItem i) => i.name),
        <String>['Fennel'],
      );
    });

    test('a list continues across a page break', () {
      final kit = _parse(
        <String>[
          _list(<String>['M Fennel 2 - \$3.00']),
          _header,
          'RECIPE DAIRY QTY NOTES EST. COST',
          'Th Eggs 12 large - \$4.00',
          'PANTRY QTY PANTRY QTY',
          'Sea salt As needed Capers -',
        ].join('\n'),
      );
      final items = kit.itemsFor(MenuVariant.regular);
      expect(items.map((MenuKitItem i) => i.name), <String>[
        'Fennel',
        'Eggs',
        'Sea salt',
        'Capers',
      ]);
      expect(_named(items, 'Eggs').aisle, 'Dairy & Eggs');
      expect(_named(items, 'Capers').pantry, isTrue);
    });
  });

  group('sections', () {
    MenuKitItem inSection(String section, String row) => _only(
      <String>[
        _header,
        'SHOPPING LIST',
        'RECIPE $section QTY NOTES EST. COST',
        row,
      ].join('\n'),
    );

    test('map to the app aisles', () {
      expect(inSection('PRODUCE', 'M Kale 1 bunch - \$2.00').aisle, 'Produce');
      expect(
        inSection('MEAT | SEAFOOD', 'M Cod 1 lb - \$9.00').aisle,
        'Meat & Fish',
      );
      expect(inSection('MEAT', 'M Pork 1 lb - \$6.00').aisle, 'Meat & Fish');
      expect(
        inSection('SEAFOOD', 'M Shrimp 1 lb - \$9.00').aisle,
        'Meat & Fish',
      );
      expect(inSection('DAIRY', 'M Feta 8 oz - \$5.00').aisle, 'Dairy & Eggs');
      expect(inSection('FROZEN', 'M Peas 1 bag - \$2.00').aisle, 'Frozen');
    });

    test('a catch-all section trusts only shelf aisles from the name', () {
      expect(
        inSection('BAKERY | MISC', 'M Phyllo dough 1 box - \$4.00').aisle,
        'Bakery',
      );
      expect(
        inSection('BAKERY | MISC', 'M Walnuts 4 oz bag - \$3.50').aisle,
        'Pantry',
      );
      // "Butter" would guess Dairy, which a shelf-stable section rules out.
      expect(
        inSection('BAKERY | MISC', 'M Butter beans 2 cans - \$3.00').aisle,
        'Pantry',
      );
      expect(
        inSection('BAKERY', 'M Walnuts 4 oz bag - \$3.50').aisle,
        'Bakery',
      );
    });
  });

  group('pantry rows', () {
    List<MenuKitItem> pantry(List<String> rows) =>
        _parse(
              <String>[
                _list(<String>['M Fennel 2 - \$3.00']),
                'PANTRY QTY PANTRY QTY',
                ...rows,
              ].join('\n'),
            )
            .itemsFor(MenuVariant.regular)
            .where((MenuKitItem item) => item.pantry)
            .toList();

    test('read one or two pairs per line, amounts optional', () {
      final items = pantry(<String>[
        'Capers - Tomato paste 2 Tablespoons',
        'Extra virgin olive oil About 1½ cups Red pepper flakes Pinch',
        'Bay leaves',
      ]);
      expect(items.map((MenuKitItem i) => i.name), <String>[
        'Capers',
        'Tomato paste',
        'Extra virgin olive oil',
        'Red pepper flakes',
        'Bay leaves',
      ]);
      expect(_named(items, 'Capers').displayAmount, '');
      expect(_named(items, 'Tomato paste').displayAmount, isNotEmpty);
      expect(
        _named(items, 'Extra virgin olive oil').amountText,
        'About 1½ cups',
      );
      expect(_named(items, 'Red pepper flakes').amountText, 'Pinch');
      expect(items.every((MenuKitItem i) => i.aisle == 'Pantry'), isTrue);
      expect(items.every((MenuKitItem i) => i.costCents == null), isTrue);
    });

    test('lowercase words inside an amount stay with it', () {
      final items = pantry(<String>[
        'Canned tomatoes 1 (14.5 oz) can crushed tomatoes Sea salt As needed',
      ]);
      expect(
        _named(items, 'Canned tomatoes').amountText,
        '1 (14.5 oz) can crushed tomatoes',
      );
      expect(_named(items, 'Sea salt').amountText, 'As needed');
    });

    test('a line that is not a pantry row ends the pantry', () {
      final items = pantry(<String>[
        'Capers -',
        'see the prep guide for more',
        'Sea salt As needed',
      ]);
      expect(items.map((MenuKitItem i) => i.name), <String>['Capers']);
    });
  });

  group('menus', () {
    test('collect dishes per day and stop at prose', () {
      final kit = _parse(
        <String>[
          _header,
          'MENU',
          'MONDAY',
          'BEAN PLAKI',
          'ROASTED FENNEL',
          'SATURDAY',
          'WEEKEND PIE',
          'Enjoy the week.',
          'SUNDAY',
          'NOT A DISH',
          _list(<String>['M Fennel 2 - \$3.00']),
        ].join('\n'),
      );
      final menu = kit.menuFor(MenuVariant.regular);
      expect(menu.map((MenuDay d) => d.day), <String>['Mon', 'Sat']);
      expect(menu.first.dishes, <String>['Bean Plaki', 'Roasted Fennel']);
      expect(menu.last.dishes, <String>['Weekend Pie']);
    });

    test('Both lists each day once with the vegetarian swaps added', () {
      final menu = _parse(kMenuKitText).menuFor(MenuVariant.both);
      expect(menu.map((MenuDay d) => d.day), <String>['Mon', 'Tue']);
      expect(menu.first.dishes, hasLength(2));
      expect(menu.last.dishes, <String>[
        'Patra Baked Cod and Roasted Fennel',
        'Warm Greek Lentil and Spinach Salad',
        'Patra Baked Halloumi and Roasted Fennel',
      ]);
    });

    test('dish titles keep minor words lower case', () {
      final menu = _parse(kMenuKitText).menuFor(MenuVariant.regular);
      expect(menu.first.dishes.last, 'Roasted Fennel with Kalamata Olives');
    });
  });

  group('Both', () {
    MenuKit twoLists(List<String> regular, List<String> vegetarian) => _parse(
      <String>[
        _list(regular),
        'VEGETARIAN SHOPPING LIST',
        'RECIPE PRODUCE QTY NOTES EST. COST',
        ...vegetarian,
      ].join('\n'),
    );

    test('keeps the pricier amount when the lists disagree, noting both', () {
      final kit = twoLists(
        <String>['Th Eggs 1 dozen - \$4.00'],
        <String>['M, Th Eggs 18-count large - \$6.00'],
      );
      final eggs = kit.itemsFor(MenuVariant.both).single;
      expect(eggs.displayAmount, '18-count large');
      expect(eggs.costCents, 600);
      expect(eggs.days, <String>['Mon', 'Thu']);
      expect(eggs.note, startsWith('Regular 1 dozen · Vegetarian 18-count'));
    });

    test('identical lines merge their days and keep their note', () {
      final kit = twoLists(
        <String>['M Fennel 2 medium Keep fronds \$3.00'],
        <String>['W Fennel 2 medium Keep fronds \$3.00'],
      );
      final fennel = kit.itemsFor(MenuVariant.both).single;
      expect(fennel.days, <String>['Mon', 'Wed']);
      expect(fennel.note, 'Keep fronds');
      expect(fennel.costCents, 300);
    });

    test('each vegetarian line pairs with at most one regular line', () {
      final kit = twoLists(
        <String>[
          'M Anchovies 2 oz can - \$3.00',
          'M Anchovy paste 1 tube - \$4.00',
        ],
        <String>['M Ancovies 2 oz can - \$3.00'],
      );
      final both = kit.itemsFor(MenuVariant.both);
      expect(both.map((MenuKitItem i) => i.name), <String>[
        'Anchovies',
        'Anchovy paste',
      ]);
      expect(_named(both, 'Anchovy paste').note, 'Regular menu');
    });

    test('lines only one menu needs are labelled with that menu', () {
      final kit = twoLists(
        <String>['T Cod 12 ounces Skinless \$9.00'],
        <String>['T Halloumi 12 ounces - \$8.00'],
      );
      final both = kit.itemsFor(MenuVariant.both);
      expect(_named(both, 'Cod').note, 'Regular menu · Skinless');
      expect(_named(both, 'Halloumi').note, 'Vegetarian menu');
    });
  });

  group('recipes', () {
    MenuKit recipePage(List<String> lines) => _parse(
      <String>[
        _list(<String>['M Fennel 2 - \$3.00']),
        _header,
        'BEAN PLAKI',
        'ROASTED FENNEL',
        ...lines,
      ].join('\n'),
    );

    test('without a servings line the recipe serves one', () {
      final kit = recipePage(<String>[
        'INGREDIENTS\tINSTRUCTIONS',
        '2 Tablespoons olive oil\t1. Heat the oven.',
        'COMMON SUBSTITUTIONS',
      ]);
      expect(kit.recipes.single.servings, 1);
      expect(kit.recipes.single.title, 'Bean Plaki');
    });

    test('a recipe ends at the next page header without a footer', () {
      final kit = recipePage(<String>[
        'Serves: 2',
        'INGREDIENTS\tINSTRUCTIONS',
        '1 lemon\t1. Juice it.',
        _header,
        'ZERO-WASTE AUDIT',
        '2 lemons left over',
      ]);
      expect(
        kit.recipes.single.ingredients.map((ParsedIngredient i) => i.name),
        <String>['lemon'],
      );
    });

    test('a page with no ingredient lines is not saved', () {
      final kit = recipePage(<String>[
        'INGREDIENTS\tINSTRUCTIONS',
        '\t1. Heat the oven.',
        '\t2. Bake.',
        'COMMON SUBSTITUTIONS',
      ]);
      expect(kit.recipes, isEmpty);
    });

    test('decimal amounts are ingredients, numbered steps are not', () {
      final kit = recipePage(<String>[
        'INGREDIENTS\tINSTRUCTIONS',
        '1.5 ounces feta, crumbled\t1. Crumble.',
        '2.Bake 10 minutes.',
        'COMMON SUBSTITUTIONS',
      ]);
      final names = kit.recipes.single.ingredients
          .map((ParsedIngredient i) => i.name)
          .toList();
      expect(names, <String>['feta']);
    });

    test('pages that are not recipes are ignored', () {
      final kit = _parse(
        <String>[
          _list(<String>['M Fennel 2 - \$3.00']),
          _header,
          'WEEKLY PREP GUIDE',
          'Cook the barley Sunday.',
          'MEDITERRANEAN | FALL | PATRAS, GREECE',
          'WINE IN PATRAS',
          'INGREDIENTS\tINSTRUCTIONS',
          '1 bottle wine\t1. Pour.',
        ].join('\n'),
      );
      expect(kit.recipes, isEmpty);
    });
  });

  group('similarNames', () {
    test('short names must match exactly', () {
      expect(similarNames('Kale', 'Kail'), isFalse);
      expect(similarNames('Dill', 'Dill'), isTrue);
      expect(similarNames('Figs', 'Fig'), isTrue);
    });

    test('allow one edit for medium names and two for long ones', () {
      expect(similarNames('Shallot', 'Shalot'), isTrue);
      expect(similarNames('Shallot', 'Shalet'), isFalse);
      expect(
        similarNames('Roasted Butternut Squash', 'Roasted Butternt Sqash'),
        isTrue,
      );
      expect(
        similarNames('Roasted Butternut Squash', 'Roasted Acorn Squash'),
        isFalse,
      );
    });

    test('ignores case and spacing', () {
      expect(similarNames('BABY  SPINACH', 'baby spinach'), isTrue);
    });
  });

  group('older layouts', () {
    // June 2025: one page per day with a main and a side, single-letter day
    // codes, `RECIPE #` table headings and a colon-form vegetarian list.
    const spring = '''
MEDITERRANEAN IN SPRING | JUNE 16–20
PROVENCE, FRANCE
MENU
MONDAY
WARM LENTILS
ARTICHOKE SALAD
MEDITERRANEAN | MONDAY JUNE 16
WARM LENTILS
ARTICHOKE SALAD
Serves: 4 | Prep Time: 15 minutes
MAIN: INGREDIENTS\tINSTRUCTIONS
1 cup dry green lentils, rinsed\t1.Cook lentils.
2 cups water\t2.Drain.
Serves: 4 | Prep Time: 10 minutes
SIDE: INGREDIENTS\tINSTRUCTIONS
1 bunch asparagus, trimmed\t1.Steam asparagus.
1 lemon, juiced\t2.Squeeze lemon.
SHOPPING LIST
RECIPE #\tPRODUCE\tQTY\tNOTES\tEST.  COST *
M\tAsparagus\t1 bunch\tFresh\t\$3.00
T, W\tLemon\t2\t-\t\$1.00
RECIPE #\tDAIRY\tQTY\tNOTES\tEST.  COST *
M\tFeta\t4 oz\tBlock\t\$2.00
PANTRY\tQTY\tPANTRY\tQTY
Olive oil\t1 cup\tSalt\tAs needed
Prices are based on a aggregate of grocery costs from across the U.S.
They do not reflect organic, grass fed, or other premium ingredients.
SHOPPING LIST: VEGETARIAN
RECIPE\tPRODUCE\tQTY\tNOTES\tEST. COST *
M\tAsparagus\t1 bunch\tFresh\t\$3.00
PANTRY\tQTY\tPANTRY\tQTY
Green lentils OR\t2 cups dry OR\tSalt\tAs needed
SHOPPING LIST: SNACKS
RECIPE #\tPRODUCE\tQTY\tNOTES\tEST. COST *
1\tZucchini\t2 medium\t-\t\$1.50
''';

    // Late 2025 – mid 2026: the place stands in for the date, each dish has
    // its own page, and the vegetarian list is flagged on the page header.
    const autumn = '''
MEDITERRANEAN FALL | SAMOS, GREECE
SAMOS
MENU
MONDAY
SPICED LENTIL STEW
SAGE BREADCRUMBS
MEDITERRANEAN FALL | SAMOS, GREECE | MONDAY
SPICED LENTIL STEW
A story about the dish.
Serves: 4 | Prep Time: 20 minutes
MAIN: INGREDIENTS\tINSTRUCTIONS
1 cup lentils\t1.Simmer lentils.
MEDITERRANEAN FALL | SAMOS, GREECE | MONDAY
SAGE BREADCRUMBS
A story about the side.
Serves: 4 | Prep Time: 5 minutes
SIDE: INGREDIENTS\tINSTRUCTIONS
2 slices sourdough\t1.Toast the bread.
MEDITERRANEAN FALL | SAMOS, GREECE | VEGETARIAN | TUESDAY
EGGPLANT STEW
A story about the vegetarian dish.
Serves: 4 | Prep Time: 15 minutes
MAIN: INGREDIENTS\tINSTRUCTIONS
1 eggplant\t1.Bake the eggplant.
MEDITERRANEAN FALL | SAMOS, GREECE
SHOPPING LIST
RECIPE\tPRODUCE\tQTY\tNOTES\tEST. COST
M\tLentils\t1 cup\t-\t\$2.00
MEDITERRANEAN FALL | SAMOS, GREECE | VEGETARIAN
SHOPPING LIST
RECIPE\tPRODUCE\tQTY\tNOTES\tEST. COST
T\tEggplant\t1\t-\t\$3.00
''';

    test('reads a daily-page week with a colon-form vegetarian list', () {
      final kit = _parse(spring);
      expect(kit.title, 'Mediterranean');
      expect(kit.week, 'June 16–20');
      expect(kit.place, 'Provence, France');

      final regular = kit
          .itemsFor(MenuVariant.regular)
          .map((MenuKitItem item) => item.name);
      expect(
        regular,
        containsAll(<String>[
          'Asparagus',
          'Lemon',
          'Feta',
          'Olive oil',
          'Salt',
        ]),
      );
      expect(
        regular.any((String name) => name.startsWith('Prices are based')),
        isFalse,
      );
      expect(regular, isNot(contains('Zucchini')));

      final vegetarian = kit.itemsFor(MenuVariant.vegetarian);
      final lentils = _named(vegetarian, 'Green lentils');
      expect(lentils.amountText, '2 cups dry');
      expect(vegetarian.map((MenuKitItem item) => item.name), contains('Salt'));

      expect(kit.recipes, hasLength(2));
      expect(kit.recipes.first.title, 'Warm Lentils');
      expect(kit.recipes.first.side, isFalse);
      expect(kit.recipes.last.title, 'Artichoke Salad');
      expect(kit.recipes.last.side, isTrue);
      final ingredientNames = kit.recipes
          .expand(
            (MenuKitRecipe recipe) =>
                recipe.ingredients.map((ParsedIngredient i) => i.name),
          )
          .toList();
      expect(
        ingredientNames.any((String name) => name.contains('Cook lentils')),
        isFalse,
      );
    });

    test('reads place-headed pages and a page-header vegetarian list', () {
      final kit = _parse(autumn);
      expect(kit.title, 'Mediterranean');
      expect(kit.place, 'Samos, Greece');
      expect(
        kit.itemsFor(MenuVariant.regular).map((MenuKitItem i) => i.name),
        <String>['Lentils'],
      );
      expect(
        kit.itemsFor(MenuVariant.vegetarian).map((MenuKitItem i) => i.name),
        <String>['Eggplant'],
      );

      expect(kit.recipes.map((MenuKitRecipe recipe) => recipe.title), <String>[
        'Spiced Lentil Stew',
        'Sage Breadcrumbs',
        'Eggplant Stew',
      ]);
      expect(kit.recipes[1].side, isTrue);
      expect(kit.recipes[0].variants, <MenuVariant>{MenuVariant.regular});
      expect(kit.recipes[2].variants, <MenuVariant>{MenuVariant.vegetarian});
    });
  });

  group('DocumentParser routing', () {
    test('a kit wins over the generic list reading', () {
      final document = const DocumentParser().parseDocument(kMenuKitText);
      expect(document.menuKit, isNotNull);
      expect(document.title, 'Mediterranean');
      expect(document.isRecipe, isFalse);
    });

    test('a plain list is unaffected', () {
      final document = const DocumentParser().parseDocument(
        '2 kg flour\nMilk\n',
      );
      expect(document.menuKit, isNull);
      expect(document.items.map((ParsedIngredient i) => i.name), <String>[
        'flour',
        'Milk',
      ]);
    });
  });
}
