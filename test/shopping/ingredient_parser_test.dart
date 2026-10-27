import 'package:flutter_test/flutter_test.dart';
import 'package:mylauncher/features/shopping/models/quantity.dart';
import 'package:mylauncher/features/shopping/models/unit.dart';
import 'package:mylauncher/features/shopping/parsing/ingredient_parser.dart';

void main() {
  const parser = IngredientParser();

  group('IngredientParser.parseLine', () {
    test('parses 40 real-world lines', () {
      final cases = <(String, double?, Unit?, String, String?)>[
        ('2 cups flour', 2, Unit.cup, 'flour', null),
        ('1 1/2 cups sugar', 1.5, Unit.cup, 'sugar', null),
        ('1½ cups milk', 1.5, Unit.cup, 'milk', null),
        ('½ tsp salt', 0.5, Unit.teaspoon, 'salt', null),
        ('1/4 cup olive oil', 0.25, Unit.cup, 'olive oil', null),
        ('2-3 tbsp butter', 3, Unit.tablespoon, 'butter', null),
        ('2 to 3 cups rice', 3, Unit.cup, 'rice', null),
        ('3 boxes pasta', 3, Unit.box, 'pasta', null),
        ('1 can (400 g) tomatoes', 1, Unit.can, 'tomatoes', '400 g'),
        ('2 onions, diced', 2, Unit.piece, 'onions', 'diced'),
        ('500 g chicken breast', 500, Unit.gram, 'chicken breast', null),
        ('1.5 kg potatoes', 1.5, Unit.kilogram, 'potatoes', null),
        ('1,5 l milk', 1.5, Unit.liter, 'milk', null),
        ('- 6 eggs', 6, Unit.piece, 'eggs', null),
        ('• 2 apples', 2, Unit.piece, 'apples', null),
        ('[ ] 3 bananas', 3, Unit.piece, 'bananas', null),
        ('☐ 4 oranges', 4, Unit.piece, 'oranges', null),
        ('x2 tomatoes', 2, Unit.piece, 'tomatoes', null),
        ('2x lemons', 2, Unit.piece, 'lemons', null),
        ('400 g tomatoes x2', 800, Unit.gram, 'tomatoes', null),
        ('a dozen eggs', 1, Unit.dozen, 'eggs', null),
        ('two onions', 2, Unit.piece, 'onions', null),
        ('twelve eggs', 12, Unit.piece, 'eggs', null),
        ('1 fl oz vanilla', 1, Unit.fluidOunce, 'vanilla', null),
        ('2 quarts stock', 2, Unit.quart, 'stock', null),
        ('1 gallon water', 1, Unit.gallon, 'water', null),
        ('1 pint cream', 1, Unit.pint, 'cream', null),
        ('8 oz cheese', 8, Unit.ounce, 'cheese', null),
        ('1 lb ground beef', 1, Unit.pound, 'ground beef', null),
        ('Salt', null, null, 'Salt', null),
        ('fresh basil', null, null, 'fresh basil', null),
        ('2 pkg ramen', 2, Unit.pack, 'ramen', null),
        ('1 bottle olive oil', 1, Unit.bottle, 'olive oil', null),
        ('1 L orange juice', 1, Unit.liter, 'orange juice', null),
        ('1T olive oil', 1, Unit.tablespoon, 'olive oil', null),
        ('1 t vanilla', 1, Unit.teaspoon, 'vanilla', null),
        ('200 ml cream', 200, Unit.milliliter, 'cream', null),
        ('1/2 cup (120 ml) milk', 0.5, Unit.cup, 'milk', '120 ml'),
        ('3 tins tuna', 3, Unit.can, 'tuna', null),
        ('12 pieces sushi', 12, Unit.piece, 'sushi', null),
      ];

      for (final entry in cases) {
        final parsed = parser.parseLine(entry.$1);
        final reason = 'line: ${entry.$1}';
        if (entry.$2 == null) {
          expect(parsed.quantity, isNull, reason: reason);
        } else {
          expect(parsed.quantity, isNotNull, reason: reason);
          expect(parsed.quantity!.amount, closeTo(entry.$2!, 1e-9), reason: reason);
          expect(parsed.quantity!.unit, entry.$3, reason: reason);
        }
        expect(parsed.name, entry.$4, reason: reason);
        expect(parsed.note, entry.$5, reason: reason);
      }
    });

    test('empty lines do not throw', () {
      final parsed = parser.parseLine('   ');
      expect(parsed.name, '');
      expect(parsed.quantity, isNull);
    });

    test('mixed units in one parenthesis line keep the can as quantity', () {
      final parsed = parser.parseLine('1 can (400 g) tomatoes');
      expect(parsed.quantity, const Quantity(1, Unit.can));
      expect(parsed.note, '400 g');
    });
  });

  group('IngredientParser edge cases', () {
    test('a pack count with a pack size counts the packs', () {
      final parsed = parser.parseLine('2 x 400g cans tomatoes');
      expect(parsed.name, 'tomatoes');
      expect(parsed.quantity, const Quantity(2, Unit.can));
      expect(parsed.note, '400 g');
    });

    test('digits glued to a non-unit word stay in the name', () {
      final parsed = parser.parseLine('7up');
      expect(parsed.name, '7up');
      expect(parsed.quantity, isNull);
      expect(parser.parseLine('2 7up').name, '7up');
      // A glued unit still parses.
      expect(parser.parseLine('400g rice').quantity, const Quantity(400, Unit.gram));
    });

    test('a bare number names nothing', () {
      expect(parser.parseLine('2').name, isEmpty);
      expect(parser.parseLine('2 kg').name, isEmpty);
    });

    test('cloves are a count unit', () {
      final parsed = parser.parseLine('2 cloves garlic');
      expect(parsed.name, 'garlic');
      expect(parsed.quantity, const Quantity(2, Unit.clove));
      expect(parsed.aisle, 'Produce');
    });

    test('parseAmount accepts whole recipe amounts only', () {
      expect(IngredientParser.parseAmount('1 1/2'), 1.5);
      expect(IngredientParser.parseAmount('½'), 0.5);
      expect(IngredientParser.parseAmount('1½'), 1.5);
      expect(IngredientParser.parseAmount('3/4'), 0.75);
      expect(IngredientParser.parseAmount('2,5'), 2.5);
      expect(IngredientParser.parseAmount('2 cups'), isNull);
      expect(IngredientParser.parseAmount('abc'), isNull);
    });
  });

  group('IngredientParser.guessAisle', () {
    test('maps keywords to store aisles', () {
      expect(IngredientParser.guessAisle('milk'), 'Dairy & Eggs');
      expect(IngredientParser.guessAisle('chicken breast'), 'Meat & Fish');
      expect(IngredientParser.guessAisle('potatoes'), 'Produce');
      expect(IngredientParser.guessAisle('bread'), 'Bakery');
      expect(IngredientParser.guessAisle('orange juice'), 'Drinks');
      expect(IngredientParser.guessAisle('olive oil'), 'Pantry');
      expect(IngredientParser.guessAisle('frozen peas'), 'Frozen');
      expect(IngredientParser.guessAisle('dish soap'), 'Household');
      expect(IngredientParser.guessAisle('tomato paste'), 'Pantry');
      expect(IngredientParser.guessAisle('mystery powder'), 'Other');
    });

    test('parseLine carries the guessed aisle', () {
      expect(parser.parseLine('500 g chicken').aisle, 'Meat & Fish');
      expect(parser.parseLine('2 cups flour').aisle, 'Pantry');
    });

    test('a leading or trailing "frozen" word is the Frozen aisle', () {
      expect(parser.parseLine('frozen peas').aisle, 'Frozen');
      expect(parser.parseLine('2 cups peas frozen').aisle, 'Frozen');
      expect(parser.parseLine('Frozen pizza').aisle, 'Frozen');
    });
  });
}
