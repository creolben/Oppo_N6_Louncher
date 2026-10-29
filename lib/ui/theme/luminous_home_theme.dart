import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/app_entry.dart';
import 'system_palette.dart';

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
  // Ink-blue OLED field. Since the launcher window shows the system wallpaper
  // these are no longer painted edge to edge; they remain the ink the lock
  // surface, the scrims and the fallback panel roles are mixed from.
  static const Color background = Color(0xFF050A16);
  static const Color backgroundTop = Color(0xFF0A1830);
  static const Color backgroundDeep = Color(0xFF020711);

  /// The raised node fill when no system palette exists; see [backgroundRaised].
  static const Color _backgroundRaisedInk = Color(0xFF111C31);

  // Luminous horizon palette.
  static const Color cobalt = Color(0xFF6487FF);
  static const Color aqua = Color(0xFF70D9FF);
  static const Color mint = Color(0xFF69E5C2);
  static const Color orchid = Color(0xFFB6A1FF);
  static const Color rose = Color(0xFFFF8FAB);
  static const Color amber = Color(0xFFFFD27A);

  // Tonal glass. Alpha is part of the role so every surface stacks the same.
  // The white glass stays white: over a wallpaper, that is the ColorOS
  // material. The opaque glass and the hairlines are tonal roles that follow
  // the device's neutral ramp; their ink fallbacks live below.
  static const Color glass = Color(0x1FFFFFFF);
  static const Color glassStrong = Color(0x33FFFFFF);
  static const Color _glassOpaqueInk = Color(0xE810192A);
  static const Color _glassOpaqueStrongInk = Color(0xF0141F34);
  static const Color _hairlineInk = Color(0x2EFFFFFF);
  static const Color _hairlineStrongInk = Color(0x52FFFFFF);

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
  // The ink fallbacks for the tonal panel roles. The live values are the
  // `panel*`, `glass*`, `nodeFill` and `hairline*` getters further down, which
  // [applyPalette] re-derives from the Material You neutral ramps so a sheet
  // sits beside a ColorOS panel in the same tint.
  static const Color _panelDeepInk = Color(0xFF0B0E1E);
  static const Color _panelInk = Color(0xFF101424);
  static const Color _panelRaisedInk = Color(0xFF161B30);
  static const Color _glassCoolInk = Color(0xFF141A30);
  static const Color _glassPanelInk = Color(0xFF101528);
  static const Color _nodeFillInk = Color(0xFF0F1424);
  static const Color _panelScrimInk = Color(0xEE0B0E1E);

  /// The app-search overlay scrim. The alpha matches ColorOS
  /// `coui_color_mask_dark` (`#99000000`): 60% over the galaxy instead of the
  /// older 80%, so the field stays present behind search while the blur keeps
  /// the text legible.
  static const Color scrim = Color(0x9904060E);

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

  // ── Grocery roles ─────────────────────────────────────────────────────────
  // The shopping list's accent family: mint, the cool sibling of the warm
  // search/comet amber, so the grocery surface reads as its own place while
  // staying inside the Luminous language. The alpha ladder mirrors
  // [aquaFaint]..[aquaStrong] so every grocery surface stacks the same way.
  static const Color groceryAccent = mint;
  static const Color groceryFaint = Color(0x1869E5C2);
  static const Color grocerySoft = Color(0x2269E5C2);
  static const Color groceryGlow = Color(0x3369E5C2);
  static const Color groceryMid = Color(0x4469E5C2);
  static const Color groceryBright = Color(0x5569E5C2);
  static const Color groceryStrong = Color(0x6669E5C2);

  // ── Dynamic accent ────────────────────────────────────────────────────────
  // The one family that follows the device's Material You palette. Everything
  // else above stays a fixed ChronoFold colour so the launcher keeps its
  // identity under any accent. [aqua] and its alphas remain the fallback and
  // the art colour; the `accent*` getters are the role.
  static Color _accent = aqua;
  static Color _accentDeep = aquaDeep;
  static int _paletteRevision = 0;

  // The tonal surface roles, seeded with the ink fallbacks.
  static Color _panelDeep = _panelDeepInk;
  static Color _panel = _panelInk;
  static Color _panelRaised = _panelRaisedInk;
  static Color _glassCool = _glassCoolInk;
  static Color _glassPanel = _glassPanelInk;
  static Color _nodeFill = _nodeFillInk;
  static Color _panelScrim = _panelScrimInk;
  static Color _backgroundRaised = _backgroundRaisedInk;
  static Color _glassOpaque = _glassOpaqueInk;
  static Color _glassOpaqueStrong = _glassOpaqueStrongInk;
  static Color _hairline = _hairlineInk;
  static Color _hairlineStrong = _hairlineStrongInk;
  static Color _wallpaperScrim = backgroundDeep;

  // ── Tonal surfaces ────────────────────────────────────────────────────────
  // Material You's neutral ramps, when the platform has them. ColorOS tints
  // its own sheets, folders and dock from the same ramps, so a ChronoFold
  // panel beside a system panel shares its hue instead of staying navy.

  /// The deepest sheet surface (dialog and editor bodies).
  static Color get panelDeep => _panelDeep;

  /// The standard sheet surface.
  static Color get panel => _panel;

  /// A sheet surface one step up, for raised cards inside a sheet.
  static Color get panelRaised => _panelRaised;

  /// The cool glass behind search capsules and the comet.
  static Color get glassCool => _glassCool;

  /// The glass panel behind grouped controls.
  static Color get glassPanel => _glassPanel;

  /// The galaxy node body.
  static Color get nodeFill => _nodeFill;

  /// The modal backdrop used by every editor sheet.
  static Color get panelScrim => _panelScrim;

  /// The raised node highlight.
  static Color get backgroundRaised => _backgroundRaised;

  /// Near-opaque glass for tooltips, chips and the dock.
  static Color get glassOpaque => _glassOpaque;

  /// The strongest opaque glass, for snackbars and popups.
  static Color get glassOpaqueStrong => _glassOpaqueStrong;

  /// The one-pixel border on glass.
  static Color get hairline => _hairline;

  /// A stronger border, for focused or selected glass.
  static Color get hairlineStrong => _hairlineStrong;

  /// The ink the home scrims are mixed from. The scrims sit between the
  /// system wallpaper and the clock, labels and dock; see `WallpaperScrim`.
  static Color get wallpaperScrim => _wallpaperScrim;

  /// The launcher's current accent: the system's Material You primary, or
  /// [aqua] when the platform has none or its tone is too dark to read.
  static Color get accent => _accent;

  /// A deeper companion to [accent], for pressed and gradient states.
  static Color get accentDeep => _accentDeep;

  static Color get accentFaint => _accent.withValues(alpha: 0x18 / 255);
  static Color get accentSoft => _accent.withValues(alpha: 0x22 / 255);
  static Color get accentGlow => _accent.withValues(alpha: 0x33 / 255);
  static Color get accentMid => _accent.withValues(alpha: 0x44 / 255);
  static Color get accentBright => _accent.withValues(alpha: 0x55 / 255);
  static Color get accentStrong => _accent.withValues(alpha: 0x66 / 255);

  /// Bumps only when [applyPalette] actually changes [accent]/[accentDeep].
  ///
  /// `MaterialApp` keys off this so a palette push remounts the tree and every
  /// widget re-reads the accent instead of keeping a cached `Color`.
  static int get paletteRevision => _paletteRevision;

  /// Applies [palette] as the accent family and the tonal surface roles, or
  /// restores the aqua accent and the ink surfaces when it is null.
  ///
  /// The Material dark-theme primary is tone 200; if that is below 3.0:1 on the
  /// OLED field the guard walks to tone 100 and then 50, and only then keeps
  /// [aqua]. The step exists because a wallpaper-derived tone can be almost the
  /// field's own ink and vanish as a focus ring.
  ///
  /// The surfaces come from the neutral ramps: `neutral1` tone 900 is the
  /// Material dark surface and tone 800 its raised container; `neutral2`
  /// tone 200 is the outline. They are mixed toward black so the launcher keeps
  /// its depth while taking the wallpaper's hue, the way ColorOS tints its own
  /// sheets. A palette without a tone-900 neutral keeps the ink surfaces.
  static void applyPalette(SystemPalette? palette) {
    Color nextAccent = aqua;
    Color nextDeep = aquaDeep;
    String source = 'fallback';

    if (palette != null) {
      final List<Color?> candidates = <Color?>[
        palette.accent1(200),
        palette.accent1(100),
        palette.accent1(50),
      ];
      for (final Color? candidate in candidates) {
        if (candidate != null && _contrast(candidate, background) >= 3.0) {
          nextAccent = candidate;
          nextDeep = palette.accent1(700) ?? aquaDeep;
          source = 'system';
          break;
        }
      }
    }

    final _TonalSurfaces surfaces = _TonalSurfaces.from(palette);

    final bool accentChanged =
        nextAccent != _accent || nextDeep != _accentDeep;
    final bool surfacesChanged = surfaces.panelDeep != _panelDeep ||
        surfaces.panel != _panel ||
        surfaces.panelRaised != _panelRaised ||
        surfaces.glassCool != _glassCool ||
        surfaces.glassPanel != _glassPanel ||
        surfaces.nodeFill != _nodeFill ||
        surfaces.panelScrim != _panelScrim ||
        surfaces.backgroundRaised != _backgroundRaised ||
        surfaces.glassOpaque != _glassOpaque ||
        surfaces.glassOpaqueStrong != _glassOpaqueStrong ||
        surfaces.hairline != _hairline ||
        surfaces.hairlineStrong != _hairlineStrong ||
        surfaces.wallpaperScrim != _wallpaperScrim;
    if (!accentChanged && !surfacesChanged) return;

    _accent = nextAccent;
    _accentDeep = nextDeep;
    _panelDeep = surfaces.panelDeep;
    _panel = surfaces.panel;
    _panelRaised = surfaces.panelRaised;
    _glassCool = surfaces.glassCool;
    _glassPanel = surfaces.glassPanel;
    _nodeFill = surfaces.nodeFill;
    _panelScrim = surfaces.panelScrim;
    _backgroundRaised = surfaces.backgroundRaised;
    _glassOpaque = surfaces.glassOpaque;
    _glassOpaqueStrong = surfaces.glassOpaqueStrong;
    _hairline = surfaces.hairline;
    _hairlineStrong = surfaces.hairlineStrong;
    _wallpaperScrim = surfaces.wallpaperScrim;
    _paletteRevision++;
    debugPrint(
      'CF_THEME: palette applied accent=#${_hex(nextAccent)} '
      'panel=#${_hex(surfaces.panel)} source=$source',
    );
  }

  /// WCAG relative-luminance contrast between two opaque colours.
  static double _contrast(Color a, Color b) {
    final double la = a.computeLuminance();
    final double lb = b.computeLuminance();
    final double hi = math.max(la, lb);
    final double lo = math.min(la, lb);
    return (hi + 0.05) / (lo + 0.05);
  }

  /// `RRGGBB` for logging, matching how the device reported the source accent.
  static String _hex(Color color) =>
      (color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0');

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

  // ── Motion (ColorOS coui) ──────────────────────────────────────────────────
  // Curves and durations measured from ColorOS 16's decoded resources and named
  // after the coui tokens they come from. They replace Material's overshoot
  // curves on launcher chrome so panels settle the way the system launcher's
  // do. Galaxy motion keeps its own curves; only chrome uses these.
  /// `coui_ease`: the standard fade curve for opacity.
  static const Cubic easeStandard = Cubic(0.33, 0.0, 0.67, 1.0);

  /// `coui_ease_move`: the decelerating curve for surfaces that move or enter.
  static const Cubic easeMove = Cubic(0.3, 0.0, 0.1, 1.0);

  /// `android_alert_dialog_exit`: the accelerated curve a dialog leaves on.
  static const Cubic easeExit = Cubic(0.3, 0.0, 1.0, 1.0);

  /// ColorOS `coui_animation_time_moment` (100 ms): an immediate state flash.
  static const Duration motionMoment = Duration(milliseconds: 100);

  /// ColorOS `coui_animation_time_move_veryfast` (200 ms): a small state change.
  static const Duration motionFast = Duration(milliseconds: 200);

  /// ColorOS `coui_animation_time_move_fast` (240 ms): a content fade.
  static const Duration motionShort = Duration(milliseconds: 240);

  /// ColorOS `coui_animation_time_move` (330 ms): a surface that travels.
  static const Duration motionMove = Duration(milliseconds: 330);

  /// ColorOS `coui_open_panel_fragment_enter` (350 ms): a panel or dialog entering.
  static const Duration motionPanel = Duration(milliseconds: 350);

  /// ColorOS `coui_open_panel_fragment_exit` (150 ms): a panel or dialog leaving.
  static const Duration motionPanelExit = Duration(milliseconds: 150);

  /// ColorOS `coui_animation_time_move_slow` (420 ms): a large, deliberate transition.
  static const Duration motionSlow = Duration(milliseconds: 420);

  /// Returns [d], or [Duration.zero] when the platform asks for reduced motion.
  ///
  /// Every chrome animation routes its duration through here so the system
  /// "Remove animations" preference is honoured in one place.
  static Duration motion(BuildContext context, Duration d) =>
      MediaQuery.disableAnimationsOf(context) ? Duration.zero : d;

  // ── Geometry ──────────────────────────────────────────────────────────────
  static const double screenGutter = 20;
  static const double cardRadius = 28;
  static const double controlRadius = 18;
  static const double iconRadius = 16;
  static const double dockRadius = 32;

  // ColorOS os17 round-corner scale. The small/medium/large steps cover chips,
  // menus and dialogs, and [radiusFull] is the pill used by larger sheets.
  static const double radiusS = 11;
  static const double radiusM = 16;
  static const double radiusL = 22;
  static const double radiusFull = 72;

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
  // Clocks and headings sit at regular and medium weight: ColorOS sets its
  // clock and titles in the system font's regular/medium cuts, and the old
  // hairline weights read as a foreign surface beside them.
  static TextStyle get display => const TextStyle(
    color: textPrimary,
    fontSize: 52,
    fontWeight: FontWeight.w400,
    letterSpacing: -1.5,
    height: 1.0,
  );

  /// The folded cover's clock: a smaller sibling of [display] that fits the
  /// narrow outer panel. Tabular figures keep it from shifting width as the
  /// minute rolls over.
  static TextStyle get clock => const TextStyle(
    color: textPrimary,
    fontSize: 38,
    fontWeight: FontWeight.w400,
    letterSpacing: -0.8,
    height: 1.05,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  /// Sheet and dialog headings.
  static TextStyle get headline => const TextStyle(
    color: textPrimary,
    fontSize: 18,
    fontWeight: FontWeight.w500,
  );

  static TextStyle get title => const TextStyle(
    color: textPrimary,
    fontSize: 16,
    fontWeight: FontWeight.w500,
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

  /// The smallest step: section overlines, counts and dense secondary
  /// metadata. Nothing in the launcher sets type below this.
  static TextStyle get micro => const TextStyle(
    color: textMuted,
    fontSize: 10,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.2,
  );

  /// The sentence-case 12sp label for header utility chips. Deliberately no
  /// [TextStyle.letterSpacing]: ColorOS chrome does not track its labels, and
  /// the old 9.5sp all-caps treatment read as a system badge rather than a
  /// button.
  static TextStyle get chipLabel => const TextStyle(
    color: textSecondary,
    fontSize: 12,
    fontWeight: FontWeight.w500,
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
    final scheme = ColorScheme.dark(
      primary: accent,
      onPrimary: backgroundDeep,
      secondary: accent,
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
      // Transparent: the system wallpaper is the launcher's backdrop, shown
      // through the window by HomeTheme. Surfaces that need a field (the lock
      // panel, sheets) paint their own.
      scaffoldBackgroundColor: Colors.transparent,
      canvasColor: background,
      // No font family: the platform's default sans-serif is the font the
      // user chose in ColorOS, and naming one here would bypass that choice.
      splashColor: white.withValues(alpha: 0.08),
      highlightColor: white.withValues(alpha: 0.04),
      dividerColor: hairline,
      iconTheme: const IconThemeData(color: textSecondary),
      textTheme: const TextTheme(
        displayLarge: TextStyle(
          color: textPrimary,
          fontSize: 52,
          fontWeight: FontWeight.w400,
          letterSpacing: -1.5,
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
          fontWeight: FontWeight.w500,
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
          side: BorderSide(color: hairline),
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

/// One derivation of the tonal surface roles from a [SystemPalette].
///
/// Kept as a value so [LuminousHomeTheme.applyPalette] can compare it against
/// the live roles and bump the revision only when something actually changed.
class _TonalSurfaces {
  const _TonalSurfaces({
    required this.panelDeep,
    required this.panel,
    required this.panelRaised,
    required this.glassCool,
    required this.glassPanel,
    required this.nodeFill,
    required this.panelScrim,
    required this.backgroundRaised,
    required this.glassOpaque,
    required this.glassOpaqueStrong,
    required this.hairline,
    required this.hairlineStrong,
    required this.wallpaperScrim,
  });

  final Color panelDeep;
  final Color panel;
  final Color panelRaised;
  final Color glassCool;
  final Color glassPanel;
  final Color nodeFill;
  final Color panelScrim;
  final Color backgroundRaised;
  final Color glassOpaque;
  final Color glassOpaqueStrong;
  final Color hairline;
  final Color hairlineStrong;
  final Color wallpaperScrim;

  /// The ink roles, used when there is no palette or it lacks a neutral ramp.
  static const _TonalSurfaces ink = _TonalSurfaces(
    panelDeep: LuminousHomeTheme._panelDeepInk,
    panel: LuminousHomeTheme._panelInk,
    panelRaised: LuminousHomeTheme._panelRaisedInk,
    glassCool: LuminousHomeTheme._glassCoolInk,
    glassPanel: LuminousHomeTheme._glassPanelInk,
    nodeFill: LuminousHomeTheme._nodeFillInk,
    panelScrim: LuminousHomeTheme._panelScrimInk,
    backgroundRaised: LuminousHomeTheme._backgroundRaisedInk,
    glassOpaque: LuminousHomeTheme._glassOpaqueInk,
    glassOpaqueStrong: LuminousHomeTheme._glassOpaqueStrongInk,
    hairline: LuminousHomeTheme._hairlineInk,
    hairlineStrong: LuminousHomeTheme._hairlineStrongInk,
    wallpaperScrim: LuminousHomeTheme.backgroundDeep,
  );

  static _TonalSurfaces from(SystemPalette? palette) {
    final Color? surface = palette?.neutral1(900);
    if (palette == null || surface == null) return ink;
    final Color container = palette.neutral1(800) ?? surface;
    final Color outline = palette.neutral2(200) ?? LuminousHomeTheme.white;

    Color toward(Color from, Color to, double t) =>
        Color.lerp(from, to, t) ?? from;
    const Color black = LuminousHomeTheme.black;

    return _TonalSurfaces(
      panelDeep: toward(surface, black, 0.35),
      panel: surface,
      panelRaised: toward(surface, container, 0.4),
      glassCool: toward(surface, container, 0.3),
      glassPanel: toward(surface, black, 0.15),
      nodeFill: toward(surface, black, 0.2),
      panelScrim: toward(surface, black, 0.35).withValues(alpha: 0xEE / 255),
      backgroundRaised: toward(surface, container, 0.5),
      glassOpaque: surface.withValues(alpha: 0xE8 / 255),
      glassOpaqueStrong:
          toward(surface, container, 0.3).withValues(alpha: 0xF0 / 255),
      hairline: outline.withValues(alpha: 0x2E / 255),
      hairlineStrong: outline.withValues(alpha: 0x52 / 255),
      wallpaperScrim: toward(surface, black, 0.4),
    );
  }
}
