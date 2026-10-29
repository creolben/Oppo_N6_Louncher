import 'package:flutter_test/flutter_test.dart';
import 'package:mylauncher/features/shopping/models/unit.dart';

void main() {
  group('Unit.tryParse', () {
    test('parses count units and aliases', () {
      expect(Unit.tryParse('piece'), Unit.piece);
      expect(Unit.tryParse('pcs'), Unit.piece);
      expect(Unit.tryParse('box'), Unit.box);
      expect(Unit.tryParse('Boxes'), Unit.box);
      expect(Unit.tryParse('can'), Unit.can);
      expect(Unit.tryParse('tins'), Unit.can);
      expect(Unit.tryParse('packet'), Unit.pack);
      expect(Unit.tryParse('pkg'), Unit.pack);
      expect(Unit.tryParse('bottle'), Unit.bottle);
      expect(Unit.tryParse('jar'), Unit.jar);
      expect(Unit.tryParse('bag'), Unit.bag);
      expect(Unit.tryParse('dozen'), Unit.dozen);
      expect(Unit.tryParse('dz'), Unit.dozen);
    });

    test('parses mass units and aliases', () {
      expect(Unit.tryParse('g'), Unit.gram);
      expect(Unit.tryParse('grams'), Unit.gram);
      expect(Unit.tryParse('gr'), Unit.gram);
      expect(Unit.tryParse('kg'), Unit.kilogram);
      expect(Unit.tryParse('Kilos'), Unit.kilogram);
      expect(Unit.tryParse('oz'), Unit.ounce);
      expect(Unit.tryParse('Ounces'), Unit.ounce);
      expect(Unit.tryParse('lb'), Unit.pound);
      expect(Unit.tryParse('lbs'), Unit.pound);
      expect(Unit.tryParse('Pounds'), Unit.pound);
    });

    test('parses volume units and aliases', () {
      expect(Unit.tryParse('ml'), Unit.milliliter);
      expect(Unit.tryParse('millilitre'), Unit.milliliter);
      expect(Unit.tryParse('milliliter'), Unit.milliliter);
      expect(Unit.tryParse('l'), Unit.liter);
      expect(Unit.tryParse('L'), Unit.liter);
      expect(Unit.tryParse('litre'), Unit.liter);
      expect(Unit.tryParse('liters'), Unit.liter);
      expect(Unit.tryParse('tsp'), Unit.teaspoon);
      expect(Unit.tryParse('teaspoon'), Unit.teaspoon);
      expect(Unit.tryParse('tbsp'), Unit.tablespoon);
      expect(Unit.tryParse('tablespoon'), Unit.tablespoon);
      expect(Unit.tryParse('cup'), Unit.cup);
      expect(Unit.tryParse('cups'), Unit.cup);
      expect(Unit.tryParse('fl oz'), Unit.fluidOunce);
      expect(Unit.tryParse('fl. oz.'), Unit.fluidOunce);
      expect(Unit.tryParse('pint'), Unit.pint);
      expect(Unit.tryParse('quart'), Unit.quart);
      expect(Unit.tryParse('gallon'), Unit.gallon);
    });

    test('T is tablespoon and t is teaspoon', () {
      expect(Unit.tryParse('T'), Unit.tablespoon);
      expect(Unit.tryParse('t'), Unit.teaspoon);
      expect(Unit.tryParse('TBSP'), Unit.tablespoon);
      expect(Unit.tryParse('Tsp'), Unit.teaspoon);
    });

    test('returns null for unknown input', () {
      expect(Unit.tryParse(''), isNull);
      expect(Unit.tryParse('   '), isNull);
      expect(Unit.tryParse('blorp'), isNull);
    });
  });

  group('Unit metadata', () {
    test('US customary conversion constants', () {
      expect(Unit.ounce.toBase, 28.349523125);
      expect(Unit.pound.toBase, 453.59237);
      expect(Unit.teaspoon.toBase, 4.92892);
      expect(Unit.tablespoon.toBase, 14.7868);
      expect(Unit.cup.toBase, 236.588);
      expect(Unit.fluidOunce.toBase, 29.5735);
      expect(Unit.pint.toBase, 473.176);
      expect(Unit.quart.toBase, 946.353);
      expect(Unit.gallon.toBase, 3785.41);
    });

    test('dimensions, systems and convertibility', () {
      expect(Unit.gram.dimension, Dimension.mass);
      expect(Unit.kilogram.isMetric, isTrue);
      expect(Unit.pound.isImperial, isTrue);
      expect(Unit.cup.dimension, Dimension.volume);
      expect(Unit.cup.isImperial, isTrue);
      expect(Unit.box.dimension, Dimension.count);
      expect(Unit.box.convertible, isFalse);
      expect(Unit.piece.convertible, isTrue);
      expect(Unit.dozen.toBase, 12);
    });

    test('display names follow the amount', () {
      expect(Unit.cup.displayName(1), 'cup');
      expect(Unit.cup.displayName(2), 'cups');
      expect(Unit.gram.displayName(1), 'gram');
      // One or less reads singular ("1/2 cup"); zero stays plural.
      expect(Unit.gram.displayName(0.5), 'gram');
      expect(Unit.cup.displayName(0), 'cups');
      expect(Unit.box.displayName(3), 'boxes');
    });
  });
}
