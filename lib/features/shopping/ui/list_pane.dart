import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../../../ui/theme/luminous_home_theme.dart';
import '../models/quantity.dart';
import '../models/shopping_item.dart';
import '../models/shopping_list.dart';
import '../models/unit.dart';
import '../shopping_controller.dart';
import 'grocery_chrome.dart';
import 'item_edit_sheet.dart';
import 'unit_converter_sheet.dart';

/// Left inset applied to an indented child row, matching Keep's sub-items.
const double _childIndent = 32;

/// Clears the checked items on [list] and offers an undo snackbar.
///
/// Shared by the Done header and the surface overflow so both paths restore the
/// removed items through the controller.
void clearCheckedWithUndo(
  BuildContext context,
  ShoppingController controller,
  ShoppingList list,
) {
  final List<ShoppingItem> removed = controller.clearChecked(list.id);
  if (removed.isEmpty) return;
  showGrocerySnackBar(
    context,
    removed.length == 1
        ? 'Deleted 1 checked item'
        : 'Deleted ${removed.length} checked items',
    actionLabel: 'Undo',
    onAction: () => controller.restoreItems(list.id, removed),
  );
}

/// The active shopping list, grouped into sticky aisle sections with a Done
/// section sinking the checked items to the bottom.
///
/// Unchecked rows are reorderable within their aisle; indented children render
/// directly under their parent. The pane is a plain view over [controller];
/// every mutation goes back through the controller so the debounced save and the
/// store stay the single source of truth.
class ListPane extends StatelessWidget {
  final ShoppingController controller;
  final ShoppingList list;

  const ListPane({super.key, required this.controller, required this.list});

  @override
  Widget build(BuildContext context) {
    if (list.items.isEmpty) {
      return _EmptyListState(listName: list.name);
    }

    final bool reduceMotion = MediaQuery.disableAnimationsOf(context);
    final List<ShoppingItem> unchecked = list.items
        .where((ShoppingItem item) => !item.checked)
        .toList();
    final List<ShoppingItem> checked = list.items
        .where((ShoppingItem item) => item.checked)
        .toList();

    // Children of unchecked, top-level parents, in list order.
    final Map<String, ShoppingItem> uncheckedById = <String, ShoppingItem>{
      for (final ShoppingItem item in unchecked) item.id: item,
    };
    bool isTopLevel(ShoppingItem item) {
      final String? parentId = item.parentId;
      if (parentId == null) return true;
      final ShoppingItem? parent = uncheckedById[parentId];
      // A child whose parent is checked, missing, or itself indented becomes a
      // top-level row so it is never lost.
      return parent == null || parent.parentId != null;
    }

    final List<ShoppingItem> topLevel =
        unchecked.where(isTopLevel).toList(growable: false);
    final Set<String> topLevelIds =
        topLevel.map((ShoppingItem item) => item.id).toSet();
    final Map<String, List<ShoppingItem>> childrenByParent =
        <String, List<ShoppingItem>>{};
    for (final ShoppingItem item in unchecked) {
      final String? parentId = item.parentId;
      if (parentId != null && topLevelIds.contains(parentId)) {
        childrenByParent.putIfAbsent(parentId, () => <ShoppingItem>[]).add(item);
      }
    }

    final Map<String, List<ShoppingItem>> grouped =
        <String, List<ShoppingItem>>{};
    for (final ShoppingItem item in topLevel) {
      grouped.putIfAbsent(item.aisle, () => <ShoppingItem>[]).add(item);
    }
    final List<String> aisles = grouped.keys.toList()
      ..sort(
        (String a, String b) =>
            groceryAisleRank(a).compareTo(groceryAisleRank(b)),
      );

    return CustomScrollView(
      slivers: <Widget>[
        for (final String aisle in aisles) ...<Widget>[
          SliverPersistentHeader(
            pinned: true,
            delegate: _AisleHeaderDelegate(
              aisle: aisle,
              count: grouped[aisle]!.length,
              height: _headerHeight(context),
            ),
          ),
          SliverReorderableList(
            itemCount: grouped[aisle]!.length,
            proxyDecorator: (Widget child, int index, Animation<double> animation) =>
                _proxy(child, reduceMotion),
            onReorder: (int oldIndex, int newIndex) {
              if (newIndex > oldIndex) newIndex -= 1;
              controller.moveItem(
                list.id,
                grouped[aisle]![oldIndex].id,
                newIndex,
              );
            },
            itemBuilder: (BuildContext context, int index) {
              final ShoppingItem parent = grouped[aisle]![index];
              return KeyedSubtree(
                key: ValueKey<String>('reorder_${parent.id}'),
                child: _AisleItem(
                  controller: controller,
                  list: list,
                  parent: parent,
                  children: childrenByParent[parent.id] ?? const <ShoppingItem>[],
                  reorderIndex: index,
                ),
              );
            },
          ),
        ],
        if (checked.isNotEmpty) ...<Widget>[
          SliverToBoxAdapter(
            child: _DoneHeader(
              count: checked.length,
              collapsed: list.checkedCollapsed,
              onToggle: () => controller.setCheckedCollapsed(
                list.id,
                !list.checkedCollapsed,
              ),
              onClear: () => clearCheckedWithUndo(context, controller, list),
            ),
          ),
          if (!list.checkedCollapsed)
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (BuildContext context, int index) => _ItemRow(
                  key: ValueKey<String>('row_${checked[index].id}'),
                  controller: controller,
                  list: list,
                  item: checked[index],
                ),
                childCount: checked.length,
              ),
            ),
        ],
        const SliverToBoxAdapter(
          child: SizedBox(height: LuminousHomeTheme.space24),
        ),
      ],
    );
  }

  /// The lift applied to a row while it is being dragged.
  static Widget _proxy(Widget child, bool reduceMotion) {
    if (reduceMotion) return child;
    return Material(
      color: LuminousHomeTheme.glassOpaqueStrong,
      borderRadius: BorderRadius.circular(LuminousHomeTheme.controlRadius),
      elevation: 4,
      child: child,
    );
  }
}

/// One aisle reorderable unit: a parent row and its indented children.
class _AisleItem extends StatelessWidget {
  final ShoppingController controller;
  final ShoppingList list;
  final ShoppingItem parent;
  final List<ShoppingItem> children;
  final int reorderIndex;

  const _AisleItem({
    required this.controller,
    required this.list,
    required this.parent,
    required this.children,
    required this.reorderIndex,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _ItemRow(
          key: ValueKey<String>('row_${parent.id}'),
          controller: controller,
          list: list,
          item: parent,
          reorderIndex: reorderIndex,
        ),
        for (final ShoppingItem child in children)
          _ItemRow(
            key: ValueKey<String>('row_${child.id}'),
            controller: controller,
            list: list,
            item: child,
            indented: true,
          ),
      ],
    );
  }
}

class _DoneHeader extends StatelessWidget {
  final int count;
  final bool collapsed;
  final VoidCallback onToggle;
  final VoidCallback onClear;

  const _DoneHeader({
    required this.count,
    required this.collapsed,
    required this.onToggle,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final double base = _headerHeight(context);
    final double headerHeight = base < LuminousHomeTheme.minimumTouchTarget
        ? LuminousHomeTheme.minimumTouchTarget
        : base;
    final String label = count == 1
        ? '+ 1 checked item'
        : '+ $count checked items';
    return Container(
      height: headerHeight,
      padding: const EdgeInsets.only(
        left: LuminousHomeTheme.space12,
        right: LuminousHomeTheme.screenGutter,
      ),
      decoration: const BoxDecoration(
        color: LuminousHomeTheme.glassOpaqueStrong,
        border: Border(bottom: BorderSide(color: LuminousHomeTheme.hairline)),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Semantics(
              button: true,
              label: collapsed
                  ? 'Expand checked items'
                  : 'Collapse checked items',
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: onToggle,
                  borderRadius: BorderRadius.circular(
                    LuminousHomeTheme.controlRadius,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: LuminousHomeTheme.space8,
                    ),
                    child: Row(
                      children: <Widget>[
                        Icon(
                          collapsed
                              ? Icons.chevron_right_rounded
                              : Icons.expand_more_rounded,
                          size: 20,
                          color: LuminousHomeTheme.textMuted,
                        ),
                        const SizedBox(width: LuminousHomeTheme.space4),
                        Flexible(
                          child: Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: LuminousHomeTheme.label.copyWith(
                              color: LuminousHomeTheme.textMuted,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          TextButton(
            onPressed: onClear,
            style: TextButton.styleFrom(
              foregroundColor: LuminousHomeTheme.groceryAccent,
              minimumSize: const Size(
                LuminousHomeTheme.minimumTouchTarget,
                LuminousHomeTheme.minimumTouchTarget,
              ),
              padding: const EdgeInsets.symmetric(
                horizontal: LuminousHomeTheme.space12,
              ),
            ),
            child: const Text('Clear checked'),
          ),
        ],
      ),
    );
  }
}

class _ItemRow extends StatelessWidget {
  final ShoppingController controller;
  final ShoppingList list;
  final ShoppingItem item;

  /// Whether this row is an indented child of the row above it.
  final bool indented;

  /// The reorderable index within the aisle, or null for non-reorderable rows
  /// such as the Done section.
  final int? reorderIndex;

  const _ItemRow({
    super.key,
    required this.controller,
    required this.list,
    required this.item,
    this.indented = false,
    this.reorderIndex,
  });

  String get _quantityText =>
      item.quantity?.format(preferImperial: controller.preferImperial) ?? '';

  bool get _convertible {
    final Dimension? dimension = item.quantity?.unit.dimension;
    return dimension == Dimension.mass || dimension == Dimension.volume;
  }

  String get _semanticLabel {
    final String name = _quantityText.isEmpty
        ? item.name
        : '$_quantityText ${item.name}';
    return '$name, ${item.checked ? 'checked' : 'unchecked'}';
  }

  void _toggle() {
    controller.toggleChecked(list.id, item.id);
  }

  void _edit(BuildContext context) {
    showItemEditSheet(context, controller: controller, list: list, item: item);
  }

  void _openConverter(BuildContext context) {
    final Quantity? quantity = item.quantity;
    if (quantity == null) return;
    showUnitConverterSheet(context, initial: quantity);
  }

  void _delete(BuildContext context) {
    controller.removeItem(list.id, item.id);
    showGrocerySnackBar(
      context,
      'Removed ${item.name}',
      actionLabel: 'Undo',
      onAction: () => controller.addItem(list.id, item),
    );
  }

  Map<CustomSemanticsAction, VoidCallback> _customActions() {
    if (item.checked) return const <CustomSemanticsAction, VoidCallback>{};
    return <CustomSemanticsAction, VoidCallback>{
      if (controller.canIndent(list.id, item.id))
        const CustomSemanticsAction(label: 'Indent'): () =>
            controller.indentItem(list.id, item.id),
      if (controller.canOutdent(list.id, item.id))
        const CustomSemanticsAction(label: 'Unindent'): () =>
            controller.outdentItem(list.id, item.id),
      if (controller.canMoveUp(list.id, item.id))
        const CustomSemanticsAction(label: 'Move up'): () =>
            controller.moveItemUp(list.id, item.id),
      if (controller.canMoveDown(list.id, item.id))
        const CustomSemanticsAction(label: 'Move down'): () =>
            controller.moveItemDown(list.id, item.id),
    };
  }

  @override
  Widget build(BuildContext context) {
    final bool reduceMotion = MediaQuery.disableAnimationsOf(context);
    final Duration duration = reduceMotion
        ? Duration.zero
        : LuminousHomeTheme.motionShort;

    final Widget content = AnimatedOpacity(
      opacity: item.checked ? 0.55 : 1.0,
      duration: duration,
      curve: LuminousHomeTheme.easeStandard,
      child: Container(
        key: ValueKey<String>('row_content_${item.id}'),
        constraints: const BoxConstraints(
          minHeight: LuminousHomeTheme.minimumTouchTarget,
        ),
        padding: EdgeInsets.only(
          left: LuminousHomeTheme.screenGutter + (indented ? _childIndent : 0),
          right: LuminousHomeTheme.screenGutter,
          top: LuminousHomeTheme.space8,
          bottom: LuminousHomeTheme.space8,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            Expanded(
              child: ExcludeSemantics(
                child: Row(
                  children: <Widget>[
                    Icon(
                      item.checked
                          ? Icons.check_box_rounded
                          : Icons.check_box_outline_blank_rounded,
                      size: 24,
                      color: item.checked
                          ? LuminousHomeTheme.groceryAccent
                          : LuminousHomeTheme.textMuted,
                    ),
                    const SizedBox(width: LuminousHomeTheme.space12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          AnimatedDefaultTextStyle(
                            duration: duration,
                            curve: LuminousHomeTheme.easeStandard,
                            style: LuminousHomeTheme.title.copyWith(
                              color: item.checked
                                  ? LuminousHomeTheme.textMuted
                                  : LuminousHomeTheme.textPrimary,
                              decoration: item.checked
                                  ? TextDecoration.lineThrough
                                  : TextDecoration.none,
                              decorationColor: LuminousHomeTheme.textMuted,
                            ),
                            child: Text(item.name),
                          ),
                          if (item.note != null && item.note!.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                item.note!,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: LuminousHomeTheme.caption.copyWith(
                                  color: LuminousHomeTheme.textMuted,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_quantityText.isNotEmpty) ...<Widget>[
              const SizedBox(width: LuminousHomeTheme.space12),
              if (_convertible)
                _QuantityButton(
                  text: _quantityText,
                  onTap: () => _openConverter(context),
                )
              else
                Text(
                  _quantityText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: LuminousHomeTheme.body.copyWith(
                    color: LuminousHomeTheme.groceryAccent,
                  ),
                ),
            ],
            if (reorderIndex != null) ...<Widget>[
              const SizedBox(width: LuminousHomeTheme.space4),
              ReorderableDragStartListener(
                index: reorderIndex!,
                child: Semantics(
                  button: true,
                  label: 'Reorder ${item.name}',
                  child: SizedBox.square(
                    key: ValueKey<String>('drag_handle_${item.id}'),
                    dimension: LuminousHomeTheme.minimumTouchTarget,
                    child: const Center(
                      child: Icon(
                        Icons.drag_indicator_rounded,
                        size: 24,
                        color: LuminousHomeTheme.textMuted,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );

    return Dismissible(
      key: ValueKey<String>('dismiss_${item.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: LuminousHomeTheme.screenGutter),
        color: LuminousHomeTheme.danger.withValues(alpha: 0.24),
        child: const Icon(
          Icons.delete_outline_rounded,
          color: LuminousHomeTheme.danger,
        ),
      ),
      onDismissed: (_) => _delete(context),
      child: Semantics(
        container: true,
        button: true,
        checked: item.checked,
        label: _semanticLabel,
        onTap: _toggle,
        onLongPress: () => _edit(context),
        customSemanticsActions: _customActions(),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: _toggle,
            onLongPress: () => _edit(context),
            child: content,
          ),
        ),
      ),
    );
  }
}

/// The tappable quantity on a row; opens the unit converter preloaded.
class _QuantityButton extends StatelessWidget {
  final String text;
  final VoidCallback onTap;

  const _QuantityButton({required this.text, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final BorderRadius radius = BorderRadius.circular(
      LuminousHomeTheme.controlRadius,
    );
    return Semantics(
      button: true,
      label: 'Convert $text',
      child: ExcludeSemantics(
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: radius,
            child: Container(
              constraints: const BoxConstraints(
                minHeight: LuminousHomeTheme.minimumTouchTarget,
              ),
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(
                horizontal: LuminousHomeTheme.space8,
              ),
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: LuminousHomeTheme.body.copyWith(
                  color: LuminousHomeTheme.groceryAccent,
                  decoration: TextDecoration.underline,
                  decorationColor: LuminousHomeTheme.groceryMid,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyListState extends StatelessWidget {
  final String listName;

  const _EmptyListState({required this.listName});

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
        GroceryGlassCard(
          padding: const EdgeInsets.all(LuminousHomeTheme.space24),
          child: Column(
            children: <Widget>[
              const Icon(
                Icons.shopping_basket_rounded,
                size: 48,
                color: LuminousHomeTheme.groceryAccent,
              ),
              const SizedBox(height: LuminousHomeTheme.space16),
              Text(
                '$listName is empty',
                textAlign: TextAlign.center,
                style: LuminousHomeTheme.title,
              ),
              const SizedBox(height: LuminousHomeTheme.space8),
              Text(
                'Add an item below — try “2 kg chicken” or “milk”.',
                textAlign: TextAlign.center,
                style: LuminousHomeTheme.body.copyWith(
                  color: LuminousHomeTheme.textMuted,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

double _headerHeight(BuildContext context) {
  final TextScaler scaler = MediaQuery.textScalerOf(context);
  final double text = scaler.scale(13);
  return text < 44 ? 44 : text + 22;
}

class _AisleHeaderDelegate extends SliverPersistentHeaderDelegate {
  final String aisle;
  final int count;
  final double height;

  const _AisleHeaderDelegate({
    required this.aisle,
    required this.count,
    required this.height,
  });

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Container(
      height: height,
      padding: const EdgeInsets.symmetric(
        horizontal: LuminousHomeTheme.screenGutter,
      ),
      decoration: const BoxDecoration(
        color: LuminousHomeTheme.glassOpaqueStrong,
        border: Border(bottom: BorderSide(color: LuminousHomeTheme.hairline)),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              aisle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: LuminousHomeTheme.label.copyWith(
                color: LuminousHomeTheme.textPrimary,
              ),
            ),
          ),
          Text(
            '$count',
            style: LuminousHomeTheme.caption.copyWith(
              color: LuminousHomeTheme.textMuted,
            ),
          ),
        ],
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _AisleHeaderDelegate oldDelegate) =>
      oldDelegate.aisle != aisle ||
      oldDelegate.count != count ||
      oldDelegate.height != height;
}
