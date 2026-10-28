import 'package:mylauncher/features/shopping/models/quantity.dart';
import 'package:mylauncher/features/shopping/parsing/ingredient_parser.dart';
import 'package:mylauncher/features/shopping/parsing/menu_kit_parser.dart';

/// The JSON `ingest_menu_kit(kit jsonb)` stores (see
/// supabase/migrations/*_menu_kits.sql).
///
/// Only the two printed lists are stored; the app derives "Both" from them.
Map<String, Object?> menuKitPayload(
  MenuKit kit, {
  required String sourceFile,
  required String pdfSha256,
  String? pdfPath,
}) {
  final start = weekStart(kit.week);
  return <String, Object?>{
    'title': kit.title,
    'week_label': kit.week,
    'week_start': start == null ? null : _isoDate(start),
    'place': kit.place,
    'source_file': sourceFile,
    'pdf_sha256': pdfSha256,
    'pdf_path': pdfPath,
    'menus': <Map<String, Object?>>[
      for (final variant in _printed)
        for (final day in kit.menuFor(variant))
          <String, Object?>{
            'variant': variant.name,
            'day': day.day,
            'dishes': day.dishes,
          },
    ],
    'items': <Map<String, Object?>>[
      for (final variant in _printed)
        for (final (index, item) in kit.itemsFor(variant).indexed)
          <String, Object?>{
            'variant': variant.name,
            'position': index,
            'name': item.name,
            'aisle': item.aisle,
            'amount_text': item.amountText,
            ..._quantity(item.quantity),
            'note': item.note,
            'cost_cents': item.costCents,
            'days': item.days,
            'pantry': item.pantry,
          },
    ],
    'recipes': <Map<String, Object?>>[
      for (final (index, recipe) in kit.recipes.indexed)
        <String, Object?>{
          'position': index,
          'title': recipe.title,
          'servings': recipe.servings,
          'side': recipe.side,
          'variants': <String>[
            for (final variant in _printed)
              if (recipe.variants.contains(variant)) variant.name,
          ],
          'ingredients': <Map<String, Object?>>[
            for (final ParsedIngredient ingredient in recipe.ingredients)
              <String, Object?>{
                'name': ingredient.name,
                ..._quantity(ingredient.quantity),
                'note': ingredient.note,
              },
          ],
        },
    ],
  };
}

const List<MenuVariant> _printed = <MenuVariant>[
  MenuVariant.regular,
  MenuVariant.vegetarian,
];

Map<String, Object?> _quantity(Quantity? quantity) => <String, Object?>{
  'quantity_amount': quantity?.amount,
  'quantity_unit': quantity?.unit.symbol,
};

const Map<String, int> _months = <String, int>{
  'january': 1,
  'february': 2,
  'march': 3,
  'april': 4,
  'may': 5,
  'june': 6,
  'july': 7,
  'august': 8,
  'september': 9,
  'october': 10,
  'november': 11,
  'december': 12,
};

/// The date a printed week starts (`October 2nd, 2026` → 2026-10-02), or
/// null when [week] is not a full date.
DateTime? weekStart(String? week) {
  if (week == null) return null;
  final match = RegExp(
    r'^([A-Za-z]+)\s+(\d{1,2})(?:st|nd|rd|th)?,?\s+(\d{4})$',
    caseSensitive: false,
  ).firstMatch(week.trim());
  if (match == null) return null;
  final month = _months[match.group(1)!.toLowerCase()];
  if (month == null) return null;
  final year = int.parse(match.group(3)!);
  final day = int.parse(match.group(2)!);
  final date = DateTime.utc(year, month, day);
  // Reject days the month does not have (`February 30`).
  return date.month == month ? date : null;
}

String _isoDate(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';
