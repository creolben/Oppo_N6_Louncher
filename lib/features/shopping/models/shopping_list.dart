import 'quantity.dart';
import 'shopping_item.dart';

/// How a list orders its unchecked rows.
enum ShoppingSortMode {
  /// Grouped into sticky aisle sections in the canonical store order. This is
  /// the default and is what older stores without a `sortMode` load as.
  byAisle,

  /// A single flat section in the user's own order, shown in "My order".
  manual;

  /// Parses the persisted `sortMode` value, defaulting to [byAisle] for legacy
  /// JSON and for anything unrecognised.
  static ShoppingSortMode fromJson(Object? value) {
    switch (value) {
      case 'manual':
        return ShoppingSortMode.manual;
      case 'byAisle':
      default:
        return ShoppingSortMode.byAisle;
    }
  }

  /// The value written under the `sortMode` JSON key.
  String get jsonValue {
    switch (this) {
      case ShoppingSortMode.byAisle:
        return 'byAisle';
      case ShoppingSortMode.manual:
        return 'manual';
    }
  }
}

/// A named shopping list.
class ShoppingList {
  final String id;
  final String name;
  final List<ShoppingItem> items;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Whether the checked ("Done") section of this list is collapsed.
  ///
  /// Persisted per list; older stores without the field load as `false`.
  final bool checkedCollapsed;

  /// How the unchecked rows of this list are ordered.
  ///
  /// Persisted per list; older stores without the field load as
  /// [ShoppingSortMode.byAisle].
  final ShoppingSortMode sortMode;

  const ShoppingList({
    required this.id,
    required this.name,
    this.items = const [],
    required this.createdAt,
    required this.updatedAt,
    this.checkedCollapsed = false,
    this.sortMode = ShoppingSortMode.byAisle,
  });

  int get checkedCount => items.where((item) => item.checked).length;

  int get remainingCount => items.length - checkedCount;

  ShoppingItem? itemById(String itemId) {
    for (final item in items) {
      if (item.id == itemId) return item;
    }
    return null;
  }

  /// Adds [item], merging it into an existing same-named compatible line.
  ///
  /// A merge into an unchecked line happens only when the normalized names
  /// match **and** the quantities are compatible: two nulls (`milk` + `milk`
  /// dedupes), one null and one set, or two quantities that
  /// [Quantity.tryMerge] accepts. Anything else — a different dimension or two
  /// different packaging units — is appended instead, so `2 boxes pasta` never
  /// folds into `500 g pasta`.
  ///
  /// Re-adding a name that only exists as a *checked* line follows Keep: the
  /// checked line is replaced in place by [item], unchecked, keeping its id, so
  /// the item comes back to the list instead of vanishing into Done.
  ShoppingList addOrMerge(ShoppingItem item, {DateTime? now}) {
    final next = List<ShoppingItem>.of(items);
    for (var i = 0; i < next.length; i++) {
      final existing = next[i];
      if (existing.checked) continue;
      if (existing.normalizedName != item.normalizedName) continue;
      final merged = _mergeQuantities(existing.quantity, item.quantity);
      if (!merged.$1) continue;

      next[i] = ShoppingItem(
        id: existing.id,
        name: existing.name,
        quantity: merged.$2,
        aisle: existing.aisle,
        checked: existing.checked,
        note: existing.note ?? item.note,
        sourceRecipeId: existing.sourceRecipeId ?? item.sourceRecipeId,
        parentId: existing.parentId,
      );
      return copyWith(items: next, updatedAt: now ?? DateTime.now());
    }
    for (var i = 0; i < next.length; i++) {
      final existing = next[i];
      if (!existing.checked) continue;
      if (existing.normalizedName != item.normalizedName) continue;
      next[i] = ShoppingItem(
        id: existing.id,
        name: item.name,
        quantity: item.quantity,
        aisle: item.aisle,
        note: item.note,
        sourceRecipeId: item.sourceRecipeId,
      );
      return copyWith(items: next, updatedAt: now ?? DateTime.now());
    }
    next.add(item);
    return copyWith(items: next, updatedAt: now ?? DateTime.now());
  }

  /// Returns `(compatible, merged)`.
  ///
  /// A pair of nulls is compatible and stays null; one null adopts the other
  /// side's quantity; two quantities merge through [Quantity.tryMerge].
  static (bool, Quantity?) _mergeQuantities(Quantity? a, Quantity? b) {
    if (a == null) return (true, b);
    if (b == null) return (true, a);
    final merged = a.tryMerge(b);
    return (merged != null, merged);
  }

  ShoppingList copyWith({
    String? id,
    String? name,
    List<ShoppingItem>? items,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? checkedCollapsed,
    ShoppingSortMode? sortMode,
  }) {
    return ShoppingList(
      id: id ?? this.id,
      name: name ?? this.name,
      items: items ?? this.items,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      checkedCollapsed: checkedCollapsed ?? this.checkedCollapsed,
      sortMode: sortMode ?? this.sortMode,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'items': items.map((item) => item.toJson()).toList(),
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'checkedCollapsed': checkedCollapsed,
        'sortMode': sortMode.jsonValue,
      };

  /// Parses a stored list. Each item is parsed on its own, so one malformed
  /// item is skipped (and reported through [onSkippedItem]) instead of
  /// discarding the whole list.
  factory ShoppingList.fromJson(
    Map<String, dynamic> json, {
    void Function(Object error)? onSkippedItem,
  }) {
    final items = <ShoppingItem>[];
    for (final raw in json['items'] as List? ?? const []) {
      try {
        items.add(ShoppingItem.fromJson(Map<String, dynamic>.from(raw as Map)));
      } catch (error) {
        onSkippedItem?.call(error);
      }
    }
    return ShoppingList(
      id: json['id'] as String,
      name: json['name'] as String,
      items: items,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      checkedCollapsed: json['checkedCollapsed'] as bool? ?? false,
      sortMode: ShoppingSortMode.fromJson(json['sortMode']),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ShoppingList &&
      other.id == id &&
      other.name == name &&
      _listEquals(other.items, items) &&
      other.createdAt == createdAt &&
      other.updatedAt == updatedAt &&
      other.checkedCollapsed == checkedCollapsed &&
      other.sortMode == sortMode;

  @override
  int get hashCode => Object.hash(
        id,
        name,
        Object.hashAll(items),
        createdAt,
        updatedAt,
        checkedCollapsed,
        sortMode,
      );

  static bool _listEquals(List<ShoppingItem> a, List<ShoppingItem> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  String toString() => 'ShoppingList($id, $name, ${items.length} items)';
}
