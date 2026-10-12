import 'package:flutter/material.dart';

import '../../../ui/theme/luminous_home_theme.dart';
import '../models/measurement_converter.dart';
import '../models/quantity.dart';
import '../models/shopping_item.dart';
import '../models/shopping_list.dart';
import '../models/unit.dart';
import '../shopping_controller.dart';
import 'grocery_chrome.dart';
import 'unit_chip_row.dart';

/// The inline editor Keep shows for a list row, as a bottom sheet.
///
/// It reuses [UnitChipRow] so the unit picker and Frozen toggle behave exactly
/// as they do on the quick-add capsule. Nothing is written directly: saving
/// calls [ShoppingController.updateItem], which keeps the debounced store save
/// the single source of truth.
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
  late bool _frozen = widget.item.aisle == 'Frozen';
  late String _aisle = widget.item.aisle;
  late String? _parentId = widget.item.parentId;

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Quantity? get _quantity {
    final double? amount = MeasurementConverter.parseAmount(_amount.text);
    if (amount == null && _unit == null) return null;
    return Quantity(amount ?? 1, _unit ?? Unit.piece);
  }

  void _indent() {
    widget.controller.indentItem(widget.list.id, widget.item.id);
    final ShoppingItem? updated =
        widget.controller.listById(widget.list.id)?.itemById(widget.item.id);
    setState(() => _parentId = updated?.parentId);
  }

  void _outdent() {
    widget.controller.outdentItem(widget.list.id, widget.item.id);
    setState(() => _parentId = null);
  }

  void _save() {
    final String name = _name.text.trim();
    if (name.isEmpty) return;
    final String note = _note.text.trim();
    widget.controller.updateItem(
      widget.list.id,
      ShoppingItem(
        id: widget.item.id,
        name: name,
        quantity: _quantity,
        aisle: _frozen ? 'Frozen' : _aisle,
        checked: widget.item.checked,
        note: note.isEmpty ? null : note,
        sourceRecipeId: widget.item.sourceRecipeId,
        parentId: _parentId,
      ),
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
                      hint: '1',
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
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
                          value: _frozen ? 'Frozen' : _aisle,
                          onChanged: (String value) => setState(() {
                            _aisle = value;
                            _frozen = value == 'Frozen';
                          }),
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
                frozen: _frozen,
                onUnitSelected: (Unit? unit) => setState(() => _unit = unit),
                onFrozenChanged: (bool value) =>
                    setState(() => _frozen = value),
              ),
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
                      onTap: widget.controller.canIndent(
                        widget.list.id,
                        widget.item.id,
                      )
                          ? _indent
                          : null,
                    ),
                  ),
                  const SizedBox(width: LuminousHomeTheme.space12),
                  Expanded(
                    child: GroceryActionButton(
                      key: const ValueKey<String>('item_outdent'),
                      icon: Icons.subdirectory_arrow_left_rounded,
                      label: 'Unindent',
                      onTap: widget.controller.canOutdent(
                        widget.list.id,
                        widget.item.id,
                      )
                          ? _outdent
                          : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: LuminousHomeTheme.space16),
              GroceryActionButton(
                icon: Icons.check_rounded,
                label: 'Save item',
                onTap: _save,
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

  const _Field({
    super.key,
    required this.controller,
    required this.label,
    required this.hint,
    this.keyboardType,
    this.textInputAction,
    this.onSubmitted,
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
          style: LuminousHomeTheme.body.copyWith(
            color: LuminousHomeTheme.textPrimary,
          ),
          cursorColor: LuminousHomeTheme.groceryAccent,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: LuminousHomeTheme.body.copyWith(
              color: LuminousHomeTheme.textMuted,
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
              borderSide: const BorderSide(color: LuminousHomeTheme.hairline),
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
