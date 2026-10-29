import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mylauncher/features/shopping/parsing/ingredient_parser.dart';
import 'package:mylauncher/features/shopping/parsing/menu_kit_parser.dart';

import '../../tool/menu_kit/corrections.dart';
import '../../tool/menu_kit/payload.dart';
import 'menu_kit_fixture.dart';

void main() {
  final MenuKit kit = const MenuKitParser().tryParse(kMenuKitText)!;
  final String sha = 'a' * 64;
  late Map<String, Object?> payload;

  setUp(() {
    payload = menuKitPayload(
      kit,
      sourceFile: 'Mediterranean_October2.pdf',
      pdfSha256: sha,
      pdfPath: '$sha.pdf',
    );
  });

  List<Map<String, Object?>> listOf(String key) =>
      (payload[key]! as List<Object?>).cast<Map<String, Object?>>();

  group('weekStart', () {
    test('reads printed weeks', () {
      expect(weekStart('October 2nd, 2026'), DateTime.utc(2026, 10, 2));
      expect(weekStart('October 23, 2026'), DateTime.utc(2026, 10, 23));
      expect(weekStart('march 1st 2027'), DateTime.utc(2027, 3, 1));
    });

    test('rejects anything that is not a real date', () {
      expect(weekStart(null), isNull);
      expect(weekStart('Fall 2026'), isNull);
      expect(weekStart('Octember 2, 2026'), isNull);
      expect(weekStart('February 30, 2026'), isNull);
    });
  });

  group('menuKitPayload', () {
    test('describes the week and the stored file', () {
      expect(payload['title'], 'Mediterranean');
      expect(payload['week_label'], 'October 2nd, 2026');
      expect(payload['week_start'], '2026-10-02');
      expect(payload['place'], 'Patras, Greece');
      expect(payload['source_file'], 'Mediterranean_October2.pdf');
      expect(payload['pdf_sha256'], sha);
      expect(payload['pdf_path'], '$sha.pdf');
    });

    test('stores both printed menus, not the derived Both', () {
      final menus = listOf('menus');
      expect(menus.map((m) => m['variant']).toSet(), <String>{
        'regular',
        'vegetarian',
      });
      expect(menus.first, <String, Object?>{
        'variant': 'regular',
        'day': 'Mon',
        'dishes': <String>[
          'Patra Baked Gigantes Bean Plaki',
          'Roasted Fennel with Kalamata Olives',
        ],
      });
    });

    test('stores every printed list line with a position per list', () {
      final items = listOf('items');
      final regular = items.where((i) => i['variant'] == 'regular').toList();
      final vegetarian = items
          .where((i) => i['variant'] == 'vegetarian')
          .toList();
      expect(regular, hasLength(kit.itemsFor(MenuVariant.regular).length));
      expect(
        vegetarian,
        hasLength(kit.itemsFor(MenuVariant.vegetarian).length),
      );
      expect(regular.map((i) => i['position']), <int>[
        for (var i = 0; i < regular.length; i++) i,
      ]);
      expect(vegetarian.first['position'], 0);
      expect(items.map((i) => i['variant']), isNot(contains('both')));
    });

    test('keeps printed and structured amounts apart', () {
      final items = listOf('items');
      final fennel = items.firstWhere((i) => i['name'] == 'Fennel');
      expect(fennel, containsPair('amount_text', '4 medium bulbs'));
      expect(fennel, containsPair('quantity_amount', null));
      expect(fennel, containsPair('quantity_unit', null));
      expect(fennel, containsPair('cost_cents', 700));
      expect(fennel['days'], <String>['Mon', 'Tue', 'Wed']);
      expect(fennel, containsPair('pantry', false));

      final feta = items.firstWhere((i) => i['name'] == 'Feta cheese');
      expect(feta, containsPair('amount_text', null));
      expect(feta, containsPair('quantity_amount', 12.0));
      expect(feta, containsPair('quantity_unit', 'oz'));

      final capers = items.firstWhere((i) => i['name'] == 'Capers');
      expect(capers, containsPair('pantry', true));
      expect(capers, containsPair('cost_cents', null));
    });

    test('stores recipes with their menus and ordered ingredients', () {
      final recipes = listOf('recipes');
      expect(recipes.map((r) => r['position']), <int>[0, 1, 2]);
      final cod = recipes.first;
      expect(cod['title'], 'Patra Baked Cod and Roasted Fennel');
      expect(cod['servings'], 4);
      expect(cod['side'], false);
      expect(cod['variants'], <String>['regular']);
      expect(recipes[2]['variants'], <String>['regular', 'vegetarian']);
      final ingredients = (cod['ingredients']! as List<Object?>)
          .cast<Map<String, Object?>>();
      expect(ingredients.first, <String, Object?>{
        'name': 'medium fennel bulb',
        'quantity_amount': 1.0,
        'quantity_unit': 'pc',
        'note': 'thinly sliced',
      });
    });

    test('stores recipe descriptions, times, steps and nutrition', () {
      final recipes = listOf('recipes');
      final cod = recipes.first;
      expect(cod['description'], 'A short story about the dish.');
      expect(cod['prep_minutes'], 10);
      expect(cod['cook_minutes'], 20);
      expect(cod['rest_minutes'], null);
      expect((cod['steps']! as List<String>).first, 'Heat oven to 400°F.');
      expect(cod['nutrition'], <String, double>{
        'calories_kcal': 300,
        'protein_g': 24,
        'carbs_g': 8,
      });
      // The halloumi page prints no nutrition.
      expect(recipes[1]['nutrition'], null);
    });

    test('is plain JSON', () {
      final decoded = jsonDecode(jsonEncode(payload)) as Map<String, Object?>;
      expect(decoded['title'], 'Mediterranean');
      expect((decoded['items']! as List<Object?>), isNotEmpty);
    });
  });

  group('duplicate recipe titles', () {
    test('a dish printed for both menus is one row with both variants', () {
      const kit = MenuKit(
        title: 'Mediterranean',
        recipes: <MenuKitRecipe>[
          MenuKitRecipe(
            title: 'Creamy Polenta',
            servings: 4,
            ingredients: <ParsedIngredient>[],
            variants: <MenuVariant>{MenuVariant.regular},
          ),
          MenuKitRecipe(
            title: 'Creamy Polenta',
            servings: 4,
            ingredients: <ParsedIngredient>[],
            side: true,
            variants: <MenuVariant>{MenuVariant.vegetarian},
          ),
        ],
      );
      final duplicatePayload = menuKitPayload(
        kit,
        sourceFile: 'Mediterranean_20251128.pdf',
        pdfSha256: sha,
      );
      final recipes = (duplicatePayload['recipes']! as List<Object?>)
          .cast<Map<String, Object?>>();
      expect(recipes, hasLength(1));
      expect(recipes.single['variants'], <String>['regular', 'vegetarian']);
    });
  });

  group('applyCorrections', () {
    const String pdf = 'Mediterranean_October2.pdf';
    const String cod = 'Patra Baked Cod and Roasted Fennel';
    List<Map<String, Object?>> ingredientsOf(Map<String, Object?> recipe) =>
        (recipe['ingredients']! as List<Object?>).cast<Map<String, Object?>>();

    test('renames and replaces what the correction gives', () {
      applyCorrections(payload, <Map<String, Object?>>[
        <String, Object?>{
          'pdf': pdf,
          'title': cod,
          'why': 'The PDF serves lemon wedges it never lists.',
          'rename': 'Patra Cod',
          'cook_minutes': 25,
          'steps': <String>['Bake the cod.'],
          'nutrition': null,
          'remove_ingredients': <String>['medium fennel bulb'],
          'add_ingredients': <String>['1 lemon, cut into wedges'],
        },
      ]);
      final recipe = listOf('recipes').first;
      expect(recipe['title'], 'Patra Cod');
      expect(recipe['cook_minutes'], 25);
      expect(recipe['steps'], <String>['Bake the cod.']);
      expect(recipe['nutrition'], isNull);
      final ingredients = ingredientsOf(recipe);
      expect(
        ingredients.map((Map<String, Object?> i) => i['name']),
        isNot(contains('medium fennel bulb')),
      );
      expect(ingredients.last, <String, Object?>{
        'name': 'lemon',
        'quantity_amount': 1.0,
        'quantity_unit': 'pc',
        'note': 'cut into wedges',
      });
    });

    test('skips other PDFs and refuses stale or unexplained corrections', () {
      applyCorrections(payload, <Map<String, Object?>>[
        <String, Object?>{'pdf': 'Other.pdf', 'title': 'Gone', 'why': 'x'},
      ]);
      expect(
        () => applyCorrections(payload, <Map<String, Object?>>[
          <String, Object?>{'pdf': pdf, 'title': 'Gone', 'why': 'x'},
        ]),
        throwsStateError,
      );
      expect(
        () => applyCorrections(payload, <Map<String, Object?>>[
          <String, Object?>{
            'pdf': pdf,
            'title': cod,
            'why': 'x',
            'remove_ingredients': <String>['saffron'],
          },
        ]),
        throwsStateError,
      );
      expect(
        () => applyCorrections(payload, <Map<String, Object?>>[
          <String, Object?>{'pdf': pdf, 'title': cod, 'step': <String>[]},
        ]),
        throwsFormatException,
      );
    });
  });
}
