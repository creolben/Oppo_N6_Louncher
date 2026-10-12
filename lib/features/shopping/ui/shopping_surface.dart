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

  /// Drives the platform's keep-screen-on flag while store mode is active.
  ///
  /// Defaults to [LauncherBridge.setKeepScreenOn]. Injectable (and therefore a
  /// no-op on a test host) so a widget test can assert the request and release
  /// without touching a platform channel.
  final ValueChanged<bool>? onKeepScreenOn;

  const ShoppingSurface({
    super.key,
    required this.controller,
    required this.foldable,
    required this.onClose,
    this.pdfImportService,
    this.onKeepScreenOn,
  });

  @override
  State<ShoppingSurface> createState() => _ShoppingSurfaceState();
}

class _ShoppingSurfaceState extends State<ShoppingSurface> {
  String? _selectedRecipeId;

  /// Whether the folded-posture store-mode suggestion has been dismissed.
  bool _storeModeHintDismissed = false;

  /// Whether this surface currently holds the platform keep-screen-on flag.
  bool _keepScreenOnActive = false;

  Recipe? get _selectedRecipe {
    final String? id = _selectedRecipeId;
    if (id == null) return null;
    return widget.controller.recipeById(id);
  }

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
    _syncKeepScreenOn();
  }

  void _onControllerChanged() => _syncKeepScreenOn();

  /// Requests or releases the keep-screen-on flag so it tracks store mode.
  void _syncKeepScreenOn() {
    final bool shouldKeep = widget.controller.storeMode;
    if (shouldKeep == _keepScreenOnActive) return;
    _keepScreenOnActive = shouldKeep;
    (widget.onKeepScreenOn ?? LauncherBridge.setKeepScreenOn)(shouldKeep);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    // Never leave the screen pinned awake after the surface goes away.
    if (_keepScreenOnActive) {
      _keepScreenOnActive = false;
      (widget.onKeepScreenOn ?? LauncherBridge.setKeepScreenOn)(false);
    }
    super.dispose();
  }

  /// Whether the cover-display store-mode hint should be offered right now.
  bool get _showStoreHint =>
      !widget.controller.storeMode &&
      !_storeModeHintDismissed &&
      (widget.foldable.isFolded || widget.foldable.isOnCoverDisplay);

  /// Wraps a list view with the optional store-mode hint and (when asked) the
  /// store-aware quick-add capsule.
  Widget _buildListArea(Widget listView, {required bool showQuickAdd}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (_showStoreHint)
          _StoreModeHint(
            onEnable: () => widget.controller.setStoreMode(true),
            onDismiss: () => setState(() => _storeModeHintDismissed = true),
          ),
        Expanded(child: listView),
        if (showQuickAdd)
          _StoreQuickAdd(
            controller: widget.controller,
            storeMode: widget.controller.storeMode,
          ),
      ],
    );
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
                  : _buildListArea(
                      ListPane(controller: widget.controller, list: list),
                      showQuickAdd: false,
                    ),
        ),
        if (recipe == null)
          _StoreQuickAdd(
            controller: widget.controller,
            storeMode: widget.controller.storeMode,
          ),
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
              : _buildListArea(
                  list == null
                      ? const _NoListState()
                      : ListPane(controller: widget.controller, list: list),
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
                  : _buildListArea(
                      ListPane(controller: widget.controller, list: list),
                      showQuickAdd: false,
                    ),
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
                  _StoreQuickAdd(
                    controller: widget.controller,
                    storeMode: widget.controller.storeMode,
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// The quick-add capsule under store mode: collapsed to one large "Add item"
/// button until tapped, when it expands into the normal capsule.
class _StoreQuickAdd extends StatefulWidget {
  final ShoppingController controller;
  final bool storeMode;

  const _StoreQuickAdd({required this.controller, required this.storeMode});

  @override
  State<_StoreQuickAdd> createState() => _StoreQuickAddState();
}

class _StoreQuickAddState extends State<_StoreQuickAdd> {
  bool _expanded = false;

  @override
  void didUpdateWidget(covariant _StoreQuickAdd oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Entering or leaving store mode always starts collapsed again.
    if (oldWidget.storeMode != widget.storeMode) {
      _expanded = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.storeMode || _expanded) {
      return QuickAddCapsule(controller: widget.controller);
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        LuminousHomeTheme.screenGutter,
        LuminousHomeTheme.space8,
        LuminousHomeTheme.screenGutter,
        LuminousHomeTheme.space12,
      ),
      child: SizedBox(
        width: double.infinity,
        child: GroceryActionButton(
          key: const ValueKey<String>('store_add_item'),
          icon: Icons.add_rounded,
          label: 'Add item',
          onTap: () => setState(() => _expanded = true),
        ),
      ),
    );
  }
}

/// A dismissible suggestion, offered on the cover display, to enter store mode.
class _StoreModeHint extends StatelessWidget {
  final VoidCallback onEnable;
  final VoidCallback onDismiss;

  const _StoreModeHint({required this.onEnable, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    final BorderRadius radius = BorderRadius.circular(
      LuminousHomeTheme.controlRadius,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        LuminousHomeTheme.screenGutter,
        LuminousHomeTheme.space8,
        LuminousHomeTheme.screenGutter,
        0,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: LuminousHomeTheme.grocerySoft,
          borderRadius: radius,
          border: Border.all(color: LuminousHomeTheme.groceryBright),
        ),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Semantics(
                button: true,
                label: 'Turn on store mode',
                child: Material(
                  color: Colors.transparent,
                  borderRadius: radius,
                  child: InkWell(
                    onTap: onEnable,
                    borderRadius: radius,
                    child: Container(
                      constraints: const BoxConstraints(
                        minHeight: LuminousHomeTheme.minimumTouchTarget,
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: LuminousHomeTheme.space12,
                      ),
                      child: Row(
                        children: <Widget>[
                          const Icon(
                            Icons.storefront_rounded,
                            size: 18,
                            color: LuminousHomeTheme.groceryAccent,
                          ),
                          const SizedBox(width: LuminousHomeTheme.space8),
                          Flexible(
                            child: Text(
                              'Store mode',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: LuminousHomeTheme.label,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            GroceryIconButton(
              key: const ValueKey<String>('dismiss_store_hint'),
              icon: Icons.close_rounded,
              label: 'Dismiss store mode hint',
              color: LuminousHomeTheme.textMuted,
              onTap: onDismiss,
            ),
          ],
        ),
      ),
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

  /// The active list's name, falling back to the surface's own title.
  String get _listName => controller.activeList?.name ?? 'Shopping list';

  /// The screen-reader label for the list switcher.
  String get _switchListLabel {
    final ShoppingList? list = controller.activeList;
    final int total = list?.items.length ?? 0;
    final int done = list?.checkedCount ?? 0;
    return 'Switch list, current $_listName, $done of $total done';
  }

  static PopupMenuItem<String> _menuItem({
    required String value,
    required IconData icon,
    required String title,
    bool selected = false,
  }) {
    return PopupMenuItem<String>(
      value: value,
      child: ListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        leading: Icon(
          selected ? Icons.check_rounded : icon,
          color: selected
              ? LuminousHomeTheme.groceryAccent
              : LuminousHomeTheme.textSecondary,
        ),
        title: Text(title),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ShoppingList? list = controller.activeList;
    final ShoppingSortMode sortMode =
        list?.sortMode ?? ShoppingSortMode.byAisle;
    final bool storeMode = controller.storeMode;
    final int total = list?.items.length ?? 0;
    final int done = list?.checkedCount ?? 0;

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
              child: Semantics(
                container: true,
                button: true,
                excludeSemantics: true,
                label: _switchListLabel,
                onTap: onOpenNavigator,
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: onOpenNavigator,
                    borderRadius: BorderRadius.circular(
                      LuminousHomeTheme.controlRadius,
                    ),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        minHeight: LuminousHomeTheme.minimumTouchTarget,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: LuminousHomeTheme.space4,
                        ),
                        child: Row(
                          children: <Widget>[
                            Flexible(
                              child: Text(
                                _listName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: LuminousHomeTheme.title,
                              ),
                            ),
                            const SizedBox(width: 2),
                            const Icon(
                              Icons.expand_more_rounded,
                              size: 16,
                              color: LuminousHomeTheme.textMuted,
                            ),
                            if (total > 0) ...<Widget>[
                              const SizedBox(width: LuminousHomeTheme.space8),
                              Flexible(
                                child: Text(
                                  '$done of $total',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: LuminousHomeTheme.caption.copyWith(
                                    color: LuminousHomeTheme.textMuted,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (!storeMode)
              _UnitToggle(
                preferImperial: controller.preferImperial,
                onChanged: controller.setPreferImperial,
              ),
            if (storeMode)
              GroceryIconButton(
                key: const ValueKey<String>('exit_store_mode'),
                icon: Icons.storefront_rounded,
                label: 'Exit store mode',
                color: LuminousHomeTheme.groceryAccent,
                emphasized: true,
                onTap: () => controller.setStoreMode(false),
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
                } else if (value == 'sortByAisle') {
                  if (list != null) {
                    controller.setSortMode(list.id, ShoppingSortMode.byAisle);
                  }
                } else if (value == 'sortManual') {
                  if (list != null) {
                    controller.setSortMode(list.id, ShoppingSortMode.manual);
                  }
                } else if (value == 'storeMode') {
                  controller.setStoreMode(!controller.storeMode);
                } else if (value == 'uncheckAll') {
                  if (list != null && list.checkedCount > 0) {
                    controller.uncheckAll(list.id);
                    showGrocerySnackBar(context, 'All items unchecked');
                  }
                } else if (value == 'deleteChecked') {
                  if (list != null) {
                    clearCheckedWithUndo(context, controller, list);
                  }
                } else if (value == 'unitConverter') {
                  showUnitConverterSheet(context);
                }
              },
              itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                _menuItem(
                  value: 'navigator',
                  icon: Icons.list_alt_rounded,
                  title: 'Lists & recipes',
                ),
                _menuItem(
                  value: 'paste',
                  icon: Icons.content_paste_rounded,
                  title: 'Paste text',
                ),
                _menuItem(
                  value: 'importPdf',
                  icon: Icons.picture_as_pdf_rounded,
                  title: 'Import PDF',
                ),
                if (list != null) ...<PopupMenuEntry<String>>[
                  _menuItem(
                    value: 'sortByAisle',
                    icon: Icons.view_agenda_rounded,
                    title: 'Sort: By aisle',
                    selected: sortMode == ShoppingSortMode.byAisle,
                  ),
                  _menuItem(
                    value: 'sortManual',
                    icon: Icons.reorder_rounded,
                    title: 'Sort: My order',
                    selected: sortMode == ShoppingSortMode.manual,
                  ),
                ],
                _menuItem(
                  value: 'storeMode',
                  icon: Icons.storefront_rounded,
                  title: 'Store mode',
                  selected: storeMode,
                ),
                _menuItem(
                  value: 'uncheckAll',
                  icon: Icons.check_box_outline_blank_rounded,
                  title: 'Uncheck all items',
                ),
                _menuItem(
                  value: 'deleteChecked',
                  icon: Icons.delete_sweep_rounded,
                  title: 'Delete checked items',
                ),
                _menuItem(
                  value: 'unitConverter',
                  icon: Icons.straighten_rounded,
                  title: 'Unit converter',
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
