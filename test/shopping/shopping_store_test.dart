import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:mylauncher/features/shopping/data/shopping_store.dart';
import 'package:mylauncher/features/shopping/models/quantity.dart';
import 'package:mylauncher/features/shopping/models/recipe.dart';
import 'package:mylauncher/features/shopping/models/shopping_item.dart';
import 'package:mylauncher/features/shopping/models/shopping_list.dart';
import 'package:mylauncher/features/shopping/models/unit.dart';

void main() {
  late Directory directory;
  late ShoppingStore store;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('shopping_store_test');
    store = ShoppingStore(directoryPath: directory.path);
  });

  tearDown(() {
    if (directory.existsSync()) {
      directory.deleteSync(recursive: true);
    }
  });

  String filePath() => '${directory.path}/${ShoppingStore.fileName}';

  ShoppingStoreData sampleData() {
    final now = DateTime(2026, 1, 1, 12);
    return ShoppingStoreData(
      lists: [
        ShoppingList(
          id: 'l1',
          name: 'Groceries',
          items: [
            const ShoppingItem(
              id: 'i1',
              name: 'milk',
              quantity: Quantity(1, Unit.liter),
              aisle: 'Dairy & Eggs',
            ),
            const ShoppingItem(id: 'i2', name: 'bread', checked: true),
          ],
          createdAt: now,
          updatedAt: now,
        ),
      ],
      recipes: const [
        Recipe(
          id: 'r1',
          title: 'Cake',
          baseServings: 4,
          targetServings: 6,
          ingredients: [
            Ingredient(name: 'flour', quantity: Quantity(2, Unit.cup)),
          ],
        ),
      ],
      activeListId: 'l1',
      preferImperial: true,
    );
  }

  test('round-trips lists and recipes atomically', () async {
    final data = sampleData();
    await store.save(data);

    expect(File(filePath()).existsSync(), isTrue);
    expect(File('$filePath().tmp').existsSync(), isFalse);
    expect(await store.hasStoredData, isTrue);

    final loaded = await store.load();
    expect(loaded.lists, hasLength(1));
    expect(loaded.lists.single, data.lists.single);
    expect(loaded.recipes.single, data.recipes.single);
    expect(loaded.activeListId, 'l1');
    expect(loaded.preferImperial, isTrue);
  });

  test('loading a missing file yields empty state', () async {
    final loaded = await store.load();
    expect(loaded.lists, isEmpty);
    expect(loaded.recipes, isEmpty);
    expect(loaded.activeListId, isNull);
    expect(await store.hasStoredData, isFalse);
  });

  test('a corrupt file is backed up and treated as empty', () async {
    final file = File(filePath());
    file.writeAsStringSync('{ this is not valid json');
    expect(file.existsSync(), isTrue);

    final loaded = await store.load();
    expect(loaded.lists, isEmpty);
    expect(loaded.recipes, isEmpty);

    final backup = File('${filePath()}.corrupt');
    expect(backup.existsSync(), isTrue);
    expect(file.existsSync(), isFalse);
  });

  test('a later save replaces the previous state', () async {
    await store.save(sampleData());
    final now = DateTime(2026, 2, 2);
    await store.save(
      ShoppingStoreData(
        lists: [
          ShoppingList(
            id: 'l2',
            name: 'Hardware',
            createdAt: now,
            updatedAt: now,
          ),
        ],
      ),
    );

    final loaded = await store.load();
    expect(loaded.lists.single.id, 'l2');
    expect(loaded.recipes, isEmpty);
    expect(loaded.activeListId, isNull);
  });
}
