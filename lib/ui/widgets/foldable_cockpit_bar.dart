import 'dart:ui';
import 'package:flutter/material.dart';
import '../../core/foldable_controller.dart';
import '../../canvas/camera_controller.dart';
import '../../core/galaxy_layout_engine.dart';
import 'foldable_simulation_chip.dart';
import 'comet_orb.dart';

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
        padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 8.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Expandable Fold Simulation Controller
            if (_showFoldControls)
              Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xDD0D111F),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0x6600E5FF), width: 1.0),
                  boxShadow: const [
                    BoxShadow(color: Color(0x3300E5FF), blurRadius: 16),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Row(
                            children: [
                              const Icon(Icons.screen_rotation_rounded, color: Color(0xFF00E5FF), size: 18),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  'Foldable Posture: ${posture.name.toUpperCase()} (${angle.toStringAsFixed(0)}°)',
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 0.8,
                                  ),
                                ),
                              ),
                              if (widget.foldable.isSimulated) ...[
                                const SizedBox(width: 8),
                                FoldableSimulationChip(foldable: widget.foldable),
                              ],
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded, color: Colors.white70, size: 18),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          onPressed: () => setState(() => _showFoldControls = false),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _presetButton('Cover (0°)', DevicePosture.folded),
                        _presetButton('Tabletop (90°)', DevicePosture.tabletop),
                        _presetButton('Main Screen (180°)', DevicePosture.flat),
                      ],
                    ),
                    const SizedBox(height: 4),
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        activeTrackColor: const Color(0xFF00E5FF),
                        inactiveTrackColor: Colors.white24,
                        thumbColor: Colors.white,
                        overlayColor: const Color(0x3300E5FF),
                        trackHeight: 3.0,
                      ),
                      child: Slider(
                        value: angle,
                        min: 0.0,
                        max: 180.0,
                        onChanged: (v) => widget.foldable.setHingeAngle(v),
                      ),
                    ),
                  ],
                ),
              ),

            // Main Glassmorphic Dock Bar
            ClipRRect(
              borderRadius: BorderRadius.circular(30),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: Container(
                  height: 60,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xAA0E1222),
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(
                      color: const Color(0x44FFFFFF),
                      width: 1.0,
                    ),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x33000000),
                        blurRadius: 20,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      _cockpitIconButton(
                        icon: Icons.search_rounded,
                        color: const Color(0xFF00E5FF),
                        tooltip: 'Search apps',
                        onTap: widget.onOpenSearch,
                      ),

                      // The comet: the only warm control in a cold bar. It
                      // borrows the galaxy core's amber, so it reads as the one
                      // affordance that reaches outside the galaxy.
                      if (widget.onOpenWebSearch != null)
                        Semantics(
                          button: true,
                          label: 'Search the web',
                          child: TextButton(
                            onPressed: widget.onOpenWebSearch,
                            style: TextButton.styleFrom(
                              // 48dp minimum; shrinkWrap was explicitly
                              // opting out of it. The orb stays 22px.
                              minimumSize: const Size(48, 48),
                              padding: EdgeInsets.zero,
                              shape: const CircleBorder(),
                            ),
                            child: const Tooltip(
                              message: 'Search the web',
                              child: CometOrb(size: 22),
                            ),
                          ),
                        ),

                      // Constellation Jump Shortcuts
                      Expanded(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          physics: const BouncingScrollPhysics(),
                          padding: const EdgeInsets.symmetric(horizontal: 4.0),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Render dynamic chips for all active constellations
                              ...widget.layoutEngine.constellations.map((c) {
                                return GestureDetector(
                                  onLongPress: c.id == 'core'
                                      ? widget.onEditCore
                                      : null,
                                  child: _constellationChip(
                                    c.name,
                                    c.primaryColor,
                                    () => _jumpToConstellation(c.id),
                                  ),
                                );
                              }),

                              // + Button to create a new Constellation
                              if (widget.onCreateConstellation != null || widget.onCreateGalaxy != null)
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 3.0),
                                  child: Material(
                                    color: Colors.transparent,
                                    child: InkWell(
                                      onTap: widget.onCreateConstellation ?? widget.onCreateGalaxy,
                                      borderRadius: BorderRadius.circular(16),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF00E5FF).withValues(alpha: 0.12),
                                          borderRadius: BorderRadius.circular(16),
                                          border: Border.all(color: const Color(0xFF00E5FF).withValues(alpha: 0.5)),
                                        ),
                                        child: const Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.add_rounded, size: 14, color: Color(0xFF00E5FF)),
                                            SizedBox(width: 2),
                                            Text(
                                              'Constellation',
                                              style: TextStyle(
                                                color: Color(0xFF00E5FF),
                                                fontSize: 11,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),

                      _cockpitIconButton(
                        icon: Icons.filter_center_focus_rounded,
                        color: Colors.white70,
                        tooltip: 'Recenter galaxy',
                        onTap: () {
                          widget.layoutEngine.collapseAllExceptCore();
                          widget.camera.resetView();
                        },
                      ),

                      if (!widget.foldable.isFolded)
                        _cockpitIconButton(
                          icon: Icons.splitscreen_rounded,
                          color: _showFoldControls ? const Color(0xFF00E5FF) : Colors.white70,
                          tooltip: 'Foldable simulator',
                          onTap: () => setState(() => _showFoldControls = !_showFoldControls),
                        ),

                      if (!widget.foldable.isFolded)
                        _cockpitIconButton(
                          icon: Icons.lock_outline_rounded,
                          color: Colors.white70,
                          tooltip: 'Lock screen',
                          onTap: widget.onLock,
                        ),

                      _cockpitIconButton(
                        icon: Icons.settings_outlined,
                        color: Colors.white70,
                        tooltip: 'Settings',
                        onTap: widget.onOpenSettings,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _cockpitIconButton({
    required IconData icon,
    required Color color,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    // 48dp, the Android minimum. The icon itself stays 19px, so this widens
    // what a finger can hit without changing how the dock looks.
    return SizedBox(
      width: 48,
      height: 48,
      child: IconButton(
        icon: Icon(icon, color: color, size: 19),
        tooltip: tooltip,
        padding: EdgeInsets.zero,
        splashRadius: 18,
        onPressed: onTap,
      ),
    );
  }

  Widget _constellationChip(String label, Color color, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3.0),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withValues(alpha: 0.35), width: 1.0),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
        ),
      ),
    );
  }

  Widget _presetButton(String label, DevicePosture p) {
    final isSelected = widget.foldable.posture == p;
    return InkWell(
      onTap: () => widget.foldable.setPosture(p),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0x3300E5FF) : Colors.white10,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? const Color(0xFF00E5FF) : Colors.white24,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? const Color(0xFF00E5FF) : Colors.white70,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
