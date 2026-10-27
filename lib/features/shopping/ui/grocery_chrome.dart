import 'package:flutter/material.dart';

import '../../../ui/theme/luminous_home_theme.dart';

/// Canonical store-walk order for grouping shopping items.
///
/// The parser's aisles are a fixed vocabulary, so ordering by a known list keeps
/// a list's sections stable and familiar instead of sorting alphabetically.
/// Unknown aisles (a custom item) sort after every known one.
const List<String> groceryAisleOrder = <String>[
  'Produce',
  'Bakery',
  'Meat & Fish',
  'Dairy & Eggs',
  'Frozen',
  'Pantry',
  'Drinks',
  'Household',
  'Other',
];

int groceryAisleRank(String aisle) {
  final int index = groceryAisleOrder.indexOf(aisle);
  return index < 0 ? groceryAisleOrder.length : index;
}

/// A tonal glass card matching the home surfaces: [glassOpaque], a hairline
/// border and the shared [LuminousHomeTheme.cardRadius].
class GroceryGlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final bool glow;

  const GroceryGlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(LuminousHomeTheme.space16),
    this.radius = LuminousHomeTheme.cardRadius,
    this.glow = false,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: LuminousHomeTheme.glassOpaque,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: LuminousHomeTheme.hairline),
        boxShadow: glow
            ? const <BoxShadow>[
                BoxShadow(
                  color: LuminousHomeTheme.groceryGlow,
                  blurRadius: 18,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

/// A small uppercase section label used across the grocery surface.
class GrocerySectionLabel extends StatelessWidget {
  final String label;
  final Widget? trailing;

  const GrocerySectionLabel({super.key, required this.label, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(
          child: Text(
            label.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: LuminousHomeTheme.caption.copyWith(
              color: LuminousHomeTheme.groceryAccent,
              letterSpacing: 1.2,
            ),
          ),
        ),
        ?trailing,
      ],
    );
  }
}
/// A 48dp round icon button tinted for the grocery surface.
///
/// Semantics mirror the tooltip so a label-less icon is never ambiguous to a
/// screen reader, and the touch target stays at
/// [LuminousHomeTheme.minimumTouchTarget].
class GroceryIconButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final Color color;
  final bool emphasized;

  const GroceryIconButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.color = LuminousHomeTheme.textSecondary,
    this.emphasized = false,
  });

  @override
  Widget build(BuildContext context) {
    final BorderRadius radius = BorderRadius.circular(
      LuminousHomeTheme.controlRadius,
    );
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: label,
      child: Tooltip(
        message: label,
        child: SizedBox.square(
          dimension: LuminousHomeTheme.minimumTouchTarget,
          child: Material(
            color: emphasized
                ? LuminousHomeTheme.softTint(color, 0.16)
                : Colors.transparent,
            borderRadius: radius,
            child: InkWell(
              onTap: onTap,
              borderRadius: radius,
              child: Center(
                child: ExcludeSemantics(
                  child: Icon(icon, color: color, size: 20),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A grocery-tinted pill button (used for primary actions on a pane).
class GroceryActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  const GroceryActionButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final BorderRadius radius = BorderRadius.circular(
      LuminousHomeTheme.controlRadius,
    );
    final bool enabled = onTap != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: Material(
        color: enabled
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
            decoration: BoxDecoration(
              borderRadius: radius,
              border: Border.all(
                color: enabled
                    ? LuminousHomeTheme.groceryBright
                    : LuminousHomeTheme.hairline,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Icon(
                  icon,
                  size: 18,
                  color: enabled
                      ? LuminousHomeTheme.groceryAccent
                      : LuminousHomeTheme.textMuted,
                ),
                const SizedBox(width: LuminousHomeTheme.space8),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: LuminousHomeTheme.label.copyWith(
                      color: enabled
                          ? LuminousHomeTheme.textPrimary
                          : LuminousHomeTheme.textMuted,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Bottom clearance for grocery snack bars: the quick-add capsule (52) plus
/// its padding (8 + 12) and a gap, so an undo never covers the add field.
const double _snackBarBottomClearance = 88;

/// Shows a snack bar through the nearest messenger, replacing any current one
/// so a rapid sequence of grocery actions never queues stale messages.
///
/// It floats above the quick-add capsule rather than sitting over it, so the
/// user can keep typing while an undo is on offer.
void showGrocerySnackBar(
  BuildContext context,
  String message, {
  String? actionLabel,
  VoidCallback? onAction,
}) {
  final ScaffoldMessengerState? messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(
          LuminousHomeTheme.space16,
          0,
          LuminousHomeTheme.space16,
          _snackBarBottomClearance,
        ),
        action: actionLabel == null || onAction == null
            ? null
            : SnackBarAction(
                label: actionLabel,
                textColor: LuminousHomeTheme.groceryAccent,
                onPressed: onAction,
              ),
      ),
    );
}
