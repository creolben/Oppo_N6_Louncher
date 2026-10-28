import 'package:flutter/material.dart';

import '../../../core/launcher_haptics.dart';
import '../../../ui/theme/luminous_home_theme.dart';
import '../models/measurement_converter.dart';
import '../models/quantity.dart';
import '../models/shopping_item.dart';
import '../models/shopping_list.dart';
import '../models/unit.dart';
import '../shopping_controller.dart';
import 'grocery_chrome.dart';
import 'unit_chip_row.dart';
import 'unit_converter_sheet.dart';

/// The inline editor Keep shows for a list row, as a bottom sheet.
///
/// It reuses [UnitChipRow] so the unit picker behaves the same as the quick-add
/// capsule. Aisle, including Frozen, is the single source of truth through the
/// Aisle dropdown; there is no separate frozen flag. Nothing is written
/// directly: indentation, like every other field, is staged until Save, which
/// calls [ShoppingController.updateItem] so the debounced store save stays the
/// single source of truth. Delete removes the row with the same undo snack bar
/// a swipe offers.
class ItemEditSheet extends StatefulWidget {
  final ShoppingController controller;
  final ShoppingList list;
  final ShoppingItem item;

  const ItemEditSheet({
    super.key,
    required this.controller,
    required this.list,
    required this.item,
  });

  @override
  State<ItemEditSheet> createState() => _ItemEditSheetState();
}

class _ItemEditSheetState extends State<ItemEditSheet> {
  late final TextEditingController _name = TextEditingController(
    text: widget.item.name,
  );
  late final TextEditingController _amount = TextEditingController(
    text: widget.item.quantity == null
        ? ''
        : MeasurementConverter.formatAmount(widget.item.quantity!.amount),
  );
  late final TextEditingController _note = TextEditingController(
    text: widget.item.note ?? '',
  );

  late Unit? _unit = widget.item.quantity?.unit;
  late String _aisle = widget.item.aisle;
  late String? _parentId = widget.item.parentId;

  /// Where Indent would put the row, computed once from the saved list.
  late final String? _indentTarget =
      widget.controller.indentTargetFor(widget.list.id, widget.item.id);

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  /// Whether the amount field holds text that is not a usable amount.
  bool get _amountInvalid {
    final String text = _amount.text.trim();
    if (text.isEmpty) return false;
    final double? amount = MeasurementConverter.parseAmount(text);
    return amount == null || !amount.isFinite || amount <= 0;
  }

  /// The edited quantity. An empty amount removes the quantity, even with a
  /// unit selected.
  Quantity? get _quantity {
    if (_amountInvalid) return null;
    final double? amount = MeasurementConverter.parseAmount(_amount.text);
    if (amount == null) return null;
    return Quantity(amount, _unit ?? Unit.piece);
  }

  /// Whether the unit converter can meaningfully preload this quantity.
  bool get _isConvertible {
    final Dimension? dimension = _quantity?.unit.dimension;
    return dimension == Dimension.mass || dimension == Dimension.volume;
  }

  void _openConverter() {
    final Quantity? quantity = _quantity;
    if (quantity == null) return;
    showUnitConverterSheet(context, initial: quantity);
  }

  void _selectUnit(Unit? unit) {
    setState(() {
      _unit = unit;
      // Picking a unit for an item with no amount means "one of these".
      if (unit != null && _amount.text.trim().isEmpty) _amount.text = '1';
    });
  }

  bool get _canIndent => _parentId == null && _indentTarget != null;

  bool get _canOutdent => _parentId != null;

  void _indent() => setState(() => _parentId = _indentTarget);

  void _outdent() => setState(() => _parentId = null);

  bool get _canSave => _name.text.trim().isNotEmpty && !_amountInvalid;

  void _save() {
    if (!_canSave) return;
    final String name = _name.text.trim();
    final String note = _note.text.trim();
    widget.controller.updateItem(
      widget.list.id,
      ShoppingItem(
        id: widget.item.id,
        name: name,
        quantity: _quantity,
        aisle: _aisle,
        checked: widget.item.checked,
        note: note.isEmpty ? null : note,
        sourceRecipeId: widget.item.sourceRecipeId,
        parentId: _parentId,
        // A typed amount replaces the imported wording rather than hiding it.
        amountText: _quantity == null ? widget.item.amountText : null,
        costCents: widget.item.costCents,
        days: widget.item.days,
      ),
    );
    Navigator.of(context).maybePop();
  }

  void _delete() {
    final String listId = widget.list.id;
    final ShoppingController controller = widget.controller;
    final RemovedItem? removed = controller.removeItem(listId, widget.item.id);
    if (removed == null) return;
    LauncherHaptics.heavyClick();
    // Shown before the pop so the sheet's context still reaches the messenger.
    showGrocerySnackBar(
      context,
      'Removed ${widget.item.name}',
      actionLabel: 'Undo',
      onAction: () => controller.restoreItems(listId, <RemovedItem>[removed]),
    );
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final double bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: LuminousHomeTheme.glassOpaqueStrong,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(LuminousHomeTheme.cardRadius),
          ),
          border: Border.all(color: LuminousHomeTheme.hairline),
        ),
        padding: EdgeInsets.fromLTRB(
          LuminousHomeTheme.screenGutter,
          LuminousHomeTheme.space12,
          LuminousHomeTheme.screenGutter,
          LuminousHomeTheme.space16 + bottomInset,
        ),
        child: SingleChildScrollView(
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
                      'Edit item',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: LuminousHomeTheme.title,
                    ),
                  ),
                  GroceryIconButton(
                    icon: Icons.close_rounded,
                    label: 'Close edit item',
                    onTap: () => Navigator.of(context).maybePop(),
                  ),
                ],
              ),
              const SizedBox(height: LuminousHomeTheme.space8),
              _Field(
                key: const ValueKey<String>('edit_item_name'),
                controller: _name,
                label: 'Name',
                hint: 'Item name',
                textInputAction: TextInputAction.next,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: LuminousHomeTheme.space12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  SizedBox(
                    width: 110,
                    child: _Field(
                      key: const ValueKey<String>('edit_item_amount'),
                      controller: _amount,
                      label: 'Amount',
                      // An imported amount (`4 medium bulbs`) stays visible
                      // until a structured one is typed over it.
                      hint: widget.item.amountText ?? '1',
                      // Text, not a number pad, so `1 1/2` and `½` can be
                      // typed.
                      keyboardType: TextInputType.text,
                      errorText: _amountInvalid ? 'Not a number' : null,
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: LuminousHomeTheme.space12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          'AISLE',
                          style: LuminousHomeTheme.caption.copyWith(
                            color: LuminousHomeTheme.textMuted,
                            letterSpacing: 1.2,
                          ),
                        ),
                        const SizedBox(height: LuminousHomeTheme.space4),
                        _AisleDropdown(
                          value: _aisle,
                          onChanged: (String value) =>
                              setState(() => _aisle = value),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: LuminousHomeTheme.space12),
              Text(
                'UNIT',
                style: LuminousHomeTheme.caption.copyWith(
                  color: LuminousHomeTheme.textMuted,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: LuminousHomeTheme.space4),
              UnitChipRow(
                selected: _unit,
                units: groceryPickerUnits,
                onUnitSelected: _selectUnit,
              ),
              if (_isConvertible) ...<Widget>[
                const SizedBox(height: LuminousHomeTheme.space12),
                GroceryActionButton(
                  key: const ValueKey<String>('item_convert'),
                  icon: Icons.straighten_rounded,
                  label: 'Convert',
                  onTap: _openConverter,
                ),
              ],
              const SizedBox(height: LuminousHomeTheme.space12),
              _Field(
                key: const ValueKey<String>('edit_item_note'),
                controller: _note,
                label: 'Note',
                hint: 'Optional note',
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _save(),
              ),
              const SizedBox(height: LuminousHomeTheme.space12),
              Row(
                children: <Widget>[
                  Expanded(
                    child: GroceryActionButton(
                      key: const ValueKey<String>('item_indent'),
                      icon: Icons.subdirectory_arrow_right_rounded,
                      label: 'Indent',
                      onTap: _canIndent ? _indent : null,
                    ),
                  ),
                  const SizedBox(width: LuminousHomeTheme.space12),
                  Expanded(
                    child: GroceryActionButton(
                      key: const ValueKey<String>('item_outdent'),
                      icon: Icons.subdirectory_arrow_left_rounded,
                      label: 'Unindent',
                      onTap: _canOutdent ? _outdent : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: LuminousHomeTheme.space16),
              Row(
                children: <Widget>[
                  GroceryIconButton(
                    key: const ValueKey<String>('item_delete'),
                    icon: Icons.delete_outline_rounded,
                    label: 'Delete item',
                    color: LuminousHomeTheme.danger,
                    onTap: _delete,
                  ),
                  const SizedBox(width: LuminousHomeTheme.space12),
                  Expanded(
                    child: GroceryActionButton(
                      icon: Icons.check_rounded,
                      label: 'Save item',
                      onTap: _canSave ? _save : null,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
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

class _Field extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;

  /// Inline validation message under the field, or null when valid.
  final String? errorText;

  const _Field({
    super.key,
    required this.controller,
    required this.label,
    required this.hint,
    this.keyboardType,
    this.textInputAction,
    this.onSubmitted,
    this.onChanged,
    this.errorText,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label.toUpperCase(),
          style: LuminousHomeTheme.caption.copyWith(
            color: LuminousHomeTheme.textMuted,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: LuminousHomeTheme.space4),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          textInputAction: textInputAction,
          onSubmitted: onSubmitted,
          onChanged: onChanged,
          style: LuminousHomeTheme.body.copyWith(
            color: LuminousHomeTheme.textPrimary,
          ),
          cursorColor: LuminousHomeTheme.groceryAccent,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: LuminousHomeTheme.body.copyWith(
              color: LuminousHomeTheme.textMuted,
            ),
            errorText: errorText,
            errorStyle: LuminousHomeTheme.caption.copyWith(
              color: LuminousHomeTheme.danger,
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(
                LuminousHomeTheme.controlRadius,
              ),
              borderSide: const BorderSide(color: LuminousHomeTheme.danger),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(
                LuminousHomeTheme.controlRadius,
              ),
              borderSide: const BorderSide(color: LuminousHomeTheme.danger),
            ),
            isDense: true,
            filled: true,
            fillColor: LuminousHomeTheme.glass,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: LuminousHomeTheme.space12,
              vertical: LuminousHomeTheme.space12,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(
                LuminousHomeTheme.controlRadius,
              ),
              borderSide: BorderSide(color: LuminousHomeTheme.hairline),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(
                LuminousHomeTheme.controlRadius,
              ),
              borderSide: const BorderSide(
                color: LuminousHomeTheme.groceryBright,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _AisleDropdown extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;

  const _AisleDropdown({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Aisle',
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
          child: DropdownButton<String>(
            value: value,
            isExpanded: true,
            dropdownColor: LuminousHomeTheme.glassOpaqueStrong,
            icon: const Icon(
              Icons.expand_more_rounded,
              color: LuminousHomeTheme.textMuted,
            ),
            style: LuminousHomeTheme.body.copyWith(
              color: LuminousHomeTheme.textPrimary,
            ),
            items: <DropdownMenuItem<String>>[
              for (final String aisle in groceryAisleOrder)
                DropdownMenuItem<String>(value: aisle, child: Text(aisle)),
            ],
            onChanged: (String? next) {
              if (next != null) onChanged(next);
            },
          ),
        ),
      ),
    );
  }
}

/// Presents [ItemEditSheet] as a modal bottom sheet.
Future<void> showItemEditSheet(
  BuildContext context, {
  required ShoppingController controller,
  required ShoppingList list,
  required ShoppingItem item,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: LuminousHomeTheme.lockScrim,
    builder: (BuildContext sheetContext) =>
        ItemEditSheet(controller: controller, list: list, item: item),
  );
}
