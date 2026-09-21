import 'dart:async';
import 'dart:ui';

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
import 'ui/widgets/comet_search_surface.dart';
import 'ui/widgets/ambient_wallpaper_sheet.dart';
import 'core/search_coordinator.dart';
import 'core/search_providers/fixture_search_provider.dart';
import 'ui/widgets/app_action_dialog.dart';
import 'ui/widgets/constellation_editor_modal.dart';
import 'ui/widgets/create_constellation_modal.dart';
import 'core/galaxy_storage_service.dart';
import 'features/lockscreen/cosmic_lock_screen.dart';
import 'ui/screens/folded_cover_screen.dart';
import 'ui/screens/tabletop_cockpit_view.dart';
import 'ui/theme/luminous_home_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
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
      theme: LuminousHomeTheme.buildTheme(),
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
  late final SearchCoordinator _searchCoordinator;

  List<AppEntry> _apps = [];
  bool _isLoading = true;
  bool _isSearchOpen = false;
  bool _isLocked = false;
  bool _isCockpitMode = false;

  /// Whether ColorOS owns the lock screen instead of ChronoFold's Cosmic
  /// surface.
  ///
  /// Fresh and legacy installs default to Cosmic so screen-off events mount
  /// the launcher lock screen. A persisted explicit Native selection overrides
  /// this default in [_loadApplications]. Authentication still delegates to the
  /// platform keyguard before the Cosmic surface reveals or launches anything.
  bool _nativeMode = false;
  bool _isDefaultLauncher = true;

  /// Whether the comet web-search surface is up, and the query it was opened
  /// with when escalated from an app-search miss.
  bool _isCometSearchOpen = false;
  String? _cometInitialQuery;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _foldable = FoldableController();
    _camera = CameraController();
    _layoutEngine = GalaxyLayoutEngine();
    // Fixture-backed for now. Registering an HTTP provider here is the only
    // change needed to make inline answers live; the surface is provider-blind.
    _searchCoordinator = SearchCoordinator(
      providers: [FixtureSearchProvider()],
    );

    LauncherBridge.setScreenLockListener(_lockForScreenOff);
    _checkDefaultLauncherStatus();

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
        if (_isCometSearchOpen) {
          setState(() => _isCometSearchOpen = false);
          // Clear the previous answer too: the home button means "start over",
          // so reopening must not show a stale result.
          _searchCoordinator.reset();
        }
        _camera.resetView();
      }
    });

    _loadApplications();
  }

  Future<void> _checkDefaultLauncherStatus() async {
    final isDefault = await LauncherBridge.isDefaultLauncher();
    if (mounted) {
      setState(() => _isDefaultLauncher = isDefault);
    }
  }

  Future<void> _requestDefaultLauncher() async {
    await LauncherBridge.requestDefaultLauncher();
    await _checkDefaultLauncherStatus();
  }

  /// Keeps the first preview inside ChronoFold. ColorOS's own wallpaper
  /// chooser is intentionally a second, explicit step: it may then display an
  /// OEM lock-screen-shaped preview, not a ChronoFold keyguard.
  Future<void> _openCosmicLiveWallpaperPreview() async {
    final shouldOpenSystemPreview = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: const Color(0xC8020306),
      builder: (sheetContext) {
        return AmbientWallpaperSheet(
          onOpenSystemPreview: () => Navigator.of(sheetContext).pop(true),
        );
      },
    );

    if (!mounted || shouldOpenSystemPreview != true) return;
    final opened = await LauncherBridge.openCosmicLiveWallpaperPreview();
    if (!mounted || opened) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'ColorOS wallpaper chooser is unavailable on this device.',
        ),
      ),
    );
  }

  Future<void> _toggleNativeMode() async {
    final newMode = !_nativeMode;
    setState(() {
      _nativeMode = newMode;
      if (_nativeMode) {
        _isLocked = false;
      }
    });
    await LauncherBridge.setLockScreenOverlayEnabled(!_nativeMode);
    await GalaxyStorageService.saveConfig(
      coreAppPackageNames: _layoutEngine.corePackageNames,
      customConstellations: _layoutEngine.customConstellations,
      constellationAppOverrides: _layoutEngine.constellationAppOverrides,
      hiddenPackageNames: _layoutEngine.hiddenPackageNames,
      nativeLauncherMode: _nativeMode,
    );
  }

  /// Opens the comet surface, optionally seeded with a query the user already
  /// typed in app search, so escalating never costs them a retype.
  void _openCometSearch([String? query]) {
    setState(() {
      _isSearchOpen = false;
      _cometInitialQuery = query;
      _isCometSearchOpen = true;
    });
  }

  void _closeCometSearch() {
    setState(() => _isCometSearchOpen = false);
    _searchCoordinator.reset();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkDefaultLauncherStatus();
      if (mounted) {
        // Force a new root frame, then tell Android it is safe to remove the
        // native return bridge. The bridge hides with a short fade, so Flutter
        // is already visibly presenting the launcher beneath it.
        setState(() {});
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            unawaited(LauncherBridge.notifyLauncherFrameReady());
          }
        });
      }
    }
    // In Native Launcher Mode, switching or opening apps never locks the launcher.
  }

  /// Raises the cover-screen lock when the panel goes off.
  ///
  /// In Native Mode, ColorOS manages the lock screen directly.
  ///
  /// Only a screen-off that happens on the launcher gets here. The native side
  /// drops the event while an app the launcher opened still owns the screen,
  /// because answering it there raised this lock surface and re-asserted
  /// `showWhenLocked` behind that app — so closing it returned to a
  /// keyguard-occluding launcher with a lock panel already mounted, and the next
  /// touch went to the platform's fingerprint bouncer. That decision is made in
  /// MainActivity rather than here because Flutter's lifecycle state and the
  /// SCREEN_OFF broadcast race, and guessing wrong in this direction would mean
  /// no lock screen at all.
  void _lockForScreenOff() {
    if (!mounted || _nativeMode) return;
    if (_isLocked) return;
    // Re-enable the native window flag only for a real screen-off event.
    // Successful lock-screen app launches disable it so their return exposes
    // the cover screen rather than reviving a fingerprint/keyguard overlay.
    unawaited(LauncherBridge.setLockScreenOverlayEnabled(true));
    setState(() => _isLocked = true);
  }

  Future<void> _loadApplications() async {
    final apps = await LauncherBridge.getInstalledApps();

    // Load persisted galaxy configuration
    final config = await GalaxyStorageService.loadConfig();
    if (config.isNotEmpty) {
      final customList =
          (config['customConstellations'] ?? config['customGalaxies']) as List?;
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
      if (config.containsKey('coreAppPackageNames') &&
          config['coreAppPackageNames'] is List) {
        final corePkgs = List<String>.from(
          config['coreAppPackageNames'] as List,
        );
        _layoutEngine.setCorePackageNames(corePkgs);
      }
      if (config.containsKey('constellationAppOverrides') &&
          config['constellationAppOverrides'] is Map) {
        final rawOverrides =
            config['constellationAppOverrides'] as Map<String, dynamic>;
        for (final entry in rawOverrides.entries) {
          if (entry.value is List) {
            _layoutEngine.constellationAppOverrides[entry.key] =
                List<String>.from(entry.value as List);
          }
        }
      }
      if (config.containsKey('hiddenPackageNames') &&
          config['hiddenPackageNames'] is List) {
        final hiddenPkgs = List<String>.from(
          config['hiddenPackageNames'] as List,
        );
        _layoutEngine.setHiddenPackageNames(hiddenPkgs);
      }
      _nativeMode = config['nativeLauncherMode'] as bool? ?? false;
    }

    // Pushed unconditionally, including on a first run with no stored config.
    // Previously this lived inside the `config.isNotEmpty` branch, so a fresh
    // install never told the platform anything and the overlay state was
    // whatever the activity happened to start with.
    await LauncherBridge.setLockScreenOverlayEnabled(!_nativeMode);

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
            scale: Tween<double>(
              begin: 0.85,
              end: 1.0,
            ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutBack)),
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
            scale: Tween<double>(
              begin: 0.9,
              end: 1.0,
            ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutBack)),
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
            scale: Tween<double>(
              begin: 0.9,
              end: 1.0,
            ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutBack)),
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
    _searchCoordinator.dispose();
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
                      //
                      // The lock panel and both search surfaces cover this
                      // content completely, so its tickers are muted until it is
                      // visible again — an invisible 120Hz starfield behind an
                      // opaque overlay is pure battery cost, and freezing it also
                      // stops the search blur from re-filtering a moving
                      // background every frame.
                      TickerMode(
                        enabled:
                            !(_isLocked || _isSearchOpen || _isCometSearchOpen),
                        child: AnimatedSwitcher(
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
                                  onOpenSearch: () =>
                                      setState(() => _isSearchOpen = true),
                                  onOpenSettings: () =>
                                      LauncherBridge.openHomeSettings(),
                                  onLock: () =>
                                      setState(() => _isLocked = true),
                                  onAppLongPressed: _openAppLongPressDialog,
                                  onConstellationLongPressed:
                                      _openConstellationEditorModal,
                                  onCreateConstellation:
                                      _openCreateConstellationModal,
                                  onEditCore:
                                      _openCenterConstellationEditorModal,
                                )
                              : (_isCockpitMode && _foldable.isTabletop)
                              ? TabletopCockpitView(
                                  key: const ValueKey('tabletop_cockpit_view'),
                                  apps: _apps,
                                  foldable: _foldable,
                                  camera: _camera,
                                  layoutEngine: _layoutEngine,
                                  onOpenSearch: () =>
                                      setState(() => _isSearchOpen = true),
                                  onOpenSettings: () =>
                                      LauncherBridge.openHomeSettings(),
                                  onLock: () =>
                                      setState(() => _isLocked = true),
                                  onAppLongPressed: _openAppLongPressDialog,
                                  onConstellationLongPressed:
                                      _openConstellationEditorModal,
                                  onCreateConstellation:
                                      _openCreateConstellationModal,
                                  onEditCore:
                                      _openCenterConstellationEditorModal,
                                  onToggleFullscreen: () =>
                                      setState(() => _isCockpitMode = false),
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
                                        onAppLongPressed:
                                            _openAppLongPressDialog,
                                        onConstellationLongPressed:
                                            _openConstellationEditorModal,
                                        onSwipeDown: () => setState(
                                          () => _isSearchOpen = true,
                                        ),
                                      ),
                                    ),

                                    // 2. Cosmic HUD Header (Clock, Date & Posture Telemetry)
                                    Positioned(
                                      top: 0,
                                      left: 0,
                                      right: 0,
                                      child: CosmicHeaderHud(
                                        foldable: _foldable,
                                        isDefaultLauncher: _isDefaultLauncher,
                                        onSetDefaultLauncher:
                                            _requestDefaultLauncher,
                                        onOpenLiveWallpaper: () {
                                          unawaited(
                                            _openCosmicLiveWallpaperPreview(),
                                          );
                                        },
                                        nativeMode: _nativeMode,
                                        onToggleNativeMode: _toggleNativeMode,
                                        onLockScreen: () =>
                                            setState(() => _isLocked = true),
                                        onToggleCockpit: _foldable.isTabletop
                                            ? () => setState(
                                                () => _isCockpitMode = true,
                                              )
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
                                        onOpenSearch: () => setState(
                                          () => _isSearchOpen = true,
                                        ),
                                        onOpenWebSearch: () =>
                                            _openCometSearch(),
                                        onOpenSettings: () =>
                                            LauncherBridge.openHomeSettings(),
                                        onLock: () =>
                                            setState(() => _isLocked = true),
                                        onCreateConstellation:
                                            _openCreateConstellationModal,
                                        onEditCore:
                                            _openCenterConstellationEditorModal,
                                      ),
                                    ),
                                  ],
                                ),
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
                            onClose: () =>
                                setState(() => _isSearchOpen = false),
                            onOpenSettings: () =>
                                LauncherBridge.openHomeSettings(),
                            onSearchWeb: _openCometSearch,
                          ),
                        ),

                      // Comet Web Search Surface
                      if (_isCometSearchOpen)
                        Positioned.fill(
                          child: CometSearchSurface(
                            key: ValueKey('comet_${_cometInitialQuery ?? ''}'),
                            coordinator: _searchCoordinator,
                            initialQuery: _cometInitialQuery,
                            onClose: _closeCometSearch,
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
  final bool isDefaultLauncher;
  final VoidCallback? onSetDefaultLauncher;
  final VoidCallback? onOpenLiveWallpaper;
  final bool nativeMode;
  final VoidCallback? onToggleNativeMode;
  final VoidCallback? onLockScreen;

  const CosmicHeaderHud({
    super.key,
    required this.foldable,
    this.onToggleCockpit,
    this.isDefaultLauncher = true,
    this.onSetDefaultLauncher,
    this.onOpenLiveWallpaper,
    this.nativeMode = false,
    this.onToggleNativeMode,
    this.onLockScreen,
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
        padding: const EdgeInsets.symmetric(
          horizontal: LuminousHomeTheme.screenGutter,
          vertical: 8,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  timeString,
                  style: Theme.of(context).textTheme.displayLarge,
                ),
                const SizedBox(height: 4),
                Text(
                  dateString,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: LuminousHomeTheme.textSecondary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            const SizedBox(width: 14),

            // Compact utility shelf; it scrolls instead of competing with time.
            Flexible(
              child: Align(
                alignment: Alignment.topRight,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(
                      LuminousHomeTheme.controlRadius + 10,
                    ),
                    boxShadow: LuminousHomeTheme.floatingShadow,
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(
                      LuminousHomeTheme.controlRadius + 10,
                    ),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(
                        sigmaX: LuminousHomeTheme.glassBlur,
                        sigmaY: LuminousHomeTheme.glassBlur,
                      ),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              LuminousHomeTheme.glassStrong,
                              LuminousHomeTheme.glass,
                            ],
                          ),
                          borderRadius: BorderRadius.circular(
                            LuminousHomeTheme.controlRadius + 10,
                          ),
                          border: Border.all(color: LuminousHomeTheme.hairline),
                        ),
                        child: SizedBox(
                          height: 56,
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            reverse: true,
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (!widget.isDefaultLauncher &&
                                    widget.onSetDefaultLauncher != null)
                                  _utilityButton(
                                    icon: Icons.home_rounded,
                                    label: 'SET DEFAULT',
                                    tooltip: 'Set as default launcher',
                                    color: LuminousHomeTheme.aqua,
                                    emphasized: true,
                                    onTap: widget.onSetDefaultLauncher!,
                                  ),
                                if (widget.onOpenLiveWallpaper != null)
                                  _utilityButton(
                                    icon: Icons.wallpaper_rounded,
                                    label: 'AMBIENT',
                                    tooltip: 'Choose ambient wallpaper',
                                    color: LuminousHomeTheme.aqua,
                                    onTap: widget.onOpenLiveWallpaper!,
                                  ),
                                if (widget.onToggleNativeMode != null)
                                  _utilityButton(
                                    icon: widget.nativeMode
                                        ? Icons.shield_outlined
                                        : Icons.lock_outline_rounded,
                                    label: widget.nativeMode
                                        ? 'NATIVE'
                                        : 'COSMIC',
                                    tooltip: widget.nativeMode
                                        ? 'Use Cosmic lock screen'
                                        : 'Use native lock screen',
                                    color: widget.nativeMode
                                        ? LuminousHomeTheme.mint
                                        : LuminousHomeTheme.orchid,
                                    emphasized: true,
                                    onTap: widget.onToggleNativeMode!,
                                  ),
                                if (!widget.nativeMode &&
                                    widget.onLockScreen != null)
                                  _utilityButton(
                                    icon: Icons.lock_rounded,
                                    label: 'LOCK',
                                    tooltip: 'Lock now',
                                    color: LuminousHomeTheme.orchid,
                                    onTap: widget.onLockScreen!,
                                  ),
                                if (widget.onToggleCockpit != null)
                                  _utilityButton(
                                    icon: Icons.splitscreen_rounded,
                                    label: 'COCKPIT',
                                    tooltip: 'Open tabletop cockpit',
                                    color: LuminousHomeTheme.aqua,
                                    onTap: widget.onToggleCockpit!,
                                  ),
                                const SizedBox(
                                  height: 24,
                                  child: VerticalDivider(
                                    width: 10,
                                    thickness: 1,
                                    color: LuminousHomeTheme.hairline,
                                  ),
                                ),
                                ListenableBuilder(
                                  listenable: widget.foldable,
                                  builder: (context, _) {
                                    return _postureStatus(
                                      widget.foldable.posture.name,
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _utilityButton({
    required IconData icon,
    required String label,
    required String tooltip,
    required Color color,
    required VoidCallback onTap,
    bool emphasized = false,
  }) {
    final radius = BorderRadius.circular(LuminousHomeTheme.iconRadius);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 1),
      child: Semantics(
        button: true,
        label: tooltip,
        child: Tooltip(
          message: tooltip,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minWidth: LuminousHomeTheme.minimumTouchTarget,
              minHeight: LuminousHomeTheme.minimumTouchTarget,
            ),
            child: Material(
              color: emphasized
                  ? LuminousHomeTheme.softTint(color, 0.18)
                  : Colors.transparent,
              borderRadius: radius,
              child: InkWell(
                onTap: onTap,
                borderRadius: radius,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ExcludeSemantics(
                        child: Icon(icon, color: color, size: 19),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        label,
                        style: const TextStyle(
                          color: LuminousHomeTheme.textSecondary,
                          fontSize: 9.5,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.35,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _postureStatus(String postureName) {
    final label = postureName.isEmpty
        ? postureName
        : '${postureName[0].toUpperCase()}${postureName.substring(1)}';
    return Semantics(
      label: 'Device posture: $label',
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minHeight: LuminousHomeTheme.minimumTouchTarget,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.screen_rotation_rounded,
                color: LuminousHomeTheme.textMuted,
                size: 16,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  color: LuminousHomeTheme.textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
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
