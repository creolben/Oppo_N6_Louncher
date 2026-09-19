import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/app_entry.dart';
import '../../models/constellation.dart';
import '../../core/launcher_bridge.dart';
import '../../core/foldable_controller.dart';
import '../../core/galaxy_layout_engine.dart';

class TabletopCockpitView extends StatefulWidget {
  final List<AppEntry> apps;
  final FoldableController foldable;
  final GalaxyLayoutEngine layoutEngine;
  final VoidCallback onOpenSearch;
  final VoidCallback onOpenSettings;
  final VoidCallback onLock;
  final Function(AppEntry app, Offset screenPosition)? onAppLongPressed;
  final Function(Constellation constellation)? onConstellationLongPressed;
  final VoidCallback? onCreateConstellation;
  final VoidCallback? onEditCore;

  const TabletopCockpitView({
    super.key,
    required this.apps,
    required this.foldable,
    required this.layoutEngine,
    required this.onOpenSearch,
    required this.onOpenSettings,
    required this.onLock,
    this.onAppLongPressed,
    this.onConstellationLongPressed,
    this.onCreateConstellation,
    this.onEditCore,
  });

  @override
  State<TabletopCockpitView> createState() => _TabletopCockpitViewState();
}

class _TabletopCockpitViewState extends State<TabletopCockpitView> {
  late Timer _timer;
  DateTime _now = DateTime.now();
  String? _selectedSectorId;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() => _now = DateTime.now());
      }
    });
  }

  @override
  void dispose() {
    _timer.cancel();
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
            // TOP HALF: Ambient Cosmic HUD Display (Upright Screen)
            Expanded(
              flex: 5,
              child: _buildTopHudPanel(),
            ),

            // CREASE ILLUMINATION DIVIDER (Hinge Boundary)
            _buildCreaseDivider(),

            // BOTTOM HALF: Tactile Cockpit Launchpad (Flat Desk Surface)
            Expanded(
              flex: 6,
              child: _buildBottomCockpitPanel(core, outerConstellations),
            ),
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
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: Alignment.center,
          radius: 1.2,
          colors: [
            const Color(0xFF101938).withValues(alpha: 0.65),
            Colors.transparent,
          ],
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Device Hinge Telemetry Badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0x3300E5FF),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0x6600E5FF), width: 1.0),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x2200E5FF),
                  blurRadius: 10,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color(0xFF00E5FF),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'OPPO N6 FLEX MODE • ${widget.foldable.hingeAngle.round()}°',
                  style: const TextStyle(
                    color: Color(0xFF00E5FF),
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Luminous Time
          Text(
            timeStr,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 64,
              fontWeight: FontWeight.w200,
              letterSpacing: -2.0,
              height: 1.05,
              shadows: [
                Shadow(color: Color(0x8800E5FF), blurRadius: 28),
              ],
            ),
          ),
          const SizedBox(height: 4),

          // Date & Celestial Telemetry
          Text(
            dateStr,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.65),
              fontSize: 13,
              fontWeight: FontWeight.w600,
              letterSpacing: 2.5,
            ),
          ),
          const SizedBox(height: 14),

          // Quick System Search Trigger Pill
          GestureDetector(
            onTap: widget.onOpenSearch,
            child: Container(
              width: 280,
              height: 40,
              decoration: BoxDecoration(
                color: const Color(0xFF141C34).withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0x4464B5F6), width: 1.0),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                children: [
                  const Icon(Icons.search_rounded, color: Color(0xFF00E5FF), size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Search galaxy applications...',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.45),
                        fontSize: 12.5,
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
      height: 6,
      margin: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(3),
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
                  onTap: () => setState(() => _selectedSectorId = null),
                ),
                const SizedBox(width: 8),
                for (final c in outerConstellations) ...[
                  _sectorChip(
                    label: c.name,
                    icon: c.emblemIcon,
                    color: c.primaryColor,
                    isSelected: _selectedSectorId == c.id,
                    onTap: () => setState(() => _selectedSectorId = c.id),
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
          Row(
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
