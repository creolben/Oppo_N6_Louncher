import 'package:flutter/material.dart';

import '../../../ui/theme/luminous_home_theme.dart';
import '../models/recipe.dart';
import '../models/shopping_list.dart';
import '../shopping_controller.dart';
import 'grocery_chrome.dart';

/// A saved recipe with a live servings stepper and the scaled ingredient list.
class RecipePane extends StatelessWidget {
  final ShoppingController controller;
  final Recipe recipe;

  /// When set, a back affordance returns to the active list. The wide layout
  /// passes null because the navigator stays visible beside the pane.
  final VoidCallback? onClose;

  /// Tabletop packs the pane into the lower half, so the header is tightened.
  final bool compact;

  const RecipePane({
    super.key,
    required this.controller,
    required this.recipe,
    this.onClose,
    this.compact = false,
  });

  void _addToList(BuildContext context) {
    final ShoppingList? list = controller.activeList;
    if (list == null) return;
    controller.addRecipeToList(recipe.id, list.id);
    showGrocerySnackBar(
      context,
      'Added ${recipe.title} to ${list.name}',
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<Ingredient> scaled = recipe.scaledIngredients;
    final ShoppingList? list = controller.activeList;

    return ListView(
      padding: EdgeInsets.fromLTRB(
        LuminousHomeTheme.screenGutter,
        compact ? LuminousHomeTheme.space8 : LuminousHomeTheme.space16,
        LuminousHomeTheme.screenGutter,
        LuminousHomeTheme.space24,
      ),
      children: <Widget>[
        if (onClose != null)
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  'RECIPE',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: LuminousHomeTheme.caption.copyWith(
                    color: LuminousHomeTheme.groceryAccent,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
              GroceryIconButton(
                icon: Icons.close_rounded,
                label: 'Close recipe',
                onTap: onClose,
              ),
            ],
          ),
        Text(
          recipe.title,
          style: LuminousHomeTheme.title.copyWith(fontSize: 22),
        ),
        const SizedBox(height: LuminousHomeTheme.space12),
        _ServingsStepper(controller: controller, recipe: recipe),
        const SizedBox(height: LuminousHomeTheme.space16),
        const GrocerySectionLabel(label: 'Ingredients'),
        const SizedBox(height: LuminousHomeTheme.space8),
        if (scaled.isEmpty)
          Text(
            'This recipe has no listed ingredients yet.',
            style: LuminousHomeTheme.body.copyWith(
              color: LuminousHomeTheme.textMuted,
            ),
          )
        else
          for (final Ingredient ingredient in scaled)
            _IngredientRow(
              ingredient: ingredient,
              preferImperial: controller.preferImperial,
            ),
        const SizedBox(height: LuminousHomeTheme.space24),
        GroceryActionButton(
          icon: Icons.playlist_add_rounded,
          label: list == null ? 'Add to list' : 'Add to ${list.name}',
          onTap: list == null ? null : () => _addToList(context),
        ),
      ],
    );
  }
}

class _ServingsStepper extends StatelessWidget {
  final ShoppingController controller;
  final Recipe recipe;

  const _ServingsStepper({required this.controller, required this.recipe});

  @override
  Widget build(BuildContext context) {
    final bool canDecrease = recipe.targetServings > 1;
    final bool canIncrease = recipe.targetServings < 99;
    return Row(
      children: <Widget>[
        Expanded(
          child: Text(
            'Servings',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: LuminousHomeTheme.label,
          ),
        ),
        GroceryIconButton(
          icon: Icons.remove_rounded,
          label: 'Decrease servings',
          color: LuminousHomeTheme.groceryAccent,
          onTap: canDecrease
              ? () => controller.setRecipeServings(
                    recipe.id,
                    recipe.targetServings - 1,
                  )
              : null,
        ),
        Semantics(
          label: 'Servings',
          value: '${recipe.targetServings}',
          child: SizedBox(
            width: 48,
            child: Text(
              '${recipe.targetServings}',
              textAlign: TextAlign.center,
              style: LuminousHomeTheme.title.copyWith(fontSize: 20),
            ),
          ),
        ),
        GroceryIconButton(
          icon: Icons.add_rounded,
          label: 'Increase servings',
          color: LuminousHomeTheme.groceryAccent,
          onTap: canIncrease
              ? () => controller.setRecipeServings(
                    recipe.id,
                    recipe.targetServings + 1,
                  )
              : null,
        ),
      ],
    );
  }
}

class _IngredientRow extends StatelessWidget {
  final Ingredient ingredient;
  final bool preferImperial;

  const _IngredientRow({
    required this.ingredient,
    required this.preferImperial,
  });

  @override
  Widget build(BuildContext context) {
    // As entered, like a list row, with the other system as a muted aside;
    // converting outright produced amounts like `236.59 ml`.
    final String quantity = ingredient.quantity?.formatAsEntered() ?? '';
    final String? approx =
        ingredient.quantity?.approxIn(preferImperial: preferImperial);
    return Container(
      constraints: const BoxConstraints(
        minHeight: LuminousHomeTheme.minimumTouchTarget,
      ),
      padding: const EdgeInsets.symmetric(
        vertical: LuminousHomeTheme.space8,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Padding(
            padding: EdgeInsets.only(top: 6, right: LuminousHomeTheme.space12),
            child: Icon(
              Icons.circle,
              size: 6,
              color: LuminousHomeTheme.groceryAccent,
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(ingredient.name, style: LuminousHomeTheme.body.copyWith(
                  color: LuminousHomeTheme.textPrimary,
                )),
                if (ingredient.note != null && ingredient.note!.isNotEmpty)
                  Text(
                    ingredient.note!,
                    style: LuminousHomeTheme.caption.copyWith(
                      color: LuminousHomeTheme.textMuted,
                    ),
                  ),
              ],
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
                  style: LuminousHomeTheme.body.copyWith(
                    color: LuminousHomeTheme.groceryAccent,
                  ),
                ),
                if (approx != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      approx,
                      style: LuminousHomeTheme.caption.copyWith(
                        color: LuminousHomeTheme.textMuted,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
