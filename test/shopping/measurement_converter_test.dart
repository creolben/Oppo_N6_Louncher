import 'package:flutter_test/flutter_test.dart';
import 'package:mylauncher/features/shopping/models/measurement_converter.dart';
import 'package:mylauncher/features/shopping/models/temperature.dart';
import 'package:mylauncher/features/shopping/models/unit.dart';

void main() {
  group('MeasurementConverter.convert', () {
    test('16 oz == 453.59 g', () {
      final double? grams = MeasurementConverter.convert(
        16,
        Unit.ounce,
        Unit.gram,
      );
      expect(grams, isNotNull);
      expect(grams!, closeTo(453.59, 0.01));
    });

    test('1 kg ≈ 2.20462 lb', () {
      final double? pounds = MeasurementConverter.convert(
        1,
        Unit.kilogram,
        Unit.pound,
      );
      expect(pounds, isNotNull);
      expect(pounds!, closeTo(2.20462, 1e-4));
    });

    test('1 cup ≈ 236.588 ml', () {
      final double? millilitres = MeasurementConverter.convert(
        1,
        Unit.cup,
        Unit.milliliter,
      );
      expect(millilitres, closeTo(236.588, 1e-6));
    });

    test('1 tbsp ≈ 14.7868 ml', () {
      final double? millilitres = MeasurementConverter.convert(
        1,
        Unit.tablespoon,
        Unit.milliliter,
      );
      expect(millilitres, closeTo(14.7868, 1e-9));
    });

    test('a cross-dimension conversion returns null', () {
      expect(
        MeasurementConverter.convert(1, Unit.kilogram, Unit.liter),
        isNull,
      );
      expect(MeasurementConverter.convert(1, Unit.piece, Unit.gram), isNull);
      expect(MeasurementConverter.convert(2, Unit.box, Unit.can), isNull);
      expect(MeasurementConverter.convert(1, Unit.gram, Unit.ounce), isNotNull);
    });
  });

  group('temperature conversion', () {
    test('212°F == 100°C', () {
      expect(
        MeasurementConverter.convertTemperature(
          212,
          TemperatureUnit.fahrenheit,
          TemperatureUnit.celsius,
        ),
        closeTo(100, 1e-9),
      );
    });

    test('0°C == 32°F', () {
      expect(
        MeasurementConverter.convertTemperature(
          0,
          TemperatureUnit.celsius,
          TemperatureUnit.fahrenheit,
        ),
        closeTo(32, 1e-9),
      );
    });

    test('0 K == -273.15°C', () {
      expect(
        MeasurementConverter.convertTemperature(
          0,
          TemperatureUnit.kelvin,
          TemperatureUnit.celsius,
        ),
        closeTo(-273.15, 1e-9),
      );
    });
  });

  group('formatAmount', () {
    test('trims trailing zeros', () {
      expect(MeasurementConverter.formatAmount(2), '2');
      expect(MeasurementConverter.formatAmount(2.5), '2.5');
      expect(MeasurementConverter.formatAmount(1.25), '1.25');
      expect(MeasurementConverter.formatAmount(0), '0');
      expect(MeasurementConverter.formatAmount(-273.15), '-273.15');
    });

    test('keeps at most three decimals', () {
      expect(MeasurementConverter.formatAmount(453.59237), '453.592');
      expect(MeasurementConverter.formatAmount(236.588), '236.588');
    });
  });

  group('parseAmount', () {
    test('comma decimal input parses', () {
      expect(MeasurementConverter.parseAmount('1,5'), 1.5);
      expect(MeasurementConverter.parseAmount('1.5'), 1.5);
      expect(MeasurementConverter.parseAmount(' 2 '), 2);
      expect(MeasurementConverter.parseAmount(''), isNull);
      expect(MeasurementConverter.parseAmount('nope'), isNull);
    });
  });

  group('quick pairs', () {
    test('cover the everyday conversions', () {
      final List<String> labels = MeasurementConverter.quickPairs
          .map((QuickPair pair) => pair.label)
          .toList();
      expect(
        labels,
        containsAll(<String>[
          'oz → g',
          'g → oz',
          'lb → kg',
          'kg → lb',
          'fl oz → ml',
          'cup → ml',
          'tbsp → ml',
          'tsp → ml',
          'L → gal',
          '°F → °C',
          '°C → °F',
        ]),
      );
    });

    test('resolve to the matching category and units', () {
      final QuickPair ozToGrams = MeasurementConverter.quickPairs.firstWhere(
        (QuickPair pair) => pair.label == 'oz → g',
      );
      expect(ozToGrams.category, MeasurementCategory.weight);
      expect(ozToGrams.fromUnit, Unit.ounce);
      expect(ozToGrams.toUnit, Unit.gram);

      final QuickPair fahrenheitToCelsius = MeasurementConverter.quickPairs
          .firstWhere((QuickPair pair) => pair.label == '°F → °C');
      expect(fahrenheitToCelsius.category, MeasurementCategory.temperature);
      expect(fahrenheitToCelsius.fromTemperature, TemperatureUnit.fahrenheit);
      expect(fahrenheitToCelsius.toTemperature, TemperatureUnit.celsius);
    });
  });
}
