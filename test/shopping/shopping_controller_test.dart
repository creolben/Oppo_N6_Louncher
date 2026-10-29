import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:mylauncher/features/shopping/data/shopping_store.dart';
import 'package:mylauncher/features/shopping/models/quantity.dart';
import 'package:mylauncher/features/shopping/models/recipe.dart';
import 'package:mylauncher/features/shopping/models/unit.dart';
import 'package:mylauncher/features/shopping/parsing/document_parser.dart';
import 'package:mylauncher/features/shopping/shopping_controller.dart';

void main() {
  late Directory directory;
  late ShoppingStore store;
  late ShoppingController controller;

  setUp(() async {
    directory = Directory.systemTemp.createTempSync('shopping_controller_test');
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

  test('quickAdd parses and merges compatible amounts', () {
    controller.createList('Groceries');
    controller.quickAdd('2 kg chicken');
    controller.quickAdd('1 kg chicken');

    final items = controller.activeList!.items;
    expect(items, hasLength(1));
    expect(items.single.quantity, Quantity(3, Unit.kilogram));
  });

  test('quickAdd keeps incompatible dimensions apart', () {
    controller.createList('Groceries');
    controller.quickAdd('2 boxes pasta');
    controller.quickAdd('500 g pasta');

    expect(controller.activeList!.items, hasLength(2));
  });

  test('quickAdd captures notes and aisles', () {
    controller.createList('Groceries');
    controller.quickAdd('1 can (400 g) tomatoes');

    final item = controller.activeList!.items.single;
    expect(item.quantity, const Quantity(1, Unit.can));
    expect(item.note, '400 g');
    expect(item.aisle, 'Produce');
  });

  test('toggleChecked and clearChecked update the list', () {
    final list = controller.createList('Groceries');
    controller.quickAdd('milk');
    controller.quickAdd('eggs');

    final firstId = controller.activeList!.items.first.id;
    controller.toggleChecked(list.id, firstId);
    expect(controller.activeList!.checkedCount, 1);

    controller.clearChecked(list.id);
    expect(controller.activeList!.items, hasLength(1));
    expect(controller.activeList!.checkedCount, 0);
  });

  test('addRecipeToList scales servings and rounds count up', () {
    final list = controller.createList('Groceries');
    controller.addRecipe(
      const Recipe(
        id: 'r1',
        title: 'Cake',
        baseServings: 4,
        targetServings: 4,
        ingredients: [
          Ingredient(name: 'flour', quantity: Quantity(2, Unit.cup)),
          Ingredient(name: 'eggs', quantity: Quantity(3, Unit.piece)),
        ],
      ),
    );
    controller.setRecipeServings('r1', 6);
    controller.addRecipeToList('r1', list.id);

    final items = controller.activeList!.items;
    expect(items, hasLength(2));
    final flour = items.firstWhere((item) => item.name == 'flour');
    final eggs = items.firstWhere((item) => item.name == 'eggs');
    expect(flour.quantity, const Quantity(3, Unit.cup));
    expect(eggs.quantity, const Quantity(5, Unit.piece));
    expect(eggs.sourceRecipeId, 'r1');
  });

  test('importParsedDocument adds selected lines and registers the recipe', () {
    controller.createList('Groceries');
    const text = 'Pancakes\n'
        '\n'
        'Serves 4\n'
        '\n'
        'Ingredients\n'
        '2 cups flour\n'
        '1 tsp salt\n'
        '3 eggs\n'
        '\n'
        'Method\n'
        'Mix.';
    final document = const DocumentParser().parseDocument(text);
    expect(document.isRecipe, isTrue);

    final recipe = controller.importParsedDocument(document, const [0, 2]);
    // A recipe is saved, not added: the user scales it, then adds it once.
    expect(controller.activeList!.items, isEmpty);
    expect(controller.recipes, hasLength(1));
    expect(recipe, isNotNull);
    expect(controller.recipes.single.title, 'Pancakes');
    expect(controller.recipes.single.baseServings, 4);
    expect(controller.recipes.single.ingredients, hasLength(2));
    expect(controller.pendingRecipeId, recipe!.id);
    expect(controller.takePendingRecipe(), recipe.id);
    expect(controller.pendingRecipeId, isNull);

    // Scaling then adding puts the scaled amounts on the list exactly once.
    controller.setRecipeServings(recipe.id, 8);
    controller.addRecipeToList(recipe.id, controller.activeList!.id);
    final items = controller.activeList!.items;
    expect(items, hasLength(2));
    expect(
      items.firstWhere((item) => item.name == 'flour').quantity,
      const Quantity(4, Unit.cup),
    );
  });

  test('importParsedDocument adds a plain list to the active list', () {
    controller.createList('Groceries');
    final document = const DocumentParser().parseDocument('milk\neggs\nbread');
    expect(document.isRecipe, isFalse);
    expect(controller.importParsedDocument(document, const [0, 2]), isNull);
    expect(controller.activeList!.items, hasLength(2));
    expect(controller.recipes, isEmpty);
  });

  test('recipes can be renamed, removed and restored', () {
    controller.addRecipe(
      const Recipe(id: 'r1', title: 'Cake', baseServings: 2, targetServings: 2),
    );
    controller.addRecipe(
      const Recipe(id: 'r2', title: 'Soup', baseServings: 2, targetServings: 2),
    );
    controller.renameRecipe('r1', '   ');
    expect(controller.recipeById('r1')!.title, 'Cake');
    controller.renameRecipe('r1', ' Lemon cake ');
    expect(controller.recipeById('r1')!.title, 'Lemon cake');

    final removed = controller.removeRecipe('r1');
    expect(removed, isNotNull);
    expect(controller.recipes.map((r) => r.id), ['r2']);
    controller.restoreRecipe(removed!);
    expect(controller.recipes.map((r) => r.id), ['r1', 'r2']);
  });

  test('a default list name is sentence case and renaming to empty keeps it',
      () {
    final list = controller.createList('  ');
    expect(list.name, ShoppingController.defaultListName);
    expect(list.name, 'Shopping list');
    controller.renameList(list.id, '');
    expect(controller.listById(list.id)!.name, 'Shopping list');
  });

  test('editing an item does not learn an aisle it already had', () {
    final list = controller.createList('Groceries');
    controller.addParsed(line: 'peas', frozen: true);
    final item = controller.activeList!.items.single;
    expect(item.aisle, 'Frozen');
    controller.updateItem(list.id, item.copyWith(name: 'garden peas'));
    expect(controller.aisleMemory, isEmpty);

    // An explicit change is remembered.
    controller.updateItem(
      list.id,
      controller.activeList!.items.single.copyWith(aisle: 'Pantry'),
    );
    expect(controller.aisleMemory['garden pea'], 'Pantry');
  });

  test('the store-mode hint dismissal persists', () async {
    expect(controller.storeModeHintDismissed, isFalse);
    controller.dismissStoreModeHint();
    await controller.flush();

    final reloaded = ShoppingController(store: store);
    await reloaded.load();
    expect(reloaded.storeModeHintDismissed, isTrue);
    reloaded.dispose();
  });

  test('mutation state survives a store round trip', () async {
    controller.createList('Groceries');
    controller.quickAdd('2 kg chicken');
    controller.setPreferImperial(true);
    await controller.flush();

    final reloaded = ShoppingController(store: store);
    await reloaded.load();
    expect(reloaded.lists, hasLength(1));
    expect(reloaded.activeList!.items.single.quantity, Quantity(2, Unit.kilogram));
    expect(reloaded.preferImperial, isTrue);
    reloaded.dispose();
  });

  test('deleteList reassigns the active list', () {
    final first = controller.createList('Groceries');
    final second = controller.createList('Hardware');
    expect(controller.activeListId, first.id);

    controller.setActiveList(second.id);
    controller.deleteList(second.id);
    expect(controller.activeListId, first.id);
    expect(controller.lists, hasLength(1));
  });

  group('persistence', () {
    test('mutations before load are merged, not wiped', () async {
      // Seed the store with an existing list.
      controller.createList('Groceries');
      controller.quickAdd('milk');
      await controller.flush();

      final early = ShoppingController(store: store);
      // No load yet: an add creates an implicit list...
      early.quickAdd('eggs');
      early.setPreferImperial(true);
      // ...and nothing is written before the stored state has been read.
      await early.flush();
      final stored = await store.load();
      expect(stored.lists.single.items.single.name, 'milk');

      await early.load();
      expect(early.lists, hasLength(1));
      final names = early.activeList!.items.map((item) => item.name).toSet();
      expect(names, {'milk', 'eggs'});
      expect(early.preferImperial, isTrue);

      await early.flush();
      final saved = await store.load();
      expect(saved.lists.single.items, hasLength(2));
      early.dispose();
    });

    test('flush writes immediately and concurrent saves keep the newest',
        () async {
      controller.createList('Groceries');
      controller.quickAdd('milk');
      final first = controller.flush();
      controller.quickAdd('eggs');
      final second = controller.flush();
      await Future.wait([first, second]);

      final saved = await store.load();
      expect(saved.lists.single.items, hasLength(2));
      final leftovers = directory
          .listSync()
          .where((entity) => entity.path.endsWith('.tmp'));
      expect(leftovers, isEmpty);
    });

    test('dispose flushes a pending debounced save', () async {
      final other = ShoppingController(store: store);
      await other.load();
      other.createList('Hardware');
      other.dispose();
      // The flush is fire-and-forget; give it a moment to land.
      for (var i = 0; i < 50; i++) {
        final saved = await store.load();
        if (saved.lists.isNotEmpty) break;
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      final saved = await store.load();
      expect(saved.lists.single.name, 'Hardware');
    });

    test('a failing store is logged, not thrown', () async {
      final failing = ShoppingController(store: _FailingStore());
      await failing.load();
      failing.createList('Groceries');
      await failing.flush();
      // Still usable after the failure.
      failing.quickAdd('milk');
      expect(failing.activeList!.items, hasLength(1));
      failing.dispose();
    });

    test('mutating after dispose does not throw', () async {
      final other = ShoppingController(store: store);
      await other.load();
      other.dispose();
      expect(() => other.createList('Late'), returnsNormally);
    });
  });
}

class _FailingStore extends ShoppingStore {
  @override
  Future<ShoppingStoreData> load() async => const ShoppingStoreData();

  @override
  Future<void> save(ShoppingStoreData data) async {
    throw const FileSystemException('disk full');
  }
}
