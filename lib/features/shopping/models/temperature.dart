/// Temperature scales understood by the unit converter.
///
/// Temperature is deliberately **not** modelled as a [Unit]: unlike mass and
/// volume it has an offset, so a plain multiplier cannot convert between the
/// scales. These pure functions are the only place the offset lives.
enum TemperatureUnit { celsius, fahrenheit, kelvin }

extension TemperatureUnitLabels on TemperatureUnit {
  /// Canonical short label, e.g. `°C`.
  String get symbol {
    switch (this) {
      case TemperatureUnit.celsius:
        return '°C';
      case TemperatureUnit.fahrenheit:
        return '°F';
      case TemperatureUnit.kelvin:
        return 'K';
    }
  }

  /// Human readable name, e.g. `Celsius`.
  String get displayName {
    switch (this) {
      case TemperatureUnit.celsius:
        return 'Celsius';
      case TemperatureUnit.fahrenheit:
        return 'Fahrenheit';
      case TemperatureUnit.kelvin:
        return 'Kelvin';
    }
  }
}

/// Converts [value] from [from] into degrees Celsius.
double temperatureToCelsius(double value, TemperatureUnit from) {
  switch (from) {
    case TemperatureUnit.celsius:
      return value;
    case TemperatureUnit.fahrenheit:
      return (value - 32) * 5 / 9;
    case TemperatureUnit.kelvin:
      return value - 273.15;
  }
}

/// Converts [celsius] into [to].
double temperatureFromCelsius(double celsius, TemperatureUnit to) {
  switch (to) {
    case TemperatureUnit.celsius:
      return celsius;
    case TemperatureUnit.fahrenheit:
      return celsius * 9 / 5 + 32;
    case TemperatureUnit.kelvin:
      return celsius + 273.15;
  }
}

/// Converts [value] from [from] into [to].
double convertTemperature(
  double value,
  TemperatureUnit from,
  TemperatureUnit to,
) {
  if (from == to) return value;
  return temperatureFromCelsius(temperatureToCelsius(value, from), to);
}
