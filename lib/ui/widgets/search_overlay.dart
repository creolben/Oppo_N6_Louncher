import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/app_entry.dart';
import '../../canvas/camera_controller.dart';
import '../../core/launcher_bridge.dart';

import '../../core/galaxy_layout_engine.dart';
import 'comet_orb.dart';
import '../theme/luminous_home_theme.dart';

class CategoryTabItem {
  final String label;
  final AppCategory? category;
  final IconData icon;
  final Color color;

  const CategoryTabItem({
    required this.label,
    required this.category,
    required this.icon,
    required this.color,
  });
}

class SearchOverlay extends StatefulWidget {
  final List<AppEntry> allApps;
  final CameraController camera;
  final VoidCallback onClose;
  final VoidCallback? onOpenSettings;
  final GalaxyLayoutEngine? layoutEngine;
  final Function(AppEntry app, Offset screenPosition)? onAppLongPressed;

  /// Escalates the current query to the comet web-search surface.
  ///
  /// Deliberately not automatic: a miss in app search is a clear signal, but
  /// silently switching modes would surprise. The user taps, and their query
  /// carries over rather than being lost.
  final void Function(String query)? onSearchWeb;

  const SearchOverlay({
    super.key,
    required this.allApps,
    required this.camera,
    required this.onClose,
    this.onOpenSettings,
    this.layoutEngine,
    this.onAppLongPressed,
    this.onSearchWeb,
  });

  @override
  State<SearchOverlay> createState() => _SearchOverlayState();
}

class _SearchOverlayState extends State<SearchOverlay> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  AppCategory? _selectedCategory; // null = All
  bool _filterHiddenOnly = false;
  bool _isGridView = true;
  String? _activeScrubLetter;

  /// Clears the floating scrub letter after a beat.
  Timer? _scrubFeedbackTimer;

  /// Hit corridor for the A-Z rail. The visible rail is ~20dp wide; the touch
  /// area is the Android 48dp minimum.
  static const double _scrubberHitWidth = 48;

  /// The tallest one letter row may be, and therefore the largest scrub step.
  /// A shorter available height shrinks the row instead (see the rail's
  /// [LayoutBuilder]) so 27 rows still fit when the keyboard is up; at the
  /// full height the step is this value and the drag mapping is exact.
  static const double _scrubRowHeight = 12;

  /// Below this per-letter height the rail stops being readable or tappable,
  /// so it is dropped entirely rather than drawn into an overflow.
  static const double _scrubMinRowHeight = 7;

  /// Padding and hairline border of the rail's frame. Both are part of the
  /// offset a drag position has to be measured against.
  static const double _scrubberPadV = 4;
  static const double _scrubberBorder = 0.8;

  /// The rail is inset this far from the top and bottom of the results area.
  static const double _scrubberVerticalInset = 4;

  /// Grid geometry, shared with [_jumpToLetter] so a letter jump lands on the
  /// row the grid actually paints.
  static const double _gridMaxCrossExtent = 95;
  static const double _gridMainSpacing = 14;
  static const double _gridCrossSpacing = 12;
  static const double _gridAspectRatio = 0.82;
  static const double _gridPadLeft = 16;
  static const double _gridPadTop = 8;
  static const double _gridPadBottom = 24;

  /// The list's fixed row stride, used only by the letter jump.
  static const double _listItemHeight = 76;

  /// Vertical breathing room between the results and the rail: the grid/list
  /// reserve the rail's full hit width plus this, so no tile sits under it.
  static const double _railGap = 8;

  static const List<String> _alphabet = [
    '#', 'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J',
    'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U',
    'V', 'W', 'X', 'Y', 'Z',
  ];

  static const List<CategoryTabItem> _categories = [
    CategoryTabItem(
      label: 'All',
      category: null,
      icon: Icons.all_inclusive_rounded,
      color: LuminousHomeTheme.aqua,
    ),
    CategoryTabItem(
      label: 'Essentials',
      category: AppCategory.core,
      icon: Icons.star_rounded,
      color: LuminousHomeTheme.accentCore,
    ),
    CategoryTabItem(
      label: 'Connect',
      category: AppCategory.social,
      icon: Icons.forum_rounded,
      color: LuminousHomeTheme.constellationSocial,
    ),
    CategoryTabItem(
      label: 'Workspace',
      category: AppCategory.productivity,
      icon: Icons.workspaces_rounded,
      color: LuminousHomeTheme.aqua,
    ),
    CategoryTabItem(
      label: 'Studio',
      category: AppCategory.entertainment,
      icon: Icons.play_circle_filled_rounded,
      color: LuminousHomeTheme.constellationEntertainment,
    ),
    CategoryTabItem(
      label: 'Utilities',
      category: AppCategory.tools,
      icon: Icons.tune_rounded,
      color: LuminousHomeTheme.constellationTools,
    ),
    CategoryTabItem(
      label: 'Games',
      category: AppCategory.games,
      icon: Icons.sports_esports_rounded,
      color: LuminousHomeTheme.accentGames,
    ),
  ];

  List<CategoryTabItem> get _availableCategories {
    final list = List<CategoryTabItem>.from(_categories);
    if (widget.layoutEngine != null && widget.layoutEngine!.hiddenPackageNames.isNotEmpty) {
      list.add(
        const CategoryTabItem(
          label: 'Hidden',
          category: null,
          icon: Icons.visibility_off_rounded,
          color: LuminousHomeTheme.danger,
        ),
      );
    }
    return list;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  List<AppEntry> get _filteredApps {
    final query = _controller.text.toLowerCase().trim();
    final hiddenList = widget.layoutEngine?.hiddenPackageNames ?? const [];

    final list = widget.allApps.where((app) {
      final isHidden = hiddenList.contains(app.packageName);
      if (_filterHiddenOnly) {
        if (!isHidden) return false;
      } else {
        // By default, hide hidden apps unless in Hidden tab or explicitly searching
        if (query.isEmpty && isHidden) return false;
        if (_selectedCategory != null && app.category != _selectedCategory) {
          return false;
        }
      }
      if (query.isNotEmpty) {
        return app.label.toLowerCase().contains(query) ||
            app.packageName.toLowerCase().contains(query);
      }
      return true;
    }).toList();

    list.sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
    return list;
  }

  int _countForCategory(CategoryTabItem item) {
    final hiddenList = widget.layoutEngine?.hiddenPackageNames ?? const [];
    if (item.label == 'Hidden') {
      return hiddenList.length;
    }
    if (item.category == null) {
      return widget.allApps.where((a) => !hiddenList.contains(a.packageName)).length;
    }
    return widget.allApps.where((a) => !hiddenList.contains(a.packageName) && a.category == item.category).length;
  }

  /// A bar height that follows the system text scale.
  ///
  /// Scroll views need a bounded cross-axis, so these rows cannot simply use a
  /// min-height; scaling the height is what keeps their labels from clipping
  /// when the user turns the font up. Bounded, so a huge scale cannot push the
  /// list off the screen.
  static double _scaledBarHeight(BuildContext context, double base) {
    final double factor =
        MediaQuery.textScalerOf(context).scale(1.0).clamp(1.0, 1.8);
    return base * factor;
  }

  /// Maps a drag on the rail to a letter, so scrubbing never needs a precise
  /// hit on a 9px glyph.
  ///
  /// [rowHeight] is the height the rail actually laid its rows out at, which
  /// the hit test must share or the mapping drifts as the keyboard shrinks it.
  void _scrubToLocalY(double localY, double rowHeight) {
    final double rowsHeight = _alphabet.length * rowHeight;
    if (rowsHeight <= 0) return;
    // localY is relative to the rail's frame, so step past its border and
    // padding to reach the first row.
    final double withinRows = localY - _scrubberPadV - _scrubberBorder;
    final int index = (withinRows / rowsHeight * _alphabet.length)
        .floor()
        .clamp(0, _alphabet.length - 1);
    _jumpToLetter(_alphabet[index]);
  }

  /// The column count and row pitch a grid of content width [gridWidth] gets.
  ///
  /// Mirrors [SliverGridDelegateWithMaxCrossAxisExtent]; if the two drift
  /// apart, a letter jump lands on the wrong row.
  static (int, double) _gridMetrics(double gridWidth) {
    // Exactly the delegate's own formula (no upper clamp: the delegate has
    // none, and a wide screen can lay out more than ten columns).
    final int columns = math.max(
      1,
      (gridWidth / (_gridMaxCrossExtent + _gridCrossSpacing)).ceil(),
    );
    final double usableCross =
        gridWidth - _gridCrossSpacing * (columns - 1);
    final double childCross = usableCross / columns;
    return (columns, childCross / _gridAspectRatio + _gridMainSpacing);
  }

  /// Whether the rail fits in [availableHeight], and what it needs from the
  /// results column if so.
  ///
  /// The rail is dropped below [_scrubMinRowHeight] per letter rather than
  /// overflowing; when it is dropped its reserved width is released back to
  /// the grid.
  ({bool visible, double rowHeight, double rightInset}) _railMetrics(
    double availableHeight,
  ) {
    final double trackHeight = availableHeight -
        2 * _scrubberVerticalInset -
        2 * _scrubberPadV -
        2 * _scrubberBorder;
    final double rowHeight = math.min(
      _scrubRowHeight,
      trackHeight / _alphabet.length,
    );
    final bool visible = rowHeight >= _scrubMinRowHeight;
    return (
      visible: visible,
      rowHeight: rowHeight,
      rightInset: visible ? _scrubberHitWidth + _railGap : _gridPadLeft,
    );
  }

  void _jumpToLetter(String letter) {
    final apps = _filteredApps;
    if (apps.isEmpty) return;

    int targetIndex = -1;
    if (letter == '#') {
      targetIndex = 0;
    } else {
      targetIndex = apps.indexWhere((app) {
        final first = app.label.trim();
        if (first.isEmpty) return false;
        return first[0].toUpperCase() == letter;
      });
    }

    if (targetIndex != -1 && _scrollController.hasClients) {
      HapticFeedback.selectionClick();
      setState(() => _activeScrubLetter = letter);

      double targetOffset = 0.0;
      if (_isGridView) {
        // Jumps only fire from the rail (the rail's letters and drag are the
        // only callers), so the rail is visible and its width plus gap is the
        // right padding the grid was built with. Mirrors the delegate's own
        // column maths so the jump lands on the painted row.
        final double gridWidth = MediaQuery.of(context).size.width -
            _gridPadLeft -
            (_scrubberHitWidth + _railGap);
        final (int columns, double rowPitch) = _gridMetrics(gridWidth);
        targetOffset = (targetIndex ~/ columns) * rowPitch;
      } else {
        targetOffset = targetIndex * _listItemHeight;
      }

      final maxOffset = _scrollController.position.maxScrollExtent;
      _scrollController.animateTo(
        targetOffset.clamp(0.0, maxOffset),
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );

      // Cancellable, and cancelled on dispose: a fire-and-forget delay here
      // outlived the widget and stranded a timer past teardown.
      _scrubFeedbackTimer?.cancel();
      _scrubFeedbackTimer = Timer(const Duration(milliseconds: 800), () {
        if (mounted && _activeScrubLetter == letter) {
          setState(() => _activeScrubLetter = null);
        }
      });
    }
  }

  void _flyToAndLaunch(AppEntry app) {
    widget.camera.flyTo(app.worldPosition, targetZoom: 1.6);
    widget.onClose();
  }

  /// Converts a failed app search into a web search, carrying the query over.
  Widget _buildCosmosEscalation() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          HapticFeedback.lightImpact();
          widget.onSearchWeb!(_controller.text.trim());
        },
        borderRadius: BorderRadius.circular(22),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          decoration: BoxDecoration(
            color: LuminousHomeTheme.ember.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: LuminousHomeTheme.ember.withValues(alpha: 0.45),
            ),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CometOrb(size: 18),
              SizedBox(width: 10),
              Text(
                'Not in this galaxy — search the cosmos',
                style: TextStyle(
                  color: LuminousHomeTheme.emberLight,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.2,
                ),
              ),
              SizedBox(width: 6),
              Icon(
                Icons.arrow_forward_rounded,
                size: 15,
                color: LuminousHomeTheme.emberLight,
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _scrubFeedbackTimer?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredApps;

    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 20.0, sigmaY: 20.0),
      child: Container(
        color: LuminousHomeTheme.scrim,
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Search Input Field & Action Buttons
              Padding(
                padding: const EdgeInsets.fromLTRB(16.0, 12.0, 16.0, 8.0),
                child: Row(
                  children: [
                    Expanded(
                      child: Container(
                        // Grows with the system font instead of clipping it.
                        constraints: const BoxConstraints(minHeight: 50),
                        decoration: BoxDecoration(
                          color: LuminousHomeTheme.glassCool.withValues(alpha: 0.90),
                          borderRadius: BorderRadius.circular(25),
                          border: Border.all(
                            color: LuminousHomeTheme.borderCool.withValues(alpha: 0.35),
                            width: 1.2,
                          ),
                          boxShadow: const [
                            BoxShadow(
                              color: LuminousHomeTheme.aquaSoft,
                              blurRadius: 16,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                        child: TextField(
                          controller: _controller,
                          focusNode: _focusNode,
                          onChanged: (_) => setState(() {}),
                          style: const TextStyle(
                            color: LuminousHomeTheme.white,
                            fontSize: 15,
                            letterSpacing: 0.4,
                          ),
                          cursorColor: LuminousHomeTheme.aqua,
                          decoration: InputDecoration(
                            hintText: 'Search galaxy applications...',
                            hintStyle: TextStyle(
                              color: LuminousHomeTheme.white.withValues(alpha: 0.42),
                              fontSize: 14,
                            ),
                            prefixIcon: const Icon(
                              Icons.search_rounded,
                              color: LuminousHomeTheme.aqua,
                              size: 22,
                            ),
                            suffixIcon: _controller.text.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear_rounded, color: LuminousHomeTheme.white70, size: 20),
                                    onPressed: () {
                                      _controller.clear();
                                      setState(() {});
                                    },
                                  )
                                : null,
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),

                    // Grid / List Toggle
                    IconButton(
                      icon: Icon(
                        _isGridView ? Icons.view_list_rounded : Icons.grid_view_rounded,
                        color: LuminousHomeTheme.white70,
                        size: 24,
                      ),
                      tooltip: _isGridView ? 'Switch to List' : 'Switch to Grid',
                      onPressed: () => setState(() => _isGridView = !_isGridView),
                    ),

                    // System Settings Shortcut
                    if (widget.onOpenSettings != null)
                      IconButton(
                        icon: const Icon(Icons.tune_rounded, color: LuminousHomeTheme.white70, size: 24),
                        tooltip: 'System Settings',
                        onPressed: widget.onOpenSettings,
                      ),

                    // Close Overlay Button
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: LuminousHomeTheme.white, size: 26),
                      onPressed: widget.onClose,
                    ),
                  ],
                ),
              ),

              // Category Sector Filter Bar. A fixed 44 clipped the chip labels
              // as soon as the system font grew them, and a horizontal list
              // needs a bounded height, so the bar is sized from the scale.
              SizedBox(
                height: _scaledBarHeight(context, 48),
                child: Builder(builder: (context) {
                  final categories = _availableCategories;
                  return ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    itemCount: categories.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      final item = categories[index];
                      final isSelected = item.label == 'Hidden'
                          ? _filterHiddenOnly
                          : (!_filterHiddenOnly && _selectedCategory == item.category);
                      final count = _countForCategory(item);

                      return Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () {
                            setState(() {
                              if (item.label == 'Hidden') {
                                _filterHiddenOnly = true;
                                _selectedCategory = null;
                              } else {
                                _filterHiddenOnly = false;
                                _selectedCategory = item.category;
                              }
                            });
                          },
                          borderRadius: BorderRadius.circular(20),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6.0),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? item.color.withValues(alpha: 0.25)
                                  : LuminousHomeTheme.glassPanel.withValues(alpha: 0.65),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: isSelected
                                    ? item.color.withValues(alpha: 0.85)
                                    : LuminousHomeTheme.white.withValues(alpha: 0.12),
                                width: isSelected ? 1.4 : 1.0,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  item.icon,
                                  size: 16,
                                  color: isSelected ? item.color : LuminousHomeTheme.white60,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  item.label,
                                  style: TextStyle(
                                    color: isSelected ? LuminousHomeTheme.white : LuminousHomeTheme.white70,
                                    fontSize: 13,
                                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? item.color.withValues(alpha: 0.45)
                                        : LuminousHomeTheme.white.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    '$count',
                                    style: TextStyle(
                                      color: isSelected ? LuminousHomeTheme.white : LuminousHomeTheme.white60,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  );
                }),
              ),

              const SizedBox(height: 6),

              // Filtered Apps Count Telemetry
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 4.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(
                      child: Text(
                        '${filtered.length} applications in sector',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        softWrap: false,
                        style: TextStyle(
                          color: LuminousHomeTheme.white.withValues(alpha: 0.45),
                          fontSize: 12,
                          letterSpacing: 0.6,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    if (_controller.text.isNotEmpty ||
                        _selectedCategory != null ||
                        _filterHiddenOnly) ...[
                      const SizedBox(width: 12),
                      Semantics(
                        button: true,
                        label: 'Reset filter',
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () {
                            setState(() {
                              _controller.clear();
                              _selectedCategory = null;
                              _filterHiddenOnly = false;
                            });
                          },
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(minHeight: 48),
                            child: Center(
                              child: Text(
                                'Reset filter',
                                style: TextStyle(
                                  color:
                                      LuminousHomeTheme.aqua.withValues(alpha: 0.85),
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              const Divider(color: LuminousHomeTheme.dividerFaint, height: 12),

              // Apps Presentation (Grid or List) with A-Z Scrubber Rail
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final metrics = _railMetrics(constraints.maxHeight);
                    return Stack(
                      children: [
                        filtered.isEmpty
                            ? Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.radar_rounded,
                                      size: 48,
                                      color: LuminousHomeTheme.white
                                          .withValues(alpha: 0.25),
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      _filterHiddenOnly
                                          ? 'No hidden applications'
                                          : 'No stars found in this sector',
                                      style: TextStyle(
                                        color: LuminousHomeTheme.white
                                            .withValues(alpha: 0.45),
                                        fontSize: 14,
                                        letterSpacing: 0.8,
                                      ),
                                    ),
                                    // The escalation. A miss in app search is
                                    // exactly when web search is wanted, so the
                                    // affordance appears here rather than only
                                    // in the bar the user has already left
                                    // behind.
                                    if (!_filterHiddenOnly &&
                                        widget.onSearchWeb != null &&
                                        _controller.text.trim().isNotEmpty) ...[
                                      const SizedBox(height: 20),
                                      _buildCosmosEscalation(),
                                    ],
                                  ],
                                ),
                              )
                            : (_isGridView
                                ? _buildGridView(filtered, metrics.rightInset)
                                : _buildListView(filtered, metrics.rightInset)),

                        // A-Z Scrubber Rail on right edge.
                        //
                        // One drag surface rather than 27 ~13px taps: the whole
                        // rail maps a vertical position to a letter, so a finger
                        // can scrub without aiming, and the corridor is 48dp
                        // wide for the Android touch minimum while the visible
                        // rail stays narrow. Letters stay individually tappable,
                        // so a screen reader keeps letter-level buttons.
                        if (filtered.isNotEmpty && metrics.visible)
                          Positioned(
                            right: 0,
                            top: _scrubberVerticalInset,
                            bottom: _scrubberVerticalInset,
                            width: _scrubberHitWidth,
                            child: Center(
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTapDown: (d) => _scrubToLocalY(
                                    d.localPosition.dy, metrics.rowHeight),
                                onVerticalDragUpdate: (d) => _scrubToLocalY(
                                    d.localPosition.dy, metrics.rowHeight),
                                child: SizedBox(
                                  width: _scrubberHitWidth,
                                  child: Center(
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          vertical: _scrubberPadV,
                                          horizontal: 2),
                                      decoration: BoxDecoration(
                                        color: LuminousHomeTheme.fieldFill,
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: LuminousHomeTheme.aquaFaint,
                                          width: _scrubberBorder,
                                        ),
                                      ),
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: _alphabet.map((letter) {
                                          final isActive =
                                              _activeScrubLetter == letter;
                                          return GestureDetector(
                                            behavior: HitTestBehavior.opaque,
                                            onTap: () => _jumpToLetter(letter),
                                            child: SizedBox(
                                              height: metrics.rowHeight,
                                              child: Center(
                                                child: Text(
                                                  letter,
                                                  style: TextStyle(
                                                    color: isActive
                                                        ? LuminousHomeTheme.aqua
                                                        : LuminousHomeTheme
                                                            .white
                                                            .withValues(
                                                                alpha: 0.45),
                                                    fontSize: 9.0,
                                                    // Pin the line box so a row
                                                    // is exactly rowHeight and
                                                    // the drag mapping stays
                                                    // true.
                                                    height: 1.0,
                                                    fontWeight: isActive
                                                        ? FontWeight.bold
                                                        : FontWeight.w500,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          );
                                        }).toList(),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),

                        // Floating Scrub Letter Feedback
                        if (_activeScrubLetter != null)
                          Center(
                            child: Container(
                              width: 64,
                              height: 64,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: LuminousHomeTheme.panelScrim,
                                border: Border.all(
                                    color: LuminousHomeTheme.aqua, width: 1.8),
                                boxShadow: const [
                                  BoxShadow(
                                    color: LuminousHomeTheme.aquaBright,
                                    blurRadius: 20,
                                    spreadRadius: 2,
                                  ),
                                ],
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                _activeScrubLetter!,
                                style: const TextStyle(
                                  color: LuminousHomeTheme.aqua,
                                  fontSize: 28,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGridView(List<AppEntry> apps, double rightInset) {
    return GridView.builder(
      controller: _scrollController,
      padding: EdgeInsets.fromLTRB(
        _gridPadLeft,
        _gridPadTop,
        rightInset,
        _gridPadBottom,
      ),
      physics: const BouncingScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: _gridMaxCrossExtent,
        mainAxisSpacing: _gridMainSpacing,
        crossAxisSpacing: _gridCrossSpacing,
        childAspectRatio: _gridAspectRatio,
      ),
      itemCount: apps.length,
      itemBuilder: (context, index) {
        final app = apps[index];

        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {
              LauncherBridge.launchApp(app);
              widget.onClose();
            },
            onLongPress: () {
              HapticFeedback.mediumImpact();
              if (widget.onAppLongPressed != null) {
                widget.onAppLongPressed!(app, Offset.zero);
              } else {
                _flyToAndLaunch(app);
              }
            },
            borderRadius: BorderRadius.circular(18),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
              decoration: BoxDecoration(
                color: LuminousHomeTheme.glassPanel.withValues(alpha: 0.65),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: app.accentColor.withValues(alpha: 0.25),
                  width: 1.0,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: app.accentColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: app.accentColor.withValues(alpha: 0.45),
                        width: 1.2,
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
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
                  const SizedBox(height: 6),
                  Text(
                    app.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: LuminousHomeTheme.white,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.2,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildListView(List<AppEntry> apps, double rightInset) {
    return ListView.builder(
      controller: _scrollController,
      padding: EdgeInsets.fromLTRB(
        _gridPadLeft,
        _gridPadTop,
        rightInset,
        _gridPadBottom,
      ),
      physics: const BouncingScrollPhysics(),
      itemCount: apps.length,
      itemBuilder: (context, index) {
        final app = apps[index];
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: LuminousHomeTheme.panel.withValues(alpha: 0.70),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: app.accentColor.withValues(alpha: 0.25),
              width: 1.0,
            ),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
            leading: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: app.accentColor.withValues(alpha: 0.15),
                border: Border.all(
                  color: app.accentColor.withValues(alpha: 0.45),
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
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
            title: Text(
              app.label,
              style: const TextStyle(
                color: LuminousHomeTheme.white,
                fontWeight: FontWeight.w600,
                fontSize: 15,
              ),
            ),
            subtitle: Text(
              app.packageName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: LuminousHomeTheme.white.withValues(alpha: 0.40),
                fontSize: 12,
              ),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.radar_rounded, color: LuminousHomeTheme.aqua, size: 22),
                  tooltip: 'Locate in galaxy',
                  onPressed: () => _flyToAndLaunch(app),
                ),
                IconButton(
                  icon: const Icon(Icons.launch_rounded, color: LuminousHomeTheme.white70, size: 22),
                  tooltip: 'Launch app',
                  onPressed: () {
                    LauncherBridge.launchApp(app);
                    widget.onClose();
                  },
                ),
              ],
            ),
            onLongPress: () {
              HapticFeedback.mediumImpact();
              if (widget.onAppLongPressed != null) {
                widget.onAppLongPressed!(app, Offset.zero);
              } else {
                _flyToAndLaunch(app);
              }
            },
            onTap: () {
              LauncherBridge.launchApp(app);
              widget.onClose();
            },
          ),
        );
      },
    );
  }
}
