import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mylauncher/features/lockscreen/now_playing_card.dart';
import 'package:mylauncher/models/now_playing.dart';
import 'package:mylauncher/ui/theme/luminous_home_theme.dart';
import 'package:mylauncher/ui/theme/system_palette.dart';

/// A green accent of the kind ColorOS 16 resolves from a home wallpaper,
/// measured on the device as `accent_color=FF24B232`.
const int _green = 0xFF24B232;
const Color _greenColor = Color(_green);

/// A green deep enough to stand in for tone 700.
const int _deepGreen = 0xFF14601C;

/// A tone that vanishes into the OLED field: the contrast guard must reject it.
const int _ink = 0xFF101010;

/// A full-ish accent1 ramp, with the extra tones only present when asked for.
Map<String, dynamic> _paletteMap({
  int? accent200 = _green,
  int? accent100,
  int? accent50,
  int accent700 = _deepGreen,
}) {
  final Map<String, int> accent1 = <String, int>{};
  if (accent200 != null) accent1['200'] = accent200;
  if (accent100 != null) accent1['100'] = accent100;
  if (accent50 != null) accent1['50'] = accent50;
  accent1['700'] = accent700;
  return <String, dynamic>{
    'source': 'system',
    'accent1': accent1,
    'accent2': <String, int>{'200': _green},
    'accent3': <String, int>{'200': _green},
    'neutral1': <String, int>{'200': _green},
    'neutral2': <String, int>{'200': _green},
  };
}

NowPlaying _media() => NowPlaying(
  packageName: 'com.test.music',
  appLabel: 'Music',
  title: 'Track One',
  artist: 'Artist One',
  durationMs: 180000,
  positionMs: 30000,
  state: 'paused',
);

Future<void> _pumpCard(WidgetTester tester, {Key? key}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(child: NowPlayingCard(key: key, nowPlaying: _media())),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  // The accent is global state, so every test starts and ends on the default.
  setUp(() => LuminousHomeTheme.applyPalette(null));
  tearDown(() => LuminousHomeTheme.applyPalette(null));

  group('SystemPalette.fromMap', () {
    test('parses a full palette by tone', () {
      final SystemPalette? palette = SystemPalette.fromMap(_paletteMap());
      expect(palette, isNotNull);
      expect(palette!.accent1(200), _greenColor);
      expect(palette.accent1(700), const Color(_deepGreen));
      expect(palette.accent2(200), _greenColor);
      expect(palette.accent3(200), _greenColor);
      expect(palette.neutral1(200), _greenColor);
      expect(palette.neutral2(200), _greenColor);
    });

    test('a missing tone is null, not a malformed palette', () {
      final SystemPalette? palette = SystemPalette.fromMap(
        _paletteMap(accent100: null, accent50: null),
      );
      expect(palette, isNotNull);
      expect(palette!.accent1(100), isNull);
      expect(palette.accent1(50), isNull);
      expect(palette.accent1(200), _greenColor);
    });

    test('garbage is refused', () {
      expect(SystemPalette.fromMap(null), isNull);
      expect(SystemPalette.fromMap('not a map'), isNull);
      expect(SystemPalette.fromMap(<String, dynamic>{}), isNull);
      expect(SystemPalette.fromMap(<String, dynamic>{'accent1': 'nope'}), isNull);
      expect(
        SystemPalette.fromMap(<String, dynamic>{
          'accent1': <String, dynamic>{},
        }),
        isNull,
      );
      // No accent1 at all: nothing to theme from, even with the other groups.
      expect(
        SystemPalette.fromMap(<String, dynamic>{
          'accent2': <String, int>{'200': _green},
        }),
        isNull,
      );
    });

    test('is value-equal across separate parses', () {
      expect(
        SystemPalette.fromMap(_paletteMap()),
        SystemPalette.fromMap(_paletteMap()),
      );
      expect(
        SystemPalette.fromMap(_paletteMap()),
        isNot(SystemPalette.fromMap(_paletteMap(accent200: _ink))),
      );
    });
  });

  group('LuminousHomeTheme.applyPalette', () {
    test('picks tone 200 and its tone 700 deep companion', () {
      LuminousHomeTheme.applyPalette(SystemPalette.fromMap(_paletteMap()));
      expect(LuminousHomeTheme.accent, _greenColor);
      expect(LuminousHomeTheme.accentDeep, const Color(_deepGreen));
    });

    test('null restores the aqua fallback', () {
      LuminousHomeTheme.applyPalette(SystemPalette.fromMap(_paletteMap()));
      expect(LuminousHomeTheme.accent, _greenColor);

      LuminousHomeTheme.applyPalette(null);
      expect(LuminousHomeTheme.accent, LuminousHomeTheme.aqua);
      expect(LuminousHomeTheme.accentDeep, LuminousHomeTheme.aquaDeep);
    });

    test('a tone too dark for the field steps down to tone 100', () {
      LuminousHomeTheme.applyPalette(
        SystemPalette.fromMap(_paletteMap(accent200: _ink, accent100: _green)),
      );
      expect(LuminousHomeTheme.accent, _greenColor);
    });

    test('200 and 100 too dark step again to tone 50', () {
      LuminousHomeTheme.applyPalette(
        SystemPalette.fromMap(
          _paletteMap(accent200: _ink, accent100: _ink, accent50: _green),
        ),
      );
      expect(LuminousHomeTheme.accent, _greenColor);
    });

    test('every tone too dark keeps aqua', () {
      LuminousHomeTheme.applyPalette(
        SystemPalette.fromMap(
          _paletteMap(accent200: _ink, accent100: _ink, accent50: _ink),
        ),
      );
      expect(LuminousHomeTheme.accent, LuminousHomeTheme.aqua);
      expect(LuminousHomeTheme.accentDeep, LuminousHomeTheme.aquaDeep);
    });
  });

  group('paletteRevision', () {
    test('bumps on a real change and holds on a repeat', () {
      LuminousHomeTheme.applyPalette(null);
      final int base = LuminousHomeTheme.paletteRevision;

      final SystemPalette green = SystemPalette.fromMap(_paletteMap())!;
      LuminousHomeTheme.applyPalette(green);
      expect(LuminousHomeTheme.paletteRevision, base + 1);

      // The same palette, and an equal-but-new one, must both be no-ops.
      LuminousHomeTheme.applyPalette(green);
      LuminousHomeTheme.applyPalette(SystemPalette.fromMap(_paletteMap()));
      expect(LuminousHomeTheme.paletteRevision, base + 1);

      LuminousHomeTheme.applyPalette(null);
      expect(LuminousHomeTheme.paletteRevision, base + 2);
    });
  });

  testWidgets('an accent consumer follows the applied palette', (tester) async {
    LuminousHomeTheme.applyPalette(SystemPalette.fromMap(_paletteMap()));
    await _pumpCard(tester);

    LinearProgressIndicator progress() =>
        tester.widget<LinearProgressIndicator>(
          find.byType(LinearProgressIndicator),
        );
    expect(progress().color, _greenColor);
    expect(progress().color, LuminousHomeTheme.accent);

    // A withdrawn palette returns the card to aqua on the next rebuild.
    LuminousHomeTheme.applyPalette(null);
    await _pumpCard(tester, key: const ValueKey<String>('after-reset'));
    expect(progress().color, LuminousHomeTheme.aqua);
  });
}
