import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import '../../models/app_entry.dart';
import '../../models/constellation.dart';
import '../../core/galaxy_layout_engine.dart';
import '../../core/galaxy_storage_service.dart';
import '../theme/luminous_home_theme.dart';

class ConstellationEditorModal extends StatefulWidget {
  final Constellation constellation;
  final GalaxyLayoutEngine layoutEngine;
  final List<AppEntry> allApps;
  final VoidCallback onUpdated;

  const ConstellationEditorModal({
    super.key,
    required this.constellation,
    required this.layoutEngine,
    required this.allApps,
    required this.onUpdated,
  });

  @override
  State<ConstellationEditorModal> createState() => _ConstellationEditorModalState();
}

class _ConstellationEditorModalState extends State<ConstellationEditorModal> {
  late List<AppEntry> _constellationApps;
  bool get _isCore => widget.constellation.id == 'core';

  /// The editor's own messenger, so an Undo snackbar shows above the editor
  /// instead of under it on the home scaffold, where it could not be tapped.
  final GlobalKey<ScaffoldMessengerState> _messengerKey =
      GlobalKey<ScaffoldMessengerState>();

  /// The engine's current object for this group. A rename replaces the
  /// [Constellation] instance in the engine, so [ConstellationEditorModal]'s
  /// own reference can go stale; look it up by id instead.
  Constellation get _constellation =>
      widget.layoutEngine.constellations
          .where((c) => c.id == widget.constellation.id)
          .firstOrNull ??
      widget.constellation;

  int get _limit => _isCore
      ? GalaxyLayoutEngine.maxCoreApps
      : GalaxyLayoutEngine.maxConstellationApps;

  @override
  void initState() {
    super.initState();
    _constellationApps = List.from(widget.constellation.apps);
  }

  void _persist() {
    GalaxyStorageService.saveConfig(
      coreAppPackageNames: widget.layoutEngine.corePackageNames,
      customConstellations: widget.layoutEngine.customConstellations,
      constellationAppOverrides: widget.layoutEngine.constellationAppOverrides,
      hiddenPackageNames: widget.layoutEngine.hiddenPackageNames,
    );
  }

  void _saveChanges() {
    final pkgNames = _constellationApps.map((a) => a.packageName).toList();
    widget.layoutEngine.setConstellationAppPackages(widget.constellation.id, pkgNames);
    widget.onUpdated();
    _persist();
  }

  void _removeApp(int index) {
    final removed = _constellationApps[index];
    setState(() {
      _constellationApps.removeAt(index);
    });
    _saveChanges();

    // The removal saved instantly; offer the way back.
    _messengerKey.currentState
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('${removed.label} removed from ${_constellation.name}'),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () => _undoRemove(removed, index),
          ),
        ),
      );
  }

  void _undoRemove(AppEntry app, int index) {
    if (!mounted) return;
    if (_constellationApps.any((a) => a.packageName == app.packageName) ||
        _constellationApps.length >= _limit) {
      return;
    }
    setState(() {
      _constellationApps.insert(index.clamp(0, _constellationApps.length), app);
    });
    _saveChanges();
  }

  Future<void> _renameGroup() async {
    final current = _constellation;
    final String? name = await showDialog<String>(
      context: context,
      builder: (_) => _RenameGroupDialog(initialName: current.name),
    );
    final trimmed = name?.trim() ?? '';
    if (!mounted || trimmed.isEmpty || trimmed == current.name) return;

    // Same id, so the engine replaces the group in place and keeps its
    // colour, emblem and members.
    widget.layoutEngine.createCustomConstellation(
      id: current.id,
      name: trimmed,
      primaryColor: current.primaryColor,
      emblemIcon: current.emblemIcon,
      packageNames: List<String>.from(current.customPackageNames),
    );
    setState(() {});
    widget.onUpdated();
    _persist();
  }

  Future<void> _deleteGroup() async {
    final current = _constellation;
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: LuminousHomeTheme.panelRaised,
        title: Text('Delete “${current.name}”?', style: LuminousHomeTheme.headline),
        content: Text(
          'The group is removed. Its apps stay installed and go back to their usual groups.',
          style: LuminousHomeTheme.body,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: LuminousHomeTheme.danger),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    widget.layoutEngine.deleteConstellation(current.id);
    widget.onUpdated();
    // customConstellations is written as a whole list, so the deleted group
    // is gone from storage too.
    _persist();
    Navigator.of(context).pop();
  }

  void _openAppPicker({int? replaceIndex}) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        String searchQuery = '';
        return StatefulBuilder(
          builder: (context, setModalState) {
            final availableApps = widget.allApps.where((app) {
              final alreadyIn = _constellationApps.any((a) => a.packageName == app.packageName);
              if (alreadyIn &&
                  (replaceIndex == null || _constellationApps[replaceIndex].packageName != app.packageName)) {
                return false;
              }
              if (searchQuery.isNotEmpty) {
                return app.label.toLowerCase().contains(searchQuery.toLowerCase()) ||
                    app.packageName.toLowerCase().contains(searchQuery.toLowerCase());
              }
              return true;
            }).toList();

            return BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
              child: Container(
                height: MediaQuery.of(context).size.height * 0.72,
                decoration: BoxDecoration(
                  color: LuminousHomeTheme.panelScrim,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                  border: Border(
                    top: BorderSide(
                      color: _constellation.primaryColor.withValues(alpha: 0.6),
                      width: 1.2,
                    ),
                  ),
                ),
                child: Column(
                  children: [
                    Container(
                      margin: const EdgeInsets.only(top: 10, bottom: 8),
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: LuminousHomeTheme.white24,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                      child: Row(
                        children: [
                          Icon(
                            _constellation.emblemIcon,
                            color: _constellation.primaryColor,
                            size: 22,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            replaceIndex != null
                                ? 'Replace app in ${_constellation.name}'
                                : 'Add app to ${_constellation.name}',
                            style: LuminousHomeTheme.title.copyWith(
                              color: LuminousHomeTheme.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            '${_constellationApps.length}/$_limit apps',
                            style: LuminousHomeTheme.label.copyWith(
                              color: _constellation.primaryColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Container(
                        height: 46,
                        decoration: BoxDecoration(
                          color: LuminousHomeTheme.panelRaised,
                          borderRadius: BorderRadius.circular(LuminousHomeTheme.radiusL),
                          border: Border.all(color: LuminousHomeTheme.white12),
                        ),
                        child: TextField(
                          onChanged: (q) => setModalState(() => searchQuery = q),
                          style: LuminousHomeTheme.body.copyWith(color: LuminousHomeTheme.white),
                          decoration: InputDecoration(
                            hintText: 'Search apps...',
                            hintStyle: LuminousHomeTheme.body.copyWith(color: LuminousHomeTheme.white38),
                            prefixIcon: Icon(Icons.search_rounded,
                                color: _constellation.primaryColor, size: 20),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                        physics: const ClampingScrollPhysics(),
                        itemCount: availableApps.length,
                        itemBuilder: (context, index) {
                          final app = availableApps[index];
                          final owner = widget.layoutEngine.ownerOf(app.packageName);
                          final ownerName =
                              (owner != null && owner.id != _constellation.id) ? owner.name : null;
                          final iconCacheExtent =
                              (38 * MediaQuery.devicePixelRatioOf(context)).round();
                          return Container(
                            margin: const EdgeInsets.only(bottom: 6),
                            decoration: BoxDecoration(
                              color: LuminousHomeTheme.panel.withValues(alpha: 0.6),
                              borderRadius: BorderRadius.circular(LuminousHomeTheme.radiusM),
                              border: Border.all(color: app.accentColor.withValues(alpha: 0.2)),
                            ),
                            child: Material(
                              type: MaterialType.transparency,
                              child: ListTile(
                                dense: true,
                                leading: Container(
                                  width: 38,
                                  height: 38,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(10),
                                    color: app.accentColor.withValues(alpha: 0.15),
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: app.iconBytes != null
                                        ? Image.memory(
                                            app.iconBytes!,
                                            fit: BoxFit.cover,
                                            cacheWidth: iconCacheExtent,
                                            cacheHeight: iconCacheExtent,
                                            gaplessPlayback: true,
                                          )
                                        : Icon(app.fallbackIcon, color: app.accentColor, size: 20),
                                  ),
                                ),
                                title: Text(
                                  app.label,
                                  style: const TextStyle(color: LuminousHomeTheme.white, fontWeight: FontWeight.w600),
                                ),
                                subtitle: Text(
                                  ownerName != null ? 'In $ownerName' : app.packageName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: LuminousHomeTheme.caption.copyWith(
                                    color: LuminousHomeTheme.white38,
                                    fontWeight: FontWeight.w400,
                                    letterSpacing: 0,
                                  ),
                                ),
                                trailing: Icon(
                                  ownerName != null
                                      ? Icons.swap_horiz_rounded
                                      : Icons.add_circle_outline_rounded,
                                  color: _constellation.primaryColor,
                                ),
                                onTap: () {
                                  if (ownerName != null) {
                                    final moved = widget.layoutEngine.moveAppToConstellation(
                                      _constellation.id,
                                      app,
                                    );
                                    if (!moved) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            '${_constellation.name} holds up to $_limit apps. Remove an app first.',
                                          ),
                                          backgroundColor: LuminousHomeTheme.panelRaised,
                                        ),
                                      );
                                      return;
                                    }
                                    Navigator.of(context).pop();
                                    setState(() {
                                      _constellationApps = List.from(_constellation.apps);
                                    });
                                    widget.onUpdated();
                                    _persist();
                                    return;
                                  }
                                  Navigator.of(context).pop();
                                  setState(() {
                                    if (replaceIndex != null && replaceIndex < _constellationApps.length) {
                                      _constellationApps[replaceIndex] = app;
                                    } else if (_constellationApps.length < _limit) {
                                      _constellationApps.add(app);
                                    }
                                  });
                                  _saveChanges();
                                },
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = _constellation;
    final int iconCacheExtent =
        (48 * MediaQuery.devicePixelRatioOf(context)).round();

    // A local messenger and transparent scaffold host the Undo snackbar above
    // the editor. The scaffold's material absorbs taps, so a tap outside the
    // card closes the editor explicitly, as the route barrier did before.
    return ScaffoldMessenger(
      key: _messengerKey,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => Navigator.of(context).pop(),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Center(
              child: GestureDetector(
                // Taps on the card itself must not fall through to the dismiss.
                behavior: HitTestBehavior.opaque,
                onTap: () {},
                child: Container(
                  width: 340,
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.78,
                  ),
                  margin: const EdgeInsets.symmetric(horizontal: 20),
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(
                    color: LuminousHomeTheme.panelScrim,
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(
                      color: c.primaryColor.withValues(alpha: 0.4),
                      width: 1.2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: c.primaryColor.withValues(alpha: 0.25),
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
                        // Header
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: c.primaryColor.withValues(alpha: 0.15),
                                border: Border.all(color: c.primaryColor.withValues(alpha: 0.6)),
                              ),
                              child: Icon(c.emblemIcon, color: c.primaryColor, size: 24),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    c.name,
                                    style: LuminousHomeTheme.headline.copyWith(
                                      color: LuminousHomeTheme.white,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 0.5,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Text(
                                    '${_constellationApps.length} of $_limit apps',
                                    style: LuminousHomeTheme.chipLabel.copyWith(
                                      color: LuminousHomeTheme.white54,
                                      fontWeight: FontWeight.w400,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close_rounded, color: LuminousHomeTheme.white70, size: 22),
                              onPressed: () => Navigator.of(context).pop(),
                            ),
                          ],
                        ),

                        const SizedBox(height: 16),

                        // Radial View for Core, or Scrollable Grid/Wrap for outer constellations
                        if (_isCore)
                          // Core Radial Visual Preview
                          SizedBox(
                            width: 230,
                            height: 230,
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                Container(
                                  width: 165,
                                  height: 165,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: c.primaryColor.withValues(alpha: 0.2),
                                      width: 1.2,
                                    ),
                                  ),
                                ),
                                Container(
                                  width: 46,
                                  height: 46,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: RadialGradient(
                                      colors: [c.primaryColor, c.secondaryColor],
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: c.primaryColor.withValues(alpha: 0.4),
                                        blurRadius: 16,
                                      ),
                                    ],
                                  ),
                                  child: const Icon(Icons.auto_awesome, color: LuminousHomeTheme.panel, size: 22),
                                ),
                                ...List.generate(GalaxyLayoutEngine.maxCoreApps, (index) {
                                  final angle = (index * 2 * math.pi / GalaxyLayoutEngine.maxCoreApps) - (math.pi / 2);
                                  const radius = 82.0;
                                  final offset = Offset(math.cos(angle) * radius, math.sin(angle) * radius);
                                  final bool isFilled = index < _constellationApps.length;
                                  final app = isFilled ? _constellationApps[index] : null;

                                  return Transform.translate(
                                    offset: offset,
                                    child: GestureDetector(
                                      onTap: () {
                                        if (isFilled) {
                                          _openAppPicker(replaceIndex: index);
                                        } else {
                                          _openAppPicker();
                                        }
                                      },
                                      child: Stack(
                                        clipBehavior: Clip.none,
                                        children: [
                                          Container(
                                            width: 44,
                                            height: 44,
                                            decoration: BoxDecoration(
                                              borderRadius: BorderRadius.circular(LuminousHomeTheme.radiusM),
                                              color: isFilled
                                                  ? LuminousHomeTheme.panelRaised
                                                  : LuminousHomeTheme.panel.withValues(alpha: 0.5),
                                              border: Border.all(
                                                color: isFilled
                                                    ? c.primaryColor.withValues(alpha: 0.7)
                                                    : LuminousHomeTheme.white24,
                                                width: 1.2,
                                              ),
                                            ),
                                            child: isFilled
                                                ? ClipRRect(
                                                    borderRadius: BorderRadius.circular(11),
                                                    child: app!.iconBytes != null
                                                        ? Image.memory(
                                                            app.iconBytes!,
                                                            fit: BoxFit.cover,
                                                            cacheWidth: iconCacheExtent,
                                                            cacheHeight: iconCacheExtent,
                                                            gaplessPlayback: true,
                                                          )
                                                        : Icon(app.fallbackIcon, color: app.accentColor, size: 20),
                                                  )
                                                : const Icon(Icons.add_rounded, color: LuminousHomeTheme.white38, size: 20),
                                          ),
                                          if (isFilled)
                                            Positioned(
                                              top: -4,
                                              right: -4,
                                              child: GestureDetector(
                                                onTap: () => _removeApp(index),
                                                child: Container(
                                                  padding: const EdgeInsets.all(2),
                                                  decoration: const BoxDecoration(
                                                    shape: BoxShape.circle,
                                                    color: LuminousHomeTheme.dangerDeep,
                                                  ),
                                                  child: const Icon(Icons.close_rounded, color: LuminousHomeTheme.white, size: 12),
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  );
                                }),
                              ],
                            ),
                          )
                        else
                          // Outer Constellation: Scrollable App Cards + Add Button
                          Flexible(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxHeight: 280),
                              child: SingleChildScrollView(
                                physics: const ClampingScrollPhysics(),
                                child: Column(
                                  children: [
                                    Wrap(
                                      spacing: 12,
                                      runSpacing: 14,
                                      alignment: WrapAlignment.center,
                                      children: [
                                        ...List.generate(_constellationApps.length, (index) {
                                          final app = _constellationApps[index];
                                          return SizedBox(
                                            width: 62,
                                            child: Column(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Stack(
                                                  clipBehavior: Clip.none,
                                                  children: [
                                                    Container(
                                                      width: 48,
                                                      height: 48,
                                                      decoration: BoxDecoration(
                                                        color: LuminousHomeTheme.panelRaised,
                                                        borderRadius: BorderRadius.circular(LuminousHomeTheme.radiusM),
                                                        border: Border.all(
                                                          color: c.primaryColor.withValues(alpha: 0.5),
                                                          width: 1.2,
                                                        ),
                                                      ),
                                                      child: ClipRRect(
                                                        borderRadius: BorderRadius.circular(LuminousHomeTheme.radiusM),
                                                        child: app.iconBytes != null
                                                            ? Image.memory(
                                                                app.iconBytes!,
                                                                fit: BoxFit.cover,
                                                                cacheWidth: iconCacheExtent,
                                                                cacheHeight: iconCacheExtent,
                                                                gaplessPlayback: true,
                                                              )
                                                            : Icon(app.fallbackIcon,
                                                                color: app.accentColor, size: 24),
                                                      ),
                                                    ),
                                                    Positioned(
                                                      top: -4,
                                                      right: -4,
                                                      child: GestureDetector(
                                                        onTap: () => _removeApp(index),
                                                        child: Container(
                                                          padding: const EdgeInsets.all(3),
                                                          decoration: const BoxDecoration(
                                                            shape: BoxShape.circle,
                                                            color: LuminousHomeTheme.dangerDeep,
                                                            boxShadow: [
                                                              BoxShadow(
                                                                color: LuminousHomeTheme.dangerDeepGlow,
                                                                blurRadius: 4,
                                                              ),
                                                            ],
                                                          ),
                                                          child: const Icon(Icons.close_rounded,
                                                              color: LuminousHomeTheme.white, size: 12),
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                const SizedBox(height: 4),
                                                Text(
                                                  app.label,
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                  textAlign: TextAlign.center,
                                                  style: LuminousHomeTheme.caption.copyWith(
                                                    color: LuminousHomeTheme.white70,
                                                    fontWeight: FontWeight.w500,
                                                    letterSpacing: 0,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          );
                                        }),

                                        // Add-app tile (only shown while the group has room)
                                        if (_constellationApps.length < GalaxyLayoutEngine.maxConstellationApps)
                                          GestureDetector(
                                            onTap: () => _openAppPicker(),
                                            child: SizedBox(
                                              width: 62,
                                              child: Column(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Container(
                                                    width: 48,
                                                    height: 48,
                                                    decoration: BoxDecoration(
                                                      color: c.primaryColor.withValues(alpha: 0.1),
                                                      borderRadius: BorderRadius.circular(LuminousHomeTheme.radiusM),
                                                      border: Border.all(
                                                        color: c.primaryColor.withValues(alpha: 0.4),
                                                        width: 1.2,
                                                        style: BorderStyle.solid,
                                                      ),
                                                    ),
                                                    child: Icon(Icons.add_rounded,
                                                        color: c.primaryColor, size: 26),
                                                  ),
                                                  const SizedBox(height: 4),
                                                  Text(
                                                    'Add app',
                                                    style: LuminousHomeTheme.caption.copyWith(
                                                      color: c.primaryColor.withValues(alpha: 0.8),
                                                      letterSpacing: 0,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),

                        const SizedBox(height: 16),

                        Text(
                          _isCore
                              ? 'Tap a slot to add or replace an app.'
                              : 'Tap ✕ to remove an app or + to add one.',
                          style: LuminousHomeTheme.chipLabel.copyWith(
                            color: LuminousHomeTheme.white54,
                            fontWeight: FontWeight.w400,
                            letterSpacing: 0.3,
                          ),
                          textAlign: TextAlign.center,
                        ),

                        const SizedBox(height: 18),

                        // Custom groups can be renamed or deleted here. Built-in groups
                        // and Essentials are part of the layout and stay.
                        if (c.isCustom) ...[
                          Row(
                            children: [
                              Expanded(
                                child: TextButton.icon(
                                  style: TextButton.styleFrom(
                                    foregroundColor: LuminousHomeTheme.textSecondary,
                                    minimumSize: const Size(0, LuminousHomeTheme.minimumTouchTarget),
                                  ),
                                  onPressed: _renameGroup,
                                  icon: const Icon(Icons.edit_outlined, size: 18),
                                  label: const Text('Rename'),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: TextButton.icon(
                                  style: TextButton.styleFrom(
                                    foregroundColor: LuminousHomeTheme.danger,
                                    minimumSize: const Size(0, LuminousHomeTheme.minimumTouchTarget),
                                  ),
                                  onPressed: _deleteGroup,
                                  icon: const Icon(Icons.delete_outline_rounded, size: 18),
                                  label: const Text('Delete group'),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                        ],

                        // Done Button
                        SizedBox(
                          width: double.infinity,
                          height: 46,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: c.primaryColor,
                              foregroundColor: LuminousHomeTheme.nodeFill,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(LuminousHomeTheme.radiusL)),
                            ),
                            onPressed: () => Navigator.of(context).pop(),
                            child: Text(
                              'Done',
                              style: LuminousHomeTheme.title.copyWith(
                                color: LuminousHomeTheme.nodeFill,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Asks for a group's new name. Stateful so the text controller lives exactly
/// as long as the dialog, including its exit animation.
class _RenameGroupDialog extends StatefulWidget {
  final String initialName;

  const _RenameGroupDialog({required this.initialName});

  @override
  State<_RenameGroupDialog> createState() => _RenameGroupDialogState();
}

class _RenameGroupDialogState extends State<_RenameGroupDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialName);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: LuminousHomeTheme.panelRaised,
      title: Text('Rename group', style: LuminousHomeTheme.headline),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: 24,
        textCapitalization: TextCapitalization.words,
        style: LuminousHomeTheme.body.copyWith(color: LuminousHomeTheme.white),
        onSubmitted: (value) => Navigator.of(context).pop(value),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
