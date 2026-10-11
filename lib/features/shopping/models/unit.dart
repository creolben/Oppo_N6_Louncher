/// Measurement dimensions understood by the shopping list.
enum Dimension { count, mass, volume }

/// A measurement unit.
///
/// Count units are packaging or discrete items. Packaging units (`box`, `can`,
/// ...) are deliberately **not** convertible to anything else, because a box of
/// one product has no fixed size. Only the discrete pair `piece`/`dozen`
/// converts, and only within [Dimension.count].
///
/// Mass units convert through grams ([toBase]) and volume units through
/// millilitres. Recipe spoons and cups use US customary volumes.
class Unit {
  /// Canonical short symbol, e.g. `g`, `kg`, `ml`, `L`, `fl oz`.
  final String symbol;

  /// Human readable singular name, e.g. `gram`.
  final String singular;

  /// Human readable plural name, e.g. `grams`.
  final String plural;

  final Dimension dimension;

  /// Multiplier to the dimension's base unit (g, ml, or piece).
  final double toBase;

  /// Whether this unit belongs to the metric system. Count units are marked
  /// metric, but the flag is only meaningful for [Dimension.mass] and
  /// [Dimension.volume].
  final bool isMetric;

  /// Whether this unit may convert to other units of the same dimension.
  ///
  /// Packaging count units are their own island; `piece`/`dozen` are the only
  /// convertible count units.
  final bool convertible;

  /// Lower-cased alternatives accepted by [tryParse].
  final List<String> aliases;

  const Unit({
    required this.symbol,
    required this.singular,
    required this.plural,
    required this.dimension,
    required this.toBase,
    required this.isMetric,
    this.convertible = true,
    this.aliases = const [],
  });

  bool get isImperial => !isMetric;

  /// Name for [amount]: singular for exactly one, plural otherwise.
  String displayName(double amount) => amount == 1 ? singular : plural;

  // ---------------------------------------------------------------------------
  // Count units
  // ---------------------------------------------------------------------------

  static const Unit piece = Unit(
    symbol: 'pc',
    singular: 'piece',
    plural: 'pieces',
    dimension: Dimension.count,
    toBase: 1,
    isMetric: true,
    aliases: ['pc', 'pcs', 'piece', 'pieces'],
  );

  static const Unit dozen = Unit(
    symbol: 'dozen',
    singular: 'dozen',
    plural: 'dozen',
    dimension: Dimension.count,
    toBase: 12,
    isMetric: true,
    aliases: ['doz', 'dozen', 'dozens', 'dz'],
  );

  static const Unit box = Unit(
    symbol: 'box',
    singular: 'box',
    plural: 'boxes',
    dimension: Dimension.count,
    toBase: 1,
    isMetric: true,
    convertible: false,
    aliases: ['box', 'boxes'],
  );

  static const Unit pack = Unit(
    symbol: 'pack',
    singular: 'pack',
    plural: 'packs',
    dimension: Dimension.count,
    toBase: 1,
    isMetric: true,
    convertible: false,
    aliases: ['pack', 'packs', 'packet', 'packets', 'pkg', 'pkgs', 'package', 'packages'],
  );

  static const Unit can = Unit(
    symbol: 'can',
    singular: 'can',
    plural: 'cans',
    dimension: Dimension.count,
    toBase: 1,
    isMetric: true,
    convertible: false,
    aliases: ['can', 'cans', 'tin', 'tins'],
  );

  static const Unit bottle = Unit(
    symbol: 'bottle',
    singular: 'bottle',
    plural: 'bottles',
    dimension: Dimension.count,
    toBase: 1,
    isMetric: true,
    convertible: false,
    aliases: ['bottle', 'bottles', 'btl', 'btls'],
  );

  static const Unit jar = Unit(
    symbol: 'jar',
    singular: 'jar',
    plural: 'jars',
    dimension: Dimension.count,
    toBase: 1,
    isMetric: true,
    convertible: false,
    aliases: ['jar', 'jars'],
  );

  static const Unit bag = Unit(
    symbol: 'bag',
    singular: 'bag',
    plural: 'bags',
    dimension: Dimension.count,
    toBase: 1,
    isMetric: true,
    convertible: false,
    aliases: ['bag', 'bags'],
  );

  // ---------------------------------------------------------------------------
  // Mass units
  // ---------------------------------------------------------------------------

  static const Unit gram = Unit(
    symbol: 'g',
    singular: 'gram',
    plural: 'grams',
    dimension: Dimension.mass,
    toBase: 1,
    isMetric: true,
    aliases: ['g', 'gr', 'grm', 'gram', 'grams', 'gramme', 'grammes'],
  );

  static const Unit kilogram = Unit(
    symbol: 'kg',
    singular: 'kilogram',
    plural: 'kilograms',
    dimension: Dimension.mass,
    toBase: 1000,
    isMetric: true,
    aliases: ['kg', 'kgs', 'kilo', 'kilos', 'kilogram', 'kilograms', 'kilogramme', 'kilogrammes'],
  );

  static const Unit ounce = Unit(
    symbol: 'oz',
    singular: 'ounce',
    plural: 'ounces',
    dimension: Dimension.mass,
    toBase: 28.349523125,
    isMetric: false,
    aliases: ['oz', 'ounce', 'ounces'],
  );

  static const Unit pound = Unit(
    symbol: 'lb',
    singular: 'pound',
    plural: 'pounds',
    dimension: Dimension.mass,
    toBase: 453.59237,
    isMetric: false,
    aliases: ['lb', 'lbs', 'pound', 'pounds'],
  );

  // ---------------------------------------------------------------------------
  // Volume units
  // ---------------------------------------------------------------------------

  static const Unit milliliter = Unit(
    symbol: 'ml',
    singular: 'millilitre',
    plural: 'millilitres',
    dimension: Dimension.volume,
    toBase: 1,
    isMetric: true,
    aliases: ['ml', 'mls', 'millilitre', 'millilitres', 'milliliter', 'milliliters', 'cc'],
  );

  static const Unit liter = Unit(
    symbol: 'L',
    singular: 'litre',
    plural: 'litres',
    dimension: Dimension.volume,
    toBase: 1000,
    isMetric: true,
    aliases: ['l', 'liter', 'liters', 'litre', 'litres'],
  );

  static const Unit teaspoon = Unit(
    symbol: 'tsp',
    singular: 'teaspoon',
    plural: 'teaspoons',
    dimension: Dimension.volume,
    toBase: 4.92892,
    isMetric: false,
    aliases: ['tsp', 'tsps', 'teaspoon', 'teaspoons', 't'],
  );

  static const Unit tablespoon = Unit(
    symbol: 'tbsp',
    singular: 'tablespoon',
    plural: 'tablespoons',
    dimension: Dimension.volume,
    toBase: 14.7868,
    isMetric: false,
    aliases: ['tbsp', 'tbsps', 'tbs', 'tablespoon', 'tablespoons'],
  );

  static const Unit cup = Unit(
    symbol: 'cup',
    singular: 'cup',
    plural: 'cups',
    dimension: Dimension.volume,
    toBase: 236.588,
    isMetric: false,
    aliases: ['cup', 'cups', 'c'],
  );

  static const Unit fluidOunce = Unit(
    symbol: 'fl oz',
    singular: 'fluid ounce',
    plural: 'fluid ounces',
    dimension: Dimension.volume,
    toBase: 29.5735,
    isMetric: false,
    aliases: ['fl oz', 'floz', 'fluid ounce', 'fluid ounces'],
  );

  static const Unit pint = Unit(
    symbol: 'pt',
    singular: 'pint',
    plural: 'pints',
    dimension: Dimension.volume,
    toBase: 473.176,
    isMetric: false,
    aliases: ['pt', 'pts', 'pint', 'pints'],
  );

  static const Unit quart = Unit(
    symbol: 'qt',
    singular: 'quart',
    plural: 'quarts',
    dimension: Dimension.volume,
    toBase: 946.353,
    isMetric: false,
    aliases: ['qt', 'qts', 'quart', 'quarts'],
  );

  static const Unit gallon = Unit(
    symbol: 'gal',
    singular: 'gallon',
    plural: 'gallons',
    dimension: Dimension.volume,
    toBase: 3785.41,
    isMetric: false,
    aliases: ['gal', 'gals', 'gallon', 'gallons'],
  );

  /// Every known unit.
  static const List<Unit> values = [
    piece,
    dozen,
    box,
    pack,
    can,
    bottle,
    jar,
    bag,
    gram,
    kilogram,
    ounce,
    pound,
    milliliter,
    liter,
    teaspoon,
    tablespoon,
    cup,
    fluidOunce,
    pint,
    quart,
    gallon,
  ];

  /// The base unit of [dimension].
  static Unit baseFor(Dimension dimension) {
    switch (dimension) {
      case Dimension.count:
        return piece;
      case Dimension.mass:
        return gram;
      case Dimension.volume:
        return milliliter;
    }
  }

  static String _normalize(String value) => value
      .toLowerCase()
      .replaceAll('.', '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  static final Map<String, Unit> _aliasIndex = _buildAliasIndex();

  static Map<String, Unit> _buildAliasIndex() {
    final index = <String, Unit>{};
    for (final unit in values) {
      void put(String alias) {
        final key = _normalize(alias);
        // `t` is reserved for teaspoon so the case-sensitive `T` (tablespoon)
        // can win before normalization; never index away the reserved key.
        if (key == 't') return;
        index.putIfAbsent(key, () => unit);
      }

      put(unit.symbol);
      put(unit.singular);
      put(unit.plural);
      for (final alias in unit.aliases) {
        put(alias);
      }
    }
    return Map.unmodifiable(index);
  }

  /// Parses [input] into a unit, or returns null when it is not a unit.
  ///
  /// Matching is case-insensitive with one deliberate exception: `T` is a
  /// tablespoon and `t` is a teaspoon.
  static Unit? tryParse(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return null;
    final letters = trimmed.replaceAll('.', '').trim();
    if (letters == 'T') return tablespoon;
    if (letters == 't') return teaspoon;
    final key = _normalize(trimmed);
    if (key == 't') return teaspoon;
    return _aliasIndex[key];
  }

  @override
  bool operator ==(Object other) =>
      other is Unit && other.dimension == dimension && other.symbol == symbol;

  @override
  int get hashCode => Object.hash(dimension, symbol);

  @override
  String toString() => symbol;
}
