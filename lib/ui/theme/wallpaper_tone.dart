import 'dart:ui' show Color;

/// What the platform knows about the system wallpaper's colours.
///
/// Native sends the `WallpaperColors` of the home wallpaper: its primary
/// colour and the two platform hints. [supportsDarkText] is the one the
/// launcher acts on — it is Android's own verdict that the wallpaper is light
/// enough for dark foreground content, and it is what decides whether the
/// status and navigation bar icons go dark and how strong the home scrims are.
///
/// Value-equal and read-only: the home screen compares a fresh read against
/// the last one and rebuilds only when the verdict actually changed.
class WallpaperTone {
  const WallpaperTone({
    required this.supportsDarkText,
    required this.supportsDarkTheme,
    this.primary,
    this.secondary,
    this.tertiary,
  });

  /// The platform's `HINT_SUPPORTS_DARK_TEXT`: a light wallpaper.
  final bool supportsDarkText;

  /// The platform's `HINT_SUPPORTS_DARK_THEME`: a dark wallpaper.
  final bool supportsDarkTheme;

  /// The wallpaper's most prominent colour, when the platform extracted one.
  final Color? primary;
  final Color? secondary;
  final Color? tertiary;

  /// Whether the launcher should treat the wallpaper as light: dark chrome
  /// icons and stronger scrims behind its white text.
  bool get isLight => supportsDarkText;

  /// Parses a native tone map, or returns null when it is missing or
  /// malformed. A missing colour is a legitimate null; a non-map is refused.
  static WallpaperTone? fromMap(dynamic map) {
    if (map is! Map) return null;
    final Object? darkText = map['supportsDarkText'];
    final Object? darkTheme = map['supportsDarkTheme'];
    if (darkText is! bool || darkTheme is! bool) return null;
    Color? colour(Object? raw) => raw is int ? Color(raw) : null;
    return WallpaperTone(
      supportsDarkText: darkText,
      supportsDarkTheme: darkTheme,
      primary: colour(map['primary']),
      secondary: colour(map['secondary']),
      tertiary: colour(map['tertiary']),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is WallpaperTone &&
      other.supportsDarkText == supportsDarkText &&
      other.supportsDarkTheme == supportsDarkTheme &&
      other.primary == primary &&
      other.secondary == secondary &&
      other.tertiary == tertiary;

  @override
  int get hashCode =>
      Object.hash(supportsDarkText, supportsDarkTheme, primary, secondary, tertiary);
}
