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

  /// The id of the top-level item this line is indented under, or null.
  ///
  /// Indentation is one level deep, so a child never has children of its own.
  final String? parentId;

  /// A free-form amount from an imported list (`4 medium bulbs`,
  /// `1 (¾ oz) package`) that [Quantity] cannot represent. Shown only when
  /// [quantity] is null.
  final String? amountText;

  /// The source's estimated price for this line, in cents.
  final int? costCents;

  /// The weekdays this line is cooked on, as short names (`Mon`, `Thu`), in
  /// week order. Empty for anything not imported from a meal plan.
  final List<String> days;

  const ShoppingItem({
    required this.id,
    required this.name,
    this.quantity,
    this.aisle = 'Other',
    this.checked = false,
    this.note,
    this.sourceRecipeId,
    this.parentId,
    this.amountText,
    this.costCents,
    this.days = const <String>[],
  });

  /// What the row shows as the amount: the structured [quantity] when there is
  /// one, otherwise the imported [amountText].
  String get displayAmount =>
      quantity?.formatAsEntered() ?? amountText ?? '';

  /// Name used for duplicate detection: lower-cased, trimmed, whitespace
  /// collapsed, and with a simple English plural ending stripped.
  String get normalizedName => normalizeName(name);

  static String normalizeName(String value) {
    var text = value
        .toLowerCase()
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ');
    if (text.isEmpty) return text;
    // `berries`/`berry` and `cookies`/`cookie` must meet at one key, so both
    // `-ies` and a bare `-ie` fold to `-y`. Short words keep their `-ie`
    // (`pie`/`pies` stay `pie`).
    if (text.length > 4 && text.endsWith('ies')) {
      return '${text.substring(0, text.length - 3)}y';
    }
    if (text.length > 3 && text.endsWith('ie')) {
      return '${text.substring(0, text.length - 2)}y';
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
    String? parentId,
    bool clearParent = false,
    String? amountText,
    int? costCents,
    List<String>? days,
  }) {
    return ShoppingItem(
      id: id ?? this.id,
      name: name ?? this.name,
      quantity: quantity ?? this.quantity,
      aisle: aisle ?? this.aisle,
      checked: checked ?? this.checked,
      note: note ?? this.note,
      sourceRecipeId: sourceRecipeId ?? this.sourceRecipeId,
      parentId: clearParent ? null : (parentId ?? this.parentId),
      amountText: amountText ?? this.amountText,
      costCents: costCents ?? this.costCents,
      days: days ?? this.days,
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
        if (parentId != null) 'parentId': parentId,
        if (amountText != null) 'amountText': amountText,
        if (costCents != null) 'costCents': costCents,
        if (days.isNotEmpty) 'days': days,
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
      parentId: json['parentId'] as String?,
      amountText: json['amountText'] as String?,
      costCents: (json['costCents'] as num?)?.toInt(),
      days: (json['days'] as List? ?? const <Object>[])
          .whereType<String>()
          .toList(),
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
      other.sourceRecipeId == sourceRecipeId &&
      other.parentId == parentId &&
      other.amountText == amountText &&
      other.costCents == costCents &&
      _sameDays(other.days, days);

  static bool _sameDays(List<String> a, List<String> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
        id,
        name,
        quantity,
        aisle,
        checked,
        note,
        sourceRecipeId,
        parentId,
        amountText,
        costCents,
        Object.hashAll(days),
      );

  @override
  String toString() => 'ShoppingItem($id, $name, $quantity)';
}
