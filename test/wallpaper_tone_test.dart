import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mylauncher/ui/theme/wallpaper_tone.dart';

/// The native wallpaper-colour map, as MainActivity.readWallpaperTone sends it.
Map<String, dynamic> _map({
  bool darkText = false,
  bool darkTheme = true,
  int? primary = 0xFF7962AE,
}) =>
    <String, dynamic>{
      'primary': primary,
      'secondary': 0xFFE45C3B,
      'tertiary': null,
      'supportsDarkText': darkText,
      'supportsDarkTheme': darkTheme,
    };

void main() {
  group('WallpaperTone.fromMap', () {
    test('parses the hints and colours', () {
      final WallpaperTone? tone = WallpaperTone.fromMap(_map());
      expect(tone, isNotNull);
      expect(tone!.supportsDarkText, isFalse);
      expect(tone.supportsDarkTheme, isTrue);
      expect(tone.primary, const Color(0xFF7962AE));
      expect(tone.secondary, const Color(0xFFE45C3B));
      expect(tone.tertiary, isNull);
      expect(tone.isLight, isFalse);
    });

    test('a light wallpaper is the dark-text hint', () {
      final WallpaperTone? tone =
          WallpaperTone.fromMap(_map(darkText: true, darkTheme: false));
      expect(tone!.isLight, isTrue);
    });

    test('a missing colour is null, not a malformed tone', () {
      final WallpaperTone? tone = WallpaperTone.fromMap(_map(primary: null));
      expect(tone, isNotNull);
      expect(tone!.primary, isNull);
    });

    test('garbage and missing hints are refused', () {
      expect(WallpaperTone.fromMap(null), isNull);
      expect(WallpaperTone.fromMap('nope'), isNull);
      expect(WallpaperTone.fromMap(<String, dynamic>{}), isNull);
      expect(
        WallpaperTone.fromMap(<String, dynamic>{'supportsDarkText': 'yes'}),
        isNull,
      );
    });

    test('is value-equal across separate parses', () {
      expect(WallpaperTone.fromMap(_map()), WallpaperTone.fromMap(_map()));
      expect(
        WallpaperTone.fromMap(_map()),
        isNot(WallpaperTone.fromMap(_map(darkText: true))),
      );
    });
  });
}
