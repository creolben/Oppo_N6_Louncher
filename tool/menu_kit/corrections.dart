import 'package:mylauncher/features/shopping/parsing/ingredient_parser.dart';

import 'payload.dart';

/// Applies the fixes in `corrections.json` to one kit's [payload]: mistakes
/// printed in the PDFs themselves, such as a missing step, an ingredient the
/// steps use but the list leaves out, or a misprinted title.
///
/// Each correction names its recipe by PDF file and parsed title, says `why`,
/// and may `rename` it, replace its `description`, times, `steps` (the whole
/// list) or `nutrition` (null drops it), and `remove_ingredients` (by parsed
/// name) or `add_ingredients` (lines written like the PDF's). A correction
/// that no longer matches its recipe throws, so the file cannot go stale
/// silently.
void applyCorrections(
  Map<String, Object?> payload,
  List<Map<String, Object?>> corrections,
) {
  final recipes = (payload['recipes']! as List<Object?>)
      .cast<Map<String, Object?>>();
  for (final correction in corrections) {
    if (correction['pdf'] != payload['source_file']) continue;
    final title = correction['title'];
    final unknown = correction.keys.toSet().difference(_keys);
    if (unknown.isNotEmpty || correction['why'] is! String) {
      throw FormatException(
        'corrections.json, "$title": needs a "why"; unknown keys: $unknown',
      );
    }
    final recipe = recipes.firstWhere(
      (Map<String, Object?> recipe) => recipe['title'] == title,
      orElse: () => throw StateError(
        'corrections.json: no recipe "$title" in ${correction['pdf']}',
      ),
    );
    for (final field in _fields) {
      if (correction.containsKey(field)) recipe[field] = correction[field];
    }
    if (correction['rename'] case final String name) recipe['title'] = name;

    final ingredients = (recipe['ingredients']! as List<Object?>)
        .cast<Map<String, Object?>>();
    for (final name in _strings(correction['remove_ingredients'])) {
      final before = ingredients.length;
      ingredients.removeWhere(
        (Map<String, Object?> ingredient) => ingredient['name'] == name,
      );
      if (ingredients.length == before) {
        throw StateError('corrections.json: no ingredient "$name" in "$title"');
      }
    }
    for (final line in _strings(correction['add_ingredients'])) {
      ingredients.add(
        ingredientPayload(const IngredientParser().parseLine(line)),
      );
    }
  }
}

List<String> _strings(Object? value) =>
    (value as List<Object?>? ?? const <Object?>[]).cast<String>();

const Set<String> _fields = <String>{
  'description',
  'prep_minutes',
  'cook_minutes',
  'rest_minutes',
  'steps',
  'nutrition',
};

const Set<String> _keys = <String>{
  'pdf',
  'title',
  'why',
  'rename',
  'remove_ingredients',
  'add_ingredients',
  ..._fields,
};
