import 'package:flutter/material.dart';

import '../../../ui/theme/luminous_home_theme.dart';
import '../models/quantity.dart';
import '../models/unit.dart';
import '../parsing/ingredient_parser.dart';
import '../shopping_controller.dart';
import 'grocery_chrome.dart';
import 'unit_chip_row.dart';

/// The bottom capsule that turns a typed line into a list item.
///
/// It parses as you type so the quantity, unit and aisle are visible before the
/// commit, and it keeps focus after submit so a whole list can be dictated
/// without reaching for the field again. A chip row lets the unit be picked
/// explicitly and an item be marked Frozen; both override the parser.
class QuickAddCapsule extends StatefulWidget {
  final ShoppingController controller;

  const QuickAddCapsule({super.key, required this.controller});

  @override
  State<QuickAddCapsule> createState() => _QuickAddCapsuleState();
}

class _QuickAddCapsuleState extends State<QuickAddCapsule> {
  final TextEditingController _text = TextEditingController();
  final FocusNode _focus = FocusNode();

  Unit? _unit;
  bool _frozen = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocusChanged);
  }

  void _onFocusChanged() {
    if (mounted) setState(() {});
  }

  ParsedIngredient? get _parsed {
    final String raw = _text.text.trim();
    if (raw.isEmpty) return null;
    final ParsedIngredient parsed = const IngredientParser().parseLine(raw);
    return parsed.name.isEmpty ? null : parsed;
  }

  /// The quantity the item will get, once an explicit unit is applied.
  Quantity? get _effectiveQuantity {
    final ParsedIngredient? parsed = _parsed;
    if (parsed == null) return null;
    if (_unit == null) return parsed.quantity;
    return Quantity(parsed.quantity?.amount ?? 1, _unit!);
  }

  String get _aisle {
    final ParsedIngredient? parsed = _parsed;
    if (_frozen) return 'Frozen';
    return parsed?.aisle ?? 'Other';
  }

  bool get _showPicker => _focus.hasFocus || _text.text.trim().isNotEmpty;

  List<String> get _suggestions {
    final ParsedIngredient? parsed = _parsed;
    if (parsed == null) return const <String>[];
    return widget.controller.suggestionsFor(parsed.name);
  }

  void _applySuggestion(String suggestion) {
    final String text = _text.text;
    final ParsedIngredient? parsed = _parsed;
    if (parsed == null) {
      _text.text = suggestion;
    } else {
      final int index = text.lastIndexOf(parsed.name);
      _text.text = index < 0
          ? suggestion
          : text.replaceRange(index, index + parsed.name.length, suggestion);
    }
    _text.selection = TextSelection.collapsed(offset: _text.text.length);
    setState(() {});
    _focus.requestFocus();
  }

  void _submit() {
    final String raw = _text.text.trim();
    if (raw.isEmpty) return;
    final added = widget.controller.addParsed(
      line: raw,
      unitOverride: _unit,
      frozen: _frozen,
    );
    if (added == null) return;
    _text.clear();
    setState(() {
      _unit = null;
      _frozen = false;
    });
    _focus.requestFocus();
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocusChanged);
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ParsedIngredient? parsed = _parsed;
    final List<String> suggestions = _suggestions;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        LuminousHomeTheme.screenGutter,
        LuminousHomeTheme.space8,
        LuminousHomeTheme.screenGutter,
        LuminousHomeTheme.space12,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (suggestions.isNotEmpty) ...<Widget>[
            _SuggestionRow(
              suggestions: suggestions,
              onSelected: _applySuggestion,
            ),
            const SizedBox(height: LuminousHomeTheme.space8),
          ],
          if (parsed != null) ...<Widget>[
            _PreviewChip(
              quantity: _effectiveQuantity,
              name: parsed.name,
              aisle: _aisle,
              preferImperial: widget.controller.preferImperial,
            ),
            const SizedBox(height: LuminousHomeTheme.space8),
          ],
          if (_showPicker) ...<Widget>[
            UnitChipRow(
              selected: _unit,
              frozen: _frozen,
              onUnitSelected: (Unit? unit) => setState(() => _unit = unit),
              onFrozenChanged: (bool value) => setState(() => _frozen = value),
            ),
            const SizedBox(height: LuminousHomeTheme.space8),
          ],
          DecoratedBox(
            decoration: BoxDecoration(
              color: LuminousHomeTheme.glassOpaque,
              borderRadius: BorderRadius.circular(25),
              border: Border.all(color: LuminousHomeTheme.hairline),
              boxShadow: const <BoxShadow>[
                BoxShadow(
                  color: LuminousHomeTheme.groceryGlow,
                  blurRadius: 18,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 52),
              child: Row(
                children: <Widget>[
                  const Padding(
                    padding: EdgeInsets.only(
                      left: LuminousHomeTheme.space16,
                      right: LuminousHomeTheme.space8,
                    ),
                    child: Icon(
                      Icons.add_shopping_cart_rounded,
                      color: LuminousHomeTheme.groceryAccent,
                      size: 20,
                    ),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _text,
                      focusNode: _focus,
                      textInputAction: TextInputAction.done,
                      onChanged: (_) => setState(() {}),
                      onSubmitted: (_) => _submit(),
                      style: LuminousHomeTheme.body.copyWith(
                        color: LuminousHomeTheme.textPrimary,
                      ),
                      cursorColor: LuminousHomeTheme.groceryAccent,
                      decoration: InputDecoration(
                        hintText: 'Add an item…',
                        hintStyle: LuminousHomeTheme.body.copyWith(
                          color: LuminousHomeTheme.textMuted,
                        ),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: LuminousHomeTheme.space12,
                        ),
                      ),
                    ),
                  ),
                  GroceryIconButton(
                    icon: Icons.arrow_upward_rounded,
                    label: 'Add item',
                    color: LuminousHomeTheme.groceryAccent,
                    emphasized: parsed != null,
                    onTap: parsed == null ? null : _submit,
                  ),
                  const SizedBox(width: LuminousHomeTheme.space4),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SuggestionRow extends StatelessWidget {
  final List<String> suggestions;
  final ValueChanged<String> onSelected;

  const _SuggestionRow({required this.suggestions, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: LuminousHomeTheme.minimumTouchTarget,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: <Widget>[
          for (final String suggestion in suggestions)
            Padding(
              padding: const EdgeInsets.only(right: LuminousHomeTheme.space8),
              child: Semantics(
                button: true,
                label: 'Suggestion $suggestion',
                child: Tooltip(
                  message: suggestion,
                  child: Material(
                    color: LuminousHomeTheme.glass,
                    borderRadius: BorderRadius.circular(
                      LuminousHomeTheme.controlRadius,
                    ),
                    child: InkWell(
                      onTap: () => onSelected(suggestion),
                      borderRadius: BorderRadius.circular(
                        LuminousHomeTheme.controlRadius,
                      ),
                      child: Container(
                        constraints: const BoxConstraints(
                          minHeight: LuminousHomeTheme.minimumTouchTarget,
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: LuminousHomeTheme.space12,
                        ),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(
                            LuminousHomeTheme.controlRadius,
                          ),
                          border: Border.all(color: LuminousHomeTheme.hairline),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            const Icon(
                              Icons.history_rounded,
                              size: 15,
                              color: LuminousHomeTheme.textMuted,
                            ),
                            const SizedBox(width: LuminousHomeTheme.space4),
                            Text(
                              suggestion,
                              style: LuminousHomeTheme.label.copyWith(
                                color: LuminousHomeTheme.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _PreviewChip extends StatelessWidget {
  final Quantity? quantity;
  final String name;
  final String aisle;
  final bool preferImperial;

  const _PreviewChip({
    required this.quantity,
    required this.name,
    required this.aisle,
    required this.preferImperial,
  });

  @override
  Widget build(BuildContext context) {
    final String? quantityText = quantity?.format(
      preferImperial: preferImperial,
    );
    final double maxWidth =
        MediaQuery.sizeOf(context).width - LuminousHomeTheme.screenGutter * 2;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(maxWidth: maxWidth),
        padding: const EdgeInsets.symmetric(
          horizontal: LuminousHomeTheme.space12,
          vertical: LuminousHomeTheme.space8,
        ),
        decoration: BoxDecoration(
          color: LuminousHomeTheme.grocerySoft,
          borderRadius: BorderRadius.circular(LuminousHomeTheme.controlRadius),
          border: Border.all(color: LuminousHomeTheme.groceryBright),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(
              Icons.auto_awesome_rounded,
              size: 15,
              color: LuminousHomeTheme.groceryAccent,
            ),
            const SizedBox(width: LuminousHomeTheme.space8),
            Flexible(
              child: Text(
                <String>[?quantityText, name, '· $aisle'].join(' '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: LuminousHomeTheme.caption.copyWith(
                  color: LuminousHomeTheme.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
