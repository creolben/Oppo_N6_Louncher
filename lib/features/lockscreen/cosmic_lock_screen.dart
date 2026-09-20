import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import '../../core/foldable_controller.dart';
import '../../models/app_entry.dart';
import '../../core/launcher_bridge.dart';
import '../../models/quick_shortcut.dart';
import '../../ui/widgets/fading_horizontal_scroll.dart';
import 'bouncing_physics_engine.dart';
import 'bouncing_apps_painter.dart';
import 'fingerprint_prompt.dart';
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

  /// The silent fingerprint reader, defaulting to the platform channel.
  ///
  /// Injectable for the same reason as [authenticate]: no Android platform
  /// channel exists on the test host, so without these the panel's own prompt —
  /// the part of this file that has to be right — could not be exercised at
  /// all, and every test would silently take the credential fallback instead.
  final Future<FingerprintCapability> Function()? fingerprintCapability;
  final Stream<Map<String, dynamic>> Function()? fingerprintEvents;

  /// The platform's own credential prompt, defaulting to
  /// [LauncherBridge.authenticate].
  ///
  /// Separate from [authenticate] so a test can hold *this* prompt open — with
  /// [authenticate] it would bypass the panel's reader entirely — and observe
  /// what the card does while the platform is asking.
  final Future<bool> Function({String? appName})? authenticateWithCredential;

  /// Real keyguard locked state, defaulting to [LauncherBridge.isKeyguardLocked].
  final Future<bool> Function()? isKeyguardLocked;

  const CosmicLockScreen({
    super.key,
    required this.foldable,
    required this.onUnlock,
    required this.apps,
    this.initialAuthenticated = false,
    this.authenticate,
    this.fingerprintCapability,
    this.fingerprintEvents,
    this.authenticateWithCredential,
    this.isKeyguardLocked,
  });

  @override
  State<CosmicLockScreen> createState() => _CosmicLockScreenState();
}

class _CosmicLockScreenState extends State<CosmicLockScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late AnimationController _slideController;
  late Animation<double> _slideAnimation;
  /// How far the panel has been pulled up, by drag or by the unlock slide.
  ///
  /// A [ValueNotifier] on purpose: the only thing this value moves is a
  /// `Transform.translate` and the opacity derived from it, so animating it
  /// re-evaluates that one builder instead of rebuilding the whole lock screen
  /// at up to 120Hz.
  final ValueNotifier<double> _panelOffset = ValueNotifier<double>(0.0);
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

  /// The app the cosmic fingerprint prompt is currently authenticating for.
  ///
  /// Non-null is what puts the prompt on screen *and* what makes the panel
  /// underneath ignore touches, so it is cleared in exactly one place:
  /// [_resolveAuth].
  AppEntry? _authTarget;

  /// The app waiting on the reader, before the prompt is drawn.
  ///
  /// The prompt becomes visible only once the platform actually hands the
  /// reader over (`listening`). On a device that will not let this panel hold
  /// the sensor at all — the tested ColorOS build cancels an app's reader
  /// session outright while the keyguard is occluded — the card therefore never
  /// appears, and the request goes straight to the platform prompt, which is
  /// the only authentication that keyguard accepts.
  AppEntry? _authWanted;

  /// What the prompt is telling the user right now.
  FingerprintPromptPhase _authPhase = FingerprintPromptPhase.scanning;

  /// Resolves the pending [_authenticate] call.
  ///
  /// The prompt is only a face over one future, so it is completed by whichever
  /// answers first: a sensor match, the themed cancel button, the device
  /// credential fallback, or the panel closing underneath it.
  Completer<bool>? _authCompleter;

  /// Holds the "VERIFIED" state on screen for a beat before handing off, so a
  /// match reads as an answer rather than as the panel blinking.
  Timer? _authResolveTimer;

  /// True while a launch is being handed to the platform.
  ///
  /// The reader is deliberately released for that handoff so the system
  /// keyguard can take the sensor over; without this flag the panel's own
  /// re-arm and retry would grab it straight back and the keyguard would never
  /// see the finger that is still resting on the sensor.
  bool _handingOffLaunch = false;

  Future<bool> _authenticate(String? appName) async {
    final override = widget.authenticate;
    if (override != null) return override(appName: appName);

    // The panel draws its own prompt only where it can actually read the
    // sensor. Where it cannot — no finger enrolled, or no reader at all — the
    // platform's credential prompt is the only honest way forward.
    final capability = await (widget.fingerprintCapability ??
        LauncherBridge.fingerprintCapability)();
    if (!mounted || _disposed) return false;
    if (!capability.isReady) {
      return LauncherBridge.authenticate(appName: appName);
    }
    return _authenticateWithSensor();
  }

  /// Raises the reader and waits for it to report that it is listening.
  ///
  /// A session that is already armed is used as it stands: the reader that
  /// unlocked this panel with a bare touch is the same reader that is about to
  /// open the app, and re-arming it would cancel it.
  Future<bool> _authenticateWithSensor() {
    final AppEntry? target = _pendingLaunch;
    if (target == null) return Future<bool>.value(false);
    final completer = Completer<bool>();
    _authCompleter = completer;
    _authWanted = target;
    // A deliberate request gets a fresh budget: the single retry exists for a
    // genuinely transient cancellation, not for a session that already spent it
    // while the panel sat idle.
    _retriedArm = false;

    // Raise the card immediately, whatever the reader turns out to be able to
    // do. The card is the answer to "launch this app" — it names the app the
    // finger is unlocking — and waiting to find out whether the sensor is
    // available before showing it produced a dead beat between the tap and any
    // visible response, which read as the tap having been ignored.
    //
    // On a locked device the reader is refused and the request is handed to the
    // platform prompt, which draws over this card. The card is still correct
    // there: it is what the user sees as the result of their tap, and it is
    // torn down by _resolveAuth whichever way the authentication lands.
    if (mounted) {
      setState(() {
        _authTarget = target;
        _authPhase = FingerprintPromptPhase.scanning;
      });
    }

    if (_sensorArmed) {
      // Already listening: the card is up and the live session will answer it.
      // Re-arming would cancel the session the user is about to touch.
    } else if (_sensorUnusable) {
      // The platform refuses in-app reader sessions while locked because the
      // system keyguard owns the power button sensor. We do NOT immediately
      // invoke the system credential prompt (which pops up an unwanted PIN
      // screen). Instead, the prompt card remains visible so the user can
      // touch the power button sensor, or tap "USE PIN" explicitly.
      if (widget.authenticateWithCredential != null) {
        _useCredentialFallback();
      }
    } else {
      _armFingerprintSensor();
    }
    return completer.future;
  }

  /// Answers the prompt with the device credential instead of the reader.
  ///
  /// Also the automatic path when the platform refuses to let this panel hold
  /// the sensor: the keyguard will only accept its own authentication, so
  /// making the user tap a second button for the one remaining option would be
  /// ceremony, not a choice.
  /// Whether the platform currently has this panel's reader session armed.
  ///
  /// Tracked because re-arming a live session is destructive on the tested
  /// device rather than idempotent: the framework tears the running session
  /// down before starting the next one, and ColorOS answers the replacement
  /// with `ERROR_CANCELED` instead of taking it over. Tapping an app used to
  /// re-arm a perfectly healthy session and lose the reader for the whole
  /// request — measured as two code 5 events in a row on the CPH2765, with the
  /// reader reporting no trouble at all while it was left alone.
  bool _sensorArmed = false;

  /// True once the request has been handed to the platform credential prompt.
  ///
  /// A refused reader reports more than one event, and each of them would
  /// otherwise raise a prompt of its own.
  bool _credentialHandoff = false;

  /// True once the platform has refused this panel's reader outright.
  ///
  /// While the device is locked the keyguard owns the sensor, and the tested
  /// ColorOS build answers every arm with `ERROR_CANCELED` within ~2 ms — from
  /// a cold start, with no competing session. Retrying is therefore pointless
  /// for the rest of the lock session, and re-arming on every event produced a
  /// burst of attempts that spent the reader for nothing. Measured on the
  /// CPH2765: six arms and six cancellations inside 200 ms.
  bool _sensorUnusable = false;

  Future<void> _useCredentialFallback() async {
    if (_credentialHandoff) return;
    final AppEntry? target = _authTarget ?? _authWanted;
    if (target == null) return;
    _credentialHandoff = true;
    if (widget.authenticateWithCredential != null) {
      final bool ok = await widget.authenticateWithCredential!(appName: target.label);
      _resolveAuth(ok);
    } else {
      // In production, avoid the redundant BiometricPrompt dialog which cannot
      // unlock the keyguard and causes a double PIN screen. Complete auth and
      // let requestDismissKeyguard handle credential verification natively in
      // a single prompt.
      _resolveAuth(true);
    }
  }

  void _cancelAuth() => _resolveAuth(false);

  /// Clears the prompt and completes the pending authentication exactly once.
  void _resolveAuth(bool authenticated) {
    _authResolveTimer?.cancel();
    _authResolveTimer = null;
    final completer = _authCompleter;
    _authCompleter = null;
    _authWanted = null;
    _credentialHandoff = false;
    if (mounted) {
      setState(() {
        _authTarget = null;
        _authPhase = FingerprintPromptPhase.scanning;
      });
    }
    if (completer != null && !completer.isCompleted) {
      completer.complete(authenticated);
    }
  }

  /// Whether a screen reader is running, i.e. whether the semantics layer is
  /// worth building at all.
  bool get _screenReaderActive => SemanticsBinding.instance.semanticsEnabled;

  /// Smallest focus rectangle a screen reader can reliably land on.
  static const double _minSemanticTarget = 48.0;

  /// One focusable node per bubble, at the position the canvas paints it.
  ///
  /// A reader navigates these linearly, so their positions matter for touch
  /// exploration rather than for reaching them — which is why the simulation is
  /// held still while one is active (see [_syncPhysicsLoop]).
  Widget _buildBubbleSemantics() {
    return Stack(
      children: [
        for (final bubble in _physicsEngine.bubbles)
          () {
            final rect = Rect.fromCircle(
              center: bubble.position,
              radius: bubble.radius * 1.3,
            );
            final target = rect.width >= _minSemanticTarget &&
                    rect.height >= _minSemanticTarget
                ? rect
                : Rect.fromCenter(
                    center: rect.center,
                    width: math.max(rect.width, _minSemanticTarget),
                    height: math.max(rect.height, _minSemanticTarget),
                  );
            return Positioned(
              left: target.left,
              top: target.top,
              width: target.width,
              height: target.height,
              child: Semantics(
                container: true,
                button: true,
                label: bubble.app.label,
                hint: 'Open app',
                onTap: () => _unlockAndLaunchApp(bubble.app),
                child: const SizedBox.expand(),
              ),
            );
          }(),
      ],
    );
  }

  void _onSemanticsEnabledChanged() {
    if (!mounted) return;
    setState(() {});
    _syncPhysicsLoop();
  }

  /// Runs the simulation only when it is both wanted and useful.
  ///
  /// Held still for reduce-motion (the drift is decorative, not informative) and
  /// while a screen reader is active, so its targets are not moving out from
  /// under a reader's finger and the node rectangles do not need rebuilding
  /// every frame. Drags still repaint, because they go through [markDirty].
  void _syncPhysicsLoop() {
    final bool holdStill = (MediaQuery.maybeDisableAnimationsOf(context) ?? false) ||
        _screenReaderActive;
    if (holdStill) {
      if (_physicsTicker.isActive) _physicsTicker.stop();
    } else if (!_physicsTicker.isActive) {
      _physicsTicker.start();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncPhysicsLoop();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // A reader can be switched on while this panel is already up, and nothing
    // else here rebuilds when that happens.
    SemanticsBinding.instance.addSemanticsEnabledListener(
      _onSemanticsEnabledChanged,
    );

    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 360),
    );

    _slideAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _slideController, curve: Curves.easeOutCubic),
    )..addListener(() {
        // The slide moves one transform; pushing it through the notifier keeps
        // ~330 lines of lock screen from rebuilding per animation frame.
        _panelOffset.value = _slideAnimation.value;
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
    _physicsTicker = createTicker(_onPhysicsTick);

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

    if (_authCompleter != null && !_authCompleter!.isCompleted) {
      if (mounted) {
        setState(() => _authPhase = FingerprintPromptPhase.verified);
      }
      _authResolveTimer?.cancel();
      _authResolveTimer = Timer(
        const Duration(milliseconds: 240),
        () => _resolveAuth(true),
      );
    } else {
      _unlock();
    }
  }

  void _onScreenOn() {
    if (!mounted || _disposed) return;
    _screenInteractive = true;
    // A new panel-on is a new chance for the reader: the refusal above belongs
    // to the lock session that has just ended.
    _sensorUnusable = false;
    _armFingerprintSensor();
  }

  /// Arms the reader as soon as the lock screen appears.
  ///
  /// At rest nothing is drawn for it, by us or by the system: the reader is the
  /// side power button, so a bare touch unlocks the panel with no prompt at
  /// all. The prompt only appears once the user asks for a specific app, where
  /// the panel has something to name and a match has somewhere to go.
  Future<void> _armFingerprintSensor() async {
    if (_armingFingerprint || _disposed || _handingOffLaunch) return;
    // Already listening: leave the live session alone. Cancelling and replacing
    // it is what lost the reader on the tested device.
    if (_sensorArmed) return;
    // The platform has already refused this lock session's reader. Asking again
    // costs a sensor round trip and can only fail the same way.
    if (_sensorUnusable) return;
    _armingFingerprint = true;
    _retriedArm = false;
    try {
      final capability = await (widget.fingerprintCapability ??
          LauncherBridge.fingerprintCapability)();
      if (!mounted || _disposed) return;

      if (!capability.isReady) {
        debugPrint(
          'Fingerprint reader not usable '
          '(hardware: ${capability.hardware}, enrolled: ${capability.enrolled})',
        );
        return;
      }

      // Subscribed once and kept for the panel's lifetime.
      //
      // Re-subscribing on every arm used to mean cancelling the previous
      // subscription first, and the reader is a broadcast stream: between the
      // cancel and the new listener there is a window with no subscriber at
      // all, and a match reported inside it is lost. Keeping one subscription
      // removes the window, and removes an await that could outlive the arm.
      _fingerprintSubscription ??=
          (widget.fingerprintEvents ?? LauncherBridge.fingerprintEvents)()
              .listen(
        _onFingerprintEvent,
        onError: (Object error) {
          debugPrint('Fingerprint stream error: $error');
        },
      );

      // Only the native side knows whether the panel is really on, and it
      // refuses to arm while it is off without touching the sensor at all. The
      // Dart-side copy of that state goes stale across a pause/resume and used
      // to leave the reader permanently unarmed, so the native answer decides.
      if (!mounted || _disposed || _handingOffLaunch) {
        return;
      }
      await LauncherBridge.startFingerprintScan();
    } finally {
      _armingFingerprint = false;
    }
  }

  void _onFingerprintEvent(Map<String, dynamic> event) {
    if (!mounted || _disposed) return;
    _lastInteractionTime = DateTime.now();

    switch (event['type'] as String?) {
      case 'listening':
        // The platform handed the reader over: the session is live, and the
        // panel's own prompt is now allowed to appear. A device that refuses
        // the session never reaches this, so its users never see a card that
        // cannot read them.
        debugPrint('Fingerprint reader armed');
        _sensorArmed = true;
        final AppEntry? wanted = _authWanted;
        if (mounted && _authCompleter != null && _authTarget == null && wanted != null) {
          setState(() {
            _authTarget = wanted;
            _authPhase = FingerprintPromptPhase.scanning;
          });
        }

      case 'succeeded':
        debugPrint('Fingerprint matched: unlocking');
        _retriedArm = false;
        // The session ends with the match.
        _sensorArmed = false;
        HapticFeedback.mediumImpact();
        _unlockedBySensor = true;
        if (_authCompleter != null && !_authCompleter!.isCompleted) {
          // The prompt owns the unlock from here: show the match, then let the
          // pending launch run. Unlocking the panel directly instead would skip
          // the app the user actually asked for.
          if (mounted) {
            setState(() => _authPhase = FingerprintPromptPhase.verified);
          }
          _authResolveTimer?.cancel();
          _authResolveTimer = Timer(
            const Duration(milliseconds: 240),
            () => _resolveAuth(true),
          );
        } else {
          _unlock();
        }

      case 'failed':
        // The reader stays armed, so this is a buzz rather than a dead end.
        debugPrint('Fingerprint did not match');
        _retriedArm = false;
        HapticFeedback.heavyImpact();
        if (mounted && _authTarget != null) {
          setState(() => _authPhase = FingerprintPromptPhase.failed);
        }

      case 'error':
        final code = (event['code'] as num?)?.toInt() ?? -1;
        debugPrint('Fingerprint sensor stopped: $code ${event['message']}');
        // The session is gone whichever way this goes.
        _sensorArmed = false;
        if (!_screenInteractive) {
          // Expected while the panel is off. Not a failure, and not worth a
          // retry that the platform would cancel again.
          return;
        }
        if (_handingOffLaunch) {
          // Also expected: the reader was released on purpose so the keyguard
          // could take it over for the launch handoff.
          return;
        }
        if (!_retriedArm) {
          _retriedArm = true;
          LauncherBridge.startFingerprintScan();
          return;
        }
        // The platform will not let this app hold the reader. While locked,
        // the platform keyguard monitors the power button sensor.
        // We do NOT pop up a PIN prompt automatically; the card remains on screen
        // and the user can touch the power button to unlock natively via
        // ACTION_USER_PRESENT.
        _sensorUnusable = true;
        if (mounted && _authCompleter != null) {
          if (widget.authenticateWithCredential != null) {
            _useCredentialFallback();
          }
        }

      case 'screenOff':
        // Refused rather than failed: wait for the panel; re-arming on
        // screen-on will pick the reader back up.
        _screenInteractive = false;
        // The platform cancels an app's session when the panel goes off, so
        // there is nothing left armed to reuse.
        _sensorArmed = false;

      case 'unavailable':
        // The reason matters: it is the difference between a device with no
        // reader and a reader the platform refused to hand over.
        debugPrint('Fingerprint reader unavailable: ${event['message']}');
        _sensorArmed = false;
        if (mounted && _authCompleter != null) {
          if (widget.authenticateWithCredential != null) {
            _useCredentialFallback();
          }
        }
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
        _handingOffLaunch = false;
        // Assume the panel is on: the native side refuses an arm while it is
        // off, and reports `screenOff` back, which puts this flag right again.
        _screenInteractive = true;
        _sensorUnusable = false;
        // The panel may or may not be on by now; arming is refused cheaply if
        // it is not, and the screen-on broadcast will arm it for real.
        _armFingerprintSensor();
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        // Backgrounded: the platform owns the reader now. Drop it quietly
        // instead of collecting cancellations as failures.
        _screenInteractive = false;
        _sensorArmed = false;
        if (_authCompleter != null) {
          _cancelAuth();
        }
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

    // The engine notifies the painter, which repaints only its own layer —
    // the widget tree around it does not rebuild per simulation frame.
    _physicsEngine.update(dt);
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
    // The prompt is modal: the Listener is an ancestor of the barrier, so it
    // still receives these events and has to refuse them itself.
    if (_authTarget != null) return;
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
    if (_authTarget != null) return;
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
      // Repaint immediately: a drag must follow the finger even when the
      // simulation ticker is stopped.
      _physicsEngine.markDirty();
    } else if (!_isDraggingApp) {
      // Swiping up on background. The notifier drives the transform, so a
      // finger drag does not rebuild the tree per pointer move.
      _panelOffset.value = (_panelOffset.value - event.delta.dy).clamp(0.0, 600.0);
    }
  }

  void _onPointerUp(PointerUpEvent event) {
    if (_authTarget != null) return;
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
      if (_panelOffset.value > 140.0) {
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
      _handingOffLaunch = true;
      await LauncherBridge.stopFingerprintScan();
      final launched = await LauncherBridge.launchApp(pending);
      _handingOffLaunch = false;
      if (!mounted) return;
      _unlockStarted = false;
      if (!launched) {
        _showTurbulence('COULD NOT OPEN ${pending.label.toUpperCase()}');
      }
      return;
    }

    _slideAnimation = Tween<double>(begin: _panelOffset.value, end: 900.0).animate(
      CurvedAnimation(parent: _slideController, curve: Curves.easeInCubic),
    );
    await _slideController.forward(from: 0.0);
    if (!mounted) return;
    widget.onUnlock();
  }

  void _snapBack() {
    _slideAnimation = Tween<double>(begin: _panelOffset.value, end: 0.0).animate(
      CurvedAnimation(parent: _slideController, curve: Curves.easeOutBack),
    );
    _slideController.forward(from: 0.0).then((_) {
      _panelOffset.value = 0.0;
    });
  }

  Future<void> _unlockAndLaunchApp(AppEntry app) async {
    // One authentication at a time. The prompt is modal, so a second request
    // can only arrive from a semantics action fired underneath it.
    if (_authCompleter != null || _unlockStarted) return;
    HapticFeedback.lightImpact();
    // Record the request before authenticating.
    _pendingLaunch = app;

    final bool isLocked = await (widget.isKeyguardLocked ??
        LauncherBridge.isKeyguardLocked)();
    if (!mounted || _disposed || _unlockStarted) return;
    if (!isLocked) {
      // Device is already unlocked (e.g. side power-button reader satisfied keyguard).
      // Bypass any prompt and launch immediately with no delay!
      HapticFeedback.mediumImpact();
      _unlock();
      return;
    }

    final authenticated = await _authenticate(app.label);
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
    SemanticsBinding.instance.removeSemanticsEnabledListener(
      _onSemanticsEnabledChanged,
    );
    _panelOffset.dispose();
    WidgetsBinding.instance.removeObserver(this);
    _clockTimer.cancel();
    _turbulenceTimer?.cancel();
    _authResolveTimer?.cancel();
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

    final timeHour = _currentTime.hour.toString().padLeft(2, '0');
    final timeMinute = _currentTime.minute.toString().padLeft(2, '0');
    final dateFormatted =
        '${_weekdayName(_currentTime.weekday)}, ${_monthName(_currentTime.month)} ${_currentTime.day}';

    final isTabletop = widget.foldable.isTabletop;
    final isUnfolded = !widget.foldable.isFolded && screenSize.width > 550;

    // Everything below this builder is built once per state change; only the
    // transform and its opacity re-evaluate while the panel slides.
    return ValueListenableBuilder<double>(
      valueListenable: _panelOffset,
      builder: (context, currentOffset, child) {
        final double unlockProgress = (currentOffset / 300.0).clamp(0.0, 1.0);
        final double opacity = (1.0 - (unlockProgress * 0.85)).clamp(0.0, 1.0);
        return Transform.translate(
          offset: Offset(0, -currentOffset),
          child: Opacity(opacity: opacity, child: child),
        );
      },
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

                // CustomPaint canvas rendering bouncing apps. The boundary
                // gives the physics layer its own repaint scope: simulation
                // frames repaint this canvas alone, and HUD state changes
                // never repaint the bubbles.
                Positioned.fill(
                  child: RepaintBoundary(
                    child: CustomPaint(
                      painter: BouncingAppsPainter(
                        physics: _physicsEngine,
                        draggedBubble: _draggedBubble,
                        textScaler: MediaQuery.textScalerOf(context),
                      ),
                    ),
                  ),
                ),

                // Screen reader targets for the bubbles, which are painted into
                // the canvas and would otherwise be unreachable — the same
                // defect the galaxy home screen had. They are never wrapped in
                // IgnorePointer: that sets isBlockingUserActions and would strip
                // the tap action back off them. Each is a bare SizedBox, so it
                // takes no touch and the panel gestures below still work.
                if (_screenReaderActive)
                  Positioned.fill(
                    child: ListenableBuilder(
                      listenable: _physicsEngine,
                      builder: (context, _) => _buildBubbleSemantics(),
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

                            // Interactive Shake / Scatter Button. It carried no
                            // button trait, so a reader heard the word "SHAKE"
                            // without being told it was actionable. The action
                            // is declared here rather than left to the gesture
                            // detector, so the node a reader lands on is the one
                            // that carries both the label and the action.
                            Semantics(
                              container: true,
                              button: true,
                              label: 'Scatter apps',
                              onTap: () => _triggerShakeScatter(),
                              child: GestureDetector(
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

                // The launcher's own fingerprint prompt, drawn last so it sits
                // over everything it is authenticating for. The platform's
                // BiometricPrompt is a system dialog with its own type and
                // colour; this is the same authentication in the panel's own
                // cosmic language, fed by the silent reader.
                if (_authTarget != null)
                  Positioned.fill(
                    child: Stack(
                      children: [
                        // The panel underneath is not interactive while the
                        // reader owns the interaction.
                        const Positioned.fill(
                          child: ModalBarrier(
                            dismissible: false,
                            barrierSemanticsDismissible: false,
                            color: Color(0xCC020306),
                          ),
                        ),
                        Positioned.fill(
                          child: FingerprintAuthPrompt(
                            app: _authTarget!,
                            phase: _authPhase,
                            onCancel: _cancelAuth,
                            // Offered once the finger itself is the problem: a
                            // run of non-matches, where the reader is still
                            // live but is not going to answer for this finger.
                            onUseCredential: (_authPhase ==
                                        FingerprintPromptPhase.failed ||
                                    _sensorUnusable)
                                ? _useCredentialFallback
                                : null,
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
