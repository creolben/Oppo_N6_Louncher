import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import '../../models/app_entry.dart';
import '../../models/app_shortcut.dart';
import '../../core/launcher_bridge.dart';
import '../../core/galaxy_storage_service.dart';
import '../../core/galaxy_layout_engine.dart';
import '../theme/luminous_home_theme.dart';

class AppActionDialog extends StatefulWidget {
  final AppEntry app;
  final GalaxyLayoutEngine? layoutEngine;
  final VoidCallback? onActionCompleted;

  /// Loads the app's shortcuts. Null in production, where the bridge is used; a
  /// widget test injects a fake so it can assert what the dialog shows.
  final Future<List<AppShortcut>> Function(String packageName)? loadShortcuts;

  /// Launches a shortcut. Null in production; injectable for tests.
  final Future<bool> Function(AppShortcut shortcut, {Rect? sourceBounds})?
      launchShortcut;

  const AppActionDialog({
    super.key,
    required this.app,
    this.layoutEngine,
    this.onActionCompleted,
    this.loadShortcuts,
    this.launchShortcut,
  });

  @override
  State<AppActionDialog> createState() => _AppActionDialogState();
}

class _AppActionDialogState extends State<AppActionDialog> {
  /// The loaded shortcuts. Empty until the async load answers; the section
  /// reserves no space before then, so the dialog does not jump open.
  List<AppShortcut> _shortcuts = const [];

  @override
  void initState() {
    super.initState();
    unawaited(_loadShortcuts());
  }

  Future<void> _loadShortcuts() async {
    final loader = widget.loadShortcuts ?? LauncherBridge.getAppShortcuts;
    final shortcuts = await loader(widget.app.packageName);
    if (!mounted) return;
    setState(() => _shortcuts = shortcuts);
  }

  Future<void> _launchShortcut(AppShortcut shortcut, Rect? sourceBounds) async {
    Navigator.of(context).pop();
    final launcher = widget.launchShortcut ?? LauncherBridge.startAppShortcut;
    await launcher(shortcut, sourceBounds: sourceBounds);
  }

  /// The tile's rectangle in global logical pixels, for the launch reveal.
  Rect? _globalRectOf(BuildContext context) {
    final renderObject = context.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) return null;
    return renderObject.localToGlobal(Offset.zero) & renderObject.size;
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
      child: Center(
        child: Container(
          width: 310,
          margin: const EdgeInsets.symmetric(horizontal: 24),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: LuminousHomeTheme.panelScrim,
            borderRadius: BorderRadius.circular(LuminousHomeTheme.radiusL),
            border: Border.all(
              color: app.accentColor.withOpacity(0.4),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: app.accentColor.withOpacity(0.2),
                blurRadius: 28,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // App Emblem
                Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: app.accentColor.withOpacity(0.18),
                    border: Border.all(color: app.accentColor.withOpacity(0.6), width: 1.5),
                  ),
                  child: Icon(app.fallbackIcon, color: app.accentColor, size: 30),
                ),
                const SizedBox(height: 12),
                Text(
                  app.label,
                  style: const TextStyle(
                    color: LuminousHomeTheme.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  app.packageName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: LuminousHomeTheme.white.withOpacity(0.45),
                    fontSize: 11.5,
                  ),
                ),
                const SizedBox(height: 20),
                const Divider(color: LuminousHomeTheme.white12, height: 1),
                const SizedBox(height: 10),

                // The app's own shortcuts sit above the launcher's actions,
                // exactly as they do in the system's long-press menu. Nothing
                // is reserved until the platform answers; the section then
                // grows and fades in.
                AnimatedSize(
                  duration: LuminousHomeTheme.motion(
                    context,
                    LuminousHomeTheme.motionShort,
                  ),
                  curve: LuminousHomeTheme.easeStandard,
                  alignment: FractionalOffset.topCenter,
                  child: AnimatedOpacity(
                    duration: LuminousHomeTheme.motion(
                      context,
                      LuminousHomeTheme.motionShort,
                    ),
                    curve: LuminousHomeTheme.easeStandard,
                    opacity: _shortcuts.isEmpty ? 0.0 : 1.0,
                    child: _shortcuts.isEmpty
                        ? const SizedBox(width: double.infinity, height: 0)
                        : Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              for (final shortcut in _shortcuts)
                                _shortcutTile(context, shortcut),
                              const SizedBox(height: 4),
                            ],
                          ),
                  ),
                ),

                // Actions
                _actionTile(
                  context,
                  icon: Icons.launch_rounded,
                  label: 'Launch Application',
                  color: LuminousHomeTheme.accent,
                  onTap: (sourceBounds) {
                    Navigator.of(context).pop();
                    LauncherBridge.launchApp(app, sourceBounds: sourceBounds);
                  },
                ),

                // Center Constellation Pin/Unpin
                if (widget.layoutEngine != null) ...[
                  Builder(builder: (context) {
                    final core = widget.layoutEngine!.constellations.firstWhere((c) => c.id == 'core');
                    final isInCore = core.apps.any((a) => a.packageName == app.packageName);

                    return _actionTile(
                      context,
                      icon: isInCore ? Icons.star_border_rounded : Icons.star_rounded,
                      label: isInCore ? 'Remove from Center Constellation' : 'Pin to Center Constellation',
                      color: LuminousHomeTheme.accentCore,
                      onTap: (_) {
                        Navigator.of(context).pop();
                        if (isInCore) {
                          widget.layoutEngine!.removeAppFromCore(app.packageName);
                          GalaxyStorageService.saveConfig(
                            coreAppPackageNames: widget.layoutEngine!.coreAppPackageNames,
                            customConstellations: widget.layoutEngine!.customConstellations,
                            constellationAppOverrides: widget.layoutEngine!.constellationAppOverrides,
                            hiddenPackageNames: widget.layoutEngine!.hiddenPackageNames,
                          );
                          widget.onActionCompleted?.call();
                        } else {
                          final success = widget.layoutEngine!.addAppToCore(app);
                          if (!success) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Center Constellation is full (Max 8 apps). Remove an app first.'),
                                backgroundColor: LuminousHomeTheme.panelRaised,
                              ),
                            );
                          } else {
                            GalaxyStorageService.saveConfig(
                              coreAppPackageNames: widget.layoutEngine!.coreAppPackageNames,
                              customConstellations: widget.layoutEngine!.customConstellations,
                              constellationAppOverrides: widget.layoutEngine!.constellationAppOverrides,
                              hiddenPackageNames: widget.layoutEngine!.hiddenPackageNames,
                            );
                            widget.onActionCompleted?.call();
                          }
                        }
                      },
                    );
                  }),

                  // Hide / Unhide from Galaxy
                  Builder(builder: (context) {
                    final isHidden = widget.layoutEngine!.hiddenPackageNames.contains(app.packageName);

                    return _actionTile(
                      context,
                      icon: isHidden ? Icons.visibility_rounded : Icons.visibility_off_rounded,
                      label: isHidden ? 'Unhide in Galaxy' : 'Hide from Galaxy',
                      color: isHidden ? LuminousHomeTheme.mint : LuminousHomeTheme.danger,
                      onTap: (_) {
                        Navigator.of(context).pop();
                        if (isHidden) {
                          widget.layoutEngine!.unhideApp(app.packageName);
                        } else {
                          widget.layoutEngine!.hideApp(app.packageName);
                        }
                        GalaxyStorageService.saveConfig(
                          coreAppPackageNames: widget.layoutEngine!.coreAppPackageNames,
                          customConstellations: widget.layoutEngine!.customConstellations,
                          constellationAppOverrides: widget.layoutEngine!.constellationAppOverrides,
                          hiddenPackageNames: widget.layoutEngine!.hiddenPackageNames,
                        );
                        widget.onActionCompleted?.call();
                      },
                    );
                  }),
                ],

                _actionTile(
                  context,
                  icon: Icons.info_outline_rounded,
                  label: 'App Details & Permissions',
                  color: LuminousHomeTheme.white70,
                  onTap: (_) {
                    Navigator.of(context).pop();
                    LauncherBridge.openAppInfo(app);
                  },
                ),
                if (!app.isSystemApp)
                  _actionTile(
                    context,
                    icon: Icons.delete_outline_rounded,
                    label: 'Uninstall',
                    color: LuminousHomeTheme.danger,
                    onTap: (_) {
                      Navigator.of(context).pop();
                      LauncherBridge.uninstallApp(app);
                    },
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// One shortcut as a native-feeling row: icon (or the bolt fallback), label,
  /// a 48 dp target and the shared medium radius.
  Widget _shortcutTile(BuildContext context, AppShortcut shortcut) {
    return Builder(builder: (tileContext) {
      return Semantics(
        button: true,
        label: shortcut.label,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => _launchShortcut(shortcut, _globalRectOf(tileContext)),
            borderRadius: BorderRadius.circular(LuminousHomeTheme.radiusM),
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                minHeight: LuminousHomeTheme.minimumTouchTarget,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                child: Row(
                  children: [
                    SizedBox(
                      width: 26,
                      height: 26,
                      child: Center(child: _shortcutIcon(shortcut)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        shortcut.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: LuminousHomeTheme.textPrimary,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w500,
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
    });
  }

  Widget _shortcutIcon(AppShortcut shortcut) {
    final bytes = shortcut.iconPng;
    if (bytes == null) {
      return Icon(
        Icons.bolt_rounded,
        color: LuminousHomeTheme.accent,
        size: 22,
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Image.memory(
        bytes,
        width: 24,
        height: 24,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => Icon(
          Icons.bolt_rounded,
          color: LuminousHomeTheme.accent,
          size: 22,
        ),
      ),
    );
  }

  Widget _actionTile(
    BuildContext context, {
    required IconData icon,
    required String label,
    required Color color,
    required void Function(Rect? sourceBounds) onTap,
  }) {
    return Builder(builder: (tileContext) {
      return ListTile(
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
        leading: Icon(icon, color: color, size: 20),
        title: Text(
          label,
          style: TextStyle(color: color, fontSize: 13.5, fontWeight: FontWeight.w500),
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(LuminousHomeTheme.radiusM)),
        onTap: () => onTap(_globalRectOf(tileContext)),
      );
    });
  }
}
