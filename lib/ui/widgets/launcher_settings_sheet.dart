import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../theme/luminous_home_theme.dart';

/// Opens ChronoFold's own Settings sheet.
///
/// Every gear button in the launcher lands here. Android's default-home picker
/// is reachable only through the "Default home app" row, so a user looking for
/// the launcher's settings is never dropped into a system page by surprise.
///
/// The sheet only lists actions the launcher really has; each row is wired to a
/// callback owned by the home screen, which stays the single source of truth.
Future<void> showLauncherSettingsSheet(
  BuildContext context, {
  required ValueListenable<bool> isDefaultLauncher,
  required VoidCallback onDefaultHomeTap,
  required bool nativeLockMode,
  required Future<void> Function(bool nativeMode) onLockModeChanged,
  VoidCallback? onOpenAmbientWallpaper,
  VoidCallback? onOpenGestures,
  Future<bool> Function()? hasMediaAccess,
  Future<void> Function()? onRequestMediaAccess,
  Future<bool> Function()? isGalaxyWallpaperActive,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: LuminousHomeTheme.lockScrim,
    builder: (sheetContext) => LauncherSettingsSheet(
      isDefaultLauncher: isDefaultLauncher,
      onDefaultHomeTap: onDefaultHomeTap,
      nativeLockMode: nativeLockMode,
      onLockModeChanged: onLockModeChanged,
      onOpenAmbientWallpaper: onOpenAmbientWallpaper,
      onOpenGestures: onOpenGestures,
      hasMediaAccess: hasMediaAccess,
      onRequestMediaAccess: onRequestMediaAccess,
      isGalaxyWallpaperActive: isGalaxyWallpaperActive,
    ),
  );
}

/// The Settings sheet body. Public so widget tests can mount it directly.
class LauncherSettingsSheet extends StatefulWidget {
  const LauncherSettingsSheet({
    super.key,
    required this.isDefaultLauncher,
    required this.onDefaultHomeTap,
    required this.nativeLockMode,
    required this.onLockModeChanged,
    this.onOpenAmbientWallpaper,
    this.onOpenGestures,
    this.hasMediaAccess,
    this.onRequestMediaAccess,
    this.isGalaxyWallpaperActive,
  });

  /// Live default-home status. A listenable rather than a bool because the
  /// answer changes after a round trip to Android's own picker, which the home
  /// screen re-checks on resume while this sheet is still open.
  final ValueListenable<bool> isDefaultLauncher;

  /// Asks Android to make ChronoFold the home app, or, when it already is,
  /// opens Android's default-home picker so the user can change it.
  final VoidCallback onDefaultHomeTap;

  /// Whether ColorOS currently owns the lock screen.
  final bool nativeLockMode;

  /// Applies and persists a lock-surface change. Only called after the user
  /// confirms it.
  final Future<void> Function(bool nativeMode) onLockModeChanged;

  final VoidCallback? onOpenAmbientWallpaper;
  final VoidCallback? onOpenGestures;

  /// Whether ChronoFold holds notification access, which Android requires
  /// before it shares media sessions or notification counts. Without it the
  /// lock screen can never show what is playing, and nothing else in the
  /// launcher asks for it. Null hides the row.
  final Future<bool> Function()? hasMediaAccess;

  /// Opens Android's notification-access page; only the user can grant it.
  final Future<void> Function()? onRequestMediaAccess;

  /// Whether ChronoFold's galaxy is the system wallpaper. The launcher window
  /// shows the system wallpaper through, and ColorOS runs the close-app
  /// animation over that same wallpaper
  /// until the launcher is up, so this is what decides whether that moment
  /// looks like ChronoFold. Null leaves the wallpaper row without a status.
  final Future<bool> Function()? isGalaxyWallpaperActive;

  /// Width cap on the unfolded inner screen: a sheet stretched to 900dp reads
  /// as a banner, not a panel.
  static const double maxWidth = 560;

  @override
  State<LauncherSettingsSheet> createState() => _LauncherSettingsSheetState();
}

class _LauncherSettingsSheetState extends State<LauncherSettingsSheet>
    with WidgetsBindingObserver {
  late bool _nativeMode = widget.nativeLockMode;
  bool _switching = false;

  /// Null until the platform answers.
  bool? _mediaAccess;
  bool? _galaxyWallpaper;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshPlatformState();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// The grant happens on Android's own page with this sheet still open, so
  /// coming back is the moment the answer can have changed.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshPlatformState();
  }

  /// Both grants happen on Android's own pages with this sheet still open.
  Future<void> _refreshPlatformState() async {
    final media = widget.hasMediaAccess;
    final wallpaper = widget.isGalaxyWallpaperActive;
    final bool? granted = media == null ? null : await media();
    final bool? galaxy = wallpaper == null ? null : await wallpaper();
    if (!mounted) return;
    setState(() {
      _mediaAccess = granted;
      _galaxyWallpaper = galaxy;
    });
  }

  Future<void> _requestLockMode(bool native) async {
    if (native == _nativeMode || _switching) return;
    final bool confirmed = await _confirmLockMode(native);
    if (!confirmed || !mounted) return;
    setState(() => _switching = true);
    try {
      await widget.onLockModeChanged(native);
      if (mounted) setState(() => _nativeMode = native);
    } finally {
      if (mounted) setState(() => _switching = false);
    }
  }

  /// The lock surface is a security boundary, so a single stray tap must not
  /// swap it. The dialog names exactly what changes and what does not.
  Future<bool> _confirmLockMode(bool native) async {
    final bool? result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: LuminousHomeTheme.panelRaised,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(LuminousHomeTheme.radiusL),
        ),
        title: Text(
          native ? 'Use the ColorOS lock screen?' : 'Use the Cosmic lock screen?',
          style: LuminousHomeTheme.headline,
        ),
        content: Text(
          native
              ? 'ChronoFold will stop showing its lock panel. ColorOS handles '
                    'the whole lock screen.'
              : 'ChronoFold will show its lock panel when the screen turns '
                    'off. Android still checks your PIN, pattern or '
                    'fingerprint before anything opens.',
          style: LuminousHomeTheme.body,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            style: TextButton.styleFrom(
              foregroundColor: LuminousHomeTheme.textSecondary,
              minimumSize: const Size(
                LuminousHomeTheme.minimumTouchTarget,
                LuminousHomeTheme.minimumTouchTarget,
              ),
            ),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: LuminousHomeTheme.accent,
              minimumSize: const Size(
                LuminousHomeTheme.minimumTouchTarget,
                LuminousHomeTheme.minimumTouchTarget,
              ),
            ),
            child: const Text('Switch'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final double maxHeight = MediaQuery.sizeOf(context).height * 0.9;

    return SafeArea(
      top: false,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: LauncherSettingsSheet.maxWidth,
            maxHeight: maxHeight,
          ),
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
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Grabber and title stay pinned; the sections scroll, so a
                  // 2x font scale on the cover screen never pushes the close
                  // button out of reach.
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 8, 0),
                    child: Column(
                      children: [
                        Center(
                          child: Container(
                            width: 38,
                            height: 4,
                            decoration: BoxDecoration(
                              color: LuminousHomeTheme.white24,
                              borderRadius: BorderRadius.circular(
                                LuminousHomeTheme.radiusS,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: LuminousHomeTheme.space8),
                        Row(
                          children: [
                            Expanded(
                              child: Semantics(
                                header: true,
                                child: Text(
                                  'Settings',
                                  style: LuminousHomeTheme.headline,
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: 'Close settings',
                              onPressed: () => Navigator.of(context).maybePop(),
                              icon: const Icon(Icons.close_rounded, size: 20),
                              color: LuminousHomeTheme.textSecondary,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Flexible(
                    child: SingleChildScrollView(
                      primary: false,
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _section('Home', [_defaultHomeRow()]),
                          if (widget.onOpenAmbientWallpaper != null)
                            _section('Appearance', [
                              _wallpaperRow(),
                            ]),
                          _section('Lock screen', [
                            ..._lockModeRows(),
                            if (widget.hasMediaAccess != null &&
                                _mediaAccess != null)
                              _mediaAccessRow(_mediaAccess!),
                          ]),
                          if (widget.onOpenGestures != null)
                            _section('Gestures', [
                              _SettingsRow(
                                icon: Icons.touch_app_rounded,
                                title: 'Gestures',
                                subtitle: 'Swipe down, double-tap to sleep',
                                trailing: const _Chevron(),
                                onTap: widget.onOpenGestures,
                              ),
                            ]),
                          _section('About', const [
                            _SettingsRow(
                              icon: Icons.auto_awesome_rounded,
                              title: 'ChronoFold',
                              subtitle: 'Home screen for foldables',
                            ),
                          ]),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _defaultHomeRow() {
    return ValueListenableBuilder<bool>(
      valueListenable: widget.isDefaultLauncher,
      builder: (context, isDefault, _) {
        return _SettingsRow(
          icon: Icons.home_rounded,
          title: 'Default home app',
          subtitle: isDefault
              ? 'ChronoFold is your home app'
              : 'Another app opens when you press Home',
          semanticsHint: isDefault
              ? 'Opens Android\'s home app setting'
              : 'Asks Android to make ChronoFold your home app',
          trailing: isDefault
              ? const _Chevron()
              : const _ActionPill(label: 'Set as default'),
          onTap: widget.onDefaultHomeTap,
        );
      },
    );
  }

  Widget _wallpaperRow() {
    final bool? active = _galaxyWallpaper;
    return _SettingsRow(
      icon: Icons.wallpaper_rounded,
      title: 'Galaxy wallpaper',
      subtitle: switch (active) {
        true => 'On: the galaxy is your system wallpaper',
        false => 'Off: Home sits on your ColorOS wallpaper',
        null => 'Preview the live galaxy wallpaper',
      },
      semanticsHint: 'Opens the galaxy wallpaper preview',
      trailing: active == false
          ? const _ActionPill(label: 'Use galaxy')
          : const _Chevron(),
      onTap: widget.onOpenAmbientWallpaper,
    );
  }

  Widget _mediaAccessRow(bool granted) {
    return _SettingsRow(
      icon: Icons.music_note_rounded,
      title: 'Now playing & badges',
      subtitle: granted
          ? 'On: media controls on the lock screen and app badges'
          : 'Off: allow notification access to show what is playing',
      semanticsHint: 'Opens Android\'s notification access setting',
      trailing: granted ? const _Chevron() : const _ActionPill(label: 'Allow'),
      onTap: widget.onRequestMediaAccess == null
          ? null
          : () => unawaited(widget.onRequestMediaAccess!()),
    );
  }

  List<Widget> _lockModeRows() {
    return [
      _LockModeOption(
        icon: Icons.auto_awesome_rounded,
        title: 'Cosmic',
        subtitle:
            'ChronoFold\'s lock panel. Android still checks your fingerprint.',
        selected: !_nativeMode,
        enabled: !_switching,
        onTap: () => _requestLockMode(false),
      ),
      _LockModeOption(
        icon: Icons.shield_outlined,
        title: 'ColorOS',
        subtitle: 'The system lock screen, with nothing from ChronoFold.',
        selected: _nativeMode,
        enabled: !_switching,
        onTap: () => _requestLockMode(true),
      ),
    ];
  }

  /// A titled group: a quiet overline above a single rounded card whose rows
  /// are separated by hairlines, the ColorOS preference-list shape.
  Widget _section(String title, List<Widget> rows) {
    final children = <Widget>[];
    for (var i = 0; i < rows.length; i++) {
      if (i > 0) {
        children.add(
          const Divider(
            height: 1,
            thickness: 1,
            indent: 60,
            color: LuminousHomeTheme.dividerFaint,
          ),
        );
      }
      children.add(rows[i]);
    }
    return Padding(
      padding: const EdgeInsets.only(top: LuminousHomeTheme.space16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(
              left: LuminousHomeTheme.space4,
              bottom: LuminousHomeTheme.space8,
            ),
            child: Semantics(
              header: true,
              child: Text(
                title,
                style: LuminousHomeTheme.caption.copyWith(
                  color: LuminousHomeTheme.textMuted,
                ),
              ),
            ),
          ),
          Material(
            color: LuminousHomeTheme.glassPanel,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(LuminousHomeTheme.radiusM),
              side: BorderSide(color: LuminousHomeTheme.hairline),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(children: children),
          ),
        ],
      ),
    );
  }
}

/// One preference row: tinted icon, title, one-line subtitle, optional
/// trailing control. At least 56dp tall so it clears the 48dp target with room.
class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.trailing,
    this.onTap,
    this.semanticsHint,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final String? semanticsHint;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: onTap != null,
      label: '$title. $subtitle',
      hint: semanticsHint,
      excludeSemantics: true,
      onTap: onTap,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: LuminousHomeTheme.space12,
              vertical: LuminousHomeTheme.space8,
            ),
            child: Row(
              children: [
                _RowIcon(icon: icon),
                const SizedBox(width: LuminousHomeTheme.space12),
                Expanded(child: _RowText(title: title, subtitle: subtitle)),
                if (trailing != null) ...[
                  const SizedBox(width: LuminousHomeTheme.space8),
                  // The trailing pill may not fit beside a 2x title on the
                  // cover; it yields rather than overflowing the row.
                  Flexible(child: trailing!),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One answer in the lock-surface choice: a radio row that reports selection
/// and its mutually exclusive group to a screen reader.
class _LockModeOption extends StatelessWidget {
  const _LockModeOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      checked: selected,
      inMutuallyExclusiveGroup: true,
      enabled: enabled,
      label: 'Lock screen: $title. $subtitle',
      excludeSemantics: true,
      onTap: enabled ? onTap : null,
      child: InkWell(
        onTap: enabled ? onTap : null,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: LuminousHomeTheme.space12,
              vertical: LuminousHomeTheme.space8,
            ),
            child: Row(
              children: [
                _RowIcon(icon: icon),
                const SizedBox(width: LuminousHomeTheme.space12),
                Expanded(child: _RowText(title: title, subtitle: subtitle)),
                const SizedBox(width: LuminousHomeTheme.space8),
                Icon(
                  selected
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_unchecked_rounded,
                  size: 22,
                  color: selected
                      ? LuminousHomeTheme.accent
                      : LuminousHomeTheme.textMuted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RowIcon extends StatelessWidget {
  const _RowIcon({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: LuminousHomeTheme.accentFaint,
        borderRadius: BorderRadius.circular(LuminousHomeTheme.radiusS),
      ),
      child: Icon(icon, size: 20, color: LuminousHomeTheme.accent),
    );
  }
}

class _RowText extends StatelessWidget {
  const _RowText({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(title, style: LuminousHomeTheme.label),
        const SizedBox(height: 2),
        Text(subtitle, style: LuminousHomeTheme.caption),
      ],
    );
  }
}

class _Chevron extends StatelessWidget {
  const _Chevron();

  @override
  Widget build(BuildContext context) {
    return const Icon(
      Icons.chevron_right_rounded,
      size: 22,
      color: LuminousHomeTheme.textMuted,
    );
  }
}

/// A small accent pill naming the action a row takes, for rows whose state is
/// "not set up yet".
class _ActionPill extends StatelessWidget {
  const _ActionPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: LuminousHomeTheme.space12,
          vertical: 6,
        ),
        decoration: BoxDecoration(
          color: LuminousHomeTheme.accentSoft,
          borderRadius: BorderRadius.circular(LuminousHomeTheme.radiusFull),
        ),
        child: Text(
          label,
          style: LuminousHomeTheme.chipLabel.copyWith(
            color: LuminousHomeTheme.accent,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
