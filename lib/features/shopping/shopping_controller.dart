import 'dart:async';
import 'package:flutter/foundation.dart';
import 'data/shopping_store.dart';
import 'models/quantity.dart';
import 'models/recipe.dart';
import 'models/shopping_item.dart';
import 'models/shopping_list.dart';
import 'models/unit.dart';
import 'parsing/document_parser.dart';
import 'parsing/ingredient_parser.dart';

/// Owns the shopping lists, recipes, and display preferences.
///
/// Every mutation schedules a debounced save through [ShoppingStore]. Tests can
/// await [flush] to force a write immediately.
class ShoppingController extends ChangeNotifier {
  ShoppingController({ShoppingStore? store, DateTime Function()? clock})
      : _store = store ?? ShoppingStore(),
        _clock = clock ?? DateTime.now;

  final ShoppingStore _store;
  final DateTime Function() _clock;

  final List<ShoppingList> _lists = [];
  final List<Recipe> _recipes = [];
  String? _activeListId;
  bool _preferImperial = false;
  bool _loaded = false;
  int _idCounter = 0;
  Timer? _saveTimer;

  List<ShoppingList> get lists => List.unmodifiable(_lists);

  List<Recipe> get recipes => List.unmodifiable(_recipes);

  String? get activeListId => _activeListId;

  bool get preferImperial => _preferImperial;

  bool get isLoaded => _loaded;

  /// The active list, falling back to the first list when the stored id is
  /// stale. Null only when no list exists.
  ShoppingList? get activeList {
    for (final list in _lists) {
      if (list.id == _activeListId) return list;
    }
    return _lists.isEmpty ? null : _lists.first;
  }

  Recipe? recipeById(String recipeId) {
    for (final recipe in _recipes) {
      if (recipe.id == recipeId) return recipe;
    }
    return null;
  }

  ShoppingList? listById(String listId) {
    for (final list in _lists) {
      if (list.id == listId) return list;
    }
    return null;
  }

  Future<void> load() async {
    final data = await _store.load();
    _lists
      ..clear()
      ..addAll(data.lists);
    _recipes
      ..clear()
      ..addAll(data.recipes);
    _activeListId = data.activeListId;
    _preferImperial = data.preferImperial;
    if (_activeListId == null && _lists.isNotEmpty) {
      _activeListId = _lists.first.id;
    }
    _loaded = true;
    notifyListeners();
  }

  ShoppingList createList(String name, {String? id}) {
    final now = _clock();
    final trimmed = name.trim();
    final list = ShoppingList(
      id: id ?? _newId('list'),
      name: trimmed.isEmpty ? 'Shopping List' : trimmed,
      items: const [],
      createdAt: now,
      updatedAt: now,
    );
    _lists.add(list);
    _activeListId ??= list.id;
    _afterMutation();
    return list;
  }

  void renameList(String listId, String name) {
    final index = _lists.indexWhere((list) => list.id == listId);
    if (index < 0) return;
    final trimmed = name.trim();
    _lists[index] = _lists[index].copyWith(
      name: trimmed.isEmpty ? _lists[index].name : trimmed,
      updatedAt: _clock(),
    );
    _afterMutation();
  }

  void deleteList(String listId) {
    final before = _lists.length;
    _lists.removeWhere((list) => list.id == listId);
    if (_lists.length == before) return;
    if (_activeListId == listId) {
      _activeListId = _lists.isEmpty ? null : _lists.first.id;
    }
    _afterMutation();
  }

  void setActiveList(String listId) {
    if (_activeListId == listId || listById(listId) == null) return;
    _activeListId = listId;
    _afterMutation();
  }

  void addItem(String listId, ShoppingItem item) {
    final index = _lists.indexWhere((list) => list.id == listId);
    if (index < 0) return;
    _lists[index] = _lists[index].addOrMerge(item, now: _clock());
    _afterMutation();
  }

  /// Parses [line] and merges it into the active list.
  ShoppingItem? quickAdd(String line) => addParsed(line: line);

  /// Parses [line] into an item and merges it into the active list.
  ///
  /// [unitOverride] replaces the unit the parser found — or supplies one when
  /// none was typed, in which case the amount defaults to one. [frozen] forces
  /// the item into the Frozen aisle regardless of the parser's guess.
  ShoppingItem? addParsed({
    required String line,
    Unit? unitOverride,
    bool frozen = false,
  }) {
    final parsed = const IngredientParser().parseLine(line);
    if (parsed.name.isEmpty) return null;
    final list = _activeOrCreate();
    final Quantity? quantity = unitOverride == null
        ? parsed.quantity
        : Quantity(parsed.quantity?.amount ?? 1, unitOverride);
    final item = ShoppingItem(
      id: _newId('item'),
      name: parsed.name,
      quantity: quantity,
      aisle: frozen ? 'Frozen' : parsed.aisle,
      note: parsed.note,
    );
    final index = _lists.indexWhere((candidate) => candidate.id == list.id);
    _lists[index] = list.addOrMerge(item, now: _clock());
    _afterMutation();
    return item;
  }

  void toggleChecked(String listId, String itemId) {
    final index = _lists.indexWhere((list) => list.id == listId);
    if (index < 0) return;
    final list = _lists[index];
    final itemIndex = list.items.indexWhere((item) => item.id == itemId);
    if (itemIndex < 0) return;
    final item = list.items[itemIndex];
    final bool next = !item.checked;
    final items = List<ShoppingItem>.of(list.items);
    items[itemIndex] = item.copyWith(checked: next);

    if (next) {
      // Keep semantics: checking a parent checks its children.
      for (var i = 0; i < items.length; i++) {
        if (items[i].parentId == itemId && !items[i].checked) {
          items[i] = items[i].copyWith(checked: true);
        }
      }
    } else {
      // A parent and its children stay in sync when the parent is unchecked.
      for (var i = 0; i < items.length; i++) {
        if (items[i].parentId == itemId && items[i].checked) {
          items[i] = items[i].copyWith(checked: false);
        }
      }
      // Keep semantics: unchecking a child unchecks its checked parent.
      final String? parentId = item.parentId;
      if (parentId != null) {
        final int parentIndex = items.indexWhere((entry) => entry.id == parentId);
        if (parentIndex >= 0 && items[parentIndex].checked) {
          items[parentIndex] = items[parentIndex].copyWith(checked: false);
        }
      }
    }

    _lists[index] = list.copyWith(items: items, updatedAt: _clock());
    _afterMutation();
  }

  /// Indents [itemId] under the nearest preceding top-level unchecked item in
  /// the same aisle group.
  ///
  /// A no-op when there is no such item, when the item is already a child, or
  /// when the item has children itself (indentation is one level deep).
  void indentItem(String listId, String itemId) {
    final index = _lists.indexWhere((list) => list.id == listId);
    if (index < 0) return;
    final list = _lists[index];
    final itemIndex = list.items.indexWhere((item) => item.id == itemId);
    if (itemIndex < 0) return;
    final item = list.items[itemIndex];
    if (item.checked || item.parentId != null) return;
    if (_hasChildren(list, itemId)) return;

    for (var i = itemIndex - 1; i >= 0; i--) {
      final candidate = list.items[i];
      if (candidate.checked || candidate.parentId != null) continue;
      if (candidate.aisle != item.aisle) continue;
      final items = List<ShoppingItem>.of(list.items);
      items[itemIndex] = item.copyWith(parentId: candidate.id);
      _lists[index] = list.copyWith(items: items, updatedAt: _clock());
      _afterMutation();
      return;
    }
  }

  /// Clears the indentation of [itemId], making it a top-level row again.
  void outdentItem(String listId, String itemId) {
    final index = _lists.indexWhere((list) => list.id == listId);
    if (index < 0) return;
    final list = _lists[index];
    final itemIndex = list.items.indexWhere((item) => item.id == itemId);
    if (itemIndex < 0) return;
    final item = list.items[itemIndex];
    if (item.parentId == null) return;
    final items = List<ShoppingItem>.of(list.items);
    items[itemIndex] = item.copyWith(clearParent: true);
    _lists[index] = list.copyWith(items: items, updatedAt: _clock());
    _afterMutation();
  }

  /// Whether [indentItem] would change anything for [itemId].
  bool canIndent(String listId, String itemId) {
    final list = listById(listId);
    if (list == null) return false;
    final item = list.itemById(itemId);
    if (item == null || item.checked || item.parentId != null) return false;
    final itemIndex = list.items.indexWhere((entry) => entry.id == itemId);
    if (itemIndex < 0 || _hasChildren(list, itemId)) return false;
    return _precedingTopLevel(list, itemIndex, item.aisle) != null;
  }

  /// Whether [outdentItem] would change anything for [itemId].
  bool canOutdent(String listId, String itemId) =>
      listById(listId)?.itemById(itemId)?.parentId != null;

  ShoppingItem? _precedingTopLevel(ShoppingList list, int before, String aisle) {
    for (var i = before - 1; i >= 0; i--) {
      final candidate = list.items[i];
      if (candidate.checked || candidate.parentId != null) continue;
      if (candidate.aisle != aisle) continue;
      return candidate;
    }
    return null;
  }

  bool _hasChildren(ShoppingList list, String itemId) =>
      list.items.any((item) => item.parentId == itemId);

  /// Moves [itemId] and its children to [newIndexWithinAisle] among the
  /// unchecked top-level items of its aisle.
  ///
  /// The index is clamped to the aisle, so a reorder never crosses into another
  /// aisle. Items that are checked or already indented are left alone.
  void moveItem(String listId, String itemId, int newIndexWithinAisle) {
    final index = _lists.indexWhere((list) => list.id == listId);
    if (index < 0) return;
    final list = _lists[index];
    final item = list.itemById(itemId);
    if (item == null || item.checked || item.parentId != null) return;
    final String aisle = item.aisle;

    // Each unit is a top-level unchecked item followed by its children.
    final units = <List<ShoppingItem>>[];
    for (final candidate in list.items) {
      if (candidate.checked || candidate.parentId != null) continue;
      if (candidate.aisle != aisle) continue;
      units.add(<ShoppingItem>[
        candidate,
        ...list.items.where((child) => child.parentId == candidate.id),
      ]);
    }
    final int current = units.indexWhere((unit) => unit.first.id == itemId);
    if (current < 0) return;
    final int target = newIndexWithinAisle.clamp(0, units.length - 1);
    if (target == current) return;

    final List<ShoppingItem> moved = units.removeAt(current);
    units.insert(target, moved);
    final reordered = <ShoppingItem>[for (final unit in units) ...unit];
    final Set<String> unitIds = reordered.map((entry) => entry.id).toSet();

    // Write the reordered units back into the same slots so items from other
    // aisles and the checked ("Done") section keep their positions.
    final items = List<ShoppingItem>.of(list.items);
    var cursor = 0;
    for (var i = 0; i < items.length; i++) {
      if (unitIds.contains(items[i].id)) {
        items[i] = reordered[cursor++];
      }
    }
    _lists[index] = list.copyWith(items: items, updatedAt: _clock());
    _afterMutation();
  }

  /// Moves [itemId] one position up within its aisle (or among its siblings).
  void moveItemUp(String listId, String itemId) =>
      _moveItemRelative(listId, itemId, -1);

  /// Moves [itemId] one position down within its aisle (or among its siblings).
  void moveItemDown(String listId, String itemId) =>
      _moveItemRelative(listId, itemId, 1);

  bool canMoveUp(String listId, String itemId) =>
      _moveTarget(listId, itemId, -1) != null;

  bool canMoveDown(String listId, String itemId) =>
      _moveTarget(listId, itemId, 1) != null;

  void _moveItemRelative(String listId, String itemId, int delta) {
    final index = _lists.indexWhere((list) => list.id == listId);
    final int? target = _moveTarget(listId, itemId, delta);
    if (index < 0 || target == null) return;
    final list = _lists[index];
    final item = list.itemById(itemId);
    if (item == null) return;

    if (item.parentId == null) {
      moveItem(listId, itemId, target);
      return;
    }

    // A child moves among its siblings; swap the two slots.
    final siblings = <ShoppingItem>[
      for (final entry in list.items)
        if (entry.parentId == item.parentId) entry,
    ];
    final int current = siblings.indexWhere((entry) => entry.id == itemId);
    if (current < 0 || target < 0 || target >= siblings.length) return;
    final int movingIndex = list.items.indexWhere((entry) => entry.id == itemId);
    final int targetIndex =
        list.items.indexWhere((entry) => entry.id == siblings[target].id);
    if (movingIndex < 0 || targetIndex < 0) return;
    final items = List<ShoppingItem>.of(list.items);
    final ShoppingItem other = items[targetIndex];
    items[targetIndex] = items[movingIndex];
    items[movingIndex] = other;
    _lists[index] = list.copyWith(items: items, updatedAt: _clock());
    _afterMutation();
  }

  /// The index [delta] would move [itemId] to, or null when out of range.
  int? _moveTarget(String listId, String itemId, int delta) {
    final list = listById(listId);
    if (list == null) return null;
    final item = list.itemById(itemId);
    if (item == null || item.checked) return null;
    if (item.parentId == null) {
      final units = <ShoppingItem>[
        for (final entry in list.items)
          if (!entry.checked && entry.parentId == null && entry.aisle == item.aisle)
            entry,
      ];
      final int current = units.indexWhere((entry) => entry.id == itemId);
      if (current < 0) return null;
      final int target = current + delta;
      return target < 0 || target >= units.length ? null : target;
    }
    final siblings = <ShoppingItem>[
      for (final entry in list.items)
        if (entry.parentId == item.parentId) entry,
    ];
    final int current = siblings.indexWhere((entry) => entry.id == itemId);
    if (current < 0) return null;
    final int target = current + delta;
    return target < 0 || target >= siblings.length ? null : target;
  }

  /// Replaces the item with the same id on [listId].
  void updateItem(String listId, ShoppingItem item) {
    final index = _lists.indexWhere((list) => list.id == listId);
    if (index < 0) return;
    final list = _lists[index];
    final itemIndex =
        list.items.indexWhere((candidate) => candidate.id == item.id);
    if (itemIndex < 0) return;
    final items = List<ShoppingItem>.of(list.items);
    items[itemIndex] = item;
    _lists[index] = list.copyWith(items: items, updatedAt: _clock());
    _afterMutation();
  }

  /// Unchecks every checked item on [listId].
  void uncheckAll(String listId) {
    final index = _lists.indexWhere((list) => list.id == listId);
    if (index < 0) return;
    final list = _lists[index];
    if (list.checkedCount == 0) return;
    final items = list.items
        .map((item) => item.checked ? item.copyWith(checked: false) : item)
        .toList();
    _lists[index] = list.copyWith(items: items, updatedAt: _clock());
    _afterMutation();
  }

  /// Sets whether the checked ("Done") section of [listId] is collapsed.
  void setCheckedCollapsed(String listId, bool collapsed) {
    final index = _lists.indexWhere((list) => list.id == listId);
    if (index < 0) return;
    if (_lists[index].checkedCollapsed == collapsed) return;
    _lists[index] = _lists[index].copyWith(
      checkedCollapsed: collapsed,
      updatedAt: _clock(),
    );
    _afterMutation();
  }

  /// Up to four name suggestions for [query], drawn from every list's history.
  ///
  /// Matching is case-insensitive on [ShoppingItem.normalizedName], prefix
  /// matches before contains matches. Names already unchecked on the active
  /// list are skipped because they are on the list already, duplicates are
  /// collapsed, and the result never exceeds four entries.
  List<String> suggestionsFor(String query) {
    final String normalized = ShoppingItem.normalizeName(query);
    if (normalized.isEmpty) return const <String>[];
    final ShoppingList? active = activeList;
    final Set<String> excluded = <String>{
      if (active != null)
        for (final ShoppingItem item in active.items)
          if (!item.checked) item.normalizedName,
    };
    final List<String> prefix = <String>[];
    final List<String> contains = <String>[];
    final Set<String> seen = <String>{};
    for (final ShoppingList list in _lists) {
      for (final ShoppingItem item in list.items) {
        final String key = item.normalizedName;
        if (key.isEmpty || excluded.contains(key) || !seen.add(key)) continue;
        if (key.startsWith(normalized)) {
          prefix.add(item.name);
        } else if (key.contains(normalized)) {
          contains.add(item.name);
        }
      }
    }
    return <String>[...prefix, ...contains].take(4).toList();
  }

  void removeItem(String listId, String itemId) {
    final index = _lists.indexWhere((list) => list.id == listId);
    if (index < 0) return;
    final list = _lists[index];
    if (list.itemById(itemId) == null) return;
    // Deleting a parent promotes its children rather than deleting them.
    final items = <ShoppingItem>[
      for (final item in list.items)
        if (item.id != itemId)
          item.parentId == itemId ? item.copyWith(clearParent: true) : item,
    ];
    _lists[index] = list.copyWith(items: items, updatedAt: _clock());
    _afterMutation();
  }

  /// Removes the checked items from [listId] and returns them.
  ///
  /// The returned items let a caller offer an undo; an empty list means nothing
  /// was checked.
  List<ShoppingItem> clearChecked(String listId) {
    final index = _lists.indexWhere((list) => list.id == listId);
    if (index < 0) return const <ShoppingItem>[];
    final list = _lists[index];
    final removed =
        list.items.where((item) => item.checked).toList(growable: false);
    if (removed.isEmpty) return const <ShoppingItem>[];
    final Set<String> removedIds = removed.map((item) => item.id).toSet();
    final items = <ShoppingItem>[
      for (final item in list.items)
        if (!item.checked)
          removedIds.contains(item.parentId)
              ? item.copyWith(clearParent: true)
              : item,
    ];
    _lists[index] = list.copyWith(items: items, updatedAt: _clock());
    _afterMutation();
    return removed;
  }

  /// Re-inserts [items] on [listId] without merging, for an undo.
  void restoreItems(String listId, List<ShoppingItem> items) {
    if (items.isEmpty) return;
    final index = _lists.indexWhere((list) => list.id == listId);
    if (index < 0) return;
    final list = _lists[index];
    _lists[index] = list.copyWith(
      items: <ShoppingItem>[...list.items, ...items],
      updatedAt: _clock(),
    );
    _afterMutation();
  }

  Recipe addRecipe(Recipe recipe) {
    final index = _recipes.indexWhere((candidate) => candidate.id == recipe.id);
    if (index >= 0) {
      _recipes[index] = recipe;
    } else {
      _recipes.add(recipe);
    }
    _afterMutation();
    return recipe;
  }

  void setRecipeServings(String recipeId, int servings) {
    if (servings < 1) return;
    final index = _recipes.indexWhere((recipe) => recipe.id == recipeId);
    if (index < 0) return;
    _recipes[index] = _recipes[index].copyWith(targetServings: servings);
    _afterMutation();
  }

  void addRecipeToList(String recipeId, String listId) {
    final recipe = recipeById(recipeId);
    final listIndex = _lists.indexWhere((list) => list.id == listId);
    if (recipe == null || listIndex < 0) return;

    var updated = _lists[listIndex];
    for (final ingredient in recipe.scaledIngredients) {
      final item = ShoppingItem(
        id: _newId('item'),
        name: ingredient.name,
        quantity: ingredient.quantity,
        aisle: IngredientParser.guessAisle(ingredient.name),
        note: ingredient.note,
        sourceRecipeId: recipe.id,
      );
      updated = updated.addOrMerge(item, now: _clock());
    }
    _lists[listIndex] = updated;
    _afterMutation();
  }

  /// Adds the selected lines of [document] to the active list.
  ///
  /// A recipe document additionally registers a [Recipe] from the same
  /// selection, using its detected servings as both the base and current
  /// serving count.
  void importParsedDocument(ParsedDocument document, List<int> selectedIndices) {
    final selected = <ParsedIngredient>[];
    for (final index in selectedIndices) {
      if (index >= 0 && index < document.items.length) {
        selected.add(document.items[index]);
      }
    }
    if (selected.isEmpty) return;

    if (document.isRecipe && document.title != null) {
      final servings = document.servings ?? 1;
      addRecipe(
        Recipe(
          id: _newId('recipe'),
          title: document.title!,
          baseServings: servings,
          targetServings: servings,
          ingredients: selected
              .map(
                (parsed) => Ingredient(
                  name: parsed.name,
                  quantity: parsed.quantity,
                  note: parsed.note,
                ),
              )
              .toList(),
        ),
      );
    }

    final list = _activeOrCreate();
    final index = _lists.indexWhere((candidate) => candidate.id == list.id);
    var updated = list;
    for (final parsed in selected) {
      updated = updated.addOrMerge(
        ShoppingItem(
          id: _newId('item'),
          name: parsed.name,
          quantity: parsed.quantity,
          aisle: parsed.aisle,
          note: parsed.note,
        ),
        now: _clock(),
      );
    }
    _lists[index] = updated;
    _afterMutation();
  }

  void setPreferImperial(bool value) {
    if (_preferImperial == value) return;
    _preferImperial = value;
    _afterMutation();
  }

  /// Forces any pending debounced save to complete now.
  Future<void> flush() async {
    _saveTimer?.cancel();
    _saveTimer = null;
    await _saveNow();
  }

  ShoppingList _activeOrCreate() {
    final existing = activeList;
    if (existing != null) return existing;
    return createList('Shopping List');
  }

  String _newId(String prefix) {
    _idCounter += 1;
    return '${prefix}_${_clock().microsecondsSinceEpoch}_$_idCounter';
  }

  void _afterMutation() {
    notifyListeners();
    _scheduleSave();
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 250), () {
      _saveTimer = null;
      unawaited(_saveNow());
    });
  }

  Future<void> _saveNow() {
    return _store.save(
      ShoppingStoreData(
        lists: _lists,
        recipes: _recipes,
        activeListId: _activeListId,
        preferImperial: _preferImperial,
      ),
    );
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _saveTimer = null;
    super.dispose();
  }
}
