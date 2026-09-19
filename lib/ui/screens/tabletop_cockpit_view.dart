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
      if (mounted) {
        setState(() => _now = DateTime.now());
      }
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
      color: const Color(0xFF060914),
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
                        onConstellationLongPressed: widget.onConstellationLongPressed,
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
        '${_weekdayName(_now.weekday).toUpperCase()} • ${_monthName(_now.month).toUpperCase()} ${_now.day}';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            const Color(0xFF020306).withValues(alpha: 0.75),
            Colors.transparent,
          ],
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Top Row: Hinge Telemetry Badge & Optional Fullscreen Toggle
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0x3300E5FF),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0x6600E5FF), width: 1.0),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x2200E5FF),
                      blurRadius: 8,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color(0xFF00E5FF),
                      ),
                    ),
                    const SizedBox(width: 7),
                    Text(
                      'OPPO N6 FLEX MODE • ${widget.foldable.hingeAngle.round()}°',
                      style: const TextStyle(
                        color: Color(0xFF00E5FF),
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
              if (widget.onToggleFullscreen != null)
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: widget.onToggleFullscreen,
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0x22141A2E),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0x4464B5F6), width: 0.8),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.fullscreen_rounded, color: Color(0xFF00E5FF), size: 14),
                          SizedBox(width: 4),
                          Text(
                            'FULLSCREEN',
                            style: TextStyle(
                              color: Color(0xFF00E5FF),
                              fontSize: 9.5,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.0,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
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
                    color: Colors.white,
                    fontSize: 52,
                    fontWeight: FontWeight.w200,
                    letterSpacing: -1.5,
                    height: 1.0,
                    shadows: [
                      Shadow(color: Color(0x8800E5FF), blurRadius: 24),
                    ],
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  dateStr,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.70),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 2.0,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // Quick System Search Trigger Pill
          GestureDetector(
            onTap: widget.onOpenSearch,
            child: Container(
              width: 270,
              height: 36,
              decoration: BoxDecoration(
                color: const Color(0xFF141C34).withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0x4464B5F6), width: 1.0),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                children: [
                  const Icon(Icons.search_rounded, color: Color(0xFF00E5FF), size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Search galaxy applications...',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.5),
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCreaseDivider() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            height: 5,
            margin: const EdgeInsets.symmetric(horizontal: 20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(2.5),
              gradient: const LinearGradient(
                colors: [
                  Colors.transparent,
                  Color(0x3300E5FF),
                  Color(0xCC00E5FF),
                  Color(0x3300E5FF),
                  Colors.transparent,
                ],
              ),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x4400E5FF),
                  blurRadius: 10,
                  spreadRadius: 1,
                ),
              ],
            ),
          ),
          const SizedBox(height: 3),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0x3310162A),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0x3300E5FF), width: 0.8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _isLaunchpadCollapsed
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  color: const Color(0xFF00E5FF),
                  size: 14,
                ),
                const SizedBox(width: 4),
                Text(
                  _isLaunchpadCollapsed ? 'EXPAND LAUNCHPAD' : 'COLLAPSE PANEL',
                  style: const TextStyle(
                    color: Color(0xFF00E5FF),
                    fontSize: 8.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.0,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCollapsedCockpitBar() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: const BoxDecoration(
        color: Color(0xCC0A0E1C),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _cockpitActionButton(
              icon: Icons.grid_view_rounded,
              label: 'Launchpad',
              color: const Color(0xFF00E5FF),
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() => _isLaunchpadCollapsed = false);
              },
            ),
            _cockpitActionButton(
              icon: Icons.search_rounded,
              label: 'Search',
              color: const Color(0xFF00E5FF),
              onTap: widget.onOpenSearch,
            ),
            if (widget.onToggleFullscreen != null)
              _cockpitActionButton(
                icon: Icons.fullscreen_rounded,
                label: 'Fullscreen',
                color: const Color(0xFF00E5FF),
                onTap: widget.onToggleFullscreen!,
              ),
            if (widget.onCreateConstellation != null)
              _cockpitActionButton(
                icon: Icons.add_circle_outline_rounded,
                label: 'Create',
                color: const Color(0xFF69F0AE),
                onTap: widget.onCreateConstellation!,
              ),
            if (widget.onEditCore != null)
              _cockpitActionButton(
                icon: Icons.hub_rounded,
                label: 'Center Hub',
                color: const Color(0xFFFFD54F),
                onTap: widget.onEditCore!,
              ),
            _cockpitActionButton(
              icon: Icons.lock_outline_rounded,
              label: 'Lock',
              color: const Color(0xFFFF8A80),
              onTap: widget.onLock,
            ),
            _cockpitActionButton(
              icon: Icons.tune_rounded,
              label: 'Settings',
              color: Colors.white70,
              onTap: widget.onOpenSettings,
            ),
          ],
        ),
      ),
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
      decoration: const BoxDecoration(
        color: Color(0x990A0E1C),
      ),
      child: Column(
        children: [
          // Sector Selector Chips Row
          SizedBox(
            height: 36,
            child: ListView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              children: [
                _sectorChip(
                  label: 'Essentials',
                  icon: Icons.star_rounded,
                  color: const Color(0xFFFFD54F),
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
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _cockpitActionButton(
                  icon: Icons.search_rounded,
                  label: 'Search',
                  color: const Color(0xFF00E5FF),
                  onTap: widget.onOpenSearch,
                ),
                if (widget.onCreateConstellation != null)
                  _cockpitActionButton(
                    icon: Icons.add_circle_outline_rounded,
                    label: 'Create',
                    color: const Color(0xFF69F0AE),
                    onTap: widget.onCreateConstellation!,
                  ),
                if (widget.onEditCore != null)
                  _cockpitActionButton(
                    icon: Icons.hub_rounded,
                    label: 'Center Hub',
                    color: const Color(0xFFFFD54F),
                    onTap: widget.onEditCore!,
                  ),
                _cockpitActionButton(
                  icon: Icons.lock_outline_rounded,
                  label: 'Lock',
                  color: const Color(0xFFFF8A80),
                  onTap: widget.onLock,
                ),
                _cockpitActionButton(
                  icon: Icons.tune_rounded,
                  label: 'Settings',
                  color: Colors.white70,
                  onTap: widget.onOpenSettings,
                ),
              ],
            ),
          ),
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
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: isSelected
                ? color.withValues(alpha: 0.25)
                : const Color(0xFF141A2E).withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: isSelected ? color : Colors.white.withValues(alpha: 0.15),
              width: isSelected ? 1.4 : 1.0,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: isSelected ? color : Colors.white70),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: isSelected ? Colors.white : Colors.white70,
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTactileAppButton(AppEntry app) {
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
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFF12172C).withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: app.accentColor.withValues(alpha: 0.35),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: app.accentColor.withValues(alpha: 0.15),
                blurRadius: 12,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Circular Normalized App Icon
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: app.accentColor.withValues(alpha: 0.15),
                  border: Border.all(
                    color: app.accentColor.withValues(alpha: 0.5),
                    width: 1.2,
                  ),
                ),
                child: ClipOval(
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
                  color: Colors.white,
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
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(height: 3),
              Text(
                label,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 10.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
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
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return names[(month - 1).clamp(0, 11)];
  }
}
