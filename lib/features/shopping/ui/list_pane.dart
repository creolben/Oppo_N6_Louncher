import 'package:flutter/material.dart';

import '../../../ui/theme/luminous_home_theme.dart';
import '../models/shopping_item.dart';
import '../models/shopping_list.dart';
import '../shopping_controller.dart';
import 'grocery_chrome.dart';

/// The active shopping list, grouped into sticky aisle sections with a Done
/// section sinking the checked items to the bottom.
///
/// The pane is a plain view over [controller]; every mutation goes back through
/// the controller so the debounced save and the store stay the single source of
/// truth.
class ListPane extends StatelessWidget {
  final ShoppingController controller;
  final ShoppingList list;

  const ListPane({super.key, required this.controller, required this.list});

  @override
  Widget build(BuildContext context) {
    if (list.items.isEmpty) {
      return _EmptyListState(listName: list.name);
    }

    final List<ShoppingItem> unchecked = list.items
        .where((ShoppingItem item) => !item.checked)
        .toList();
    final List<ShoppingItem> checked = list.items
        .where((ShoppingItem item) => item.checked)
        .toList();

    final Map<String, List<ShoppingItem>> grouped =
        <String, List<ShoppingItem>>{};
    for (final ShoppingItem item in unchecked) {
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
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (BuildContext context, int index) => _ItemRow(
                controller: controller,
                list: list,
                item: grouped[aisle]![index],
              ),
              childCount: grouped[aisle]!.length,
            ),
          ),
        ],
        if (checked.isNotEmpty) ...<Widget>[
          SliverToBoxAdapter(
            child: _DoneHeader(
              list: list,
              count: checked.length,
              onClear: () => controller.clearChecked(list.id),
            ),
          ),
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (BuildContext context, int index) => _ItemRow(
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
}

class _DoneHeader extends StatelessWidget {
  final ShoppingList list;
  final int count;
  final VoidCallback onClear;

  const _DoneHeader({
    required this.list,
    required this.count,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final double headerHeight = _headerHeight(context);
    return Container(
      height: headerHeight,
      padding: const EdgeInsets.symmetric(
        horizontal: LuminousHomeTheme.screenGutter,
      ),
      color: LuminousHomeTheme.glassOpaqueStrong,
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              'Done · $count',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: LuminousHomeTheme.label.copyWith(
                color: LuminousHomeTheme.textMuted,
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

  const _ItemRow({
    required this.controller,
    required this.list,
    required this.item,
  });

  String get _quantityText => item.quantity?.format(
        preferImperial: controller.preferImperial,
      ) ??
      '';

  String get _semanticLabel {
    final String name = _quantityText.isEmpty
        ? item.name
        : '$_quantityText ${item.name}';
    return '$name, ${item.checked ? 'checked' : 'unchecked'}';
  }

  void _toggle() {
    controller.toggleChecked(list.id, item.id);
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

  @override
  Widget build(BuildContext context) {
    final bool reduceMotion = MediaQuery.disableAnimationsOf(context);
    final Duration duration = reduceMotion
        ? Duration.zero
        : LuminousHomeTheme.motionShort;

    return Dismissible(
      key: ValueKey<String>('dismiss_${item.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(
          right: LuminousHomeTheme.screenGutter,
        ),
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
        child: ExcludeSemantics(
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _toggle,
              child: AnimatedOpacity(
                opacity: item.checked ? 0.55 : 1.0,
                duration: duration,
                curve: LuminousHomeTheme.easeStandard,
                child: Container(
                  constraints: const BoxConstraints(
                    minHeight: LuminousHomeTheme.minimumTouchTarget,
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: LuminousHomeTheme.screenGutter,
                    vertical: LuminousHomeTheme.space8,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
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
                      if (_quantityText.isNotEmpty) ...<Widget>[
                        const SizedBox(width: LuminousHomeTheme.space12),
                        Text(
                          _quantityText,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: LuminousHomeTheme.body.copyWith(
                            color: LuminousHomeTheme.groceryAccent,
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
        border: Border(
          bottom: BorderSide(color: LuminousHomeTheme.hairline),
        ),
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
