import 'package:flutter/material.dart';

import '../../../ui/theme/luminous_home_theme.dart';
import '../parsing/document_parser.dart';
import '../parsing/menu_kit_parser.dart';
import '../shopping_controller.dart';
import 'grocery_chrome.dart';
import 'import_review_sheet.dart';
import 'list_pane.dart' show formatCents;

/// Opens the right review for an imported [document]: the meal-kit sheet for
/// a weekly menu PDF, the line-by-line sheet for anything else.
///
/// Shared by the paste, picker and share routes so they cannot drift apart.
Future<void> reviewImportedDocument(
  BuildContext context, {
  required ShoppingController controller,
  required ParsedDocument document,
}) {
  final MenuKit? kit = document.menuKit;
  if (kit != null) {
    return showMenuKitSheet(
      context,
      kit: kit,
      onConfirm:
          (
            MenuVariant variant,
            List<MenuKitItem> items,
            List<MenuKitRecipe> recipes,
          ) => controller.importMenuKit(
            kit.listName(variant),
            items,
            recipes: recipes,
          ),
    );
  }
  return showImportReviewSheet(
    context,
    document: document,
    preferImperial: controller.preferImperial,
    onConfirm: (List<int> indices) =>
        controller.importParsedDocument(document, indices),
  );
}

/// Reviews a weekly meal kit before it becomes a list.
///
/// The user picks the regular menu, the vegetarian one, or both, and can drop
/// lines. Pantry staples start unselected: the kit lists them as reminders,
/// and most kitchens already have salt and olive oil. The chosen menu's
/// recipe pages are saved to Recipes too, unless the user opts out.
class MenuKitSheet extends StatefulWidget {
  final MenuKit kit;
  final MenuKitConfirm onConfirm;

  const MenuKitSheet({super.key, required this.kit, required this.onConfirm});

  @override
  State<MenuKitSheet> createState() => _MenuKitSheetState();
}

class _MenuKitSheetState extends State<MenuKitSheet> {
  late MenuVariant _variant = widget.kit.variants.first;

  /// Keys of lines the user does not want. Shared across variants, so a line
  /// dropped under Regular stays dropped under Both.
  late final Set<String> _excluded = <String>{
    for (final MenuVariant variant in widget.kit.variants)
      for (final MenuKitItem item in widget.kit.itemsFor(variant))
        if (item.pantry) item.key,
  };

  bool _menuOpen = false;

  bool _saveRecipes = true;

  List<MenuKitRecipe> get _recipes => widget.kit.recipesFor(_variant);

  List<MenuKitItem> get _items => widget.kit.itemsFor(_variant);

  List<MenuKitItem> get _selected => _items
      .where((MenuKitItem item) => !_excluded.contains(item.key))
      .toList();

  void _toggle(MenuKitItem item) {
    setState(() {
      if (!_excluded.remove(item.key)) _excluded.add(item.key);
    });
  }

  void _setGroup(List<MenuKitItem> group, bool selected) {
    setState(() {
      for (final MenuKitItem item in group) {
        if (selected) {
          _excluded.remove(item.key);
        } else {
          _excluded.add(item.key);
        }
      }
    });
  }

  void _confirm() {
    final List<MenuKitItem> selected = _selected;
    if (selected.isEmpty) return;
    widget.onConfirm(
      _variant,
      selected,
      _saveRecipes ? _recipes : const <MenuKitRecipe>[],
    );
    if (mounted && Navigator.canPop(context)) {
      Navigator.of(context).pop();
    }
  }

  /// The selected lines grouped by aisle in store-walk order, with pantry
  /// staples always last.
  List<MapEntry<String, List<MenuKitItem>>> get _groups {
    final Map<String, List<MenuKitItem>> byAisle =
        <String, List<MenuKitItem>>{};
    final List<MenuKitItem> pantry = <MenuKitItem>[];
    for (final MenuKitItem item in _items) {
      if (item.pantry) {
        pantry.add(item);
      } else {
        byAisle.putIfAbsent(item.aisle, () => <MenuKitItem>[]).add(item);
      }
    }
    final List<String> aisles = byAisle.keys.toList()
      ..sort(
        (String a, String b) =>
            groceryAisleRank(a).compareTo(groceryAisleRank(b)),
      );
    return <MapEntry<String, List<MenuKitItem>>>[
      for (final String aisle in aisles)
        MapEntry<String, List<MenuKitItem>>(aisle, byAisle[aisle]!),
      if (pantry.isNotEmpty)
        MapEntry<String, List<MenuKitItem>>(
          'Pantry staples — check before you shop',
          pantry,
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final MenuKit kit = widget.kit;
    final List<MenuKitItem> selected = _selected;
    final int cost = selected.fold<int>(
      0,
      (int sum, MenuKitItem item) => sum + (item.costCents ?? 0),
    );
    final double bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final String subtitle = <String>[?kit.week, ?kit.place].join(' · ');

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
                    '${kit.title} meal plan',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: LuminousHomeTheme.title,
                  ),
                ),
                GroceryIconButton(
                  icon: Icons.close_rounded,
                  label: 'Close meal plan import',
                  onTap: () => Navigator.of(context).maybePop(),
                ),
              ],
            ),
            if (subtitle.isNotEmpty)
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: LuminousHomeTheme.caption.copyWith(
                  color: LuminousHomeTheme.textMuted,
                ),
              ),
            const SizedBox(height: LuminousHomeTheme.space12),
            Wrap(
              spacing: LuminousHomeTheme.space8,
              runSpacing: LuminousHomeTheme.space8,
              children: <Widget>[
                for (final MenuVariant variant in kit.variants)
                  _VariantChip(
                    key: ValueKey<String>('menu_variant_${variant.name}'),
                    label: variant.label,
                    selected: variant == _variant,
                    onTap: () => setState(() => _variant = variant),
                  ),
              ],
            ),
            if (kit.menuFor(_variant).isNotEmpty) ...<Widget>[
              const SizedBox(height: LuminousHomeTheme.space4),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => setState(() => _menuOpen = !_menuOpen),
                  style: TextButton.styleFrom(
                    foregroundColor: LuminousHomeTheme.textSecondary,
                    minimumSize: const Size(
                      LuminousHomeTheme.minimumTouchTarget,
                      LuminousHomeTheme.minimumTouchTarget,
                    ),
                  ),
                  icon: Icon(
                    _menuOpen
                        ? Icons.expand_more_rounded
                        : Icons.chevron_right_rounded,
                    size: 20,
                  ),
                  label: const Text("This week's menu"),
                ),
              ),
            ],
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: <Widget>[
                  if (_menuOpen)
                    for (final MenuDay day in kit.menuFor(_variant))
                      Padding(
                        padding: const EdgeInsets.only(
                          bottom: LuminousHomeTheme.space8,
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            SizedBox(
                              width: 44,
                              child: Text(
                                day.day,
                                style: LuminousHomeTheme.label.copyWith(
                                  color: LuminousHomeTheme.groceryAccent,
                                ),
                              ),
                            ),
                            Expanded(
                              child: Text(
                                day.dishes.join('\n'),
                                style: LuminousHomeTheme.caption.copyWith(
                                  color: LuminousHomeTheme.textSecondary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  for (final MapEntry<String, List<MenuKitItem>> group
                      in _groups) ...<Widget>[
                    const SizedBox(height: LuminousHomeTheme.space8),
                    GrocerySectionLabel(
                      label: group.key,
                      trailing: _GroupToggle(
                        allSelected: group.value.every(
                          (MenuKitItem item) => !_excluded.contains(item.key),
                        ),
                        onChanged: (bool selected) =>
                            _setGroup(group.value, selected),
                      ),
                    ),
                    for (final MenuKitItem item in group.value)
                      _MenuKitRow(
                        item: item,
                        selected: !_excluded.contains(item.key),
                        onTap: () => _toggle(item),
                      ),
                  ],
                ],
              ),
            ),
            if (_recipes.isNotEmpty)
              _SaveRecipesToggle(
                count: _recipes.length,
                value: _saveRecipes,
                onChanged: (bool value) => setState(() => _saveRecipes = value),
              ),
            const SizedBox(height: LuminousHomeTheme.space12),
            GroceryActionButton(
              icon: Icons.playlist_add_rounded,
              label: selected.isEmpty
                  ? 'Nothing selected'
                  : <String>[
                      'Create list',
                      selected.length == 1
                          ? '1 item'
                          : '${selected.length} items',
                      if (cost > 0) '~${formatCents(cost)}',
                    ].join(' · '),
              onTap: selected.isEmpty ? null : _confirm,
            ),
          ],
        ),
      ),
    );
  }
}

/// Called with the chosen menu, its selected lines, and the recipes to save
/// (empty when the user opted out).
typedef MenuKitConfirm = void Function(
  MenuVariant variant,
  List<MenuKitItem> items,
  List<MenuKitRecipe> recipes,
);

class _SaveRecipesToggle extends StatelessWidget {
  final int count;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SaveRecipesToggle({
    required this.count,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final String label = count == 1
        ? 'Also save 1 recipe'
        : 'Also save $count recipes';
    return Semantics(
      container: true,
      toggled: value,
      label: label,
      onTap: () => onChanged(!value),
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: const ValueKey<String>('menu_kit_save_recipes'),
          onTap: () => onChanged(!value),
          borderRadius: BorderRadius.circular(LuminousHomeTheme.controlRadius),
          child: Container(
            constraints: const BoxConstraints(
              minHeight: LuminousHomeTheme.minimumTouchTarget,
            ),
            padding: const EdgeInsets.only(top: LuminousHomeTheme.space8),
            child: Row(
              children: <Widget>[
                Icon(
                  value
                      ? Icons.check_box_rounded
                      : Icons.check_box_outline_blank_rounded,
                  size: 22,
                  color: value
                      ? LuminousHomeTheme.groceryAccent
                      : LuminousHomeTheme.textMuted,
                ),
                const SizedBox(width: LuminousHomeTheme.space12),
                Expanded(
                  child: Text(
                    label,
                    style: LuminousHomeTheme.body.copyWith(
                      color: LuminousHomeTheme.textPrimary,
                    ),
                  ),
                ),
                const Icon(
                  Icons.menu_book_rounded,
                  size: 18,
                  color: LuminousHomeTheme.textMuted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _VariantChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _VariantChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final BorderRadius radius = BorderRadius.circular(
      LuminousHomeTheme.controlRadius,
    );
    return Semantics(
      button: true,
      selected: selected,
      label: '$label menu',
      excludeSemantics: true,
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
              horizontal: LuminousHomeTheme.space16,
            ),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: radius,
              border: Border.all(
                color: selected
                    ? LuminousHomeTheme.groceryBright
                    : LuminousHomeTheme.hairline,
              ),
            ),
            child: Text(
              label,
              style: LuminousHomeTheme.label.copyWith(
                color: selected
                    ? LuminousHomeTheme.groceryAccent
                    : LuminousHomeTheme.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GroupToggle extends StatelessWidget {
  final bool allSelected;
  final ValueChanged<bool> onChanged;

  const _GroupToggle({required this.allSelected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: () => onChanged(!allSelected),
      style: TextButton.styleFrom(
        foregroundColor: LuminousHomeTheme.textSecondary,
        minimumSize: const Size(
          LuminousHomeTheme.minimumTouchTarget,
          LuminousHomeTheme.minimumTouchTarget,
        ),
      ),
      child: Text(allSelected ? 'Select none' : 'Select all'),
    );
  }
}

class _MenuKitRow extends StatelessWidget {
  final MenuKitItem item;
  final bool selected;
  final VoidCallback onTap;

  const _MenuKitRow({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final String amount = item.displayAmount;
    final String? cost = item.costCents == null
        ? null
        : formatCents(item.costCents!);
    final String detail = <String>[
      if (item.days.isNotEmpty) item.days.join(' · '),
      ?item.note,
    ].join(' — ');
    return Semantics(
      container: true,
      button: true,
      selected: selected,
      label: <String>[
        if (amount.isNotEmpty) amount,
        item.name,
        ?cost,
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
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          item.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: LuminousHomeTheme.body.copyWith(
                            color: LuminousHomeTheme.textPrimary,
                          ),
                        ),
                        if (detail.isNotEmpty)
                          Text(
                            detail,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: LuminousHomeTheme.caption.copyWith(
                              color: LuminousHomeTheme.textMuted,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (amount.isNotEmpty || cost != null) ...<Widget>[
                    const SizedBox(width: LuminousHomeTheme.space12),
                    Flexible(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          if (amount.isNotEmpty)
                            Text(
                              amount,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: LuminousHomeTheme.caption.copyWith(
                                color: LuminousHomeTheme.groceryAccent,
                              ),
                            ),
                          if (cost != null)
                            Text(
                              cost,
                              style: LuminousHomeTheme.caption.copyWith(
                                color: LuminousHomeTheme.textMuted,
                              ),
                            ),
                        ],
                      ),
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

/// Presents [MenuKitSheet] as a modal sheet.
Future<void> showMenuKitSheet(
  BuildContext context, {
  required MenuKit kit,
  required MenuKitConfirm onConfirm,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: LuminousHomeTheme.lockScrim,
    builder: (BuildContext sheetContext) =>
        MenuKitSheet(kit: kit, onConfirm: onConfirm),
  );
}
