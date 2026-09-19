import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'models/app_entry.dart';
import 'models/constellation.dart';
import 'core/launcher_bridge.dart';
import 'core/foldable_controller.dart';
import 'core/galaxy_layout_engine.dart';
import 'canvas/camera_controller.dart';
import 'canvas/galaxy_interactive_canvas.dart';
import 'ui/widgets/foldable_cockpit_bar.dart';
import 'ui/widgets/search_overlay.dart';
import 'ui/widgets/app_action_dialog.dart';
import 'ui/widgets/constellation_editor_modal.dart';
import 'ui/widgets/create_constellation_modal.dart';
import 'core/galaxy_storage_service.dart';
import 'features/lockscreen/cosmic_lock_screen.dart';
import 'ui/screens/folded_cover_screen.dart';
import 'ui/screens/tabletop_cockpit_view.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  runApp(const ChronoFoldApp());
}

class ChronoFoldApp extends StatelessWidget {
  const ChronoFoldApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ChronoFold Launcher',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF020306),
        fontFamily: 'Roboto',
      ),
      home: const ChronoFoldHomeScreen(),
    );
  }
}

class ChronoFoldHomeScreen extends StatefulWidget {
  const ChronoFoldHomeScreen({super.key});

  @override
  State<ChronoFoldHomeScreen> createState() => _ChronoFoldHomeScreenState();
}

class _ChronoFoldHomeScreenState extends State<ChronoFoldHomeScreen>
    with WidgetsBindingObserver {
  late final FoldableController _foldable;
  late final CameraController _camera;
  late final GalaxyLayoutEngine _layoutEngine;

  List<AppEntry> _apps = [];
  bool _isLoading = true;
  bool _isSearchOpen = false;
  bool _isLocked = false;
  bool _isCockpitMode = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _foldable = FoldableController();
    _camera = CameraController();
    _layoutEngine = GalaxyLayoutEngine();

    LauncherBridge.setScreenLockListener(_lockForScreenOff);

    LauncherBridge.setPackageChangeListener(() {
      if (mounted) {
        _loadApplications();
      }
    });

    LauncherBridge.setHomeButtonListener(() {
      if (mounted) {
        if (_isSearchOpen) {
          setState(() => _isSearchOpen = false);
        }
        _camera.resetView();
      }
    });

    _loadApplications();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      _lockForScreenOff();
    }
  }

  /// Raises the cover-screen lock when the panel goes off or the launcher is
  /// backgrounded. The platform keyguard authenticates a touch on the reader
  /// behind it and hands the unlock back, which is what clears this overlay.
  void _lockForScreenOff() {
    if (!mounted) return;
    setState(() => _isLocked = true);
  }


  Future<void> _loadApplications() async {
    final apps = await LauncherBridge.getInstalledApps();
    
    // Load persisted galaxy configuration
    final config = await GalaxyStorageService.loadConfig();
    if (config.isNotEmpty) {
      final customList = (config['customConstellations'] ?? config['customGalaxies']) as List?;
      if (customList != null) {
        for (final raw in customList) {
          if (raw is Map<String, dynamic>) {
            final customConfig = CustomConstellationConfig.fromJson(raw);
            _layoutEngine.createCustomConstellation(
              id: customConfig.id,
              name: customConfig.name,
              primaryColor: Color(customConfig.primaryColorValue),
              emblemIcon: customConfig.icon,
              packageNames: customConfig.packageNames,
            );
          }
        }
      }
      if (config.containsKey('coreAppPackageNames') && config['coreAppPackageNames'] is List) {
        final corePkgs = List<String>.from(config['coreAppPackageNames'] as List);
        _layoutEngine.setCorePackageNames(corePkgs);
      }
      if (config.containsKey('constellationAppOverrides') && config['constellationAppOverrides'] is Map) {
        final rawOverrides = config['constellationAppOverrides'] as Map<String, dynamic>;
        for (final entry in rawOverrides.entries) {
          if (entry.value is List) {
            _layoutEngine.constellationAppOverrides[entry.key] = List<String>.from(entry.value as List);
          }
        }
      }
      if (config.containsKey('hiddenPackageNames') && config['hiddenPackageNames'] is List) {
        final hiddenPkgs = List<String>.from(config['hiddenPackageNames'] as List);
        _layoutEngine.setHiddenPackageNames(hiddenPkgs);
      }
    }

    _layoutEngine.assignApps(apps);
    if (mounted) {
      setState(() {
        _apps = apps;
        _isLoading = false;
      });
    }
  }

  void _openAppLongPressDialog(AppEntry app, Offset screenPosition) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'AppActions',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 240),
      pageBuilder: (context, anim1, anim2) {
        return AppActionDialog(
          app: app,
          layoutEngine: _layoutEngine,
          onActionCompleted: () => setState(() {}),
        );
      },
      transitionBuilder: (context, anim, secondaryAnim, child) {
        return FadeTransition(
          opacity: CurvedAnimation(parent: anim, curve: Curves.easeOutCubic),
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.85, end: 1.0).animate(
              CurvedAnimation(parent: anim, curve: Curves.easeOutBack),
            ),
            child: child,
          ),
        );
      },
    );
  }

  void _openConstellationEditorModal(Constellation constellation) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'ConstellationEditor',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 260),
      pageBuilder: (context, anim1, anim2) {
        return ConstellationEditorModal(
          constellation: constellation,
          layoutEngine: _layoutEngine,
          allApps: _apps,
          onUpdated: () => setState(() {}),
        );
      },
      transitionBuilder: (context, anim, secondaryAnim, child) {
        return FadeTransition(
          opacity: CurvedAnimation(parent: anim, curve: Curves.easeOutCubic),
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.9, end: 1.0).animate(
              CurvedAnimation(parent: anim, curve: Curves.easeOutBack),
            ),
            child: child,
          ),
        );
      },
    );
  }

  void _openCenterConstellationEditorModal() {
    final core = _layoutEngine.constellations.firstWhere((c) => c.id == 'core');
    _openConstellationEditorModal(core);
  }

  void _openCreateConstellationModal() {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'CreateConstellation',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 260),
      pageBuilder: (context, anim1, anim2) {
        return CreateConstellationModal(
          layoutEngine: _layoutEngine,
          allApps: _apps,
          onCreated: () => setState(() {}),
        );
      },
      transitionBuilder: (context, anim, secondaryAnim, child) {
        return FadeTransition(
          opacity: CurvedAnimation(parent: anim, curve: Curves.easeOutCubic),
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.9, end: 1.0).animate(
              CurvedAnimation(parent: anim, curve: Curves.easeOutBack),
            ),
            child: child,
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _foldable.dispose();
    _camera.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _foldable.updateFromMediaQuery(context);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_isSearchOpen) {
          setState(() => _isSearchOpen = false);
        } else {
          _camera.resetView();
        }
      },
      child: Scaffold(
        body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(
                color: Color(0xFF00E5FF),
                strokeWidth: 2.0,
              ),
            )
          : ListenableBuilder(
              listenable: _foldable,
              builder: (context, _) {
                return Stack(
                  children: [
                    // Main Launcher Content (Folded Cover Screen vs Unfolded Cosmic Galaxy)
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 320),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      transitionBuilder: (child, animation) {
                        return FadeTransition(
                          opacity: animation,
                          child: child,
                        );
                      },
                      child: _foldable.isFolded
                          ? FoldedCoverScreen(
                              key: const ValueKey('folded_cover_screen'),
                              apps: _apps,
                              foldable: _foldable,
                              layoutEngine: _layoutEngine,
                              onOpenSearch: () => setState(() => _isSearchOpen = true),
                              onOpenSettings: () => LauncherBridge.openHomeSettings(),
                              onLock: () => setState(() => _isLocked = true),
                              onAppLongPressed: _openAppLongPressDialog,
                              onConstellationLongPressed: _openConstellationEditorModal,
                              onCreateConstellation: _openCreateConstellationModal,
                              onEditCore: _openCenterConstellationEditorModal,
                            )
                          : (_isCockpitMode && _foldable.isTabletop)
                              ? TabletopCockpitView(
                                  key: const ValueKey('tabletop_cockpit_view'),
                                  apps: _apps,
                                  foldable: _foldable,
                                  camera: _camera,
                                  layoutEngine: _layoutEngine,
                                  onOpenSearch: () => setState(() => _isSearchOpen = true),
                                  onOpenSettings: () => LauncherBridge.openHomeSettings(),
                                  onLock: () => setState(() => _isLocked = true),
                                  onAppLongPressed: _openAppLongPressDialog,
                                  onConstellationLongPressed: _openConstellationEditorModal,
                                  onCreateConstellation: _openCreateConstellationModal,
                                  onEditCore: _openCenterConstellationEditorModal,
                                  onToggleFullscreen: () => setState(() => _isCockpitMode = false),
                                )
                              : Stack(
                                  key: const ValueKey('unfolded_galaxy_screen'),
                                  children: [
                                    // 1. Kinetic Galaxy Canvas
                                    Positioned.fill(
                                      child: GalaxyInteractiveCanvas(
                                        apps: _apps,
                                        foldable: _foldable,
                                        camera: _camera,
                                        layoutEngine: _layoutEngine,
                                        onAppLongPressed: _openAppLongPressDialog,
                                        onConstellationLongPressed: _openConstellationEditorModal,
                                        onSwipeDown: () => setState(() => _isSearchOpen = true),
                                      ),
                                    ),

                                    // 2. Cosmic HUD Header (Clock, Date & Posture Telemetry)
                                    Positioned(
                                      top: 0,
                                      left: 0,
                                      right: 0,
                                      child: CosmicHeaderHud(
                                        foldable: _foldable,
                                        onToggleCockpit: _foldable.isTabletop
                                            ? () => setState(() => _isCockpitMode = true)
                                            : null,
                                      ),
                                    ),

                                    // 3. Ergonomic Bottom Cockpit Bar
                                    Positioned(
                                      bottom: 0,
                                      left: 0,
                                      right: 0,
                                      child: FoldableCockpitBar(
                                        foldable: _foldable,
                                        camera: _camera,
                                        layoutEngine: _layoutEngine,
                                        onOpenSearch: () => setState(() => _isSearchOpen = true),
                                        onOpenSettings: () => LauncherBridge.openHomeSettings(),
                                        onLock: () => setState(() => _isLocked = true),
                                        onCreateConstellation: _openCreateConstellationModal,
                                        onEditCore: _openCenterConstellationEditorModal,
                                      ),
                                    ),
                                  ],
                                ),
                    ),

                    // Fullscreen Search HUD & Categorized Celestial Library
                    if (_isSearchOpen)
                      Positioned.fill(
                        child: SearchOverlay(
                          allApps: _apps,
                          camera: _camera,
                          layoutEngine: _layoutEngine,
                          onAppLongPressed: _openAppLongPressDialog,
                          onClose: () => setState(() => _isSearchOpen = false),
                          onOpenSettings: () => LauncherBridge.openHomeSettings(),
                        ),
                      ),

                    // Celestial Foldable Lock Screen
                    if (_isLocked)
                      Positioned.fill(
                        child: CosmicLockScreen(
                          foldable: _foldable,
                          apps: _apps,
                          onUnlock: () => setState(() => _isLocked = false),
                        ),
                      ),
                  ],
                  );
                },
              ),
      ),
    );
  }
}

class CosmicHeaderHud extends StatefulWidget {
  final FoldableController foldable;
  final VoidCallback? onToggleCockpit;

  const CosmicHeaderHud({
    super.key,
    required this.foldable,
    this.onToggleCockpit,
  });

  @override
  State<CosmicHeaderHud> createState() => _CosmicHeaderHudState();
}

class _CosmicHeaderHudState extends State<CosmicHeaderHud> {
  late Timer _timer;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {
          _now = DateTime.now();
        });
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
    final timeString =
        '${_now.hour.toString().padLeft(2, '0')}:${_now.minute.toString().padLeft(2, '0')}';
    final dateString =
        '${_weekdayName(_now.weekday)}, ${_monthName(_now.month)} ${_now.day}';

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 8.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Clock & Date
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  timeString,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 34,
                    fontWeight: FontWeight.w200,
                    letterSpacing: -0.5,
                    shadows: [
                      Shadow(color: Color(0x6600E5FF), blurRadius: 16),
                    ],
                  ),
                ),
                Text(
                  dateString.toUpperCase(),
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.6),
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 2.0,
                  ),
                ),
              ],
            ),

            // Top Right: Posture Badge & Return to Cockpit Button
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.onToggleCockpit != null) ...[
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: widget.onToggleCockpit,
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0x33101424),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: const Color(0x4464B5F6),
                            width: 0.8,
                          ),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.splitscreen_rounded, color: Color(0xFF00E5FF), size: 14),
                            SizedBox(width: 4),
                            Text(
                              'COCKPIT',
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
                  const SizedBox(width: 8),
                ],
                ListenableBuilder(
                  listenable: widget.foldable,
                  builder: (context, _) {
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0x33101424),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: const Color(0x3364B5F6),
                          width: 0.8,
                        ),
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
                              boxShadow: [
                                BoxShadow(
                                  color: Color(0xFF00E5FF),
                                  blurRadius: 6,
                                  spreadRadius: 1,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            widget.foldable.posture.name.toUpperCase(),
                            style: const TextStyle(
                              color: Color(0xFF00E5FF),
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.2,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),
          ],
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
