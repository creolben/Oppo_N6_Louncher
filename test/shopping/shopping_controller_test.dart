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

    controller.importParsedDocument(document, const [0, 2]);
    expect(controller.activeList!.items, hasLength(2));
    expect(controller.recipes, hasLength(1));
    expect(controller.recipes.single.title, 'Pancakes');
    expect(controller.recipes.single.baseServings, 4);
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
}
