import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/semantics.dart';
import '../models/app_entry.dart';
import '../models/constellation.dart';
import '../core/launcher_bridge.dart';
import '../core/launcher_haptics.dart';
import '../core/foldable_controller.dart';
import '../core/galaxy_layout_engine.dart';
import '../core/system_gestures.dart';
import 'camera_controller.dart';
import 'galaxy_custom_painter.dart';
import '../ui/theme/luminous_home_theme.dart';

class GalaxyInteractiveCanvas extends StatefulWidget {
  final List<AppEntry> apps;
  final FoldableController foldable;
  final CameraController camera;
  final GalaxyLayoutEngine layoutEngine;
  final Function(AppEntry app)? onAppSelected;
  final Function(AppEntry app, Offset screenPosition)? onAppLongPressed;
  final Function(Constellation constellation)? onConstellationLongPressed;
  final VoidCallback? onSwipeDown;

  /// Whether a double tap on empty space should sleep the screen.
  ///
  /// The gesture is additionally gated on the accessibility service being
  /// connected at tap time, and the surface that owns the lock panel keeps this
  /// false while that panel is mounted.
  final bool doubleTapToSleep;

  /// Bumps when the notification counts changed, so a resting (reduce-motion)
  /// canvas still repaints its badges.
  final int badgeRevision;

  const GalaxyInteractiveCanvas({
    super.key,
    required this.apps,
    required this.foldable,
    required this.camera,
    required this.layoutEngine,
    this.onAppSelected,
    this.onAppLongPressed,
    this.onConstellationLongPressed,
    this.onSwipeDown,
    this.doubleTapToSleep = false,
    this.badgeRevision = 0,
  });

  /// How long the canvas keeps rendering after the last sign of activity
  /// before it rests on its last painted frame.
  ///
  /// The render loop is the launcher's largest steady cost (120Hz on the N6's
  /// panel). With nobody touching the galaxy and nothing in flight there is
  /// nothing worth drawing at that rate, so after this window the ticker stops
  /// and any touch, camera move, animation or relevant rebuild restarts it.
  @visibleForTesting
  static const Duration idleTimeout = Duration(seconds: 8);

  @override
  State<GalaxyInteractiveCanvas> createState() => _GalaxyInteractiveCanvasState();
}

class _GalaxyInteractiveCanvasState extends State<GalaxyInteractiveCanvas>
    with TickerProviderStateMixin {
  late Ticker _renderLoopTicker;
  final ChangeNotifier _paintRepaintNotifier = ChangeNotifier();
  double _animationTime = 0.0;

  /// The ticker timestamp of the previous frame, or null when the next frame
  /// must only re-establish the baseline.
  ///
  /// Cleared whenever the loop (re)starts or is unmuted, so the first frame
  /// after a rest never sees the rest itself as one enormous `dt`: simulated
  /// time carries forward from where it stopped instead of skipping ahead.
  Duration? _lastFrameTime;

  // Idle pause bookkeeping.
  bool _reduceMotion = false;

  /// Simulated seconds since the last sign of activity.
  double _idleSeconds = 0.0;

  /// Pointers currently down on the canvas.
  int _activePointers = 0;

  ValueListenable<TickerModeData>? _tickerModeNotifier;
  bool _tickerModeEnabled = true;

  /// Fingerprint of what the layout engine currently arranges, compared on
  /// rebuild so a change made elsewhere (an editor, a rescan) wakes the loop
  /// to morph into it.
  int _layoutSignature = 0;

  // Starfield particles in fixed world space
  final List<CosmicParticle> _starfield = [];
  final List<ShootingStar> _shootingStars = [];
  double _nextMeteorSpawnTime = 1.5;
  final math.Random _rng = math.Random(1337);

  // Touch and Gesture State
  Offset? _magneticTouchWorld;
  Offset? _lastFocalPoint;
  double _lastScale = 1.0;
  double _accumulatedPanDy = 0.0;
  double _accumulatedPanDx = 0.0;
  SupernovaAnimation? _activeSupernova;
  AppEntry? _focusedApp;

  /// The launch deferred behind the supernova. Cancelled on dispose so an app
  /// can never open after the canvas that was tapped is gone.
  Timer? _pendingLaunchTimer;

  @override
  void initState() {
    super.initState();
    widget.camera.init(this);
    _generateWorldStarfield(420);

    widget.camera.addListener(_onCameraChange);
    widget.foldable.addListener(_onFoldableChange);
    _renderLoopTicker = createTicker(_onRenderTick);
    _layoutSignature = _computeLayoutSignature();

    // A reader can be switched on while this screen is already up, and nothing
    // else here rebuilds when that happens — without this the canvas would stay
    // unreachable until the next unrelated rebuild.
    SemanticsBinding.instance.addSemanticsEnabledListener(
      _onSemanticsEnabledChanged,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Perpetual orbiting and twinkling is the point of this surface, but a user
    // who turned animations off should get one still frame of it rather than a
    // 120Hz loop they explicitly asked not to have.
    _syncRenderLoop();
    _syncTickerModeListener();
  }

  @override
  void didUpdateWidget(covariant GalaxyInteractiveCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.foldable, widget.foldable)) {
      oldWidget.foldable.removeListener(_onFoldableChange);
      widget.foldable.addListener(_onFoldableChange);
    }
    // Only a rebuild that can change what is drawn wakes the loop: the cockpit
    // rebuilds this canvas every minute for its clock, and that alone must not
    // cost eight seconds of 120Hz.
    final int signature = _computeLayoutSignature();
    if (signature != _layoutSignature ||
        !identical(oldWidget.apps, widget.apps) ||
        !identical(oldWidget.layoutEngine, widget.layoutEngine) ||
        !identical(oldWidget.camera, widget.camera) ||
        !identical(oldWidget.foldable, widget.foldable) ||
        oldWidget.badgeRevision != widget.badgeRevision) {
      _layoutSignature = signature;
      _markActivity();
    }
  }

  void _syncRenderLoop() {
    _reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (_reduceMotion) {
      if (_renderLoopTicker.isActive) _renderLoopTicker.stop();
      // Paint the resting arrangement once.
      _requestRepaint();
    } else {
      // Turning reduce motion off, or any other dependency change (text
      // scale, theme), counts as activity.
      _markActivity();
    }
  }

  /// Follows the TickerMode the host mutes this canvas with behind the lock,
  /// search and shopping overlays. The mute itself is the ticker's; unmuting
  /// is activity, and rebases simulated time so the overlay's duration is not
  /// replayed as one jump in orbits and meteors.
  void _syncTickerModeListener() {
    final notifier = TickerMode.getValuesNotifier(context);
    if (identical(notifier, _tickerModeNotifier)) return;
    _tickerModeNotifier?.removeListener(_onTickerModeChanged);
    _tickerModeNotifier = notifier..addListener(_onTickerModeChanged);
    _tickerModeEnabled = notifier.value.enabled;
  }

  void _onTickerModeChanged() {
    final bool enabled = _tickerModeNotifier?.value.enabled ?? true;
    if (enabled == _tickerModeEnabled) return;
    _tickerModeEnabled = enabled;
    _lastFrameTime = null;
    if (enabled) _markActivity();
  }

  /// Records activity: resets the idle window and makes sure the render loop
  /// runs. Cheap enough to call on every pointer move and camera change.
  void _markActivity() {
    _idleSeconds = 0.0;
    if (_reduceMotion || !mounted) return;
    if (!_renderLoopTicker.isActive) {
      // A fresh start: the first frame only sets the baseline.
      _lastFrameTime = null;
      // A meteor overdue during the rest would fire on the very first frame,
      // reading as a reaction to the touch; push it back instead.
      _nextMeteorSpawnTime = math.max(_nextMeteorSpawnTime, _animationTime + 1.5);
      _renderLoopTicker.start();
    }
  }

  /// Whether anything on the canvas is still moving under its own power, in
  /// which case the loop stays awake past the idle window until it finishes.
  bool get _motionInProgress {
    if (_activePointers > 0 || _magneticTouchWorld != null) return true;
    if (_activeSupernova != null || _shootingStars.isNotEmpty) return true;
    if (widget.camera.isAnimating) return true;
    for (final c in widget.layoutEngine.constellations) {
      final double target = c.isExpanded ? 1.0 : 0.0;
      if ((c.expansionProgress - target).abs() > 1e-3) return true;
      for (final app in c.apps) {
        if ((app.worldPosition - app.basePosition).distanceSquared > 0.01) {
          return true;
        }
      }
    }
    return false;
  }

  int _computeLayoutSignature() {
    int hash = 0;
    for (final c in widget.layoutEngine.constellations) {
      hash = Object.hash(hash, identityHashCode(c), c.isExpanded, c.apps.length);
      for (final app in c.apps) {
        hash = Object.hash(hash, identityHashCode(app), app.notificationCount);
      }
    }
    return hash;
  }

  void _onFoldableChange() => _markActivity();

  /// Asks the canvas to repaint without advancing the simulation.
  void _requestRepaint() {
    // ignore: invalid_use_of_visible_for_testing_member, invalid_use_of_protected_member
    _paintRepaintNotifier.notifyListeners();
  }

  void _onCameraChange() {
    _markActivity();
    _requestRepaint();
  }

  void _generateWorldStarfield(int count) {
    _starfield.clear();
    const colors = [
      LuminousHomeTheme.white, // Diamond white
      LuminousHomeTheme.starIcy, // Icy cyan
      LuminousHomeTheme.starGold, // Warm solar gold
      LuminousHomeTheme.starRose, // Soft nebula rose
      LuminousHomeTheme.starViolet, // Ethereal violet
      LuminousHomeTheme.starBlue, // Stellar blue
    ];

    // 1. Layer of distant micro-stardust particles (faint, sharp depth)
    final int microCount = (count * 0.70).round();
    for (int i = 0; i < microCount; i++) {
      final z = 0.3 + _rng.nextDouble() * 0.8;
      _starfield.add(
        CosmicParticle(
          x: _rng.nextDouble() * 4800 - 2400,
          y: _rng.nextDouble() * 4800 - 2400,
          z: z,
          radius: 0.4 + _rng.nextDouble() * 0.65,
          baseBrightness: 0.20 + _rng.nextDouble() * 0.40,
          twinkleSpeed: 0.4 + _rng.nextDouble() * 1.4,
          color: colors[_rng.nextInt(colors.length)],
        ),
      );
    }

    // 2. Main sequence stars (medium brightness & size)
    final int mainCount = (count * 0.24).round();
    for (int i = 0; i < mainCount; i++) {
      final z = 0.8 + _rng.nextDouble() * 1.0;
      _starfield.add(
        CosmicParticle(
          x: _rng.nextDouble() * 4400 - 2200,
          y: _rng.nextDouble() * 4400 - 2200,
          z: z,
          radius: 0.9 + _rng.nextDouble() * 1.1,
          baseBrightness: 0.50 + _rng.nextDouble() * 0.40,
          twinkleSpeed: 0.6 + _rng.nextDouble() * 1.2,
          color: colors[_rng.nextInt(colors.length)],
        ),
      );
    }

    // 3. Bright beacon stars with diffraction cross spikes
    final int beaconCount = count - microCount - mainCount;
    for (int i = 0; i < beaconCount; i++) {
      final z = 1.2 + _rng.nextDouble() * 0.8;
      _starfield.add(
        CosmicParticle(
          x: _rng.nextDouble() * 3800 - 1900,
          y: _rng.nextDouble() * 3800 - 1900,
          z: z,
          radius: 1.8 + _rng.nextDouble() * 1.3,
          baseBrightness: 0.85 + _rng.nextDouble() * 0.15,
          twinkleSpeed: 0.8 + _rng.nextDouble() * 1.5,
          color: colors[_rng.nextInt(colors.length)],
          hasSpikes: true,
        ),
      );
    }
  }

  void _updateShootingStars(double dt) {
    // Past the idle window no new meteor starts, so the ones in flight can
    // finish and the loop can rest on an empty sky.
    if (_idleSeconds < _idleTimeoutSeconds &&
        _animationTime >= _nextMeteorSpawnTime) {
      _spawnShootingStar();
      _nextMeteorSpawnTime = _animationTime + 2.5 + _rng.nextDouble() * 4.0;
    }

    for (int i = _shootingStars.length - 1; i >= 0; i--) {
      final s = _shootingStars[i];
      s.progress += s.speed * dt;
      if (s.progress >= 1.0) {
        _shootingStars.removeAt(i);
      }
    }
  }

  void _spawnShootingStar() {
    final startX = _rng.nextDouble() * 2600 - 1300;
    final startY = _rng.nextDouble() * 1800 - 1200;
    final angle = (math.pi / 4) + (_rng.nextDouble() - 0.5) * 0.45;
    final dist = 320.0 + _rng.nextDouble() * 300.0;
    final endX = startX + math.cos(angle) * dist;
    final endY = startY + math.sin(angle) * dist;

    const meteorColors = [
      LuminousHomeTheme.white,
      LuminousHomeTheme.starBlue,
      LuminousHomeTheme.accentCore,
      LuminousHomeTheme.mint,
    ];

    _shootingStars.add(
      ShootingStar(
        start: Offset(startX, startY),
        end: Offset(endX, endY),
        speed: 0.75 + _rng.nextDouble() * 0.75,
        length: 75.0 + _rng.nextDouble() * 65.0,
        thickness: 1.2 + _rng.nextDouble() * 0.9,
        color: meteorColors[_rng.nextInt(meteorColors.length)],
      ),
    );
  }

  static final double _idleTimeoutSeconds =
      GalaxyInteractiveCanvas.idleTimeout.inMicroseconds / 1e6;

  void _onRenderTick(Duration elapsed) {
    final Duration? last = _lastFrameTime;
    _lastFrameTime = elapsed;
    // The ticker's clock restarts at zero on every start, so a timestamp from
    // before the baseline also means "rebase".
    if (last == null || elapsed < last) return;

    final double dt = (elapsed.inMicroseconds - last.inMicroseconds) / 1e6;
    _animationTime += dt;
    _idleSeconds += dt;

    _updateShootingStars(dt);

    widget.layoutEngine.updateGalaxyMorph(
      posture: widget.foldable.posture,
      hingeAngle: widget.foldable.hingeAngle,
      dt: dt,
      magneticTouchPoint: _magneticTouchWorld,
    );

    if (_activeSupernova != null &&
        _activeSupernova!.getProgress(_animationTime) >= 1.0) {
      _activeSupernova = null;
    }

    // ignore: invalid_use_of_visible_for_testing_member, invalid_use_of_protected_member
    _paintRepaintNotifier.notifyListeners();

    // Nothing touched, nothing in flight: rest on the frame just painted. Any
    // activity source restarts the loop through [_markActivity].
    if (_idleSeconds >= _idleTimeoutSeconds && !_motionInProgress) {
      _renderLoopTicker.stop();
    }
  }

  Constellation? _hitTestConstellation(Offset screenPos) {
    final worldTap = widget.camera.screenToWorld(screenPos);
    for (final c in widget.layoutEngine.constellations) {
      final hitRadius = (c.id == 'core') ? 70.0 : 45.0;
      if ((worldTap - c.center).distance <= hitRadius) {
        return c;
      }
    }
    return null;
  }

  AppEntry? _hitTestApp(Offset screenPos) {
    final worldTap = widget.camera.screenToWorld(screenPos);
    AppEntry? closest;
    double minDistance = double.infinity;

    // Check if any outer constellation is active/expanded
    final activeOuter = widget.layoutEngine.constellations.where(
      (c) => c.id != 'core' && (c.isExpanded || c.expansionProgress > 0.25),
    ).firstOrNull;

    for (final c in widget.layoutEngine.constellations) {
      // If an outer constellation is opened, ONLY its apps are interactive
      if (activeOuter != null) {
        if (c.id != activeOuter.id) continue;
      } else {
        // When no outer constellation is open, only test outer apps if blooming
        if (c.id != 'core' && c.expansionProgress < 0.3) continue;
        // If core is closed or condensing, don't test core apps so center hub can be tapped cleanly!
        if (c.id == 'core' && (c.expansionProgress < 0.35 || !c.isExpanded)) continue;
      }

      for (final app in c.apps) {
        final d = (worldTap - app.worldPosition).distance;
        final hitRadius = (32.0 / widget.camera.zoom).clamp(28.0, 56.0);
        if (d < hitRadius && d < minDistance) {
          minDistance = d;
          closest = app;
        }
      }
    }
    return closest;
  }

  void _handleTapUp(TapUpDetails details) {
    // 1. Check if user tapped an active app
    final tappedApp = _hitTestApp(details.localPosition);
    if (tappedApp != null) {
      _clearEmptyTap();
      _activateApp(tappedApp);
      return;
    }

    // 2. Check if user tapped a constellation cluster hub
    final tappedConstellation = _hitTestConstellation(details.localPosition);
    if (tappedConstellation != null) {
      _clearEmptyTap();
      _activateConstellation(tappedConstellation);
      return;
    }

    // 3. Tapped empty space with the sleep gesture armed and a matching first
    //    tap behind it: sleep instead of collapsing.
    if (_isDoubleTapOnEmptySpace(details.localPosition)) {
      _clearEmptyTap();
      unawaited(_sleepOnDoubleTap());
      return;
    }
    _recordEmptyTap(details.localPosition);

    // 4. Tapped empty space: smoothly collapse expanded outer constellations
    //    back to clean state.
    _focusedApp = null;
    final anyOuterExpanded = widget.layoutEngine.constellations.any(
      (c) => c.id != 'core' && (c.isExpanded || c.expansionProgress > 0.25),
    );
    if (anyOuterExpanded) {
      widget.layoutEngine.collapseAllExceptCore();
      widget.camera.flyTo(Offset.zero, targetZoom: 1.05);
    }
  }

  /// The candidate first tap of the sleep gesture.
  ///
  /// Double-tap detection is timestamp-based rather than a
  /// `DoubleTapGestureRecognizer` on purpose: that recognizer keeps the gesture
  /// arena open after the first tap, so every node tap would wait out the
  /// double-tap timeout before it could launch. Here a node tap runs the
  /// existing tests and opens the app on the same frame, exactly as before.
  final DoubleTapTracker _emptyTap = DoubleTapTracker();

  void _recordEmptyTap(Offset position) {
    if (!widget.doubleTapToSleep) {
      _emptyTap.clear();
      return;
    }
    _emptyTap.record(position);
  }

  void _clearEmptyTap() => _emptyTap.clear();

  bool _isDoubleTapOnEmptySpace(Offset position) =>
      widget.doubleTapToSleep && _emptyTap.matches(position);

  /// Sleeps the screen for a double tap on empty space.
  ///
  /// Only reached with the preference on; the service is re-checked at tap time
  /// so a disabled service makes the gesture a no-op rather than an error, and
  /// [SystemGestures.lockScreen] answers false rather than throwing when the
  /// platform refuses. The lock panel's owner keeps [GalaxyInteractiveCanvas.doubleTapToSleep]
  /// false while that panel is mounted, so this can never re-lock a locked
  /// launcher.
  Future<void> _sleepOnDoubleTap() async {
    if (!widget.doubleTapToSleep) return;
    if (!await SystemGestures.isEnabled()) return;
    await SystemGestures.lockScreen();
  }

  /// Opens [app] — the single path shared by a tap on the canvas and a
  /// TalkBack activation, so the two can never drift apart.
  void _activateApp(AppEntry app) {
    LauncherHaptics.click();
    _markActivity();
    // Capture the node's on-screen rectangle at tap time. The launch is
    // deliberately deferred behind the supernova, and the platform's clip
    // reveal must describe where the finger landed, not where the camera has
    // drifted to by the time the app opens.
    final Rect? sourceBounds = _appScreenRect(app);
    _focusedApp = app;
    _activeSupernova = SupernovaAnimation(
      worldPosition: app.worldPosition,
      color: app.accentColor,
      startTime: _animationTime,
    );

    widget.onAppSelected?.call(app);

    _pendingLaunchTimer?.cancel();
    _pendingLaunchTimer = Timer(const Duration(milliseconds: 300), () {
      _pendingLaunchTimer = null;
      // The panel can lock inside the supernova's 300ms. The canvas stays
      // mounted under the lock surface but its tickers are muted, so a muted
      // canvas means something now covers it and the tap is void.
      if (!mounted || !TickerMode.getValuesNotifier(context).value.enabled) {
        return;
      }
      LauncherBridge.launchApp(app, sourceBounds: sourceBounds);
    });
  }

  /// The tapped node's rectangle in global logical pixels, or null when its
  /// geometry cannot be read.
  Rect? _appScreenRect(AppEntry app) {
    final renderObject = context.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) return null;
    final Offset localCenter = widget.camera.worldToScreen(app.worldPosition);
    final double radius = 32.0 * widget.camera.zoom;
    return Rect.fromCircle(
      center: renderObject.localToGlobal(localCenter),
      radius: radius,
    );
  }

  /// Expands or collapses [constellation], the action a hub tap performs.
  void _activateConstellation(Constellation constellation) {
    LauncherHaptics.click();
    _markActivity();
    if (constellation.id == 'core') {
      final anyOuterExpanded = widget.layoutEngine.constellations.any(
        (c) => c.id != 'core' && (c.isExpanded || c.expansionProgress > 0.25),
      );
      if (anyOuterExpanded) {
        widget.layoutEngine.expandOnly('core');
        widget.camera.flyTo(Offset.zero, targetZoom: 1.25);
      } else {
        // Toggle center constellation between open and closed
        final willExpand = !constellation.isExpanded;
        constellation.isExpanded = willExpand;
        widget.camera.flyTo(Offset.zero, targetZoom: willExpand ? 1.25 : 1.05);
      }
      return;
    }

    if (!constellation.isExpanded) {
      widget.layoutEngine.expandOnly(constellation.id);
      widget.camera.flyTo(constellation.center, targetZoom: 1.4);
    } else {
      constellation.isExpanded = false;
      widget.camera.flyTo(Offset.zero, targetZoom: 1.05);
    }
  }

  void _handleLongPress(LongPressStartDetails details) {
    final app = _hitTestApp(details.localPosition);
    if (app != null) {
      LauncherHaptics.heavyClick();
      widget.onAppLongPressed?.call(app, details.localPosition);
      return;
    }

    // If long pressing constellation emblem / center hub
    final constellation = _hitTestConstellation(details.localPosition);
    if (constellation != null) {
      if (constellation.isExpanded || constellation.id == 'core') {
        LauncherHaptics.heavyClick();
        widget.onConstellationLongPressed?.call(constellation);
      }
    }
  }

  @override
  void dispose() {
    SemanticsBinding.instance.removeSemanticsEnabledListener(
      _onSemanticsEnabledChanged,
    );
    _pendingLaunchTimer?.cancel();
    _tickerModeNotifier?.removeListener(_onTickerModeChanged);
    widget.foldable.removeListener(_onFoldableChange);
    widget.camera.removeListener(_onCameraChange);
    // Only this canvas's own binding is torn down: during a posture transition
    // the incoming canvas may already have re-bound the camera.
    widget.camera.detach(this);
    _renderLoopTicker.dispose();
    _paintRepaintNotifier.dispose();
    super.dispose();
  }

  /// Whether a screen reader is running, i.e. whether the semantics layer is
  /// worth building at all.
  ///
  /// Everything on this surface is painted into one canvas, so nothing is
  /// reachable without explicit semantic nodes — but building a node per app on
  /// every camera change would be per-frame work for users who cannot benefit
  /// from it. Touch exploration is only meaningful when a reader is active.
  bool get _screenReaderActive => SemanticsBinding.instance.semanticsEnabled;

  void _onSemanticsEnabledChanged() {
    if (mounted) setState(() {});
  }

  /// Smallest focus rectangle a screen reader can reliably land on.
  static const double _minSemanticTarget = 48.0;

  static Rect _minTarget(Rect rect) {
    if (rect.width >= _minSemanticTarget && rect.height >= _minSemanticTarget) {
      return rect;
    }
    final center = rect.center;
    final w = math.max(rect.width, _minSemanticTarget);
    final h = math.max(rect.height, _minSemanticTarget);
    return Rect.fromCenter(center: center, width: w, height: h);
  }

  /// The nodes a screen reader can reach, in the order the canvas presents
  /// them: the constellation hubs, then the apps of the constellation that is
  /// currently open — mirroring exactly what a sighted user can tap.
  List<_SemanticTarget> _semanticTargets(Size size) {
    final viewport = Offset.zero & size;
    final targets = <_SemanticTarget>[];

    final openConstellation = widget.layoutEngine.constellations
        .where((c) => c.isExpanded)
        .firstOrNull;

    for (final constellation in widget.layoutEngine.constellations) {
      final center = widget.camera.worldToScreen(constellation.center);
      final hitRadius = (constellation.id == 'core' ? 70.0 : 45.0);
      final rect = _minTarget(
        Rect.fromCircle(
          center: center,
          radius: hitRadius * widget.camera.zoom,
        ),
      );
      if (!rect.overlaps(viewport)) continue;

      final int appCount = constellation.apps.length;
      targets.add(
        _SemanticTarget(
          label: constellation.name,
          hint: constellation.isExpanded
              ? 'Open, $appCount apps. Double tap to close.'
              : '$appCount apps. Double tap to open.',
          rect: rect,
          onTap: () => _activateConstellation(constellation),
          onLongPress: widget.onConstellationLongPressed == null
              ? null
              : () => widget.onConstellationLongPressed!(constellation),
        ),
      );

      // Only the open constellation's apps have distinct positions on screen;
      // a collapsed one is a single hub, and reporting its apps would point a
      // reader at the same spot several times.
      if (constellation.id != openConstellation?.id) continue;

      for (final app in constellation.apps) {
        final appCenter = widget.camera.worldToScreen(app.worldPosition);
        final appRect = _minTarget(
          Rect.fromCircle(
            center: appCenter,
            radius: 32.0 * widget.camera.zoom,
          ),
        );
        if (!appRect.overlaps(viewport)) continue;

        targets.add(
          _SemanticTarget(
            label: app.notificationCount > 0
                ? '${app.label}, ${app.notificationCount} '
                      'notification${app.notificationCount == 1 ? '' : 's'}'
                : app.label,
            hint: 'Open app',
            rect: appRect,
            onTap: () => _activateApp(app),
            onLongPress: widget.onAppLongPressed == null
                ? null
                : () => widget.onAppLongPressed!(app, appCenter),
          ),
        );
      }
    }

    return targets;
  }

  Widget _buildSemanticsLayer(Size size) {
    return Stack(
      children: [
        for (final target in _semanticTargets(size))
          Positioned(
            left: target.rect.left,
            top: target.rect.top,
            width: target.rect.width,
            height: target.rect.height,
            child: Semantics(
              container: true,
              button: true,
              label: target.label,
              hint: target.hint,
              onTap: target.onTap,
              onLongPress: target.onLongPress,
              child: const SizedBox.expand(),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        widget.camera.updateViewportSize(constraints.biggest);

        return Semantics(
          container: true,
          explicitChildNodes: true,
          child: Stack(
            children: [
              Positioned.fill(child: _buildCanvas()),
              // These nodes exist for the screen reader only. They are not
              // wrapped in IgnorePointer, because that would set
              // isBlockingUserActions and strip the tap action back off them,
              // leaving a reader able to hear an app but not open it. They
              // absorb nothing on their own: each is a bare SizedBox, which is
              // not hit-testable, so panning, zooming and dragging still belong
              // to the canvas gestures underneath.
              if (_screenReaderActive)
                Positioned.fill(
                  child: ListenableBuilder(
                    listenable: widget.camera,
                    builder: (context, _) =>
                        _buildSemanticsLayer(constraints.biggest),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  void _onPointerDown(PointerDownEvent event) {
    _activePointers++;
    _markActivity();
  }

  void _onPointerUp(PointerEvent event) {
    if (_activePointers > 0) _activePointers--;
    _markActivity();
  }

  Widget _buildCanvas() {
    // The raw pointer listener sees a touch on its down event, before the
    // gesture arena decides anything, so a resting loop is already running by
    // the time the first drag frame arrives.
    return Listener(
      onPointerDown: _onPointerDown,
      onPointerMove: (_) => _markActivity(),
      onPointerUp: _onPointerUp,
      onPointerCancel: _onPointerUp,
      onPointerSignal: (_) => _markActivity(),
      onPointerPanZoomStart: (_) => _markActivity(),
      onPointerPanZoomUpdate: (_) => _markActivity(),
      child: _buildGestures(),
    );
  }

  Widget _buildGestures() {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapUp: _handleTapUp,
      onLongPressStart: _handleLongPress,
      onScaleStart: (details) {
        _lastFocalPoint = details.localFocalPoint;
        _lastScale = 1.0;
        _accumulatedPanDy = 0.0;
        _accumulatedPanDx = 0.0;
        _magneticTouchWorld = widget.camera.screenToWorld(details.localFocalPoint);
      },
      onScaleUpdate: (details) {
        if (_lastFocalPoint != null) {
          final delta = details.localFocalPoint - _lastFocalPoint!;
          _accumulatedPanDy += delta.dy;
          _accumulatedPanDx += delta.dx;
          widget.camera.applyPan(delta);
          _lastFocalPoint = details.localFocalPoint;
        }

        if (details.scale != 1.0) {
          final scaleDelta = details.scale / _lastScale;
          widget.camera.applyScale(scaleDelta, details.localFocalPoint);
          _lastScale = details.scale;
        }

        _magneticTouchWorld = widget.camera.screenToWorld(details.localFocalPoint);
      },
      onScaleEnd: (details) {
        final vy = details.velocity.pixelsPerSecond.dy;
        final vx = details.velocity.pixelsPerSecond.dx.abs();
        final isFastSwipeDown = vy > 480 && vy > vx * 1.5;
        final isIntentionalDragDown = _accumulatedPanDy > 140 && _accumulatedPanDy > _accumulatedPanDx.abs() * 2.0;

        if ((isFastSwipeDown || isIntentionalDragDown) && widget.onSwipeDown != null) {
          LauncherHaptics.click();
          widget.onSwipeDown!();
        } else {
          widget.camera.onDragEnd(details.velocity);
        }

        _lastFocalPoint = null;
        _lastScale = 1.0;
        _accumulatedPanDy = 0.0;
        _accumulatedPanDx = 0.0;
        _magneticTouchWorld = null;
      },
      child: RepaintBoundary(
        child: CustomPaint(
          size: Size.infinite,
          painter: GalaxyCustomPainter(
            repaint: _paintRepaintNotifier,
            textScaler: MediaQuery.textScalerOf(context),
            camera: widget.camera,
            constellations: widget.layoutEngine.constellations,
            foldable: widget.foldable,
            animationTime: _animationTime,
            starfield: _starfield,
            shootingStars: _shootingStars,
            activeSupernova: _activeSupernova,
            activeTouchScreenPoint: _lastFocalPoint,
            focusedApp: _focusedApp,
            badgeRevision: widget.badgeRevision,
          ),
        ),
      ),
    );
  }
}

/// One focusable point on the galaxy canvas for a screen reader.
class _SemanticTarget {
  final String label;
  final String hint;
  final Rect rect;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const _SemanticTarget({
    required this.label,
    required this.hint,
    required this.rect,
    required this.onTap,
    this.onLongPress,
  });
}
