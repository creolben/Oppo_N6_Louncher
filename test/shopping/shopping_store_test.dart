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
      aisleMemory: const <String, String>{'quinoa': 'Pantry'},
      storeMode: true,
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
    expect(loaded.aisleMemory, const <String, String>{'quinoa': 'Pantry'});
    expect(loaded.storeMode, isTrue);
  });

  test('old JSON without aisleMemory loads as an empty map', () async {
    final Map<String, dynamic> legacy = <String, dynamic>{
      'lists': const <dynamic>[],
      'recipes': const <dynamic>[],
      'activeListId': null,
      'preferImperial': false,
    };
    final loaded = ShoppingStoreData.fromJson(legacy);
    expect(loaded.aisleMemory, isEmpty);
    expect(loaded.storeMode, isFalse);
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

    final backups = directory
        .listSync()
        .where((entity) =>
            entity.uri.pathSegments.last
                .startsWith('${ShoppingStore.fileName}.corrupt.'))
        .toList();
    expect(backups, hasLength(1));
    expect(file.existsSync(), isFalse);

    // A second corrupt file gets its own backup instead of overwriting.
    file.writeAsStringSync('also broken');
    await store.load();
    final second = directory
        .listSync()
        .where((entity) =>
            entity.uri.pathSegments.last
                .startsWith('${ShoppingStore.fileName}.corrupt.'))
        .toList();
    expect(second, hasLength(2));
  });

  test('one malformed item or list does not discard the rest', () async {
    final file = File(filePath());
    file.writeAsStringSync('''
{
  "lists": [
    {
      "id": "l1",
      "name": "Groceries",
      "createdAt": "2026-01-01T12:00:00.000",
      "updatedAt": "2026-01-01T12:00:00.000",
      "items": [
        {"id": "a", "name": "milk"},
        {"id": "b", "name": "flour", "quantity": {"amount": 1, "unit": "zz"}},
        {"name": 42}
      ]
    },
    {"id": "broken"}
  ],
  "recipes": [{"title": 5}],
  "storeModeHintDismissed": true
}
''');
    final loaded = await store.load();
    expect(loaded.lists, hasLength(1));
    expect(loaded.lists.single.items.single.name, 'milk');
    expect(loaded.recipes, isEmpty);
    expect(loaded.storeModeHintDismissed, isTrue);
    expect(loaded.skippedEntries, 4);
    // The original stays in place and a copy is kept for recovery.
    expect(file.existsSync(), isTrue);
    expect(
      directory.listSync().where((entity) =>
          entity.uri.pathSegments.last.contains('.corrupt.')),
      hasLength(1),
    );
  });

  test('stores without newer keys load with defaults', () async {
    File(filePath()).writeAsStringSync('{"lists": []}');
    final loaded = await store.load();
    expect(loaded.storeModeHintDismissed, isFalse);
    expect(loaded.storeMode, isFalse);
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
