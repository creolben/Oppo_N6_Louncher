import 'quantity.dart';

/// One line on a shopping list.
class ShoppingItem {
  final String id;
  final String name;
  final Quantity? quantity;
  final String aisle;
  final bool checked;
  final String? note;
  final String? sourceRecipeId;

  const ShoppingItem({
    required this.id,
    required this.name,
    this.quantity,
    this.aisle = 'Other',
    this.checked = false,
    this.note,
    this.sourceRecipeId,
  });

  /// Name used for duplicate detection: lower-cased, trimmed, whitespace
  /// collapsed, and with a simple English plural ending stripped.
  String get normalizedName => normalizeName(name);

  static String normalizeName(String value) {
    var text = value
        .toLowerCase()
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ');
    if (text.isEmpty) return text;
    if (text.length > 3 && text.endsWith('ies')) {
      return '${text.substring(0, text.length - 3)}y';
    }
    if (text.length > 3 && RegExp(r'(?:s|x|z|ch|sh|o)es$').hasMatch(text)) {
      return text.substring(0, text.length - 2);
    }
    if (text.length > 2 && text.endsWith('s') && !text.endsWith('ss')) {
      return text.substring(0, text.length - 1);
    }
    return text;
  }

  ShoppingItem copyWith({
    String? id,
    String? name,
    Quantity? quantity,
    String? aisle,
    bool? checked,
    String? note,
    String? sourceRecipeId,
  }) {
    return ShoppingItem(
      id: id ?? this.id,
      name: name ?? this.name,
      quantity: quantity ?? this.quantity,
      aisle: aisle ?? this.aisle,
      checked: checked ?? this.checked,
      note: note ?? this.note,
      sourceRecipeId: sourceRecipeId ?? this.sourceRecipeId,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        if (quantity != null) 'quantity': quantity!.toJson(),
        'aisle': aisle,
        'checked': checked,
        if (note != null) 'note': note,
        if (sourceRecipeId != null) 'sourceRecipeId': sourceRecipeId,
      };

  factory ShoppingItem.fromJson(Map<String, dynamic> json) {
    final rawQuantity = json['quantity'];
    return ShoppingItem(
      id: json['id'] as String,
      name: json['name'] as String,
      quantity: rawQuantity is Map
          ? Quantity.fromJson(Map<String, dynamic>.from(rawQuantity))
          : null,
      aisle: json['aisle'] as String? ?? 'Other',
      checked: json['checked'] as bool? ?? false,
      note: json['note'] as String?,
      sourceRecipeId: json['sourceRecipeId'] as String?,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ShoppingItem &&
      other.id == id &&
      other.name == name &&
      other.quantity == quantity &&
      other.aisle == aisle &&
      other.checked == checked &&
      other.note == note &&
      other.sourceRecipeId == sourceRecipeId;

  @override
  int get hashCode =>
      Object.hash(id, name, quantity, aisle, checked, note, sourceRecipeId);

  @override
  String toString() => 'ShoppingItem($id, $name, $quantity)';
}
