import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/foldable_controller.dart';
import '../../../core/launcher_bridge.dart';
import '../../../ui/theme/luminous_home_theme.dart';
import '../models/recipe.dart';
import '../models/shopping_list.dart';
import '../parsing/document_parser.dart';
import '../parsing/pdf_text_import.dart';
import '../shopping_controller.dart';
import 'grocery_chrome.dart';
import 'import_review_sheet.dart';
import 'list_pane.dart';
import 'lists_pane.dart';
import 'quick_add_capsule.dart';
import 'recipe_pane.dart';
import 'unit_converter_sheet.dart';

/// The full-screen shopping surface.
///
/// A sibling of [CometSearchSurface]: the same blurred scrim, the same 50px
/// capsule at 25px radius, so opening it feels like turning to another page of
/// the launcher rather than launching a separate app.
class ShoppingSurface extends StatefulWidget {
  final ShoppingController controller;
  final FoldableController foldable;
  final VoidCallback onClose;

  /// The PDF importer used by the overflow's "Import PDF" action. Null in
  /// production, where the surface builds one from the platform bridge;
  /// injectable so the picker-to-review flow can be exercised without a device.
  final PdfImportService? pdfImportService;

  const ShoppingSurface({
    super.key,
    required this.controller,
    required this.foldable,
    required this.onClose,
    this.pdfImportService,
  });

  @override
  State<ShoppingSurface> createState() => _ShoppingSurfaceState();
}

class _ShoppingSurfaceState extends State<ShoppingSurface> {
  String? _selectedRecipeId;

  Recipe? get _selectedRecipe {
    final String? id = _selectedRecipeId;
    if (id == null) return null;
    return widget.controller.recipeById(id);
  }

  Future<void> _openNavigatorSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: LuminousHomeTheme.lockScrim,
      builder: (BuildContext sheetContext) {
        return SafeArea(
          top: false,
          child: Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.72,
            ),
            decoration: BoxDecoration(
              color: LuminousHomeTheme.glassOpaqueStrong,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(LuminousHomeTheme.cardRadius),
              ),
              border: Border.all(color: LuminousHomeTheme.hairline),
            ),
            child: ListsPane(
              controller: widget.controller,
              selectedRecipeId: _selectedRecipeId,
              onSelectRecipe: (String id) {
                setState(() => _selectedRecipeId = id);
                Navigator.of(sheetContext).pop();
              },
              onSelectList: (_) {
                setState(() => _selectedRecipeId = null);
                Navigator.of(sheetContext).pop();
              },
            ),
          ),
        );
      },
    );
  }

  Future<void> _pasteText() async {
    final ClipboardData? data = await Clipboard.getData(Clipboard.kTextPlain);
    final String text = data?.text ?? '';
    if (!mounted) return;
    if (text.trim().isEmpty) {
      showGrocerySnackBar(context, 'Nothing to paste');
      return;
    }
    final document = const DocumentParser().parseDocument(text);
    if (document.isEmpty) {
      showGrocerySnackBar(context, 'No list items found in the clipboard');
      return;
    }
    await showImportReviewSheet(
      context,
      document: document,
      onConfirm: (List<int> indices) =>
          widget.controller.importParsedDocument(document, indices),
    );
  }

  /// Picks a PDF, extracts its text layer on-device, and opens the same review
  /// sheet the paste route uses. Every non-cancel failure is surfaced rather
  /// than swallowed, so a scanned PDF says why it did not import.
  Future<void> _importPdf() async {
    final PdfImportService service = widget.pdfImportService ??
        PdfImportService(
          extract: LauncherBridge.extractPdfText,
          pick: LauncherBridge.pickPdf,
        );
    final PdfImportResult result = await service.importFromPicker();
    if (!mounted) return;
    if (!result.isSuccess) {
      if (result.error == PdfImportErrorKind.cancelled) return;
      showGrocerySnackBar(context, result.message ?? 'This PDF could not be read.');
      return;
    }
    final ParsedDocument document = result.document!;
    if (document.isEmpty) {
      showGrocerySnackBar(context, 'No list items found in this PDF');
      return;
    }
    await showImportReviewSheet(
      context,
      document: document,
      onConfirm: (List<int> indices) =>
          widget.controller.importParsedDocument(document, indices),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 20.0, sigmaY: 20.0),
      child: Container(
        color: LuminousHomeTheme.scrim,
        child: SafeArea(
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              return ListenableBuilder(
                listenable: widget.controller,
                builder: (BuildContext context, Widget? _) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      _ShoppingCapsule(
                        controller: widget.controller,
                        onClose: widget.onClose,
                        onOpenNavigator: _openNavigatorSheet,
                        onPasteText: _pasteText,
                        onImportPdf: _importPdf,
                      ),
                      Expanded(child: _buildBody(constraints)),
                    ],
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildBody(BoxConstraints constraints) {
    if (widget.foldable.isTabletop) {
      return _buildTabletop();
    }
    final bool wide =
        constraints.maxWidth >= 600 && !widget.foldable.isFolded;
    if (wide) return _buildWide();
    return _buildNarrow();
  }

  Widget _buildNarrow() {
    final Recipe? recipe = _selectedRecipe;
    final ShoppingList? list = widget.controller.activeList;
    return Column(
      key: const ValueKey<String>('shopping_narrow'),
      children: <Widget>[
        Expanded(
          child: recipe != null
              ? RecipePane(
                  controller: widget.controller,
                  recipe: recipe,
                  onClose: () => setState(() => _selectedRecipeId = null),
                )
              : list == null
                  ? const _NoListState()
                  : ListPane(controller: widget.controller, list: list),
        ),
        if (recipe == null) QuickAddCapsule(controller: widget.controller),
      ],
    );
  }

  Widget _buildWide() {
    final Recipe? recipe = _selectedRecipe;
    final ShoppingList? list = widget.controller.activeList;
    return Row(
      key: const ValueKey<String>('shopping_wide'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SizedBox(
          width: 300,
          child: ListsPane(
            controller: widget.controller,
            selectedRecipeId: _selectedRecipeId,
            onSelectRecipe: (String id) =>
                setState(() => _selectedRecipeId = id),
            onSelectList: (_) => setState(() => _selectedRecipeId = null),
          ),
        ),
        const VerticalDivider(
          width: 1,
          thickness: 1,
          color: LuminousHomeTheme.hairline,
        ),
        Expanded(
          child: recipe != null
              ? RecipePane(
                  controller: widget.controller,
                  recipe: recipe,
                  onClose: () => setState(() => _selectedRecipeId = null),
                )
              : _ListColumn(
                  controller: widget.controller,
                  list: list,
                  showQuickAdd: true,
                ),
        ),
      ],
    );
  }

  Widget _buildTabletop() {
    final ShoppingList? list = widget.controller.activeList;
    final Recipe? recipe = _selectedRecipe ??
        (widget.controller.recipes.isEmpty
            ? null
            : widget.controller.recipes.first);

    // Split the *body* (below the capsule), not the whole safe area, so the
    // two halves really meet at the middle when the platform reports no hinge
    // geometry.
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double total = constraints.maxHeight;
        final double half = total / 2;
        double topHeight = half;
        final Rect? crease = widget.foldable.creaseBounds;
        if (crease != null && crease.top >= 120 && crease.top <= total - 120) {
          topHeight = crease.top;
        }

        return Column(
          key: const ValueKey<String>('shopping_tabletop'),
          children: <Widget>[
            SizedBox(
              height: topHeight,
              child: list == null
                  ? const _NoListState()
                  : ListPane(controller: widget.controller, list: list),
            ),
            Container(height: 1, color: LuminousHomeTheme.groceryGlow),
            Expanded(
              child: Column(
                children: <Widget>[
                  if (recipe != null)
                    Expanded(
                      child: RecipePane(
                        controller: widget.controller,
                        recipe: recipe,
                        compact: true,
                      ),
                    ),
                  QuickAddCapsule(controller: widget.controller),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ListColumn extends StatelessWidget {
  final ShoppingController controller;
  final ShoppingList? list;
  final bool showQuickAdd;

  const _ListColumn({
    required this.controller,
    required this.list,
    required this.showQuickAdd,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Expanded(
          child: list == null
              ? const _NoListState()
              : ListPane(controller: controller, list: list!),
        ),
        if (showQuickAdd) QuickAddCapsule(controller: controller),
      ],
    );
  }
}

class _NoListState extends StatelessWidget {
  const _NoListState();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        LuminousHomeTheme.screenGutter,
        64,
        LuminousHomeTheme.screenGutter,
        96,
      ),
      children: <Widget>[
        const Icon(
          Icons.shopping_cart_rounded,
          size: 48,
          color: LuminousHomeTheme.groceryAccent,
        ),
        const SizedBox(height: LuminousHomeTheme.space16),
        Text(
          'No list yet',
          textAlign: TextAlign.center,
          style: LuminousHomeTheme.title,
        ),
        const SizedBox(height: LuminousHomeTheme.space8),
        Text(
          'Type an item below and a Groceries list is created for you.',
          textAlign: TextAlign.center,
          style: LuminousHomeTheme.body.copyWith(
            color: LuminousHomeTheme.textMuted,
          ),
        ),
      ],
    );
  }
}

class _ShoppingCapsule extends StatelessWidget {
  final ShoppingController controller;
  final VoidCallback onClose;
  final VoidCallback onOpenNavigator;
  final VoidCallback onPasteText;
  final VoidCallback onImportPdf;

  const _ShoppingCapsule({
    required this.controller,
    required this.onClose,
    required this.onOpenNavigator,
    required this.onPasteText,
    required this.onImportPdf,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        LuminousHomeTheme.space16,
        LuminousHomeTheme.space12,
        LuminousHomeTheme.space16,
        LuminousHomeTheme.space8,
      ),
      child: Container(
        height: 50,
        decoration: BoxDecoration(
          color: LuminousHomeTheme.glassOpaque,
          borderRadius: BorderRadius.circular(25),
          border: Border.all(
            color: LuminousHomeTheme.groceryBright,
            width: 1.2,
          ),
          boxShadow: const <BoxShadow>[
            BoxShadow(
              color: LuminousHomeTheme.groceryGlow,
              blurRadius: 18,
              spreadRadius: 1,
            ),
          ],
        ),
        child: Row(
          children: <Widget>[
            const Padding(
              padding: EdgeInsets.only(
                left: LuminousHomeTheme.space16,
                right: LuminousHomeTheme.space8,
              ),
              child: Icon(
                Icons.shopping_cart_rounded,
                color: LuminousHomeTheme.groceryAccent,
                size: 20,
              ),
            ),
            Expanded(
              child: Text(
                'Shopping list',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: LuminousHomeTheme.title,
              ),
            ),
            _UnitToggle(
              preferImperial: controller.preferImperial,
              onChanged: controller.setPreferImperial,
            ),
            PopupMenuButton<String>(
              tooltip: 'Shopping options',
              icon: const Icon(
                Icons.more_vert_rounded,
                color: LuminousHomeTheme.textSecondary,
                size: 20,
              ),
              onSelected: (String value) {
                if (value == 'navigator') {
                  onOpenNavigator();
                } else if (value == 'paste') {
                  onPasteText();
                } else if (value == 'importPdf') {
                  onImportPdf();
                } else if (value == 'uncheckAll') {
                  final ShoppingList? list = controller.activeList;
                  if (list != null && list.checkedCount > 0) {
                    controller.uncheckAll(list.id);
                    showGrocerySnackBar(context, 'All items unchecked');
                  }
                } else if (value == 'deleteChecked') {
                  final ShoppingList? list = controller.activeList;
                  if (list != null) {
                    clearCheckedWithUndo(context, controller, list);
                  }
                } else if (value == 'unitConverter') {
                  showUnitConverterSheet(context);
                }
              },
              itemBuilder: (BuildContext context) =>
                  const <PopupMenuEntry<String>>[
                PopupMenuItem<String>(
                  value: 'navigator',
                  child: ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.list_alt_rounded),
                    title: Text('Lists & recipes'),
                  ),
                ),
                PopupMenuItem<String>(
                  value: 'paste',
                  child: ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.content_paste_rounded),
                    title: Text('Paste text'),
                  ),
                ),
                PopupMenuItem<String>(
                  value: 'importPdf',
                  child: ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.picture_as_pdf_rounded),
                    title: Text('Import PDF'),
                  ),
                ),
                PopupMenuItem<String>(
                  value: 'uncheckAll',
                  child: ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.check_box_outline_blank_rounded),
                    title: Text('Uncheck all items'),
                  ),
                ),
                PopupMenuItem<String>(
                  value: 'deleteChecked',
                  child: ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.delete_sweep_rounded),
                    title: Text('Delete checked items'),
                  ),
                ),
                PopupMenuItem<String>(
                  value: 'unitConverter',
                  child: ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.straighten_rounded),
                    title: Text('Unit converter'),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(right: LuminousHomeTheme.space4),
              child: GroceryIconButton(
                icon: Icons.close_rounded,
                label: 'Close shopping list',
                color: LuminousHomeTheme.textPrimary,
                onTap: onClose,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UnitToggle extends StatelessWidget {
  final bool preferImperial;
  final ValueChanged<bool> onChanged;

  const _UnitToggle({required this.preferImperial, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: 'Units',
      child: Container(
        decoration: BoxDecoration(
          color: LuminousHomeTheme.glass,
          borderRadius: BorderRadius.circular(LuminousHomeTheme.controlRadius),
          border: Border.all(color: LuminousHomeTheme.hairline),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            _UnitSegment(
              label: 'kg',
              semanticLabel: 'Metric units',
              selected: !preferImperial,
              onTap: () => onChanged(false),
            ),
            _UnitSegment(
              label: 'lb',
              semanticLabel: 'Imperial units',
              selected: preferImperial,
              onTap: () => onChanged(true),
            ),
          ],
        ),
      ),
    );
  }
}

class _UnitSegment extends StatelessWidget {
  final String label;
  final String semanticLabel;
  final bool selected;
  final VoidCallback onTap;

  const _UnitSegment({
    required this.label,
    required this.semanticLabel,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final BorderRadius radius = BorderRadius.circular(
      LuminousHomeTheme.controlRadius - 2,
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
              : Colors.transparent,
          borderRadius: radius,
          child: InkWell(
            onTap: onTap,
            borderRadius: radius,
            child: SizedBox(
              width: 42,
              height: LuminousHomeTheme.minimumTouchTarget,
              child: Center(
                child: Text(
                  label,
                  style: LuminousHomeTheme.label.copyWith(
                    color: selected
                        ? LuminousHomeTheme.groceryAccent
                        : LuminousHomeTheme.textMuted,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
