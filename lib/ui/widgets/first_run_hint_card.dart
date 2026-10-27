import 'package:flutter/material.dart';

import '../theme/luminous_home_theme.dart';

/// A one-time card that names the three gestures the galaxy is built on.
///
/// It is shown on the unfolded galaxy until the user taps "Got it", which the
/// home screen persists. The copy is passed in so it always matches what the
/// swipe-down gesture is currently configured to do.
class FirstRunHintCard extends StatelessWidget {
  const FirstRunHintCard({
    super.key,
    required this.swipeDownLabel,
    required this.onDismiss,
    this.onSetDefault,
  });

  /// "Swipe down to search" or "Swipe down for notifications".
  final String swipeDownLabel;

  final VoidCallback onDismiss;

  /// Shown as a second action only while ChronoFold is not the home app.
  final VoidCallback? onSetDefault;

  @override
  Widget build(BuildContext context) {
    final tips = <(IconData, String)>[
      (Icons.swipe_down_rounded, swipeDownLabel),
      (Icons.touch_app_rounded, 'Tap a group to open it'),
      (Icons.pan_tool_alt_rounded, 'Long-press an app for options'),
    ];

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 480),
      child: Semantics(
        container: true,
        label: 'Getting started',
        child: Material(
          color: LuminousHomeTheme.glassOpaqueStrong,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(LuminousHomeTheme.radiusL),
            side: const BorderSide(color: LuminousHomeTheme.hairline),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 8, 6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Text('Getting started', style: LuminousHomeTheme.title),
                ),
                const SizedBox(height: LuminousHomeTheme.space8),
                for (final (icon, text) in tips)
                  Padding(
                    padding: const EdgeInsets.only(
                      right: 8,
                      bottom: LuminousHomeTheme.space4,
                    ),
                    child: Row(
                      children: [
                        ExcludeSemantics(
                          child: Icon(
                            icon,
                            size: 18,
                            color: LuminousHomeTheme.accent,
                          ),
                        ),
                        const SizedBox(width: LuminousHomeTheme.space8),
                        Expanded(
                          child: Text(text, style: LuminousHomeTheme.body),
                        ),
                      ],
                    ),
                  ),
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: Wrap(
                  alignment: WrapAlignment.end,
                  spacing: LuminousHomeTheme.space4,
                  children: [
                    if (onSetDefault != null)
                      TextButton(
                        onPressed: onSetDefault,
                        style: _buttonStyle(LuminousHomeTheme.textSecondary),
                        child: const Text('Set as default'),
                      ),
                    TextButton(
                      onPressed: onDismiss,
                      style: _buttonStyle(LuminousHomeTheme.accent),
                      child: const Text('Got it'),
                    ),
                  ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static ButtonStyle _buttonStyle(Color color) => TextButton.styleFrom(
    foregroundColor: color,
    minimumSize: const Size(
      LuminousHomeTheme.minimumTouchTarget,
      LuminousHomeTheme.minimumTouchTarget,
    ),
    padding: const EdgeInsets.symmetric(horizontal: LuminousHomeTheme.space12),
  );
}
