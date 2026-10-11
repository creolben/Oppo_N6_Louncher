import 'package:flutter/material.dart';

import '../../core/system_gestures.dart';
import '../theme/luminous_home_theme.dart';

/// The small Gestures sheet: the one place ChronoFold's opt-in,
/// accessibility-backed gestures are explained and configured.
///
/// It is deliberately quiet. When the service is off it says so once, disables
/// what cannot work yet, and offers Android's own settings page — it never
/// nags, never raises a dialog, and never claims a capability the service does
/// not have. The actions it configures are exactly the three the service can
/// perform: open the notification shade, lock the screen, show recent apps.
class GesturesSheet extends StatefulWidget {
  const GesturesSheet({
    super.key,
    required this.serviceEnabled,
    required this.doubleTapToSleep,
    required this.swipeDownAction,
    required this.onDoubleTapToSleepChanged,
    required this.onSwipeDownActionChanged,
    this.isServiceEnabled = SystemGestures.isEnabled,
    this.onOpenSettings = SystemGestures.openSettings,
    this.onShowRecents = SystemGestures.recents,
  });

  /// Whether the accessibility service was connected when the sheet opened.
  final bool serviceEnabled;

  /// Whether a double tap on empty space should sleep the screen.
  final bool doubleTapToSleep;

  /// [SwipeDownAction.search] or [SwipeDownAction.notifications].
  final String swipeDownAction;

  final ValueChanged<bool> onDoubleTapToSleepChanged;
  final ValueChanged<String> onSwipeDownActionChanged;

  /// Re-reads the connection state after a trip to the system settings.
  final Future<bool> Function() isServiceEnabled;

  /// Opens Android's accessibility settings.
  final Future<bool> Function() onOpenSettings;

  /// Runs the "show recent apps" test action.
  final Future<bool> Function() onShowRecents;

  @override
  State<GesturesSheet> createState() => _GesturesSheetState();
}

class _GesturesSheetState extends State<GesturesSheet> {
  late bool _serviceEnabled = widget.serviceEnabled;
  late bool _doubleTapToSleep = widget.doubleTapToSleep;
  late String _swipeDownAction = widget.swipeDownAction;

  /// The single explanation shown while the service is off. One line, stated
  /// once, never a nag.
  static const String _offExplanation =
      'Turn the service on in Android Settings to use these gestures. '
      'ChronoFold never reads screen content.';

  Future<void> _openSettings() async {
    await widget.onOpenSettings();
    if (!mounted) return;
    // The user may just have enabled it, so the sheet re-reads the connection
    // rather than keeping a stale "off".
    final bool enabled = await widget.isServiceEnabled();
    if (!mounted) return;
    setState(() => _serviceEnabled = enabled);
  }

  void _setDoubleTapToSleep(bool value) {
    setState(() => _doubleTapToSleep = value);
    widget.onDoubleTapToSleepChanged(value);
  }

  void _setSwipeDownAction(String action) {
    if (action == _swipeDownAction) return;
    setState(() => _swipeDownAction = action);
    widget.onSwipeDownActionChanged(action);
  }

  @override
  Widget build(BuildContext context) {
    final bool off = !_serviceEnabled;
    final Duration motionFast = LuminousHomeTheme.motion(
      context,
      LuminousHomeTheme.motionFast,
    );

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: Container(
          decoration: BoxDecoration(
            color: LuminousHomeTheme.panelDeep,
            borderRadius: BorderRadius.circular(LuminousHomeTheme.radiusL),
            border: Border.all(color: LuminousHomeTheme.hairlineStrong),
            boxShadow: const [
              BoxShadow(
                color: LuminousHomeTheme.blackScrim,
                blurRadius: 36,
                offset: Offset(0, -8),
              ),
            ],
          ),
          child: SingleChildScrollView(
            primary: false,
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 38,
                    height: 4,
                    decoration: BoxDecoration(
                      color: LuminousHomeTheme.white24,
                      borderRadius: BorderRadius.circular(LuminousHomeTheme.radiusS),
                    ),
                  ),
                ),
                const SizedBox(height: LuminousHomeTheme.space16),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Gestures',
                        style: LuminousHomeTheme.title,
                      ),
                    ),
                    Semantics(
                      button: true,
                      label: 'Close gestures',
                      child: IconButton(
                        tooltip: 'Close',
                        onPressed: () => Navigator.of(context).maybePop(),
                        icon: const Icon(Icons.close_rounded, size: 20),
                        color: LuminousHomeTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: LuminousHomeTheme.space4),
                Text(
                  'ChronoFold reaches the system only through Android\'s '
                  'accessibility service. Nothing here reads your screen.',
                  style: LuminousHomeTheme.caption,
                ),
                const SizedBox(height: LuminousHomeTheme.space16),
                _buildStatusCard(off, motionFast),
                const SizedBox(height: LuminousHomeTheme.space16),
                _buildDoubleTapRow(off),
                const SizedBox(height: LuminousHomeTheme.space16),
                _buildSwipeDownSection(off),
                const SizedBox(height: LuminousHomeTheme.space16),
                _buildRecentsButton(off),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatusCard(bool off, Duration motionFast) {
    return AnimatedContainer(
      duration: motionFast,
      curve: LuminousHomeTheme.easeStandard,
      padding: const EdgeInsets.all(LuminousHomeTheme.space12),
      decoration: BoxDecoration(
        color: LuminousHomeTheme.glassPanel,
        borderRadius: BorderRadius.circular(LuminousHomeTheme.radiusM),
        border: Border.all(
          color: off
              ? LuminousHomeTheme.hairline
              : LuminousHomeTheme.accentGlow,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.accessibility_new_rounded,
                size: 20,
                color: off
                    ? LuminousHomeTheme.textMuted
                    : LuminousHomeTheme.accent,
              ),
              const SizedBox(width: LuminousHomeTheme.space8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Accessibility service',
                      style: LuminousHomeTheme.label,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      off ? 'Off' : 'On',
                      style: LuminousHomeTheme.chipLabel.copyWith(
                        color: off
                            ? LuminousHomeTheme.textMuted
                            : LuminousHomeTheme.accent,
                      ),
                    ),
                  ],
                ),
              ),
              if (off)
                Semantics(
                  button: true,
                  label: 'Enable the accessibility service in Android Settings',
                  child: TextButton(
                    onPressed: _openSettings,
                    style: TextButton.styleFrom(
                      foregroundColor: LuminousHomeTheme.accent,
                      backgroundColor: LuminousHomeTheme.accentSoft,
                      minimumSize: const Size(
                        LuminousHomeTheme.minimumTouchTarget,
                        LuminousHomeTheme.minimumTouchTarget,
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: LuminousHomeTheme.space12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                          LuminousHomeTheme.radiusM,
                        ),
                      ),
                    ),
                    child: const Text('Enable in Settings'),
                  ),
                ),
            ],
          ),
          if (off) ...[
            const SizedBox(height: LuminousHomeTheme.space8),
            Text(_offExplanation, style: LuminousHomeTheme.caption),
          ],
        ],
      ),
    );
  }

  Widget _buildDoubleTapRow(bool off) {
    return Semantics(
      toggled: _doubleTapToSleep,
      enabled: !off,
      label: 'Double-tap empty space to sleep',
      child: Container(
        constraints: const BoxConstraints(
          minHeight: LuminousHomeTheme.minimumTouchTarget,
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: LuminousHomeTheme.space12,
          vertical: LuminousHomeTheme.space8,
        ),
        decoration: BoxDecoration(
          color: LuminousHomeTheme.glassPanel,
          borderRadius: BorderRadius.circular(LuminousHomeTheme.radiusM),
          border: Border.all(color: LuminousHomeTheme.hairline),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Double-tap empty space to sleep',
                    style: LuminousHomeTheme.label,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Lock the screen without reaching for the power key.',
                    style: LuminousHomeTheme.caption,
                  ),
                ],
              ),
            ),
            const SizedBox(width: LuminousHomeTheme.space8),
            ExcludeSemantics(
              child: Switch(
                value: _doubleTapToSleep,
                onChanged: off ? null : _setDoubleTapToSleep,
                activeThumbColor: LuminousHomeTheme.accent,
                inactiveThumbColor: LuminousHomeTheme.textMuted,
                inactiveTrackColor: LuminousHomeTheme.hairlineStrong,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSwipeDownSection(bool off) {
    // Search always works, so it stays available even with the service off;
    // only the notifications answer depends on the service.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Swipe down opens', style: LuminousHomeTheme.label),
        const SizedBox(height: LuminousHomeTheme.space8),
        Row(
          children: [
            Expanded(
              child: _GestureChoice(
                label: 'Search',
                selected: _swipeDownAction == SwipeDownAction.search,
                onTap: () => _setSwipeDownAction(SwipeDownAction.search),
              ),
            ),
            const SizedBox(width: LuminousHomeTheme.space8),
            Expanded(
              child: _GestureChoice(
                label: 'Notifications',
                selected: _swipeDownAction == SwipeDownAction.notifications,
                onTap: off
                    ? null
                    : () => _setSwipeDownAction(SwipeDownAction.notifications),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildRecentsButton(bool off) {
    return Semantics(
      button: true,
      enabled: !off,
      label: 'Show recent apps',
      child: OutlinedButton.icon(
        onPressed: off
            ? null
            : () async {
                await widget.onShowRecents();
              },
        icon: const Icon(Icons.splitscreen_rounded, size: 20),
        label: const Text('Show recent apps'),
        style: OutlinedButton.styleFrom(
          foregroundColor: LuminousHomeTheme.accent,
          disabledForegroundColor: LuminousHomeTheme.textMuted,
          minimumSize: const Size.fromHeight(
            LuminousHomeTheme.minimumTouchTarget,
          ),
          side: BorderSide(
            color: off ? LuminousHomeTheme.hairline : LuminousHomeTheme.accentGlow,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(LuminousHomeTheme.radiusM),
          ),
        ),
      ),
    );
  }
}

/// One answer in the swipe-down choice: a 48dp chip that reports selection to
/// a screen reader and disables itself when the service cannot back it.
class _GestureChoice extends StatelessWidget {
  const _GestureChoice({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final bool enabled = onTap != null;
    final Color foreground = !enabled
        ? LuminousHomeTheme.textMuted
        : selected
        ? LuminousHomeTheme.textPrimary
        : LuminousHomeTheme.textSecondary;

    return Semantics(
      button: true,
      selected: selected,
      enabled: enabled,
      label: 'Swipe down opens $label',
      child: Material(
        color: selected
            ? LuminousHomeTheme.accentSoft
            : LuminousHomeTheme.glassPanel,
        borderRadius: BorderRadius.circular(LuminousHomeTheme.radiusM),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(LuminousHomeTheme.radiusM),
          child: Container(
            constraints: const BoxConstraints(
              minHeight: LuminousHomeTheme.minimumTouchTarget,
            ),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(LuminousHomeTheme.radiusM),
              border: Border.all(
                color: selected
                    ? LuminousHomeTheme.accentMid
                    : LuminousHomeTheme.hairline,
              ),
            ),
            child: ExcludeSemantics(
              child: Text(
                label,
                style: LuminousHomeTheme.chipLabel.copyWith(
                  color: foreground,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
