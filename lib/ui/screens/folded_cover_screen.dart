import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/app_entry.dart';
import '../../models/constellation.dart';
import '../../core/launcher_bridge.dart';
import '../../core/foldable_controller.dart';
import '../../core/galaxy_layout_engine.dart';

class FoldedCoverScreen extends StatefulWidget {
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

  const FoldedCoverScreen({
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
  State<FoldedCoverScreen> createState() => _FoldedCoverScreenState();
}

class _FoldedCoverScreenState extends State<FoldedCoverScreen>
    with SingleTickerProviderStateMixin {
  late Timer _clockTimer;
  DateTime _now = DateTime.now();

  String? _selectedSectorId;
  bool _showFoldControls = false;

  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {
          _now = DateTime.now();
        });
      }
    });

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _clockTimer.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  Constellation? get _selectedConstellation {
    final outerList = widget.layoutEngine.constellations
        .where((c) => c.id != 'core')
        .toList();
    if (outerList.isEmpty) {
      return widget.layoutEngine.constellations.firstOrNull;
    }
    return outerList.where((c) => c.id == _selectedSectorId).firstOrNull ??
        outerList.first;
  }

  Constellation get _coreConstellation {
    return widget.layoutEngine.constellations.firstWhere(
      (c) => c.id == 'core',
      orElse: () => widget.layoutEngine.constellations.first,
    );
  }

  void _launchAppWithFeedback(AppEntry app) {
    HapticFeedback.mediumImpact();
    LauncherBridge.launchApp(app);
  }

  @override
  Widget build(BuildContext context) {
    final coreConstellation = _coreConstellation;
    final otherConstellations = widget.layoutEngine.constellations
        .where((c) => c.id != 'core')
        .toList();
    final selectedConstellation = _selectedConstellation;

    return Scaffold(
      backgroundColor: const Color(0xFF020306),
      body: Stack(
        children: [
          // 1. Ambient Stardust Starfield Background
          Positioned.fill(
            child: CustomPaint(
              painter: _CoverStardustPainter(
                animation: _pulseController,
              ),
            ),
          ),

          // 2. Main Scrollable Cover Screen Content
          SafeArea(
            bottom: false,
            child: Column(
              children: [
                // Top Header: Chrono Clock & Date + Quick Posture Badge
                _buildChronoHeader(),

                // Quick Search Bar Pill
                _buildSearchPill(),

                // Scrollable Body (Essentials + Sector Browser)
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.only(
                      left: 16.0,
                      right: 16.0,
                      top: 4.0,
                      bottom: 96.0, // Space for bottom cockpit bar
                    ),
                    physics: const BouncingScrollPhysics(),
                    children: [
                      // Essentials (Core) Launchpad Shelf
                      _buildEssentialsShelf(coreConstellation),

                      const SizedBox(height: 20),

                      // Constellation Sector Tabs Bar
                      _buildSectorTabBar(otherConstellations),

                      const SizedBox(height: 14),

                      // Active Sector Grid
                      if (selectedConstellation != null)
                        _buildSectorAppCard(selectedConstellation),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // 3. Ergonomic Bottom Cockpit Bar for Narrow Cover
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _buildCoverCockpitBar(),
          ),

          // 4. Fold Simulator Popup Drawer (if toggled)
          if (_showFoldControls)
            Positioned(
              left: 16,
              right: 16,
              bottom: 82,
              child: _buildFoldControlsSheet(),
            ),
        ],
      ),
    );
  }

  // --- WIDGET BUILDERS ---

  Widget _buildChronoHeader() {
    final timeString =
        '${_now.hour.toString().padLeft(2, '0')}:${_now.minute.toString().padLeft(2, '0')}';
    final dateString =
        '${_weekdayName(_now.weekday)}, ${_monthName(_now.month)} ${_now.day}';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Clock & Date
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                timeString,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 38,
                  fontWeight: FontWeight.w200,
                  letterSpacing: -1.0,
                  height: 1.1,
                  shadows: [
                    Shadow(color: Color(0x7700E5FF), blurRadius: 18),
                  ],
                ),
              ),
              const SizedBox(height: 2),
              Text(
                dateString.toUpperCase(),
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.65),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 2.2,
                ),
              ),
            ],
          ),

          // Cover Mode Posture Telemetry Badge (Tappable to toggle simulator)
          GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() => _showFoldControls = !_showFoldControls);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: _showFoldControls
                    ? const Color(0x3300E5FF)
                    : const Color(0x22101424),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: _showFoldControls
                      ? const Color(0xFF00E5FF)
                      : const Color(0x4464B5F6),
                  width: 1.0,
                ),
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
                      boxShadow: [
                        BoxShadow(
                          color: Color(0xFF00E5FF),
                          blurRadius: 8,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Text(
                    'COVER',
                    style: TextStyle(
                      color: Color(0xFF00E5FF),
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    _showFoldControls
                        ? Icons.keyboard_arrow_down_rounded
                        : Icons.keyboard_arrow_up_rounded,
                    size: 14,
                    color: const Color(0xFF00E5FF),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchPill() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 6.0),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.onOpenSearch,
          borderRadius: BorderRadius.circular(22),
          child: Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: const Color(0x2210162A),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: const Color(0x3300E5FF),
                width: 0.9,
              ),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x1100E5FF),
                  blurRadius: 12,
                  spreadRadius: 0,
                ),
              ],
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.search_rounded,
                  color: Color(0xFF00E5FF),
                  size: 19,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Search apps or cosmos...',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.5),
                      fontSize: 13,
                      fontWeight: FontWeight.w400,
                      letterSpacing: 0.2,
                    ),
                  ),
                ),
                Icon(
                  Icons.auto_awesome_rounded,
                  color: Colors.white.withValues(alpha: 0.35),
                  size: 16,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEssentialsShelf(Constellation core) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0x1C131A30),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: core.primaryColor.withValues(alpha: 0.3),
          width: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: core.glowColor.withValues(alpha: 0.12),
            blurRadius: 18,
            spreadRadius: 0,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Shelf Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(
                    core.emblemIcon,
                    size: 16,
                    color: core.primaryColor,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'ESSENTIALS',
                    style: TextStyle(
                      color: core.primaryColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.8,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                    decoration: BoxDecoration(
                      color: core.primaryColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${core.apps.length} stars',
                      style: TextStyle(
                        color: core.primaryColor,
                        fontSize: 9.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              if (widget.onEditCore != null)
                IconButton(
                  icon: Icon(
                    Icons.edit_outlined,
                    size: 16,
                    color: Colors.white.withValues(alpha: 0.6),
                  ),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  tooltip: 'Edit Essentials',
                  onPressed: widget.onEditCore,
                ),
            ],
          ),

          const SizedBox(height: 12),

          // App Grid for Essentials
          if (core.apps.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12.0),
              child: Center(
                child: Text(
                  'No essentials added. Long-press any app to assign.',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.45),
                    fontSize: 11,
                  ),
                ),
              ),
            )
          else
            _buildAppGrid(core.apps, core.primaryColor),
        ],
      ),
    );
  }

  Widget _buildSectorTabBar(List<Constellation> outerList) {
    if (outerList.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4.0, bottom: 8.0),
          child: Text(
            'SECTORS',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.55),
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 2.0,
            ),
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          child: Row(
            children: [
              // Outer constellations chips
              ...outerList.map((c) {
                final isSelected = _selectedSectorId == c.id ||
                    (_selectedSectorId == null && c == outerList.first);
                return _buildSectorChip(
                  id: c.id,
                  label: c.name,
                  icon: c.emblemIcon,
                  color: c.primaryColor,
                  isSelected: isSelected,
                  onTap: () => setState(() => _selectedSectorId = c.id),
                );
              }),

              // "+ Add Sector" Chip
              if (widget.onCreateConstellation != null)
                Padding(
                  padding: const EdgeInsets.only(right: 6.0),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: widget.onCreateConstellation,
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                        decoration: BoxDecoration(
                          color: const Color(0xFF00E5FF).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: const Color(0xFF00E5FF).withValues(alpha: 0.35),
                          ),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.add_rounded, size: 14, color: Color(0xFF00E5FF)),
                            SizedBox(width: 4),
                            Text(
                              'Sector',
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
      ],
    );
  }

  Widget _buildSectorChip({
    required String id,
    required String label,
    required IconData icon,
    required Color color,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 8.0),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: isSelected
                  ? color.withValues(alpha: 0.22)
                  : const Color(0x18131A30),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: isSelected ? color : color.withValues(alpha: 0.25),
                width: isSelected ? 1.2 : 0.8,
              ),
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                        color: color.withValues(alpha: 0.28),
                        blurRadius: 10,
                        spreadRadius: 0,
                      )
                    ]
                  : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 14,
                  color: isSelected ? color : Colors.white70,
                ),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    color: isSelected ? Colors.white : Colors.white70,
                    fontSize: 11.5,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSectorAppCard(Constellation constellation) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0x18131A30),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: constellation.primaryColor.withValues(alpha: 0.28),
          width: 0.9,
        ),
        boxShadow: [
          BoxShadow(
            color: constellation.glowColor.withValues(alpha: 0.10),
            blurRadius: 16,
            spreadRadius: 0,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Sector Card Header with Edit Action
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(
                    constellation.emblemIcon,
                    size: 16,
                    color: constellation.primaryColor,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    constellation.name.toUpperCase(),
                    style: TextStyle(
                      color: constellation.primaryColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.8,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                    decoration: BoxDecoration(
                      color: constellation.primaryColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${constellation.apps.length} stars',
                      style: TextStyle(
                        color: constellation.primaryColor,
                        fontSize: 9.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              IconButton(
                icon: Icon(
                  Icons.tune_rounded,
                  size: 16,
                  color: Colors.white.withValues(alpha: 0.6),
                ),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                tooltip: 'Edit Constellation',
                onPressed: () {
                  widget.onConstellationLongPressed?.call(constellation);
                },
              ),
            ],
          ),

          const SizedBox(height: 12),

          // App Grid for Sector
          if (constellation.apps.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24.0),
              child: Center(
                child: Column(
                  children: [
                    Icon(
                      Icons.star_outline_rounded,
                      size: 28,
                      color: constellation.primaryColor.withValues(alpha: 0.4),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'No apps in this sector yet',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.5),
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: constellation.primaryColor,
                        side: BorderSide(color: constellation.primaryColor.withValues(alpha: 0.4)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      ),
                      icon: const Icon(Icons.add_rounded, size: 16),
                      label: const Text('Add Apps', style: TextStyle(fontSize: 11)),
                      onPressed: () {
                        widget.onConstellationLongPressed?.call(constellation);
                      },
                    ),
                  ],
                ),
              ),
            )
          else
            _buildAppGrid(constellation.apps, constellation.primaryColor),
        ],
      ),
    );
  }

  Widget _buildAppGrid(List<AppEntry> appList, Color sectorColor) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Adapt between 3 or 4 columns based on narrow screen width
        final int crossAxisCount = constraints.maxWidth > 350 ? 4 : 3;

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: appList.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: 10,
            mainAxisSpacing: 12,
            childAspectRatio: 0.82,
          ),
          itemBuilder: (context, index) {
            final app = appList[index];
            return _buildAppItem(app, sectorColor);
          },
        );
      },
    );
  }

  Widget _buildAppItem(AppEntry app, Color sectorColor) {
    return GestureDetector(
      onTap: () => _launchAppWithFeedback(app),
      onLongPressStart: (details) {
        HapticFeedback.heavyImpact();
        widget.onAppLongPressed?.call(app, details.globalPosition);
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // App Icon Container with Glowing Border & Glass Backing
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: app.accentColor.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: app.accentColor.withValues(alpha: 0.45),
                width: 1.0,
              ),
              boxShadow: [
                BoxShadow(
                  color: app.accentColor.withValues(alpha: 0.18),
                  blurRadius: 10,
                  spreadRadius: 0,
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(13),
              child: app.iconBytes != null
                  ? Image.memory(
                      app.iconBytes!,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => Icon(
                        app.fallbackIcon,
                        color: app.accentColor,
                        size: 24,
                      ),
                    )
                  : Icon(
                      app.fallbackIcon,
                      color: app.accentColor,
                      size: 24,
                    ),
            ),
          ),
          const SizedBox(height: 5),
          // App Label
          Text(
            app.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10.5,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCoverCockpitBar() {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(26),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Container(
              height: 56,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: const Color(0xCC0D1120),
                borderRadius: BorderRadius.circular(26),
                border: Border.all(
                  color: const Color(0x3364B5F6),
                  width: 0.9,
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x33000000),
                    blurRadius: 16,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  // Search
                  _dockIconButton(
                    icon: Icons.search_rounded,
                    color: const Color(0xFF00E5FF),
                    tooltip: 'Search Apps',
                    onTap: widget.onOpenSearch,
                  ),

                  // Fold Simulator Toggle
                  _dockIconButton(
                    icon: Icons.splitscreen_rounded,
                    color: _showFoldControls ? const Color(0xFF00E5FF) : Colors.white70,
                    tooltip: 'Fold Simulator',
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() => _showFoldControls = !_showFoldControls);
                    },
                  ),

                  // Lock Screen
                  _dockIconButton(
                    icon: Icons.lock_outline_rounded,
                    color: Colors.white70,
                    tooltip: 'Lock Screen',
                    onTap: widget.onLock,
                  ),

                  // Settings
                  _dockIconButton(
                    icon: Icons.settings_outlined,
                    color: Colors.white70,
                    tooltip: 'Launcher Settings',
                    onTap: widget.onOpenSettings,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _dockIconButton({
    required IconData icon,
    required Color color,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          width: 44,
          height: 44,
          alignment: Alignment.center,
          child: Icon(icon, color: color, size: 22),
        ),
      ),
    );
  }

  Widget _buildFoldControlsSheet() {
    final posture = widget.foldable.posture;
    final angle = widget.foldable.hingeAngle;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xEE0D1120),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0x6600E5FF), width: 1.0),
        boxShadow: const [
          BoxShadow(color: Color(0x4400E5FF), blurRadius: 18),
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
                    const Icon(Icons.screen_rotation_rounded, color: Color(0xFF00E5FF), size: 16),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        'Posture: ${posture.name.toUpperCase()} (${angle.toStringAsFixed(0)}°)',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded, color: Colors.white70, size: 16),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () => setState(() => _showFoldControls = false),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _presetButton('Cover (0°)', DevicePosture.folded)),
              const SizedBox(width: 6),
              Expanded(child: _presetButton('Tabletop (90°)', DevicePosture.tabletop)),
              const SizedBox(width: 6),
              Expanded(child: _presetButton('Main (180°)', DevicePosture.flat)),
            ],
          ),
          const SizedBox(height: 6),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: const Color(0xFF00E5FF),
              inactiveTrackColor: Colors.white24,
              thumbColor: Colors.white,
              overlayColor: const Color(0x3300E5FF),
              trackHeight: 2.5,
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
    );
  }

  Widget _presetButton(String label, DevicePosture targetPosture) {
    final isSelected = widget.foldable.posture == targetPosture;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => widget.foldable.setPosture(targetPosture),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 6),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isSelected ? const Color(0x3300E5FF) : const Color(0x18FFFFFF),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected ? const Color(0xFF00E5FF) : Colors.white24,
              width: 0.9,
            ),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: isSelected ? const Color(0xFF00E5FF) : Colors.white70,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  String _weekdayName(int day) {
    const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return names[(day - 1) % 7];
  }

  String _monthName(int month) {
    const names = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return names[(month - 1) % 12];
  }
}

/// Dynamic cosmic stardust painter for the folded cover screen
class _CoverStardustPainter extends CustomPainter {
  final Animation<double> animation;
  static final math.Random _rng = math.Random(42);

  // Pre-generate 60 subtle stars
  static final List<_CoverStar> _stars = List.generate(60, (index) {
    return _CoverStar(
      x: _rng.nextDouble(),
      y: _rng.nextDouble(),
      radius: 0.6 + _rng.nextDouble() * 1.2,
      baseAlpha: 0.2 + _rng.nextDouble() * 0.45,
      blinkRate: 0.5 + _rng.nextDouble() * 1.5,
      color: index % 3 == 0
          ? const Color(0xFF00E5FF)
          : (index % 4 == 0 ? const Color(0xFFFFD54F) : Colors.white),
    );
  });

  _CoverStardustPainter({required this.animation}) : super(repaint: animation);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    final t = animation.value;

    for (final star in _stars) {
      final alpha = (star.baseAlpha + 0.25 * math.sin(t * math.pi * 2 * star.blinkRate))
          .clamp(0.08, 0.85);
      paint.color = star.color.withValues(alpha: alpha);
      final center = Offset(star.x * size.width, star.y * size.height);
      canvas.drawCircle(center, star.radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _CoverStardustPainter oldDelegate) => false;
}

class _CoverStar {
  final double x;
  final double y;
  final double radius;
  final double baseAlpha;
  final double blinkRate;
  final Color color;

  const _CoverStar({
    required this.x,
    required this.y,
    required this.radius,
    required this.baseAlpha,
    required this.blinkRate,
    required this.color,
  });
}
