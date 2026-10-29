import '../models/quantity.dart';
import '../models/unit.dart';

/// A single line interpreted as an ingredient or a list entry.
class ParsedIngredient {
  final Quantity? quantity;
  final String name;
  final String? note;
  final String aisle;

  const ParsedIngredient({
    this.quantity,
    required this.name,
    this.note,
    this.aisle = 'Other',
  });

  bool get hasQuantity => quantity != null;

  Map<String, dynamic> toJson() => {
        'name': name,
        if (quantity != null) 'quantity': quantity!.toJson(),
        if (note != null) 'note': note,
        'aisle': aisle,
      };

  factory ParsedIngredient.fromJson(Map<String, dynamic> json) {
    final rawQuantity = json['quantity'];
    return ParsedIngredient(
      quantity: rawQuantity is Map
          ? Quantity.fromJson(Map<String, dynamic>.from(rawQuantity))
          : null,
      name: json['name'] as String,
      note: json['note'] as String?,
      aisle: json['aisle'] as String? ?? 'Other',
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ParsedIngredient &&
      other.quantity == quantity &&
      other.name == name &&
      other.note == note &&
      other.aisle == aisle;

  @override
  int get hashCode => Object.hash(quantity, name, note, aisle);

  @override
  String toString() => 'ParsedIngredient($quantity, "$name", note: $note, $aisle)';
}

/// Turns a free-text ingredient or list line into a [ParsedIngredient].
///
/// Handles bullets and checkboxes, parenthetical and trailing-comma notes,
/// `x2`/`2x` multipliers, ranges (upper value wins), mixed numbers, unicode
/// fractions, count words, and unit aliases. A line without a number becomes a
/// name-only entry.
class IngredientParser {
  const IngredientParser();

  ParsedIngredient parseLine(String rawLine) {
    final original = rawLine.trim();
    var text = _stripLeadingMarkers(original);
    final notes = <String>[];

    // "Juice of 1 lemon", "Zest and juice of 2 oranges": the fruit is bought.
    final part = RegExp(
      r'^((?:zest|juice)(?:\s+(?:and|&)\s+(?:zest|juice))?)\s+of\s+',
      caseSensitive: false,
    ).firstMatch(text);
    if (part != null) {
      notes.add(part.group(1)!.toLowerCase());
      text = text.substring(part.end);
    }

    // Parenthetical and bracketed asides become notes.
    text = text.replaceAllMapped(RegExp(r'[\(\[]([^\)\]]*)[\)\]]'), (match) {
      final content = match.group(1)!.trim();
      if (content.isNotEmpty) notes.add(content);
      return ' ';
    });

    // An explicit multiplier can appear as "x2", "2x", or "x 2".
    var multiplier = 1.0;
    final multiplierMatch = RegExp(
      r'(?:^|\s)(?:(?:[xX]\s*(\d+(?:[.,]\d+)?))|(?:(\d+(?:[.,]\d+)?)\s*[xX]))(?=\s|$)',
    ).firstMatch(text);
    if (multiplierMatch != null) {
      multiplier = _toDouble(multiplierMatch.group(1) ?? multiplierMatch.group(2)!);
      text =
          text.replaceRange(multiplierMatch.start, multiplierMatch.end, ' ').trim();
    }

    // Removed asides leave gaps before commas ("juiced  , 1 zested").
    text = text.replaceAll(RegExp(r'\s+,'), ',');

    // A trailing comma introduces a note. A comma followed by a digit is a
    // decimal separator ("1,5 kg") and must survive.
    final commaMatch = RegExp(r',(?=\s|$)').firstMatch(text);
    if (commaMatch != null) {
      final note = text.substring(commaMatch.end).trim();
      if (note.isNotEmpty) notes.add(note);
      text = text.substring(0, commaMatch.start).trim();
    }

    text = text.replaceAll(RegExp(r'\s+'), ' ').trim();

    final number = _matchNumber(text);
    double? amount;
    var rest = text;
    if (number != null) {
      amount = number.$1 * multiplier;
      rest = number.$2;
    } else if (multiplier != 1.0) {
      amount = multiplier;
    }

    Unit? unit;
    if (number != null) {
      final unitResult = _matchUnit(rest);
      unit = unitResult.$1;
      rest = unitResult.$2;

      // A pack size followed by its packaging ("2 x 400g cans tomatoes",
      // "500 g bag rice") counts the packs and keeps the size as a note.
      if (unit != null && unit.dimension != Dimension.count) {
        final packResult = _matchUnit(rest);
        final Unit? pack = packResult.$1;
        if (pack != null &&
            pack.dimension == Dimension.count &&
            !pack.convertible &&
            packResult.$2.trim().isNotEmpty) {
          notes.insert(0, Quantity(number.$1, unit).formatAsEntered());
          amount = multiplier;
          unit = pack;
          rest = packResult.$2;
        }
      }
    }

    // A bare number or amount ("2", "2 kg") names nothing, so it yields an
    // empty name that callers reject instead of an item called "2".
    final name = rest.trim();
    final quantity = amount == null ? null : Quantity(amount, unit ?? Unit.piece);
    final note = notes.isEmpty ? null : notes.join('; ');

    return ParsedIngredient(
      quantity: quantity,
      name: name,
      note: note,
      aisle: guessAisle(name.isEmpty ? original : name),
    );
  }

  /// Parses [text] as a whole amount: an integer or decimal (dot or comma), a
  /// fraction (`1/2`), a mixed number (`1 1/2`, `1-1/2`), a unicode fraction
  /// (`½`, `1½`), a range (upper bound wins) or a count word. Returns null
  /// when anything but the amount is left over, or when nothing matched.
  static double? parseAmount(String text) {
    final match = _matchNumber(text.trim());
    if (match == null || match.$2.trim().isNotEmpty) return null;
    return match.$1;
  }

  static const Map<String, double> _countWords = {
    'a': 1,
    'an': 1,
    'one': 1,
    'two': 2,
    'three': 3,
    'four': 4,
    'five': 5,
    'six': 6,
    'seven': 7,
    'eight': 8,
    'nine': 9,
    'ten': 10,
    'eleven': 11,
    'twelve': 12,
  };

  static const Map<String, double> _unicodeFractions = {
    '½': 0.5,
    '¼': 0.25,
    '¾': 0.75,
    '⅓': 1 / 3,
    '⅔': 2 / 3,
    '⅛': 0.125,
    '⅜': 0.375,
    '⅝': 0.625,
    '⅞': 0.875,
    '⅕': 0.2,
    '⅖': 0.4,
    '⅗': 0.6,
    '⅘': 0.8,
    '⅙': 1 / 6,
    '⅚': 5 / 6,
    '⅐': 1 / 7,
    '⅑': 1 / 9,
    '⅒': 0.1,
  };

  String _stripLeadingMarkers(String text) {
    var result = text.replaceFirst(
      RegExp(r'^\s*(?:[-*•·▪‣–—]+|\[[ xX]\]|☐|☑|✅|✔|✓|✗|✘)\s*'),
      '',
    );
    result = result.replaceFirst(RegExp(r'^\d+[.)]\s+'), '');
    return result.trim();
  }

  /// Returns `(amount, rest)` for a leading number, or null when there is none.
  ///
  /// A range takes its upper bound (`2-3`, `¾-1`, `1½ to 2`), and a hyphen
  /// joining the amount to its unit (`1-ounce walnuts`) is dropped.
  static (double, String)? _matchNumber(String text) {
    final first = _matchSingleNumber(text.trimLeft());
    if (first == null) return null;
    final dash = RegExp(
      r'^\s*(?:-|–|—|to\b)\s*',
      caseSensitive: false,
    ).firstMatch(first.$2);
    if (dash != null) {
      final second = _matchSingleNumber(first.$2.substring(dash.end));
      if (second != null) {
        return (first.$1 > second.$1 ? first.$1 : second.$1, second.$2);
      }
    }
    final unit = RegExp(r'^-([A-Za-z]+)').firstMatch(first.$2);
    if (unit != null && Unit.tryParse(unit.group(1)!) != null) {
      return (first.$1, first.$2.substring(1));
    }
    return first;
  }

  /// One number at the start of [value]: see [_matchNumber].
  static (double, String)? _matchSingleNumber(String value) {
    // Mixed number, e.g. "1 1/2" or "1-1/2".
    final mixed = RegExp(
      r'^(\d+)(?:\s+|\s*-\s*)(\d+)\s*/\s*(\d+)',
    ).firstMatch(value);
    if (mixed != null) {
      final whole = int.parse(mixed.group(1)!);
      final numerator = int.parse(mixed.group(2)!);
      final denominator = int.parse(mixed.group(3)!);
      return (
        whole + numerator / denominator,
        value.substring(mixed.end).trimLeft(),
      );
    }

    // Integer with an attached unicode fraction, e.g. "1½".
    final unicode = RegExp(
      r'^(\d+)?\s*([½¼¾⅓⅔⅛⅜⅝⅞⅕⅖⅗⅘⅙⅚⅐⅑⅒])',
    ).firstMatch(value);
    if (unicode != null) {
      final whole = unicode.group(1) == null ? 0.0 : double.parse(unicode.group(1)!);
      final fraction = _unicodeFractions[unicode.group(2)!]!;
      return (whole + fraction, value.substring(unicode.end).trimLeft());
    }

    // Plain fraction, e.g. "1/2".
    final fraction = RegExp(r'^(\d+)\s*/\s*(\d+)').firstMatch(value);
    if (fraction != null) {
      final numerator = int.parse(fraction.group(1)!);
      final denominator = int.parse(fraction.group(2)!);
      return (numerator / denominator, value.substring(fraction.end).trimLeft());
    }

    // Decimal or integer, with either dot or comma. Letters glued to the
    // number must be a unit ("400g"); otherwise the digits belong to the name
    // ("7up").
    final decimal = RegExp(r'^(\d+(?:[.,]\d+)?)').firstMatch(value);
    if (decimal != null) {
      final String after = value.substring(decimal.end);
      final Match? glued = RegExp(r'^[A-Za-z]+').firstMatch(after);
      if (glued != null && Unit.tryParse(glued.group(0)!) == null) {
        return null;
      }
      return (_toDouble(decimal.group(1)!), after.trimLeft());
    }

    // Count words.
    final word = RegExp(
      r'^(a|an|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve)\b',
      caseSensitive: false,
    ).firstMatch(value);
    if (word != null) {
      return (
        _countWords[word.group(1)!.toLowerCase()]!,
        value.substring(word.end).trimLeft(),
      );
    }

    return null;
  }

  (Unit?, String) _matchUnit(String text) {
    final words = text.trim().split(RegExp(r'\s+'));
    if (words.isEmpty || words.first.isEmpty) return (null, text);
    if (words.length >= 2) {
      final two = Unit.tryParse('${words[0]} ${words[1]}');
      if (two != null) return (two, words.sublist(2).join(' '));
    }
    final one = Unit.tryParse(words.first);
    if (one != null) return (one, words.sublist(1).join(' '));
    return (null, words.join(' '));
  }

  static double _toDouble(String value) => double.parse(value.replaceAll(',', '.'));

  /// A best-effort store aisle for [name].
  static String guessAisle(String name) {
    final lower = name.toLowerCase();
    for (final rule in _aisleRules) {
      final keyword = RegExp.escape(rule.key);
      if (RegExp('\\b$keyword(?:s|es)?\\b').hasMatch(lower)) {
        return rule.value;
      }
    }
    return 'Other';
  }

  /// Keyword-to-aisle map. Longer keywords are checked first so `tomato paste`
  /// wins over `tomato` and `ice cream` wins over `cream`.
  static final List<MapEntry<String, String>> _aisleRules =
      _buildAisleRules();

  static List<MapEntry<String, String>> _buildAisleRules() {
    const rules = <String, String>{
      // Frozen
      'frozen': 'Frozen',
      'ice cream': 'Frozen',
      'icecream': 'Frozen',
      'fish fingers': 'Frozen',
      'frozen peas': 'Frozen',
      'frozen berries': 'Frozen',
      'frozen vegetables': 'Frozen',
      'pizza': 'Frozen',
      'fries': 'Frozen',
      // Bakery
      'bread': 'Bakery',
      'baguette': 'Bakery',
      'tortilla': 'Bakery',
      'croissant': 'Bakery',
      'bagel': 'Bakery',
      'pita': 'Bakery',
      'muffin': 'Bakery',
      'pastry': 'Bakery',
      'brioche': 'Bakery',
      'naan': 'Bakery',
      'dough': 'Bakery',
      'bun': 'Bakery',
      'roll': 'Bakery',
      'cake': 'Bakery',
      // Meat & Fish
      'ground beef': 'Meat & Fish',
      'ground turkey': 'Meat & Fish',
      'chicken': 'Meat & Fish',
      'meatball': 'Meat & Fish',
      'sausage': 'Meat & Fish',
      'salmon': 'Meat & Fish',
      'shrimp': 'Meat & Fish',
      'prawn': 'Meat & Fish',
      'bacon': 'Meat & Fish',
      'turkey': 'Meat & Fish',
      'seafood': 'Meat & Fish',
      'tuna': 'Meat & Fish',
      'beef': 'Meat & Fish',
      'pork': 'Meat & Fish',
      'lamb': 'Meat & Fish',
      'steak': 'Meat & Fish',
      'mince': 'Meat & Fish',
      'fish': 'Meat & Fish',
      'cod': 'Meat & Fish',
      'ham': 'Meat & Fish',
      // Dairy & Eggs
      'cream cheese': 'Dairy & Eggs',
      'cottage cheese': 'Dairy & Eggs',
      'sour cream': 'Dairy & Eggs',
      'mozzarella': 'Dairy & Eggs',
      'parmesan': 'Dairy & Eggs',
      'cheddar': 'Dairy & Eggs',
      'buttermilk': 'Dairy & Eggs',
      'margarine': 'Dairy & Eggs',
      'yogurt': 'Dairy & Eggs',
      'yoghurt': 'Dairy & Eggs',
      'butter': 'Dairy & Eggs',
      'cheese': 'Dairy & Eggs',
      'cream': 'Dairy & Eggs',
      'ghee': 'Dairy & Eggs',
      'milk': 'Dairy & Eggs',
      'egg': 'Dairy & Eggs',
      // Drinks
      'sparkling water': 'Drinks',
      'orange juice': 'Drinks',
      'apple juice': 'Drinks',
      'lemonade': 'Drinks',
      'smoothie': 'Drinks',
      'kombucha': 'Drinks',
      'juice': 'Drinks',
      'coffee': 'Drinks',
      'water': 'Drinks',
      'soda': 'Drinks',
      'beer': 'Drinks',
      'wine': 'Drinks',
      'cider': 'Drinks',
      'cola': 'Drinks',
      'tea': 'Drinks',
      // Household
      'paper towel': 'Household',
      'toilet paper': 'Household',
      'toilet roll': 'Household',
      'trash bag': 'Household',
      'cling film': 'Household',
      'plastic wrap': 'Household',
      'dish soap': 'Household',
      'detergent': 'Household',
      'laundry': 'Household',
      'shampoo': 'Household',
      'cleaner': 'Household',
      'sponge': 'Household',
      'napkin': 'Household',
      'tissue': 'Household',
      'foil': 'Household',
      'soap': 'Household',
      // Produce
      'blueberry': 'Produce',
      'strawberry': 'Produce',
      'raspberry': 'Produce',
      'bell pepper': 'Produce',
      'cucumber': 'Produce',
      'avocado': 'Produce',
      'mushroom': 'Produce',
      'broccoli': 'Produce',
      'zucchini': 'Produce',
      'cabbage': 'Produce',
      'spinach': 'Produce',
      'lettuce': 'Produce',
      'banana': 'Produce',
      'orange': 'Produce',
      'potato': 'Produce',
      'carrot': 'Produce',
      'tomato': 'Produce',
      'onion': 'Produce',
      'garlic': 'Produce',
      'ginger': 'Produce',
      'celery': 'Produce',
      'parsley': 'Produce',
      'cilantro': 'Produce',
      'coriander': 'Produce',
      'lemon': 'Produce',
      'apple': 'Produce',
      'grape': 'Produce',
      'mango': 'Produce',
      'peach': 'Produce',
      'pear': 'Produce',
      'kale': 'Produce',
      'basil': 'Produce',
      'herb': 'Produce',
      'fruit': 'Produce',
      'vegetable': 'Produce',
      'berries': 'Produce',
      'berry': 'Produce',
      'salad': 'Produce',
      'corn': 'Produce',
      'lime': 'Produce',
      'peas': 'Produce',
      'pepper': 'Produce',
      // Pantry
      'canned tomatoes': 'Pantry',
      'peanut butter': 'Pantry',
      'coconut milk': 'Pantry',
      'baking powder': 'Pantry',
      'baking soda': 'Pantry',
      'olive oil': 'Pantry',
      'soy sauce': 'Pantry',
      'tomato paste': 'Pantry',
      'black pepper': 'Pantry',
      'mayonnaise': 'Pantry',
      'cinnamon': 'Pantry',
      'chocolate': 'Pantry',
      'vinegar': 'Pantry',
      'mustard': 'Pantry',
      'ketchup': 'Pantry',
      'vanilla': 'Pantry',
      'paprika': 'Pantry',
      'lentil': 'Pantry',
      'noodle': 'Pantry',
      'cereal': 'Pantry',
      'flour': 'Pantry',
      'sugar': 'Pantry',
      'rice': 'Pantry',
      'pasta': 'Pantry',
      'bean': 'Pantry',
      'spice': 'Pantry',
      'curry': 'Pantry',
      'cumin': 'Pantry',
      'honey': 'Pantry',
      'syrup': 'Pantry',
      'stock': 'Pantry',
      'broth': 'Pantry',
      'oats': 'Pantry',
      'yeast': 'Pantry',
      'cocoa': 'Pantry',
      'peanut': 'Pantry',
      'tahini': 'Pantry',
      'jam': 'Pantry',
      'oil': 'Pantry',
      'sauce': 'Pantry',
      'salt': 'Pantry',
      'nut': 'Pantry',
      'seed': 'Pantry',
    };
    final entries = rules.entries.toList();
    entries.sort((a, b) => b.key.length.compareTo(a.key.length));
    return entries;
  }
}
