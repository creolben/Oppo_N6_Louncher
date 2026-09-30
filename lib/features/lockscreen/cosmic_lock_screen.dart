import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../../core/foldable_controller.dart';
import '../../models/app_entry.dart';
import '../../core/launcher_bridge.dart';
import '../../models/now_playing.dart';
import '../../models/quick_shortcut.dart';
import '../../ui/theme/luminous_home_theme.dart';
import '../../ui/format/clock_format.dart';
import 'bouncing_physics_engine.dart';
import 'bouncing_apps_painter.dart';
import 'fingerprint_prompt.dart';
import 'now_playing_card.dart';
import 'quick_shortcut_resolver.dart';

/// What an authentication attempt on this panel actually established.
///
/// This used to be a bare `bool`, and the bool was not true. Where the platform
/// refuses this panel the reader — which on a locked device is everywhere, since
/// only the keyguard may use the sensor — the code completed the attempt with
/// `true` and relied on the native `requestDismissKeyguard` at launch time to do
/// the real checking. That arrangement works, but it reports verification that
/// never happened, so nothing downstream can tell a verified user from an
/// unverified one, and the single real gate sits a layer below the code that
/// claims to be the gate.
///
/// [deferToPlatform] names that case instead of hiding it.
enum AuthOutcome {
  /// Someone was actually authenticated here: the reader matched, or the
  /// platform reported a genuine unlock of a locked keyguard.
  verified,

  /// Nothing was verified on this panel. The request may proceed only because
  /// launching goes through the platform keyguard, which will do the
  /// authenticating itself. Never treat this as an unlock.
  deferToPlatform,

  /// The user declined, or the attempt failed.
  denied,
}

class CosmicLockScreen extends StatefulWidget {
  final FoldableController foldable;
  final VoidCallback onUnlock;
  final List<AppEntry> apps;

  /// Stands in for the whole authentication step. Null in production, where the
  /// panel reads the silent sensor and then leaves the keyguard to the platform.
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

  /// Starts a silent scan session, defaulting to
  /// [LauncherBridge.startFingerprintScan].
  ///
  /// Injectable because the start answer is now what armed state is built
  /// from ("a scan was started and no terminal event has arrived"), and a
  /// test host has no platform to genuinely start one — the same reason the
  /// event seam exists: the tests need to say what the platform did.
  final Future<bool> Function()? startFingerprintScan;

  /// A credential prompt the panel may raise itself. Null in production.
  ///
  /// There is deliberately no production default. Raising a prompt of our own
  /// here cannot dismiss the keyguard, so the launch that follows would ask
  /// again — two prompts for one tap. Without it the request resolves as
  /// [AuthOutcome.deferToPlatform] and the keyguard asks exactly once.
  ///
  /// Separate from [authenticate] so a test can hold *this* prompt open — with
  /// [authenticate] it would bypass the panel's reader entirely — and observe
  /// what the card does while the platform is asking.
  final Future<bool> Function({String? appName})? authenticateWithCredential;

  /// Real keyguard locked state, defaulting to [LauncherBridge.isKeyguardLocked].
  final Future<bool> Function()? isKeyguardLocked;

  /// Whether any credential protects this device at all, defaulting to
  /// [LauncherBridge.isDeviceSecure].
  ///
  /// Full lock ownership is the settled product decision — the panel mounts
  /// on a device with no secure lock too — so this decides nothing about
  /// visibility. It decides honesty: with no credential there is no
  /// fingerprint that could ever be enrolled, so the panel neither arms a
  /// reader nor badges itself "locked" on such a device.
  final Future<bool> Function()? isDeviceSecure;

  /// Whether this panel clears itself at its first frame if the keyguard is
  /// already unlocked (default false).
  ///
  /// Set only for mounts that stand for a lock — screen-off and cold-start
  /// mounts. The launcher cannot draw behind another task's window, so such
  /// a panel often inflates long after the platform has authenticated the
  /// user; the ghost it would then be is prevented by asking the keyguard
  /// from a post-frame callback, which by construction runs once frames are
  /// definitely pumping — the race-free reconciliation report §2.5 D1-1
  /// prescribed. A panel the user raised deliberately (the dock/HUD privacy
  /// lock) passes false: it stands for the user's wish, not for a keyguard
  /// state, and must stay up on an unlocked device.
  final bool reconcileOnMount;

  /// Asks the platform to authenticate the user and clear the keyguard,
  /// defaulting to [LauncherBridge.dismissKeyguard].
  ///
  /// Injectable so a test can exercise both answers to swipe-to-enter on a
  /// locked device: the platform authenticating the user, and the user backing
  /// out of the platform's bouncer.
  final Future<bool> Function()? dismissKeyguard;

  /// The real battery state for the telemetry row, defaulting to
  /// [LauncherBridge.batteryState].
  ///
  /// Injectable so the two rules that matter can be pinned without a
  /// platform: the percentage shows only a level the platform actually
  /// reported, and an unknown level hides it rather than inventing a number
  /// (the old row hardcoded `92%` under a charging glyph that never went
  /// out).
  final Future<BatteryState?> Function()? battery;

  /// The current media session, or null when nothing is playing, defaulting to
  /// [LauncherBridge.mediaStream].
  ///
  /// Injectable so the card's show/hide rule can be exercised without a
  /// platform channel: the lock screen never asks whether access was granted,
  /// it simply renders whatever session the platform reports, so a device with
  /// no notification access naturally shows nothing.
  final Stream<NowPlaying?>? mediaStream;

  /// Sends a transport command to the primary session, defaulting to
  /// [LauncherBridge.mediaCommand].
  final Future<bool> Function(String command)? mediaCommand;

  /// Launches an app after authentication, defaulting to
  /// [LauncherBridge.launchApp].
  ///
  /// Injectable so a widget test can prove the ambient bubble field launches
  /// nothing: the field is decoration, and the only app targets are the phone
  /// and camera shortcuts.
  final Future<bool> Function(AppEntry app)? launchApp;

  const CosmicLockScreen({
    super.key,
    required this.foldable,
    required this.onUnlock,
    required this.apps,
    this.authenticate,
    this.fingerprintCapability,
    this.fingerprintEvents,
    this.startFingerprintScan,
    this.authenticateWithCredential,
    this.isKeyguardLocked,
    this.isDeviceSecure,
    this.reconcileOnMount = false,
    this.dismissKeyguard,
    this.battery,
    this.mediaStream,
    this.mediaCommand,
    this.launchApp,
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

  /// The ambient field's canvas. Its render box is the coordinate space the
  /// measured bubble band is expressed in.
  final GlobalKey _bubbleFieldKey = GlobalKey();

  /// The empty gap between the last HUD element and the unlock hint.
  ///
  /// Putting a key on the [Spacer] gives the field its band directly: the
  /// spacer's top is the bottom of the card (or the clock block) and its
  /// bottom is the top of the hint, whatever the HUD above it is doing.
  final GlobalKey _bubbleGapKey = GlobalKey();

  /// The centred HUD column, measured so the bubble band can align with it.
  final GlobalKey _hudColumnKey = GlobalKey();

  /// The widest the HUD (status, clock, date, battery, card) is allowed to be.
  ///
  /// On the inner display — where Android 16 ignores the portrait lock — this
  /// keeps the block readable in the middle of a wide landscape window instead
  /// of stretching it edge to edge. The card shares the cap, so the bubble band
  /// can align to one column.
  static const double _hudMaxWidth = 480.0;

  /// Fires once the ambient field has been idle for [_ambientIdleWindow].
  ///
  /// A [Timer] rather than a wall-clock comparison because a widget test's
  /// `pump(Duration)` advances fake time but not `DateTime.now()`, and the
  /// "no frames after 10 s" contract has to hold there too.
  Timer? _ambientIdleTimer;
  static const Duration _ambientIdleWindow = Duration(seconds: 10);

  /// Reduce-motion, cached from the last dependency change.
  bool _reduceMotion = false;

  String? _turbulenceMessage;
  Timer? _turbulenceTimer;

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

  /// Whether any credential protects this device, or null until the platform
  /// has answered.
  ///
  /// Null is treated as secure (the arm proceeds; the capability gate still
  /// refuses a device with nothing enrolled), so a slow or failed probe cannot
  /// take a working reader away from a device that has one. False — known,
  /// credential-less — is the state that stops the panel pretending a
  /// fingerprint could ever answer it.
  bool? _deviceSecure;

  /// True once the capability probe reported a reader with something enrolled.
  ///
  /// Only the unlock hint reads it: on a device whose side power key can
  /// authenticate, the honest hint names that key instead of promising a swipe
  /// alone will open the panel.
  bool _fingerprintEnrolled = false;

  /// The battery the platform last reported for the telemetry row, or null
  /// while no answer has arrived (and for an answer that cannot report a
  /// level). The row renders null as a glyph with no percentage rather than
  /// an invented number — the old `92%` was a lie about exactly this value.
  BatteryState? _batteryState;

  /// The primary media session the platform last reported, or null when there
  /// is none. Non-null puts the now-playing card on the panel.
  NowPlaying? _nowPlaying;

  /// The `media` event subscription, held from initState to dispose.
  StreamSubscription<NowPlaying?>? _mediaSubscription;

  /// True while a pointer is down on the now-playing card.
  ///
  /// The card sits inside the panel's swipe-to-unlock `Listener`, so the raw
  /// pointer stream reaches both. The card's own listener runs first (events
  /// dispatch leaf-first), which lets the panel's handlers refuse a pointer the
  /// card owns instead of dragging the bubble painted underneath it.
  bool _pointerOnMediaCard = false;

  /// The app the cosmic fingerprint prompt is currently authenticating for.
  ///
  /// Non-null is what puts the prompt on screen *and* what makes the panel
  /// underneath ignore touches, so it is cleared in exactly one place:
  /// [_resolveAuth].
  AppEntry? _authTarget;

  /// The app waiting on the reader, before the prompt is drawn.
  ///
  /// The prompt becomes visible only once a scan session genuinely started —
  /// the platform accepted the arm — whether because the start answer said so
  /// or because sensor activity (`listening`, a partial read) confirmed the
  /// session is live. On a device that will not let this panel hold the
  /// sensor at all — the tested ColorOS build cancels an app's reader
  /// session outright while the keyguard is occluded — the card therefore
  /// never appears, and the request goes straight to the platform prompt,
  /// which is the only authentication that keyguard accepts.
  AppEntry? _authWanted;

  /// What the prompt is telling the user right now.
  FingerprintPromptPhase _authPhase = FingerprintPromptPhase.scanning;

  /// Resolves the pending [_authenticate] call.
  ///
  /// The prompt is only a face over one future, so it is completed by whichever
  /// answers first: a sensor match, the themed cancel button, the device
  /// credential fallback, or the panel closing underneath it.
  Completer<AuthOutcome>? _authCompleter;

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

  /// True once this panel has finished its job: it has authenticated, handed
  /// off, and told the launcher to take it down.
  ///
  /// It is not enough to stop at [_disposed]. `widget.onUnlock()` is a setState
  /// issued at the moment the launched activity takes the screen, and Flutter
  /// does not build a frame for an activity that is no longer visible — so the
  /// element is still mounted, still a `WidgetsBindingObserver`, and still the
  /// registered `screenOn`/`userPresent` listener for the whole time the other
  /// app is in front. On the way back its `resumed` handler used to re-arm the
  /// reader and, with the guards it also reset, could re-run a leftover launch:
  /// a fingerprint request with no tap behind it.
  ///
  /// A fresh panel is constructed for the next lock, so a one-way latch here
  /// costs nothing and makes "this panel is finished" mean it.
  bool _handedOff = false;

  /// Whether this panel should be reading the sensor at all.
  ///
  /// The reader is only ever armed for a lock surface the user is looking at.
  bool get _sensorSessionAllowed =>
      mounted && !_disposed && !_handedOff && !_handingOffLaunch;

  Future<AuthOutcome> _authenticate(String? appName) async {
    final override = widget.authenticate;
    if (override != null) {
      return await override(appName: appName)
          ? AuthOutcome.verified
          : AuthOutcome.denied;
    }

    // The panel draws its own prompt only where it can actually read the
    // sensor. Where it cannot — no finger enrolled, or no reader at all — there
    // is nothing for it to ask, so it asks nothing and lets the launch run.
    final capability =
        await (widget.fingerprintCapability ??
            LauncherBridge.fingerprintCapability)();
    if (!mounted || _disposed) return AuthOutcome.denied;
    if (!capability.isReady) {
      // Deliberately not `LauncherBridge.authenticate` — that raises the
      // platform's BiometricPrompt, which cannot dismiss the keyguard, so the
      // `requestDismissKeyguard` inside the launch that follows asks the user a
      // second time for the same tap. Two prompts for one intention is the
      // "why is it asking again" complaint, and the first of them buys nothing.
      //
      // Deferring is not an authentication and does not claim to be: the launch
      // still cannot be seen until the keyguard's own prompt is satisfied.
      return AuthOutcome.deferToPlatform;
    }
    return _authenticateWithSensor();
  }

  /// Raises the reader and holds the request open for a finger.
  ///
  /// A session that is already armed is used as it stands: the reader that
  /// armed with the panel on an unlocked device — the dock privacy lock — is
  /// the same reader that is about to open the app, and re-arming it would
  /// cancel it.
  Future<AuthOutcome> _authenticateWithSensor() {
    final AppEntry? target = _pendingLaunch;
    if (target == null) return Future<AuthOutcome>.value(AuthOutcome.denied);
    final completer = Completer<AuthOutcome>();
    _authCompleter = completer;
    _authWanted = target;
    // A deliberate request gets a fresh budget: the single retry exists for a
    // genuinely transient cancellation, not for a session that already spent it
    // while the panel sat idle.
    _retriedArm = false;

    if (_sensorArmed) {
      // The session is already live — the scan-start answer said so (the
      // reader that armed with the panel on an unlocked device, the dock
      // privacy lock) — so a finger can genuinely answer a card for this
      // request. Raise it now: waiting for a `listening` event would read
      // as the tap being ignored, and on device that event now means
      // "sensor activity seen", which a clean first touch never triggers.
      if (mounted) {
        setState(() {
          _authTarget = target;
          _authPhase = FingerprintPromptPhase.scanning;
        });
      }
    } else if (_deviceSecure == false) {
      // No credential protects this device, so no fingerprint can ever be
      // enrolled to answer the panel's reader — asking for one would be the
      // pretend this panel refuses to do. Production cannot reach here (a
      // credential-less device fails the capability gate long before this
      // point); a request that raced past it anyway must not hang behind a
      // card nothing can answer, so the fallback resolves it — and on such
      // a device the platform's launch-time dismiss is silent, because
      // there is no credential to ask for.
      debugPrint(
        'CF_FP: device has no secure lock; deferring the request to the platform',
      );
      _useCredentialFallback();
    } else if (_sensorUnusable) {
      // The platform has already refused this panel the reader — on a locked
      // device the keyguard owns the sensor, and every arm is refused. The
      // card is deliberately NOT raised: it would ask for a finger that can
      // never answer it, and with no credential hook in production nothing
      // would ever resolve it — the modal dead-end of report §3.1. The
      // request resolves through the credential fallback instead: with a hook
      // injected the hook answers first; without one the fallback completes
      // as [AuthOutcome.deferToPlatform] and the launch runs through the
      // platform's single `requestDismissKeyguard` bouncer, so the
      // platform's own prompt is the one visible ask.
      debugPrint(
        'CF_FP: reader refused while keyguard locked; deferring to platform prompt',
      );
      _useCredentialFallback();
    } else {
      // The reader's state is unknown yet: arm it. A session the platform
      // accepts promotes `_authWanted` to the card right there — the start
      // answer is the promotion, so the card appears the moment a finger
      // could genuinely answer it (the `listening` event promotes too, as
      // the safety net for a request that raced the arm). A device that
      // refuses the session never starts one, so its users never see a card
      // at all — the refusal events resolve the request instead.
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
      final bool ok = await widget.authenticateWithCredential!(
        appName: target.label,
      );
      _resolveAuth(ok ? AuthOutcome.verified : AuthOutcome.denied);
    } else {
      // Raising BiometricPrompt here would ask the user twice: it cannot
      // dismiss the keyguard, so the native `requestDismissKeyguard` at launch
      // time prompts again. Deferring to that single native prompt is the right
      // behaviour — but it is a deferral, not an authentication, and saying so
      // is the whole point of [AuthOutcome.deferToPlatform]. Completing with
      // `verified` here is what previously let this panel report an unlock it
      // had not performed.
      _resolveAuth(AuthOutcome.deferToPlatform);
    }
  }

  void _cancelAuth() => _resolveAuth(AuthOutcome.denied);

  /// Clears the prompt and completes the pending authentication exactly once.
  void _resolveAuth(AuthOutcome outcome) {
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
      completer.complete(outcome);
    }
  }

  /// Runs the ambient field only when it is both wanted and useful.
  ///
  /// Held still for reduce-motion (the drift is decorative, not informative).
  /// Otherwise it runs for one idle window and then stops entirely — no
  /// ticker, so no frame callbacks, so no frames — until a touch or the
  /// platform's screen-on gives it another window. This is the battery
  /// contract on the N6's large panel: a decorative field must not keep the
  /// display compositor awake all night.
  void _syncPhysicsLoop() {
    _reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (_reduceMotion) {
      _ambientIdleTimer?.cancel();
      _ambientIdleTimer = null;
      if (_physicsTicker.isActive) _physicsTicker.stop();
      // No ticker means no breath: park the field so reduce-motion gets a
      // static grid rather than a frozen frame of the animation.
      _physicsEngine.settleToHome();
      return;
    }
    _touchAmbientMotion();
  }

  /// Gives the field another idle window, starting it if it had stopped.
  void _touchAmbientMotion() {
    if (_reduceMotion) return;
    _ambientIdleTimer?.cancel();
    _ambientIdleTimer = Timer(_ambientIdleWindow, _pauseAmbientMotion);
    if (!_physicsTicker.isActive) {
      // The ticker reports elapsed since its own start, so a restarted ticker
      // must not be handed a stale baseline.
      _lastElapsed = Duration.zero;
      _physicsTicker.start();
    }
  }

  void _pauseAmbientMotion() {
    _ambientIdleTimer = null;
    if (_physicsTicker.isActive) _physicsTicker.stop();
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

    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 360),
    );

    _slideAnimation =
        Tween<double>(begin: 0.0, end: 1.0).animate(
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
          (now.minute == _currentTime.minute &&
              now.hour == _currentTime.hour)) {
        return;
      }
      setState(() => _currentTime = now);
      // The battery rides the minute rollover: a percentage that changed
      // while nobody looked is fine to catch up a minute late, and a probe
      // per minute costs nothing where a battery timer of its own would
      // cost exactly what the idle throttling below exists to save.
      _refreshBattery();
    });

    // 60/120 FPS Physics simulation loop
    _physicsTicker = createTicker(_onPhysicsTick);

    // The field is deliberately deaf to the accelerometer. An ambient grid
    // that leans with the phone reads as broken on an upright device (gravity
    // pinned every sphere to one edge), so the panel no longer subscribes to
    // the shake/tilt stream at all.

    // The panel turning on is the first moment the reader can be held again,
    // and it arrives before the activity resumes.
    LauncherBridge.setScreenOnListener(_onScreenOn);
    LauncherBridge.setUserPresentListener(_onUserPresent);
    // Full lock ownership is the settled product decision: the panel mounts
    // whether the device has a credential or not. The secure answer decides
    // only whether a reader is armed — and arming waits for it, so a device
    // with no secure lock never spends even the probe on a fingerprint that
    // cannot exist there.
    _refreshDeviceSecure();
    // The lock surface shows the real battery: sampled now, refreshed on the
    // platform's `screenOn` signal and on the clock's minute rollover — no
    // timer of its own.
    _refreshBattery();

    // The now-playing card follows the platform's primary session. Nothing is
    // asked of the user here: with no notification access the native stream is
    // simply silent, so no card appears and the lock screen never nags for a
    // grant (that flow is P5's).
    _mediaSubscription =
        (widget.mediaStream ?? LauncherBridge.mediaStream).listen(
          _onNowPlaying,
          onError: (Object error) {
            debugPrint('CF_MEDIA: media stream error: $error');
          },
        );

    if (widget.reconcileOnMount) {
      // Post-frame on purpose: the launcher cannot draw behind a foreign
      // task or over the keyguard, so this callback firing at all means a
      // frame was pumped — the only moment a keyguard answer can be trusted
      // to describe what the user is actually looking at.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _reconcileAgainstKeyguard();
      });
    }
  }

  /// Clears this panel if the keyguard it was mounted for no longer exists.
  ///
  /// Runs from initState's post-frame callback, and again every time the
  /// panel's lifecycle returns to `resumed` — the moment the launcher
  /// regains the screen after the platform unlock — and only for mounts
  /// that stand for a lock ([CosmicLockScreen.reconcileOnMount]). A
  /// screen-off behind a foreign app mounts this panel invisibly — the
  /// launcher cannot draw there — and by the time it can, the platform has
  /// usually already authenticated the user; without this check the panel
  /// would appear as a lock for a device already unlocked. The resumed pass
  /// is the belt-and-braces for the native `USER_PRESENT` gate: a single
  /// dropped broadcast must not be able to strand the panel over an
  /// unlocked device again. A panel that has handed off a launch has
  /// already called `onUnlock`, so there is nothing left to reconcile.
  Future<void> _reconcileAgainstKeyguard() async {
    if (!mounted || _disposed || _handedOff) return;
    final bool isLocked =
        await (widget.isKeyguardLocked ?? LauncherBridge.isKeyguardLocked)();
    if (!mounted || _disposed || _handedOff) return;
    if (isLocked) return;
    debugPrint('CF_LOCK: panel reconciled away; keyguard already unlocked');
    widget.onUnlock();
  }

  /// Asks the platform whether any credential protects this device, then
  /// arms the reader for the panel's first appearance through that answer.
  ///
  /// Arming waits for the answer on purpose: a device with no secure lock
  /// has no credential a fingerprint could be enrolled against, so arming
  /// there could only ask a question nothing on the device can answer —
  /// and the panel refuses to pretend otherwise. On a secure device the
  /// cost is one platform round trip before an arm that was already racing
  /// the first frame; on a credential-less device the sensor is never
  /// touched at all.
  Future<void> _refreshDeviceSecure() async {
    final bool secure =
        await (widget.isDeviceSecure ?? LauncherBridge.isDeviceSecure)();
    if (!mounted || _disposed) return;
    setState(() => _deviceSecure = secure);
    if (secure) {
      _armFingerprintSensor();
    } else {
      debugPrint('CF_FP: device has no secure lock; reader not armed');
    }
  }

  /// Samples the battery through the seam.
  ///
  /// Called on mount, on the platform's `screenOn`, and on the clock's
  /// minute rollover — the three moments the percentage can change
  /// meaningfully without a new high-frequency timer draining the OLED the
  /// idle throttling exists to save.
  Future<void> _refreshBattery() async {
    final BatteryState? state =
        await (widget.battery ?? LauncherBridge.batteryState)();
    if (!mounted || _disposed) return;
    setState(() => _batteryState = state);
  }

  /// The single charging line under the date, or null when none should show.
  ///
  /// The status bar already carries the level, so a discharging lock screen
  /// that repeats a percentage is noise: ColorOS shows the line only on
  /// charge. At 100% the line says "Charged" rather than "100 %", which is
  /// what the device is actually doing by then.
  String? get _batteryLabel {
    final state = _batteryState;
    if (state == null || !state.charging) return null;
    final level = state.level;
    if (level == null) return 'Charging';
    if (level >= 100) return 'Charged';
    return 'Charging · $level %';
  }

  /// The hint under the field.
  ///
  /// Three honest variants, one per device state: a credential-less device
  /// opens (nothing to authenticate), an enrolled reader is named because the
  /// side power key — not the panel — is the reader, and everything else
  /// promises only the swipe.
  String get _unlockHint {
    if (_deviceSecure == false) return 'Swipe up to open';
    if (_fingerprintEnrolled) return 'Swipe up or touch the power key';
    return 'Swipe up to unlock';
  }

  /// Whether a media session is actively playing.
  ///
  /// This — not merely "a card is visible" — is what freezes and dims the
  /// bubble field: a paused card is informational and leaves the panel usable,
  /// while a playing one means the user's attention is on the transport.
  bool get _mediaPlaying => _nowPlaying?.isPlaying == true;

  /// Applies the platform's latest primary session.
  ///
  /// Null means "nothing to show". A session replaces the previous one
  /// wholesale; the model's equality deliberately ignores position, so a
  /// repeated snapshot is still applied (the progress line may have moved)
  /// without the native side having to tick.
  void _onNowPlaying(NowPlaying? media) {
    if (!mounted || _disposed) return;
    if (media == null) {
      if (_nowPlaying == null) return;
      debugPrint('CF_MEDIA: no active session; hiding now-playing card');
      setState(() => _nowPlaying = null);
      return;
    }
    debugPrint(
      'CF_MEDIA: ${media.appLabel} — ${media.title ?? '(untitled)'} '
      '[${media.state}]',
    );
    setState(() => _nowPlaying = media);
  }

  Future<bool> _sendMediaCommand(String command) async {
    final handler = widget.mediaCommand ?? LauncherBridge.mediaCommand;
    try {
      return await handler(command);
    } catch (error) {
      debugPrint('CF_MEDIA: command "$command" failed: $error');
      return false;
    }
  }

  /// The now-playing card, or null when there is no session.
  ///
  /// Wrapped in its own [Listener] so a pointer that goes down on the card is
  /// marked before the panel's raw pointer handlers see it; those handlers then
  /// refuse to pick up the bubble painted underneath. Tapping the art or title
  /// does nothing in this phase — opening the app is P2.
  Widget _buildNowPlayingCard() {
    final media = _nowPlaying;
    if (media == null) return const SizedBox.shrink();
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: _hudMaxWidth),
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (_) => _pointerOnMediaCard = true,
        onPointerUp: (_) => _pointerOnMediaCard = false,
        onPointerCancel: (_) => _pointerOnMediaCard = false,
        child: NowPlayingCard(
          nowPlaying: media,
          onCommand: _sendMediaCommand,
        ),
      ),
    );
  }

  /// The platform authenticated someone and the keyguard is gone, so this
  /// overlay clears with it. While the launcher draws over the keyguard its own
  /// reader session is usually preempted, so the platform's success is the
  /// signal that a real touch produced a real unlock — never a bare wake, since
  /// the native side only reports an unlock that followed a locked keyguard.
  void _onUserPresent() {
    if (!mounted || _disposed) return;
    if (_unlockedBySensor) return;
    if (_handedOff) {
      // This panel has already unlocked and handed off. Acting again would
      // re-launch or re-authenticate on behalf of a surface the user has left.
      debugPrint('Ignoring userPresent on a panel that already handed off');
      return;
    }
    if (_handingOffLaunch) {
      debugPrint('Ignoring userPresent while handing off app launch');
      return;
    }

    if (_authCompleter != null && !_authCompleter!.isCompleted) {
      debugPrint(
        'Platform unlocked a locked keyguard; completing pending auth',
      );
      HapticFeedback.mediumImpact();
      _unlockedBySensor = true;
      if (mounted) {
        setState(() => _authPhase = FingerprintPromptPhase.verified);
      }
      _authResolveTimer?.cancel();
      _authResolveTimer = Timer(
        const Duration(milliseconds: 240),
        () => _resolveAuth(AuthOutcome.verified),
      );
    } else {
      debugPrint(
        'Platform unlocked a locked keyguard; clearing the overlay or launching pending',
      );
      HapticFeedback.mediumImpact();
      _unlockedBySensor = true;
      _unlock();
    }
  }

  void _onScreenOn() {
    if (!mounted || _disposed || _handedOff) return;
    _screenInteractive = true;
    // A new panel-on is a new chance for the reader: the refusal above belongs
    // to the lock session that has just ended.
    _sensorUnusable = false;
    _armFingerprintSensor();
    // The battery rode through the whole off period with the panel unable
    // to show it; panel-on is the natural refresh moment, and reusing this
    // signal adds no timer of its own.
    _refreshBattery();
    // The panel has just come back; the field gets a fresh idle window.
    _touchAmbientMotion();
  }

  /// Arms the reader as soon as the lock screen appears.
  ///
  /// At rest nothing is drawn for it, by us or by the system: the reader is the
  /// side power button, so a bare touch unlocks the panel with no prompt at
  /// all. The prompt only appears once the user asks for a specific app, where
  /// the panel has something to name and a match has somewhere to go.
  Future<void> _armFingerprintSensor() async {
    if (_armingFingerprint || !_sensorSessionAllowed) return;
    // Already listening: leave the live session alone. Cancelling and replacing
    // it is what lost the reader on the tested device.
    if (_sensorArmed) return;
    // The platform has already refused this lock session's reader. Asking again
    // costs a sensor round trip and can only fail the same way.
    if (_sensorUnusable) return;
    // A device with no secure lock has no credential a fingerprint could be
    // enrolled against, so arming could only ask a question nothing on the
    // device can answer. This covers the arms that do not come from mount
    // (screen-on, resume, a tap); the mount arm waits for the same answer.
    if (_deviceSecure == false) return;
    _armingFingerprint = true;
    _retriedArm = false;
    try {
      final capability =
          await (widget.fingerprintCapability ??
              LauncherBridge.fingerprintCapability)();
      if (!mounted || _disposed) return;

      if (!capability.isReady) {
        debugPrint(
          'Fingerprint reader not usable '
          '(hardware: ${capability.hardware}, enrolled: ${capability.enrolled})',
        );
        return;
      }

      if (mounted && !_fingerprintEnrolled) {
        setState(() => _fingerprintEnrolled = true);
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

      // Only the native side knows whether the panel is really on, and whether
      // this activity is the one in front. It refuses to arm in either case
      // without touching the sensor at all. The Dart-side copies of that state
      // go stale across a pause/resume and used to leave the reader permanently
      // unarmed, so the native answer decides.
      if (!_sensorSessionAllowed) return;
      final bool started = await _startScan();
      if (!started) return;
      // A session the platform genuinely accepted. The request that
      // prompted this arm may raise its card now: waiting for `listening`
      // would tie the card to an event that on device means "sensor
      // activity seen" — a partial read — and a clean first touch can
      // succeed without it ever arriving. A bare touch needs no prompt, so
      // a missing `listening` costs nothing.
      final AppEntry? wanted = _authWanted;
      if (mounted &&
          _authCompleter != null &&
          _authTarget == null &&
          wanted != null) {
        setState(() {
          _authTarget = wanted;
          _authPhase = FingerprintPromptPhase.scanning;
        });
      }
    } finally {
      _armingFingerprint = false;
    }
  }

  /// Starts a silent scan through the seam and records the honest answer as
  /// this panel's armed state.
  ///
  /// Armed means exactly "a scan was started and no terminal event has
  /// arrived": set by this answer, cleared by the terminal and refusal
  /// events — never set by the arrival of `listening`, which on device now
  /// means "sensor activity seen" and may never arrive at all. A refusal
  /// (false) leaves armed state alone; the refusal event it carries does
  /// the rest (fallback, retry budget, interactivity bookkeeping).
  Future<bool> _startScan() async {
    final bool started = await (widget.startFingerprintScan ??
        LauncherBridge.startFingerprintScan)();
    if (started) {
      _sensorArmed = true;
      debugPrint('Fingerprint reader armed');
    }
    return started;
  }

  void _onFingerprintEvent(Map<String, dynamic> event) {
    if (!mounted || _disposed) return;

    switch (event['type'] as String?) {
      case 'listening':
        // Sensor activity seen — a partial read, finger moved or sensor
        // dirty — the first honest evidence the session is live. Armed
        // state no longer comes from here (see [_startScan]): the start
        // answer owns it, and a clean first touch can succeed without this
        // event arriving at all. What stays is the card promotion, as the
        // safety net for a request that raced the arm.
        debugPrint('Fingerprint sensor activity: session live');
        final AppEntry? wanted = _authWanted;
        if (mounted &&
            _authCompleter != null &&
            _authTarget == null &&
            wanted != null) {
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
            () => _resolveAuth(AuthOutcome.verified),
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
          // The retry's answer decides armed state exactly like the first
          // arm's: a retry that genuinely started is a live session. The
          // event handler is synchronous, so the bookkeeping rides the
          // future rather than an await here.
          unawaited(_startScan());
          return;
        }
        // The platform will not let this app hold the reader — while the
        // device is locked the keyguard owns the sensor and this refusal is
        // its refusal. Resolving through the credential fallback does not
        // raise a prompt of ours: with no hook injected it completes as
        // [AuthOutcome.deferToPlatform], and the launch that follows runs
        // through the platform's single `requestDismissKeyguard` bouncer.
        // Leaving the completer pending here — the old behaviour, which only
        // a test-injected hook could satisfy — is what stranded real requests
        // behind a modal card that nothing could ever answer.
        _sensorUnusable = true;
        if (mounted && _authCompleter != null) {
          debugPrint(
            'CF_FP: reader refused while keyguard locked; deferring to platform prompt',
          );
          _useCredentialFallback();
        }

      case 'screenOff':
        // Refused rather than failed: wait for the panel; re-arming on
        // screen-on will pick the reader back up.
        _screenInteractive = false;
        // The platform cancels an app's session when the panel goes off, so
        // there is nothing left armed to reuse.
        _sensorArmed = false;

      case 'keyguardLocked':
        // Refused before the sensor was touched: while the keyguard is
        // locked it owns the reader, and the native side now says so up
        // front instead of letting ColorOS cancel the session after the
        // arm. Nothing was armed, so the panel loses nothing it had — and a
        // pending request resolves through the credential fallback, which on
        // this device means the platform's own `requestDismissKeyguard`
        // bouncer, the only reader this state accepts. This also marks the
        // session unusable so later taps short-circuit straight to the
        // fallback without another arm round trip.
        _sensorArmed = false;
        _sensorUnusable = true;
        debugPrint(
          'CF_FP: reader refused while keyguard locked; deferring to platform prompt',
        );
        if (mounted && _authCompleter != null) {
          _useCredentialFallback();
        }

      case 'background':
        // The native side refused because the launcher is not the activity in
        // front. Nothing was armed and nothing is wrong with the reader, so
        // this is neither a failure nor grounds for the credential fallback:
        // the resume handler arms it once the panel is actually visible.
        debugPrint('Reader not armed: launcher is not in the foreground');
        _sensorArmed = false;

      case 'unavailable':
        // The reason matters: it is the difference between a device with no
        // reader and a reader the platform refused to hand over.
        debugPrint('Fingerprint reader unavailable: ${event['message']}');
        _sensorArmed = false;
        // No hook required here either: production has no
        // `authenticateWithCredential`, and a request that reached this point
        // must still resolve — through the fallback's deferToPlatform path
        // rather than hanging behind a card a missing reader can never
        // answer.
        if (mounted && _authCompleter != null) {
          _useCredentialFallback();
        }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        // A panel that has already unlocked and handed off is finished. It is
        // only still here because Flutter could not build the frame that would
        // dispose it while the launched app held the screen, and reviving its
        // reader — or its guards — is what asked for a fingerprint on the way
        // back out of that app. Leave it alone; the frame after this resume
        // takes it down.
        if (_handedOff) return;
        // Coming back to the front with the panel still the live lock surface,
        // so it has to accept an unlock and re-arm the reader all over again.
        _unlockStarted = false;
        _unlockedBySensor = false;
        _handingOffLaunch = false;
        // Assume the panel is on: the native side refuses an arm while it is
        // off, and reports `screenOff` back, which puts this flag right again.
        _screenInteractive = true;
        _sensorUnusable = false;
        // The panel may or may not be on by now, and this activity may not yet
        // be the one in front; arming is refused cheaply in either case, and
        // the screen-on broadcast will arm it for real.
        _armFingerprintSensor();
        // Belt-and-braces for the cold-boot gate: if the platform
        // authenticated the user while this activity was paused — or a
        // broadcast was dropped on the way — `userPresent` may never
        // arrive, and the panel would sit over an unlocked device until a
        // swipe cleared it. The launcher regains the screen exactly on this
        // transition, so this is the moment to ask the keyguard directly
        // and clear a panel whose lock is gone. Only panels that stand for
        // a keyguard reconcile; one mounted by the LOCK buttons stands for
        // the user's wish and must stay up on an unlocked device.
        if (widget.reconcileOnMount) {
          _reconcileAgainstKeyguard();
        }
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        // Backgrounded: the platform owns the reader now. Drop it quietly
        // instead of collecting cancellations as failures.
        _screenInteractive = false;
        _sensorArmed = false;
        if (_authCompleter != null) {
          _cancelAuth();
        }
        // Forget what the panel was in the middle of. A request only means
        // anything while the user is looking at the surface they made it on;
        // carrying it across a background trip is how a tap from before could
        // launch an app, and raise the keyguard to do it, long after the fact.
        // The handoff is the one exception: there the launch is the reason the
        // panel is being backgrounded.
        if (!_handingOffLaunch) {
          _pendingLaunch = null;
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
    if (dt <= 0.0) return;

    // The engine notifies the painter, which repaints only its own layer —
    // the widget tree around it does not rebuild per simulation frame.
    _physicsEngine.update(dt);
  }

  /// The app set the ambient field may draw.
  ///
  /// Two exclusions: the apps the corner shortcuts already stand for — a bubble
  /// that duplicates the camera shortcut both wastes a sphere and muddies the
  /// target — and apps the platform gave no icon bytes for, which the painter
  /// can only draw as a flat fallback glyph.
  List<AppEntry> _ambientApps() {
    final shortcutPackages = <String>{};
    final phone = QuickShortcutResolver.phone(widget.apps);
    if (phone != null) shortcutPackages.add(phone.packageName);
    final camera = QuickShortcutResolver.camera(widget.apps);
    if (camera != null) shortcutPackages.add(camera.packageName);
    return [
      for (final app in widget.apps)
        if (!shortcutPackages.contains(app.packageName) &&
            app.iconBytes != null &&
            app.iconBytes!.isNotEmpty)
          app,
    ];
  }

  void _ensurePhysicsInitialized(Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    if (_physicsEngine.bubbles.isEmpty) {
      // The panel mounts with `apps: const []` and fills the list on a later
      // build (see `lock_main.dart`), so this can run after the post-frame
      // measurement has already pinned the real band. When it has, initialize
      // straight into that band instead of the provisional guess: the engine
      // is the source of truth, and re-deriving from `size.height * 0.28`
      // would put the first row back under the now-playing card.
      final Rect? measured = _physicsEngine.viewportSize == size
          ? _physicsEngine.bounds
          : null;
      if (measured != null) {
        _physicsEngine.initializeBubbles(
          apps: _ambientApps(),
          size: size,
          padding: EdgeInsets.fromLTRB(
            measured.left,
            measured.top,
            size.width - measured.right,
            size.height - measured.bottom,
          ),
        );
        return;
      }

      // First frame, before any measurement: provisional vertical padding, but
      // the real horizontal margin. The HUD column is capped at [_hudMaxWidth]
      // and centred, so the band's left and right edges do not depend on
      // whether the card is present. The post-frame band measurement pins the
      // vertical gap before the next frame is shown.
      final double hudWidth = math.max(
        0.0,
        math.min(size.width - 48.0, _hudMaxWidth),
      );
      final double margin = (size.width - hudWidth) / 2.0;
      _physicsEngine.initializeBubbles(
        apps: _ambientApps(),
        size: size,
        padding: EdgeInsets.fromLTRB(
          margin,
          size.height * 0.28,
          margin,
          210.0,
        ),
      );
    } else if (_physicsEngine.viewportSize != size) {
      _physicsEngine.resize(size);
    }
  }

  /// Confines the ambient field to the empty gap between the HUD and the hint.
  ///
  /// Measured after layout because the gap depends on whether a now-playing
  /// card is present and on the ambient text scale. The band keeps 24dp of
  /// vertical clearance (the brief's floor is 16dp), and its horizontal edges
  /// follow the HUD column, so the spheres align with the card. The engine
  /// re-clamps immediately, so nothing is ever drawn outside the band while the
  /// next tick waits.
  void _syncBubbleBand() {
    if (!mounted || _disposed) return;
    final RenderBox? field =
        _bubbleFieldKey.currentContext?.findRenderObject() as RenderBox?;
    final RenderBox? gap =
        _bubbleGapKey.currentContext?.findRenderObject() as RenderBox?;
    final RenderBox? hud =
        _hudColumnKey.currentContext?.findRenderObject() as RenderBox?;
    if (field == null || gap == null || !field.hasSize || !gap.hasSize) return;

    final Offset gapOrigin = field.globalToLocal(gap.localToGlobal(Offset.zero));
    final double top = gapOrigin.dy + 24.0;
    final double bottom = gapOrigin.dy + gap.size.height - 24.0;
    // A band this thin cannot hold a sphere without painting over the HUD;
    // leave the field where it is.
    if (bottom - top < 40.0) return;

    // Horizontal inset = the HUD column's margin, so the spheres line up with
    // the card rather than the raw screen. Falls back to the outer padding
    // until the column has laid out.
    double left = 24.0;
    double right = field.size.width - 24.0;
    if (hud != null &&
        hud.hasSize &&
        hud.size.width > 0 &&
        field.size.width > 48.0) {
      final Offset hudOrigin = field.globalToLocal(
        hud.localToGlobal(Offset.zero),
      );
      left = hudOrigin.dx.clamp(24.0, field.size.width - 24.0);
      right = (hudOrigin.dx + hud.size.width).clamp(
        24.0,
        field.size.width - 24.0,
      );
    }
    if (right - left < 80.0) {
      left = 24.0;
      right = field.size.width - 24.0;
    }

    final Rect band = Rect.fromLTRB(left, top, right, bottom);
    // The engine is the single source of truth for its own band. A late
    // `initializeBubbles` resets the engine's padding behind this method's
    // back, so a widget-side cache of the last band would short-circuit the
    // re-apply and leave the field under the card. `setBounds` already no-ops
    // on an identical band, so running every post-frame is cheap.
    if (_physicsEngine.bounds == band) {
      return;
    }
    _physicsEngine.setBounds(band, viewport: field.size);
  }

  // Pointer event handlers. The ambient field is not a touch target: the only
  // gestures the panel owns are the swipe-up to unlock and the two corner
  // shortcuts.
  void _onPointerDown(PointerDownEvent event) {
    // The prompt is modal: the Listener is an ancestor of the barrier, so it
    // still receives these events and has to refuse them itself.
    if (_authTarget != null) return;
    // A pointer that began on the now-playing card belongs to the card's own
    // buttons; the panel must not also swipe under it.
    if (_pointerOnMediaCard) return;
    _touchAmbientMotion();
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (_authTarget != null) return;
    if (_pointerOnMediaCard) return;
    // Swiping up on the background. The notifier drives the transform, so a
    // finger drag does not rebuild the tree per pointer move.
    _panelOffset.value = (_panelOffset.value - event.delta.dy).clamp(
      0.0,
      600.0,
    );
  }

  void _onPointerUp(PointerUpEvent event) {
    if (_authTarget != null) return;
    if (_panelOffset.value > 140.0) {
      _enterLauncher();
    } else {
      _snapBack();
    }
  }

  /// Clears the panel in response to a swipe, for someone the platform has
  /// actually authenticated.
  ///
  /// This gesture used to clear the panel unconditionally — the comment here
  /// read "Anyone can swipe up to enter the launcher", and it was literally
  /// true. Because the panel is drawn over the keyguard while COSMIC mode is on,
  /// a swipe on a locked device exposed the launcher behind it: the whole app
  /// inventory, search across every installed app name, and the editors that
  /// persist layout changes to disk. App launches were still gated natively, so
  /// the exposure was disclosure and tampering rather than arbitrary app access
  /// — but the surface drew a padlock and the word LOCKED while enforcing
  /// nothing.
  ///
  /// The panel cannot authenticate anyone itself: while the device is locked only
  /// the keyguard may use the sensor. So it asks the platform to authenticate,
  /// and clears only if the platform reports that it did.
  Future<void> _enterLauncher() async {
    if (_unlockStarted || _disposed) return;

    final bool isLocked =
        await (widget.isKeyguardLocked ?? LauncherBridge.isKeyguardLocked)();
    if (!mounted || _disposed || _unlockStarted) return;

    if (!isLocked) {
      _unlock();
      return;
    }

    final bool dismissed =
        await (widget.dismissKeyguard ?? LauncherBridge.dismissKeyguard)();
    if (!mounted || _disposed || _unlockStarted) return;

    if (dismissed) {
      _unlock();
      return;
    }

    // The user declined the platform's prompt, or it could not be raised.
    // Put the panel back rather than leaving it half-pulled.
    _snapBack();
    _showTurbulence('UNLOCK TO ENTER THE LAUNCHER');
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
      final launch = widget.launchApp ?? LauncherBridge.launchApp;
      final launched = await launch(pending);
      _handingOffLaunch = false;
      if (!mounted) return;
      _unlockStarted = false;
      if (launched) {
        // Latched before onUnlock, because onUnlock is the last thing this
        // panel does and the frame that disposes it may be a whole app
        // round trip away. Everything after this point must be inert.
        _handedOff = true;
        // The native handoff already removes `showWhenLocked` before the
        // target starts. Keep the Dart side in sync so its return reveals the
        // folded cover screen rather than recreating a fingerprint surface.
        unawaited(LauncherBridge.setLockScreenOverlayEnabled(false));
        unawaited(LauncherBridge.stopFingerprintScan());
        widget.onUnlock();
      } else {
        _showTurbulence('COULD NOT OPEN ${pending.label.toUpperCase()}');
      }
      return;
    }

    _slideAnimation = Tween<double>(begin: _panelOffset.value, end: 900.0)
        .animate(
          CurvedAnimation(parent: _slideController, curve: Curves.easeInCubic),
        );
    await _slideController.forward(from: 0.0);
    if (!mounted) return;
    _handedOff = true;
    // An ordinary unlock also needs to stop MainActivity behaving like a
    // keyguard overlay until the next genuine screen-off event.
    unawaited(LauncherBridge.setLockScreenOverlayEnabled(false));
    unawaited(LauncherBridge.stopFingerprintScan());
    widget.onUnlock();
  }

  void _snapBack() {
    _slideAnimation = Tween<double>(begin: _panelOffset.value, end: 0.0)
        .animate(
          CurvedAnimation(parent: _slideController, curve: Curves.easeOutBack),
        );
    _slideController.forward(from: 0.0).then((_) {
      _panelOffset.value = 0.0;
    });
  }

  Future<void> _unlockAndLaunchApp(AppEntry app) async {
    // One authentication at a time. The prompt is modal, so a second request
    // can only arrive from a semantics action fired underneath it.
    if (_authCompleter != null || _unlockStarted || _handedOff) return;
    HapticFeedback.lightImpact();
    // Record the request before authenticating.
    _pendingLaunch = app;

    final bool isLocked =
        await (widget.isKeyguardLocked ?? LauncherBridge.isKeyguardLocked)();
    // Bailing out has to forget the request too. A [_pendingLaunch] left behind
    // here is a tap that can still be redeemed later, by a platform unlock the
    // user performed for some other reason — an app opening on its own, and a
    // keyguard prompt raised to open it.
    if (!mounted || _disposed || _unlockStarted) {
      _pendingLaunch = null;
      return;
    }
    if (!isLocked) {
      // Device is already unlocked (e.g. side power-button reader satisfied keyguard).
      // Bypass any prompt and launch immediately with no delay!
      HapticFeedback.mediumImpact();
      _unlock();
      return;
    }

    final outcome = await _authenticate(app.label);
    if (!mounted || _disposed || _unlockStarted) {
      _pendingLaunch = null;
      return;
    }

    if (outcome == AuthOutcome.denied) {
      _pendingLaunch = null;
      _showTurbulence('AUTH REQUIRED TO LAUNCH ${app.label.toUpperCase()}');
      return;
    }

    // Only [AuthOutcome.verified] is an authentication, and only it gets the
    // confirming haptic. [AuthOutcome.deferToPlatform] continues for a
    // different reason: the launch itself runs through the platform keyguard,
    // which prompts before the activity can be seen. Buzzing for that would
    // tell the user they had been recognised when they had not.
    if (outcome == AuthOutcome.verified) {
      HapticFeedback.mediumImpact();
    }
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
    debugPrint(
      'Quick shortcut ${shortcut.name}: no app matched, asking platform',
    );
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
    _panelOffset.dispose();
    WidgetsBinding.instance.removeObserver(this);
    _clockTimer.cancel();
    _ambientIdleTimer?.cancel();
    _turbulenceTimer?.cancel();
    _authResolveTimer?.cancel();
    _fingerprintSubscription?.cancel();
    _mediaSubscription?.cancel();
    LauncherBridge.setScreenOnListener(null);
    LauncherBridge.setUserPresentListener(null);
    LauncherBridge.stopFingerprintScan();
    _physicsTicker.dispose();
    _slideController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    _ensurePhysicsInitialized(screenSize);
    // The band depends on the laid-out HUD, so it can only be measured after
    // this frame. Registering here (rather than from a layout callback) keeps
    // the measurement to once per real HUD change; the paint-only frame the
    // engine's notify schedules does not re-run build, so this cannot loop.
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncBubbleBand());

    // The shared helper follows the platform's 12/24-hour setting, so the
    // large clock cannot disagree with the ColorOS keyguard it replaces. In
    // 12-hour mode the day period travels in the same string (`7:05 PM`),
    // which the large typeface accepts unchanged.
    final timeString = formatClockTime(context, _currentTime);
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
                LuminousHomeTheme.lockFieldGlow,
                LuminousHomeTheme.lockField,
                LuminousHomeTheme.lockFieldDeep,
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
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          LuminousHomeTheme.softTint(
                            LuminousHomeTheme.aqua,
                            0.20,
                          ),
                          LuminousHomeTheme.softTint(
                            LuminousHomeTheme.cobalt,
                            0.08,
                          ),
                          Colors.transparent,
                        ],
                        stops: [0.0, 0.45, 1.0],
                      ),
                    ),
                  ),
                ),
              ),

              // CustomPaint canvas rendering the ambient field. The boundary
              // gives the physics layer its own repaint scope: simulation
              // frames repaint this canvas alone, and HUD state changes never
              // repaint the spheres.
              //
              // The field takes no touches and sits at 80% (55% while a
              // session plays): calmer than the now-playing card, but bright
              // enough that a dark app mark stays legible on its plate.
              Positioned.fill(
                child: IgnorePointer(
                  child: AnimatedOpacity(
                    opacity: _mediaPlaying ? 0.55 : 0.80,
                    duration: const Duration(milliseconds: 250),
                    child: RepaintBoundary(
                      key: _bubbleFieldKey,
                      child: CustomPaint(
                        painter: BouncingAppsPainter(physics: _physicsEngine),
                      ),
                    ),
                  ),
                ),
              ),

              // Scrim: keeps the unlock cluster and gesture hints readable
              // while the spheres keep drifting behind them.
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
                          LuminousHomeTheme.lockFieldDeep.withValues(alpha: 0.0),
                          LuminousHomeTheme.lockFieldDeep.withValues(
                            alpha: 0.72,
                          ),
                          LuminousHomeTheme.lockFieldDeep,
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24.0,
                    vertical: 14.0,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // The HUD is one centred column capped at [_hudMaxWidth]:
                      // on the inner display it stays a readable width in the
                      // middle of a wide (even landscape) window, while the
                      // hint and the corner shortcuts below stay full-width.
                      // The bubble band is measured from this column, so the
                      // spheres align with the card rather than the raw screen.
                      Center(
                        child: ConstrainedBox(
                          key: _hudColumnKey,
                          constraints: const BoxConstraints(
                            maxWidth: _hudMaxWidth,
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                      // Status line. The reader is the side power key, so the
                      // panel names the lock but draws no fingerprint target.
                      // Hidden on a credential-less device, where the badge
                      // would be a claim with nothing behind it.
                      if (_deviceSecure != false)
                        const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.lock_outline_rounded,
                              color: LuminousHomeTheme.textSecondary,
                              size: 14,
                            ),
                            SizedBox(width: 6),
                            Text(
                              'Locked',
                              style: TextStyle(
                                color: LuminousHomeTheme.textSecondary,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                letterSpacing: 0.3,
                              ),
                            ),
                          ],
                        ),

                      const SizedBox(height: 10),

                      // Clock, date and — only while charging — the battery
                      // line. One block, so the field has a single bottom
                      // anchor when no card is present. The status bar already
                      // carries a discharging percentage; repeating it here
                      // would be noise.
                      IgnorePointer(
                        child: Column(
                          children: [
                            Text(
                              timeString,
                              style: TextStyle(
                                color: LuminousHomeTheme.textPrimary,
                                fontSize: isTabletop
                                    ? 52
                                    : (isUnfolded ? 76 : 64),
                                fontWeight: FontWeight.w200,
                                letterSpacing: -2.0,
                                height: 1.0,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                                shadows: [
                                  Shadow(
                                    color: LuminousHomeTheme.softTint(
                                      LuminousHomeTheme.aqua,
                                      0.28,
                                    ),
                                    blurRadius: 18,
                                  ),
                                  const Shadow(
                                    color: LuminousHomeTheme.black,
                                    blurRadius: 12,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              dateFormatted,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: LuminousHomeTheme.textSecondary,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                letterSpacing: 0.2,
                                shadows: [
                                  Shadow(color: LuminousHomeTheme.black, blurRadius: 8),
                                ],
                              ),
                            ),
                            if (_batteryLabel != null) ...[
                              const SizedBox(height: 4),
                              Text(
                                _batteryLabel!,
                                style: const TextStyle(
                                  color: LuminousHomeTheme.textSecondary,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  fontFeatures: [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                              ),
                            ],
                            if (_turbulenceMessage != null) ...[
                              const SizedBox(height: 10),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: LuminousHomeTheme.softTint(
                                    LuminousHomeTheme.orchid,
                                    0.80,
                                  ),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: LuminousHomeTheme.softTint(
                                      LuminousHomeTheme.orchid,
                                      0.95,
                                    ),
                                    width: 1.0,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: LuminousHomeTheme.softTint(
                                        LuminousHomeTheme.orchid,
                                        0.40,
                                      ),
                                      blurRadius: 16,
                                    ),
                                  ],
                                ),
                                child: Text(
                                  _turbulenceMessage!,
                                  style: const TextStyle(
                                    color: LuminousHomeTheme.textPrimary,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 1.0,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),

                      if (_nowPlaying != null) const SizedBox(height: 16),

                      // The now-playing card, under the date and above the
                      // bubble field. The switcher cross-fades it in with a
                      // slight upward slide while the rest of the panel stays
                      // put; a null session swaps in a zero-size child, so
                      // there is nothing to show and nothing to nag about.
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 250),
                        switchInCurve: Curves.easeOutCubic,
                        switchOutCurve: Curves.easeInCubic,
                        transitionBuilder: (child, animation) {
                          final slide = Tween<Offset>(
                            begin: const Offset(0, 0.08),
                            end: Offset.zero,
                          ).animate(animation);
                          return FadeTransition(
                            opacity: animation,
                            child: SlideTransition(
                              position: slide,
                              child: child,
                            ),
                          );
                        },
                        child: _nowPlaying == null
                            ? const SizedBox.shrink(key: ValueKey('no-media'))
                            : KeyedSubtree(
                                key: const ValueKey('now-playing'),
                                child: _buildNowPlayingCard(),
                              ),
                      ),

                            ],
                          ),
                        ),
                      ),

                      // The band the ambient field drifts in. The key lets the
                      // field read this gap back after layout, so the spheres
                      // can never be painted over the card above or the hint
                      // below, whatever the now-playing card is doing.
                      Spacer(key: _bubbleGapKey),

                      // Unlock hint. The reader is the side power key, so no
                      // fingerprint affordance is drawn here or anywhere else
                      // on the panel; the wording changes with what the device
                      // can actually do.
                      IgnorePointer(
                        child: Column(
                          children: [
                            const Icon(
                              Icons.keyboard_arrow_up_rounded,
                              color: LuminousHomeTheme.textSecondary,
                              size: 22,
                            ),
                            Text(
                              _unlockHint,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: LuminousHomeTheme.textSecondary,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                letterSpacing: 0.3,
                                shadows: [
                                  Shadow(color: LuminousHomeTheme.black, blurRadius: 6),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 14),

                      // Quick shortcuts: phone on the left, camera on the
                      // right. These and the three media controls are the only
                      // app targets on the panel; the field between them is
                      // decoration.
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _quickActionCircle(
                            icon: Icons.phone_rounded,
                            label: 'Phone',
                            onTap: () =>
                                _openQuickShortcut(QuickShortcut.phone),
                          ),
                          _quickActionCircle(
                            icon: Icons.camera_alt_rounded,
                            label: 'Camera',
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
                          color: LuminousHomeTheme.lockFieldDeep,
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
                          onUseCredential:
                              (_authPhase == FingerprintPromptPhase.failed ||
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

  /// A 48dp corner shortcut with its own Semantics label.
  ///
  /// These are the only app targets on the panel now, so their labels name
  /// the app rather than the action a reader cannot see.
  Widget _quickActionCircle({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        label: label,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(24),
            child: Container(
              width: LuminousHomeTheme.minimumTouchTarget,
              height: LuminousHomeTheme.minimumTouchTarget,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: LuminousHomeTheme.backgroundRaised.withValues(
                  alpha: 0.54,
                ),
                border: Border.all(
                  color: LuminousHomeTheme.hairlineStrong,
                  width: 1.0,
                ),
                boxShadow: LuminousHomeTheme.floatingShadow,
              ),
              child: Icon(
                icon,
                color: LuminousHomeTheme.textPrimary,
                size: 22,
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _weekdayName(int day) {
    const names = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    return names[(day - 1) % 7];
  }

  String _monthName(int month) {
    const names = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return names[(month - 1) % 12];
  }
}

/// Test-only seam onto the panel's ambient physics engine.
///
/// The state class stays private; a test reaches the engine by typing the
/// value from `tester.state` as `State<CosmicLockScreen>` and reading
/// [physicsForTesting]. An extension rather than a public rename, so the
/// widget's public surface does not grow for tests.
extension LockScreenPhysics on State<CosmicLockScreen> {
  @visibleForTesting
  BouncingPhysicsEngine get physicsForTesting =>
      (this as _CosmicLockScreenState)._physicsEngine;
}
