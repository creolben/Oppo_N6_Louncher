import 'quantity.dart';

/// One ingredient of a [Recipe].
class Ingredient {
  final String name;
  final Quantity? quantity;
  final String? note;

  const Ingredient({required this.name, this.quantity, this.note});

  Ingredient copyWith({String? name, Quantity? quantity, String? note}) {
    return Ingredient(
      name: name ?? this.name,
      quantity: quantity ?? this.quantity,
      note: note ?? this.note,
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        if (quantity != null) 'quantity': quantity!.toJson(),
        if (note != null) 'note': note,
      };

  factory Ingredient.fromJson(Map<String, dynamic> json) {
    final rawQuantity = json['quantity'];
    return Ingredient(
      name: json['name'] as String,
      quantity: rawQuantity is Map
          ? Quantity.fromJson(Map<String, dynamic>.from(rawQuantity))
          : null,
      note: json['note'] as String?,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Ingredient &&
      other.name == name &&
      other.quantity == quantity &&
      other.note == note;

  @override
  int get hashCode => Object.hash(name, quantity, note);

  @override
  String toString() => 'Ingredient($name, $quantity)';
}

/// A recipe with a base serving count and a user-facing target.
class Recipe {
  final String id;
  final String title;
  final int baseServings;
  final int targetServings;
  final List<Ingredient> ingredients;

  const Recipe({
    required this.id,
    required this.title,
    required this.baseServings,
    required this.targetServings,
    this.ingredients = const [],
  });

  /// Multiplier applied to ingredient amounts.
  double get scaleFactor =>
      baseServings <= 0 ? 1 : targetServings / baseServings;

  /// Ingredients with their amounts scaled by [scaleFactor]; name-only lines
  /// pass through untouched.
  List<Ingredient> get scaledIngredients => ingredients
      .map(
        (ingredient) => ingredient.quantity == null
            ? ingredient
            : ingredient.copyWith(
                quantity: ingredient.quantity!.scale(scaleFactor),
              ),
      )
      .toList();

  Recipe copyWith({
    String? id,
    String? title,
    int? baseServings,
    int? targetServings,
    List<Ingredient>? ingredients,
  }) {
    return Recipe(
      id: id ?? this.id,
      title: title ?? this.title,
      baseServings: baseServings ?? this.baseServings,
      targetServings: targetServings ?? this.targetServings,
      ingredients: ingredients ?? this.ingredients,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'baseServings': baseServings,
        'targetServings': targetServings,
        'ingredients': ingredients.map((ingredient) => ingredient.toJson()).toList(),
      };

  factory Recipe.fromJson(Map<String, dynamic> json) {
    return Recipe(
      id: json['id'] as String,
      title: json['title'] as String,
      baseServings: json['baseServings'] as int? ?? 1,
      targetServings: json['targetServings'] as int? ?? 1,
      ingredients: (json['ingredients'] as List? ?? const [])
          .map((ingredient) => Ingredient.fromJson(
                Map<String, dynamic>.from(ingredient as Map),
              ))
          .toList(),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Recipe &&
      other.id == id &&
      other.title == title &&
      other.baseServings == baseServings &&
      other.targetServings == targetServings &&
      _listEquals(other.ingredients, ingredients);

  @override
  int get hashCode => Object.hash(
        id,
        title,
        baseServings,
        targetServings,
        Object.hashAll(ingredients),
      );

  static bool _listEquals(List<Ingredient> a, List<Ingredient> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  String toString() => 'Recipe($id, $title, $baseServings->$targetServings)';
}
