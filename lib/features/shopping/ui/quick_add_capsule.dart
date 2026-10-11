import 'package:flutter/material.dart';

import '../../../ui/theme/luminous_home_theme.dart';
import '../parsing/ingredient_parser.dart';
import '../shopping_controller.dart';
import 'grocery_chrome.dart';

/// The bottom capsule that turns a typed line into a list item.
///
/// It parses as you type so the quantity, unit and aisle are visible before the
/// commit, and it keeps focus after submit so a whole list can be dictated
/// without reaching for the field again.
class QuickAddCapsule extends StatefulWidget {
  final ShoppingController controller;

  const QuickAddCapsule({super.key, required this.controller});

  @override
  State<QuickAddCapsule> createState() => _QuickAddCapsuleState();
}

class _QuickAddCapsuleState extends State<QuickAddCapsule> {
  final TextEditingController _text = TextEditingController();
  final FocusNode _focus = FocusNode();

  ParsedIngredient? get _parsed {
    final String raw = _text.text.trim();
    if (raw.isEmpty) return null;
    final ParsedIngredient parsed = const IngredientParser().parseLine(raw);
    return parsed.name.isEmpty ? null : parsed;
  }

  void _submit() {
    final String raw = _text.text.trim();
    if (raw.isEmpty) return;
    final added = widget.controller.quickAdd(raw);
    if (added == null) return;
    _text.clear();
    setState(() {});
    _focus.requestFocus();
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ParsedIngredient? parsed = _parsed;
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
          if (parsed != null) ...<Widget>[
            _PreviewChip(
              parsed: parsed,
              preferImperial: widget.controller.preferImperial,
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

class _PreviewChip extends StatelessWidget {
  final ParsedIngredient parsed;
  final bool preferImperial;

  const _PreviewChip({required this.parsed, required this.preferImperial});

  @override
  Widget build(BuildContext context) {
    final String? quantity = parsed.quantity?.format(
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
                <String>[
                  ?quantity,
                  parsed.name,
                  '· ${parsed.aisle}',
                ].join(' '),
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
