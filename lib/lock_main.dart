import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'core/foldable_controller.dart';
import 'core/launcher_bridge.dart';
import 'features/lockscreen/cosmic_lock_screen.dart';
import 'models/app_entry.dart';
import 'ui/theme/luminous_home_theme.dart';
import 'ui/theme/system_palette.dart';

/// The entry point for the [LockActivity] engine.
///
/// `@pragma('vm:entry-point')` keeps this alive through AOT tree-shaking even
/// though nothing in the launcher calls it: the engine looks it up by name
/// (`getDartEntrypointFunctionName()` returns `lockMain`). `main.dart`
/// re-exports it so the two entry points stay in one kernel.
@pragma('vm:entry-point')
Future<void> lockMain() async {
  WidgetsFlutterBinding.ensureInitialized();
  // The lock activity is a second engine, so it resolves the accent itself
  // rather than inheriting the launcher's. Same timeout contract: a platform
  // that never answers keeps the aqua fallback.
  final SystemPalette? palette = await LauncherBridge.getSystemPalette()
      .timeout(const Duration(milliseconds: 300), onTimeout: () => null);
  LuminousHomeTheme.applyPalette(palette);
  runApp(const LockSurfaceApp());
}

/// The lock surface raised over a foreign task on screen-off.
///
/// It is deliberately tiny: the cosmic panel already owns the visuals and the
/// authentication rules, so this only supplies the seams the panel does not
/// decide for itself — the app inventory, the keyguard question, and what
/// "unlock" means on a surface that is not the launcher (finish the activity,
/// revealing the app underneath).
class LockSurfaceApp extends StatefulWidget {
  /// Loads the app inventory. Defaults to [LauncherBridge.getInstalledApps];
  /// injectable so a widget test never touches a platform channel.
  final Future<List<AppEntry>> Function()? loadApps;

  /// Leaves the lock surface. Defaults to [LauncherBridge.finishLock];
  /// injectable so a test can observe the unlock without a platform.
  final Future<bool> Function()? onFinish;

  /// The keyguard question the panel's `reconcileOnMount` asks. Defaults to
  /// [LauncherBridge.isKeyguardLocked].
  final Future<bool> Function()? isKeyguardLocked;

  /// Schedules the forced frame that makes Android draw the lock window.
  /// Defaults to [SchedulerBinding.instance.scheduleForcedFrame]; injectable so
  /// a test can count requests without the panel's live animations leaving
  /// `hasScheduledFrame` permanently true.
  final VoidCallback? requestFrame;

  const LockSurfaceApp({
    super.key,
    this.loadApps,
    this.onFinish,
    this.isKeyguardLocked,
    this.requestFrame,
  });

  @override
  State<LockSurfaceApp> createState() => _LockSurfaceAppState();
}

class _LockSurfaceAppState extends State<LockSurfaceApp>
    with WidgetsBindingObserver {
  late final FoldableController _foldable;
  List<AppEntry> _apps = const [];

  /// Whether the panel has already asked this surface to leave.
  ///
  /// Several independent paths can clear the panel within the same unlock —
  /// the mount reconcile, a swipe, a shortcut — and each one used to call the
  /// finisher. The native side now guards too; this keeps the request itself
  /// single so nothing downstream sees a second unlock.
  bool _finishRequested = false;

  @override
  void initState() {
    super.initState();
    _foldable = FoldableController();
    // A lock surface raised while the display is off can resume with its window
    // still `DRAW_PENDING`: frames were disabled while the engine was stopped,
    // and nothing in the framework schedules one when it comes back. Both
    // signals below answer with a forced frame so Android finally draws it.
    WidgetsBinding.instance.addObserver(this);
    LauncherBridge.setRequestFrameListener(_requestFrame);
    _loadApps();
  }

  /// Produces a frame even while the engine believes frames are disabled.
  ///
  /// [SchedulerBinding.scheduleFrame] would be dropped in the paused/stopped
  /// state that a screen-off lock resumes from; the forced variant reaches
  /// `PlatformDispatcher.scheduleFrame` unconditionally, which is what the
  /// `DRAW_PENDING` window needs to make `isReadyForDisplay()` true.
  void _requestFrame() {
    final request = widget.requestFrame;
    if (request != null) {
      request();
    } else {
      SchedulerBinding.instance.scheduleForcedFrame();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
      case AppLifecycleState.inactive:
        _requestFrame();
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        break;
    }
  }

  Future<void> _loadApps() async {
    final loadApps = widget.loadApps;
    // Split rather than `?? tearOff()` on purpose: the bridge method has an
    // optional named argument, and a conditional keeps the static type exact.
    final apps = loadApps != null
        ? await loadApps()
        : await LauncherBridge.getInstalledApps();
    if (!mounted) return;
    setState(() => _apps = apps);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    LauncherBridge.setRequestFrameListener(null);
    _foldable.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<SystemPalette?>(
      stream: LauncherBridge.systemPaletteChanges,
      builder: (context, snapshot) {
        // Mirrors the launcher: apply only a real push, so the palette
        // [lockMain] resolved before the first frame is not reset to aqua by the
        // stream's empty start, and a null push restores aqua.
        if (snapshot.connectionState == ConnectionState.active) {
          LuminousHomeTheme.applyPalette(snapshot.data);
        }
        return MaterialApp(
          key: ValueKey<int>(LuminousHomeTheme.paletteRevision),
          title: 'ChronoFold Lock',
          debugShowCheckedModeBanner: false,
          // The same design system as the launcher: one source of colour, radius
          // and type, so the lock surface cannot drift from the HOME panel.
          theme: LuminousHomeTheme.buildTheme(),
          home: PopScope(
            // A lock surface never backs out of itself; the platform keyguard is
            // the only way out. The native side swallows back as well.
            canPop: false,
            // The launcher mounts this panel inside the home Scaffold; the lock
            // activity has no Scaffold, so provide the Material ancestor the app
            // tiles' InkWells expect without changing the layout.
            child: Material(
              type: MaterialType.transparency,
              child: CosmicLockScreen(
                foldable: _foldable,
                apps: _apps,
                // This surface stands for a screen-off lock, not a user-raised
                // privacy panel, so it clears itself if the keyguard is already
                // gone by the time it can draw.
                reconcileOnMount: true,
                isKeyguardLocked: widget.isKeyguardLocked,
                onUnlock: () {
                  if (_finishRequested) return;
                  _finishRequested = true;
                  final finish = widget.onFinish ?? LauncherBridge.finishLock;
                  unawaited(finish());
                },
              ),
            ),
          ),
        );
      },
    );
  }
}
