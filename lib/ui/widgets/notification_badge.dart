import 'package:flutter/material.dart';

import '../theme/luminous_home_theme.dart';

/// The small notification dot drawn over an app icon.
///
/// Colour, ring and cap are fixed here so the cover grid, tabletop buttons and
/// search results all present the same badge the galaxy paints: the launcher's
/// notification accent, a one-pixel dark ring, and a count that caps at `9+`.
/// The count is only drawn when there is room for it; the dot alone still
/// carries the signal on a small tile.
class NotificationBadge extends StatelessWidget {
  /// The number of notifications. Zero or below renders nothing.
  final int count;

  /// The dot's diameter in logical pixels.
  final double size;

  const NotificationBadge({super.key, required this.count, this.size = 16});

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return const SizedBox.shrink();
    final bool showCount = size >= 13;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: LuminousHomeTheme.notification,
        shape: BoxShape.circle,
        border: Border.all(
          color: LuminousHomeTheme.backgroundDeep,
          width: 1.0,
        ),
      ),
      child: showCount
          ? Text(
              count > 9 ? '9+' : '$count',
              maxLines: 1,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: LuminousHomeTheme.textPrimary,
                fontSize: size * 0.56,
                fontWeight: FontWeight.w700,
                height: 1.0,
              ),
            )
          : null,
    );
  }
}
