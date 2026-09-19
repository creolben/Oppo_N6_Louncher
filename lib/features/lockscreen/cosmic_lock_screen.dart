import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import '../../core/foldable_controller.dart';
import '../../models/app_entry.dart';
import '../../core/launcher_bridge.dart';
import '../../models/quick_shortcut.dart';
import '../../ui/widgets/fading_horizontal_scroll.dart';
import 'bouncing_physics_engine.dart';
import 'bouncing_apps_painter.dart';
import 'quick_shortcut_resolver.dart';

class CosmicLockScreen extends StatefulWidget {
  final FoldableController foldable;
  final VoidCallback onUnlock;
  final List<AppEntry> apps;
  final bool initialAuthenticated;

  /// Platform authentication, defaulting to [LauncherBridge.authenticate].
  ///
  /// Injectable because the reader is the side power button: on a real device
  /// the platform keyguard usually authenticates first and this prompt is
  /// cancelled, so a test cannot otherwise hold it open to reproduce that race.
  final Future<bool> Function({String? appName})? authenticate;

  const CosmicLockScreen({
    super.key,
    required this.foldable,
    required this.onUnlock,
    required this.apps,
    this.initialAuthenticated = false,
    this.authenticate,
  });

  @override
  State<CosmicLockScreen> createState() => _CosmicLockScreenState();
}

class _CosmicLockScreenState extends State<CosmicLockScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late AnimationController _slideController;
  late Animation<double> _slideAnimation;
  double _dragOffset = 0.0;
  DateTime _currentTime = DateTime.now();
  late Timer _clockTimer;

  // Bouncing Physics Engine & Ticker
  late final Ticker _physicsTicker;
  Duration _lastElapsed = Duration.zero;
  final BouncingPhysicsEngine _physicsEngine = BouncingPhysicsEngine();
  StreamSubscription? _shakeSubscription;

  // Touch state for dragging / flinging bubbles vs swiping to unlock
  AppBubble? _draggedBubble;
  Offset? _dragStartPos;
  Offset? _lastPointerPos;
  DateTime? _lastPointerTime;
  Offset _pointerVelocity = Offset.zero;
  bool _isDraggingApp = false;
  String? _turbulenceMessage;
  Timer? _turbulenceTimer;

  // Power & Idle Throttling (saves battery on Oppo N6 large OLED screen)
  DateTime _lastInteractionTime = DateTime.now();
  int _physicsFrameCount = 0;

  // Silent fingerprint sensor. The reader is the side power button, not the
  // panel, so the lock screen deliberately draws no fingerprint affordance:
  // no image can be touched to unlock. This flag only records that the sensor
  // already unlocked, which keeps a late platform signal from unlocking twice.
  bool _unlockedBySensor = false;
  StreamSubscription<Map<String, dynamic>>? _fingerprintSubscription;
  bool _disposed = false;

  /// Guards [_armFingerprintSensor] against overlapping runs: two in flight
  /// would each subscribe and cancel, and the loser's cancel would disarm the
  /// session the winner just armed.
  bool _armingFingerprint = false;

  /// The platform will not let an app hold the reader while the panel is off,
  /// and cancels the session the instant it is armed. Arming then does not just
  /// fail, it spends the retry budget, so the lock screen would give up before
  /// the user touched anything and the sensor stayed dead for the rest of the
  /// session. Tracking the real panel state — reported natively from
  /// PowerManager, not inferred from the app lifecycle, which stays resumed
  /// through doze on this build — keeps arming to the moments it can succeed.
  bool _screenInteractive = true;

  /// One bounded re-arm per fresh attempt. The platform preempts an app's
  /// reader session whenever the keyguard is holding the sensor, and retrying
  /// that in a loop produced a burst of cancellations that ended in a dead
  /// affordance; a single retry covers a genuinely transient cancellation
  /// without becoming a storm.
  bool _retriedArm = false;

  Future<bool> _authenticate(String? appName) async {
    final override = widget.authenticate;
    if (override != null) return override(appName: appName);
    return LauncherBridge.authenticate(appName: appName);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 360),
    );

    _slideAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _slideController, curve: Curves.easeOutCubic),
    )..addListener(() {
        setState(() {});
      });

    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      // Hours and minutes are all this renders: repaint when the visible
      // minute rolls over rather than once a second.
      final now = DateTime.now();
      if (!mounted ||
          (now.minute == _currentTime.minute && now.hour == _currentTime.hour)) {
        return;
      }
      setState(() => _currentTime = now);
    });

    // 60/120 FPS Physics simulation loop
    _physicsTicker = createTicker(_onPhysicsTick)..start();

    // Native Android accelerometer shake & gravity tilt stream
    _shakeSubscription = LauncherBridge.getShakeStream().listen((event) {
      if (!mounted) return;
      final type = event['type'] as String? ?? 'tilt';
      if (type == 'shake') {
        _lastInteractionTime = DateTime.now();
        _triggerShakeScatter(
          strength: ((event['magnitude'] as num?)?.toDouble() ?? 12.0) / 10.0,
        );
      } else if (type == 'tilt') {
        final x = (event['x'] as num?)?.toDouble() ?? 0.0;
        final y = (event['y'] as num?)?.toDouble() ?? 0.0;
        // Map phone coordinate system: tilting right (+x) accelerates right (+dx), tilting top toward user accelerates down (+dy)
        // Normal gravity on flat table is ~0 on X, ~0 on Y, ~9.8 on Z.
        final tiltX = (x / 9.8).clamp(-1.0, 1.0);
        final tiltY = (y / 9.8).clamp(-1.0, 1.0);
        _physicsEngine.tiltVector = Offset(-tiltX, tiltY);
        // Subtle tilt activity keeps simulation responsive
        if (tiltX.abs() > 0.15 || tiltY.abs() > 0.15) {
          _lastInteractionTime = DateTime.now();
        }
      }
    });

    // The panel turning on is the first moment the reader can be held again,
    // and it arrives before the activity resumes.
    LauncherBridge.setScreenOnListener(_onScreenOn);
    LauncherBridge.setUserPresentListener(_onUserPresent);
    _armFingerprintSensor();
  }

  /// The platform authenticated someone and the keyguard is gone, so this
  /// overlay clears with it. While the launcher draws over the keyguard its own
  /// reader session is usually preempted, so the platform's success is the
  /// signal that a real touch produced a real unlock — never a bare wake, since
  /// the native side only reports an unlock that followed a locked keyguard.
  void _onUserPresent() {
    if (!mounted || _disposed) return;
    if (_unlockedBySensor) return;
    debugPrint('Platform unlocked a locked keyguard; clearing the overlay');
    HapticFeedback.mediumImpact();
    _unlockedBySensor = true;
    _unlock();
  }

  void _onScreenOn() {
    if (!mounted || _disposed) return;
    _screenInteractive = true;
    _armFingerprintSensor();
  }

  /// Arms the reader as soon as the lock screen appears. Nothing is drawn for
  /// it, by us or by the system: the reader is the side power button, so a
  /// touch on the sensor authenticates and unlocks without any prompt.
  Future<void> _armFingerprintSensor() async {
    if (_armingFingerprint || _disposed) return;
    _armingFingerprint = true;
    _retriedArm = false;
    try {
      final capability = await LauncherBridge.fingerprintCapability();
      if (!mounted || _disposed) return;

      if (!capability.isReady) {
        debugPrint(
          'Fingerprint reader not usable '
          '(hardware: ${capability.hardware}, enrolled: ${capability.enrolled})',
        );
        return;
      }

      // Detach the old subscription before arming: the native onCancel for it
      // calls stopFingerprintScan, which would otherwise disarm what we are
      // about to start.
      await _fingerprintSubscription?.cancel();
      _fingerprintSubscription = null;
      if (!mounted || _disposed) return;

      _fingerprintSubscription = LauncherBridge.fingerprintEvents().listen(
        _onFingerprintEvent,
        onError: (Object error) {
          debugPrint('Fingerprint stream error: $error');
        },
      );
      // The awaits above can outlive a pause: if the panel went away in the
      // meantime, arming now would grab the reader for a backgrounded app and
      // silently swallow the next genuine arm.
      if (!mounted || _disposed || !_screenInteractive) return;
      await LauncherBridge.startFingerprintScan();
    } finally {
      _armingFingerprint = false;
    }
  }

  void _onFingerprintEvent(Map<String, dynamic> event) {
    if (!mounted || _disposed) return;
    _lastInteractionTime = DateTime.now();

    switch (event['type'] as String?) {
      case 'succeeded':
        debugPrint('Fingerprint matched: unlocking');
        _retriedArm = false;
        HapticFeedback.mediumImpact();
        _unlockedBySensor = true;
        _unlock();

      case 'failed':
        // The reader stays armed, so this is a buzz rather than a dead end.
        // Nothing on screen changes: there is no affordance to update.
        debugPrint('Fingerprint did not match');
        _retriedArm = false;
        HapticFeedback.heavyImpact();

      case 'error':
        final code = (event['code'] as num?)?.toInt() ?? -1;
        debugPrint('Fingerprint sensor stopped: $code ${event['message']}');
        if (!_screenInteractive) {
          // Expected while the panel is off. Not a failure, and not worth a
          // retry that the platform would cancel again.
          return;
        }
        if (!_retriedArm) {
          _retriedArm = true;
          LauncherBridge.startFingerprintScan();
          return;
        }
        // The platform would not let this app hold the reader. Swipe-up still
        // works, and the reader is re-armed on the next screen-on or resume.

      case 'screenOff':
        // Refused rather than failed: wait for the panel; re-arming on
        // screen-on will pick the reader back up.
        _screenInteractive = false;

      case 'unavailable':
        debugPrint('Fingerprint reader unavailable');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        // Coming back to the front. Usually this panel was cleared by an
        // unlock, but an app launched from it leaves it up, and that panel is
        // still on screen — so this starts a fresh lock session and it has to
        // accept an unlock, and re-arm the reader, all over again.
        _unlockStarted = false;
        _unlockedBySensor = false;
        // The panel may or may not be on by now; arming is refused cheaply if
        // it is not, and the screen-on broadcast will arm it for real.
        _armFingerprintSensor();
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        // Backgrounded: the platform owns the reader now. Drop it quietly
        // instead of collecting cancellations as failures.
        _screenInteractive = false;
        _fingerprintSubscription?.cancel();
        _fingerprintSubscription = null;
        LauncherBridge.stopFingerprintScan();
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        // Transient (a dialog, the notification shade): leave the session be.
        break;
    }
  }

  void _onPhysicsTick(Duration elapsed) {
    if (_lastElapsed == Duration.zero) {
      _lastElapsed = elapsed;
      return;
    }
    final double dt = (elapsed - _lastElapsed).inMicroseconds / 1000000.0;
    _lastElapsed = elapsed;

    // Idle Battery Saver: After 12s without touch or active movement, throttle to 30 FPS
    final isIdle = DateTime.now().difference(_lastInteractionTime).inSeconds > 12;
    _physicsFrameCount++;
    if (isIdle && (_physicsFrameCount % 3 != 0)) {
      return;
    }

    _physicsEngine.update(dt);
    if (mounted) {
      setState(() {});
    }
  }

  AppCategory? _selectedCategory;

  List<AppEntry> get _filteredApps {
    if (_selectedCategory == null) {
      return widget.apps;
    }
    final filtered = widget.apps.where((a) => a.category == _selectedCategory).toList();
    return filtered.isNotEmpty ? filtered : widget.apps;
  }

  void _onCategorySelected(AppCategory? cat) {
    if (_selectedCategory == cat) return;
    setState(() {
      _selectedCategory = cat;
    });
    HapticFeedback.selectionClick();
    if (_physicsEngine.viewportSize != Size.zero) {
      _physicsEngine.initializeBubbles(
        apps: _filteredApps,
        size: _physicsEngine.viewportSize,
        padding: _physicsEngine.safePadding,
      );
    }
  }

  void _ensurePhysicsInitialized(Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    final padding = EdgeInsets.fromLTRB(
      20.0,
      size.height * 0.28, // Room below top clock & category filters
      20.0,
      210.0, // Room above the gesture hints and quick shortcuts
    );

    if (_physicsEngine.bubbles.isEmpty) {
      _physicsEngine.initializeBubbles(
        apps: _filteredApps,
        size: size,
        padding: padding,
      );
    } else if (_physicsEngine.viewportSize != size) {
      _physicsEngine.resize(size, padding: padding);
    }
  }

  void _triggerShakeScatter({double strength = 1.0, Offset? focalPoint}) {
    HapticFeedback.heavyImpact();
    _physicsEngine.triggerShakeScatter(
      strength: strength.clamp(0.8, 2.2),
      focalPoint: focalPoint,
    );

    setState(() {
      _turbulenceMessage = '⚡ COSMIC SHAKE DETECTED • APPS DISPERSED';
    });
    _turbulenceTimer?.cancel();
    _turbulenceTimer = Timer(const Duration(milliseconds: 2200), () {
      if (mounted) {
        setState(() {
          _turbulenceMessage = null;
        });
      }
    });
  }

  // Pointer event handlers
  void _onPointerDown(PointerDownEvent event) {
    _lastInteractionTime = DateTime.now();
    final hit = _physicsEngine.findBubbleAt(event.localPosition);
    if (hit != null) {
      _draggedBubble = hit;
      _draggedBubble!.isBeingDragged = true;
      _isDraggingApp = true;
      _dragStartPos = event.localPosition;
      _lastPointerPos = event.localPosition;
      _lastPointerTime = DateTime.now();
      _pointerVelocity = Offset.zero;
      HapticFeedback.selectionClick();
    } else {
      _isDraggingApp = false;
      _dragStartPos = event.localPosition;
    }
  }

  void _onPointerMove(PointerMoveEvent event) {
    _lastInteractionTime = DateTime.now();
    final now = DateTime.now();
    if (_isDraggingApp && _draggedBubble != null) {
      if (_lastPointerPos != null && _lastPointerTime != null) {
        final double dt = (now.difference(_lastPointerTime!).inMicroseconds) / 1000000.0;
        if (dt > 0.002) {
          _pointerVelocity = (event.localPosition - _lastPointerPos!) / dt;
        }
      }
      _lastPointerPos = event.localPosition;
      _lastPointerTime = now;
      _draggedBubble!.position = event.localPosition;
    } else if (!_isDraggingApp) {
      // Swiping up on background
      final dy = event.delta.dy;
      setState(() {
        _dragOffset = (_dragOffset - dy).clamp(0.0, 600.0);
      });
    }
  }

  void _onPointerUp(PointerUpEvent event) {
    if (_isDraggingApp && _draggedBubble != null) {
      final appToLaunch = _draggedBubble!.app;
      final bool wasTap = _dragStartPos != null &&
          (event.localPosition - _dragStartPos!).distance < 12.0;

      _draggedBubble!.isBeingDragged = false;

      if (wasTap) {
        // Tapped bouncy app directly: authenticate & launch!
        _draggedBubble = null;
        _isDraggingApp = false;
        _unlockAndLaunchApp(appToLaunch);
        return;
      }

      // Thrown / fling momentum
      if (_pointerVelocity.distance > 80.0) {
        final double speed = _pointerVelocity.distance.clamp(100.0, 1500.0);
        _draggedBubble!.velocity = (_pointerVelocity / _pointerVelocity.distance) * speed;
      }
      _draggedBubble = null;
      _isDraggingApp = false;
    } else if (!_isDraggingApp) {
      if (_dragOffset > 140.0) {
        // Anyone can swipe up to enter the launcher
        _unlock();
      } else {
        _snapBack();
      }
    }
  }

  /// The app a shortcut or bubble asked to open, held until authentication
  /// finishes — by whichever path gets there first.
  ///
  /// The reader is the side power button, so the platform keyguard owns the
  /// sensor and normally authenticates before this overlay's own prompt does:
  /// it reports `userPresent`, or a silent sensor success, and both used to
  /// clear the overlay without launching anything. Remembering the request is
  /// what makes "open the dialer" survive that ordering — without it the user
  /// authenticates and lands back on a lock surface with no app opened.
  AppEntry? _pendingLaunch;

  /// Set while the overlay is unlocking, so a second authentication path
  /// arriving late can neither unlock twice nor launch twice.
  bool _unlockStarted = false;

  Future<void> _unlock() async {
    if (_unlockStarted || _disposed) return;
    _unlockStarted = true;
    HapticFeedback.lightImpact();

    final pending = _pendingLaunch;
    _pendingLaunch = null;

    if (pending != null) {
      // Launch with this panel still up, and leave it up.
      //
      // It is the only cover over the ColorOS lock screen, so dropping it
      // during the handoff exposed the system keyguard — and dropping it at
      // all meant closing the launched app landed the user behind the panel
      // instead of back on it. Staying locked is also what a lock-screen
      // shortcut should do: the app opens, and closing it returns here.
      final launched = await LauncherBridge.launchApp(pending);
      if (!mounted) return;
      if (!launched) {
        // Nothing opened, so this panel never went anywhere. Make it usable
        // again and say so.
        _unlockStarted = false;
        _showTurbulence('COULD NOT OPEN ${pending.label.toUpperCase()}');
      }
      return;
    }

    _slideAnimation = Tween<double>(begin: _dragOffset, end: 900.0).animate(
      CurvedAnimation(parent: _slideController, curve: Curves.easeInCubic),
    );
    await _slideController.forward(from: 0.0);
    if (!mounted) return;
    widget.onUnlock();
  }

  void _snapBack() {
    _slideAnimation = Tween<double>(begin: _dragOffset, end: 0.0).animate(
      CurvedAnimation(parent: _slideController, curve: Curves.easeOutBack),
    );
    _slideController.forward(from: 0.0).then((_) {
      _dragOffset = 0.0;
    });
  }

  Future<void> _unlockAndLaunchApp(AppEntry app) async {
    HapticFeedback.lightImpact();
    // Record the request before authenticating. The platform keyguard may
    // answer the touch itself and unlock via _onUserPresent, cancelling this
    // prompt; the request has to outlive that.
    _pendingLaunch = app;

    final authenticated = await _authenticate(app.label);
    // Another path already authenticated and is sliding the overlay away; its
    // completion owns the pending launch now.
    if (!mounted || _disposed || _unlockStarted) return;

    if (!authenticated) {
      _pendingLaunch = null;
      _showTurbulence('AUTH REQUIRED TO LAUNCH ${app.label.toUpperCase()}');
      return;
    }

    HapticFeedback.mediumImpact();
    _unlock();
  }

  /// Opens the phone or camera shortcut.
  ///
  /// The target is resolved from the installed app list rather than from a
  /// hard-coded package name: no package name is portable, and the two this
  /// used to name (`com.android.phone`, `com.android.camera`) are respectively
  /// not launchable and not installed on the tested device.
  Future<void> _openQuickShortcut(QuickShortcut shortcut) async {
    final target = QuickShortcutResolver.resolve(shortcut, widget.apps);

    if (target != null) {
      debugPrint(
        'Quick shortcut ${shortcut.name}: ${target.label} '
        '(${target.packageName}/${target.activityName})',
      );
      await _unlockAndLaunchApp(target);
      return;
    }

    // The list holds LAUNCHER activities only and is empty until the first
    // scan finishes, so the shortcut can be tapped before it can be resolved.
    // Ask the platform for its own handler instead of going dead.
    debugPrint('Quick shortcut ${shortcut.name}: no app matched, asking platform');
    if (await LauncherBridge.openQuickShortcut(shortcut)) {
      HapticFeedback.mediumImpact();
      _unlock();
      return;
    }

    _showTurbulence('NO ${shortcut.label.toUpperCase()} APP FOUND');
  }

  void _showTurbulence(String message) {
    if (!mounted) return;
    setState(() {
      _turbulenceMessage = message;
    });
    _turbulenceTimer?.cancel();
    _turbulenceTimer = Timer(const Duration(milliseconds: 2500), () {
      if (mounted) {
        setState(() {
          _turbulenceMessage = null;
        });
      }
    });
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _clockTimer.cancel();
    _turbulenceTimer?.cancel();
    _fingerprintSubscription?.cancel();
    LauncherBridge.setScreenOnListener(null);
    LauncherBridge.setUserPresentListener(null);
    LauncherBridge.stopFingerprintScan();
    _physicsTicker.dispose();
    _slideController.dispose();
    _shakeSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    _ensurePhysicsInitialized(screenSize);

    final currentOffset = _slideController.isAnimating ? _slideAnimation.value : _dragOffset;
    final double unlockProgress = (currentOffset / 300.0).clamp(0.0, 1.0);
    final double opacity = (1.0 - (unlockProgress * 0.85)).clamp(0.0, 1.0);

    final timeHour = _currentTime.hour.toString().padLeft(2, '0');
    final timeMinute = _currentTime.minute.toString().padLeft(2, '0');
    final dateFormatted =
        '${_weekdayName(_currentTime.weekday)}, ${_monthName(_currentTime.month)} ${_currentTime.day}';

    final isTabletop = widget.foldable.isTabletop;
    final isUnfolded = !widget.foldable.isFolded && screenSize.width > 550;

    return Transform.translate(
      offset: Offset(0, -currentOffset),
      child: Opacity(
        opacity: opacity,
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: _onPointerDown,
          onPointerMove: _onPointerMove,
          onPointerUp: _onPointerUp,
          child: Container(
            width: double.infinity,
            height: double.infinity,
            decoration: const BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(0.0, -0.2),
                radius: 1.3,
                colors: [
                  Color(0xFF0D1426), // Deep cosmic glow
                  Color(0xFF070A14), // Dark indigo void
                  Color(0xFF020306), // Pitch black OLED
                ],
                stops: [0.0, 0.55, 1.0],
              ),
            ),
            child: Stack(
              children: [
                // Ambient Celestial Halo
                Positioned(
                  top: screenSize.height * 0.12,
                  left: screenSize.width * 0.5 - 150,
                  child: IgnorePointer(
                    child: Container(
                      width: 300,
                      height: 300,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            Color(0x3300E5FF),
                            Color(0x1564B5F6),
                            Colors.transparent,
                          ],
                          stops: [0.0, 0.45, 1.0],
                        ),
                      ),
                    ),
                  ),
                ),

                // CustomPaint Canvas rendering bouncing apps
                Positioned.fill(
                  child: CustomPaint(
                    painter: BouncingAppsPainter(
                      physics: _physicsEngine,
                      animationProgress: _lastElapsed.inMilliseconds / 1000.0,
                      draggedBubble: _draggedBubble,
                    ),
                  ),
                ),

                // Scrim: keeps the unlock cluster and gesture hints readable
                // while bouncing bubbles keep moving behind them.
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: 260,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            const Color(0xFF020306).withValues(alpha: 0.0),
                            const Color(0xFF020306).withValues(alpha: 0.72),
                            const Color(0xFF020306),
                          ],
                          stops: const [0.0, 0.5, 1.0],
                        ),
                      ),
                    ),
                  ),
                ),

                // Foreground HUD (Telemetry, Clock, Hints, and Quick Docks)
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 14.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Top Telemetry Bar with interactive Shake Trigger Button
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.lock_outline_rounded,
                                  color: Color(0xFF00E5FF),
                                  size: 16,
                                ),
                                SizedBox(width: 6),
                                Text(
                                  'LOCKED',
                                  style: TextStyle(
                                    color: Color(0xFF00E5FF),
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 1.5,
                                  ),
                                ),
                              ],
                            ),

                            // Interactive Shake / Scatter Button
                            GestureDetector(
                              onTap: () => _triggerShakeScatter(),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(
                                  color: const Color(0x3300E5FF),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: const Color(0x6600E5FF), width: 1.0),
                                  boxShadow: const [
                                    BoxShadow(color: Color(0x2200E5FF), blurRadius: 8),
                                  ],
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.vibration_rounded, color: Color(0xFF00E5FF), size: 14),
                                    SizedBox(width: 4),
                                    Text(
                                      'SHAKE',
                                      style: TextStyle(
                                        color: Color(0xFF00E5FF),
                                        fontSize: 9,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 1.2,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),

                            Row(
                              children: [
                                const Icon(Icons.battery_charging_full_rounded, color: Colors.white70, size: 16),
                                const SizedBox(width: 4),
                                Text(
                                  '92%',
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.8),
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),

                        const SizedBox(height: 12),

                        // Centerpiece Cosmic Clock HUD (wrapped in IgnorePointer to allow bubble interaction)
                        IgnorePointer(
                          child: Column(
                            children: [
                              Text(
                                '$timeHour:$timeMinute',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: isTabletop ? 52 : (isUnfolded ? 76 : 64),
                                  fontWeight: FontWeight.w100,
                                  letterSpacing: -2.0,
                                  height: 1.0,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                  shadows: const [
                                    Shadow(color: Color(0x6600E5FF), blurRadius: 26),
                                    Shadow(color: Colors.black, blurRadius: 12),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                dateFormatted.toUpperCase(),
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.8),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 2.8,
                                  shadows: const [
                                    Shadow(color: Colors.black, blurRadius: 8),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 10),
                              if (_turbulenceMessage != null)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: const Color(0xCC7C4DFF),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(color: const Color(0xFFB388FF), width: 1.0),
                                    boxShadow: const [
                                      BoxShadow(color: Color(0x667C4DFF), blurRadius: 16),
                                    ],
                                  ),
                                  child: Text(
                                    _turbulenceMessage!,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 1.0,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 12),
                        // Interactive Curated Category Chips Bar
                        FadingHorizontalScroll(
                          center: true,
                          fadeColor: const Color(0xFF090D1A),
                          children: [
                            _categoryFilterChip('★ Featured', null),
                            const SizedBox(width: 8),
                            _categoryFilterChip('Core', AppCategory.core),
                            const SizedBox(width: 8),
                            _categoryFilterChip('Social', AppCategory.social),
                            const SizedBox(width: 8),
                            _categoryFilterChip('Media', AppCategory.entertainment),
                            const SizedBox(width: 8),
                            _categoryFilterChip('Work', AppCategory.productivity),
                            const SizedBox(width: 8),
                            _categoryFilterChip('Tools', AppCategory.tools),
                          ],
                        ),

                        const Spacer(),

                        // Secondary gesture hints: the reader is the side power
                        // button, so no fingerprint affordance is drawn here or
                        // anywhere else on the panel.
                        IgnorePointer(
                          child: Column(
                            children: [
                              const Icon(
                                Icons.keyboard_arrow_up_rounded,
                                color: Color(0xFF00E5FF),
                                size: 22,
                              ),
                              Text(
                                'TAP APP TO LAUNCH • SWIPE UP TO ENTER',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.72),
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.6,
                                  shadows: const [
                                    Shadow(color: Colors.black, blurRadius: 6),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 14),

                        // Quick shortcuts: phone on the left, camera on the
                        // right. Nothing sits between them, so the swipe-up
                        // gesture has clear panel to travel across.
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            _quickActionCircle(
                              icon: Icons.phone_rounded,
                              tooltip: 'Open Phone',
                              onTap: () =>
                                  _openQuickShortcut(QuickShortcut.phone),
                            ),
                            _quickActionCircle(
                              icon: Icons.camera_alt_rounded,
                              tooltip: 'Open Camera',
                              onTap: () =>
                                  _openQuickShortcut(QuickShortcut.camera),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _quickActionCircle({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(28),
            child: Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0x8A11172A),
                border: Border.all(
                  color: const Color(0x4DFFFFFF),
                  width: 1.0,
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x66000000),
                    blurRadius: 14,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: Icon(icon, color: Colors.white, size: 23),
            ),
          ),
        ),
      ),
    );
  }



  Widget _categoryFilterChip(String label, AppCategory? category) {
    final bool isSelected = _selectedCategory == category;
    return Semantics(
      button: true,
      selected: isSelected,
      label: '$label apps',
      child: GestureDetector(
        onTap: () => _onCategorySelected(category),
        child: Container(
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isSelected ? const Color(0x3D00E5FF) : const Color(0x3310172C),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isSelected ? const Color(0xFF00E5FF) : const Color(0x2EFFFFFF),
              width: isSelected ? 1.2 : 0.8,
            ),
            boxShadow: isSelected
                ? const [
                    BoxShadow(
                      color: Color(0x3300E5FF),
                      blurRadius: 10,
                      offset: Offset(0, 3),
                    ),
                  ]
                : null,
          ),
          child: Text(
            label,
            style: TextStyle(
              color: isSelected ? const Color(0xFF00E5FF) : Colors.white70,
              fontSize: 10,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              letterSpacing: 0.5,
            ),
          ),
        ),
      ),
    );
  }

  String _weekdayName(int day) {
    const names = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    return names[(day - 1) % 7];
  }

  String _monthName(int month) {
    const names = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    return names[(month - 1) % 12];
  }
}
