import 'package:flutter/material.dart';

import '../../../ui/theme/luminous_home_theme.dart';
import '../parsing/document_parser.dart';
import '../parsing/ingredient_parser.dart';
import 'grocery_chrome.dart';

/// Reviews a [ParsedDocument] before it is committed to a list.
///
/// Every parsed line starts selected; the user can drop the ones they do not
/// want and confirm. It takes no controller, only an [onConfirm] callback, so
/// it is reachable from any import path — the clipboard paste today, a PDF
/// extractor later.
class ImportReviewSheet extends StatefulWidget {
  final ParsedDocument document;
  final void Function(List<int> selectedIndices) onConfirm;

  /// Which system the muted approximation beside each amount uses.
  final bool preferImperial;

  const ImportReviewSheet({
    super.key,
    required this.document,
    required this.onConfirm,
    this.preferImperial = false,
  });

  @override
  State<ImportReviewSheet> createState() => _ImportReviewSheetState();
}

class _ImportReviewSheetState extends State<ImportReviewSheet> {
  late final List<bool> _selected = List<bool>.filled(
    widget.document.items.length,
    true,
  );

  int get _selectedCount =>
      _selected.where((bool selected) => selected).length;

  List<int> get _selectedIndices => <int>[
        for (int i = 0; i < _selected.length; i++)
          if (_selected[i]) i,
      ];

  void _setAll(bool value) {
    setState(() => _selected.fillRange(0, _selected.length, value));
  }

  void _confirm() {
    final List<int> indices = _selectedIndices;
    if (indices.isEmpty) return;
    widget.onConfirm(indices);
    if (mounted && Navigator.canPop(context)) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final ParsedDocument document = widget.document;
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: LuminousHomeTheme.hairlineStrong,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: LuminousHomeTheme.space12),
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    'Review import',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: LuminousHomeTheme.title,
                  ),
                ),
                GroceryIconButton(
                  icon: Icons.close_rounded,
                  label: 'Close import review',
                  onTap: () => Navigator.of(context).maybePop(),
                ),
              ],
            ),
            Text(
              _summary(document),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: LuminousHomeTheme.caption.copyWith(
                color: LuminousHomeTheme.textMuted,
              ),
            ),
            const SizedBox(height: LuminousHomeTheme.space8),
            Wrap(
              spacing: LuminousHomeTheme.space8,
              children: <Widget>[
                TextButton(
                  onPressed: () => _setAll(true),
                  style: TextButton.styleFrom(
                    foregroundColor: LuminousHomeTheme.groceryAccent,
                    minimumSize: const Size(
                      LuminousHomeTheme.minimumTouchTarget,
                      LuminousHomeTheme.minimumTouchTarget,
                    ),
                  ),
                  child: const Text('Select all'),
                ),
                TextButton(
                  onPressed: () => _setAll(false),
                  style: TextButton.styleFrom(
                    foregroundColor: LuminousHomeTheme.textSecondary,
                    minimumSize: const Size(
                      LuminousHomeTheme.minimumTouchTarget,
                      LuminousHomeTheme.minimumTouchTarget,
                    ),
                  ),
                  child: const Text('Select none'),
                ),
              ],
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: document.items.length,
                itemBuilder: (BuildContext context, int index) {
                  return _ImportRow(
                    ingredient: document.items[index],
                    preferImperial: widget.preferImperial,
                    selected: _selected[index],
                    onTap: () => setState(
                      () => _selected[index] = !_selected[index],
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: LuminousHomeTheme.space12),
            GroceryActionButton(
              icon: Icons.download_rounded,
              label: document.isRecipe
                  ? 'Save recipe'
                  : _selectedCount == 1
                      ? 'Import 1 item'
                      : 'Import $_selectedCount items',
              onTap: _selectedCount == 0 ? null : _confirm,
            ),
          ],
        ),
      ),
    );
  }

  static String _summary(ParsedDocument document) {
    final int count = document.items.length;
    final String lines = count == 1 ? '1 line detected' : '$count lines detected';
    if (document.isRecipe) {
      final String title = document.title ?? 'Recipe';
      final String servings = document.servings == null
          ? ''
          : ' · serves ${document.servings}';
      return '$title$servings · $lines';
    }
    return 'List · $lines';
  }
}

class _ImportRow extends StatelessWidget {
  final ParsedIngredient ingredient;
  final bool preferImperial;
  final bool selected;
  final VoidCallback onTap;

  const _ImportRow({
    required this.ingredient,
    required this.preferImperial,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // As entered, like a list row, with the other system as a muted aside.
    final String quantity = ingredient.quantity?.formatAsEntered() ?? '';
    final String? approx =
        ingredient.quantity?.approxIn(preferImperial: preferImperial);
    return Semantics(
      container: true,
      button: true,
      selected: selected,
      label: <String>[
        if (quantity.isNotEmpty) quantity,
        ingredient.name,
      ].join(' '),
      onTap: onTap,
      child: ExcludeSemantics(
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(
              LuminousHomeTheme.controlRadius,
            ),
            child: Container(
              constraints: const BoxConstraints(
                minHeight: LuminousHomeTheme.minimumTouchTarget,
              ),
              padding: const EdgeInsets.symmetric(
                vertical: LuminousHomeTheme.space4,
              ),
              child: Row(
                children: <Widget>[
                  Icon(
                    selected
                        ? Icons.check_box_rounded
                        : Icons.check_box_outline_blank_rounded,
                    size: 22,
                    color: selected
                        ? LuminousHomeTheme.groceryAccent
                        : LuminousHomeTheme.textMuted,
                  ),
                  const SizedBox(width: LuminousHomeTheme.space12),
                  Expanded(
                    child: Text(
                      ingredient.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: LuminousHomeTheme.body.copyWith(
                        color: LuminousHomeTheme.textPrimary,
                      ),
                    ),
                  ),
                  if (quantity.isNotEmpty) ...<Widget>[
                    const SizedBox(width: LuminousHomeTheme.space12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          quantity,
                          style: LuminousHomeTheme.caption.copyWith(
                            color: LuminousHomeTheme.groceryAccent,
                          ),
                        ),
                        if (approx != null)
                          Text(
                            approx,
                            style: LuminousHomeTheme.caption.copyWith(
                              color: LuminousHomeTheme.textMuted,
                            ),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Presents [ImportReviewSheet] as a modal sheet.
Future<void> showImportReviewSheet(
  BuildContext context, {
  required ParsedDocument document,
  required void Function(List<int> selectedIndices) onConfirm,
  bool preferImperial = false,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: LuminousHomeTheme.lockScrim,
    builder: (BuildContext sheetContext) => ImportReviewSheet(
      document: document,
      onConfirm: onConfirm,
      preferImperial: preferImperial,
    ),
  );
}
