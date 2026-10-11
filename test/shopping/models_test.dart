import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:mylauncher/features/shopping/models/quantity.dart';
import 'package:mylauncher/features/shopping/models/recipe.dart';
import 'package:mylauncher/features/shopping/models/shopping_item.dart';
import 'package:mylauncher/features/shopping/models/shopping_list.dart';
import 'package:mylauncher/features/shopping/models/unit.dart';

void main() {
  group('ShoppingItem', () {
    test('normalizedName strips simple plurals', () {
      expect(ShoppingItem.normalizeName('  Onions '), 'onion');
      expect(ShoppingItem.normalizeName('Boxes'), 'box');
      expect(ShoppingItem.normalizeName('Tomatoes'), 'tomato');
      expect(ShoppingItem.normalizeName('Glass'), 'glass');
      expect(ShoppingItem.normalizeName('Cheese'), 'cheese');
      expect(ShoppingItem.normalizeName('Berries'), 'berry');
    });

    test('json round trip', () {
      const item = ShoppingItem(
        id: 'i1',
        name: 'milk',
        quantity: Quantity(2, Unit.liter),
        aisle: 'Dairy & Eggs',
        checked: true,
        note: 'semi-skimmed',
        sourceRecipeId: 'r1',
      );
      final decoded = ShoppingItem.fromJson(
        jsonDecode(jsonEncode(item.toJson())) as Map<String, dynamic>,
      );
      expect(decoded, item);
    });
  });

  group('ShoppingList.addOrMerge', () {
    ShoppingList baseList() => ShoppingList(
          id: 'l1',
          name: 'Groceries',
          createdAt: DateTime(2026, 1, 1),
          updatedAt: DateTime(2026, 1, 1),
        );

    test('merges packaging quantities of the same normalized name', () {
      var list = baseList();
      list = list.addOrMerge(
        const ShoppingItem(
          id: 'a',
          name: 'pasta',
          quantity: Quantity(2, Unit.box),
        ),
      );
      list = list.addOrMerge(
        const ShoppingItem(
          id: 'b',
          name: 'Pasta',
          quantity: Quantity(1, Unit.box),
        ),
      );
      expect(list.items, hasLength(1));
      expect(list.items.single.quantity, const Quantity(3, Unit.box));
    });

    test('converts compatible quantities when merging', () {
      var list = baseList();
      list = list.addOrMerge(
        ShoppingItem(id: 'a', name: 'flour', quantity: Quantity(500, Unit.gram)),
      );
      list = list.addOrMerge(
        ShoppingItem(
          id: 'b',
          name: 'flour',
          quantity: Quantity(1, Unit.kilogram),
        ),
      );
      expect(list.items, hasLength(1));
      expect(list.items.single.quantity, Quantity(1.5, Unit.kilogram));
    });

    test('never merges across dimensions', () {
      var list = baseList();
      list = list.addOrMerge(
        const ShoppingItem(
          id: 'a',
          name: 'pasta',
          quantity: Quantity(2, Unit.box),
        ),
      );
      list = list.addOrMerge(
        ShoppingItem(id: 'b', name: 'pasta', quantity: Quantity(500, Unit.gram)),
      );
      expect(list.items, hasLength(2));
    });

    test('one side with no quantity adopts the other', () {
      var list = baseList();
      list = list.addOrMerge(const ShoppingItem(id: 'a', name: 'Salt'));
      list = list.addOrMerge(
        const ShoppingItem(
          id: 'b',
          name: 'salt',
          quantity: Quantity(1, Unit.teaspoon),
        ),
      );
      expect(list.items, hasLength(1));
      expect(list.items.single.quantity, const Quantity(1, Unit.teaspoon));
    });

    test('keeps the checked flag when merging', () {
      var list = baseList();
      list = list.addOrMerge(
        ShoppingItem(
          id: 'a',
          name: 'milk',
          quantity: Quantity(1, Unit.liter),
          checked: true,
        ),
      );
      list = list.addOrMerge(
        ShoppingItem(id: 'b', name: 'milk', quantity: Quantity(2, Unit.liter)),
      );
      expect(list.items.single.checked, isTrue);
      expect(list.items.single.quantity, Quantity(3, Unit.liter));
    });

    test('different names append', () {
      var list = baseList();
      list = list.addOrMerge(const ShoppingItem(id: 'a', name: 'milk'));
      list = list.addOrMerge(const ShoppingItem(id: 'b', name: 'eggs'));
      expect(list.items, hasLength(2));
    });

    test('json round trip', () {
      var list = baseList();
      list = list.addOrMerge(
        ShoppingItem(
          id: 'a',
          name: 'flour',
          quantity: Quantity(500, Unit.gram),
          note: 'sifted',
        ),
        now: DateTime(2026, 2, 2),
      );
      final decoded = ShoppingList.fromJson(
        jsonDecode(jsonEncode(list.toJson())) as Map<String, dynamic>,
      );
      expect(decoded, list);
    });
  });

  group('Recipe scaling', () {
    final recipe = Recipe(
      id: 'r1',
      title: 'Cake',
      baseServings: 4,
      targetServings: 6,
      ingredients: [
        Ingredient(name: 'flour', quantity: Quantity(2, Unit.cup)),
        Ingredient(name: 'eggs', quantity: Quantity(3, Unit.piece)),
        Ingredient(name: 'salt'),
      ],
    );

    test('scales by target/base and rounds count up', () {
      final scaled = recipe.scaledIngredients;
      expect(scaled[0].quantity!.amount, closeTo(3, 1e-9));
      expect(scaled[0].quantity!.unit, Unit.cup);
      // 3 eggs * 1.5 = 4.5 -> 5
      expect(scaled[1].quantity, const Quantity(5, Unit.piece));
      expect(scaled[2].quantity, isNull);
      expect(recipe.scaleFactor, closeTo(1.5, 1e-9));
    });

    test('json round trip', () {
      final decoded = Recipe.fromJson(
        jsonDecode(jsonEncode(recipe.toJson())) as Map<String, dynamic>,
      );
      expect(decoded, recipe);
    });
  });
}
