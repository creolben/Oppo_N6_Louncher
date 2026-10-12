import 'quantity.dart';
import 'shopping_item.dart';

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

  const ShoppingList({
    required this.id,
    required this.name,
    this.items = const [],
    required this.createdAt,
    required this.updatedAt,
    this.checkedCollapsed = false,
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
  /// A merge happens only when the normalized names match **and** the
  /// quantities are compatible: two nulls, one null and one set, or two
  /// quantities that [Quantity.tryMerge] accepts. Anything else — a different
  /// dimension or two different packaging units — is appended instead, so
  /// `2 boxes pasta` never folds into `500 g pasta`.
  ShoppingList addOrMerge(ShoppingItem item, {DateTime? now}) {
    final next = List<ShoppingItem>.of(items);
    for (var i = 0; i < next.length; i++) {
      final existing = next[i];
      if (existing.normalizedName != item.normalizedName) continue;
      final mergedQuantity = _mergeQuantities(existing.quantity, item.quantity);
      if (mergedQuantity == null) continue;

      next[i] = existing.copyWith(
        quantity: mergedQuantity,
        note: existing.note ?? item.note,
        sourceRecipeId: existing.sourceRecipeId ?? item.sourceRecipeId,
      );
      return copyWith(items: next, updatedAt: now ?? DateTime.now());
    }
    next.add(item);
    return copyWith(items: next, updatedAt: now ?? DateTime.now());
  }

  /// Returns the merged quantity, or null when the two are incompatible.
  ///
  /// A pair of nulls is compatible and yields null; one null adopts the other
  /// side's quantity.
  static Quantity? _mergeQuantities(Quantity? a, Quantity? b) {
    if (a == null) return b;
    if (b == null) return a;
    return a.tryMerge(b);
  }

  ShoppingList copyWith({
    String? id,
    String? name,
    List<ShoppingItem>? items,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? checkedCollapsed,
  }) {
    return ShoppingList(
      id: id ?? this.id,
      name: name ?? this.name,
      items: items ?? this.items,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      checkedCollapsed: checkedCollapsed ?? this.checkedCollapsed,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'items': items.map((item) => item.toJson()).toList(),
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'checkedCollapsed': checkedCollapsed,
      };

  factory ShoppingList.fromJson(Map<String, dynamic> json) {
    return ShoppingList(
      id: json['id'] as String,
      name: json['name'] as String,
      items: (json['items'] as List? ?? const [])
          .map((item) => ShoppingItem.fromJson(
                Map<String, dynamic>.from(item as Map),
              ))
          .toList(),
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      checkedCollapsed: json['checkedCollapsed'] as bool? ?? false,
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
      other.checkedCollapsed == checkedCollapsed;

  @override
  int get hashCode => Object.hash(
        id,
        name,
        Object.hashAll(items),
        createdAt,
        updatedAt,
        checkedCollapsed,
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
