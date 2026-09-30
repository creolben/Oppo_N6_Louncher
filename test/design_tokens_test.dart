import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The theme file is the single source of truth for colour.
///
/// These guards walk `lib/` and fail if any other file writes a raw colour, so
/// the next round can re-colour the whole launcher by editing
/// `lib/ui/theme/luminous_home_theme.dart` alone.
void main() {
  const String themePath = 'lib/ui/theme/luminous_home_theme.dart';

  List<String> offenders(RegExp pattern) {
    final Directory dir = Directory('lib');
    expect(dir.existsSync(), isTrue, reason: 'run the suite from the project root');
    final List<String> hits = <String>[];
    for (final FileSystemEntity entity in dir.listSync(recursive: true)) {
      if (entity is! File) continue;
      final String path = entity.path.replaceAll('\\', '/');
      if (!path.endsWith('.dart')) continue;
      if (path.endsWith(themePath)) continue;
      final RegExpMatch? match = pattern.firstMatch(entity.readAsStringSync());
      if (match != null) {
        hits.add('$path contains `${match.group(0)}`');
      }
    }
    return hits;
  }

  test('only the theme file writes raw colour literals', () {
    final List<String> hits = offenders(
      RegExp(r'Color\(0x|Color\.fromARGB\(|Color\.fromRGBO\('),
    );
    expect(hits, isEmpty, reason: hits.join('\n'));
  });

  test('only the theme file names Material white or black', () {
    final List<String> hits = offenders(RegExp(r'Colors\.(white|black)[0-9]*\b'));
    expect(hits, isEmpty, reason: hits.join('\n'));
  });
}
