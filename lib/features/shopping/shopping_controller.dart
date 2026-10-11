import 'dart:async';
import 'package:flutter/foundation.dart';
import 'data/shopping_store.dart';
import 'models/recipe.dart';
import 'models/shopping_item.dart';
import 'models/shopping_list.dart';
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
  ShoppingItem? quickAdd(String line) {
    final parsed = const IngredientParser().parseLine(line);
    if (parsed.name.isEmpty) return null;
    final list = _activeOrCreate();
    final item = ShoppingItem(
      id: _newId('item'),
      name: parsed.name,
      quantity: parsed.quantity,
      aisle: parsed.aisle,
      note: parsed.note,
    );
    final index = _lists.indexWhere((candidate) => candidate.id == list.id);
    _lists[index] = list.addOrMerge(item, now: _clock());
    _afterMutation();
    return item;
  }

  void toggleChecked(String listId, String itemId) {
    _mutateItem(
      listId,
      itemId,
      (item) => item.copyWith(checked: !item.checked),
    );
  }

  void removeItem(String listId, String itemId) {
    final index = _lists.indexWhere((list) => list.id == listId);
    if (index < 0) return;
    final list = _lists[index];
    final items = list.items.where((item) => item.id != itemId).toList();
    if (items.length == list.items.length) return;
    _lists[index] = list.copyWith(items: items, updatedAt: _clock());
    _afterMutation();
  }

  void clearChecked(String listId) {
    final index = _lists.indexWhere((list) => list.id == listId);
    if (index < 0) return;
    final list = _lists[index];
    final items = list.items.where((item) => !item.checked).toList();
    if (items.length == list.items.length) return;
    _lists[index] = list.copyWith(items: items, updatedAt: _clock());
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

  void _mutateItem(
    String listId,
    String itemId,
    ShoppingItem Function(ShoppingItem item) transform,
  ) {
    final index = _lists.indexWhere((list) => list.id == listId);
    if (index < 0) return;
    final list = _lists[index];
    final itemIndex = list.items.indexWhere((item) => item.id == itemId);
    if (itemIndex < 0) return;
    final items = List<ShoppingItem>.of(list.items);
    items[itemIndex] = transform(items[itemIndex]);
    _lists[index] = list.copyWith(items: items, updatedAt: _clock());
    _afterMutation();
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
