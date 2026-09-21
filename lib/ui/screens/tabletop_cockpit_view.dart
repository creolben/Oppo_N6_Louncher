import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/app_entry.dart';
import '../../models/constellation.dart';
import '../../core/launcher_bridge.dart';
import '../../core/foldable_controller.dart';
import '../../core/galaxy_layout_engine.dart';
import '../../canvas/camera_controller.dart';
import '../../canvas/galaxy_interactive_canvas.dart';
import '../theme/luminous_home_theme.dart';

class TabletopCockpitView extends StatefulWidget {
  final List<AppEntry> apps;
  final FoldableController foldable;
  final CameraController? camera;
  final GalaxyLayoutEngine layoutEngine;
  final VoidCallback onOpenSearch;
  final VoidCallback onOpenSettings;
  final VoidCallback onLock;
  final Function(AppEntry app, Offset screenPosition)? onAppLongPressed;
  final Function(Constellation constellation)? onConstellationLongPressed;
  final VoidCallback? onCreateConstellation;
  final VoidCallback? onEditCore;
  final VoidCallback? onToggleFullscreen;

  const TabletopCockpitView({
    super.key,
    required this.apps,
    required this.foldable,
    this.camera,
    required this.layoutEngine,
    required this.onOpenSearch,
    required this.onOpenSettings,
    required this.onLock,
    this.onAppLongPressed,
    this.onConstellationLongPressed,
    this.onCreateConstellation,
    this.onEditCore,
    this.onToggleFullscreen,
  });

  @override
  State<TabletopCockpitView> createState() => _TabletopCockpitViewState();
}

class _TabletopCockpitViewState extends State<TabletopCockpitView> {
  late Timer _timer;
  DateTime _now = DateTime.now();
  String? _selectedSectorId;
  late final CameraController _activeCamera;
  bool _ownsCamera = false;
  bool _isLaunchpadCollapsed = false;

  @override
  void initState() {
    super.initState();
    if (widget.camera != null) {
      _activeCamera = widget.camera!;
      _ownsCamera = false;
    } else {
      _activeCamera = CameraController();
      _ownsCamera = true;
    }
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      // The header renders hours and minutes only: repaint when the visible
      // minute rolls over, as the cover and lock screens already do, instead
      // of rebuilding the whole cockpit once a second.
      final now = DateTime.now();
      if (!mounted || (now.minute == _now.minute && now.hour == _now.hour)) {
        return;
      }
      setState(() => _now = now);
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    if (_ownsCamera) {
      _activeCamera.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final core = widget.layoutEngine.constellations.firstWhere(
      (c) => c.id == 'core',
      orElse: () => widget.layoutEngine.constellations.first,
    );

    final outerConstellations = widget.layoutEngine.constellations
        .where((c) => c.id != 'core')
        .toList();

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            LuminousHomeTheme.backgroundTop,
            LuminousHomeTheme.background,
            LuminousHomeTheme.backgroundDeep,
          ],
          stops: [0.0, 0.58, 1.0],
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            // TOP HALF: Ambient Cosmic Constellation Viewport (Upright Screen)
            Expanded(
              flex: _isLaunchpadCollapsed ? 1 : 5,
              child: ClipRect(
                child: Stack(
                  children: [
                    // 1. Live Interactive Constellation & Starfield Canvas
                    Positioned.fill(
                      child: GalaxyInteractiveCanvas(
                        apps: widget.apps,
                        foldable: widget.foldable,
                        camera: _activeCamera,
                        layoutEngine: widget.layoutEngine,
                        onAppLongPressed: widget.onAppLongPressed,
                        onConstellationLongPressed:
                            widget.onConstellationLongPressed,
                        onSwipeDown: widget.onOpenSearch,
                      ),
                    ),

                    // 2. Cosmic HUD Overlay (Clock, Date, Search Trigger & Telemetry)
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: _buildTopHudPanel(),
                    ),
                  ],
                ),
              ),
            ),

            // CREASE ILLUMINATION DIVIDER (Hinge Boundary) with Collapse Toggle
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() => _isLaunchpadCollapsed = !_isLaunchpadCollapsed);
              },
              child: _buildCreaseDivider(),
            ),

            // BOTTOM HALF: Tactile Cockpit Launchpad (Flat Desk Surface)
            if (!_isLaunchpadCollapsed)
              Expanded(
                flex: 6,
                child: _buildBottomCockpitPanel(core, outerConstellations),
              )
            else
              _buildCollapsedCockpitBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildTopHudPanel() {
    final timeStr =
        '${_now.hour.toString().padLeft(2, '0')}:${_now.minute.toString().padLeft(2, '0')}';
    final dateStr =
        '${_weekdayName(_now.weekday)} • ${_monthName(_now.month)} ${_now.day}';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            LuminousHomeTheme.backgroundDeep.withValues(alpha: 0.86),
            LuminousHomeTheme.background.withValues(alpha: 0.34),
            Colors.transparent,
          ],
          stops: const [0.0, 0.68, 1.0],
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Top Row: Hinge Telemetry Badge & Optional Fullscreen Toggle
          Row(
            children: [
              Expanded(
                child: Container(
                  constraints: const BoxConstraints(minHeight: 32),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: LuminousHomeTheme.glass,
                    borderRadius: BorderRadius.circular(
                      LuminousHomeTheme.controlRadius,
                    ),
                    border: Border.all(
                      color: LuminousHomeTheme.hairline,
                      width: 0.8,
                    ),
                  ),
                  child: Row(
                    children: [
                      const DecoratedBox(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: LuminousHomeTheme.aqua,
                        ),
                        child: SizedBox(width: 6, height: 6),
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          'OPPO N6 FLEX MODE • ${widget.foldable.hingeAngle.round()}°',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: LuminousHomeTheme.textSecondary,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (widget.onToggleFullscreen != null) ...[
                const SizedBox(width: 8),
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: widget.onToggleFullscreen,
                    borderRadius: BorderRadius.circular(
                      LuminousHomeTheme.controlRadius,
                    ),
                    child: Container(
                      constraints: const BoxConstraints(
                        minWidth: LuminousHomeTheme.minimumTouchTarget,
                        minHeight: LuminousHomeTheme.minimumTouchTarget,
                        maxWidth: 128,
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        color: LuminousHomeTheme.glass,
                        borderRadius: BorderRadius.circular(
                          LuminousHomeTheme.controlRadius,
                        ),
                        border: Border.all(
                          color: LuminousHomeTheme.hairline,
                          width: 0.8,
                        ),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.fullscreen_rounded,
                            color: LuminousHomeTheme.aqua,
                            size: 16,
                          ),
                          SizedBox(width: 5),
                          Flexible(
                            child: Text(
                              'Fullscreen',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: LuminousHomeTheme.textSecondary,
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.2,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),

          // Luminous Time & Date (IgnorePointer allows dragging celestial canvas beneath)
          IgnorePointer(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  timeStr,
                  style: const TextStyle(
                    color: LuminousHomeTheme.textPrimary,
                    fontSize: 52,
                    fontWeight: FontWeight.w300,
                    letterSpacing: -1.5,
                    height: 1.0,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  dateStr,
                  style: const TextStyle(
                    color: LuminousHomeTheme.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // Quick System Search Trigger Pill. 48dp tall for the Android touch
          // minimum, and it carries a label: it was a bare GestureDetector, so
          // a screen reader had nothing to focus here at all.
          Semantics(
            button: true,
            label: 'Search apps',
            child: GestureDetector(
              onTap: widget.onOpenSearch,
              child: Container(
                width: 270,
                height: LuminousHomeTheme.minimumTouchTarget,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: LuminousHomeTheme.glassStrong,
                  borderRadius: BorderRadius.circular(
                    LuminousHomeTheme.controlRadius,
                  ),
                  border: Border.all(
                    color: LuminousHomeTheme.hairline,
                    width: 0.8,
                  ),
                  boxShadow: LuminousHomeTheme.floatingShadow,
                ),
                child: const Row(
                  children: [
                    Icon(
                      Icons.search_rounded,
                      color: LuminousHomeTheme.aqua,
                      size: 16,
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Search galaxy applications...',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: LuminousHomeTheme.textMuted,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCreaseDivider() {
    return Container(
      constraints: const BoxConstraints(
        minHeight: LuminousHomeTheme.minimumTouchTarget,
      ),
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            height: 1,
            margin: const EdgeInsets.symmetric(horizontal: 20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.transparent,
                  LuminousHomeTheme.hairline,
                  LuminousHomeTheme.aqua.withValues(alpha: 0.28),
                  LuminousHomeTheme.hairline,
                  Colors.transparent,
                ],
              ),
            ),
          ),
          const SizedBox(height: 5),
          Container(
            constraints: const BoxConstraints(minHeight: 32),
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: LuminousHomeTheme.glass,
              borderRadius: BorderRadius.circular(
                LuminousHomeTheme.controlRadius,
              ),
              border: Border.all(color: LuminousHomeTheme.hairline, width: 0.8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _isLaunchpadCollapsed
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  color: LuminousHomeTheme.aqua,
                  size: 14,
                ),
                const SizedBox(width: 4),
                Text(
                  _isLaunchpadCollapsed ? 'Expand launchpad' : 'Collapse panel',
                  style: const TextStyle(
                    color: LuminousHomeTheme.textSecondary,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionStrip(List<Widget> children) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: constraints.maxWidth),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: children,
            ),
          ),
        );
      },
    );
  }

  Widget _buildCollapsedCockpitBar() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: const BoxDecoration(
        color: LuminousHomeTheme.glassOpaque,
        border: Border(
          top: BorderSide(color: LuminousHomeTheme.hairline, width: 0.8),
        ),
      ),
      child: _buildActionStrip([
        _cockpitActionButton(
          icon: Icons.grid_view_rounded,
          label: 'Launchpad',
          color: LuminousHomeTheme.aqua,
          onTap: () {
            HapticFeedback.selectionClick();
            setState(() => _isLaunchpadCollapsed = false);
          },
        ),
        _cockpitActionButton(
          icon: Icons.search_rounded,
          label: 'Search',
          color: LuminousHomeTheme.aqua,
          onTap: widget.onOpenSearch,
        ),
        if (widget.onToggleFullscreen != null)
          _cockpitActionButton(
            icon: Icons.fullscreen_rounded,
            label: 'Fullscreen',
            color: LuminousHomeTheme.aqua,
            onTap: widget.onToggleFullscreen!,
          ),
        if (widget.onCreateConstellation != null)
          _cockpitActionButton(
            icon: Icons.add_circle_outline_rounded,
            label: 'Create',
            color: LuminousHomeTheme.mint,
            onTap: widget.onCreateConstellation!,
          ),
        if (widget.onEditCore != null)
          _cockpitActionButton(
            icon: Icons.hub_rounded,
            label: 'Center Hub',
            color: LuminousHomeTheme.amber,
            onTap: widget.onEditCore!,
          ),
        _cockpitActionButton(
          icon: Icons.lock_outline_rounded,
          label: 'Lock',
          color: LuminousHomeTheme.rose,
          onTap: widget.onLock,
        ),
        _cockpitActionButton(
          icon: Icons.tune_rounded,
          label: 'Settings',
          color: LuminousHomeTheme.textSecondary,
          onTap: widget.onOpenSettings,
        ),
      ]),
    );
  }

  Widget _buildBottomCockpitPanel(
    Constellation core,
    List<Constellation> outerConstellations,
  ) {
    final activeConstellation = _selectedSectorId == null
        ? core
        : outerConstellations.firstWhere(
            (c) => c.id == _selectedSectorId,
            orElse: () => core,
          );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: const BoxDecoration(color: LuminousHomeTheme.glassOpaque),
      child: Column(
        children: [
          // Sector Selector Chips Row. Tall enough for the 48dp touch minimum;
          // a fixed 36 also clipped these chips once the system font scale
          // grew the label.
          SizedBox(
            height: LuminousHomeTheme.minimumTouchTarget,
            child: ListView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              children: [
                _sectorChip(
                  label: 'Essentials',
                  icon: Icons.star_rounded,
                  color: LuminousHomeTheme.amber,
                  isSelected: _selectedSectorId == null,
                  onTap: () {
                    setState(() => _selectedSectorId = null);
                    _activeCamera.resetView();
                  },
                ),
                const SizedBox(width: 8),
                for (final c in outerConstellations) ...[
                  _sectorChip(
                    label: c.name,
                    icon: c.emblemIcon,
                    color: c.primaryColor,
                    isSelected: _selectedSectorId == c.id,
                    onTap: () {
                      setState(() => _selectedSectorId = c.id);
                      _activeCamera.flyTo(c.center, targetZoom: 1.35);
                    },
                  ),
                  const SizedBox(width: 8),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Tactile Launchpad Grid
          Expanded(
            child: GridView.builder(
              physics: const BouncingScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 10,
                crossAxisSpacing: 12,
                childAspectRatio: 1.12,
              ),
              itemCount: activeConstellation.apps.length,
              itemBuilder: (context, index) {
                final app = activeConstellation.apps[index];
                return _buildTactileAppButton(app);
              },
            ),
          ),

          // Bottom Cockpit Controls Row
          _buildActionStrip([
            _cockpitActionButton(
              icon: Icons.search_rounded,
              label: 'Search',
              color: LuminousHomeTheme.aqua,
              onTap: widget.onOpenSearch,
            ),
            if (widget.onCreateConstellation != null)
              _cockpitActionButton(
                icon: Icons.add_circle_outline_rounded,
                label: 'Create',
                color: LuminousHomeTheme.mint,
                onTap: widget.onCreateConstellation!,
              ),
            if (widget.onEditCore != null)
              _cockpitActionButton(
                icon: Icons.hub_rounded,
                label: 'Center Hub',
                color: LuminousHomeTheme.amber,
                onTap: widget.onEditCore!,
              ),
            _cockpitActionButton(
              icon: Icons.lock_outline_rounded,
              label: 'Lock',
              color: LuminousHomeTheme.rose,
              onTap: widget.onLock,
            ),
            _cockpitActionButton(
              icon: Icons.tune_rounded,
              label: 'Settings',
              color: LuminousHomeTheme.textSecondary,
              onTap: widget.onOpenSettings,
            ),
          ]),
        ],
      ),
    );
  }

  Widget _sectorChip({
    required String label,
    required IconData icon,
    required Color color,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        borderRadius: BorderRadius.circular(LuminousHomeTheme.controlRadius),
        child: Container(
          constraints: const BoxConstraints(
            minHeight: LuminousHomeTheme.minimumTouchTarget,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: isSelected
                ? LuminousHomeTheme.softTint(color, 0.18)
                : LuminousHomeTheme.glass,
            borderRadius: BorderRadius.circular(
              LuminousHomeTheme.controlRadius,
            ),
            border: Border.all(
              color: isSelected
                  ? LuminousHomeTheme.hairlineStrong
                  : LuminousHomeTheme.hairline,
              width: 0.8,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 15,
                color: isSelected ? color : LuminousHomeTheme.textSecondary,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: isSelected
                      ? LuminousHomeTheme.textPrimary
                      : LuminousHomeTheme.textSecondary,
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTactileAppButton(AppEntry app) {
    final tintedGlass = Color.alphaBlend(
      app.accentColor.withValues(alpha: 0.035),
      LuminousHomeTheme.glassStrong,
    );

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          HapticFeedback.mediumImpact();
          LauncherBridge.launchApp(app);
        },
        onLongPress: () {
          HapticFeedback.heavyImpact();
          widget.onAppLongPressed?.call(app, Offset.zero);
        },
        borderRadius: BorderRadius.circular(LuminousHomeTheme.controlRadius),
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [tintedGlass, LuminousHomeTheme.glass],
            ),
            borderRadius: BorderRadius.circular(
              LuminousHomeTheme.controlRadius,
            ),
            border: Border.all(color: LuminousHomeTheme.hairline, width: 0.8),
            boxShadow: LuminousHomeTheme.floatingShadow,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Clean squircle app icon without a nested accent ring.
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: LuminousHomeTheme.glassStrong,
                  borderRadius: BorderRadius.circular(
                    LuminousHomeTheme.iconRadius,
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(
                    LuminousHomeTheme.iconRadius,
                  ),
                  child: app.iconBytes != null
                      ? Image.memory(
                          app.iconBytes!,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) => Icon(
                            app.fallbackIcon,
                            color: app.accentColor,
                            size: 22,
                          ),
                        )
                      : Icon(
                          app.fallbackIcon,
                          color: app.accentColor,
                          size: 22,
                        ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                app.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: LuminousHomeTheme.textPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _cockpitActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          HapticFeedback.lightImpact();
          onTap();
        },
        borderRadius: BorderRadius.circular(LuminousHomeTheme.controlRadius),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minWidth: LuminousHomeTheme.minimumTouchTarget,
            minHeight: LuminousHomeTheme.minimumTouchTarget,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: color, size: 22),
                const SizedBox(height: 3),
                Text(
                  label,
                  style: const TextStyle(
                    color: LuminousHomeTheme.textSecondary,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _weekdayName(int weekday) {
    const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return names[(weekday - 1).clamp(0, 6)];
  }

  String _monthName(int month) {
    const names = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return names[(month - 1).clamp(0, 11)];
  }
}
