import 'dart:ui';

import 'package:flutter/material.dart';

import '../../canvas/camera_controller.dart';
import '../../core/foldable_controller.dart';
import '../../core/galaxy_layout_engine.dart';
import '../theme/luminous_home_theme.dart';
import 'comet_orb.dart';
import 'foldable_simulation_chip.dart';

class FoldableCockpitBar extends StatefulWidget {
  final FoldableController foldable;
  final CameraController camera;
  final GalaxyLayoutEngine layoutEngine;
  final VoidCallback onOpenSearch;
  final VoidCallback onOpenSettings;
  final VoidCallback onLock;
  final VoidCallback? onCreateConstellation;
  final VoidCallback? onCreateGalaxy;
  final VoidCallback? onEditCore;

  /// Summons the comet web-search surface. Optional so the bar can still be
  /// used by surfaces that have no business opening web search.
  final VoidCallback? onOpenWebSearch;

  const FoldableCockpitBar({
    super.key,
    required this.foldable,
    required this.camera,
    required this.layoutEngine,
    required this.onOpenSearch,
    required this.onOpenSettings,
    required this.onLock,
    this.onCreateConstellation,
    this.onCreateGalaxy,
    this.onEditCore,
    this.onOpenWebSearch,
  });

  @override
  State<FoldableCockpitBar> createState() => _FoldableCockpitBarState();
}

class _FoldableCockpitBarState extends State<FoldableCockpitBar> {
  bool _showFoldControls = false;

  void _jumpToConstellation(String id) {
    if (id == 'core') {
      final core = widget.layoutEngine.constellations.firstWhere(
        (element) => element.id == 'core',
      );
      final activeOuter = widget.layoutEngine.constellations.any(
        (c) => c.id != 'core' && c.isExpanded,
      );
      if (activeOuter) {
        widget.layoutEngine.expandOnly('core');
        widget.camera.flyTo(Offset.zero, targetZoom: 1.25);
      } else {
        widget.layoutEngine.toggleCore();
        if (core.isExpanded) {
          widget.camera.flyTo(Offset.zero, targetZoom: 1.25);
        } else {
          widget.camera.flyTo(Offset.zero, targetZoom: 1.05);
        }
      }
    } else {
      final c = widget.layoutEngine.constellations.firstWhere(
        (element) => element.id == id,
        orElse: () => widget.layoutEngine.constellations.first,
      );
      if (c.isExpanded) {
        c.isExpanded = false;
        widget.camera.flyTo(Offset.zero, targetZoom: 1.05);
      } else {
        widget.layoutEngine.expandOnly(id);
        widget.camera.flyTo(c.center, targetZoom: 1.4);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final posture = widget.foldable.posture;
    final angle = widget.foldable.hingeAngle;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_showFoldControls) _buildFoldControls(context, posture, angle),
            _buildShelf(),
          ],
        ),
      ),
    );
  }

  Widget _buildFoldControls(
    BuildContext context,
    DevicePosture posture,
    double angle,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(LuminousHomeTheme.cardRadius),
        boxShadow: LuminousHomeTheme.floatingShadow,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(LuminousHomeTheme.cardRadius),
        child: BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: LuminousHomeTheme.glassBlur,
            sigmaY: LuminousHomeTheme.glassBlur,
          ),
          child: Material(
            color: LuminousHomeTheme.glassOpaque,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(
                  LuminousHomeTheme.cardRadius,
                ),
                border: Border.all(color: LuminousHomeTheme.hairline),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        DecoratedBox(
                          decoration: BoxDecoration(
                            color: LuminousHomeTheme.softTint(
                              LuminousHomeTheme.aqua,
                              0.14,
                            ),
                            borderRadius: BorderRadius.circular(
                              LuminousHomeTheme.iconRadius,
                            ),
                          ),
                          child: const SizedBox.square(
                            dimension: 40,
                            child: Icon(
                              Icons.screen_rotation_rounded,
                              color: LuminousHomeTheme.aqua,
                              size: 20,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Fold position',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: LuminousHomeTheme.textPrimary,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${_postureLabel(posture)} · ${angle.toStringAsFixed(0)}°',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: LuminousHomeTheme.textMuted,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (widget.foldable.isSimulated) ...[
                          const SizedBox(width: 8),
                          FoldableSimulationChip(foldable: widget.foldable),
                        ],
                        IconButton(
                          icon: const Icon(Icons.close_rounded, size: 19),
                          color: LuminousHomeTheme.textSecondary,
                          tooltip: 'Close fold controls',
                          onPressed: () {
                            setState(() => _showFoldControls = false);
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      child: Row(
                        children: [
                          _presetButton('Cover · 0°', DevicePosture.folded),
                          const SizedBox(width: 8),
                          _presetButton(
                            'Tabletop · 90°',
                            DevicePosture.tabletop,
                          ),
                          const SizedBox(width: 8),
                          _presetButton('Main · 180°', DevicePosture.flat),
                        ],
                      ),
                    ),
                    const SizedBox(height: 2),
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        activeTrackColor: LuminousHomeTheme.aqua,
                        inactiveTrackColor: LuminousHomeTheme.hairlineStrong,
                        thumbColor: LuminousHomeTheme.textPrimary,
                        overlayColor: LuminousHomeTheme.softTint(
                          LuminousHomeTheme.aqua,
                          0.16,
                        ),
                        trackHeight: 3,
                      ),
                      child: Slider(
                        value: angle,
                        min: 0,
                        max: 180,
                        semanticFormatterCallback: (value) {
                          return '${value.round()} degrees';
                        },
                        onChanged: (value) {
                          widget.foldable.setHingeAngle(value);
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildShelf() {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(LuminousHomeTheme.dockRadius),
        boxShadow: LuminousHomeTheme.floatingShadow,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(LuminousHomeTheme.dockRadius),
        child: BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: LuminousHomeTheme.glassBlur,
            sigmaY: LuminousHomeTheme.glassBlur,
          ),
          child: Material(
            color: Colors.transparent,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    LuminousHomeTheme.glassStrong,
                    LuminousHomeTheme.glass,
                  ],
                ),
                borderRadius: BorderRadius.circular(
                  LuminousHomeTheme.dockRadius,
                ),
                border: Border.all(color: LuminousHomeTheme.hairline),
              ),
              child: SizedBox(
                height: 64,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Row(
                    children: [
                      _cockpitIconButton(
                        icon: Icons.search_rounded,
                        color: LuminousHomeTheme.aqua,
                        tooltip: 'Search apps',
                        onTap: widget.onOpenSearch,
                      ),
                      if (widget.onOpenWebSearch != null)
                        _cometButton(widget.onOpenWebSearch!),
                      const _ShelfDivider(),
                      ...widget.layoutEngine.constellations.map((
                        constellation,
                      ) {
                        return _constellationShortcut(
                          label: constellation.name,
                          color: constellation.primaryColor,
                          icon: constellation.emblemIcon,
                          onTap: () {
                            _jumpToConstellation(constellation.id);
                          },
                          onLongPress: constellation.id == 'core'
                              ? widget.onEditCore
                              : null,
                        );
                      }),
                      if (widget.onCreateConstellation != null ||
                          widget.onCreateGalaxy != null)
                        _cockpitIconButton(
                          icon: Icons.add_rounded,
                          color: LuminousHomeTheme.aqua,
                          tooltip: 'Create constellation',
                          emphasized: true,
                          onTap:
                              widget.onCreateConstellation ??
                              widget.onCreateGalaxy!,
                        ),
                      const _ShelfDivider(),
                      _cockpitIconButton(
                        icon: Icons.filter_center_focus_rounded,
                        color: LuminousHomeTheme.textSecondary,
                        tooltip: 'Recenter galaxy',
                        onTap: () {
                          widget.layoutEngine.collapseAllExceptCore();
                          widget.camera.resetView();
                        },
                      ),
                      if (!widget.foldable.isFolded)
                        _cockpitIconButton(
                          icon: Icons.splitscreen_rounded,
                          color: _showFoldControls
                              ? LuminousHomeTheme.aqua
                              : LuminousHomeTheme.textSecondary,
                          tooltip: 'Foldable simulator',
                          emphasized: _showFoldControls,
                          onTap: () {
                            setState(
                              () => _showFoldControls = !_showFoldControls,
                            );
                          },
                        ),
                      if (!widget.foldable.isFolded)
                        _cockpitIconButton(
                          icon: Icons.lock_outline_rounded,
                          color: LuminousHomeTheme.textSecondary,
                          tooltip: 'Lock screen',
                          onTap: widget.onLock,
                        ),
                      _cockpitIconButton(
                        icon: Icons.settings_outlined,
                        color: LuminousHomeTheme.textSecondary,
                        tooltip: 'Settings',
                        onTap: widget.onOpenSettings,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _cometButton(VoidCallback onTap) {
    return Semantics(
      button: true,
      label: 'Search the web',
      child: Tooltip(
        message: 'Search the web',
        child: SizedBox.square(
          dimension: LuminousHomeTheme.minimumTouchTarget,
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(LuminousHomeTheme.iconRadius),
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(LuminousHomeTheme.iconRadius),
              child: const Center(
                child: ExcludeSemantics(child: CometOrb(size: 22)),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _cockpitIconButton({
    required IconData icon,
    required Color color,
    required String tooltip,
    required VoidCallback onTap,
    bool emphasized = false,
  }) {
    final radius = BorderRadius.circular(LuminousHomeTheme.iconRadius);
    return Semantics(
      button: true,
      label: tooltip,
      child: Tooltip(
        message: tooltip,
        child: SizedBox.square(
          dimension: LuminousHomeTheme.minimumTouchTarget,
          child: Material(
            color: emphasized
                ? LuminousHomeTheme.softTint(color, 0.16)
                : Colors.transparent,
            borderRadius: radius,
            child: InkWell(
              onTap: onTap,
              borderRadius: radius,
              child: Center(
                child: ExcludeSemantics(
                  child: Icon(icon, color: color, size: 20),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _constellationShortcut({
    required String label,
    required Color color,
    required IconData icon,
    required VoidCallback onTap,
    VoidCallback? onLongPress,
  }) {
    final semanticLabel = 'Open $label constellation';
    final radius = BorderRadius.circular(LuminousHomeTheme.iconRadius);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Semantics(
        button: true,
        label: semanticLabel,
        hint: onLongPress == null ? null : 'Long press to edit',
        onLongPress: onLongPress,
        child: Tooltip(
          message: label,
          child: SizedBox.square(
            dimension: LuminousHomeTheme.minimumTouchTarget,
            child: Material(
              color: LuminousHomeTheme.softTint(color, 0.13),
              borderRadius: radius,
              child: InkWell(
                onTap: onTap,
                onLongPress: onLongPress,
                borderRadius: radius,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    ExcludeSemantics(child: Icon(icon, color: color, size: 20)),
                    Positioned(
                      right: 8,
                      bottom: 8,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                        ),
                        child: const SizedBox.square(dimension: 4),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _presetButton(String label, DevicePosture posture) {
    final isSelected = widget.foldable.posture == posture;
    final radius = BorderRadius.circular(LuminousHomeTheme.controlRadius);
    return Semantics(
      button: true,
      selected: isSelected,
      label: 'Set posture to $label',
      child: Material(
        color: isSelected
            ? LuminousHomeTheme.softTint(LuminousHomeTheme.aqua, 0.16)
            : LuminousHomeTheme.glass,
        borderRadius: radius,
        child: InkWell(
          onTap: () => widget.foldable.setPosture(posture),
          borderRadius: radius,
          child: Container(
            constraints: const BoxConstraints(
              minHeight: LuminousHomeTheme.minimumTouchTarget,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              borderRadius: radius,
              border: Border.all(
                color: isSelected
                    ? LuminousHomeTheme.aqua.withValues(alpha: 0.48)
                    : LuminousHomeTheme.hairline,
              ),
            ),
            alignment: Alignment.center,
            child: Text(
              label,
              style: TextStyle(
                color: isSelected
                    ? LuminousHomeTheme.textPrimary
                    : LuminousHomeTheme.textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _postureLabel(DevicePosture posture) {
    final name = posture.name;
    return '${name[0].toUpperCase()}${name.substring(1)}';
  }
}

class _ShelfDivider extends StatelessWidget {
  const _ShelfDivider();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 4),
      child: SizedBox(
        height: 24,
        child: VerticalDivider(
          width: 1,
          thickness: 1,
          color: LuminousHomeTheme.hairline,
        ),
      ),
    );
  }
}
