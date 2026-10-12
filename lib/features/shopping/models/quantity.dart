import 'unit.dart';

/// An immutable amount together with its [Unit].
class Quantity {
  final double amount;
  final Unit unit;

  const Quantity(this.amount, this.unit);

  Dimension get dimension => unit.dimension;

  bool get isMetric => unit.isMetric;

  /// Converts to [target] when the units share a dimension and are compatible.
  ///
  /// Returns null for a cross-dimension request, for two different packaging
  /// count units, or for a packaging unit against a convertible one.
  Quantity? tryConvertTo(Unit target) {
    if (target.dimension != dimension) return null;
    if (target == unit) return Quantity(amount, target);
    if (dimension == Dimension.count && !(unit.convertible && target.convertible)) {
      return null;
    }
    final base = amount * unit.toBase;
    return Quantity(base / target.toBase, target);
  }

  /// Like [tryConvertTo] but throws [ArgumentError] when incompatible.
  Quantity convertTo(Unit target) {
    final converted = tryConvertTo(target);
    if (converted == null) {
      throw ArgumentError(
        'Cannot convert ${unit.symbol} to ${target.symbol}',
      );
    }
    return converted;
  }

  /// Merges [other] into this quantity, or returns null when incompatible.
  ///
  /// The sum is expressed in the larger-magnitude unit of the two operands, so
  /// `500 g + 1 kg` is `1.5 kg`.
  Quantity? tryMerge(Quantity other) {
    if (dimension != other.dimension) return null;
    if (dimension == Dimension.count) {
      if (!unit.convertible || !other.unit.convertible) {
        if (unit != other.unit) return null;
        return Quantity(amount + other.amount, unit);
      }
    }
    final baseTotal = amount * unit.toBase + other.amount * other.unit.toBase;
    final target = unit.toBase >= other.unit.toBase ? unit : other.unit;
    return Quantity(baseTotal / target.toBase, target);
  }

  /// Merges compatible quantities; throws when they cannot be merged.
  Quantity operator +(Quantity other) {
    final merged = tryMerge(other);
    if (merged == null) {
      throw ArgumentError(
        'Cannot add ${other.unit.symbol} to ${unit.symbol}: incompatible quantities',
      );
    }
    return merged;
  }

  /// Multiplies the amount by [factor].
  ///
  /// Count units round **up** to the next whole item (`2.4 eggs` becomes
  /// `3 eggs`), because a shopping list cannot buy a fraction of a discrete
  /// thing. Every other dimension keeps full precision.
  Quantity scale(double factor) {
    final scaled = amount * factor;
    if (dimension == Dimension.count) {
      return Quantity(scaled.ceilToDouble(), unit);
    }
    return Quantity(scaled, unit);
  }

  /// Rewrites the amount in the friendliest unit that stays in the same system.
  ///
  /// Metric mass picks `kg` at 1000 g or above, metric volume picks `L` at
  /// 1000 ml or above, imperial mass picks `lb` at 16 oz or above, and imperial
  /// volume only upgrades to a larger spoon/cup/pint/quart/gallon so a cup
  /// never degrades into tablespoons.
  Quantity normalized() {
    if (dimension == Dimension.count) return this;
    final base = amount * unit.toBase;

    if (unit.isMetric) {
      if (dimension == Dimension.mass) {
        return base >= 1000
            ? Quantity(_clean(base / Unit.kilogram.toBase), Unit.kilogram)
            : Quantity(_clean(base), Unit.gram);
      }
      return base >= 1000
          ? Quantity(_clean(base / Unit.liter.toBase), Unit.liter)
          : Quantity(_clean(base), Unit.milliliter);
    }

    if (dimension == Dimension.mass) {
      final ounces = base / Unit.ounce.toBase;
      return ounces >= 16
          ? Quantity(_clean(ounces / 16), Unit.pound)
          : Quantity(_clean(ounces), Unit.ounce);
    }

    // Imperial volume: climb to the largest spoon/cup/pint/quart/gallon that
    // holds at least one whole unit. Fluid ounces are intentionally left out of
    // the ladder so `2 tbsp` does not turn into `1 fluid ounce`.
    const ladder = <Unit>[
      Unit.teaspoon,
      Unit.tablespoon,
      Unit.cup,
      Unit.pint,
      Unit.quart,
      Unit.gallon,
    ];
    var best = Quantity(amount, unit);
    var bestFactor = unit.toBase;
    for (final candidate in ladder) {
      if (candidate.toBase < unit.toBase) continue;
      final value = base / candidate.toBase;
      if (value >= 1 - 1e-9 && candidate.toBase > bestFactor) {
        best = Quantity(_clean(value), candidate);
        bestFactor = candidate.toBase;
      }
    }
    return best;
  }

  /// Human readable representation.
  ///
  /// Metric mass and volume use up to two trimmed decimals (`1.5 kg`,
  /// `250 ml`). Imperial mass and volume use the nearest common recipe
  /// fraction (`1 1/2 cups`, `3/4 lb`). Count and imperial units take their
  /// singular or plural display name, chosen from the *rendered* amount.
  String format({bool preferImperial = false}) {
    final display = _displayFor(preferImperial);
    final rendered = display.unit;
    final isSymbolUnit = rendered.isMetric && rendered.dimension != Dimension.count;
    final amountText =
        isSymbolUnit ? _trimDecimal(display.amount) : _formatFraction(display.amount);
    final suffix = isSymbolUnit
        ? rendered.symbol
        : rendered.displayName(_pluralAmount(amountText, display.amount));
    return '$amountText $suffix';
  }

  /// The amount exactly as it is stored, with no cross-system conversion and no
  /// friendly-unit upgrade.
  ///
  /// Metric mass and volume use trimmed decimals plus the symbol (`250 g`,
  /// `1.5 kg`). Imperial and count units use the nearest common recipe fraction
  /// plus the singular/plural name (`16 ounces`, `1 1/2 cups`, `2 boxes`). This
  /// is what the user typed (or a merged amount in the same unit), so a list row
  /// can always show the entered unit and offer the preferred system as a
  /// secondary approximation via [approxIn].
  String formatAsEntered() {
    final bool isSymbolUnit = unit.isMetric && dimension != Dimension.count;
    final String amountText =
        isSymbolUnit ? _trimDecimal(amount) : _formatFraction(amount);
    final String suffix =
        isSymbolUnit ? unit.symbol : unit.displayName(_pluralAmount(amountText, amount));
    return '$amountText $suffix';
  }

  /// Amount used for singular/plural agreement: a value that renders as
  /// exactly `1` (1.06 quarts shown as `1`) takes the singular name, so a
  /// label never reads `1 quarts`.
  static double _pluralAmount(String amountText, double amount) =>
      amountText == '1' ? 1 : amount;

  /// A rounded amount in the preferred measurement system, or null when the
  /// quantity's own system already matches [preferImperial].
  ///
  /// Only [Dimension.mass] and [Dimension.volume] have a cross-system twin, so
  /// count and packaging units always return null. The text is prefixed with
  /// `≈`. Metric targets round grams and millilitres to the nearest 5 (or 10 at
  /// and above 100), while imperial targets reuse the existing conversion,
  /// unit normalization and fraction formatting.
  String? approxIn({required bool preferImperial}) {
    if (dimension == Dimension.count) return null;
    final bool wantMetric = !preferImperial;
    if (unit.isMetric == wantMetric) return null;

    final double base = amount * unit.toBase;
    if (wantMetric) {
      final Unit target = Unit.baseFor(dimension);
      return '≈ ${_trimDecimal(_roundApprox(base))} ${target.symbol}';
    }

    final Unit imperialBase =
        dimension == Dimension.mass ? Unit.ounce : Unit.teaspoon;
    final Quantity converted =
        Quantity(base / imperialBase.toBase, imperialBase).normalized();
    return '≈ ${converted.format(preferImperial: true)}';
  }

  /// Rounds a base-unit approximation to a friendly value: nearest 10 at and
  /// above 100, nearest 5 between 10 and 100, and a whole number below that.
  static double _roundApprox(double value) {
    if (value >= 100) return (value / 10).round() * 10.0;
    if (value >= 10) return (value / 5).round() * 5.0;
    return value.roundToDouble();
  }

  /// The quantity as it should be shown under the metric/imperial preference.
  Quantity _displayFor(bool preferImperial) {
    if (dimension == Dimension.count) return normalized();
    final wantMetric = !preferImperial;
    if (unit.isMetric == wantMetric) return normalized();

    final base = amount * unit.toBase;
    if (wantMetric) {
      return Quantity(base, Unit.baseFor(dimension)).normalized();
    }
    final imperialBase = dimension == Dimension.mass ? Unit.ounce : Unit.teaspoon;
    return Quantity(base / imperialBase.toBase, imperialBase).normalized();
  }

  Quantity copyWith({double? amount, Unit? unit}) =>
      Quantity(amount ?? this.amount, unit ?? this.unit);

  Map<String, dynamic> toJson() => {'amount': amount, 'unit': unit.symbol};

  factory Quantity.fromJson(Map<String, dynamic> json) {
    final unit = Unit.tryParse(json['unit'] as String? ?? '');
    if (unit == null) {
      throw FormatException('Unknown unit: ${json['unit']}');
    }
    return Quantity((json['amount'] as num).toDouble(), unit);
  }

  static const List<(double, String)> _fractions = [
    (0.0, ''),
    (0.125, '1/8'),
    (0.25, '1/4'),
    (0.3333333333, '1/3'),
    (0.5, '1/2'),
    (0.6666666667, '2/3'),
    (0.75, '3/4'),
    (1.0, ''),
  ];

  /// Rounds away floating-point noise so `48 tsp` normalizes to exactly
  /// `1 cup` instead of `1.0000007 cup`.
  static double _clean(double value) {
    final rounded = double.parse(value.toStringAsFixed(6));
    final nearest = rounded.roundToDouble();
    if ((rounded - nearest).abs() < 1e-4) return nearest;
    return rounded;
  }

  static String _trimDecimal(double value) {
    if (!value.isFinite) return value.toString();
    if (value == value.roundToDouble()) return value.toInt().toString();
    var text = value.toStringAsFixed(2);
    if (text.contains('.')) {
      text = text.replaceFirst(RegExp(r'0+$'), '');
      text = text.replaceFirst(RegExp(r'\.$'), '');
    }
    return text;
  }

  static String _formatFraction(double value) {
    if (value == 0) return '0';
    final negative = value < 0;
    final absolute = value.abs();
    var whole = absolute.floor();
    final fraction = absolute - whole;

    var best = _fractions.first;
    var bestDistance = (fraction - best.$1).abs();
    for (final candidate in _fractions) {
      final distance = (fraction - candidate.$1).abs();
      if (distance < bestDistance) {
        best = candidate;
        bestDistance = distance;
      }
    }

    String result;
    if (best.$2.isEmpty) {
      if (best.$1 == 1.0) whole += 1;
      result = '$whole';
    } else if (whole == 0) {
      result = best.$2;
    } else {
      result = '$whole ${best.$2}';
    }
    return negative ? '-$result' : result;
  }

  @override
  bool operator ==(Object other) =>
      other is Quantity && other.amount == amount && other.unit == unit;

  @override
  int get hashCode => Object.hash(amount, unit);

  @override
  String toString() => '${_trimDecimal(amount)} ${unit.symbol}';
}
