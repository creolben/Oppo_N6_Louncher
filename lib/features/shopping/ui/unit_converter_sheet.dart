import 'package:flutter/material.dart';

import '../../../ui/theme/luminous_home_theme.dart';
import '../models/measurement_converter.dart';
import '../models/quantity.dart';
import '../models/temperature.dart';
import '../models/unit.dart';
import 'grocery_chrome.dart';

/// The everyday-measurements tool, presented as a bottom sheet.
///
/// It is a thin view over [MeasurementConverter] and [convertTemperature]; the
/// conversion and formatting rules live in those testable files.
class UnitConverterSheet extends StatefulWidget {
  /// A quantity to preload the sheet with, e.g. the amount on a list row.
  final Quantity? initial;

  const UnitConverterSheet({super.key, this.initial});

  @override
  State<UnitConverterSheet> createState() => _UnitConverterSheetState();
}

class _UnitConverterSheetState extends State<UnitConverterSheet> {
  late final TextEditingController _input;
  late MeasurementCategory _category;
  late Unit _from;
  late Unit _to;
  late TemperatureUnit _fromTemp;
  late TemperatureUnit _toTemp;

  @override
  void initState() {
    super.initState();
    _fromTemp = TemperatureUnit.fahrenheit;
    _toTemp = TemperatureUnit.celsius;
    final Quantity? initial = widget.initial;
    if (initial != null &&
        (initial.dimension == Dimension.mass ||
            initial.dimension == Dimension.volume)) {
      _category = initial.dimension == Dimension.mass
          ? MeasurementCategory.weight
          : MeasurementCategory.volume;
      _from = initial.unit;
      _to = _counterpart(_from, MeasurementConverter.unitsFor(_category));
      _input = TextEditingController(
        text: MeasurementConverter.formatAmount(initial.amount),
      );
    } else {
      _category = MeasurementCategory.weight;
      _from = Unit.ounce;
      _to = Unit.gram;
      _input = TextEditingController();
    }
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  /// The friendliest opposite-system partner for [from], falling back to any
  /// other unit in [units].
  static Unit _counterpart(Unit from, List<Unit> units) {
    for (final Unit unit in units) {
      if (unit != from && unit.isMetric != from.isMetric) return unit;
    }
    for (final Unit unit in units) {
      if (unit != from) return unit;
    }
    return from;
  }

  void _selectCategory(MeasurementCategory category) {
    setState(() {
      _category = category;
      switch (category) {
        case MeasurementCategory.weight:
          _from = Unit.ounce;
          _to = Unit.gram;
        case MeasurementCategory.volume:
          _from = Unit.cup;
          _to = Unit.milliliter;
        case MeasurementCategory.temperature:
          _fromTemp = TemperatureUnit.fahrenheit;
          _toTemp = TemperatureUnit.celsius;
      }
    });
  }

  void _swap() {
    setState(() {
      if (_category == MeasurementCategory.temperature) {
        final TemperatureUnit from = _fromTemp;
        _fromTemp = _toTemp;
        _toTemp = from;
      } else {
        final Unit from = _from;
        _from = _to;
        _to = from;
      }
    });
  }

  void _applyPair(QuickPair pair) {
    setState(() {
      _category = pair.category;
      if (pair.category == MeasurementCategory.temperature) {
        _fromTemp = pair.fromTemperature!;
        _toTemp = pair.toTemperature!;
      } else {
        _from = pair.fromUnit!;
        _to = pair.toUnit!;
      }
    });
  }

  String get _resultText {
    final double? value = MeasurementConverter.parseAmount(_input.text);
    if (value == null) return '—';
    if (_category == MeasurementCategory.temperature) {
      final double converted = MeasurementConverter.convertTemperature(
        value,
        _fromTemp,
        _toTemp,
      );
      return '${MeasurementConverter.formatAmount(converted)} ${_toTemp.symbol}';
    }
    final double? converted = MeasurementConverter.convert(value, _from, _to);
    if (converted == null) return '—';
    return '${MeasurementConverter.formatAmount(converted)} ${_to.symbol}';
  }

  List<Widget> _allUnitRows() {
    final double? value = MeasurementConverter.parseAmount(_input.text);
    if (value == null) {
      return <Widget>[
        Text(
          'Enter a value to see it in every unit.',
          style: LuminousHomeTheme.caption.copyWith(
            color: LuminousHomeTheme.textMuted,
          ),
        ),
      ];
    }
    if (_category == MeasurementCategory.temperature) {
      return <Widget>[
        for (final TemperatureUnit unit in TemperatureUnit.values)
          _ConversionRow(
            symbol: unit.symbol,
            name: unit.displayName,
            value: MeasurementConverter.formatAmount(
              MeasurementConverter.convertTemperature(value, _fromTemp, unit),
            ),
          ),
      ];
    }
    return <Widget>[
      for (final Unit unit in MeasurementConverter.unitsFor(_category))
        _ConversionRow(
          symbol: unit.symbol,
          name: unit.plural,
          value: MeasurementConverter.formatAmount(
            MeasurementConverter.convert(value, _from, unit) ?? double.nan,
          ),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final double bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return SafeArea(
      top: false,
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.8,
        ),
        decoration: BoxDecoration(
          color: LuminousHomeTheme.glassOpaqueStrong,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(LuminousHomeTheme.cardRadius),
          ),
          border: Border.all(color: LuminousHomeTheme.hairline),
        ),
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            LuminousHomeTheme.screenGutter,
            LuminousHomeTheme.space12,
            LuminousHomeTheme.screenGutter,
            LuminousHomeTheme.space16 + bottomInset,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const _SheetHandle(),
              const SizedBox(height: LuminousHomeTheme.space12),
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      'Unit converter',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: LuminousHomeTheme.title,
                    ),
                  ),
                  GroceryIconButton(
                    icon: Icons.close_rounded,
                    label: 'Close unit converter',
                    onTap: () => Navigator.of(context).maybePop(),
                  ),
                ],
              ),
              const SizedBox(height: LuminousHomeTheme.space12),
              _CategoryRow(category: _category, onSelected: _selectCategory),
              const SizedBox(height: LuminousHomeTheme.space12),
              _ValueField(
                controller: _input,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: LuminousHomeTheme.space12),
              _buildUnitRow(),
              const SizedBox(height: LuminousHomeTheme.space12),
              Text(
                'RESULT',
                style: LuminousHomeTheme.caption.copyWith(
                  color: LuminousHomeTheme.textMuted,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: LuminousHomeTheme.space4),
              Text(
                _resultText,
                key: const ValueKey<String>('unit_converter_result'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: LuminousHomeTheme.title.copyWith(
                  fontSize: 28,
                  color: LuminousHomeTheme.groceryAccent,
                ),
              ),
              const SizedBox(height: LuminousHomeTheme.space16),
              const GrocerySectionLabel(label: 'All units'),
              const SizedBox(height: LuminousHomeTheme.space4),
              ..._allUnitRows(),
              const SizedBox(height: LuminousHomeTheme.space16),
              const GrocerySectionLabel(label: 'Quick pairs'),
              const SizedBox(height: LuminousHomeTheme.space8),
              Wrap(
                spacing: LuminousHomeTheme.space8,
                runSpacing: LuminousHomeTheme.space8,
                children: <Widget>[
                  for (final QuickPair pair in MeasurementConverter.quickPairs)
                    _PairChip(pair: pair, onTap: () => _applyPair(pair)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildUnitRow() {
    if (_category == MeasurementCategory.temperature) {
      return Row(
        children: <Widget>[
          Expanded(
            child: _UnitSelector<TemperatureUnit>(
              semanticLabel: 'From temperature',
              value: _fromTemp,
              items: TemperatureUnit.values,
              labelOf: (TemperatureUnit unit) => unit.symbol,
              onChanged: (TemperatureUnit unit) =>
                  setState(() => _fromTemp = unit),
            ),
          ),
          GroceryIconButton(
            icon: Icons.swap_horiz_rounded,
            label: 'Swap units',
            color: LuminousHomeTheme.groceryAccent,
            onTap: _swap,
          ),
          Expanded(
            child: _UnitSelector<TemperatureUnit>(
              semanticLabel: 'To temperature',
              value: _toTemp,
              items: TemperatureUnit.values,
              labelOf: (TemperatureUnit unit) => unit.symbol,
              onChanged: (TemperatureUnit unit) =>
                  setState(() => _toTemp = unit),
            ),
          ),
        ],
      );
    }
    final List<Unit> units = MeasurementConverter.unitsFor(_category);
    return Row(
      children: <Widget>[
        Expanded(
          child: _UnitSelector<Unit>(
            semanticLabel: 'From unit',
            value: _from,
            items: units,
            labelOf: (Unit unit) => unit.symbol,
            onChanged: (Unit unit) => setState(() => _from = unit),
          ),
        ),
        GroceryIconButton(
          icon: Icons.swap_horiz_rounded,
          label: 'Swap units',
          color: LuminousHomeTheme.groceryAccent,
          onTap: _swap,
        ),
        Expanded(
          child: _UnitSelector<Unit>(
            semanticLabel: 'To unit',
            value: _to,
            items: units,
            labelOf: (Unit unit) => unit.symbol,
            onChanged: (Unit unit) => setState(() => _to = unit),
          ),
        ),
      ],
    );
  }
}

class _SheetHandle extends StatelessWidget {
  const _SheetHandle();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 40,
        height: 4,
        decoration: BoxDecoration(
          color: LuminousHomeTheme.hairlineStrong,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

class _CategoryRow extends StatelessWidget {
  final MeasurementCategory category;
  final ValueChanged<MeasurementCategory> onSelected;

  const _CategoryRow({required this.category, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        for (final MeasurementCategory value in MeasurementCategory.values)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(right: LuminousHomeTheme.space4),
              child: _CategoryChip(
                key: ValueKey<String>('converter_category_${value.name}'),
                label: _labelFor(value),
                selected: value == category,
                onTap: () => onSelected(value),
              ),
            ),
          ),
      ],
    );
  }

  static String _labelFor(MeasurementCategory category) {
    switch (category) {
      case MeasurementCategory.weight:
        return 'Weight';
      case MeasurementCategory.volume:
        return 'Volume';
      case MeasurementCategory.temperature:
        return 'Temperature';
    }
  }
}

class _CategoryChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _CategoryChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final BorderRadius radius = BorderRadius.circular(
      LuminousHomeTheme.controlRadius,
    );
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: Material(
        color: selected
            ? LuminousHomeTheme.grocerySoft
            : LuminousHomeTheme.glass,
        borderRadius: radius,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: Container(
            constraints: const BoxConstraints(
              minHeight: LuminousHomeTheme.minimumTouchTarget,
            ),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: radius,
              border: Border.all(
                color: selected
                    ? LuminousHomeTheme.groceryBright
                    : LuminousHomeTheme.hairline,
              ),
            ),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: LuminousHomeTheme.label.copyWith(
                color: selected
                    ? LuminousHomeTheme.groceryAccent
                    : LuminousHomeTheme.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ValueField extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  const _ValueField({required this.controller, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return TextField(
      key: const ValueKey<String>('unit_converter_input'),
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      onChanged: onChanged,
      style: LuminousHomeTheme.title.copyWith(fontSize: 20),
      cursorColor: LuminousHomeTheme.groceryAccent,
      decoration: InputDecoration(
        hintText: 'Value',
        hintStyle: LuminousHomeTheme.title.copyWith(
          fontSize: 20,
          color: LuminousHomeTheme.textMuted,
        ),
        isDense: true,
        filled: true,
        fillColor: LuminousHomeTheme.glass,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: LuminousHomeTheme.space16,
          vertical: LuminousHomeTheme.space12,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(LuminousHomeTheme.controlRadius),
          borderSide: BorderSide(color: LuminousHomeTheme.hairline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(LuminousHomeTheme.controlRadius),
          borderSide: const BorderSide(color: LuminousHomeTheme.groceryBright),
        ),
      ),
    );
  }
}

class _UnitSelector<T> extends StatelessWidget {
  final String semanticLabel;
  final T value;
  final List<T> items;
  final String Function(T) labelOf;
  final ValueChanged<T> onChanged;

  const _UnitSelector({
    required this.semanticLabel,
    required this.value,
    required this.items,
    required this.labelOf,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticLabel,
      child: Container(
        constraints: const BoxConstraints(
          minHeight: LuminousHomeTheme.minimumTouchTarget,
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: LuminousHomeTheme.space12,
        ),
        decoration: BoxDecoration(
          color: LuminousHomeTheme.glass,
          borderRadius: BorderRadius.circular(LuminousHomeTheme.controlRadius),
          border: Border.all(color: LuminousHomeTheme.hairline),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<T>(
            value: value,
            isExpanded: true,
            dropdownColor: LuminousHomeTheme.glassOpaqueStrong,
            icon: const Icon(
              Icons.expand_more_rounded,
              color: LuminousHomeTheme.textMuted,
            ),
            style: LuminousHomeTheme.label.copyWith(
              color: LuminousHomeTheme.textPrimary,
            ),
            items: <DropdownMenuItem<T>>[
              for (final T item in items)
                DropdownMenuItem<T>(
                  value: item,
                  child: Text(
                    labelOf(item),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: (T? next) {
              if (next != null) onChanged(next);
            },
          ),
        ),
      ),
    );
  }
}

class _ConversionRow extends StatelessWidget {
  final String symbol;
  final String name;
  final String value;

  const _ConversionRow({
    required this.symbol,
    required this.name,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: LuminousHomeTheme.space4),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 56,
            child: Text(
              symbol,
              style: LuminousHomeTheme.label.copyWith(
                color: LuminousHomeTheme.textPrimary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: LuminousHomeTheme.caption.copyWith(
                color: LuminousHomeTheme.textMuted,
              ),
            ),
          ),
          Text(
            value,
            style: LuminousHomeTheme.body.copyWith(
              color: LuminousHomeTheme.groceryAccent,
            ),
          ),
        ],
      ),
    );
  }
}

class _PairChip extends StatelessWidget {
  final QuickPair pair;
  final VoidCallback onTap;

  const _PairChip({required this.pair, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final BorderRadius radius = BorderRadius.circular(
      LuminousHomeTheme.controlRadius,
    );
    return Semantics(
      button: true,
      label: 'Convert ${pair.label}',
      child: Material(
        color: LuminousHomeTheme.glass,
        borderRadius: radius,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: Container(
            constraints: const BoxConstraints(
              minHeight: LuminousHomeTheme.minimumTouchTarget,
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: LuminousHomeTheme.space12,
            ),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: radius,
              border: Border.all(color: LuminousHomeTheme.hairline),
            ),
            child: Text(
              pair.label,
              style: LuminousHomeTheme.label.copyWith(
                color: LuminousHomeTheme.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Presents [UnitConverterSheet] as a modal bottom sheet.
///
/// [initial] preloads the value and the From unit; only mass and volume
/// quantities are meaningful, so count quantities are ignored.
Future<void> showUnitConverterSheet(BuildContext context, {Quantity? initial}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: LuminousHomeTheme.lockScrim,
    builder: (BuildContext sheetContext) =>
        UnitConverterSheet(initial: initial),
  );
}
