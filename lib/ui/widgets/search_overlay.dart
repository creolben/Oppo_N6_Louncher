import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/app_entry.dart';
import '../../canvas/camera_controller.dart';
import '../../core/launcher_bridge.dart';

import '../../core/galaxy_layout_engine.dart';
import 'comet_orb.dart';

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
      color: Color(0xFF00E5FF),
    ),
    CategoryTabItem(
      label: 'Essentials',
      category: AppCategory.core,
      icon: Icons.star_rounded,
      color: Color(0xFFFFD54F),
    ),
    CategoryTabItem(
      label: 'Connect',
      category: AppCategory.social,
      icon: Icons.forum_rounded,
      color: Color(0xFFFF4081),
    ),
    CategoryTabItem(
      label: 'Workspace',
      category: AppCategory.productivity,
      icon: Icons.workspaces_rounded,
      color: Color(0xFF00E5FF),
    ),
    CategoryTabItem(
      label: 'Studio',
      category: AppCategory.entertainment,
      icon: Icons.play_circle_filled_rounded,
      color: Color(0xFF00E676),
    ),
    CategoryTabItem(
      label: 'Utilities',
      category: AppCategory.tools,
      icon: Icons.tune_rounded,
      color: Color(0xFFFFAB00),
    ),
    CategoryTabItem(
      label: 'Games',
      category: AppCategory.games,
      icon: Icons.sports_esports_rounded,
      color: Color(0xFFBA68C8),
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
          color: Color(0xFFFF5252),
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
        final screenWidth = MediaQuery.of(context).size.width;
        final crossAxisCount = (screenWidth / 95).floor().clamp(1, 10);
        final rowIndex = targetIndex ~/ crossAxisCount;
        const rowHeight = 115.0;
        targetOffset = rowIndex * rowHeight;
      } else {
        const itemHeight = 76.0;
        targetOffset = targetIndex * itemHeight;
      }

      final maxOffset = _scrollController.position.maxScrollExtent;
      _scrollController.animateTo(
        targetOffset.clamp(0.0, maxOffset),
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );

      Future.delayed(const Duration(milliseconds: 800), () {
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
            color: const Color(0xFFFFB300).withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: const Color(0xFFFFB300).withValues(alpha: 0.45),
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
                  color: Color(0xFFFFC64D),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.2,
                ),
              ),
              SizedBox(width: 6),
              Icon(
                Icons.arrow_forward_rounded,
                size: 15,
                color: Color(0xFFFFC64D),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
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
        color: const Color(0xCC04060E),
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
                        height: 50,
                        decoration: BoxDecoration(
                          color: const Color(0xFF141A30).withValues(alpha: 0.90),
                          borderRadius: BorderRadius.circular(25),
                          border: Border.all(
                            color: const Color(0xFF64B5F6).withValues(alpha: 0.35),
                            width: 1.2,
                          ),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x2200E5FF),
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
                            color: Colors.white,
                            fontSize: 15,
                            letterSpacing: 0.4,
                          ),
                          cursorColor: const Color(0xFF00E5FF),
                          decoration: InputDecoration(
                            hintText: 'Search galaxy applications...',
                            hintStyle: TextStyle(
                              color: Colors.white.withValues(alpha: 0.42),
                              fontSize: 14,
                            ),
                            prefixIcon: const Icon(
                              Icons.search_rounded,
                              color: Color(0xFF00E5FF),
                              size: 22,
                            ),
                            suffixIcon: _controller.text.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear_rounded, color: Colors.white70, size: 20),
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
                        color: Colors.white70,
                        size: 24,
                      ),
                      tooltip: _isGridView ? 'Switch to List' : 'Switch to Grid',
                      onPressed: () => setState(() => _isGridView = !_isGridView),
                    ),

                    // System Settings Shortcut
                    if (widget.onOpenSettings != null)
                      IconButton(
                        icon: const Icon(Icons.tune_rounded, color: Colors.white70, size: 24),
                        tooltip: 'System Settings',
                        onPressed: widget.onOpenSettings,
                      ),

                    // Close Overlay Button
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: Colors.white, size: 26),
                      onPressed: widget.onClose,
                    ),
                  ],
                ),
              ),

              // Category Sector Filter Bar
              SizedBox(
                height: 44,
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
                                  : const Color(0xFF101526).withValues(alpha: 0.65),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: isSelected
                                    ? item.color.withValues(alpha: 0.85)
                                    : Colors.white.withValues(alpha: 0.12),
                                width: isSelected ? 1.4 : 1.0,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  item.icon,
                                  size: 16,
                                  color: isSelected ? item.color : Colors.white60,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  item.label,
                                  style: TextStyle(
                                    color: isSelected ? Colors.white : Colors.white70,
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
                                        : Colors.white.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    '$count',
                                    style: TextStyle(
                                      color: isSelected ? Colors.white : Colors.white60,
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
                    Text(
                      '${filtered.length} applications in sector',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.45),
                        fontSize: 12,
                        letterSpacing: 0.6,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (_controller.text.isNotEmpty || _selectedCategory != null || _filterHiddenOnly)
                      GestureDetector(
                        onTap: () {
                          setState(() {
                            _controller.clear();
                            _selectedCategory = null;
                            _filterHiddenOnly = false;
                          });
                        },
                        child: Text(
                          'Reset filter',
                          style: TextStyle(
                            color: const Color(0xFF00E5FF).withValues(alpha: 0.85),
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                  ],
                ),
              ),

              const Divider(color: Color(0x22FFFFFF), height: 12),

              // Apps Presentation (Grid or List) with A-Z Scrubber Rail
              Expanded(
                child: Stack(
                  children: [
                    filtered.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.radar_rounded,
                                  size: 48,
                                  color: Colors.white.withValues(alpha: 0.25),
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  _filterHiddenOnly
                                      ? 'No hidden applications'
                                      : 'No stars found in this sector',
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.45),
                                    fontSize: 14,
                                    letterSpacing: 0.8,
                                  ),
                                ),
                                // The escalation. A miss in app search is
                                // exactly when web search is wanted, so the
                                // affordance appears here rather than only in
                                // the bar the user has already left behind.
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
                            ? _buildGridView(filtered)
                            : _buildListView(filtered)),

                    // A-Z Scrubber Rail on right edge
                    if (filtered.isNotEmpty)
                      Positioned(
                        right: 2,
                        top: 4,
                        bottom: 4,
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                            decoration: BoxDecoration(
                              color: const Color(0x330C1020),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: const Color(0x1800E5FF),
                                width: 0.8,
                              ),
                            ),
                            child: SingleChildScrollView(
                              physics: const NeverScrollableScrollPhysics(),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: _alphabet.map((letter) {
                                  final isActive = _activeScrubLetter == letter;
                                  return GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onTap: () => _jumpToLetter(letter),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 1.0, horizontal: 3.5),
                                      child: Text(
                                        letter,
                                        style: TextStyle(
                                          color: isActive
                                              ? const Color(0xFF00E5FF)
                                              : Colors.white.withValues(alpha: 0.45),
                                          fontSize: 9.0,
                                          fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
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

                    // Floating Scrub Letter Feedback
                    if (_activeScrubLetter != null)
                      Center(
                        child: Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: const Color(0xEE12182E),
                            border: Border.all(color: const Color(0xFF00E5FF), width: 1.8),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x5500E5FF),
                                blurRadius: 20,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            _activeScrubLetter!,
                            style: const TextStyle(
                              color: Color(0xFF00E5FF),
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGridView(List<AppEntry> apps) {
    return GridView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(16, 8, 30, 24),
      physics: const BouncingScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 95,
        mainAxisSpacing: 14,
        crossAxisSpacing: 12,
        childAspectRatio: 0.82,
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
                color: const Color(0xFF101528).withValues(alpha: 0.65),
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
                      color: Colors.white,
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

  Widget _buildListView(List<AppEntry> apps) {
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(16, 8, 30, 24),
      physics: const BouncingScrollPhysics(),
      itemCount: apps.length,
      itemBuilder: (context, index) {
        final app = apps[index];
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF101424).withValues(alpha: 0.70),
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
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 15,
              ),
            ),
            subtitle: Text(
              app.packageName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.40),
                fontSize: 12,
              ),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.radar_rounded, color: Color(0xFF00E5FF), size: 22),
                  tooltip: 'Locate in galaxy',
                  onPressed: () => _flyToAndLaunch(app),
                ),
                IconButton(
                  icon: const Icon(Icons.launch_rounded, color: Colors.white70, size: 22),
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
