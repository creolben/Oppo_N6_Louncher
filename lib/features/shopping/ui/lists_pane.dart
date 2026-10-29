import 'package:flutter/material.dart';

import '../../../core/launcher_haptics.dart';
import '../../../ui/theme/luminous_home_theme.dart';
import '../models/recipe.dart';
import '../models/shopping_list.dart';
import '../shopping_controller.dart';
import 'grocery_chrome.dart';

/// The lists-and-recipes navigator.
///
/// It owns no state: the surface rebuilds it from [controller], and dialogs
/// mutate through the controller so persistence stays in one place.
class ListsPane extends StatelessWidget {
  final ShoppingController controller;

  /// Highlighted recipe in the navigator, or null when the active list is shown.
  final String? selectedRecipeId;

  final ValueChanged<String> onSelectRecipe;
  final ValueChanged<String> onSelectList;

  const ListsPane({
    super.key,
    required this.controller,
    required this.selectedRecipeId,
    required this.onSelectRecipe,
    required this.onSelectList,
  });

  @override
  Widget build(BuildContext context) {
    final String? activeId = controller.activeList?.id;
    final List<ShoppingList> lists = controller.lists;
    final List<Recipe> recipes = controller.recipes;

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        LuminousHomeTheme.space12,
        LuminousHomeTheme.space8,
        LuminousHomeTheme.space12,
        LuminousHomeTheme.space24,
      ),
      children: <Widget>[
        const Padding(
          padding: EdgeInsets.symmetric(
            horizontal: LuminousHomeTheme.space8,
            vertical: LuminousHomeTheme.space8,
          ),
          child: GrocerySectionLabel(label: 'Lists'),
        ),
        for (final ShoppingList list in lists)
          _NavigatorTile(
            key: ValueKey<String>('list_tile_${list.id}'),
            icon: Icons.list_alt_rounded,
            title: list.name,
            subtitle: _listSubtitle(list),
            selected: selectedRecipeId == null && list.id == activeId,
            onTap: () {
              controller.setActiveList(list.id);
              onSelectList(list.id);
            },
            menu: _TileMenu(
              tooltip: 'List options',
              onRename: () => _renameList(context, list),
              onDelete: () => _confirmDeleteList(context, list),
            ),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: LuminousHomeTheme.space8,
            vertical: LuminousHomeTheme.space8,
          ),
          child: GroceryActionButton(
            icon: Icons.add_rounded,
            label: 'New list',
            onTap: () => _createList(context),
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(
            horizontal: LuminousHomeTheme.space8,
            vertical: LuminousHomeTheme.space8,
          ),
          child: GrocerySectionLabel(label: 'Recipes'),
        ),
        if (recipes.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: LuminousHomeTheme.space8,
              vertical: LuminousHomeTheme.space8,
            ),
            child: Text(
              'Saved recipes appear here after an import.',
              style: LuminousHomeTheme.body.copyWith(
                color: LuminousHomeTheme.textMuted,
              ),
            ),
          )
        else
          for (final Recipe recipe in recipes)
            _NavigatorTile(
              key: ValueKey<String>('recipe_tile_${recipe.id}'),
              icon: Icons.menu_book_rounded,
              title: recipe.title,
              subtitle: _recipeSubtitle(recipe),
              selected: recipe.id == selectedRecipeId,
              onTap: () => onSelectRecipe(recipe.id),
              menu: _TileMenu(
                tooltip: 'Recipe options',
                onRename: () => _renameRecipe(context, recipe),
                onDelete: () => _deleteRecipe(context, recipe),
              ),
            ),
      ],
    );
  }

  static String _listSubtitle(ShoppingList list) {
    final int total = list.items.length;
    if (total == 0) return 'Empty';
    final int done = list.checkedCount;
    return done == 0 ? '$total items' : '$total items · $done done';
  }

  static String _recipeSubtitle(Recipe recipe) {
    final int count = recipe.ingredients.length;
    final String servings = '${recipe.targetServings} servings';
    return count == 0 ? servings : '$servings · $count ingredients';
  }

  /// Creates a list and switches to it, closing the navigator like any other
  /// list pick.
  Future<void> _createList(BuildContext context) async {
    final String? name = await showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) => const _NameDialog(
        title: 'New list',
        confirmLabel: 'Create',
        hint: ShoppingController.defaultListName,
      ),
    );
    if (name == null) return;
    final ShoppingList list = controller.createList(name);
    controller.setActiveList(list.id);
    onSelectList(list.id);
  }

  Future<void> _renameList(BuildContext context, ShoppingList list) async {
    final String? name = await showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) => _NameDialog(
        title: 'Rename list',
        confirmLabel: 'Rename',
        initialValue: list.name,
      ),
    );
    if (name == null) return;
    controller.renameList(list.id, name);
  }

  Future<void> _confirmDeleteList(
    BuildContext context,
    ShoppingList list,
  ) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('Delete list?'),
        content: Text('“${list.name}” and its items will be removed.'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: LuminousHomeTheme.danger,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    controller.deleteList(list.id);
  }

  Future<void> _renameRecipe(BuildContext context, Recipe recipe) async {
    final String? title = await showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) => _NameDialog(
        title: 'Rename recipe',
        confirmLabel: 'Rename',
        hint: 'Recipe name',
        initialValue: recipe.title,
      ),
    );
    if (title == null) return;
    controller.renameRecipe(recipe.id, title);
  }

  /// Deletes [recipe] at once and offers an undo, like a list row.
  void _deleteRecipe(BuildContext context, Recipe recipe) {
    final RemovedRecipe? removed = controller.removeRecipe(recipe.id);
    if (removed == null) return;
    LauncherHaptics.heavyClick();
    showGrocerySnackBar(
      context,
      'Deleted ${recipe.title}',
      actionLabel: 'Undo',
      onAction: () => controller.restoreRecipe(removed),
    );
  }
}

/// The rename/delete overflow on a list or recipe tile.
class _TileMenu extends StatelessWidget {
  final String tooltip;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  const _TileMenu({
    required this.tooltip,
    required this.onRename,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: tooltip,
      icon: const Icon(
        Icons.more_horiz_rounded,
        color: LuminousHomeTheme.textSecondary,
      ),
      onSelected: (String value) {
        if (value == 'rename') {
          onRename();
        } else if (value == 'delete') {
          onDelete();
        }
      },
      itemBuilder: (BuildContext context) => const <PopupMenuEntry<String>>[
        PopupMenuItem<String>(
          value: 'rename',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.edit_rounded),
            title: Text('Rename'),
          ),
        ),
        PopupMenuItem<String>(
          value: 'delete',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              Icons.delete_outline_rounded,
              color: LuminousHomeTheme.danger,
            ),
            title: Text('Delete'),
          ),
        ),
      ],
    );
  }
}

class _NavigatorTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;
  final Widget? menu;

  const _NavigatorTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
    this.menu,
  });

  @override
  Widget build(BuildContext context) {
    final BorderRadius radius = BorderRadius.circular(
      LuminousHomeTheme.controlRadius,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: LuminousHomeTheme.space4),
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
            padding: const EdgeInsets.fromLTRB(
              LuminousHomeTheme.space12,
              LuminousHomeTheme.space8,
              LuminousHomeTheme.space4,
              LuminousHomeTheme.space8,
            ),
            decoration: BoxDecoration(
              borderRadius: radius,
              border: Border.all(
                color: selected
                    ? LuminousHomeTheme.groceryBright
                    : LuminousHomeTheme.hairline,
              ),
            ),
            child: Row(
              children: <Widget>[
                Icon(
                  icon,
                  size: 18,
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
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: LuminousHomeTheme.label.copyWith(
                          color: LuminousHomeTheme.textPrimary,
                        ),
                      ),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: LuminousHomeTheme.caption.copyWith(
                          color: LuminousHomeTheme.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                ?menu,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NameDialog extends StatefulWidget {
  final String title;
  final String confirmLabel;
  final String? hint;
  final String? initialValue;

  const _NameDialog({
    required this.title,
    required this.confirmLabel,
    this.hint,
    this.initialValue,
  });

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialValue ?? '',
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Returns the trimmed text, possibly empty: the controller decides what an
  /// empty name means (the default for a new list, no change for a rename).
  void _submit() {
    Navigator.of(context).pop(_controller.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _submit(),
        decoration: InputDecoration(hintText: widget.hint ?? 'List name'),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: _submit,
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}
