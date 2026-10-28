import 'package:flutter_test/flutter_test.dart';
import 'package:mylauncher/features/shopping/models/quantity.dart';
import 'package:mylauncher/features/shopping/models/unit.dart';
import 'package:mylauncher/features/shopping/parsing/document_parser.dart';

void main() {
  const parser = DocumentParser();

  test('reads column tabs from the PDF extractor as plain spaces', () {
    final tabbed = parser.parseDocument('2 kg\tflour\n1 l\tmilk\n');
    final spaced = parser.parseDocument('2 kg flour\n1 l milk\n');
    expect(tabbed.items, spaced.items);
    expect(tabbed.items.first.name, 'flour');
  });

  test('detects recipe, title, servings and the ingredients section', () {
    const text = 'Chocolate Chip Cookies\n'
        '\n'
        'Serves 24\n'
        '\n'
        'Ingredients\n'
        '2 1/4 cups all-purpose flour\n'
        '1 tsp baking soda\n'
        '1 cup butter, softened\n'
        '3/4 cup white sugar\n'
        '2 eggs\n'
        '1 tsp vanilla extract\n'
        '\n'
        'Method\n'
        'Preheat oven to 375 F.\n';

    final document = parser.parseDocument(text);
    expect(document.isRecipe, isTrue);
    expect(document.title, 'Chocolate Chip Cookies');
    expect(document.servings, 24);
    expect(document.items, hasLength(6));
    expect(document.items[0].quantity, const Quantity(2.25, Unit.cup));
    expect(document.items[0].name, 'all-purpose flour');
    expect(document.items[2].note, 'softened');
    expect(document.items[3].quantity, const Quantity(0.75, Unit.cup));
    expect(document.items[4].quantity, const Quantity(2, Unit.piece));
    expect(document.items[5].name, 'vanilla extract');
    expect(document.items.any((item) => item.name == 'Method'), isFalse);
  });

  test('ingredient section stops at an instructions heading', () {
    final document = parser.parseDocument(
      'Ingredients\n1 cup flour\nInstructions\nBake it.',
    );
    expect(document.items, hasLength(1));
    expect(document.items.single.name, 'flour');
  });

  test('treats plain text as a list and skips noise', () {
    final longLine = List<String>.filled(130, 'a').join();
    final text = 'Milk\n'
        '2 loaves bread\n'
        '6 eggs\n'
        'Bananas\n'
        'Page 2\n'
        '3 / 5\n'
        '$longLine';

    final document = parser.parseDocument(text);
    expect(document.isRecipe, isFalse);
    expect(document.title, isNull);
    expect(document.servings, isNull);
    expect(document.items, hasLength(4));
    expect(
      document.items.map((item) => item.name),
      ['Milk', 'loaves bread', 'eggs', 'Bananas'],
    );
  });

  test('recognizes the documented servings lines', () {
    const samples = <String, int>{
      'Serves 4': 4,
      'Servings: 6': 6,
      'Yield: 8 portions': 8,
      'Makes 12': 12,
      'For 4 people': 4,
      'Serves 4 to 6': 6,
    };
    for (final entry in samples.entries) {
      final document = parser.parseDocument(
        '${entry.key}\nIngredients\n1 cup flour',
      );
      expect(document.servings, entry.value, reason: entry.key);
      expect(document.isRecipe, isTrue, reason: entry.key);
    }
  });

  test('empty text yields an empty document', () {
    final document = parser.parseDocument('');
    expect(document.isRecipe, isFalse);
    expect(document.items, isEmpty);
  });
}
