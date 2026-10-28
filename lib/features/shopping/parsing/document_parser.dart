import 'ingredient_parser.dart';
import 'menu_kit_parser.dart';

/// A document interpreted as either a recipe or a plain list.
class ParsedDocument {
  final bool isRecipe;
  final String? title;
  final int? servings;
  final List<ParsedIngredient> items;

  /// Set when the text is a weekly meal-kit PDF; [items] is then empty and the
  /// kit's own shopping lists are reviewed instead.
  final MenuKit? menuKit;

  const ParsedDocument({
    required this.isRecipe,
    this.title,
    this.servings,
    this.items = const [],
    this.menuKit,
  });

  bool get isEmpty => menuKit == null && items.isEmpty;

  @override
  String toString() =>
      'ParsedDocument(recipe: $isRecipe, title: $title, servings: $servings, '
      'items: ${items.length}, menuKit: ${menuKit != null})';
}

/// Splits pasted or imported text into a [ParsedDocument].
///
/// A weekly meal-kit PDF is handed to [MenuKitParser]. Otherwise it
/// recognizes a servings line, an `Ingredients` heading that ends at the next
/// method/instructions/directions/steps/preparation heading, and otherwise
/// treats every non-empty short line as a list item. Page numbers and (in list
/// mode) lines longer than 120 characters are skipped.
class DocumentParser {
  const DocumentParser();

  ParsedDocument parseDocument(String fullText) {
    final kit = const MenuKitParser().tryParse(fullText);
    if (kit != null) {
      return ParsedDocument(isRecipe: false, title: kit.title, menuKit: kit);
    }

    const parser = IngredientParser();
    // The extractor marks wide column gaps with tabs; a plain document reads
    // them as the single space it always got.
    final lines = fullText
        .replaceAll('\t', ' ')
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .toList();

    int? servings;
    var servingsIndex = -1;
    for (var i = 0; i < lines.length; i++) {
      final parsed = _parseServings(lines[i]);
      if (parsed != null) {
        servings = parsed;
        servingsIndex = i;
        break;
      }
    }

    final headingIndex = lines.indexWhere(_isIngredientsHeading);
    final isRecipe = headingIndex >= 0 || servings != null;

    final items = <ParsedIngredient>[];
    String? title;

    if (headingIndex >= 0) {
      final endIndex = _sectionEnd(lines, headingIndex + 1);
      title = _titleBefore(lines, headingIndex, servingsIndex);
      for (var i = headingIndex + 1; i < endIndex; i++) {
        final line = lines[i];
        if (line.isEmpty || _isPageNumber(line)) continue;
        if (_isStopHeading(line)) break;
        _addParsed(items, parser.parseLine(line));
      }
    } else if (isRecipe) {
      title = _titleBefore(lines, lines.length, servingsIndex);
      for (var i = 0; i < lines.length; i++) {
        if (i == servingsIndex) continue;
        final line = lines[i];
        if (line.isEmpty || _isPageNumber(line) || _isStopHeading(line)) {
          continue;
        }
        if (title != null && line == title && items.isEmpty) continue;
        _addParsed(items, parser.parseLine(line));
      }
    } else {
      for (final line in lines) {
        if (line.isEmpty || line.length > 120 || _isPageNumber(line)) continue;
        _addParsed(items, parser.parseLine(line));
      }
    }

    return ParsedDocument(
      isRecipe: isRecipe,
      title: title,
      servings: servings,
      items: items,
    );
  }

  /// Keeps lines that name something; a bare number ("2") is dropped.
  static void _addParsed(List<ParsedIngredient> items, ParsedIngredient parsed) {
    if (parsed.name.isNotEmpty) items.add(parsed);
  }

  static int _sectionEnd(List<String> lines, int start) {
    for (var i = start; i < lines.length; i++) {
      if (_isStopHeading(lines[i])) return i;
    }
    return lines.length;
  }

  static String? _titleBefore(
    List<String> lines,
    int limit,
    int servingsIndex,
  ) {
    const parser = IngredientParser();
    for (var i = 0; i < limit; i++) {
      if (i == servingsIndex) continue;
      final line = lines[i];
      if (line.isEmpty || line.length > 120 || _isPageNumber(line)) continue;
      if (_isIngredientsHeading(line) || _isStopHeading(line)) continue;
      if (parser.parseLine(line).quantity != null) continue;
      return line;
    }
    return null;
  }

  static bool _isIngredientsHeading(String line) => RegExp(
        r'^\s*ingredients?(?:\s+list)?\s*:?\s*$',
        caseSensitive: false,
      ).hasMatch(line);

  static bool _isStopHeading(String line) => RegExp(
        r'^\s*(?:method|instructions?|directions?|steps?|preparation|prep|'
        r'notes?|nutrition|tips?)\s*:?\s*$',
        caseSensitive: false,
      ).hasMatch(line);

  static bool _isPageNumber(String line) {
    if (RegExp(
      r'^\s*(?:page\s*)?\d+\s*(?:/\s*\d+)?\s*$',
      caseSensitive: false,
    ).hasMatch(line)) {
      return true;
    }
    return RegExp(r'^\s*[-–—]?\s*\d+\s*[-–—]?\s*$').hasMatch(line);
  }

  static int? _parseServings(String line) {
    final match = RegExp(
      r'^\s*(?:serves|servings?|yield|makes?|for)\b\s*[:\-]?\s*(\d+)'
      r'(?:\s*(?:[-–—]|to)\s*(\d+))?\s*'
      r'(?:people|persons?|portions?|servings?)?\s*:?\s*$',
      caseSensitive: false,
    ).firstMatch(line);
    if (match == null) return null;
    final first = int.parse(match.group(1)!);
    final second = match.group(2);
    if (second == null) return first;
    final upper = int.parse(second);
    return upper > first ? upper : first;
  }
}
