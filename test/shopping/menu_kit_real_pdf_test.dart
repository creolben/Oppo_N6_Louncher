// Checks the meal-kit parser against real PDFs, which stay out of the repo.
// Opt-in: extract them first, then point the test at the text files.
//
//   tool/pdf_text/extract.sh ~/Documents/Recipes /tmp/menu-kit-text
//   MENU_KIT_TEXT_DIR=/tmp/menu-kit-text \
//     flutter test test/shopping/menu_kit_real_pdf_test.dart
//
// Without MENU_KIT_TEXT_DIR every test here is skipped.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mylauncher/features/shopping/models/shopping_list.dart';
import 'package:mylauncher/features/shopping/parsing/document_parser.dart';
import 'package:mylauncher/features/shopping/parsing/ingredient_parser.dart';
import 'package:mylauncher/features/shopping/parsing/menu_kit_parser.dart';

void main() {
  final String? dir = Platform.environment['MENU_KIT_TEXT_DIR'];
  final List<File> files = dir == null
      ? const <File>[]
      : (Directory(dir)
            .listSync()
            .whereType<File>()
            .where((File f) => f.path.endsWith('.txt'))
            .toList()
          ..sort((File a, File b) => a.path.compareTo(b.path)));

  if (files.isEmpty) {
    test(
      'real meal-kit PDFs',
      () {},
      skip: 'Set MENU_KIT_TEXT_DIR to a folder of extracted PDF text',
    );
    return;
  }

  /// Instruction wording that must never leak into an ingredient.
  final RegExp instructionWords = RegExp(
    r'\b(?:heat|toss|stir|bake|roast|simmer|drizzle|serve)\b|\bcook \d|\bminutes?\b',
    caseSensitive: false,
  );

  for (final File file in files) {
    final String name = file.uri.pathSegments.last;
    group(name, () {
      late MenuKit kit;

      setUpAll(() {
        final document = const DocumentParser().parseDocument(
          file.readAsStringSync(),
        );
        expect(document.menuKit, isNotNull, reason: 'not read as a meal kit');
        kit = document.menuKit!;
      });

      test('names the week', () {
        expect(kit.title, isNotEmpty);
        expect(kit.week, matches(RegExp(r'^[A-Z][a-z]+ \d{1,2}')));
        expect(kit.listName(MenuVariant.regular), contains('·'));
      });

      test('offers regular, vegetarian and both', () {
        expect(kit.variants, <MenuVariant>[
          MenuVariant.regular,
          MenuVariant.vegetarian,
          MenuVariant.both,
        ]);
      });

      test('reads a five-day menu for each table', () {
        for (final MenuVariant variant in <MenuVariant>[
          MenuVariant.regular,
          MenuVariant.vegetarian,
        ]) {
          final menu = kit.menuFor(variant);
          expect(menu.map((MenuDay d) => d.day), <String>[
            'Mon',
            'Tue',
            'Wed',
            'Thu',
            'Fri',
          ]);
          for (final MenuDay day in menu) {
            expect(
              day.dishes,
              hasLength(2),
              reason: '${variant.name} ${day.day}',
            );
          }
        }
      });

      test('every bought line is complete and clean', () {
        for (final MenuVariant variant in kit.variants) {
          final items = kit.itemsFor(variant);
          final bought = items.where((MenuKitItem i) => !i.pantry).toList();
          expect(bought.length, greaterThanOrEqualTo(15), reason: variant.name);
          for (final MenuKitItem item in bought) {
            final where = '${variant.name}: $item';
            expect(item.name, matches(RegExp(r'^[A-ZÀ-Ý]')), reason: where);
            expect(item.name, isNot(contains(r'$')), reason: where);
            expect(item.displayAmount, isNotEmpty, reason: where);
            expect(item.costCents, inInclusiveRange(1, 10000), reason: where);
            expect(item.days, isNotEmpty, reason: where);
            expect(
              weekdayOrder.where(item.days.contains),
              item.days,
              reason: where,
            );
            expect(item.aisle, isNot('Other'), reason: where);
          }
        }
      });

      test('the pantry is complete and unpriced', () {
        final pantry = kit
            .itemsFor(MenuVariant.regular)
            .where((MenuKitItem i) => i.pantry)
            .toList();
        expect(pantry.length, greaterThanOrEqualTo(15));
        for (final MenuKitItem item in pantry) {
          expect(item.costCents, isNull, reason: '$item');
          expect(item.aisle, 'Pantry', reason: '$item');
          expect(item.name, matches(RegExp(r'^[A-Z]')), reason: '$item');
        }
      });

      test('Both lists each item once', () {
        final regular = kit.itemsFor(MenuVariant.regular);
        final vegetarian = kit.itemsFor(MenuVariant.vegetarian);
        final both = kit.itemsFor(MenuVariant.both);
        expect(both.length, lessThan(regular.length + vegetarian.length));
        expect(both.length, greaterThanOrEqualTo(regular.length));
        final keys = both.map((MenuKitItem i) => i.key).toList();
        expect(keys.toSet(), hasLength(keys.length));
        for (var i = 0; i < both.length; i++) {
          for (var j = i + 1; j < both.length; j++) {
            expect(
              similarNames(both[i].name, both[j].name),
              isFalse,
              reason: '${both[i].name} / ${both[j].name}',
            );
          }
        }
      });

      test('reads every recipe page', () {
        expect(kit.recipes.length, greaterThanOrEqualTo(10));
        expect(kit.recipes.where((MenuKitRecipe r) => r.side), isNotEmpty);
        for (final MenuKitRecipe recipe in kit.recipes) {
          expect(recipe.servings, greaterThan(0), reason: recipe.title);
          expect(
            recipe.ingredients.length,
            greaterThanOrEqualTo(3),
            reason: recipe.title,
          );
          for (final ParsedIngredient ingredient in recipe.ingredients) {
            final text = '${ingredient.name} ${ingredient.note ?? ''}';
            expect(
              instructionWords.hasMatch(ingredient.name),
              isFalse,
              reason: '${recipe.title}: $text',
            );
            expect(
              RegExp(r'(?:^|\s)\d+\.[A-Z]').hasMatch(text),
              isFalse,
              reason: '${recipe.title}: $text',
            );
          }
        }
      });

      test('each menu cooks a main and a side every day', () {
        for (final MenuVariant variant in <MenuVariant>[
          MenuVariant.regular,
          MenuVariant.vegetarian,
        ]) {
          final recipes = kit.recipesFor(variant);
          expect(
            recipes.where((MenuKitRecipe r) => !r.side),
            hasLength(5),
            reason: variant.name,
          );
          expect(
            recipes.where((MenuKitRecipe r) => r.side),
            hasLength(5),
            reason: variant.name,
          );
        }
      });
    });
  }
}
