import 'package:flutter/material.dart';

import '../theme/luminous_home_theme.dart';

/// The two legibility scrims between the system wallpaper and the home chrome.
///
/// A native launcher never draws text straight onto the wallpaper: Launcher3
/// keeps a scrim under the status bar and clock and another under the dock,
/// and ColorOS dims its wallpaper behind the same regions. This widget is that
/// pair for ChronoFold, mixed from [LuminousHomeTheme.wallpaperScrim] so it
/// takes the device's neutral tint.
///
/// [light] is the platform's verdict that the wallpaper supports dark text; a
/// light wallpaper gets a heavier scrim because the launcher's text stays
/// white over it.
class WallpaperScrim extends StatelessWidget {
  const WallpaperScrim({
    super.key,
    this.light = false,
    this.topExtent = 240,
    this.bottomExtent = 220,
  });

  /// Whether the wallpaper is light enough that the scrims must work harder.
  final bool light;

  /// The height of the top scrim, from the top edge of the screen.
  final double topExtent;

  /// The height of the bottom scrim, from the bottom edge of the screen.
  final double bottomExtent;

  /// The peak alpha of the top scrim for the given wallpaper.
  static double topAlpha({required bool light}) => light ? 0.55 : 0.36;

  /// The peak alpha of the bottom scrim for the given wallpaper.
  static double bottomAlpha({required bool light}) => light ? 0.62 : 0.44;

  @override
  Widget build(BuildContext context) {
    final Color ink = LuminousHomeTheme.wallpaperScrim;
    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: topExtent,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    ink.withValues(alpha: topAlpha(light: light)),
                    ink.withValues(alpha: topAlpha(light: light) * 0.45),
                    ink.withValues(alpha: 0.0),
                  ],
                  stops: const [0.0, 0.45, 1.0],
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            height: bottomExtent,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    ink.withValues(alpha: 0.0),
                    ink.withValues(alpha: bottomAlpha(light: light) * 0.5),
                    ink.withValues(alpha: bottomAlpha(light: light)),
                  ],
                  stops: const [0.0, 0.5, 1.0],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
