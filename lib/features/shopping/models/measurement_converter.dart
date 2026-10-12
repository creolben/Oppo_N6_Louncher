import 'quantity.dart';
import 'temperature.dart' as temp;
import 'unit.dart';

/// The three tabs of the unit converter.
enum MeasurementCategory { weight, volume, temperature }

/// A named everyday conversion the converter offers as a one-tap chip.
///
/// Weight and volume pairs carry [fromUnit]/[toUnit]; temperature pairs carry
/// [fromTemperature]/[toTemperature]. Exactly one pair is set, selected by
/// [category].
class QuickPair {
  final String label;
  final MeasurementCategory category;
  final Unit? fromUnit;
  final Unit? toUnit;
  final temp.TemperatureUnit? fromTemperature;
  final temp.TemperatureUnit? toTemperature;

  const QuickPair({
    required this.label,
    required this.category,
    this.fromUnit,
    this.toUnit,
    this.fromTemperature,
    this.toTemperature,
  });

  const QuickPair.weight(this.label, this.fromUnit, this.toUnit)
    : category = MeasurementCategory.weight,
      fromTemperature = null,
      toTemperature = null;

  const QuickPair.volume(this.label, this.fromUnit, this.toUnit)
    : category = MeasurementCategory.volume,
      fromTemperature = null,
      toTemperature = null;

  const QuickPair.temperature(
    this.label,
    this.fromTemperature,
    this.toTemperature,
  ) : category = MeasurementCategory.temperature,
      fromUnit = null,
      toUnit = null;
}

/// Pure conversion and formatting logic behind the unit converter sheet.
///
/// Weight and volume reuse [Quantity.tryConvertTo] so there is a single set of
/// factors in [Unit]; temperature delegates to [temp.convertTemperature]. The
/// sheet itself stays a thin view over these functions.
abstract final class MeasurementConverter {
  /// Units shown for [category]. Temperature has its own enum, so this returns
  /// an empty list for it.
  static List<Unit> unitsFor(MeasurementCategory category) {
    switch (category) {
      case MeasurementCategory.weight:
        return const <Unit>[Unit.gram, Unit.kilogram, Unit.ounce, Unit.pound];
      case MeasurementCategory.volume:
        return const <Unit>[
          Unit.milliliter,
          Unit.liter,
          Unit.teaspoon,
          Unit.tablespoon,
          Unit.cup,
          Unit.fluidOunce,
          Unit.pint,
          Unit.quart,
          Unit.gallon,
        ];
      case MeasurementCategory.temperature:
        return const <Unit>[];
    }
  }

  /// Converts [value] from one unit to another, or null when the two units live
  /// in different dimensions or are otherwise incompatible (a packaging count
  /// unit against another).
  static double? convert(double value, Unit from, Unit to) {
    if (from.dimension != Dimension.mass &&
        from.dimension != Dimension.volume) {
      return null;
    }
    return Quantity(value, from).tryConvertTo(to)?.amount;
  }

  /// Converts [value] from one temperature scale to another.
  static double convertTemperature(
    double value,
    temp.TemperatureUnit from,
    temp.TemperatureUnit to,
  ) => temp.convertTemperature(value, from, to);

  /// Parses a typed amount, accepting either a dot or a comma as the decimal
  /// separator. Returns null for an empty or non-numeric string.
  static double? parseAmount(String text) {
    final String trimmed = text.trim();
    if (trimmed.isEmpty) return null;
    return double.tryParse(trimmed.replaceAll(',', '.'));
  }

  /// Formats [value] with at most three decimals, trimming trailing zeros.
  ///
  /// `453.59237` becomes `453.592`, `2.0` becomes `2`, and `-273.15` keeps its
  /// decimals. Values that are not finite fall back to their `toString`.
  static String formatAmount(double value) {
    if (!value.isFinite) return value.toString();
    String text = value.toStringAsFixed(3);
    if (text.contains('.')) {
      text = text.replaceFirst(RegExp(r'0+$'), '');
      text = text.replaceFirst(RegExp(r'\.$'), '');
    }
    // `-0` reads badly and is never a meaningful measurement.
    if (text == '-0') return '0';
    return text;
  }

  /// The everyday conversions offered as quick-pair chips.
  static const List<QuickPair> quickPairs = <QuickPair>[
    QuickPair.weight('oz → g', Unit.ounce, Unit.gram),
    QuickPair.weight('g → oz', Unit.gram, Unit.ounce),
    QuickPair.weight('lb → kg', Unit.pound, Unit.kilogram),
    QuickPair.weight('kg → lb', Unit.kilogram, Unit.pound),
    QuickPair.volume('fl oz → ml', Unit.fluidOunce, Unit.milliliter),
    QuickPair.volume('cup → ml', Unit.cup, Unit.milliliter),
    QuickPair.volume('tbsp → ml', Unit.tablespoon, Unit.milliliter),
    QuickPair.volume('tsp → ml', Unit.teaspoon, Unit.milliliter),
    QuickPair.volume('L → gal', Unit.liter, Unit.gallon),
    QuickPair.temperature(
      '°F → °C',
      temp.TemperatureUnit.fahrenheit,
      temp.TemperatureUnit.celsius,
    ),
    QuickPair.temperature(
      '°C → °F',
      temp.TemperatureUnit.celsius,
      temp.TemperatureUnit.fahrenheit,
    ),
  ];
}
