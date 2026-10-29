import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'models/app_entry.dart';
import 'models/constellation.dart';
import 'core/badge_controller.dart';
import 'core/launcher_bridge.dart';
import 'core/foldable_controller.dart';
import 'core/galaxy_layout_engine.dart';
import 'canvas/camera_controller.dart';
import 'canvas/galaxy_interactive_canvas.dart';
import 'ui/widgets/foldable_cockpit_bar.dart';
import 'ui/widgets/search_overlay.dart';
import 'ui/widgets/comet_search_surface.dart';
import 'ui/widgets/ambient_wallpaper_sheet.dart';
import 'ui/widgets/wallpaper_scrim.dart';
import 'ui/theme/wallpaper_tone.dart';
import 'core/search_coordinator.dart';
import 'core/search_providers/fixture_search_provider.dart';
import 'core/system_gestures.dart';
import 'ui/widgets/app_action_dialog.dart';
import 'ui/widgets/native_panel_transition.dart';
import 'ui/widgets/constellation_editor_modal.dart';
import 'ui/widgets/create_constellation_modal.dart';
import 'ui/widgets/gestures_sheet.dart';
import 'ui/widgets/first_run_hint_card.dart';
import 'ui/widgets/launcher_settings_sheet.dart';
import 'core/galaxy_storage_service.dart';
import 'features/lockscreen/cosmic_lock_screen.dart';
import 'features/shopping/parsing/document_parser.dart';
import 'features/shopping/parsing/pdf_text_import.dart';
import 'features/shopping/shopping_controller.dart';
import 'features/shopping/ui/grocery_chrome.dart';
import 'features/shopping/ui/menu_kit_sheet.dart';
import 'features/shopping/ui/shopping_surface.dart';
import 'ui/format/clock_format.dart';
import 'ui/screens/folded_cover_screen.dart';
import 'ui/screens/tabletop_cockpit_view.dart';
import 'ui/theme/luminous_home_theme.dart';
import 'ui/theme/system_palette.dart';

import 'lock_main.dart' as lock_surface;

/// The lock activity's engine entry point, declared in the root library.
///
/// `LockActivity` names `lockMain` and leaves the library to the engine's
/// default, the root library — this file. An AOT release build resolves an
/// entry point only as a real, `vm:entry-point`-annotated function of the
/// library it is asked to search: a re-export is not one, and looking it up
/// in `lock_main.dart` by URI was measured to fail too on the CPH2765
/// ("Could not resolve main entrypoint function"), so the lock engine never
/// ran Dart, never drew, and the first-frame watchdog handed every
/// screen-off over another app (YouTube playing, say) to the ColorOS
/// keyguard. A real function here is the documented custom-entrypoint shape.
@pragma('vm:entry-point')
Future<void> lockMain() => lock_surface.lockMain();

/// The transparent, edge-to-edge system chrome, with its icons dark or light.
///
/// The home screen picks [darkIcons] from the wallpaper's own colour verdict
/// (`WallpaperTone.isLight`), the way ColorOS flips its status bar on a light
/// wallpaper, and goes back to light icons under a dark scrim or the lock
/// panel. Exposed so tests can check the choice.
SystemUiOverlayStyle homeOverlayStyle({required bool darkIcons}) {
  final Brightness icons = darkIcons ? Brightness.dark : Brightness.light;
  return SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: icons,
    statusBarBrightness: darkIcons ? Brightness.light : Brightness.dark,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarIconBrightness: icons,
    systemNavigationBarContrastEnforced: false,
  );
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(homeOverlayStyle(darkIcons: false));
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

  /// Pass-through seams for [ChronoFoldHomeScreen]. Null in production.
  final Future<String?> Function()? takePendingSharedPdf;
  final Future<PdfTextResult> Function(String path)? extractPdfText;
  final Future<String?> Function()? pickPdf;

  /// The notification-badge stream. Null in production, where the platform
  /// channel is used; injectable so a test can drive badge changes.
  final Stream<Map<String, dynamic>>? badgesStream;

  /// Test seams for the two gesture preferences. Null in production, where they
  /// are read from `galaxy_settings.json`; a widget test states them directly
  /// rather than standing in for the settings file.
  final bool? doubleTapToSleep;
  final String? swipeDownAction;

  /// Test seam for the persisted first-run hint flag. Null in production.
  final bool? firstRunHintDismissed;

  const ChronoFoldApp({
    super.key,
    this.isKeyguardLocked,
    this.takePendingSharedPdf,
    this.extractPdfText,
    this.pickPdf,
    this.badgesStream,
    this.doubleTapToSleep,
    this.swipeDownAction,
    this.firstRunHintDismissed,
  });

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
          home: ChronoFoldHomeScreen(
            isKeyguardLocked: isKeyguardLocked,
            takePendingSharedPdf: takePendingSharedPdf,
            extractPdfText: extractPdfText,
            pickPdf: pickPdf,
            badgesStream: badgesStream,
            doubleTapToSleep: doubleTapToSleep,
            swipeDownAction: swipeDownAction,
            firstRunHintDismissed: firstRunHintDismissed,
          ),
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

  /// Injection seams for the PDF import path. Null in production, where the
  /// bridge is used; a widget test stands in for the platform channel here.
  final Future<String?> Function()? takePendingSharedPdf;
  final Future<PdfTextResult> Function(String path)? extractPdfText;
  final Future<String?> Function()? pickPdf;

  /// The notification-badge stream. Null in production; injectable for tests.
  final Stream<Map<String, dynamic>>? badgesStream;

  /// Test seams for the two persisted gesture preferences. Null in production.
  final bool? doubleTapToSleep;
  final String? swipeDownAction;

  /// Test seam for the persisted first-run hint flag. Null in production.
  final bool? firstRunHintDismissed;

  const ChronoFoldHomeScreen({
    super.key,
    this.isKeyguardLocked,
    this.takePendingSharedPdf,
    this.extractPdfText,
    this.pickPdf,
    this.badgesStream,
    this.doubleTapToSleep,
    this.swipeDownAction,
    this.firstRunHintDismissed,
  });

  @override
  State<ChronoFoldHomeScreen> createState() => _ChronoFoldHomeScreenState();
}

class _ChronoFoldHomeScreenState extends State<ChronoFoldHomeScreen>
    with WidgetsBindingObserver {
  late final FoldableController _foldable;
  late final CameraController _camera;
  late final GalaxyLayoutEngine _layoutEngine;
  late final SearchCoordinator _searchCoordinator;

  /// The per-package notification counts behind the app badges.
  late final BadgeController _badgeController;

  /// Bumped whenever the counts change, so the galaxy canvas repaints its
  /// badges even while the ticker is resting under "remove animations".
  int _badgeRevision = 0;

  List<AppEntry> _apps = [];
  bool _isLoading = true;
  bool _isSearchOpen = false;
  bool _isLocked = false;

  bool _isCockpitMode = false;

  /// The platform's verdict on the system wallpaper's colours, or null until
  /// it has answered (and on hosts with no wallpaper). Decides the chrome
  /// icon brightness and the strength of the home scrims.
  WallpaperTone? _wallpaperTone;
  StreamSubscription<WallpaperTone?>? _wallpaperToneSubscription;

  /// What the status and navigation bar icons were last set to, so a rebuild
  /// only touches the platform when the choice changes.
  bool? _darkChromeIcons;

  /// Whether the wallpaper is currently blurred behind the window.
  bool _windowBlurOn = false;

  /// Wallpaper-offset reporting, coalesced to one report per frame.
  bool _wallpaperOffsetScheduled = false;
  Offset? _lastWallpaperOffset;

  /// How far the wallpaper travels across the galaxy's full pan range: a
  /// quarter of its own width, so it moves a little slower than the field in
  /// front of it, the way a paged home's wallpaper lags its pages.
  static const double _wallpaperParallax = 0.25;

  /// Whether ColorOS owns the lock screen instead of ChronoFold's Cosmic
  /// surface.
  ///
  /// Fresh and legacy installs default to Cosmic so screen-off events mount
  /// the launcher lock screen. A persisted explicit Native selection overrides
  /// this default in [_loadApplications]. Authentication still delegates to the
  /// platform keyguard before the Cosmic surface reveals or launches anything.
  bool _nativeMode = false;

  /// Whether ChronoFold holds Android's HOME role. A notifier so the Settings
  /// sheet, which stays open across a trip to Android's picker, sees the
  /// answer the resume re-check brings back.
  final ValueNotifier<bool> _defaultLauncher = ValueNotifier<bool>(true);
  bool get _isDefaultLauncher => _defaultLauncher.value;

  /// Whether the one-time "Getting started" card has been dismissed. Read from
  /// `galaxy_settings.json` on the first load; a file written before the card
  /// existed has no key, which reads as "not yet".
  bool _firstRunHintDismissed = false;

  /// The two persisted gesture preferences.
  ///
  /// Both default to today's behaviour: no sleep-on-double-tap, and a swipe down
  /// opens search. They only take effect through the optional accessibility
  /// service, which is off until the user enables it.
  bool _doubleTapToSleep = false;
  String _swipeDownAction = SwipeDownAction.search;

  /// Whether the comet web-search surface is up, and the query it was opened
  /// with when escalated from an app-search miss.
  bool _isCometSearchOpen = false;
  String? _cometInitialQuery;

  /// Whether the shopping surface is up. It owns the persisted lists, which are
  /// loaded once and saved through the controller's debounced store.
  late final ShoppingController _shoppingController;
  bool _isShoppingOpen = false;

  /// A shared PDF that arrived while the lock panel was up. It is held here and
  /// imported only after the panel clears, so the review sheet is never drawn
  /// over a locked surface.
  String? _pendingSharedPdfPath;

  /// Whether the startup pull of a native pending share has run. Set before the
  /// await so a package-change reload cannot pull it twice.
  bool _pendingSharedPdfChecked = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _foldable = FoldableController();
    _camera = CameraController();
    _layoutEngine = GalaxyLayoutEngine();
    // No live inline provider exists yet. Registering an HTTP provider here is
    // the only change needed to make inline answers live; the surface is
    // provider-blind. The fixture is debug-only: a release build must never
    // stream canned "answers" to a real user, so there the coordinator runs
    // handoff-only and the surface offers the native web-search handoff.
    _searchCoordinator = SearchCoordinator(
      providers: [if (kDebugMode) FixtureSearchProvider()],
    );
    _shoppingController = ShoppingController();
    unawaited(_shoppingController.load());

    _badgeController = BadgeController(stream: widget.badgesStream);
    _badgeController.addListener(_onBadgeCountsChanged);

    LauncherBridge.setScreenLockListener(_lockForScreenOff);
    LauncherBridge.setSharedPdfListener((String path) {
      if (mounted) {
        unawaited(_onSharedPdf(path));
      }
    });
    _checkDefaultLauncherStatus();

    LauncherBridge.setPackageChangeListener(() {
      if (mounted) {
        _loadApplications();
      }
    });

    LauncherBridge.setHomeButtonListener(() {
      // While the lock panel is up, Home belongs to the keyguard: the surfaces
      // under the panel must stay exactly as the user left them.
      if (mounted && !_isLocked) {
        if (_isSearchOpen) {
          setState(() => _isSearchOpen = false);
        }
        if (_isCometSearchOpen) {
          setState(() => _isCometSearchOpen = false);
          // Clear the previous answer too: the home button means "start over",
          // so reopening must not show a stale result.
          _searchCoordinator.reset();
        }
        if (_isShoppingOpen) {
          setState(() => _isShoppingOpen = false);
        }
        _camera.resetView();
      }
    });

    _camera.addListener(_scheduleWallpaperOffsets);
    _foldable.addListener(_scheduleWallpaperOffsets);
    unawaited(_readWallpaperTone());
    _wallpaperToneSubscription =
        LauncherBridge.wallpaperToneChanges.listen(_applyWallpaperTone);

    _loadApplications();
  }

  /// Asks the platform what it knows about the wallpaper's colours.
  Future<void> _readWallpaperTone() async {
    final WallpaperTone? tone = await LauncherBridge.getWallpaperTone();
    if (mounted) _applyWallpaperTone(tone);
  }

  void _applyWallpaperTone(WallpaperTone? tone) {
    if (!mounted || tone == _wallpaperTone) return;
    setState(() => _wallpaperTone = tone);
  }

  /// Whether a surface that covers the whole home is up (search, the comet,
  /// shopping). The lock panel is tracked separately.
  bool get _fullScreenSurfaceUp =>
      _isSearchOpen || _isCometSearchOpen || _isShoppingOpen;

  /// Keeps the system chrome and the wallpaper blur in step with the screen.
  ///
  /// Called from [build], because every state that matters here is also what
  /// drives a rebuild; both platform calls are made only on a real change, so
  /// the common rebuild costs two comparisons. Icons go dark only over a
  /// light wallpaper with nothing drawn across it; a full-screen surface
  /// brings its own dark scrim and the lock panel its own field.
  void _syncWallpaperChrome() {
    final bool overlayUp = _fullScreenSurfaceUp;
    final bool darkIcons =
        (_wallpaperTone?.isLight ?? false) && !overlayUp && !_isLocked;
    if (_darkChromeIcons != darkIcons) {
      _darkChromeIcons = darkIcons;
      SystemChrome.setSystemUIOverlayStyle(
        homeOverlayStyle(darkIcons: darkIcons),
      );
    }
    final bool blur = overlayUp && !_isLocked;
    if (_windowBlurOn != blur) {
      _windowBlurOn = blur;
      unawaited(LauncherBridge.setWindowBlur(blur));
    }
  }

  /// Reports the camera's pan to the system wallpaper once per frame.
  void _scheduleWallpaperOffsets() {
    if (_wallpaperOffsetScheduled) return;
    _wallpaperOffsetScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _wallpaperOffsetScheduled = false;
      if (mounted) _reportWallpaperOffsets();
    });
  }

  void _reportWallpaperOffsets() {
    Offset target = const Offset(0.5, 0.5);
    if (!_foldable.isFolded) {
      final Offset pan = _camera.panFraction;
      target = Offset(
        0.5 - pan.dx * _wallpaperParallax,
        0.5 - pan.dy * _wallpaperParallax,
      );
    }
    final Offset? last = _lastWallpaperOffset;
    if (last != null && (last - target).distance < 0.002) return;
    _lastWallpaperOffset = target;
    unawaited(LauncherBridge.setWallpaperOffsets(target.dx, target.dy));
  }

  /// A new badge map arrived: fold it into the app entries and rebuild so every
  /// surface (galaxy, cover grid, tabletop, search) redraws its dots.
  void _onBadgeCountsChanged() {
    if (!mounted) return;
    setState(() {
      _badgeRevision++;
      _applyBadgeCounts(_apps);
    });
  }

  /// Copies the controller's per-package counts onto [apps].
  void _applyBadgeCounts(List<AppEntry> apps) {
    for (final app in apps) {
      app.notificationCount = _badgeController.countFor(app.packageName);
    }
  }

  Future<void> _checkDefaultLauncherStatus() async {
    final isDefault = await LauncherBridge.isDefaultLauncher();
    if (mounted) {
      setState(() => _defaultLauncher.value = isDefault);
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

  /// Switches the lock surface between Cosmic and ColorOS (native) and
  /// persists the choice. The Settings sheet confirms with the user first.
  Future<void> _setNativeMode(bool native) async {
    if (native == _nativeMode) return;
    setState(() {
      _nativeMode = native;
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

  /// The "Default home app" row: asks for the HOME role while ChronoFold does
  /// not hold it, and otherwise opens Android's default-home picker. This row
  /// is the only way into that system page.
  void _openDefaultHomeSetting() {
    if (_isDefaultLauncher) {
      unawaited(LauncherBridge.openHomeSettings());
    } else {
      unawaited(_requestDefaultLauncher());
    }
  }

  /// Opens ChronoFold's own Settings sheet, the target of every gear button.
  void _openSettings() {
    // Never over the lock panel: settings include the lock surface itself.
    if (_isLocked) return;
    unawaited(
      showLauncherSettingsSheet(
        context,
        isDefaultLauncher: _defaultLauncher,
        onDefaultHomeTap: _openDefaultHomeSetting,
        nativeLockMode: _nativeMode,
        onLockModeChanged: _setNativeMode,
        onOpenAmbientWallpaper: () =>
            unawaited(_openCosmicLiveWallpaperPreview()),
        onOpenGestures: () => unawaited(_openGesturesSheet()),
        hasMediaAccess: LauncherBridge.hasMediaAccess,
        isGalaxyWallpaperActive: LauncherBridge.isCosmicWallpaperActive,
        onRequestMediaAccess: () async {
          await LauncherBridge.requestMediaAccess();
        },
      ),
    );
  }

  /// Hides the first-run card for good. Same save path and queue as every
  /// other setting; only the new key is added to the merge.
  void _dismissFirstRunHint() {
    setState(() => _firstRunHintDismissed = true);
    unawaited(
      GalaxyStorageService.saveConfig(
        coreAppPackageNames: _layoutEngine.corePackageNames,
        customConstellations: _layoutEngine.customConstellations,
        constellationAppOverrides: _layoutEngine.constellationAppOverrides,
        hiddenPackageNames: _layoutEngine.hiddenPackageNames,
        firstRunHintDismissed: true,
      ),
    );
  }

  bool get _showFirstRunHint =>
      !_firstRunHintDismissed &&
      !_isLocked &&
      !_isSearchOpen &&
      !_isCometSearchOpen &&
      !_isShoppingOpen;

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

  /// Opens the shopping surface, closing the search surfaces beneath it so Back
  /// and the TickerMode mute stay ordered.
  void _openShopping() {
    setState(() {
      _isSearchOpen = false;
      _isCometSearchOpen = false;
      _isShoppingOpen = true;
    });
    _searchCoordinator.reset();
  }

  void _closeShopping() {
    setState(() => _isShoppingOpen = false);
  }

  /// Forces the shopping store's debounced save to disk now. Only once the
  /// store has loaded, so an early flush can never overwrite saved lists with
  /// the empty pre-load state.
  void _flushShopping() {
    if (_shoppingController.isLoaded) {
      unawaited(_shoppingController.flush());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _flushShopping();
    }
    if (state == AppLifecycleState.resumed) {
      _checkDefaultLauncherStatus();
      // The wallpaper may have changed while the user was away. The colour
      // listener covers a change during the session; this covers the gap.
      unawaited(_readWallpaperTone());
      // Another wallpaper target may have scrolled the wallpaper meanwhile;
      // re-report this window's position on the next frame.
      _lastWallpaperOffset = null;
      _scheduleWallpaperOffsets();
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
    if (!mounted) return;
    // Persist any pending shopping edit before the device sleeps, whichever
    // surface owns the lock.
    _flushShopping();
    if (_nativeMode) return;
    // Re-assert the window flag BEFORE the early-out rather than after it.
    // The flag is cleared by every lock-screen app launch, so a screen-off
    // that landed on a panel mounted by the lock buttons used to skip this
    // push entirely and the wake showed the ColorOS keyguard instead of the
    // cosmic panel: the same physical action produced a different lock
    // surface depending on launch history. Pushing first keeps the
    // invariant — panel mounted ⟺ overlay enabled — in Cosmic mode.
    unawaited(LauncherBridge.setLockScreenOverlayEnabled(true));
    // The shopping surface holds FLAG_KEEP_SCREEN_ON in store mode. Release it
    // directly: with the panel off, the frame that disposes the surface (and
    // releases the flag itself) may not run until the next wake.
    if (_isShoppingOpen) {
      unawaited(LauncherBridge.setKeepScreenOn(false));
    }
    if (_isLocked) {
      if (_isShoppingOpen) setState(() => _isShoppingOpen = false);
      debugPrint('CF_LOCK: screen-off with panel already up');
      return;
    }
    debugPrint('CF_LOCK: overlay re-asserted for screen-off lock');
    setState(() {
      _isLocked = true;
      _isShoppingOpen = false;
    });
  }

  /// Locks the device through the optional accessibility service.
  ///
  /// The LOCK buttons used to mount the in-app cosmic panel directly, which
  /// meant an explicit lock only ever raised the fingerprint reader over an
  /// unlocked device instead of turning the screen off. When the service is
  /// connected and accepts the action, the platform performs the real lock and
  /// the resulting screen-off broadcast mounts the panel through
  /// [_lockForScreenOff] in Cosmic mode, so there is nothing left to do here.
  /// Native mode delegates the whole lock surface to ColorOS, and the real
  /// screen-off is what it reacts to as well.
  ///
  /// Otherwise the lock cannot happen. The panel is deliberately not mounted:
  /// it would ask for a fingerprint over a device that was never locked. The
  /// user is pointed at the single grant that enables instant locking instead.
  Future<void> _lockDevice() async {
    if (await SystemGestures.isEnabled()) {
      final bool locked = await SystemGestures.lockScreen();
      if (locked) return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text(
          'Turn on ChronoFold in Accessibility to lock instantly',
        ),
        action: SnackBarAction(
          label: 'Enable',
          textColor: LuminousHomeTheme.accent,
          onPressed: () => unawaited(SystemGestures.openSettings()),
        ),
      ),
    );
  }

  /// Whether the sleep-on-double-tap gesture may fire right now.
  ///
  /// Never while the cosmic lock panel is mounted: re-locking a locked launcher
  /// is exactly the ghost-panel behaviour the lock code exists to prevent. The
  /// canvas and cover re-check the service themselves, at tap time.
  bool get _doubleTapToSleepArmed => _doubleTapToSleep && !_isLocked;

  /// Persists the two gesture preferences through the same
  /// [GalaxyStorageService] the layout uses.
  ///
  /// `nativeLauncherMode` is deliberately omitted: a null argument leaves the
  /// stored value alone, so saving a gesture cannot silently reset the lock mode.
  Future<void> _saveGestureSettings() async {
    await GalaxyStorageService.saveConfig(
      coreAppPackageNames: _layoutEngine.corePackageNames,
      customConstellations: _layoutEngine.customConstellations,
      constellationAppOverrides: _layoutEngine.constellationAppOverrides,
      hiddenPackageNames: _layoutEngine.hiddenPackageNames,
      doubleTapToSleep: _doubleTapToSleep,
      swipeDownAction: _swipeDownAction,
    );
  }

  /// Opens the small Gestures sheet.
  ///
  /// The service state is read once on open so the sheet never shows a stale
  /// "on"; the sheet then re-reads it after a trip to Android's settings.
  Future<void> _openGesturesSheet() async {
    final bool enabled = await SystemGestures.isEnabled();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: LuminousHomeTheme.lockScrim,
      builder: (sheetContext) => GesturesSheet(
        serviceEnabled: enabled,
        doubleTapToSleep: _doubleTapToSleep,
        swipeDownAction: _swipeDownAction,
        onDoubleTapToSleepChanged: (value) {
          setState(() => _doubleTapToSleep = value);
          unawaited(_saveGestureSettings());
        },
        onSwipeDownActionChanged: (action) {
          setState(() => _swipeDownAction = SwipeDownAction.normalise(action));
          unawaited(_saveGestureSettings());
        },
      ),
    );
  }

  /// The galaxy's swipe-down action.
  ///
  /// Configured for notifications and with the service connected, it opens the
  /// shade; a platform refusal falls back to search rather than swallowing the
  /// gesture. Otherwise it opens app search exactly as it always has.
  void _handleSwipeDown() {
    if (_swipeDownAction == SwipeDownAction.notifications) {
      unawaited(_showNotificationsOrSearch());
      return;
    }
    setState(() => _isSearchOpen = true);
  }

  Future<void> _showNotificationsOrSearch() async {
    if (await SystemGestures.isEnabled()) {
      final bool opened = await SystemGestures.notifications();
      if (opened) return;
    }
    if (!mounted) return;
    setState(() => _isSearchOpen = true);
  }

  /// Whether the persisted layout has been applied to [_layoutEngine].
  ///
  /// [_loadApplications] runs again on every package-change broadcast. The
  /// stored config (core pin, custom constellations, overrides, hidden apps,
  /// native mode) must be read once; re-applying it on each broadcast is what
  /// used to append a duplicate custom constellation per package change. After
  /// the first load a broadcast only refreshes the app list.
  bool _storedConfigApplied = false;

  /// Bumped per [_loadApplications] call. Package-change broadcasts can start
  /// overlapping reloads; only the newest may apply its scan.
  int _loadGen = 0;

  /// Retries a device scan that failed before any inventory existed, so a
  /// transient PackageManager error does not leave an empty galaxy until the
  /// next package change. Bounded; cancelled on dispose.
  Timer? _scanRetryTimer;
  int _scanRetries = 0;
  static const int _maxScanRetries = 3;

  Future<void> _loadApplications() async {
    final gen = ++_loadGen;
    final scanned = await LauncherBridge.getInstalledApps();
    if (gen != _loadGen || !mounted) return;
    // A failed scan on a device returns null: keep the current inventory.
    final List<AppEntry> apps = scanned ?? _apps;
    if (scanned == null &&
        apps.isEmpty &&
        _scanRetries < _maxScanRetries) {
      _scanRetries++;
      _scanRetryTimer?.cancel();
      _scanRetryTimer = Timer(const Duration(seconds: 2), () {
        if (mounted) _loadApplications();
      });
    }

    // Load persisted galaxy configuration once, on the first load only.
    if (!_storedConfigApplied) {
      _storedConfigApplied = true;
      final config = await GalaxyStorageService.loadConfig();
      if (!mounted) return;
      // Deliberately not generation-checked: the config is read only once, so
      // it must be applied even if a newer reload has overtaken this one.
      if (config.isNotEmpty) {
        // Every read here tolerates a malformed value: a single bad entry in
        // the settings file used to throw out of this load and leave the
        // launcher on its spinner for good.
        final customList = CustomConstellationConfig.parseList(
          config['customConstellations'] ?? config['customGalaxies'],
        );
        for (final customConfig in customList) {
          _layoutEngine.createCustomConstellation(
            id: customConfig.id,
            name: customConfig.name,
            primaryColor: Color(customConfig.primaryColorValue),
            emblemIcon: customConfig.icon,
            packageNames: customConfig.packageNames,
          );
        }
        final rawCore = config['coreAppPackageNames'];
        if (rawCore is List) {
          _layoutEngine.setCorePackageNames(
            rawCore.whereType<String>().toList(),
          );
        }
        final rawOverrides = config['constellationAppOverrides'];
        if (rawOverrides is Map<String, dynamic>) {
          for (final entry in rawOverrides.entries) {
            final value = entry.value;
            if (value is List) {
              _layoutEngine.constellationAppOverrides[entry.key] =
                  value.whereType<String>().toList();
            }
          }
        }
        final rawHidden = config['hiddenPackageNames'];
        if (rawHidden is List) {
          _layoutEngine.setHiddenPackageNames(
            rawHidden.whereType<String>().toList(),
          );
        }
        final rawNative = config['nativeLauncherMode'];
        _nativeMode = rawNative is bool ? rawNative : false;
        final rawSleep = config['doubleTapToSleep'];
        _doubleTapToSleep = rawSleep is bool ? rawSleep : false;
        _swipeDownAction = SwipeDownAction.normalise(
          config['swipeDownAction'],
        );
        final rawHint = config['firstRunHintDismissed'];
        _firstRunHintDismissed = rawHint is bool ? rawHint : false;
      }
      // Test seams win over the stored file. Production passes neither, so this
      // is inert there.
      if (widget.doubleTapToSleep != null) {
        _doubleTapToSleep = widget.doubleTapToSleep!;
      }
      if (widget.swipeDownAction != null) {
        _swipeDownAction = SwipeDownAction.normalise(widget.swipeDownAction);
      }
      if (widget.firstRunHintDismissed != null) {
        _firstRunHintDismissed = widget.firstRunHintDismissed!;
      }
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
      // This panel stands for the keyguard, so it reconciles in case the
      // platform satisfies the lock before the launcher ever draws.
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
    if (gen != _loadGen || !mounted) return;

    _layoutEngine.assignApps(apps);
    if (mounted) {
      setState(() {
        _apps = apps;
        _isLoading = false;
        // A package-change rescan rebuilds the entries, so the counts that
        // already arrived must be re-applied to the new objects — but only
        // once the platform has actually answered, so a desktop simulation
        // keeps its sample badges.
        if (_badgeController.hasReceivedEvent) {
          _applyBadgeCounts(apps);
        }
      });
    }

    // A PDF shared before the launcher started was retained natively; collect
    // it now that the cold-start keyguard check above has settled `_isLocked`.
    // Guarded so the package-change reloads do not pull it repeatedly.
    if (!_pendingSharedPdfChecked) {
      _pendingSharedPdfChecked = true;
      unawaited(_pullPendingSharedPdf());
    }
  }

  /// Pulls the native pending share at startup and routes it through the same
  /// lock-aware handoff as a live push.
  Future<void> _pullPendingSharedPdf() async {
    final String? path = await (widget.takePendingSharedPdf ??
        LauncherBridge.takePendingSharedPdf)();
    if (!mounted || path == null || path.isEmpty) return;
    await _onSharedPdf(path);
  }

  /// Handles a shared PDF path: import it now, or hold it if the lock panel is
  /// up. A locked device must never show the shopping surface or its review
  /// sheet, so the path waits for [_handleUnlock].
  Future<void> _onSharedPdf(String path) async {
    if (!mounted) return;
    if (_isLocked) {
      _pendingSharedPdfPath = path;
      return;
    }
    await _openSharedPdf(path);
  }

  /// Extracts, parses and reviews a shared PDF, then leaves the user in the
  /// shopping surface. Failures are themed snack bars rather than silent drops.
  Future<void> _openSharedPdf(String path) async {
    final PdfImportService service = PdfImportService(
      extract: widget.extractPdfText ?? LauncherBridge.extractPdfText,
      pick: widget.pickPdf ?? LauncherBridge.pickPdf,
    );
    final PdfImportResult result = await service.importPath(path);
    if (!mounted) return;
    if (!result.isSuccess) {
      if (result.error == PdfImportErrorKind.cancelled) return;
      _showSharedPdfError(
        result.message ?? 'This PDF could not be read.',
      );
      return;
    }

    final ParsedDocument document = result.document!;
    _openShopping();
    if (document.isEmpty) {
      _showSharedPdfError('No list items found in this PDF');
      return;
    }
    await reviewImportedDocument(
      context,
      controller: _shoppingController,
      document: document,
    );
  }

  void _showSharedPdfError(String message) {
    if (!mounted) return;
    showGrocerySnackBar(context, message);
  }

  /// Clears the lock panel and, if a shared PDF was held back while locked,
  /// imports it now that the surface is clear.
  void _handleUnlock() {
    setState(() => _isLocked = false);
    final String? path = _pendingSharedPdfPath;
    if (path == null) return;
    _pendingSharedPdfPath = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(_openSharedPdf(path));
      }
    });
  }

  void _openAppLongPressDialog(AppEntry app, Offset screenPosition) {
    showNativePanel(
      context: context,
      barrierLabel: 'AppActions',
      pageBuilder: (context) => AppActionDialog(
        app: app,
        layoutEngine: _layoutEngine,
        onActionCompleted: () => setState(() {}),
      ),
    );
  }

  void _openConstellationEditorModal(Constellation constellation) {
    showNativePanel(
      context: context,
      barrierLabel: 'ConstellationEditor',
      pageBuilder: (context) => ConstellationEditorModal(
        constellation: constellation,
        layoutEngine: _layoutEngine,
        allApps: _apps,
        onUpdated: () => setState(() {}),
      ),
    );
  }

  void _openCenterConstellationEditorModal() {
    final core = _layoutEngine.constellations.firstWhere((c) => c.id == 'core');
    _openConstellationEditorModal(core);
  }

  void _openCreateConstellationModal() {
    showNativePanel(
      context: context,
      barrierLabel: 'CreateConstellation',
      pageBuilder: (context) => CreateConstellationModal(
        layoutEngine: _layoutEngine,
        allApps: _apps,
        onCreated: () => setState(() {}),
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scanRetryTimer?.cancel();
    _wallpaperToneSubscription?.cancel();
    _badgeController.removeListener(_onBadgeCountsChanged);
    _badgeController.dispose();
    _camera.removeListener(_scheduleWallpaperOffsets);
    _foldable.removeListener(_scheduleWallpaperOffsets);
    _foldable.dispose();
    _camera.dispose();
    _searchCoordinator.dispose();
    _shoppingController.dispose();
    _defaultLauncher.dispose();
    super.dispose();
  }

  Widget _buildFirstRunHint(BuildContext context) {
    // An overlay or the lock panel mutes this subtree's tickers, which would
    // freeze an exit animation half-way; drop the card outright instead.
    if (!_firstRunHintDismissed && !_showFirstRunHint) {
      return const SizedBox.shrink();
    }
    final bool show = _showFirstRunHint;
    return AnimatedSwitcher(
      duration: LuminousHomeTheme.motion(
        context,
        LuminousHomeTheme.motionShort,
      ),
      switchInCurve: LuminousHomeTheme.easeStandard,
      switchOutCurve: LuminousHomeTheme.easeExit,
      child: show
          ? Padding(
              key: const ValueKey('first_run_hint'),
              padding: const EdgeInsets.symmetric(
                horizontal: LuminousHomeTheme.screenGutter,
              ),
              child: FirstRunHintCard(
                swipeDownLabel:
                    _swipeDownAction == SwipeDownAction.notifications
                    ? 'Swipe down for notifications'
                    : 'Swipe down to search',
                onDismiss: _dismissFirstRunHint,
                onSetDefault: _isDefaultLauncher
                    ? null
                    : () => unawaited(_requestDefaultLauncher()),
              ),
            )
          : const SizedBox.shrink(key: ValueKey('first_run_hint_hidden')),
    );
  }

  @override
  Widget build(BuildContext context) {
    _foldable.updateFromMediaQuery(context);
    _syncWallpaperChrome();

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        // While the lock panel is up Back is consumed and does nothing: it
        // must not close search or shopping underneath the lock.
        if (_isLocked) return;
        // Back is consumed by the topmost surface first. The shopping surface
        // sits above the comet web-search surface and app search, so it must
        // close before them; otherwise Back would be swallowed while the
        // shopping list stays up.
        if (_isShoppingOpen) {
          _closeShopping();
        } else if (_isCometSearchOpen) {
          _closeCometSearch();
        } else if (_isSearchOpen) {
          setState(() => _isSearchOpen = false);
        }
        // On the bare home surface Back is consumed and does nothing. A native
        // home ignores Back on its own surface — ColorOS neither leaves HOME
        // nor scrolls its pages — and recentering the galaxy here made the
        // launcher the one home that visibly reacted. Home (the gesture or
        // the button) is what recenters, through setHomeButtonListener.
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
                      // 0. Legibility scrims over the system wallpaper, under
                      // every posture's chrome. The lock panel and the
                      // full-screen surfaces cover them with their own.
                      Positioned.fill(
                        key: const ValueKey('wallpaper_scrim'),
                        child: WallpaperScrim(
                          light: _wallpaperTone?.isLight ?? false,
                        ),
                      ),

                      // Main Launcher Content (Folded Cover Screen vs Unfolded Cosmic Galaxy)
                      //
                      // The lock panel and both search surfaces cover this
                      // content completely, so its tickers are muted until it is
                      // visible again — an invisible 120Hz starfield behind an
                      // opaque overlay is pure battery cost, and freezing it also
                      // stops the search blur from re-filtering a moving
                      // background every frame.
                      TickerMode(
                        enabled: !(_isLocked ||
                            _isSearchOpen ||
                            _isCometSearchOpen ||
                            _isShoppingOpen),
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
                                  onOpenSettings: _openSettings,
                                  onLock: _lockDevice,
                                  onAppLongPressed: _openAppLongPressDialog,
                                  onConstellationLongPressed:
                                      _openConstellationEditorModal,
                                  onCreateConstellation:
                                      _openCreateConstellationModal,
                                  onEditCore:
                                      _openCenterConstellationEditorModal,
                                  onOpenShopping: _openShopping,
                                  onOpenGestures: _openGesturesSheet,
                                  doubleTapToSleep: _doubleTapToSleepArmed,
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
                                  onOpenSettings: _openSettings,
                                  onLock: _lockDevice,
                                  onAppLongPressed: _openAppLongPressDialog,
                                  onConstellationLongPressed:
                                      _openConstellationEditorModal,
                                  onCreateConstellation:
                                      _openCreateConstellationModal,
                                  onEditCore:
                                      _openCenterConstellationEditorModal,
                                  onToggleFullscreen: () =>
                                      setState(() => _isCockpitMode = false),
                                  onOpenShopping: _openShopping,
                                  onSwipeDown: _handleSwipeDown,
                                  doubleTapToSleep: _doubleTapToSleepArmed,
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
                                        badgeRevision: _badgeRevision,
                                        onAppLongPressed:
                                            _openAppLongPressDialog,
                                        onConstellationLongPressed:
                                            _openConstellationEditorModal,
                                        onSwipeDown: _handleSwipeDown,
                                        doubleTapToSleep:
                                            _doubleTapToSleepArmed,
                                      ),
                                    ),

                                    // 2. Header (clock, date, primary
                                    // nudges) with the one-time hint card
                                    // directly beneath it, well clear of
                                    // the dock.
                                    Positioned(
                                      top: 0,
                                      left: 0,
                                      right: 0,
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          CosmicHeaderHud(
                                            isDefaultLauncher:
                                                _isDefaultLauncher,
                                            onSetDefaultLauncher:
                                                _requestDefaultLauncher,
                                            onToggleCockpit: _foldable
                                                    .isTabletop
                                                ? () => setState(
                                                    () => _isCockpitMode =
                                                        true,
                                                  )
                                                : null,
                                          ),
                                          _buildFirstRunHint(context),
                                        ],
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
                                        onOpenSettings: _openSettings,
                                        onLock: _lockDevice,
                                        onCreateConstellation:
                                            _openCreateConstellationModal,
                                        onEditCore:
                                            _openCenterConstellationEditorModal,
                                        onOpenShopping: _openShopping,
                                        onOpenGestures: _openGesturesSheet,
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                      ),

                      // Fullscreen Search HUD & Categorized Celestial Library
                      // Every overlay is keyed. Unkeyed, closing one shifted
                      // the later siblings into its element slot, so a mounted
                      // lock panel was rebuilt as a fresh state — and the old
                      // state's dispose then cleared the new one's unlock
                      // listeners, stranding the panel after an unlock.
                      if (_isSearchOpen)
                        Positioned.fill(
                          key: const ValueKey('overlay_search'),
                          child: SearchOverlay(
                            allApps: _apps,
                            camera: _camera,
                            layoutEngine: _layoutEngine,
                            onAppLongPressed: _openAppLongPressDialog,
                            onClose: () =>
                                setState(() => _isSearchOpen = false),
                            onOpenSettings: _openSettings,
                            onSearchWeb: _openCometSearch,
                          ),
                        ),

                      // Comet Web Search Surface
                      if (_isCometSearchOpen)
                        Positioned.fill(
                          key: const ValueKey('overlay_comet'),
                          child: CometSearchSurface(
                            key: ValueKey('comet_${_cometInitialQuery ?? ''}'),
                            coordinator: _searchCoordinator,
                            initialQuery: _cometInitialQuery,
                            onClose: _closeCometSearch,
                          ),
                        ),

                      // Shopping List Surface
                      if (_isShoppingOpen)
                        Positioned.fill(
                          key: const ValueKey('overlay_shopping'),
                          child: ShoppingSurface(
                            controller: _shoppingController,
                            foldable: _foldable,
                            onClose: _closeShopping,
                          ),
                        ),

                      // Celestial Foldable Lock Screen
                      if (_isLocked)
                        Positioned.fill(
                          key: const ValueKey('overlay_lock'),
                          child: CosmicLockScreen(
                            foldable: _foldable,
                            apps: _apps,
                            onUnlock: _handleUnlock,
                            // Every mount now stands for a lock the platform
                            // may have satisfied before this panel could draw
                            // (screen-off behind a foreign app, or a cold start
                            // raced by an unlock), so it always reconciles:
                            // the panel checks the keyguard at its first frame
                            // and clears itself if the lock is gone.
                            reconcileOnMount: true,
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

/// The unfolded header: clock and date, plus at most two primary nudges.
///
/// Wallpaper, lock-surface mode and gestures live in the Settings sheet, Lock
/// is on the dock, and the posture readout was ornamental telemetry (PRODUCT.md
/// principle 2), so the shelf only carries what has no other entry point: the
/// "Set default" nudge while ChronoFold is not the home app, and the tabletop
/// Cockpit switch.
class CosmicHeaderHud extends StatefulWidget {
  final VoidCallback? onToggleCockpit;
  final bool isDefaultLauncher;
  final VoidCallback? onSetDefaultLauncher;

  const CosmicHeaderHud({
    super.key,
    this.onToggleCockpit,
    this.isDefaultLauncher = true,
    this.onSetDefaultLauncher,
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
    final bool showSetDefault =
        !widget.isDefaultLauncher && widget.onSetDefaultLauncher != null;

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
            if (showSetDefault || widget.onToggleCockpit != null) ...[
              const SizedBox(width: 14),

              // Compact utility shelf; it scrolls instead of competing with
              // time.
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
                      // An opaque fill, not a BackdropFilter: the galaxy under
                      // the header repaints every frame and would re-run the
                      // blur on each one (same reasoning as the dock).
                      child: ColoredBox(
                        color: LuminousHomeTheme.glassOpaque,
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
                            border: Border.all(
                              color: LuminousHomeTheme.hairline,
                            ),
                          ),
                          child: SizedBox(
                            height: 56,
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              reverse: true,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (showSetDefault)
                                    _utilityButton(
                                      icon: Icons.home_rounded,
                                      label: 'Set default',
                                      tooltip: 'Set as default launcher',
                                      color: LuminousHomeTheme.accent,
                                      emphasized: true,
                                      onTap: widget.onSetDefaultLauncher!,
                                    ),
                                  if (widget.onToggleCockpit != null)
                                    _utilityButton(
                                      icon: Icons.splitscreen_rounded,
                                      label: 'Cockpit',
                                      tooltip: 'Open tabletop cockpit',
                                      color: LuminousHomeTheme.accent,
                                      onTap: widget.onToggleCockpit!,
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
                        style: LuminousHomeTheme.chipLabel,
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
