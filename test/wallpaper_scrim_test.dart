import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mylauncher/main.dart';
import 'package:mylauncher/ui/theme/luminous_home_theme.dart';
import 'package:mylauncher/ui/widgets/wallpaper_scrim.dart';

/// Guards the wallpaper-backed home: the launcher window is transparent so the
/// system wallpaper shows through, the scrims between it and the chrome get
/// heavier on a light wallpaper, and the system chrome follows the same verdict.

void main() {
  group('WallpaperScrim', () {
    testWidgets('draws a top and a bottom gradient that ignore pointers',
        (tester) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: WallpaperScrim(),
        ),
      );

      expect(find.byType(IgnorePointer), findsOneWidget);
      final Iterable<DecoratedBox> boxes =
          tester.widgetList<DecoratedBox>(find.byType(DecoratedBox));
      expect(boxes.length, 2);
      for (final DecoratedBox box in boxes) {
        final BoxDecoration decoration = box.decoration as BoxDecoration;
        expect(decoration.gradient, isA<LinearGradient>());
        final LinearGradient gradient = decoration.gradient! as LinearGradient;
        // One end of each scrim is fully transparent: the wallpaper is never
        // dimmed across the whole screen.
        expect(gradient.colors.map((c) => c.a), contains(0.0));
      }
    });

    test('a light wallpaper gets heavier scrims than a dark one', () {
      expect(
        WallpaperScrim.topAlpha(light: true),
        greaterThan(WallpaperScrim.topAlpha(light: false)),
      );
      expect(
        WallpaperScrim.bottomAlpha(light: true),
        greaterThan(WallpaperScrim.bottomAlpha(light: false)),
      );
      // Never opaque: the wallpaper stays visible under the clock and dock.
      expect(WallpaperScrim.topAlpha(light: true), lessThan(0.8));
      expect(WallpaperScrim.bottomAlpha(light: true), lessThan(0.8));
    });
  });

  group('Wallpaper-backed theme', () {
    test('the scaffold is transparent so the wallpaper shows through', () {
      expect(LuminousHomeTheme.buildTheme().scaffoldBackgroundColor,
          Colors.transparent);
    });

    test('the type scale names no font family, so the platform font applies',
        () {
      // Material's own Typography still labels Android styles 'Roboto'; the
      // launcher's scale adds no family of its own on top of it, and the
      // engine resolves that label to the device's default sans-serif.
      expect(LuminousHomeTheme.display.fontFamily, isNull);
      expect(LuminousHomeTheme.clock.fontFamily, isNull);
      expect(LuminousHomeTheme.body.fontFamily, isNull);
      expect(LuminousHomeTheme.title.fontFamily, isNull);
    });

    test('clocks are regular weight, not hairline', () {
      expect(LuminousHomeTheme.display.fontWeight, FontWeight.w400);
      expect(LuminousHomeTheme.clock.fontWeight, FontWeight.w400);
      expect(LuminousHomeTheme.headline.fontWeight, FontWeight.w500);
      expect(LuminousHomeTheme.title.fontWeight, FontWeight.w500);
    });
  });

  group('homeOverlayStyle', () {
    test('keeps the bars transparent and flips icon brightness', () {
      final SystemUiOverlayStyle light = homeOverlayStyle(darkIcons: false);
      expect(light.statusBarColor, Colors.transparent);
      expect(light.systemNavigationBarColor, Colors.transparent);
      expect(light.statusBarIconBrightness, Brightness.light);
      expect(light.systemNavigationBarIconBrightness, Brightness.light);

      final SystemUiOverlayStyle dark = homeOverlayStyle(darkIcons: true);
      expect(dark.statusBarIconBrightness, Brightness.dark);
      expect(dark.systemNavigationBarIconBrightness, Brightness.dark);
      expect(dark.systemNavigationBarContrastEnforced, isFalse);
    });
  });

  group('Home surface', () {
    testWidgets('mounts the scrim under the galaxy', (tester) async {
      await tester.pumpWidget(
        ChronoFoldApp(isKeyguardLocked: () async => false),
      );
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byKey(const ValueKey('wallpaper_scrim')), findsOneWidget);
      // No wallpaper verdict on a test host: the default is the dark-wallpaper
      // scrim with light chrome icons.
      final WallpaperScrim scrim =
          tester.widget<WallpaperScrim>(find.byType(WallpaperScrim));
      expect(scrim.light, isFalse);
    });
  });
}
