import 'package:flutter/material.dart';

import '../theme/luminous_home_theme.dart';

/// The scale every [showNativePanel] surface grows from.
///
/// ColorOS panels enter with a small, decelerating lift rather than the
/// springy overshoot the launcher used before. Never above 1.0.
const double nativePanelScaleBegin = 0.9;

/// Builds the shared ColorOS-style enter/exit transition for launcher panels.
///
/// * scale grows [nativePanelScaleBegin] → 1.0 on
///   [LuminousHomeTheme.easeMove] and leaves on [LuminousHomeTheme.easeExit];
/// * opacity follows [LuminousHomeTheme.easeStandard] in and
///   [LuminousHomeTheme.easeExit] out;
/// * both collapse to the child untouched when the platform has animations
///   disabled, so reduce-motion users still get the panel.
///
/// Exposed (not private) so widget tests can sample the curve.
Widget buildNativePanelTransition(
  BuildContext context,
  Animation<double> animation,
  Animation<double> secondaryAnimation,
  Widget child,
) {
  if (MediaQuery.disableAnimationsOf(context)) {
    return child;
  }

  final CurvedAnimation scaleCurve = CurvedAnimation(
    parent: animation,
    curve: LuminousHomeTheme.easeMove,
    reverseCurve: LuminousHomeTheme.easeExit,
  );
  final CurvedAnimation opacityCurve = CurvedAnimation(
    parent: animation,
    curve: LuminousHomeTheme.easeStandard,
    reverseCurve: LuminousHomeTheme.easeExit,
  );

  return FadeTransition(
    opacity: opacityCurve,
    child: ScaleTransition(
      scale: Tween<double>(
        begin: nativePanelScaleBegin,
        end: 1.0,
      ).animate(scaleCurve),
      child: child,
    ),
  );
}

/// A dialog route that opens over [LuminousHomeTheme.motionPanel] and closes
/// over [LuminousHomeTheme.motionPanelExit].
///
/// `showGeneralDialog` uses one duration for both directions. Overriding
/// [reverseTransitionDuration] is what lets the panel leave as quickly as
/// ColorOS dialogs do instead of replaying the 350 ms entry backwards.
class NativePanelRoute<T> extends RawDialogRoute<T> {
  NativePanelRoute({
    required super.pageBuilder,
    super.barrierDismissible = true,
    super.barrierLabel,
    super.barrierColor,
    super.settings,
    super.transitionDuration = LuminousHomeTheme.motionPanel,
    this.reduceMotion = false,
  });

  /// True when the opening context had animations disabled; the route then
  /// opens and closes instantly instead of merely hiding the animation.
  final bool reduceMotion;

  @override
  Duration get reverseTransitionDuration => reduceMotion
      ? Duration.zero
      : LuminousHomeTheme.motionPanelExit;

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) =>
      buildNativePanelTransition(context, animation, secondaryAnimation, child);
}

/// Opens the shared native-feeling panel behind [pageBuilder].
///
/// Matches `showGeneralDialog`'s barrier behaviour while using
/// [NativePanelRoute] for the ColorOS enter/exit timing. Honours the system
/// reduce-motion preference by opening and closing with no animation.
Future<T?> showNativePanel<T>({
  required BuildContext context,
  required WidgetBuilder pageBuilder,
  bool barrierDismissible = true,
  String? barrierLabel,
  Color barrierColor = Colors.transparent,
  bool useRootNavigator = true,
}) {
  final bool reduceMotion = MediaQuery.disableAnimationsOf(context);
  return Navigator.of(context, rootNavigator: useRootNavigator).push<T>(
    NativePanelRoute<T>(
      barrierDismissible: barrierDismissible,
      barrierLabel:
          barrierLabel ?? MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: barrierColor,
      transitionDuration:
          reduceMotion ? Duration.zero : LuminousHomeTheme.motionPanel,
      reduceMotion: reduceMotion,
      pageBuilder: (context, animation, secondaryAnimation) =>
          pageBuilder(context),
    ),
  );
}
