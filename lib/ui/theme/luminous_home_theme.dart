import 'package:flutter/material.dart';

import '../../models/app_entry.dart';

/// The galaxy constellation palette: a primary glow, a secondary tone, and the
/// translucent halo. Returned by [LuminousHomeTheme.constellationPalette].
typedef ConstellationPalette = ({Color primary, Color secondary, Color glow});

/// Shared visual language for ChronoFold's ColorOS-inspired home surfaces.
///
/// This is intentionally an original theme rather than a copy of OEM assets.
/// Its fluid light, tonal glass, generous shapes, and quiet typography sit
/// comfortably beside ColorOS while ChronoFold keeps its own spatial motion.
///
/// This file is the only place a colour value is written. Every surface takes
/// its colours from here by semantic name, so a future dynamic-colour round can
/// re-colour the launcher by changing this file alone.
abstract final class LuminousHomeTheme {
  // Ink-blue OLED field.
  static const Color background = Color(0xFF050A16);
  static const Color backgroundTop = Color(0xFF0A1830);
  static const Color backgroundRaised = Color(0xFF111C31);
  static const Color backgroundDeep = Color(0xFF020711);

  // Luminous horizon palette.
  static const Color cobalt = Color(0xFF6487FF);
  static const Color aqua = Color(0xFF70D9FF);
  static const Color mint = Color(0xFF69E5C2);
  static const Color orchid = Color(0xFFB6A1FF);
  static const Color rose = Color(0xFFFF8FAB);
  static const Color amber = Color(0xFFFFD27A);

  // Tonal glass. Alpha is part of the role so every surface stacks the same.
  static const Color glass = Color(0x1FFFFFFF);
  static const Color glassStrong = Color(0x33FFFFFF);
  static const Color glassOpaque = Color(0xE810192A);
  static const Color glassOpaqueStrong = Color(0xF0141F34);
  static const Color hairline = Color(0x2EFFFFFF);
  static const Color hairlineStrong = Color(0x52FFFFFF);

  static const Color textPrimary = Color(0xFFF7FAFF);
  static const Color textSecondary = Color(0xC7DDE8F7);
  static const Color textMuted = Color(0x91C8D5E8);
  static const Color shadow = Color(0x7A00040C);
  static const Color notification = Color(0xFFFF526B);

  // The lock surface's own field. It is a deeper, quieter version of the home
  // background because the lock screen is seen at night, at low brightness, and
  // must not compete with the clock.
  static const Color lockFieldGlow = Color(0xFF0D1426);
  static const Color lockField = Color(0xFF070A14);
  static const Color lockFieldDeep = Color(0xFF020306);

  // Ambient bubble shells. Kept here rather than in the painter so the palette
  // stays in one place; the sphere reads as one glass object, not three colours.
  static const Color bubbleShellTop = Color(0xFF1E2846);
  static const Color bubbleShellMid = Color(0xFF0D1426);
  static const Color bubbleShellDeep = Color(0xFF050814);

  // ── Pure roles ────────────────────────────────────────────────────────────
  /// Un-toned white, for the rare glyph that must stay neutral.
  static const Color white = Color(0xFFFFFFFF);

  /// Un-toned black, for shadows and contrast plates.
  static const Color black = Color(0xFF000000);

  // The Material white alphas, kept as named roles so the values survive in
  // `const` constructors.
  static const Color white70 = Color(0xB3FFFFFF);
  static const Color white60 = Color(0x99FFFFFF);
  static const Color white54 = Color(0x8AFFFFFF);
  static const Color white38 = Color(0x62FFFFFF);
  static const Color white24 = Color(0x3DFFFFFF);
  static const Color white12 = Color(0x1FFFFFFF);

  /// A black scrim for sheets that float over the galaxy.
  static const Color blackScrim = Color(0x99000000);

  // ── Category accents ──────────────────────────────────────────────────────
  // One flat colour per app category, used for chips, badges and galaxy nodes.
  static const Color accentCore = Color(0xFFFFD54F);
  static const Color accentSocial = Color(0xFFF06292);
  static const Color accentProductivity = Color(0xFF4DD0E1);
  static const Color accentEntertainment = Color(0xFF81C784);
  static const Color accentTools = Color(0xFFFFB74D);
  static const Color accentGames = Color(0xFFBA68C8);

  /// The flat accent for an app category.
  static Color categoryAccent(AppCategory category) {
    switch (category) {
      case AppCategory.core:
        return accentCore;
      case AppCategory.social:
        return accentSocial;
      case AppCategory.productivity:
        return accentProductivity;
      case AppCategory.entertainment:
        return accentEntertainment;
      case AppCategory.tools:
        return accentTools;
      case AppCategory.games:
        return accentGames;
    }
  }

  // ── Constellation palette ─────────────────────────────────────────────────
  // The richer three-stop palette the galaxy canvas and its editor use. It is
  // deliberately distinct from the flat category accents above: the two are not
  // interchangeable in the current art direction.
  static const Color constellationCore = Color(0xFFFFD54F);
  static const Color constellationCoreSecondary = Color(0xFFFF9800);
  static const Color constellationCoreGlow = Color(0x66FFD54F);
  static const Color constellationSocial = Color(0xFFFF4081);
  static const Color constellationSocialSecondary = Color(0xFFE040FB);
  static const Color constellationSocialGlow = Color(0x55FF4081);
  // The bright `#00E5FF` cyan consolidated onto [aqua]; the glow follows it.
  static const Color constellationProductivity = aqua;
  static const Color constellationProductivitySecondary = Color(0xFF2979FF);
  static const Color constellationProductivityGlow = Color(0x5570D9FF);
  static const Color constellationEntertainment = Color(0xFF00E676);
  static const Color constellationEntertainmentSecondary = Color(0xFF1DE9B6);
  static const Color constellationEntertainmentGlow = Color(0x5500E676);
  static const Color constellationTools = Color(0xFFFFAB00);
  static const Color constellationToolsSecondary = Color(0xFFFF6D00);
  static const Color constellationToolsGlow = Color(0x55FFAB00);

  /// The three-stop palette for a constellation of [category].
  static ConstellationPalette constellationPalette(AppCategory category) {
    switch (category) {
      case AppCategory.core:
        return (
          primary: constellationCore,
          secondary: constellationCoreSecondary,
          glow: constellationCoreGlow,
        );
      case AppCategory.social:
        return (
          primary: constellationSocial,
          secondary: constellationSocialSecondary,
          glow: constellationSocialGlow,
        );
      case AppCategory.productivity:
        return (
          primary: constellationProductivity,
          secondary: constellationProductivitySecondary,
          glow: constellationProductivityGlow,
        );
      case AppCategory.entertainment:
        return (
          primary: constellationEntertainment,
          secondary: constellationEntertainmentSecondary,
          glow: constellationEntertainmentGlow,
        );
      case AppCategory.tools:
        return (
          primary: constellationTools,
          secondary: constellationToolsSecondary,
          glow: constellationToolsGlow,
        );
      case AppCategory.games:
        return (
          primary: accentGames,
          secondary: constellationSocialSecondary,
          glow: constellationSocialGlow,
        );
    }
  }

  // ── Galaxy canvas roles ───────────────────────────────────────────────────
  static const Color starDiamond = white;
  static const Color starIcy = Color(0xFFB3E5FC);
  static const Color starGold = Color(0xFFFFE082);
  static const Color starRose = Color(0xFFFF80AB);
  static const Color starViolet = Color(0xFFE1BEE7);
  static const Color starBlue = Color(0xFF80D8FF);

  /// The field's distant/mid/beacon star tints.
  static const List<Color> starfieldColors = [
    starDiamond,
    starIcy,
    starGold,
    starRose,
    starViolet,
    starBlue,
  ];

  /// The shooting-star tints. The pale mint merged into [mint].
  static const List<Color> meteorColors = [
    starDiamond,
    starBlue,
    accentCore,
    mint,
  ];

  // ── Warm accents (search, answers, the comet) ─────────────────────────────
  static const Color ember = Color(0xFFFFB300);
  static const Color emberDeep = Color(0xFFFF6F00);
  static const Color emberHot = Color(0xFFFFF3D6);
  static const Color emberLight = Color(0xFFFFC64D);
  static const Color emberGlow = Color(0x33FFB300);
  static const Color emberFaint = Color(0x1AFFB300);

  /// The cool border tint shared by search capsules and the comet.
  static const Color borderCool = Color(0xFF64B5F6);

  // ── Panels, modals and sheets ─────────────────────────────────────────────
  static const Color panelDeep = Color(0xFF0B0E1E);
  static const Color panel = Color(0xFF101424);
  static const Color panelRaised = Color(0xFF161B30);
  static const Color glassCool = Color(0xFF141A30);
  static const Color glassPanel = Color(0xFF101528);
  static const Color nodeFill = Color(0xFF0F1424);

  /// The modal backdrop used by every editor sheet.
  static const Color panelScrim = Color(0xEE0B0E1E);

  /// The app-search overlay scrim.
  static const Color scrim = Color(0xCC04060E);

  /// A faint blue info fill.
  static const Color infoFill = Color(0x1418BFEA);

  /// A hairline divider on a dark panel.
  static const Color dividerFaint = Color(0x22FFFFFF);

  /// The recessed fill behind a search field.
  static const Color fieldFill = Color(0x330C1020);

  // ── Danger / status ───────────────────────────────────────────────────────
  static const Color danger = Color(0xFFFF5252);
  static const Color dangerDeep = Color(0xFFFF3B5C);
  static const Color dangerDeepGlow = Color(0x66FF3B5C);

  // ── Lock-surface glass ────────────────────────────────────────────────────
  static const Color lockGlassTop = Color(0xF20D1426);
  static const Color lockGlassDeep = Color(0xF2070A14);

  /// The cold barrier behind a lock-owned route.
  static const Color lockScrim = Color(0xC8020306);

  // ── Translucent aqua roles ────────────────────────────────────────────────
  // The `#00E5FF` family collapsed onto [aqua]; these keep the alpha steps it
  // used in constructors that must stay `const`.
  static const Color aquaFaint = Color(0x1870D9FF);
  static const Color aquaSoft = Color(0x2270D9FF);
  static const Color aquaGlow = Color(0x3370D9FF);
  static const Color aquaMid = Color(0x4470D9FF);
  static const Color aquaBright = Color(0x5570D9FF);
  static const Color aquaStrong = Color(0x6670D9FF);

  /// A deeper cyan, one step under [aqua].
  static const Color aquaDeep = Color(0xFF00B8D4);

  // ── Ambient wallpaper preview ─────────────────────────────────────────────
  static const Color wallpaperTop = Color(0xFF111B37);
  static const Color wallpaperMid = Color(0xFF060914);
  static const Color wallpaperDeep = Color(0xFF010204);
  static const Color wallpaperNebula = Color(0xFF5830AF);
  static const Color wallpaperNebulaCool = Color(0xFF007D9F);
  static const Color wallpaperStar = Color(0xFFE9F8FF);
  static const Color wallpaperCore = accentCore;
  static const Color wallpaperCoreDeep = Color(0xFFFF8A00);
  static const Color wallpaperOrbit = borderCool;
  static const Color wallpaperAurora = Color(0xFF8DEBFF);
  static const Color wallpaperHorizon = Color(0xFFFFF7D2);
  static const Color wallpaperHorizonDeep = ember;
  static const Color wallpaperHorizonMid = Color(0xFF10172B);
  static const Color wallpaperViolet = Color(0xFFB388FF);

  // ── Constellation editor swatches ─────────────────────────────────────────
  static const Color paletteAzure = Color(0xFF40C4FF);
  static const Color accentCoreGlow = Color(0x33FFD54F);

  // ── Mock-app brand accents ────────────────────────────────────────────────
  // The sample galaxy's per-app tints. Real apps bring their own palette from
  // the platform, but the first-run field has to look right too.
  static const Color brandWhatsapp = Color(0xFF25D366);
  static const Color brandDiscord = Color(0xFF7289DA);
  static const Color brandInstagram = Color(0xFFE1306C);
  static const Color brandTelegram = Color(0xFF29B6F6);
  static const Color brandGmail = Color(0xFFEA4335);
  static const Color brandGoogleBlue = Color(0xFF4285F4);
  static const Color brandNotion = Color(0xFFE0E0E0);
  static const Color brandSlack = Color(0xFF4A154B);
  static const Color brandGithub = Color(0xFF80CBC4);
  static const Color brandSpotify = Color(0xFF1DB954);
  static const Color brandYoutube = Color(0xFFFF0000);
  static const Color brandNetflix = Color(0xFFE50914);
  static const Color brandPhotos = Color(0xFFFBBC05);
  static const Color brandClock = Color(0xFF26A69A);
  static const Color brandCalculator = Color(0xFFFFA726);
  static const Color brandSettings = Color(0xFF78909C);
  static const Color brandMaps = Color(0xFF34A853);
  static const Color brandFiles = Color(0xFF42A5F5);

  // ── Geometry ──────────────────────────────────────────────────────────────
  static const double screenGutter = 20;
  static const double cardRadius = 28;
  static const double controlRadius = 18;
  static const double iconRadius = 16;
  static const double dockRadius = 32;
  static const double glassBlur = 24;
  static const double minimumTouchTarget = 48;

  // Spacing steps that already repeat across three or more surfaces.
  static const double space4 = 4;
  static const double space8 = 8;
  static const double space12 = 12;
  static const double space16 = 16;
  static const double space24 = 24;

  // ── Type scale ────────────────────────────────────────────────────────────
  // Base styles only. Widgets keep applying `MediaQuery.textScalerOf(context)`,
  // so these are safe to reuse at any scale.
  static TextStyle get display => const TextStyle(
    color: textPrimary,
    fontSize: 52,
    fontWeight: FontWeight.w300,
    letterSpacing: -2.0,
    height: 1.0,
  );

  static TextStyle get title => const TextStyle(
    color: textPrimary,
    fontSize: 16,
    fontWeight: FontWeight.w600,
  );

  static TextStyle get body => const TextStyle(
    color: textSecondary,
    fontSize: 14,
    fontWeight: FontWeight.w400,
  );

  static TextStyle get label => const TextStyle(
    color: textPrimary,
    fontSize: 13,
    fontWeight: FontWeight.w600,
  );

  static TextStyle get caption => const TextStyle(
    color: textSecondary,
    fontSize: 11,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.2,
  );

  static const List<BoxShadow> floatingShadow = [
    BoxShadow(color: shadow, blurRadius: 28, offset: Offset(0, 12)),
    BoxShadow(color: Color(0x143A6EA8), blurRadius: 18, offset: Offset(0, 4)),
  ];

  static Color softTint(Color accent, [double alpha = 0.14]) {
    return Color.lerp(Colors.transparent, accent, alpha) ??
        accent.withValues(alpha: alpha);
  }

  static ThemeData buildTheme() {
    const scheme = ColorScheme.dark(
      primary: aqua,
      onPrimary: backgroundDeep,
      secondary: mint,
      onSecondary: backgroundDeep,
      error: notification,
      onError: white,
      surface: backgroundRaised,
      onSurface: textPrimary,
      outline: hairlineStrong,
    );

    return ThemeData(
      brightness: Brightness.dark,
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      canvasColor: background,
      fontFamily: 'Roboto',
      splashColor: white.withValues(alpha: 0.08),
      highlightColor: white.withValues(alpha: 0.04),
      dividerColor: hairline,
      iconTheme: const IconThemeData(color: textSecondary),
      textTheme: const TextTheme(
        displayLarge: TextStyle(
          color: textPrimary,
          fontSize: 52,
          fontWeight: FontWeight.w300,
          letterSpacing: -2.0,
          height: 1.0,
        ),
        headlineLarge: TextStyle(
          color: textPrimary,
          fontSize: 32,
          fontWeight: FontWeight.w400,
          letterSpacing: -0.8,
        ),
        titleMedium: TextStyle(
          color: textPrimary,
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
        bodyMedium: TextStyle(
          color: textSecondary,
          fontSize: 14,
          fontWeight: FontWeight.w400,
        ),
        labelLarge: TextStyle(
          color: textPrimary,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
        labelMedium: TextStyle(
          color: textSecondary,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
        ),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: glassOpaqueStrong,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: hairline),
        ),
        textStyle: const TextStyle(
          color: textPrimary,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: glassOpaqueStrong,
        contentTextStyle: const TextStyle(color: textPrimary),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(controlRadius),
          side: const BorderSide(color: hairline),
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
