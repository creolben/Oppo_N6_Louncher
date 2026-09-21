import 'package:flutter/material.dart';

/// Shared visual language for ChronoFold's ColorOS-inspired home surfaces.
///
/// This is intentionally an original theme rather than a copy of OEM assets.
/// Its fluid light, tonal glass, generous shapes, and quiet typography sit
/// comfortably beside ColorOS while ChronoFold keeps its own spatial motion.
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

  static const double screenGutter = 20;
  static const double cardRadius = 28;
  static const double controlRadius = 18;
  static const double iconRadius = 16;
  static const double dockRadius = 32;
  static const double glassBlur = 24;
  static const double minimumTouchTarget = 48;

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
      onError: Colors.white,
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
      splashColor: Colors.white.withValues(alpha: 0.08),
      highlightColor: Colors.white.withValues(alpha: 0.04),
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
