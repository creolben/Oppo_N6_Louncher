import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mylauncher/features/shopping/data/shopping_store.dart';
import 'package:mylauncher/features/shopping/models/quantity.dart';
import 'package:mylauncher/features/shopping/models/shopping_item.dart';
import 'package:mylauncher/features/shopping/models/shopping_list.dart';
import 'package:mylauncher/features/shopping/models/unit.dart';
import 'package:mylauncher/features/shopping/shopping_controller.dart';

void main() {
  late Directory directory;
  late ShoppingStore store;
  late ShoppingController controller;

  setUp(() async {
    directory = Directory.systemTemp.createTempSync('shopping_keep_test');
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

  group('addParsed', () {
    test('a unit override replaces the parsed unit', () {
      controller.createList('Groceries');
      controller.addParsed(line: '2 chicken', unitOverride: Unit.kilogram);

      final ShoppingItem item = controller.activeList!.items.single;
      expect(item.quantity, const Quantity(2, Unit.kilogram));
      expect(item.name, 'chicken');
    });

    test('a unit override with no amount implies one', () {
      controller.createList('Groceries');
      controller.addParsed(line: 'chicken', unitOverride: Unit.kilogram);

      expect(
        controller.activeList!.items.single.quantity,
        const Quantity(1, Unit.kilogram),
      );
    });

    test('frozen forces the Frozen aisle', () {
      controller.createList('Groceries');
      controller.addParsed(line: '2 chicken', frozen: true);

      final ShoppingItem item = controller.activeList!.items.single;
      expect(item.aisle, 'Frozen');
      expect(item.quantity, const Quantity(2, Unit.piece));
    });

    test('quickAdd still parses without overrides', () {
      controller.createList('Groceries');
      controller.quickAdd('2 kg chicken');

      expect(
        controller.activeList!.items.single.quantity,
        const Quantity(2, Unit.kilogram),
      );
      expect(controller.activeList!.items.single.aisle, 'Meat & Fish');
    });
  });

  group('item mutations', () {
    test('uncheckAll clears every checked flag', () {
      final ShoppingList list = controller.createList('Groceries');
      controller.quickAdd('milk');
      controller.quickAdd('eggs');
      for (final ShoppingItem item in controller.activeList!.items) {
        controller.toggleChecked(list.id, item.id);
      }
      expect(controller.activeList!.checkedCount, 2);

      controller.uncheckAll(list.id);
      expect(controller.activeList!.checkedCount, 0);
    });

    test('updateItem replaces name, quantity, aisle and note', () {
      final ShoppingList list = controller.createList('Groceries');
      controller.quickAdd('2 kg chicken');
      final ShoppingItem original = controller.activeList!.items.single;

      controller.updateItem(
        list.id,
        original.copyWith(
          name: 'tofu',
          quantity: const Quantity(500, Unit.gram),
          aisle: 'Produce',
          note: 'firm',
        ),
      );

      final ShoppingItem updated = controller.activeList!.items.single;
      expect(updated.id, original.id);
      expect(updated.name, 'tofu');
      expect(updated.quantity, const Quantity(500, Unit.gram));
      expect(updated.aisle, 'Produce');
      expect(updated.note, 'firm');
    });

    test(
      'clearChecked returns removed items and restoreItems puts them back',
      () {
        final ShoppingList list = controller.createList('Groceries');
        controller.quickAdd('milk');
        controller.quickAdd('eggs');
        final String milkId = controller.activeList!.items
            .firstWhere((ShoppingItem item) => item.name == 'milk')
            .id;
        controller.toggleChecked(list.id, milkId);

        final List<RemovedItem> removed = controller.clearChecked(list.id);
        expect(removed, hasLength(1));
        expect(removed.single.item.name, 'milk');
        expect(controller.activeList!.items, hasLength(1));

        controller.restoreItems(list.id, removed);
        expect(controller.activeList!.items, hasLength(2));
        expect(controller.activeList!.checkedCount, 1);
      },
    );

    test('setCheckedCollapsed toggles and stops on no-ops', () {
      final ShoppingList list = controller.createList('Groceries');
      expect(controller.activeList!.checkedCollapsed, isFalse);

      controller.setCheckedCollapsed(list.id, true);
      expect(controller.activeList!.checkedCollapsed, isTrue);

      controller.setCheckedCollapsed(list.id, true);
      expect(controller.activeList!.checkedCollapsed, isTrue);

      controller.setCheckedCollapsed(list.id, false);
      expect(controller.activeList!.checkedCollapsed, isFalse);
    });
  });

  group('suggestionsFor', () {
    test('returns prior names and excludes active unchecked ones', () {
      controller.createList('Groceries');
      controller.quickAdd('Milk');

      // Milk is on the active list, so switch to another list where it is
      // history rather than a current entry.
      final ShoppingList hardware = controller.createList('Hardware');
      controller.setActiveList(hardware.id);
      expect(controller.suggestionsFor('mi'), contains('Milk'));
      expect(controller.suggestionsFor('MIL'), contains('Milk'));

      // Once milk is unchecked on the active list it is no longer suggested.
      controller.quickAdd('Milk');
      expect(controller.suggestionsFor('mi'), isEmpty);
    });

    test('prefix matches rank before contains matches and caps at four', () {
      controller.createList('Groceries');
      controller.quickAdd('Milk');
      controller.quickAdd('Oat milk');
      controller.quickAdd('Almond milk');
      controller.quickAdd('Milk chocolate');
      controller.quickAdd('Milk powder');
      controller.quickAdd('Buttermilk');

      // The active list holds all six unchecked, so clear it to make them
      // history again.
      final ShoppingList history = controller.activeList!;
      for (final ShoppingItem item in List<ShoppingItem>.of(history.items)) {
        controller.toggleChecked(history.id, item.id);
      }
      final List<String> suggestions = controller.suggestionsFor('milk');

      expect(suggestions.length, lessThanOrEqualTo(4));
      expect(suggestions.take(4).first, 'Milk');
      expect(suggestions, contains('Milk'));
    });
  });

  group('checkedCollapsed persistence', () {
    test('round trips through JSON', () {
      final ShoppingList list = controller.createList('Groceries');
      controller.setCheckedCollapsed(list.id, true);

      final Map<String, dynamic> json = controller.activeList!.toJson();
      final ShoppingList decoded = ShoppingList.fromJson(
        jsonDecode(jsonEncode(json)) as Map<String, dynamic>,
      );
      expect(decoded.checkedCollapsed, isTrue);
      expect(decoded, controller.activeList);
    });

    test('old JSON without the field loads as false', () {
      final Map<String, dynamic> oldJson = <String, dynamic>{
        'id': 'l1',
        'name': 'Old list',
        'items': const <dynamic>[],
        'createdAt': DateTime(2026, 1, 1).toIso8601String(),
        'updatedAt': DateTime(2026, 1, 1).toIso8601String(),
      };
      expect(ShoppingList.fromJson(oldJson).checkedCollapsed, isFalse);
    });
  });

  group('parentId model', () {
    test('round trips through JSON and copyWith can clear it', () {
      const item = ShoppingItem(id: 'c1', name: 'child', parentId: 'p1');
      final decoded = ShoppingItem.fromJson(
        jsonDecode(jsonEncode(item.toJson())) as Map<String, dynamic>,
      );
      expect(decoded.parentId, 'p1');
      expect(decoded, item);

      expect(item.copyWith().parentId, 'p1');
      expect(item.copyWith(parentId: 'p2').parentId, 'p2');
      expect(item.copyWith(clearParent: true).parentId, isNull);
    });

    test('legacy JSON without parentId loads as null and toJson omits it', () {
      final Map<String, dynamic> legacy = <String, dynamic>{
        'id': 'i1',
        'name': 'milk',
        'aisle': 'Other',
        'checked': false,
      };
      final ShoppingItem decoded = ShoppingItem.fromJson(legacy);
      expect(decoded.parentId, isNull);
      expect(decoded.name, 'milk');

      const topLevel = ShoppingItem(id: 'i2', name: 'eggs');
      expect(topLevel.toJson().containsKey('parentId'), isFalse);
    });

    test('a parentId difference is part of equality', () {
      const topLevel = ShoppingItem(id: 'i1', name: 'milk');
      const child = ShoppingItem(id: 'i1', name: 'milk', parentId: 'p1');
      expect(topLevel == child, isFalse);
      expect(topLevel.hashCode == child.hashCode, isFalse);
    });
  });

  group('indent and outdent', () {
    ShoppingList seedProduce() {
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
      return controller.activeList!;
    }

    test('indent makes an item a child of the nearest preceding top-level row',
        () {
      final ShoppingList list = seedProduce();
      controller.indentItem(list.id, 'b');

      expect(controller.activeList!.itemById('b')!.parentId, 'a');
      expect(controller.activeList!.itemById('a')!.parentId, isNull);
    });

    test('the first item in an aisle and other aisles have no parent', () {
      final ShoppingList list = seedProduce();
      controller.indentItem(list.id, 'a');
      expect(controller.activeList!.itemById('a')!.parentId, isNull);

      controller.addItem(
        list.id,
        const ShoppingItem(id: 'd', name: 'detergent', aisle: 'Household'),
      );
      controller.indentItem(list.id, 'd');
      expect(controller.activeList!.itemById('d')!.parentId, isNull);
    });

    test('indent skips checked rows and existing children', () {
      final ShoppingList list = seedProduce();
      controller.indentItem(list.id, 'b');
      controller.indentItem(list.id, 'c');
      // The nearest top-level row for C is A, because B is already a child.
      expect(controller.activeList!.itemById('c')!.parentId, 'a');

      controller.outdentItem(list.id, 'b');
      controller.toggleChecked(list.id, 'a');
      controller.indentItem(list.id, 'b');
      // A is checked, so there is no unchecked parent to attach to.
      expect(controller.activeList!.itemById('b')!.parentId, isNull);
    });

    test('an item that already has children cannot be indented', () {
      final ShoppingList list = seedProduce();
      controller.indentItem(list.id, 'b');
      controller.indentItem(list.id, 'a');
      expect(controller.activeList!.itemById('a')!.parentId, isNull);
    });

    test('outdent clears the parent and is a no-op for a top-level row', () {
      final ShoppingList list = seedProduce();
      controller.indentItem(list.id, 'b');
      controller.outdentItem(list.id, 'b');
      expect(controller.activeList!.itemById('b')!.parentId, isNull);

      controller.outdentItem(list.id, 'a');
      expect(controller.activeList!.itemById('a')!.parentId, isNull);
    });
  });

  group('parent and child checking', () {
    ShoppingList seedFamily() {
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
      controller.indentItem(list.id, 'b');
      controller.indentItem(list.id, 'c');
      return controller.activeList!;
    }

    test('checking a parent checks its children', () {
      final ShoppingList list = seedFamily();
      controller.toggleChecked(list.id, 'a');

      expect(controller.activeList!.itemById('a')!.checked, isTrue);
      expect(controller.activeList!.itemById('b')!.checked, isTrue);
      expect(controller.activeList!.itemById('c')!.checked, isTrue);
    });

    test('unchecking a child unchecks its checked parent', () {
      final ShoppingList list = seedFamily();
      controller.toggleChecked(list.id, 'a');
      controller.toggleChecked(list.id, 'b');

      expect(controller.activeList!.itemById('b')!.checked, isFalse);
      expect(controller.activeList!.itemById('a')!.checked, isFalse);
    });

    test('unchecking a parent unchecks its children', () {
      final ShoppingList list = seedFamily();
      controller.toggleChecked(list.id, 'a');
      controller.toggleChecked(list.id, 'a');

      expect(controller.activeList!.itemById('a')!.checked, isFalse);
      expect(controller.activeList!.itemById('b')!.checked, isFalse);
      expect(controller.activeList!.itemById('c')!.checked, isFalse);
    });

    test('deleting a parent promotes its children to top level', () {
      final ShoppingList list = seedFamily();
      controller.removeItem(list.id, 'a');

      final ShoppingList updated = controller.activeList!;
      expect(updated.itemById('a'), isNull);
      expect(updated.itemById('b')!.parentId, isNull);
      expect(updated.itemById('c')!.parentId, isNull);
      expect(updated.items, hasLength(2));
    });

    test('merging by name preserves the existing parent', () {
      final ShoppingList list = seedFamily();
      controller.addItem(
        list.id,
        const ShoppingItem(
          id: 'b2',
          name: 'Banana',
          quantity: Quantity(2, Unit.piece),
        ),
      );

      final ShoppingItem merged = controller.activeList!.itemById('b')!;
      expect(controller.activeList!.items, hasLength(3));
      expect(merged.parentId, 'a');
      expect(merged.quantity, const Quantity(2, Unit.piece));
    });
  });

  group('moveItem', () {
    ShoppingList seedAisle() {
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
      return controller.activeList!;
    }

    List<String> ids() =>
        controller.activeList!.items.map((ShoppingItem item) => item.id).toList();

    test('an item and its children move together', () {
      final ShoppingList list = seedAisle();
      controller.indentItem(list.id, 'b');
      controller.moveItem(list.id, 'a', 1);

      expect(ids(), <String>['c', 'a', 'b']);
      expect(controller.activeList!.itemById('b')!.parentId, 'a');
    });

    test('the index is clamped to the aisle', () {
      final ShoppingList list = seedAisle();
      controller.addItem(
        list.id,
        const ShoppingItem(id: 'd', name: 'detergent', aisle: 'Household'),
      );
      controller.indentItem(list.id, 'b');

      controller.moveItem(list.id, 'a', 99);
      expect(ids(), <String>['c', 'a', 'b', 'd']);

      controller.moveItem(list.id, 'c', 5);
      expect(ids(), <String>['a', 'b', 'c', 'd']);
    });

    test('down and up convenience methods respect the aisle edges', () {
      final ShoppingList list = seedAisle();
      controller.moveItemUp(list.id, 'a');
      expect(ids(), <String>['a', 'b', 'c']);

      controller.moveItemDown(list.id, 'c');
      expect(ids(), <String>['a', 'b', 'c']);

      controller.moveItemDown(list.id, 'a');
      expect(ids(), <String>['b', 'a', 'c']);

      controller.moveItemUp(list.id, 'a');
      expect(ids(), <String>['a', 'b', 'c']);
    });

    test('moveItem ignores checked rows and children', () {
      final ShoppingList list = seedAisle();
      controller.indentItem(list.id, 'b');
      controller.moveItem(list.id, 'b', 0);
      expect(ids(), <String>['a', 'b', 'c']);

      controller.toggleChecked(list.id, 'c');
      controller.moveItem(list.id, 'c', 0);
      expect(ids(), <String>['a', 'b', 'c']);
    });

    test('a child moves among its siblings', () {
      final ShoppingList list = seedAisle();
      controller.addItem(
        list.id,
        const ShoppingItem(id: 'e', name: 'endive', aisle: 'Produce'),
      );
      controller.indentItem(list.id, 'b');
      controller.indentItem(list.id, 'c');

      controller.moveItemDown(list.id, 'b');
      expect(ids(), <String>['a', 'c', 'b', 'e']);
      expect(controller.activeList!.itemById('b')!.parentId, 'a');
      expect(controller.activeList!.itemById('c')!.parentId, 'a');

      controller.moveItemUp(list.id, 'b');
      expect(ids(), <String>['a', 'b', 'c', 'e']);

      controller.moveItemUp(list.id, 'b');
      expect(ids(), <String>['a', 'b', 'c', 'e']);
    });
  });

  group('remove and undo', () {
    test('delete then undo keeps the original position', () {
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

      final RemovedItem? removed = controller.removeItem(list.id, 'b');
      expect(removed, isNotNull);
      expect(removed!.index, 1);
      expect(
        controller.activeList!.items.map((ShoppingItem item) => item.id),
        <String>['a', 'c'],
      );

      controller.restoreItems(list.id, <RemovedItem>[removed]);
      expect(
        controller.activeList!.items.map((ShoppingItem item) => item.id),
        <String>['a', 'b', 'c'],
      );
    });

    test('undo does not merge with a same-name item', () {
      final ShoppingList list = controller.createList('Groceries');
      controller.addItem(
        list.id,
        const ShoppingItem(
          id: 'a',
          name: 'pasta',
          quantity: Quantity(2, Unit.box),
        ),
      );
      controller.addItem(
        list.id,
        const ShoppingItem(
          id: 'b',
          name: 'pasta',
          quantity: Quantity(200, Unit.gram),
        ),
      );
      expect(controller.activeList!.items, hasLength(2));

      final RemovedItem removed = controller.removeItem(list.id, 'a')!;
      controller.restoreItems(list.id, <RemovedItem>[removed]);

      expect(controller.activeList!.items, hasLength(2));
      expect(controller.activeList!.items.first.id, 'a');
      expect(
        controller.activeList!.items.first.quantity,
        const Quantity(2, Unit.box),
      );
    });

    test('undo reapplies the parentId of promoted children', () {
      final ShoppingList list = controller.createList('Groceries');
      controller.addItem(
        list.id,
        const ShoppingItem(id: 'a', name: 'apple', aisle: 'Produce'),
      );
      controller.addItem(
        list.id,
        const ShoppingItem(id: 'b', name: 'banana', aisle: 'Produce'),
      );
      controller.indentItem(list.id, 'b');

      final RemovedItem removed = controller.removeItem(list.id, 'a')!;
      expect(controller.activeList!.itemById('b')!.parentId, isNull);

      controller.restoreItems(list.id, <RemovedItem>[removed]);
      expect(controller.activeList!.itemById('b')!.parentId, 'a');
      expect(
        controller.activeList!.items.map((ShoppingItem item) => item.id),
        <String>['a', 'b'],
      );
    });

    test('clearChecked undo restores positions and re-indents children', () {
      final ShoppingList list = controller.createList('Groceries');
      controller.addItem(
        list.id,
        const ShoppingItem(
          id: 'a',
          name: 'apple',
          aisle: 'Produce',
          checked: true,
        ),
      );
      controller.addItem(
        list.id,
        const ShoppingItem(id: 'b', name: 'banana', aisle: 'Produce'),
      );
      controller.addItem(
        list.id,
        const ShoppingItem(
          id: 'c',
          name: 'carrot',
          aisle: 'Produce',
          parentId: 'a',
        ),
      );

      final List<RemovedItem> removed = controller.clearChecked(list.id);
      expect(removed, hasLength(1));
      expect(controller.activeList!.itemById('c')!.parentId, isNull);
      expect(
        controller.activeList!.items.map((ShoppingItem item) => item.id),
        <String>['b', 'c'],
      );

      controller.restoreItems(list.id, removed);
      expect(
        controller.activeList!.items.map((ShoppingItem item) => item.id),
        <String>['a', 'b', 'c'],
      );
      expect(controller.activeList!.itemById('c')!.parentId, 'a');
    });
  });

  group('aisle memory', () {
    test('a remembered aisle is applied on the next add', () {
      final ShoppingList first = controller.createList('Groceries');
      controller.quickAdd('quinoa');
      final ShoppingItem item = controller.activeList!.items.single;
      expect(item.aisle, 'Other');

      controller.updateItem(first.id, item.copyWith(aisle: 'Pantry'));
      expect(controller.aisleFor('quinoa', 'Other'), 'Pantry');

      final ShoppingList second = controller.createList('Second');
      controller.setActiveList(second.id);
      controller.quickAdd('quinoa');
      expect(controller.activeList!.items.single.aisle, 'Pantry');
    });

    test('the Frozen quick-add toggle never records an aisle', () {
      final ShoppingList list = controller.createList('Groceries');
      controller.addParsed(line: 'quinoa', frozen: true);

      expect(controller.activeList!.items.single.aisle, 'Frozen');
      expect(list.id, controller.activeList!.id);
      expect(controller.aisleMemory, isEmpty);
    });

    test('a remembered aisle survives a store round trip', () async {
      final ShoppingList list = controller.createList('Groceries');
      controller.quickAdd('quinoa');
      controller.updateItem(
        list.id,
        controller.activeList!.items.single.copyWith(aisle: 'Pantry'),
      );
      await controller.flush();

      final ShoppingController reloaded = ShoppingController(store: store);
      await reloaded.load();
      expect(reloaded.aisleFor('quinoa', 'Other'), 'Pantry');
      reloaded.dispose();
    });
  });
}
