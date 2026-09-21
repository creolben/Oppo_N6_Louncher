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
import '../theme/luminous_home_theme.dart';
import '../widgets/fading_horizontal_scroll.dart';
import '../widgets/foldable_simulation_chip.dart';

/// Luminous Horizon roles tuned for the narrow, one-handed cover surface.
///
/// Colors and materials come from [LuminousHomeTheme]; the local rhythm stays
/// compact so the existing cover grid and touch geometry remain unchanged.
abstract final class CoverStyle {
  static const Color page = LuminousHomeTheme.background;
  static const Color pageTop = LuminousHomeTheme.backgroundTop;
  static const Color pageDeep = LuminousHomeTheme.backgroundDeep;
  static const Color accent = LuminousHomeTheme.aqua;
  static const Color secondaryAccent = LuminousHomeTheme.cobalt;
  static const Color tertiaryAccent = LuminousHomeTheme.orchid;
  static const Color hairline = LuminousHomeTheme.hairline;
  static const Color label = LuminousHomeTheme.textSecondary;
  static const Color labelMuted = LuminousHomeTheme.textMuted;

  static const double gutter = 16;
  static const double cardRadius = LuminousHomeTheme.cardRadius;
  static const double chipRadius = LuminousHomeTheme.controlRadius;
  static const double tileRadius = LuminousHomeTheme.iconRadius;
  static const double dockRadius = LuminousHomeTheme.dockRadius;

  /// Minimum touch target for a control on the cover panel: 48dp, the
  /// Android baseline, not a round number below it.
  static const double touchTarget = LuminousHomeTheme.minimumTouchTarget;

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
          // 1. Luminous Horizon atmosphere: an ink-blue OLED field with a
          // low cobalt horizon and restrained aqua/orchid light.
          Positioned.fill(
            child: IgnorePointer(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          CoverStyle.pageTop,
                          CoverStyle.page,
                          CoverStyle.pageDeep,
                        ],
                        stops: [0.0, 0.58, 1.0],
                      ),
                    ),
                  ),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        center: const Alignment(-0.9, -0.62),
                        radius: 0.9,
                        colors: [
                          CoverStyle.accent.withValues(alpha: 0.13),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        center: const Alignment(0.95, 0.02),
                        radius: 0.82,
                        colors: [
                          CoverStyle.tertiaryAccent.withValues(alpha: 0.11),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        center: const Alignment(0.08, 1.16),
                        radius: 0.8,
                        colors: [
                          CoverStyle.secondaryAccent.withValues(alpha: 0.2),
                          Colors.transparent,
                        ],
                        stops: const [0.0, 1.0],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 2. Ambient Stardust Starfield Background. The boundary keeps the
          // breathing pulse repainting this layer only, instead of dragging
          // the whole cover subtree (including the scrollable body) with it.
          Positioned.fill(
            child: RepaintBoundary(
              child: CustomPaint(
                painter: _CoverStardustPainter(animation: _pulseController),
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
                  color: LuminousHomeTheme.textPrimary,
                  fontSize: 38,
                  fontWeight: FontWeight.w300,
                  letterSpacing: -1.2,
                  height: 1.05,
                  // Tabular figures keep the clock from shifting width as the
                  // minute rolls over.
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(height: 3),
              Text(
                dateString,
                style: const TextStyle(
                  color: CoverStyle.labelMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.3,
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
                constraints: const BoxConstraints(
                  minHeight: CoverStyle.touchTarget,
                ),
                padding: const EdgeInsets.symmetric(horizontal: 11),
                decoration: BoxDecoration(
                  color: _showFoldControls
                      ? LuminousHomeTheme.softTint(CoverStyle.accent, 0.16)
                      : LuminousHomeTheme.glass,
                  borderRadius: BorderRadius.circular(CoverStyle.chipRadius),
                  border: Border.all(
                    color: _showFoldControls
                        ? LuminousHomeTheme.hairlineStrong
                        : CoverStyle.hairline,
                    width: 0.8,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: CoverStyle.accent,
                      ),
                      child: SizedBox(width: 7, height: 7),
                    ),
                    const SizedBox(width: 7),
                    const Text(
                      'COVER',
                      style: TextStyle(
                        color: LuminousHomeTheme.textSecondary,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.2,
                      ),
                    ),
                    const SizedBox(width: 2),
                    Icon(
                      _showFoldControls
                          ? Icons.keyboard_arrow_down_rounded
                          : Icons.keyboard_arrow_up_rounded,
                      size: 15,
                      color: _showFoldControls
                          ? CoverStyle.accent
                          : LuminousHomeTheme.textMuted,
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
                color: LuminousHomeTheme.glass,
                borderRadius: BorderRadius.circular(23),
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
                    color: LuminousHomeTheme.textSecondary,
                    size: 19,
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Search apps or cosmos...',
                      style: TextStyle(
                        color: LuminousHomeTheme.textMuted,
                        fontSize: 13,
                        fontWeight: FontWeight.w400,
                        letterSpacing: 0.1,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.auto_awesome_rounded,
                    color: LuminousHomeTheme.textMuted,
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

  /// Shared milky tonal-glass shelf. Accent is mixed into the material at a
  /// very low level; it identifies content without outlining every surface.
  Widget _cardSurface({required Color accent, required Widget child}) {
    final tintedGlass = Color.alphaBlend(
      accent.withValues(alpha: 0.035),
      LuminousHomeTheme.glassStrong,
    );

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [tintedGlass, LuminousHomeTheme.glass],
        ),
        borderRadius: BorderRadius.circular(CoverStyle.cardRadius),
        border: Border.all(color: LuminousHomeTheme.hairline, width: 0.8),
        boxShadow: LuminousHomeTheme.floatingShadow,
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
            style: const TextStyle(
              color: LuminousHomeTheme.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.1,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          starCount == 1 ? '1 star' : '$starCount stars',
          style: const TextStyle(
            color: LuminousHomeTheme.textMuted,
            fontSize: 10,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.1,
          ),
        ),
        if (action != null) ...[const Spacer(), action],
      ],
    );
  }

  Widget _buildEssentialsShelf(Constellation core) {
    return _cardSurface(
      accent: core.primaryColor,
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
      icon: Icon(icon, size: 17, color: LuminousHomeTheme.textSecondary),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(
        minWidth: CoverStyle.touchTarget,
        minHeight: CoverStyle.touchTarget,
      ),
      tooltip: tooltip,
      onPressed: onPressed,
    );
  }

  Widget _sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 4.0),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          color: CoverStyle.labelMuted,
          fontSize: 10,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.7,
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
          isSelected:
              _selectedSectorId == c.id ||
              (_selectedSectorId == null && c == outerList.first),
          onTap: () => setState(() => _selectedSectorId = c.id),
        ),
      if (widget.onCreateConstellation != null)
        _buildAddSectorChip(widget.onCreateConstellation!),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel('Sectors'),
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
                color: LuminousHomeTheme.softTint(CoverStyle.accent, 0.12),
                borderRadius: BorderRadius.circular(CoverStyle.chipRadius),
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
                    ? LuminousHomeTheme.softTint(color, 0.18)
                    : LuminousHomeTheme.glass,
                borderRadius: BorderRadius.circular(CoverStyle.chipRadius),
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
                    size: 14,
                    color: isSelected ? color : LuminousHomeTheme.textSecondary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: TextStyle(
                      color: isSelected
                          ? LuminousHomeTheme.textPrimary
                          : LuminousHomeTheme.textSecondary,
                      fontSize: 11.5,
                      fontWeight: isSelected
                          ? FontWeight.w700
                          : FontWeight.w500,
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
                      backgroundColor: LuminousHomeTheme.glass,
                      minimumSize: const Size(0, CoverStyle.touchTarget),
                      side: const BorderSide(
                        color: LuminousHomeTheme.hairline,
                        width: 0.8,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                    ),
                    icon: const Icon(Icons.add_rounded, size: 16),
                    label: const Text(
                      'Add Apps',
                      style: TextStyle(fontSize: 11),
                    ),
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
            filter: ImageFilter.blur(
              sigmaX: LuminousHomeTheme.glassBlur,
              sigmaY: LuminousHomeTheme.glassBlur,
            ),
            child: Container(
              height: 60,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: LuminousHomeTheme.glassOpaque,
                borderRadius: BorderRadius.circular(CoverStyle.dockRadius),
                border: Border.all(
                  color: LuminousHomeTheme.hairline,
                  width: 0.8,
                ),
                boxShadow: LuminousHomeTheme.floatingShadow,
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
                        : LuminousHomeTheme.textSecondary,
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
                    color: LuminousHomeTheme.textSecondary,
                    tooltip: 'Lock Screen',
                    onTap: widget.onLock,
                  ),

                  // Settings
                  _dockIconButton(
                    icon: Icons.settings_outlined,
                    color: LuminousHomeTheme.textSecondary,
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
        color: LuminousHomeTheme.glassOpaqueStrong,
        borderRadius: BorderRadius.circular(CoverStyle.cardRadius),
        border: Border.all(color: LuminousHomeTheme.hairline, width: 0.8),
        boxShadow: LuminousHomeTheme.floatingShadow,
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
                    const Icon(
                      Icons.screen_rotation_rounded,
                      color: LuminousHomeTheme.aqua,
                      size: 16,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        'Posture: ${posture.name} (${angle.toStringAsFixed(0)}°)',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: LuminousHomeTheme.textPrimary,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.2,
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
                icon: const Icon(
                  Icons.close_rounded,
                  color: LuminousHomeTheme.textSecondary,
                  size: 16,
                ),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(
                  minWidth: CoverStyle.touchTarget,
                  minHeight: CoverStyle.touchTarget,
                ),
                onPressed: () => setState(() => _showFoldControls = false),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _presetButton('Cover (0°)', DevicePosture.folded),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _presetButton('Tabletop (90°)', DevicePosture.tabletop),
              ),
              const SizedBox(width: 6),
              Expanded(child: _presetButton('Main (180°)', DevicePosture.flat)),
            ],
          ),
          const SizedBox(height: 6),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: CoverStyle.accent,
              inactiveTrackColor: LuminousHomeTheme.hairlineStrong,
              thumbColor: LuminousHomeTheme.textPrimary,
              overlayColor: LuminousHomeTheme.softTint(CoverStyle.accent, 0.16),
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
          constraints: const BoxConstraints(minHeight: CoverStyle.touchTarget),
          padding: const EdgeInsets.symmetric(vertical: 6),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isSelected
                ? LuminousHomeTheme.softTint(CoverStyle.accent, 0.16)
                : LuminousHomeTheme.glass,
            borderRadius: BorderRadius.circular(10),
            border: isSelected
                ? Border.all(
                    color: CoverStyle.accent.withValues(alpha: 0.48),
                    width: 0.9,
                  )
                : null,
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: isSelected
                  ? CoverStyle.accent
                  : LuminousHomeTheme.textSecondary,
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
    return names[(month - 1) % 12];
  }
}

/// Dynamic cosmic stardust painter for the folded cover screen
class _CoverStardustPainter extends CustomPainter {
  final Animation<double> animation;
  static final math.Random _rng = math.Random(42);

  // Pre-generate 60 restrained points of light. Their pulse formula and rate
  // remain unchanged; only scale, base opacity, and palette are quieter.
  static final List<_CoverStar> _stars = List.generate(60, (index) {
    return _CoverStar(
      x: _rng.nextDouble(),
      y: _rng.nextDouble(),
      radius: 0.45 + _rng.nextDouble() * 0.8,
      baseAlpha: 0.1 + _rng.nextDouble() * 0.22,
      blinkRate: 0.5 + _rng.nextDouble() * 1.5,
      color: index % 5 == 0
          ? LuminousHomeTheme.aqua
          : (index % 7 == 0
                ? LuminousHomeTheme.orchid
                : LuminousHomeTheme.textSecondary),
    );
  });

  _CoverStardustPainter({required this.animation}) : super(repaint: animation);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    final t = animation.value;

    for (final star in _stars) {
      final alpha =
          (star.baseAlpha + 0.25 * math.sin(t * math.pi * 2 * star.blinkRate))
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
              // Clean 48dp squircle icon with soft offset depth. The source
              // artwork is the icon; there is no nested glowing frame.
              AnimatedContainer(
                duration: const Duration(milliseconds: 140),
                curve: Curves.easeOutCubic,
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: _pressed
                      ? Color.alphaBlend(
                          app.accentColor.withValues(alpha: 0.12),
                          LuminousHomeTheme.glassStrong,
                        )
                      : LuminousHomeTheme.glassStrong,
                  borderRadius: BorderRadius.circular(CoverStyle.tileRadius),
                  boxShadow: [
                    BoxShadow(
                      color: LuminousHomeTheme.shadow.withValues(
                        alpha: _pressed ? 0.64 : 0.48,
                      ),
                      blurRadius: _pressed ? 16 : 12,
                      offset: Offset(0, _pressed ? 7 : 4),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(CoverStyle.tileRadius),
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
                  color: LuminousHomeTheme.textPrimary,
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
          Icon(icon, size: 24, color: LuminousHomeTheme.textMuted),
          const SizedBox(height: 8),
          Text(
            title,
            style: const TextStyle(
              color: LuminousHomeTheme.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            hint,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: LuminousHomeTheme.textMuted,
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
