import 'package:flutter_test/flutter_test.dart';
import 'package:mylauncher/features/shopping/models/quantity.dart';
import 'package:mylauncher/features/shopping/models/unit.dart';

void main() {
  group('conversion', () {
    test('within mass', () {
      expect(
        Quantity(1000, Unit.gram).convertTo(Unit.kilogram),
        Quantity(1, Unit.kilogram),
      );
      expect(Quantity(1, Unit.kilogram).convertTo(Unit.gram).amount, 1000);
    });

    test('within volume', () {
      expect(Quantity(1, Unit.liter).convertTo(Unit.milliliter).amount, 1000);
      expect(
        Quantity(1, Unit.cup).convertTo(Unit.tablespoon).amount,
        closeTo(16, 0.001),
      );
      expect(
        Quantity(1, Unit.gallon).convertTo(Unit.quart).amount,
        closeTo(4, 0.001),
      );
    });

    test('across metric and imperial within a dimension', () {
      expect(
        Quantity(1, Unit.kilogram).convertTo(Unit.pound).amount,
        closeTo(2.20462, 0.001),
      );
      expect(
        Quantity(1, Unit.pound).convertTo(Unit.ounce).amount,
        closeTo(16, 1e-9),
      );
    });

    test('piece and dozen convert', () {
      expect(
        Quantity(1, Unit.dozen).convertTo(Unit.piece),
        Quantity(12, Unit.piece),
      );
      expect(
        Quantity(12, Unit.piece).convertTo(Unit.dozen),
        Quantity(1, Unit.dozen),
      );
    });

    test('packaging units do not convert, and dimensions never mix', () {
      expect(Quantity(1, Unit.box).tryConvertTo(Unit.gram), isNull);
      expect(Quantity(1, Unit.box).tryConvertTo(Unit.can), isNull);
      expect(Quantity(1, Unit.dozen).tryConvertTo(Unit.box), isNull);
      expect(Quantity(1, Unit.gram).tryConvertTo(Unit.milliliter), isNull);
      expect(Quantity(1, Unit.gram).tryConvertTo(Unit.piece), isNull);
      expect(
        () => Quantity(1, Unit.box).convertTo(Unit.gram),
        throwsArgumentError,
      );
    });
  });

  group('merge', () {
    test('500 g + 1 kg = 1.5 kg', () {
      final result = Quantity(500, Unit.gram) + Quantity(1, Unit.kilogram);
      expect(result, Quantity(1.5, Unit.kilogram));
    });

    test('same unit merges', () {
      expect(
        Quantity(100, Unit.gram) + Quantity(50, Unit.gram),
        Quantity(150, Unit.gram),
      );
      expect(
        Quantity(2, Unit.box) + Quantity(3, Unit.box),
        Quantity(5, Unit.box),
      );
    });

    test('compatible count units convert into the larger unit', () {
      expect(
        Quantity(1, Unit.dozen) + Quantity(6, Unit.piece),
        Quantity(1.5, Unit.dozen),
      );
    });

    test('never merges across dimensions', () {
      expect(
        Quantity(500, Unit.gram).tryMerge(Quantity(1, Unit.liter)),
        isNull,
      );
      expect(Quantity(1, Unit.box).tryMerge(Quantity(500, Unit.gram)), isNull);
      expect(
        () => Quantity(1, Unit.gram) + Quantity(1, Unit.milliliter),
        throwsArgumentError,
      );
    });

    test('packaging units only merge with themselves', () {
      expect(Quantity(1, Unit.box).tryMerge(Quantity(1, Unit.can)), isNull);
    });
  });

  group('scale', () {
    test('count units round up', () {
      expect(Quantity(2.4, Unit.piece).scale(1), Quantity(3, Unit.piece));
      expect(Quantity(3, Unit.piece).scale(1.5), Quantity(5, Unit.piece));
      expect(Quantity(0.1, Unit.box).scale(1), Quantity(1, Unit.box));
    });

    test('non-count units keep precision', () {
      expect(Quantity(1.25, Unit.cup).scale(2).amount, closeTo(2.5, 1e-9));
      expect(Quantity(100, Unit.gram).scale(1.5).amount, closeTo(150, 1e-9));
    });
  });

  group('normalized', () {
    test('metric picks the friendly unit', () {
      expect(
        Quantity(1500, Unit.gram).normalized(),
        Quantity(1.5, Unit.kilogram),
      );
      expect(
        Quantity(0.25, Unit.liter).normalized(),
        Quantity(250, Unit.milliliter),
      );
      expect(Quantity(500, Unit.gram).normalized(), Quantity(500, Unit.gram));
    });

    test('imperial picks the friendly unit', () {
      expect(Quantity(16, Unit.ounce).normalized(), Quantity(1, Unit.pound));
      expect(Quantity(8, Unit.ounce).normalized(), Quantity(8, Unit.ounce));
      expect(Quantity(48, Unit.teaspoon).normalized(), Quantity(1, Unit.cup));
      expect(Quantity(0.75, Unit.cup).normalized(), Quantity(0.75, Unit.cup));
      expect(Quantity(2, Unit.tablespoon).normalized(), Quantity(2, Unit.tablespoon));
    });

    test('count units are left alone', () {
      expect(Quantity(3, Unit.box).normalized(), Quantity(3, Unit.box));
    });
  });

  group('format', () {
    test('metric trims decimals', () {
      expect(Quantity(1.5, Unit.kilogram).format(), '1.5 kg');
      expect(Quantity(250, Unit.milliliter).format(), '250 ml');
      expect(Quantity(236.588, Unit.milliliter).format(), '236.59 ml');
      expect(Quantity(1000, Unit.gram).format(), '1 kg');
    });

    test('imperial uses common fractions and mixed numbers', () {
      expect(Quantity(1.5, Unit.cup).format(preferImperial: true), '1 1/2 cups');
      expect(Quantity(0.75, Unit.cup).format(preferImperial: true), '3/4 cup');
      expect(Quantity(1, Unit.cup).format(preferImperial: true), '1 cup');
      expect(Quantity(16, Unit.ounce).format(preferImperial: true), '1 pound');
      expect(
        Quantity(500, Unit.gram).format(preferImperial: true),
        '1 1/8 pounds',
      );
    });

    test('count units use names', () {
      // The implicit piece renders as a bare number ("2 milk").
      expect(Quantity(3, Unit.piece).format(), '3');
      expect(Quantity(1, Unit.box).format(), '1 box');
      expect(Quantity(2, Unit.dozen).format(), '2 dozen');
    });

    test('preference converts between systems', () {
      expect(Quantity(1, Unit.cup).format(), '236.59 ml');
      expect(Quantity(8, Unit.ounce).format(), '226.8 g');
      expect(Quantity(1, Unit.kilogram).format(preferImperial: true), '2 1/4 pounds');
    });
  });

  group('formatAsEntered', () {
    test('keeps metric mass and volume in the entered unit', () {
      expect(Quantity(250, Unit.gram).formatAsEntered(), '250 g');
      expect(Quantity(1.5, Unit.kilogram).formatAsEntered(), '1.5 kg');
      expect(Quantity(236.588, Unit.milliliter).formatAsEntered(), '236.59 ml');
      // No friendly-unit upgrade: 1000 g stays in grams.
      expect(Quantity(1000, Unit.gram).formatAsEntered(), '1000 g');
    });

    test('imperial and count units use fractions and names', () {
      expect(Quantity(16, Unit.ounce).formatAsEntered(), '16 ounces');
      expect(Quantity(1.5, Unit.cup).formatAsEntered(), '1 1/2 cups');
      expect(Quantity(2, Unit.box).formatAsEntered(), '2 boxes');
      expect(Quantity(1, Unit.piece).formatAsEntered(), '1');
      expect(Quantity(0.5, Unit.cup).formatAsEntered(), '1/2 cup');
      expect(Quantity(2, Unit.clove).formatAsEntered(), '2 cloves');
    });
  });

  group('approxIn', () {
    test('is null in the preferred system and for counts', () {
      expect(Quantity(250, Unit.gram).approxIn(preferImperial: false), isNull);
      expect(Quantity(16, Unit.ounce).approxIn(preferImperial: true), isNull);
      expect(Quantity(2, Unit.box).approxIn(preferImperial: false), isNull);
      expect(Quantity(2, Unit.box).approxIn(preferImperial: true), isNull);
    });

    test('rounds imperial mass and volume to friendly metric values', () {
      expect(
        Quantity(16, Unit.ounce).approxIn(preferImperial: false),
        '≈ 450 g',
      );
      expect(
        Quantity(1, Unit.ounce).approxIn(preferImperial: false),
        '≈ 30 g',
      );
      expect(
        Quantity(1, Unit.cup).approxIn(preferImperial: false),
        '≈ 240 ml',
      );
      expect(
        Quantity(1, Unit.tablespoon).approxIn(preferImperial: false),
        '≈ 15 ml',
      );
    });

    test('uses imperial fractions for metric amounts', () {
      expect(
        Quantity(500, Unit.gram).approxIn(preferImperial: true),
        '≈ 1 1/8 pounds',
      );
      expect(
        Quantity(453.59237, Unit.gram).approxIn(preferImperial: true),
        '≈ 1 pound',
      );
      expect(
        Quantity(236.588, Unit.milliliter).approxIn(preferImperial: true),
        '≈ 1 cup',
      );
    });
  });

  group('plural agreement follows the rendered amount', () {
    test('a value rendered as 1 uses the singular name', () {
      expect(Quantity(1.0567, Unit.quart).format(preferImperial: true), '1 quart');
      expect(Quantity(1.02, Unit.cup).formatAsEntered(), '1 cup');
      expect(Quantity(1, Unit.liter).approxIn(preferImperial: true), '≈ 1 quart');
    });

    test('other amounts keep the plural name', () {
      expect(Quantity(2, Unit.quart).formatAsEntered(), '2 quarts');
      expect(Quantity(1.5, Unit.cup).formatAsEntered(), '1 1/2 cups');
    });
  });
}
