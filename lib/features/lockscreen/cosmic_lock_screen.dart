import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import '../../core/foldable_controller.dart';
import '../../models/app_entry.dart';
import '../../core/launcher_bridge.dart';
import '../../ui/widgets/fading_horizontal_scroll.dart';
import 'bouncing_physics_engine.dart';
import 'bouncing_apps_painter.dart';

/// State of the lock screen's fingerprint sensor.
enum _FingerprintStatus {
  /// This app holds the reader and it is waiting for a finger.
  listening,

  /// A finger touched the sensor but did not match.
  failed,

  /// Matched: the lock screen is unlocking.
  granted,

  /// No reader, nothing enrolled, or the reader could not be held.
  unavailable,
}

/// Diameter of the on-screen fingerprint affordance.
///
/// The reader on this device class is the side power button rather than an
/// under-display sensor (the platform reports `sensorType: side`), so this is
/// an indicator that names the sensor rather than a target the user is meant
/// to press: the screen is not the reader.
const double _fingerprintAffordanceSize = 60.0;

/// How many times a failed session is retried before the affordance admits the
/// reader is not available to this app.
const int _maxFingerprintRearms = 2;

class CosmicLockScreen extends StatefulWidget {
  final FoldableController foldable;
  final VoidCallback onUnlock;
  final List<AppEntry> apps;
  final bool initialAuthenticated;

  const CosmicLockScreen({
    super.key,
    required this.foldable,
    required this.onUnlock,
    required this.apps,
    this.initialAuthenticated = false,
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

  // Silent fingerprint sensor (the lock screen is its UI)
  _FingerprintStatus _fingerprintStatus = _FingerprintStatus.unavailable;
  StreamSubscription<Map<String, dynamic>>? _fingerprintSubscription;
  Timer? _fingerprintResetTimer;
  bool _disposed = false;

  /// Consecutive automatic re-arms after a sensor error, so a transient
  /// cancellation recovers without a reader that keeps failing being re-armed
  /// forever. Any real read resets it.
  int _fingerprintRearms = 0;

  /// Guards [_armFingerprintSensor] against overlapping runs: two in flight
  /// would each subscribe and cancel, and the loser's cancel would disarm the
  /// session the winner just armed.
  bool _armingFingerprint = false;

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

    _armFingerprintSensor();
  }

  /// Arms the reader as soon as the lock screen appears. Nothing is drawn by
  /// the system: the fingerprint affordance below is the whole UI, so a touch
  /// on the sensor authenticates and unlocks without any prompt.
  Future<void> _armFingerprintSensor() async {
    if (_armingFingerprint || _disposed) return;
    _armingFingerprint = true;
    // A deliberate arm — on mount, or back from the background — is a fresh
    // attempt, so it gets the full retry budget again instead of inheriting a
    // spent one and reporting a working reader as unavailable.
    _fingerprintRearms = 0;
    try {
      final capability = await LauncherBridge.fingerprintCapability();
      if (!mounted || _disposed) return;

      if (!capability.isReady) {
        debugPrint(
          'Fingerprint reader not usable '
          '(hardware: ${capability.hardware}, enrolled: ${capability.enrolled})',
        );
        setState(() => _fingerprintStatus = _FingerprintStatus.unavailable);
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
          if (mounted) {
            setState(() => _fingerprintStatus = _FingerprintStatus.unavailable);
          }
        },
      );
      setState(() => _fingerprintStatus = _FingerprintStatus.listening);
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
        _fingerprintRearms = 0;
        HapticFeedback.mediumImpact();
        setState(() => _fingerprintStatus = _FingerprintStatus.granted);
        _unlock();

      case 'failed':
        // The reader stays armed, so this is feedback, not a dead end.
        debugPrint('Fingerprint did not match');
        _fingerprintRearms = 0;
        HapticFeedback.heavyImpact();
        _fingerprintResetTimer?.cancel();
        setState(() => _fingerprintStatus = _FingerprintStatus.failed);
        _fingerprintResetTimer = Timer(const Duration(milliseconds: 1800), () {
          if (mounted) {
            setState(() => _fingerprintStatus = _FingerprintStatus.listening);
          }
        });

      case 'error':
        final code = (event['code'] as num?)?.toInt() ?? -1;
        debugPrint('Fingerprint sensor stopped: $code ${event['message']}');
        _fingerprintResetTimer?.cancel();
        // A cancelled or transiently failed session is worth one retry, but a
        // reader that keeps failing must not be re-armed forever, and the
        // affordance must not claim a session this app does not hold.
        if (_fingerprintRearms < _maxFingerprintRearms) {
          _fingerprintRearms++;
          setState(() => _fingerprintStatus = _FingerprintStatus.listening);
          _fingerprintResetTimer = Timer(const Duration(milliseconds: 600), () {
            if (mounted && !_disposed) {
              LauncherBridge.startFingerprintScan();
            }
          });
          return;
        }
        setState(() => _fingerprintStatus = _FingerprintStatus.unavailable);

      case 'unavailable':
        _fingerprintResetTimer?.cancel();
        setState(() => _fingerprintStatus = _FingerprintStatus.unavailable);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // A backgrounded app loses the reader, so arm it again on the way back in.
    if (state == AppLifecycleState.resumed &&
        _fingerprintStatus != _FingerprintStatus.granted) {
      _armFingerprintSensor();
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
      210.0, // Room above the fingerprint sensor, hints and quick shortcuts
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

  void _unlock({VoidCallback? onComplete}) {
    HapticFeedback.lightImpact();
    _slideAnimation = Tween<double>(begin: _dragOffset, end: 900.0).animate(
      CurvedAnimation(parent: _slideController, curve: Curves.easeInCubic),
    );
    _slideController.forward(from: 0.0).then((_) {
      widget.onUnlock();
      onComplete?.call();
    });
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
    // Prompt biometric authentication for launching this specific app
    final authenticated = await LauncherBridge.authenticate(appName: app.label);
    if (!authenticated) {
      if (mounted) {
        setState(() {
          _turbulenceMessage = 'AUTH REQUIRED TO LAUNCH ${app.label.toUpperCase()}';
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
      return;
    }

    HapticFeedback.mediumImpact();
    _unlock(onComplete: () {
      LauncherBridge.launchApp(app);
    });
  }

  Future<void> _launchQuickApp(String packageName) async {
    // The shortcut circles render before the app list has loaded, so there may
    // be nothing to resolve yet.
    if (widget.apps.isEmpty) return;
    final app = widget.apps.firstWhere(
      (a) => a.packageName == packageName,
      orElse: () => widget.apps.first,
    );
    await _unlockAndLaunchApp(app);
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _clockTimer.cancel();
    _turbulenceTimer?.cancel();
    _fingerprintResetTimer?.cancel();
    _fingerprintSubscription?.cancel();
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

                        // Secondary gesture hints. The fingerprint affordance
                        // is not part of this column: it floats over the reader
                        // itself, further down.
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

                        // Quick shortcuts flanking the fingerprint indicator.
                        // The reader is the side power button, so the indicator
                        // names the sensor instead of asking for a screen press.
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            _quickActionCircle(
                              icon: Icons.phone_rounded,
                              tooltip: 'Open Phone',
                              onTap: () => _launchQuickApp('com.android.phone'),
                            ),
                            // Never a tap target: the swipe-up-to-unlock
                            // gesture has to pass straight through it.
                            IgnorePointer(
                              child: _FingerprintIndicator(
                                status: _fingerprintStatus,
                              ),
                            ),
                            _quickActionCircle(
                              icon: Icons.camera_alt_rounded,
                              tooltip: 'Open Camera',
                              onTap: () => _launchQuickApp('com.android.camera'),
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

/// On-screen fingerprint affordance.
///
/// The reader itself is armed by the lock screen, so this is an indicator
/// rather than a button: it marks where the sensor sits, breathes while it is
/// listening, and reports the outcome of a touch. Nothing here opens a system
/// prompt.
class _FingerprintIndicator extends StatefulWidget {
  final _FingerprintStatus status;

  const _FingerprintIndicator({required this.status});

  @override
  State<_FingerprintIndicator> createState() => _FingerprintIndicatorState();
}

class _FingerprintIndicatorState extends State<_FingerprintIndicator>
    with TickerProviderStateMixin {
  late final AnimationController _pulse;
  late final AnimationController _shake;

  /// Built once: a [CurvedAnimation] created inside build() would add a status
  /// listener on every rebuild, and this widget rebuilds with the physics loop.
  late final Animation<double> _shakeOffset = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: 0.0, end: -7.0), weight: 1),
    TweenSequenceItem(tween: Tween(begin: -7.0, end: 6.0), weight: 1),
    TweenSequenceItem(tween: Tween(begin: 6.0, end: -4.0), weight: 1),
    TweenSequenceItem(tween: Tween(begin: -4.0, end: 0.0), weight: 1),
  ]).animate(CurvedAnimation(parent: _shake, curve: Curves.easeOut));

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat();
    _shake = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
  }

  @override
  void didUpdateWidget(covariant _FingerprintIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.status == _FingerprintStatus.failed &&
        oldWidget.status != _FingerprintStatus.failed) {
      _shake.forward(from: 0.0);
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    _shake.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final status = widget.status;
    final bool failed = status == _FingerprintStatus.failed;
    final bool granted = status == _FingerprintStatus.granted;
    final bool unavailable = status == _FingerprintStatus.unavailable;
    final Color tint = failed
        ? const Color(0xFFFF5252)
        : (unavailable ? const Color(0x8AFFFFFF) : const Color(0xFF00E5FF));

    final String label = switch (status) {
      _FingerprintStatus.listening => 'TOUCH SENSOR TO UNLOCK',
      _FingerprintStatus.failed => 'NOT RECOGNIZED • TOUCH AGAIN',
      _FingerprintStatus.granted => 'UNLOCKED',
      _FingerprintStatus.unavailable => 'FINGERPRINT UNAVAILABLE',
    };

    return Semantics(
      // liveRegion announces the status changes; the label text below is the
      // node's own name, so it is not repeated here as well.
      container: true,
      liveRegion: true,
      child: SizedBox(
        // Bounded so the quick shortcuts either side can never be pushed off
        // the panel by a long status label.
        width: _fingerprintAffordanceSize + 96,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
          Transform.translate(
            offset: Offset(_shakeOffset.value, 0),
            child: SizedBox(
              width: _fingerprintAffordanceSize + 32,
              height: _fingerprintAffordanceSize + 32,
              child: AnimatedBuilder(
                animation: Listenable.merge([_pulse, _shake]),
                builder: (context, child) {
                  return CustomPaint(
                    painter: _SensorPulsePainter(
                      // A dead reader has nothing to breathe for.
                      phase: unavailable ? 0.35 : _pulse.value,
                      color: tint,
                      intensity: unavailable ? 0.25 : (failed ? 0.7 : 0.55),
                    ),
                    child: child,
                  );
                },
                child: Center(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    width: _fingerprintAffordanceSize,
                    height: _fingerprintAffordanceSize,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: tint.withValues(alpha: granted ? 0.26 : 0.12),
                      border: Border.all(
                        color: tint.withValues(alpha: granted ? 1.0 : 0.8),
                        width: granted ? 2.0 : 1.4,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: tint.withValues(alpha: granted ? 0.5 : 0.3),
                          blurRadius: granted ? 26 : 18,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Icon(
                      granted
                          ? Icons.lock_open_rounded
                          : Icons.fingerprint_rounded,
                      color: tint,
                      size: granted ? 28 : 30,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 2),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 160),
            child: Text(
              label,
              key: ValueKey(label),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: tint,
                fontSize: 9.5,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.3,
                shadows: const [Shadow(color: Colors.black, blurRadius: 6)],
              ),
            ),
          ),
        ],
      ),
      ),
    );
  }
}

/// Sonar rings under the sensor disc, breathing while the reader is armed.
class _SensorPulsePainter extends CustomPainter {
  final double phase;
  final Color color;
  final double intensity;

  const _SensorPulsePainter({
    required this.phase,
    required this.color,
    required this.intensity,
  });

  /// Reused across paints: this runs every frame on a 120 Hz panel.
  static final Paint _ring = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.2;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);

    for (var i = 0; i < 2; i++) {
      final p = (phase + i * 0.5) % 1.0;
      _ring.color = color.withValues(alpha: (1.0 - p) * intensity * 0.55);
      canvas.drawCircle(
        center,
        _fingerprintAffordanceSize / 2 + 4.0 + p * 12.0,
        _ring,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SensorPulsePainter oldDelegate) {
    return oldDelegate.phase != phase ||
        oldDelegate.color != color ||
        oldDelegate.intensity != intensity;
  }
}
