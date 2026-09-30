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
import 'ui/format/clock_format.dart';
import 'ui/screens/folded_cover_screen.dart';
import 'ui/screens/tabletop_cockpit_view.dart';
import 'ui/theme/luminous_home_theme.dart';
import 'ui/theme/system_palette.dart';

// The lock activity runs its own engine on the `lockMain` entry point, which
// lives in its own library. Re-exporting it keeps that entry point in this
// kernel, so AOT tree-shaking cannot drop the second surface's entry point.
export 'lock_main.dart' show lockMain;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  // The accent has to be settled before the first frame, or the launcher would
  // flash aqua and then re-colour. The timeout is a fail-safe for a platform
  // that never answers, not the normal path.
  final SystemPalette? palette = await LauncherBridge.getSystemPalette()
      .timeout(const Duration(milliseconds: 300), onTimeout: () => null);
  LuminousHomeTheme.applyPalette(palette);

  runApp(const ChronoFoldApp());
}

class ChronoFoldApp extends StatelessWidget {
  /// Passes [ChronoFoldHomeScreen.isKeyguardLocked] through. Null in
  /// production, where the home screen asks the bridge itself.
  final Future<bool> Function()? isKeyguardLocked;

  const ChronoFoldApp({super.key, this.isKeyguardLocked});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<SystemPalette?>(
      stream: LauncherBridge.systemPaletteChanges,
      builder: (context, snapshot) {
        // Only an actual push re-applies: before the first event the palette
        // [main] already applied must survive, and a null event means the
        // platform withdrew its palette and aqua should come back.
        if (snapshot.connectionState == ConnectionState.active) {
          LuminousHomeTheme.applyPalette(snapshot.data);
        }
        return MaterialApp(
          key: ValueKey<int>(LuminousHomeTheme.paletteRevision),
          title: 'ChronoFold Launcher',
          debugShowCheckedModeBanner: false,
          theme: LuminousHomeTheme.buildTheme(),
          home: ChronoFoldHomeScreen(isKeyguardLocked: isKeyguardLocked),
        );
      },
    );
  }
}

class ChronoFoldHomeScreen extends StatefulWidget {
  /// Stands in for the platform's keyguard state at cold start — the same
  /// seam [CosmicLockScreen] injects for its own keyguard question. Null in
  /// production, where the cold-start check in `_loadApplications` goes to
  /// the bridge. Injectable because the test host has no keyguard and its
  /// bridge answers "locked" by default, so this is the only way a widget
  /// test can express an unlocked device — which the posture tests need,
  /// since a mounted lock panel mutes the tickers that retire the outgoing
  /// posture child.
  final Future<bool> Function()? isKeyguardLocked;

  const ChronoFoldHomeScreen({super.key, this.isKeyguardLocked});

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

  /// Whether the lock panel about to mount was raised by an explicit user
  /// action — the LOCK buttons — rather than by a screen-off or a cold
  /// start over a locked keyguard.
  ///
  /// Read once per mount, when the panel below is constructed. It decides
  /// `reconcileOnMount`: a panel mounted for a lock the platform may have
  /// already satisfied clears itself at its first frame rather than
  /// ghosting, while the privacy lock the user asked for stays up on an
  /// unlocked device.
  bool _lockMountedByUserAction = false;
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
      barrierColor: LuminousHomeTheme.lockScrim,
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
  /// The native side drops only a screen-off that happens inside an app the
  /// launcher itself launched (the handoff latch). Everything else —
  /// including a screen-off behind an app opened from a notification or
  /// recents, which never sets that latch — reaches here, because the
  /// alternative was to guess from lifecycle state whether the launcher or
  /// something else was showing, and on the CPH2765 `onPause` precedes the
  /// SCREEN_OFF broadcast even on the launcher's own surface, so that guess
  /// dropped lock-from-home entirely. The ghost panel those drops were
  /// meant to prevent is closed at the other end instead: a panel mounted
  /// here reconciles against the keyguard once it can actually draw (see
  /// `reconcileOnMount` on the panel), so it appears only for a lock that
  /// still exists.
  void _lockForScreenOff() {
    if (!mounted || _nativeMode) return;
    // Re-assert the window flag BEFORE the early-out rather than after it.
    // The flag is cleared by every lock-screen app launch, so a screen-off
    // that landed on a panel mounted by the lock buttons used to skip this
    // push entirely and the wake showed the ColorOS keyguard instead of the
    // cosmic panel: the same physical action produced a different lock
    // surface depending on launch history. Pushing first keeps the
    // invariant — panel mounted ⟺ overlay enabled — in Cosmic mode.
    unawaited(LauncherBridge.setLockScreenOverlayEnabled(true));
    if (_isLocked) {
      debugPrint('CF_LOCK: screen-off with panel already up');
      return;
    }
    debugPrint('CF_LOCK: overlay re-asserted for screen-off lock');
    _lockMountedByUserAction = false;
    setState(() => _isLocked = true);
  }

  /// Mounts the lock panel for an explicit user action (the LOCK buttons).
  ///
  /// The four lock buttons used to mount the panel inline without pushing the
  /// overlay flag, so whether the wake after them showed the cosmic panel or
  /// the ColorOS keyguard depended on whether any earlier app launch had
  /// cleared the flag. Single-sourcing the two here makes the invariant above
  /// hold for manual locks too. Native mode keeps delegating the whole lock
  /// surface to ColorOS, so the push is skipped there — the button still
  /// mounts the panel exactly as it did before.
  ///
  /// This is also the one mount that is deliberately exempt from keyguard
  /// reconciliation: the user asked for this surface on a device that may
  /// well be unlocked, and it stays up until they dismiss it.
  void _mountLockPanel() {
    if (!mounted) return;
    if (!_nativeMode) {
      unawaited(LauncherBridge.setLockScreenOverlayEnabled(true));
      debugPrint('CF_LOCK: panel mounted by user action');
    }
    _lockMountedByUserAction = true;
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

    // Never start cold over a locked keyguard. Pushing the overlay flag here
    // unconditionally is what used to expose the *home* surface — the whole
    // app inventory, search and the layout editors — over a locked device,
    // because `_isLocked` starts false and nothing checked the keyguard
    // (report Path D). Mounting the lock panel instead, without the overlay
    // push, leaves the keyguard in front (the activity starts with the flag
    // cleared), and the panel's own `userPresent` listener clears it the
    // moment the platform authenticates. Native mode keeps today's behaviour
    // — no overlay, ColorOS owns the whole surface. The injected seam stands
    // in for the platform here; null means the bridge, i.e. production.
    if (!_nativeMode &&
        await (widget.isKeyguardLocked ?? LauncherBridge.isKeyguardLocked)()) {
      debugPrint(
        'CF_LOCK: cold start with keyguard locked; mounting lock surface',
      );
      // Not a user action: this panel stands for the keyguard, so it
      // reconciles like a screen-off mount in case the platform satisfies
      // the lock before the launcher ever draws.
      _lockMountedByUserAction = false;
      if (mounted) {
        setState(() => _isLocked = true);
      }
    } else {
      // Pushed unconditionally on the normal (unlocked) path, including on a
      // first run with no stored config. Previously this lived inside the
      // `config.isNotEmpty` branch, so a fresh install never told the
      // platform anything and the overlay state was whatever the activity
      // happened to start with.
      await LauncherBridge.setLockScreenOverlayEnabled(!_nativeMode);
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
            ? Center(
                child: CircularProgressIndicator(
                  color: LuminousHomeTheme.accent,
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
                                  onLock: _mountLockPanel,
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
                                  onLock: _mountLockPanel,
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
                                        onLockScreen: _mountLockPanel,
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
                                        onLock: _mountLockPanel,
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
                            // Not raised by the LOCK buttons → the mount is
                            // for a lock the platform may have satisfied
                            // before this panel could draw (screen-off
                            // behind a foreign app, or a cold start raced by
                            // an unlock). The panel checks the keyguard at
                            // its first frame and clears itself if the lock
                            // is gone; the user-raised privacy lock is
                            // exempt and stays up.
                            reconcileOnMount: !_lockMountedByUserAction,
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
      // The HUD renders hours and minutes only, so it repaints when the
      // visible minute rolls over rather than once a second — the other
      // three clock surfaces already gate this way. An ungated timer kept
      // rebuilding the whole HUD subtree every second, including the whole
      // time the launcher sat paused behind another app.
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // The shared helper follows the platform's own 12/24-hour setting so this
    // clock cannot disagree with the ColorOS status bar on the same screen.
    final timeString = formatClockTime(context, _now);
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
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // The clock became width-variable when it started
                  // following the platform's 12/24-hour setting, and a
                  // 12-hour reading ("7:05 PM") is wider than the old
                  // "19:05" at the same font size — on cover/N6 widths the
                  // inflexible clock pushed this row past the utility
                  // shelf's share. The column yields — the shelf already
                  // flexes and scrolls — and the reading scales down to the
                  // share it is given rather than overflowing the header.
                  // The date line is short; it stays as it is.
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      timeString,
                      style: Theme.of(context).textTheme.displayLarge,
                    ),
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
                                    color: LuminousHomeTheme.accent,
                                    emphasized: true,
                                    onTap: widget.onSetDefaultLauncher!,
                                  ),
                                if (widget.onOpenLiveWallpaper != null)
                                  _utilityButton(
                                    icon: Icons.wallpaper_rounded,
                                    label: 'AMBIENT',
                                    tooltip: 'Choose ambient wallpaper',
                                    color: LuminousHomeTheme.accent,
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
                                    color: LuminousHomeTheme.accent,
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
