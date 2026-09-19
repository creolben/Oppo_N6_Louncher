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
import '../widgets/fading_horizontal_scroll.dart';
import '../widgets/foldable_simulation_chip.dart';

/// Visual tokens for the folded cover surface.
///
/// The cover panel is narrow and used one-handed, so it runs a tighter rhythm
/// than the unfolded galaxy: one 4-based gutter, one card radius, one chip
/// radius, one touch target. Values live here so a single surface cannot drift
/// into five near-identical greys and radii again.
abstract final class CoverStyle {
  static const Color page = Color(0xFF020306);
  static const Color accent = Color(0xFF00E5FF);
  static const Color hairline = Color(0x3364B5F6);
  static const Color label = Color(0xA6FFFFFF);
  static const Color labelMuted = Color(0x8AFFFFFF);

  static const double gutter = 16;
  static const double cardRadius = 18;
  static const double chipRadius = 16;
  static const double tileRadius = 14;
  static const double dockRadius = 24;

  /// Minimum touch target for a control on the cover panel: 48dp, the
  /// Android baseline, not a round number below it.
  static const double touchTarget = 48;

  /// Height reserved below the scrolling body for the floating cockpit dock.
  static const double dockClearance = 118;
}

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
      // The header renders hours and minutes only: repaint when the visible
      // minute actually rolls over instead of once a second.
      final now = DateTime.now();
      if (!mounted || now.minute == _now.minute && now.hour == _now.hour) {
        return;
      }
      setState(() => _now = now);
    });

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The stardust breathing is ambient, not informative: honor the system
    // "remove animations" setting by resting on a single frame.
    final bool reduceMotion =
        MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduceMotion) {
      if (_pulseController.isAnimating) _pulseController.stop();
      _pulseController.value = 0.5;
    } else if (!_pulseController.isAnimating) {
      _pulseController.repeat(reverse: true);
    }
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
      backgroundColor: CoverStyle.page,
      body: Stack(
        children: [
          // 1. Ambient nebula wash: ties the cover panel to the lock screen,
          // which opens on the same deep-space gradient.
          const Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment(0.0, -0.85),
                    radius: 1.05,
                    colors: [
                      Color(0x1F00E5FF),
                      Color(0x0D2979FF),
                      Color(0x00020306),
                    ],
                    stops: [0.0, 0.42, 1.0],
                  ),
                ),
              ),
            ),
          ),

          // 2. Ambient Stardust Starfield Background. The boundary keeps the
          // breathing pulse repainting this layer only, instead of dragging
          // the whole cover subtree (including the scrollable body) with it.
          Positioned.fill(
            child: RepaintBoundary(
              child: CustomPaint(
                painter: _CoverStardustPainter(
                  animation: _pulseController,
                ),
              ),
            ),
          ),

          // 3. Main Scrollable Cover Screen Content
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
                    padding: const EdgeInsets.fromLTRB(
                      CoverStyle.gutter,
                      4.0,
                      CoverStyle.gutter,
                      CoverStyle.dockClearance,
                    ),
                    physics: const ClampingScrollPhysics(),
                    children: [
                      // Essentials (Core) Launchpad Shelf
                      _buildEssentialsShelf(coreConstellation),

                      const SizedBox(height: 18),

                      // Constellation Sector Tabs Bar
                      _buildSectorTabBar(otherConstellations),

                      const SizedBox(height: 12),

                      // Active Sector Grid
                      if (selectedConstellation != null)
                        _SectorCrossFade(
                          sectorId: selectedConstellation.id,
                          child: _buildSectorAppCard(selectedConstellation),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // 4. Scrim so the scrolling body dissolves under the floating dock
          // instead of colliding with it.
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 150,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      CoverStyle.page.withValues(alpha: 0.0),
                      CoverStyle.page.withValues(alpha: 0.86),
                      CoverStyle.page,
                    ],
                    stops: const [0.0, 0.55, 1.0],
                  ),
                ),
              ),
            ),
          ),

          // 5. Ergonomic Bottom Cockpit Bar for Narrow Cover
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _buildCoverCockpitBar(),
          ),

          // 6. Fold Simulator Popup Drawer (if toggled)
          if (_showFoldControls)
            Positioned(
              left: CoverStyle.gutter,
              right: CoverStyle.gutter,
              bottom: 92,
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
      padding: const EdgeInsets.fromLTRB(
        CoverStyle.gutter,
        8.0,
        CoverStyle.gutter,
        10.0,
      ),
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
                  letterSpacing: -1.2,
                  height: 1.05,
                  // Tabular figures keep the clock from shifting width as the
                  // minute rolls over.
                  fontFeatures: [FontFeature.tabularFigures()],
                  shadows: [
                    Shadow(color: Color(0x5900E5FF), blurRadius: 16),
                  ],
                ),
              ),
              const SizedBox(height: 3),
              Text(
                dateString.toUpperCase(),
                style: const TextStyle(
                  color: CoverStyle.labelMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.6,
                ),
              ),
            ],
          ),

          // Cover Mode Posture Telemetry Badge (tappable to toggle simulator)
          Semantics(
            button: true,
            label: _showFoldControls
                ? 'Hide posture controls'
                : 'Show posture controls',
            child: GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() => _showFoldControls = !_showFoldControls);
              },
              behavior: HitTestBehavior.opaque,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
                decoration: BoxDecoration(
                  color: _showFoldControls
                      ? const Color(0x3300E5FF)
                      : const Color(0x1F101424),
                  borderRadius: BorderRadius.circular(CoverStyle.chipRadius),
                  border: Border.all(
                    color: _showFoldControls
                        ? CoverStyle.accent
                        : CoverStyle.hairline,
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
                        color: CoverStyle.accent,
                        boxShadow: [
                          BoxShadow(
                            color: Color(0x9900E5FF),
                            blurRadius: 7,
                            spreadRadius: 0.5,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 7),
                    const Text(
                      'COVER',
                      style: TextStyle(
                        color: CoverStyle.accent,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.4,
                      ),
                    ),
                    const SizedBox(width: 2),
                    Icon(
                      _showFoldControls
                          ? Icons.keyboard_arrow_down_rounded
                          : Icons.keyboard_arrow_up_rounded,
                      size: 15,
                      color: CoverStyle.accent,
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

  Widget _buildSearchPill() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        CoverStyle.gutter,
        6.0,
        CoverStyle.gutter,
        4.0,
      ),
      child: Semantics(
        button: true,
        label: 'Search apps or cosmos',
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.onOpenSearch,
            borderRadius: BorderRadius.circular(23),
            child: Container(
              // 48dp, not 46: it measured 2dp under the Android minimum.
              height: CoverStyle.touchTarget,
              padding: const EdgeInsets.symmetric(horizontal: 15),
              decoration: BoxDecoration(
                color: const Color(0x2E10162A),
                borderRadius: BorderRadius.circular(23),
                border: Border.all(
                  color: const Color(0x2E00E5FF),
                  width: 0.9,
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x40000000),
                    blurRadius: 8,
                    offset: Offset(0, 3),
                  ),
                ],
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.search_rounded,
                    color: CoverStyle.accent,
                    size: 19,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Search apps or cosmos...',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.58),
                        fontSize: 13,
                        fontWeight: FontWeight.w400,
                        letterSpacing: 0.1,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.auto_awesome_rounded,
                    color: Colors.white.withValues(alpha: 0.32),
                    size: 16,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Shared card surface: one radius, one fill, one hairline, and a single
  /// two-part elevation (real drop shadow + faint accent halo). Both the
  /// Essentials shelf and the sector grid are built from it so they cannot
  /// drift apart.
  Widget _cardSurface({
    required Color accent,
    required Color glow,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: const Color(0x1A131A30),
        borderRadius: BorderRadius.circular(CoverStyle.cardRadius),
        border: Border.all(
          color: accent.withValues(alpha: 0.26),
          width: 0.9,
        ),
        boxShadow: [
          const BoxShadow(
            color: Color(0x52000000),
            blurRadius: 14,
            offset: Offset(0, 6),
          ),
          BoxShadow(
            color: glow.withValues(alpha: 0.10),
            blurRadius: 18,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _cardHeader({
    required IconData icon,
    required String title,
    required Color color,
    required int starCount,
    Widget? action,
  }) {
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 7),
        Flexible(
          child: Text(
            title.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.6,
            ),
          ),
        ),
        const SizedBox(width: 7),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            starCount == 1 ? '1 star' : '$starCount stars',
            style: TextStyle(
              color: color,
              fontSize: 9.5,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
            ),
          ),
        ),
        if (action != null) ...[const Spacer(), action],
      ],
    );
  }

  Widget _buildEssentialsShelf(Constellation core) {
    return _cardSurface(
      accent: core.primaryColor,
      glow: core.glowColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardHeader(
            icon: core.emblemIcon,
            title: 'Essentials',
            color: core.primaryColor,
            starCount: core.apps.length,
            action: widget.onEditCore == null
                ? null
                : _cardAction(
                    icon: Icons.edit_outlined,
                    tooltip: 'Edit Essentials',
                    onPressed: widget.onEditCore!,
                  ),
          ),

          const SizedBox(height: 10),

          // App Grid for Essentials
          if (core.apps.isEmpty)
            const _ShelfEmptyState(
              icon: Icons.star_outline_rounded,
              title: 'Nothing pinned yet',
              hint: 'Long-press any app to add it to Essentials.',
            )
          else
            _buildAppGrid(core.apps),
        ],
      ),
    );
  }

  Widget _cardAction({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
  }) {
    return IconButton(
      icon: Icon(icon, size: 17, color: Colors.white.withValues(alpha: 0.62)),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(
        minWidth: 40,
        minHeight: 48,
      ),
      tooltip: tooltip,
      onPressed: onPressed,
    );
  }

  Widget _sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 4.0),
      child: Text(
        text,
        style: const TextStyle(
          color: CoverStyle.labelMuted,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.8,
        ),
      ),
    );
  }

  Widget _buildSectorTabBar(List<Constellation> outerList) {
    if (outerList.isEmpty) return const SizedBox.shrink();

    final List<Widget> chips = [
      for (final c in outerList)
        _buildSectorChip(
          label: c.name,
          icon: c.emblemIcon,
          color: c.primaryColor,
          isSelected: _selectedSectorId == c.id ||
              (_selectedSectorId == null && c == outerList.first),
          onTap: () => setState(() => _selectedSectorId = c.id),
        ),
      if (widget.onCreateConstellation != null)
        _buildAddSectorChip(widget.onCreateConstellation!),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel('SECTORS'),
        const SizedBox(height: 8),
        FadingHorizontalScroll(
          fadeColor: CoverStyle.page,
          children: [...chips, const SizedBox(width: 4)],
        ),
      ],
    );
  }

  Widget _buildAddSectorChip(VoidCallback onCreate) {
    return Padding(
      padding: const EdgeInsets.only(right: 6.0),
      child: Semantics(
        button: true,
        label: 'Create a new sector',
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onCreate,
            borderRadius: BorderRadius.circular(CoverStyle.chipRadius),
            child: Container(
              constraints: const BoxConstraints(minHeight: 48),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: CoverStyle.accent.withValues(alpha: 0.09),
                borderRadius: BorderRadius.circular(CoverStyle.chipRadius),
                border: Border.all(
                  color: CoverStyle.accent.withValues(alpha: 0.32),
                  width: 0.9,
                ),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.add_rounded, size: 15, color: CoverStyle.accent),
                  SizedBox(width: 5),
                  Text(
                    'Sector',
                    style: TextStyle(
                      color: CoverStyle.accent,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.2,
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

  Widget _buildSectorChip({
    required String label,
    required IconData icon,
    required Color color,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 8.0),
      child: Semantics(
        button: true,
        selected: isSelected,
        label: '$label sector',
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(CoverStyle.chipRadius),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              constraints: const BoxConstraints(minHeight: 48),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: isSelected
                    ? color.withValues(alpha: 0.20)
                    : const Color(0x14131A30),
                borderRadius: BorderRadius.circular(CoverStyle.chipRadius),
                border: Border.all(
                  color: isSelected ? color : color.withValues(alpha: 0.22),
                  width: isSelected ? 1.1 : 0.8,
                ),
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color: color.withValues(alpha: 0.22),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
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
                      letterSpacing: 0.1,
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

  Widget _buildSectorAppCard(Constellation constellation) {
    return _cardSurface(
      accent: constellation.primaryColor,
      glow: constellation.glowColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardHeader(
            icon: constellation.emblemIcon,
            title: constellation.name,
            color: constellation.primaryColor,
            starCount: constellation.apps.length,
            action: _cardAction(
              icon: Icons.tune_rounded,
              tooltip: 'Edit Constellation',
              onPressed: () =>
                  widget.onConstellationLongPressed?.call(constellation),
            ),
          ),

          const SizedBox(height: 10),

          // App Grid for Sector
          if (constellation.apps.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 18.0),
              child: Column(
                children: [
                  const _ShelfEmptyState(
                    icon: Icons.star_outline_rounded,
                    title: 'This sector is empty',
                    hint: 'Add apps to bring it into orbit.',
                  ),
                  const SizedBox(height: 14),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: constellation.primaryColor,
                      side: BorderSide(
                        color: constellation.primaryColor.withValues(alpha: 0.4),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                    ),
                    icon: const Icon(Icons.add_rounded, size: 16),
                    label: const Text('Add Apps', style: TextStyle(fontSize: 11)),
                    onPressed: () {
                      widget.onConstellationLongPressed?.call(constellation);
                    },
                  ),
                ],
              ),
            )
          else
            _buildAppGrid(constellation.apps),
        ],
      ),
    );
  }

  /// Column count for an app grid on the cover panel, chosen so the trailing
  /// row is never a lone orphan.
  static int _columnsFor(double availableWidth, int appCount) {
    final int maxColumns = (availableWidth / 64).floor().clamp(3, 5);
    if (appCount <= 1) return maxColumns;
    for (var columns = maxColumns; columns >= 3; columns--) {
      final remainder = appCount % columns;
      if (remainder == 0 || remainder * 2 >= columns) return columns;
    }
    return maxColumns;
  }

  /// Fixed-size tile grid built on [Wrap] rather than [GridView]: the rows keep
  /// their natural height (no stretched aspect-ratio gap under each label) and
  /// a short final row centres instead of leaving a hole.
  Widget _buildAppGrid(List<AppEntry> appList) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const double spacing = 8.0;
        final int columns = _columnsFor(constraints.maxWidth, appList.length);
        final double tileWidth =
            (constraints.maxWidth - spacing * (columns - 1)) / columns - 0.5;

        return Wrap(
          spacing: spacing,
          runSpacing: 14.0,
          alignment: WrapAlignment.center,
          children: [
            for (final app in appList)
              SizedBox(
                width: tileWidth,
                child: _CoverAppTile(
                  app: app,
                  onTap: () => _launchAppWithFeedback(app),
                  onLongPress: (position) {
                    HapticFeedback.heavyImpact();
                    widget.onAppLongPressed?.call(app, position);
                  },
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildCoverCockpitBar() {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          CoverStyle.gutter,
          8.0,
          CoverStyle.gutter,
          8.0,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(CoverStyle.dockRadius),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Container(
              height: 60,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: const Color(0xD90D1120),
                borderRadius: BorderRadius.circular(CoverStyle.dockRadius),
                border: Border.all(color: CoverStyle.hairline, width: 0.9),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x66000000),
                    blurRadius: 18,
                    offset: Offset(0, 6),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  // Search
                  _dockIconButton(
                    icon: Icons.search_rounded,
                    color: CoverStyle.accent,
                    tooltip: 'Search Apps',
                    onTap: widget.onOpenSearch,
                  ),

                  // Fold Simulator Toggle
                  _dockIconButton(
                    icon: Icons.splitscreen_rounded,
                    color: _showFoldControls
                        ? CoverStyle.accent
                        : Colors.white70,
                    tooltip: 'Fold Simulator',
                    isActive: _showFoldControls,
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
    bool isActive = false,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(CoverStyle.chipRadius),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            width: CoverStyle.touchTarget + 4,
            height: CoverStyle.touchTarget + 4,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: isActive
                  ? CoverStyle.accent.withValues(alpha: 0.16)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(CoverStyle.chipRadius),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
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
        color: const Color(0xF20D1120),
        borderRadius: BorderRadius.circular(CoverStyle.cardRadius),
        border: Border.all(
          color: CoverStyle.accent.withValues(alpha: 0.42),
          width: 1.0,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x73000000),
            blurRadius: 20,
            offset: Offset(0, 8),
          ),
          BoxShadow(
            color: Color(0x2E00E5FF),
            blurRadius: 22,
            offset: Offset(0, 4),
          ),
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
                    if (widget.foldable.isSimulated) ...[
                      const SizedBox(width: 6),
                      FoldableSimulationChip(
                        foldable: widget.foldable,
                        fontSize: 9,
                      ),
                    ],
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

/// A single app on the cover grid.
///
/// Pressing a tile scales it down and lifts its accent glow, so a tap on a
/// small cover-panel target is acknowledged before the app opens.
class _CoverAppTile extends StatefulWidget {
  final AppEntry app;
  final VoidCallback onTap;
  final void Function(Offset globalPosition) onLongPress;

  const _CoverAppTile({
    required this.app,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  State<_CoverAppTile> createState() => _CoverAppTileState();
}

class _CoverAppTileState extends State<_CoverAppTile> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  /// Anchors the long-press dialog on the tile itself when the action comes
  /// from a screen reader rather than a finger.
  void _semanticLongPress() {
    final box = context.findRenderObject() as RenderBox?;
    final position = box == null || !box.hasSize
        ? Offset.zero
        : box.localToGlobal(box.size.center(Offset.zero));
    widget.onLongPress(position);
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    return Semantics(
      button: true,
      label: 'Open ${app.label}',
      // Without this the long-press route to Essentials is unreachable under
      // a screen reader, and the hint below advertises it.
      onLongPress: _semanticLongPress,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) {
          HapticFeedback.selectionClick();
          _setPressed(true);
        },
        onTapUp: (_) => _setPressed(false),
        onTapCancel: () => _setPressed(false),
        onTap: widget.onTap,
        onLongPressStart: (details) {
          _setPressed(false);
          widget.onLongPress(details.globalPosition);
        },
        child: AnimatedScale(
          scale: _pressed ? 0.92 : 1.0,
          duration: const Duration(milliseconds: 110),
          curve: Curves.easeOutCubic,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // App Icon Container with Glowing Border & Glass Backing
              AnimatedContainer(
                duration: const Duration(milliseconds: 140),
                curve: Curves.easeOutCubic,
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: app.accentColor.withValues(alpha: _pressed ? 0.22 : 0.13),
                  borderRadius: BorderRadius.circular(CoverStyle.tileRadius),
                  border: Border.all(
                    color: app.accentColor.withValues(alpha: _pressed ? 0.7 : 0.4),
                    width: 1.0,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: app.accentColor.withValues(
                        alpha: _pressed ? 0.32 : 0.14,
                      ),
                      blurRadius: _pressed ? 14 : 9,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(CoverStyle.tileRadius - 1),
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
        ),
      ),
    );
  }
}

/// Empty state for a shelf or sector with no apps.
class _ShelfEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String hint;

  const _ShelfEmptyState({
    required this.icon,
    required this.title,
    required this.hint,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Column(
        children: [
          Icon(icon, size: 24, color: Colors.white.withValues(alpha: 0.45)),
          const SizedBox(height: 8),
          Text(
            title,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.72),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            hint,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 11,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }
}

/// Fades a freshly selected sector card in, so switching sectors reads as a
/// content change instead of an instant swap. Only the incoming card is built,
/// which keeps a single set of app tiles in the tree at any moment.
class _SectorCrossFade extends StatefulWidget {
  final String sectorId;
  final Widget child;

  const _SectorCrossFade({required this.sectorId, required this.child});

  @override
  State<_SectorCrossFade> createState() => _SectorCrossFadeState();
}

class _SectorCrossFadeState extends State<_SectorCrossFade>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
    value: 1.0,
  );

  late final Animation<double> _curve = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOutCubic,
  );

  @override
  void didUpdateWidget(covariant _SectorCrossFade oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sectorId != widget.sectorId) {
      _controller.forward(from: 0.0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _curve,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0.0, 0.025),
          end: Offset.zero,
        ).animate(_curve),
        child: widget.child,
      ),
    );
  }
}
