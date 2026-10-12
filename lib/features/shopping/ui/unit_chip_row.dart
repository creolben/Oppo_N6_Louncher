import 'package:flutter/material.dart';

import '../../../ui/theme/luminous_home_theme.dart';
import '../models/unit.dart';

/// The units offered by the explicit picker, in display order.
///
/// It deliberately covers one representative of every picker family — mass,
/// volume, and count — so the row stays short enough to scroll horizontally on
/// a phone.
const List<Unit> groceryPickerUnits = <Unit>[
  Unit.ounce,
  Unit.gram,
  Unit.kilogram,
  Unit.pound,
  Unit.milliliter,
  Unit.liter,
  Unit.fluidOunce,
  Unit.cup,
  Unit.piece,
  Unit.dozen,
  Unit.box,
  Unit.pack,
  Unit.can,
  Unit.bag,
  Unit.bottle,
  Unit.jar,
];

/// A compact horizontally scrollable row of unit chips.
///
/// Shared by the quick-add capsule and the item edit sheet. [selected] is null
/// when the amount's unit should come from the parser. [units] is the caller's
/// visible list, so a context-aware picker can show only the relevant family;
/// when [onMore] is set a trailing "More" chip expands the full
/// [groceryPickerUnits] list in place.
class UnitChipRow extends StatelessWidget {
  final Unit? selected;
  final List<Unit> units;
  final ValueChanged<Unit?> onUnitSelected;

  /// When non-null, a "More" chip is shown and expands the picker.
  final VoidCallback? onMore;

  const UnitChipRow({
    super.key,
    required this.selected,
    required this.units,
    required this.onUnitSelected,
    this.onMore,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: LuminousHomeTheme.minimumTouchTarget,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(
          horizontal: LuminousHomeTheme.space4,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            for (final Unit unit in units)
              Padding(
                padding: const EdgeInsets.only(right: LuminousHomeTheme.space8),
                child: _PickerChip(
                  key: ValueKey<String>('unit_chip_${unit.symbol}'),
                  label: unit.symbol,
                  semanticLabel: 'Unit ${unit.symbol}',
                  selected: selected == unit,
                  onTap: () => onUnitSelected(selected == unit ? null : unit),
                ),
              ),
            if (onMore != null)
              _PickerChip(
                key: const ValueKey<String>('unit_chip_more'),
                label: 'More',
                semanticLabel: 'More units',
                icon: Icons.more_horiz_rounded,
                selected: false,
                onTap: onMore!,
              ),
          ],
        ),
      ),
    );
  }
}

class _PickerChip extends StatelessWidget {
  final String label;
  final String semanticLabel;
  final IconData? icon;
  final bool selected;
  final VoidCallback onTap;

  const _PickerChip({
    super.key,
    required this.label,
    required this.semanticLabel,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final BorderRadius radius = BorderRadius.circular(
      LuminousHomeTheme.controlRadius,
    );
    return Semantics(
      button: true,
      selected: selected,
      label: semanticLabel,
      child: Tooltip(
        message: semanticLabel,
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
              padding: const EdgeInsets.symmetric(
                horizontal: LuminousHomeTheme.space12,
              ),
              decoration: BoxDecoration(
                borderRadius: radius,
                border: Border.all(
                  color: selected
                      ? LuminousHomeTheme.groceryBright
                      : LuminousHomeTheme.hairline,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  if (icon != null) ...<Widget>[
                    Icon(
                      icon,
                      size: 16,
                      color: selected
                          ? LuminousHomeTheme.groceryAccent
                          : LuminousHomeTheme.textMuted,
                    ),
                    const SizedBox(width: LuminousHomeTheme.space4),
                  ],
                  Text(
                    label,
                    style: LuminousHomeTheme.label.copyWith(
                      color: selected
                          ? LuminousHomeTheme.groceryAccent
                          : LuminousHomeTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
