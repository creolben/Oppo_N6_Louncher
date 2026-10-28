import '../models/quantity.dart';
import '../models/shopping_item.dart';
import '../models/shopping_list.dart';
import 'ingredient_parser.dart';

/// Which of a meal kit's menus a list is built from.
enum MenuVariant {
  regular,
  vegetarian,

  /// Both menus in one list: shared lines once, each menu's own lines added.
  both;

  String get label {
    switch (this) {
      case MenuVariant.regular:
        return 'Regular';
      case MenuVariant.vegetarian:
        return 'Vegetarian';
      case MenuVariant.both:
        return 'Both';
    }
  }
}

/// One day of a weekly menu and the dishes cooked on it.
class MenuDay {
  final String day;
  final List<String> dishes;

  const MenuDay({required this.day, required this.dishes});
}

/// One line of a meal kit's shopping list.
class MenuKitItem {
  final String name;

  /// The store aisle the line belongs in, already mapped to the app's aisles.
  final String aisle;

  /// The amount when it parses cleanly (`12 ounces`, `4`), else null.
  final Quantity? quantity;

  /// The printed amount when [quantity] could not hold it (`4 medium bulbs`).
  final String? amountText;

  final String? note;
  final int? costCents;

  /// Short weekday names (`Mon`, `Thu`) in week order.
  final List<String> days;

  /// A pantry staple: listed as a reminder rather than something to buy.
  final bool pantry;

  const MenuKitItem({
    required this.name,
    required this.aisle,
    this.quantity,
    this.amountText,
    this.note,
    this.costCents,
    this.days = const <String>[],
    this.pantry = false,
  });

  /// The amount as printed, for review screens.
  String get displayAmount => quantity?.formatAsEntered() ?? amountText ?? '';

  String get key => ShoppingItem.normalizeName(name);

  MenuKitItem copyWith({String? note, List<String>? days}) => MenuKitItem(
    name: name,
    aisle: aisle,
    quantity: quantity,
    amountText: amountText,
    note: note ?? this.note,
    costCents: costCents,
    days: days ?? this.days,
    pantry: pantry,
  );

  @override
  String toString() =>
      'MenuKitItem($name, $displayAmount, $aisle, $days, $costCents)';
}

/// One recipe page of a meal kit.
class MenuKitRecipe {
  final String title;
  final int servings;
  final List<ParsedIngredient> ingredients;

  /// Whether the page is a side dish rather than the day's main.
  final bool side;

  /// The menus that cook this recipe: [MenuVariant.regular],
  /// [MenuVariant.vegetarian] or both.
  final Set<MenuVariant> variants;

  const MenuKitRecipe({
    required this.title,
    required this.servings,
    required this.ingredients,
    this.side = false,
    this.variants = const <MenuVariant>{MenuVariant.regular},
  });

  @override
  String toString() =>
      'MenuKitRecipe($title, serves $servings, ${ingredients.length} '
      'ingredients, $variants)';
}

/// Whether two printed names mean the same thing despite a typo
/// (`Anchovies`/`Ancovies`, `Roasted Squash`/`Roasted Squashs`).
///
/// Names are compared through [ShoppingItem.normalizeName]. Short names must
/// match exactly; longer ones may differ by one edit, and long ones by two.
bool similarNames(String a, String b) {
  final x = ShoppingItem.normalizeName(a);
  final y = ShoppingItem.normalizeName(b);
  if (x == y) return true;
  final shorter = x.length < y.length ? x.length : y.length;
  if (shorter < 6) return false;
  final allowed = shorter >= 14 ? 2 : 1;
  if ((x.length - y.length).abs() > allowed) return false;
  return _editDistance(x, y, allowed) <= allowed;
}

/// Levenshtein distance, giving up once it exceeds [limit].
int _editDistance(String a, String b, int limit) {
  var previous = List<int>.generate(b.length + 1, (int i) => i);
  for (var i = 1; i <= a.length; i++) {
    final current = List<int>.filled(b.length + 1, 0)..[0] = i;
    var rowMin = current[0];
    for (var j = 1; j <= b.length; j++) {
      final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
      final value = <int>[
        previous[j] + 1,
        current[j - 1] + 1,
        previous[j - 1] + cost,
      ].reduce((int m, int v) => v < m ? v : m);
      current[j] = value;
      if (value < rowMin) rowMin = value;
    }
    if (rowMin > limit) return limit + 1;
    previous = current;
  }
  return previous[b.length];
}

/// A weekly meal-kit PDF: menus and shopping lists for a regular and a
/// vegetarian table.
class MenuKit {
  /// The cuisine line of the page header (`Mediterranean`).
  final String title;

  /// The week the kit is for, as printed (`October 2nd, 2026`).
  final String? week;

  /// The featured place (`Patras, Greece`), when the kit names one.
  final String? place;

  final Map<MenuVariant, List<MenuDay>> menus;

  /// The printed lists, keyed by [MenuVariant.regular] and
  /// [MenuVariant.vegetarian]. [itemsFor] derives [MenuVariant.both].
  final Map<MenuVariant, List<MenuKitItem>> lists;

  /// Every recipe page whose ingredient column could be read.
  final List<MenuKitRecipe> recipes;

  const MenuKit({
    required this.title,
    this.week,
    this.place,
    this.menus = const <MenuVariant, List<MenuDay>>{},
    this.lists = const <MenuVariant, List<MenuKitItem>>{},
    this.recipes = const <MenuKitRecipe>[],
  });

  /// The recipes cooked under [variant]; [MenuVariant.both] is all of them.
  List<MenuKitRecipe> recipesFor(MenuVariant variant) {
    if (variant == MenuVariant.both) return recipes;
    return recipes
        .where((MenuKitRecipe recipe) => recipe.variants.contains(variant))
        .toList();
  }

  /// The variants this kit can build a list from, in display order.
  List<MenuVariant> get variants => <MenuVariant>[
    if (lists.containsKey(MenuVariant.regular)) MenuVariant.regular,
    if (lists.containsKey(MenuVariant.vegetarian)) MenuVariant.vegetarian,
    if (lists.containsKey(MenuVariant.regular) &&
        lists.containsKey(MenuVariant.vegetarian))
      MenuVariant.both,
  ];

  /// The dishes for [variant]. [MenuVariant.both] lists each day's regular
  /// dishes followed by any vegetarian dish that differs.
  List<MenuDay> menuFor(MenuVariant variant) {
    if (variant != MenuVariant.both) {
      return menus[variant] ?? const <MenuDay>[];
    }
    final regular = menus[MenuVariant.regular] ?? const <MenuDay>[];
    final vegetarian = menus[MenuVariant.vegetarian] ?? const <MenuDay>[];
    if (regular.isEmpty) return vegetarian;
    return <MenuDay>[
      for (final day in regular)
        MenuDay(
          day: day.day,
          dishes: <String>[
            ...day.dishes,
            for (final other in vegetarian)
              if (other.day == day.day)
                for (final dish in other.dishes)
                  if (!day.dishes.contains(dish)) dish,
          ],
        ),
    ];
  }

  /// The shopping lines for [variant].
  ///
  /// [MenuVariant.both] keeps every regular line, takes a shared line once
  /// (the pricier amount when the two lists disagree, with both noted), and
  /// adds each vegetarian-only line marked as such.
  List<MenuKitItem> itemsFor(MenuVariant variant) {
    if (variant != MenuVariant.both) {
      return lists[variant] ?? const <MenuKitItem>[];
    }
    final regular = lists[MenuVariant.regular] ?? const <MenuKitItem>[];
    final vegetarian = lists[MenuVariant.vegetarian] ?? const <MenuKitItem>[];
    // Each vegetarian line pairs with at most one regular line: an exact name
    // first, else a near-identical one so a typo does not list it twice.
    final unmatched = List<MenuKitItem>.of(vegetarian);
    MenuKitItem? takeMatch(MenuKitItem item) {
      var index = unmatched.indexWhere((other) => other.key == item.key);
      if (index < 0) {
        index = unmatched.indexWhere(
          (other) =>
              other.pantry == item.pantry &&
              similarNames(other.name, item.name),
        );
      }
      return index < 0 ? null : unmatched.removeAt(index);
    }

    final combined = <MenuKitItem>[];
    for (final item in regular) {
      final other = takeMatch(item);
      if (other == null) {
        combined.add(item.pantry ? item : _tagged(item, 'Regular menu'));
        continue;
      }
      final days = _unionDays(item.days, other.days);
      if (item.displayAmount == other.displayAmount) {
        combined.add(item.copyWith(days: days));
        continue;
      }
      final bigger = (other.costCents ?? 0) > (item.costCents ?? 0)
          ? other
          : item;
      combined.add(
        _tagged(
          bigger.copyWith(days: days),
          'Regular ${item.displayAmount} · Vegetarian ${other.displayAmount}',
        ),
      );
    }
    for (final item in unmatched) {
      combined.add(item.pantry ? item : _tagged(item, 'Vegetarian menu'));
    }
    return combined;
  }

  /// A list name such as `Mediterranean · Oct 2 · Vegetarian`.
  String listName(MenuVariant variant) {
    final parts = <String>[title];
    final shortWeek = _shortWeek(week);
    if (shortWeek != null) parts.add(shortWeek);
    if (variant != MenuVariant.regular) parts.add(variant.label);
    return parts.join(' · ');
  }

  static MenuKitItem _tagged(MenuKitItem item, String tag) =>
      item.copyWith(note: item.note == null ? tag : '$tag · ${item.note}');

  static List<String> _unionDays(List<String> a, List<String> b) {
    final all = <String>{...a, ...b};
    return weekdayOrder.where(all.contains).toList();
  }

  static const Map<String, String> _monthShort = <String, String>{
    'january': 'Jan',
    'february': 'Feb',
    'march': 'Mar',
    'april': 'Apr',
    'may': 'May',
    'june': 'Jun',
    'july': 'Jul',
    'august': 'Aug',
    'september': 'Sep',
    'october': 'Oct',
    'november': 'Nov',
    'december': 'Dec',
  };

  static String? _shortWeek(String? week) {
    if (week == null) return null;
    final match = RegExp(r'^([A-Za-z]+)\s+(\d{1,2})').firstMatch(week);
    if (match == null) return week;
    final month = _monthShort[match.group(1)!.toLowerCase()];
    return month == null ? week : '$month ${match.group(2)}';
  }
}

/// Recognizes weekly meal-kit PDFs and reads their menus and shopping lists.
///
/// The format, as the on-device text extractor emits it (one table row per
/// line, columns joined by spaces, or by a tab across a wide gap):
///
/// ```text
/// MEDITERRANEAN | FALL | OCTOBER 2ND, 2026
/// VEGETARIAN SHOPPING LIST
/// RECIPE PRODUCE QTY NOTES EST. COST
/// T, W Cherry tomatoes 1 pint Halve just before cooking $3.50
/// PANTRY QTY PANTRY QTY
/// Canned tomatoes 1 (28 oz) can Sea salt As needed
/// ```
///
/// Each table row is `days name amount notes $cost`. Pantry rows hold two
/// `name amount` pairs side by side. Column boundaries are recovered from the
/// shapes of the cells: an amount starts with a number, `-`, `About`, `As` or
/// `Pinch`, and a note or the next name starts with a capital letter that is
/// not a unit (`Tablespoons`).
///
/// Recipe pages (`Serves: 4`, then `INGREDIENTS<tab>INSTRUCTIONS`) are read
/// from the left column only, so they need the extractor's column tabs.
class MenuKitParser {
  const MenuKitParser();

  /// Returns the kit in [text], or null when [text] has no meal-kit shopping
  /// list.
  MenuKit? tryParse(String text) {
    String? title;
    String? week;
    String? place;
    final menus = <MenuVariant, List<MenuDay>>{};
    final lists = <MenuVariant, List<MenuKitItem>>{};
    final pages = <_RecipePage>[];

    _Mode mode = _Mode.none;
    _RecipePage? page;
    String? dailySideTitle;
    int? dailySideServings;
    var dailyVegetarian = false;
    var pendingVegetarianList = false;
    String? pendingVariant;
    MenuVariant variant = MenuVariant.regular;
    // The list the last shopping-list heading opened, so a section heading on
    // the next page continues it.
    MenuVariant? listVariant;
    String section = '';
    List<MenuDay>? menu;
    String? day;
    List<String>? dishes;

    void closeDay() {
      final open = menu;
      final openDay = day;
      final openDishes = dishes;
      if (open != null &&
          openDay != null &&
          openDishes != null &&
          openDishes.isNotEmpty) {
        open.add(MenuDay(day: openDay, dishes: openDishes));
      }
      day = null;
      dishes = null;
    }

    void closeRecipe() {
      final open = page;
      if (open != null && open.lines.isNotEmpty) pages.add(open);
      page = null;
    }

    final lines = text.split(RegExp(r'\r?\n'));
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i].trim().replaceAll(RegExp(r'\s+'), ' ');
      if (line.isEmpty) continue;

      // A variant word on its own line (`VEGETARIAN`) belongs to the heading
      // that follows (`MENU`, `SHOPPING LIST`).
      if (pendingVariant != null &&
          line != 'MENU' &&
          !line.endsWith('SHOPPING LIST')) {
        pendingVariant = null;
      }
      if (_variantWord.hasMatch(line)) {
        pendingVariant = line.toUpperCase();
        continue;
      }

      final header = _pageHeader.firstMatch(line);
      if (header != null) {
        closeDay();
        closeRecipe();
        title ??= _titleCase(header.group(2)!);
        week ??= _titleCase(header.group(3)!);
        mode = _Mode.none;
        // Any page can be a recipe; it only counts once an ingredient
        // heading follows. The title is the first line under the header.
        final following = _nextLines(lines, i + 1, 2);
        if (following.isNotEmpty && _isHeading(following.first)) {
          page = _RecipePage(
            title: _titleCase(following.first),
            side: following.length > 1 && following[1] == 'SIDE DISH',
            vegetarianPage: header.group(1) != null,
          );
          mode = _Mode.recipeIntro;
        }
        // The line under the first page header names the featured place.
        if (place == null && i + 1 < lines.length) {
          final next = lines[i + 1].trim();
          if (_place.hasMatch(next)) place = _titleCase(next);
        }
        continue;
      }

      final daily = _dailyHeader.firstMatch(line);
      if (daily != null) {
        closeDay();
        closeRecipe();
        mode = _Mode.none;
        dailyVegetarian = line.toUpperCase().contains('VEGETARIAN');
        final sidePage = line.toUpperCase().endsWith('SIDE');
        // Titles run until the first non-heading line. Whether a second
        // all-caps line is another dish or a wrapped title depends on the
        // ingredient heading further down.
        final rawTitles = <String>[];
        var j = i + 1;
        while (j < lines.length) {
          final raw = lines[j].trim().replaceAll(RegExp(r'\s+'), ' ');
          if (raw.isEmpty) {
            j++;
            continue;
          }
          if (!_isHeading(raw)) break;
          if (raw != 'SIDE DISH' && raw != 'MAIN DISH') rawTitles.add(raw);
          j++;
        }
        var heading = '';
        for (var k = j; k < lines.length && k < i + 30; k++) {
          final candidate = lines[k].trim();
          final upper = candidate.toUpperCase();
          if (upper.startsWith('MAIN: INGREDIENTS') ||
              upper.startsWith('SIDE: INGREDIENTS')) {
            heading = upper;
            break;
          }
          if (_dailyHeader.hasMatch(candidate) ||
              _pageHeader.hasMatch(candidate)) {
            break;
          }
        }
        final titles = _titlesFor(
          rawTitles,
          _dayDishes(
            menus,
            dailyVegetarian ? MenuVariant.vegetarian : MenuVariant.regular,
            _weekday[daily.group(1)!] ?? '',
          ),
        );
        if (titles.isNotEmpty) {
          final sideHeading = heading.startsWith('SIDE');
          page = _RecipePage(
            title: _titleCase(sideHeading ? titles.join(' ') : titles.first),
            side: sidePage || sideHeading,
            vegetarianPage: dailyVegetarian,
          );
          dailySideTitle = !sideHeading && titles.length > 1
              ? _titleCase(titles[1])
              : null;
          dailySideServings = null;
          mode = _Mode.dailyIntro;
        }
        continue;
      }

      if (_vegetarianListHeader.hasMatch(line)) {
        closeDay();
        closeRecipe();
        pendingVegetarianList = true;
        mode = _Mode.none;
        continue;
      }

      // `MEDITERRANEAN FALL | SAMOS, GREECE` — week header of the middle
      // layout, naming the featured place instead of a date.
      final placeHeader = _placeHeader.firstMatch(line);
      if (placeHeader != null) {
        closeDay();
        closeRecipe();
        mode = _Mode.none;
        pendingVegetarianList = false;
        title ??= _titleCase(
          placeHeader
              .group(1)!
              .replaceFirst(RegExp(r'\s+(?:SPRING|SUMMER|FALL|WINTER)$'), ''),
        );
        place ??= _titleCase(placeHeader.group(2)!);
        continue;
      }

      // `MEDITERRANEAN IN SPRING | JUNE 16–20` — the older week header, which
      // prints no year.
      final weekHeader = _weekHeader.firstMatch(line);
      if (weekHeader != null) {
        closeDay();
        closeRecipe();
        mode = _Mode.none;
        final cuisine = weekHeader.group(1)!;
        if (!cuisine.contains('SNACKS')) {
          title ??= _titleCase(
            cuisine.replaceFirst(RegExp(r'\s+IN\s+[A-Z]+$'), ''),
          );
          week ??= _titleCase(weekHeader.group(2)!);
        }
        if (place == null) {
          final following = _nextLines(lines, i + 1, 1);
          if (following.isNotEmpty && _place.hasMatch(following.first)) {
            place = _titleCase(following.first);
          }
        }
        continue;
      }

      // Any other all-caps running header (`MEDITERRANEAN | FALL | PATRAS,
      // GREECE`): it starts a page that is not part of a recipe.
      if (_otherHeader.hasMatch(line)) {
        closeDay();
        closeRecipe();
        mode = _Mode.none;
        continue;
      }

      final menuHeading = _menuHeading.firstMatch(line);
      if (menuHeading != null) {
        closeDay();
        variant = _variantOf(menuHeading.group(1) ?? pendingVariant);
        pendingVariant = null;
        menu = menus.putIfAbsent(variant, () => <MenuDay>[]);
        listVariant = null;
        mode = _Mode.menu;
        continue;
      }

      final listHeading = _listHeading.firstMatch(line);
      if (listHeading != null) {
        closeDay();
        final listWord =
            listHeading.group(1) ?? listHeading.group(2) ?? pendingVariant;
        pendingVariant = null;
        variant = listWord != null
            ? _variantOf(listWord)
            : (pendingVegetarianList
                  ? MenuVariant.vegetarian
                  : MenuVariant.regular);
        pendingVegetarianList = false;
        listVariant = variant;
        lists.putIfAbsent(variant, () => <MenuKitItem>[]);
        section = '';
        mode = _Mode.table;
        continue;
      }

      // `SHOPPING LIST: SNACKS` is not one of the two printed menus; its rows
      // use recipe numbers instead of weekdays and are not imported.
      if (_otherListHeading.hasMatch(line)) {
        closeDay();
        listVariant = null;
        mode = _Mode.none;
        continue;
      }

      // A table heading outside a list continues the last list: a list that
      // runs onto a second page gets a page header, not a new list heading.
      final openList = listVariant;
      if (openList != null &&
          mode != _Mode.table &&
          mode != _Mode.pantry &&
          (_sectionHeading.hasMatch(line) || _pantryHeading.hasMatch(line))) {
        closeDay();
        page = null;
        variant = openList;
        mode = _Mode.table;
      }

      switch (mode) {
        case _Mode.none:
          break;
        case _Mode.recipeIntro:
          final serves = _serves.firstMatch(line);
          if (serves != null) {
            page?.servings = int.parse(serves.group(1)!);
          } else if (line.toUpperCase().startsWith('INGREDIENTS')) {
            // Without the extractor's column tabs the ingredient and
            // instruction columns cannot be told apart; skip the recipe
            // rather than save instructions as ingredients.
            if (lines[i].contains('\t')) {
              mode = _Mode.recipeIngredients;
            } else {
              page = null;
              mode = _Mode.none;
            }
          }
        case _Mode.dailyIntro:
          final serves = _serves.firstMatch(line);
          if (serves != null) {
            page?.servings = int.parse(serves.group(1)!);
          } else if (line.toUpperCase().startsWith('MAIN: INGREDIENTS') ||
              line.toUpperCase().startsWith('SIDE: INGREDIENTS')) {
            if (line.toUpperCase().startsWith('SIDE:')) page?.side = true;
            if (lines[i].contains('\t')) {
              mode = _Mode.dailyIngredients;
            } else {
              page = null;
              mode = _Mode.none;
            }
          }
        case _Mode.dailyIngredients:
          final upper = line.toUpperCase();
          if (upper.startsWith('SERVES:')) {
            final sideServes = _serves.firstMatch(line);
            dailySideServings = sideServes == null
                ? null
                : int.parse(sideServes.group(1)!);
          } else if (upper.startsWith('SIDE: INGREDIENTS')) {
            final open = page;
            if (open != null && open.lines.isEmpty) {
              // A page of its own, headed by the side's title.
              open.side = true;
              open.servings = dailySideServings ?? open.servings;
            } else {
              final mainServings = open?.servings;
              closeRecipe();
              page = _RecipePage(
                title: dailySideTitle ?? 'Side dish',
                side: true,
                vegetarianPage: dailyVegetarian,
              )..servings = dailySideServings ?? mainServings;
              dailySideTitle = null;
              dailySideServings = null;
            }
          } else if (upper.startsWith('MAIN: INGREDIENTS')) {
            // Repeated heading; nothing to add.
          } else if (upper.startsWith('COMMON SUBSTITUTIONS') ||
              upper.startsWith('INGREDIENT SWAPS') ||
              upper.startsWith('QUICK ASSEMBLY') ||
              line.contains('Nutritional Information')) {
            closeRecipe();
            mode = _Mode.none;
          } else {
            page?.addLine(lines[i]);
          }
        case _Mode.recipeIngredients:
          if (line.toUpperCase().startsWith('COMMON SUBSTITUTIONS') ||
              line.contains('Nutritional Information')) {
            closeRecipe();
            mode = _Mode.none;
            continue;
          }
          page?.addLine(lines[i]);
        case _Mode.menu:
          if (_weekday.containsKey(line.toUpperCase())) {
            closeDay();
            day = _weekday[line.toUpperCase()];
            dishes = <String>[];
          } else if (dishes != null && line == line.toUpperCase()) {
            dishes!.add(_titleCase(line));
          } else {
            closeDay();
            mode = _Mode.none;
          }
        case _Mode.table:
        case _Mode.pantry:
          final sectionMatch = _sectionHeading.firstMatch(line);
          if (sectionMatch != null) {
            section = sectionMatch.group(1)!.replaceFirst(RegExp(r'^#\s*'), '');
            mode = _Mode.table;
            continue;
          }
          if (_pantryHeading.hasMatch(line)) {
            mode = _Mode.pantry;
            continue;
          }
          final items = lists[variant]!;
          if (mode == _Mode.table) {
            final item = _parseRow(line, section);
            if (item != null) {
              items.add(item);
            } else {
              mode = _Mode.none;
            }
          } else {
            final pairs = _parsePantryRow(line);
            if (pairs.isEmpty) {
              mode = _Mode.none;
            } else {
              items.addAll(pairs);
            }
          }
      }
    }
    closeDay();
    closeRecipe();

    lists.removeWhere((_, items) => items.isEmpty);
    if (lists.isEmpty) return null;
    menus.removeWhere((_, days) => days.isEmpty);
    final vegetarianDishes = <String>[
      for (final day in menus[MenuVariant.vegetarian] ?? const <MenuDay>[])
        ...day.dishes,
    ];
    final hasVegetarianPages = pages.any(
      (_RecipePage page) => page.vegetarianPage,
    );
    return MenuKit(
      title: title ?? 'Meal plan',
      week: week,
      place: place,
      menus: menus,
      lists: lists,
      recipes: <MenuKitRecipe>[
        for (final recipe in pages)
          MenuKitRecipe(
            title: recipe.title,
            servings: recipe.servings ?? 1,
            ingredients: List<ParsedIngredient>.unmodifiable(
              recipe.ingredients,
            ),
            side: recipe.side,
            variants: _recipeVariants(
              recipe,
              vegetarianDishes,
              hasVegetarianPages: hasVegetarianPages,
            ),
          ),
      ],
    );
  }

  /// A vegetarian page belongs to the vegetarian menu alone. Any other page
  /// is on the regular menu, and on the vegetarian one too when that menu
  /// lists the dish (or prints no menu to check against).
  static Set<MenuVariant> _recipeVariants(
    _RecipePage page,
    List<String> vegetarianDishes, {
    bool hasVegetarianPages = false,
  }) {
    if (page.vegetarianPage) return const <MenuVariant>{MenuVariant.vegetarian};
    final shared = vegetarianDishes.isEmpty
        ? !hasVegetarianPages
        : vegetarianDishes.any((String dish) => similarNames(dish, page.title));
    return <MenuVariant>{
      MenuVariant.regular,
      if (shared) MenuVariant.vegetarian,
    };
  }

  /// Up to [count] non-empty, whitespace-collapsed lines from [start].
  static List<String> _nextLines(List<String> lines, int start, int count) {
    final found = <String>[];
    for (var i = start; i < lines.length && found.length < count; i++) {
      final line = lines[i].trim().replaceAll(RegExp(r'\s+'), ' ');
      if (line.isNotEmpty) found.add(line);
    }
    return found;
  }

  /// An all-caps line with letters: a page or dish title.
  static bool _isHeading(String line) =>
      line == line.toUpperCase() && RegExp(r'[A-Z]').hasMatch(line);

  /// Joins a title that wraps onto a second line (`CRUSTY BREAD WITH GARLIC,`
  /// / `HERBS & LEMON`) without merging two separate dishes.
  static List<String> _joinWrappedTitles(List<String> titles) {
    final joined = <String>[];
    for (final title in titles) {
      final previous = joined.isEmpty ? null : joined.last;
      if (previous != null &&
          (previous.endsWith(',') ||
              previous.endsWith('-') ||
              previous.endsWith('&') ||
              RegExp(r'^(?:WITH|AND|&)\b').hasMatch(title))) {
        joined.last = '$previous $title';
      } else {
        joined.add(title);
      }
    }
    return joined;
  }

  /// The dishes the printed menu lists for [day], preferring [variant].
  static List<String> _dayDishes(
    Map<MenuVariant, List<MenuDay>> menus,
    MenuVariant variant,
    String day,
  ) {
    for (final candidate in <MenuVariant>[
      variant,
      MenuVariant.regular,
      MenuVariant.vegetarian,
    ]) {
      for (final menuDay in menus[candidate] ?? const <MenuDay>[]) {
        if (menuDay.day == day && menuDay.dishes.isNotEmpty) {
          return menuDay.dishes;
        }
      }
    }
    return const <String>[];
  }

  /// Joins title lines that merely wrap, using [dishes] to tell a continuation
  /// (`CHICKPEA TAGINE WITH PRESERVED` + `LEMON, CARROTS & OLIVES`) from the
  /// next dish printed on the page.
  static List<String> _titlesFor(List<String> raw, List<String> dishes) {
    if (dishes.isEmpty) return _joinWrappedTitles(raw);
    final titles = <String>[];
    var current = '';
    for (final line in raw) {
      final candidate = current.isEmpty ? line : '$current $line';
      final wanted = ShoppingItem.normalizeName(candidate);
      final isDish = dishes.any((String dish) {
        final name = ShoppingItem.normalizeName(dish);
        return name == wanted || name.startsWith(wanted);
      });
      final continues =
          current.endsWith(',') ||
          current.endsWith('-') ||
          current.endsWith('&') ||
          isDish;
      if (current.isNotEmpty && !continues) {
        titles.add(current);
        current = line;
      } else {
        current = candidate;
      }
    }
    if (current.isNotEmpty) titles.add(current);
    return titles;
  }

  static final RegExp _serves = RegExp(
    r'^Serves:?\s*(\d+)',
    caseSensitive: false,
  );

  // ---- Table rows -------------------------------------------------------

  static final RegExp _row = RegExp(
    r'^((?:Mo|Tu|We|Th|Fr|Sa|Su|M|T|W|F)(?:\s*,\s*(?:Mo|Tu|We|Th|Fr|Sa|Su|M|T|W|F))*)'
    r'\s+(.+?)\s+\$\s?(\d+(?:\.\d{1,2})?)$',
  );

  static MenuKitItem? _parseRow(String line, String section) {
    final match = _row.firstMatch(line);
    if (match == null) return null;
    final days = _days(match.group(1)!);
    final tokens = match.group(2)!.split(' ');
    final cost = (double.parse(match.group(3)!) * 100).round();

    final amountStart = _findAmountStart(tokens, 0);
    if (amountStart < 0) return null;
    final name = tokens.sublist(0, amountStart).join(' ');
    final amountEnd = _findAmountEnd(tokens, amountStart);
    final amount = tokens.sublist(amountStart, amountEnd).join(' ');
    final noteText = tokens.sublist(amountEnd).join(' ');

    return _item(
      name: name,
      amount: amount,
      note: noteText.isEmpty || noteText == '-' ? null : noteText,
      aisle: _aisleFor(section, name),
      costCents: cost,
      days: days,
    );
  }

  /// Reads the one or two `name amount` pairs of a pantry row. Returns an
  /// empty list when the line does not look like one.
  static List<MenuKitItem> _parsePantryRow(String line) {
    // The notes under the pantry table are sentences, not items.
    if (line.endsWith('.')) return const <MenuKitItem>[];
    final tokens = line.split(' ');
    if (tokens.length > 20) return const <MenuKitItem>[];
    final items = <MenuKitItem>[];
    var start = 0;
    while (start < tokens.length) {
      if (!_startsName(tokens[start])) return const <MenuKitItem>[];
      final amountStart = _findAmountStart(tokens, start);
      if (amountStart < 0) {
        // A trailing name with no amount column ("Bay leaves").
        items.add(
          _item(
            name: _trimOr(tokens.sublist(start).join(' ')),
            amount: '',
            aisle: 'Pantry',
            pantry: true,
          ),
        );
        break;
      }
      final amountEnd = _findAmountEnd(tokens, amountStart);
      items.add(
        _item(
          name: _trimOr(tokens.sublist(start, amountStart).join(' ')),
          amount: _trimOr(tokens.sublist(amountStart, amountEnd).join(' ')),
          aisle: 'Pantry',
          pantry: true,
        ),
      );
      start = amountEnd;
    }
    return items.length > 2 ? const <MenuKitItem>[] : items;
  }

  /// The older vegetarian pantry prints alternatives (`Green lentils OR`).
  static String _trimOr(String text) =>
      text.endsWith(' OR') ? text.substring(0, text.length - 3) : text;

  /// The index of the first amount token after at least one name token, or
  /// -1.
  static int _findAmountStart(List<String> tokens, int nameStart) {
    for (var i = nameStart + 1; i < tokens.length; i++) {
      if (_startsAmount(tokens[i])) return i;
    }
    return -1;
  }

  /// The index just past the amount that begins at [start].
  static int _findAmountEnd(List<String> tokens, int start) {
    if (tokens[start] == '-') return start + 1;
    var i = start + 1;
    while (i < tokens.length && !_endsAmount(tokens[i])) {
      i++;
    }
    return i;
  }

  static final RegExp _amountLead = RegExp(r'^[\d¼½¾⅓⅔⅛]');
  static const Set<String> _amountWords = <String>{
    'about',
    'as',
    'pinch',
    'approx',
    'approx.',
  };

  static bool _startsAmount(String token) =>
      token == '-' ||
      _amountLead.hasMatch(token) ||
      _amountWords.contains(token.toLowerCase());

  /// Units printed with a capital inside an amount (`2 Tablespoons`).
  static const Set<String> _unitWords = <String>{
    'tablespoon',
    'tablespoons',
    'tbsp',
    'teaspoon',
    'teaspoons',
    'tsp',
    'cup',
    'cups',
    'oz',
    'ounce',
    'ounces',
    'lb',
    'lbs',
    'pound',
    'pounds',
    'pint',
    'pints',
    'quart',
    'quarts',
    'can',
    'cans',
    'package',
    'packages',
    'bunch',
    'bunches',
    'head',
    'heads',
    'clove',
    'cloves',
    'g',
    'kg',
    'ml',
    'l',
  };

  /// Whether [token] begins the column after an amount: a `-` placeholder or a
  /// capitalized word that is not a unit.
  static bool _endsAmount(String token) {
    if (token == '-') return true;
    if (!_startsName(token)) return false;
    final bare = token.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');
    return !_unitWords.contains(bare);
  }

  static bool _startsName(String token) =>
      token != 'OR' && token.isNotEmpty && RegExp(r'^[A-ZÀ-Ý]').hasMatch(token);

  static final RegExp _plainAmount = RegExp(
    r'^[\d¼½¾⅓⅔⅛][\d¼½¾⅓⅔⅛/. ]*(?: [A-Za-z]+)?$',
  );

  /// Builds an item, keeping [amount] as a [Quantity] when it parses fully.
  static MenuKitItem _item({
    required String name,
    required String amount,
    required String aisle,
    String? note,
    int? costCents,
    List<String> days = const <String>[],
    bool pantry = false,
  }) {
    Quantity? quantity;
    String? amountText;
    if (amount.isNotEmpty && amount != '-') {
      // Only a bare `number unit` becomes a Quantity; anything with a package
      // size, range or aside keeps its printed wording so nothing is lost.
      final parsed = _plainAmount.hasMatch(amount)
          ? const IngredientParser().parseLine(amount)
          : null;
      if (parsed != null &&
          parsed.quantity != null &&
          parsed.name.trim().isEmpty) {
        quantity = parsed.quantity;
      } else {
        amountText = amount;
      }
    }
    return MenuKitItem(
      name: name,
      aisle: aisle,
      quantity: quantity,
      amountText: amountText,
      note: note,
      costCents: costCents,
      days: days,
      pantry: pantry,
    );
  }

  /// Maps a printed section to the app's aisles. Sections the app has no
  /// aisle for (`BAKERY | MISC`) fall back to the per-name guess.
  static String _aisleFor(String section, String name) {
    final upper = section.toUpperCase();
    if (upper.contains('PRODUCE')) return 'Produce';
    if (upper.contains('MEAT') ||
        upper.contains('SEAFOOD') ||
        upper.contains('FISH')) {
      return 'Meat & Fish';
    }
    if (upper.contains('DAIRY')) return 'Dairy & Eggs';
    if (upper.contains('FROZEN')) return 'Frozen';
    // A shelf-stable catch-all: trust the name only for the aisles such a
    // section holds, so `Butter beans` never lands in Dairy.
    final guess = IngredientParser.guessAisle(name);
    if (const <String>{
      'Bakery',
      'Frozen',
      'Pantry',
      'Drinks',
    }.contains(guess)) {
      return guess;
    }
    return upper.contains('BAKERY') && !upper.contains('MISC')
        ? 'Bakery'
        : 'Pantry';
  }

  static const Map<String, String> _dayCodes = <String, String>{
    'M': 'Mon',
    'MO': 'Mon',
    'T': 'Tue',
    'TU': 'Tue',
    'W': 'Wed',
    'WE': 'Wed',
    'TH': 'Thu',
    'F': 'Fri',
    'FR': 'Fri',
    'SA': 'Sat',
    'SU': 'Sun',
  };

  static List<String> _days(String codes) {
    final set = codes
        .split(',')
        .map((code) => _dayCodes[code.trim().toUpperCase()])
        .whereType<String>()
        .toSet();
    return weekdayOrder.where(set.contains).toList();
  }

  // ---- Headings ---------------------------------------------------------

  /// `MEDITERRANEAN | FALL | OCTOBER 2ND, 2026` — cuisine, season, week.
  static final RegExp _pageHeader = RegExp(
    r'^(?:(VEGETARIAN|VEGAN)\s*\|\s*)?([A-Z][A-Z &\-]+?)\s*\|\s*[A-Z]+\s*\|\s*([A-Z]+ \d{1,2}(?:ST|ND|RD|TH)?,? \d{4})$',
  );

  /// Any other all-caps running header (`MEDITERRANEAN | FALL | PATRAS,
  /// GREECE`): it starts a page that is not part of a recipe.
  static final RegExp _otherHeader = RegExp(
    r"^[A-Z][A-Z &\-]*(?: \| [A-Z0-9À-Ý ,.'\-]+){2,}$",
  );

  /// A recipe day page, in any of the printed shapes:
  /// `MEDITERRANEAN | MONDAY JUNE 16`,
  /// `MEDITERRANEAN FALL | SAMOS, GREECE | MONDAY`,
  /// `MEDITERRANEAN | TUESDAY SIDE`.
  static final RegExp _dailyHeader = RegExp(
    r'^[A-Z][A-Z &\-]*(?:\s*\|[^|]+)*\|\s*'
    r'(MONDAY|TUESDAY|WEDNESDAY|THURSDAY|FRIDAY|SATURDAY|SUNDAY)'
    r'(?:\s+[A-Z]+\s+\d{1,2})?(?:\s+SIDE)?$',
  );

  /// `MEDITERRANEAN FALL | SAMOS, GREECE | VEGETARIAN` — heads the vegetarian
  /// shopping list; the list heading itself is plain.
  static final RegExp _vegetarianListHeader = RegExp(
    r'^[A-Z][A-Z &\-]*(?:\s*\|[^|]+)*\|\s*VEGETARIAN$',
  );

  /// `MEDITERRANEAN IN SPRING | JUNE 16–20` — the older week header, which
  /// prints no year.
  static final RegExp _weekHeader = RegExp(
    r'^([A-Z][A-Z &\-]+?)\s*\|\s*'
    r'([A-Z]+ \d{1,2}(?:\s*[–-]\s*\d{1,2})?)$',
  );

  /// `MEDITERRANEAN FALL | SAMOS, GREECE` — cuisine and place, no date.
  /// Table headings (`RECIPE MEAT | SEAFOOD QTY …`) are not place headers.
  static final RegExp _placeHeader = RegExp(
    r"^(?!RECIPE\b)(?!.*\bQTY\b)([A-Z][A-Z &\-]+?)\s*\|\s*"
    r"([A-ZÀ-Ý][A-ZÀ-Ý .,'\-]+)$",
  );

  static final RegExp _place = RegExp(r"^[A-ZÀ-Ý .'\-]+, [A-ZÀ-Ý .'\-]+$");

  static final RegExp _menuHeading = RegExp(
    r'^(?:(VEGETARIAN|VEGAN|REGULAR|CLASSIC)\s+)?MENU$',
    caseSensitive: false,
  );

  /// A variant word printed on its own line, with the heading on the next one.
  static final RegExp _variantWord = RegExp(
    r'^(VEGETARIAN|VEGAN|REGULAR|CLASSIC)$',
    caseSensitive: false,
  );

  static final RegExp _listHeading = RegExp(
    r'^(?:(VEGETARIAN|VEGAN|REGULAR|CLASSIC)\s+)?SHOPPING LIST'
    r'(?::\s*(VEGETARIAN|VEGAN|REGULAR|CLASSIC))?$',
    caseSensitive: false,
  );

  /// `SHOPPING LIST: SNACKS` — a list the app does not model.
  static final RegExp _otherListHeading = RegExp(
    r'^SHOPPING LIST:\s*[A-Z]+$',
    caseSensitive: false,
  );

  /// `RECIPE PRODUCE QTY NOTES EST. COST` — group 1 is the section. The older
  /// layout prints `RECIPE #` and a trailing `*`.
  static final RegExp _sectionHeading = RegExp(
    r'^RECIPE(?: #)? (.+?) QTY NOTES EST\. ?COST(?: \*)?$',
    caseSensitive: false,
  );

  static final RegExp _pantryHeading = RegExp(
    r'^PANTRY QTY(?: PANTRY QTY)?$',
    caseSensitive: false,
  );

  static const Map<String, String> _weekday = <String, String>{
    'MONDAY': 'Mon',
    'TUESDAY': 'Tue',
    'WEDNESDAY': 'Wed',
    'THURSDAY': 'Thu',
    'FRIDAY': 'Fri',
    'SATURDAY': 'Sat',
    'SUNDAY': 'Sun',
  };

  static MenuVariant _variantOf(String? word) {
    final upper = word?.toUpperCase();
    return upper == 'VEGETARIAN' || upper == 'VEGAN'
        ? MenuVariant.vegetarian
        : MenuVariant.regular;
  }

  static const Set<String> _minorWords = <String>{
    'and',
    'or',
    'with',
    'of',
    'the',
    'a',
    'over',
    'in',
    'on',
    'de',
    'à',
    'la',
    'le',
    'au',
    'aux',
    'du',
    'des',
  };

  static String _titleCase(String text) {
    final words = text.toLowerCase().split(' ');
    return <String>[
      for (var i = 0; i < words.length; i++)
        if (words[i].isEmpty)
          words[i]
        else if (i > 0 && _minorWords.contains(words[i]))
          words[i]
        else
          words[i][0].toUpperCase() + words[i].substring(1),
    ].join(' ');
  }
}

enum _Mode {
  none,
  menu,
  table,
  pantry,
  recipeIntro,
  recipeIngredients,
  dailyIntro,
  dailyIngredients,
}

/// A recipe page while it is being read.
class _RecipePage {
  final String title;
  bool side;
  final bool vegetarianPage;

  /// The left-column text of each ingredient, wrapped lines rejoined.
  final List<String> lines = <String>[];
  int? servings;

  _RecipePage({
    required this.title,
    required this.side,
    required this.vegetarianPage,
  });

  List<ParsedIngredient> get ingredients =>
      <ParsedIngredient>[for (final line in lines) _parse(line)]
          .where((ParsedIngredient parsed) => parsed.name.isNotEmpty)
          .toList();

  /// Words a recipe lists before the ingredient itself, comma-separated
  /// (`boneless, skinless chicken thighs`).
  static const Set<String> _descriptors = <String>{
    'boneless',
    'skinless',
    'fresh',
    'large',
    'medium',
    'small',
    'ripe',
  };

  /// Parses [line], keeping a leading `boneless, skinless` with the name it
  /// describes instead of letting the comma end the name.
  static ParsedIngredient _parse(String line) {
    const parser = IngredientParser();
    final parsed = parser.parseLine(line);
    if (!_descriptors.contains(parsed.name.toLowerCase())) return parsed;
    final comma = line.indexOf(',');
    if (comma < 0) return parsed;
    return parser.parseLine(
      line.substring(0, comma) + line.substring(comma + 1),
    );
  }

  /// Takes one raw line of the two-column ingredient block.
  ///
  /// The ingredient is the text left of the column tab. A line that starts
  /// with a tab only continues the instructions; one indented with spaces
  /// continues the ingredient above it. When a long ingredient runs so close
  /// to the instructions that no tab was written, the cell ends at the first
  /// numbered step (`7.Drizzle`) or sentence break (`. Heat`).
  void addLine(String raw) {
    if (raw.replaceFirst(RegExp(r'^ +'), '').startsWith('\t')) return;
    var cell = raw.split('\t').first;
    if (!raw.contains('\t')) {
      final cut = _glued.firstMatch(cell);
      if (cut != null) cell = cell.substring(0, cut.start);
    }
    cell = cell.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (cell.isEmpty || _step.hasMatch(cell)) return;
    if (lines.isNotEmpty && (raw.startsWith(' ') || _continues(cell))) {
      lines.last = '${lines.last} $cell';
    } else {
      lines.add(cell);
    }
  }

  /// Whether [cell] carries on the ingredient above: it starts in lower case
  /// (`pieces, cook to 165°F`) or the line above stopped mid-phrase.
  bool _continues(String cell) {
    if (RegExp(r'^[a-z]').hasMatch(cell)) return true;
    final previous = lines.last;
    if (previous.endsWith(',') || previous.endsWith('-')) return true;
    return '('.allMatches(previous).length > ')'.allMatches(previous).length;
  }

  /// A numbered instruction (`1. Heat`, `2.Toss`), not an amount (`1.5 oz`).
  static final RegExp _step = RegExp(r'^\d+\.(?!\d)\s?[A-Za-z]');

  /// Where instruction text starts inside an untabbed line: a step number or
  /// a sentence break.
  static final RegExp _glued = RegExp(r'\s\d+\.(?!\d)\s?[A-Z]|\.\s+[A-Z]');
}
