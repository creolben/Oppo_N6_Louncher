import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../../models/app_entry.dart';

/// What the lock screen's fingerprint prompt is currently telling the user.
enum FingerprintPromptPhase {
  /// The reader is armed and waiting for a touch.
  scanning,

  /// A finger was read but did not match; the reader stays armed.
  failed,

  /// The reader matched and the launch is being handed to the platform.
  verified,
}

/// The lock screen's own fingerprint prompt.
///
/// The platform's `BiometricPrompt` always draws a system dialog with its own
/// type, colour and spacing, which is the one piece of the lock screen that
/// cannot be made to look like the rest of the launcher. This is the same
/// authentication drawn in the launcher's own cosmic language instead: the
/// panel owns the affordance, and the native side reports the reader's raw
/// events over an event channel rather than raising a dialog.
class FingerprintAuthPrompt extends StatefulWidget {
  /// The app the user is authenticating for, named so the prompt says what
  /// the finger is unlocking rather than just "authenticate".
  final AppEntry app;

  final FingerprintPromptPhase phase;

  /// Dismisses the prompt and abandons the pending launch.
  final VoidCallback onCancel;

  /// Present once the finger itself is the problem — a run of non-matches, or a
  /// reader that died mid-prompt — so the user is not stuck waiting on a sensor
  /// that is not going to answer.
  final Future<void> Function()? onUseCredential;

  const FingerprintAuthPrompt({
    super.key,
    required this.app,
    required this.phase,
    required this.onCancel,
    this.onUseCredential,
  });

  @override
  State<FingerprintAuthPrompt> createState() => _FingerprintAuthPromptState();
}

class _FingerprintAuthPromptState extends State<FingerprintAuthPrompt>
    with TickerProviderStateMixin {
  // The launcher's cosmic tokens, kept in one place so the prompt cannot drift
  // away from the panel behind it.
  static const Color _cyan = Color(0xFF00E5FF);
  static const Color _violet = Color(0xFF7C4DFF);
  static const Color _glass = Color(0xFF0D1426);

  /// The breathing reader rings. Repeats for as long as the prompt is up.
  late final AnimationController _pulse;

  /// The card's entrance. A separate controller on purpose: driving this from
  /// the repeating pulse made the whole card fade back in at the start of every
  /// pulse cycle — a flash every 1.9 seconds, and, because a fully transparent
  /// [FadeTransition] drops its subtree from the semantics tree, a card that
  /// periodically disappeared for a screen reader as well.
  late final AnimationController _entranceController;
  late final Animation<double> _entrance;

  /// Null until the first dependency pass, so the animations below actually
  /// start: initialising this to `false` made the first `didChangeDependencies`
  /// a no-op, which left the entrance at opacity 0 — an invisible prompt.
  bool? _reduceMotion;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1900),
    );
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    );
    _entrance = CurvedAnimation(
      parent: _entranceController,
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // A pulse that never stops is decoration, and decoration is exactly what
    // reduce-motion asks to be spared.
    final bool reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduce == _reduceMotion) return;
    _reduceMotion = reduce;
    if (reduce) {
      _pulse.stop();
      _pulse.value = 0.0;
      _entranceController.value = 1.0;
    } else {
      _pulse.repeat();
      _entranceController.forward();
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    _entranceController.dispose();
    super.dispose();
  }

  Color get _stateColor {
    switch (widget.phase) {
      case FingerprintPromptPhase.scanning:
        return _cyan;
      case FingerprintPromptPhase.failed:
        return const Color(0xFFFFB74D);
      case FingerprintPromptPhase.verified:
        return const Color(0xFF81C784);
    }
  }

  String get _status {
    switch (widget.phase) {
      case FingerprintPromptPhase.scanning:
        return 'TOUCH THE SENSOR TO CONTINUE';
      case FingerprintPromptPhase.failed:
        return 'NOT RECOGNISED • TOUCH AGAIN';
      case FingerprintPromptPhase.verified:
        return 'VERIFIED • OPENING';
    }
  }

  String get _semanticStatus {
    switch (widget.phase) {
      case FingerprintPromptPhase.scanning:
        return 'Touch the fingerprint sensor to open ${widget.app.label}';
      case FingerprintPromptPhase.failed:
        return 'Fingerprint not recognised. Touch the sensor again';
      case FingerprintPromptPhase.verified:
        return 'Fingerprint verified. Opening ${widget.app.label}';
    }
  }

  @override
  Widget build(BuildContext context) {
    final Color accent = _stateColor;

    return Semantics(
      // A live region so the status change ("not recognised", "verified") is
      // announced without the user having to go looking for it.
      container: true,
      liveRegion: true,
      label: 'Fingerprint required',
      value: _semanticStatus,
      child: FadeTransition(
        opacity: (_reduceMotion ?? false)
            ? const AlwaysStoppedAnimation<double>(1.0)
            : _entrance,
        child: Center(child: _buildCard(context, accent)),
      ),
    );
  }

  Widget _buildCard(BuildContext context, Color accent) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 30.0),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 340),
        child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(26, 28, 26, 22),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xF20D1426), Color(0xF2070A14)],
              ),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                color: accent.withValues(alpha: 0.45),
                width: 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: accent.withValues(alpha: 0.18),
                  blurRadius: 34,
                  spreadRadius: 2,
                ),
                // A second, colder halo so the card sits in the same violet
                // nebula light the panel's background is built from.
                BoxShadow(
                  color: _violet.withValues(alpha: 0.14),
                  blurRadius: 46,
                  spreadRadius: -6,
                ),
                const BoxShadow(
                  color: Color(0x99000000),
                  blurRadius: 26,
                  offset: Offset(0, 12),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildSensorDisc(accent),
                const SizedBox(height: 22),
                // The visible title and status are the same words the container
                // node already carries as its label and value. Left in, they
                // merge into it and a reader hears every line twice; excluded,
                // the prompt is announced once, exactly as written below.
                ExcludeSemantics(
                  child: Text(
                    widget.phase == FingerprintPromptPhase.verified
                        ? 'UNLOCKED'
                        : 'FINGERPRINT REQUIRED',
                    style: TextStyle(
                      color: accent,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 2.6,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                _buildAppRow(accent),
                const SizedBox(height: 10),
                ExcludeSemantics(
                  child: Text(
                    _status,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.72),
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.4,
                      height: 1.5,
                    ),
                  ),
                ),
                const SizedBox(height: 22),
                _buildActions(accent),
              ],
            ),
          ),
        ],
        ),
      ),
    );
  }

  /// The pulsing reader glyph.
  ///
  /// Two staggered rings rather than one, so the animation reads as a sensor
  /// breathing rather than a single blinking outline.
  Widget _buildSensorDisc(Color accent) {
    return SizedBox(
      width: 104,
      height: 104,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (!(_reduceMotion ?? false))
            AnimatedBuilder(
              animation: _pulse,
              builder: (context, _) {
                return Stack(
                  alignment: Alignment.center,
                  children: [
                    _ring(_pulse.value, accent),
                    _ring((_pulse.value + 0.5) % 1.0, accent),
                  ],
                );
              },
            )
          else
            _ring(0.55, accent),
          Container(
            width: 70,
            height: 70,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  accent.withValues(alpha: 0.28),
                  accent.withValues(alpha: 0.06),
                  Colors.transparent,
                ],
                stops: const [0.2, 0.65, 1.0],
              ),
            ),
          ),
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _glass.withValues(alpha: 0.9),
              border: Border.all(
                color: accent.withValues(alpha: 0.75),
                width: 1.4,
              ),
              boxShadow: [
                BoxShadow(
                  color: accent.withValues(alpha: 0.35),
                  blurRadius: 18,
                ),
              ],
            ),
            child: Icon(
              widget.phase == FingerprintPromptPhase.verified
                  ? Icons.check_rounded
                  : Icons.fingerprint_rounded,
              color: accent,
              size: 32,
            ),
          ),
        ],
      ),
    );
  }

  Widget _ring(double progress, Color accent) {
    final double eased = Curves.easeOutCubic.transform(progress);
    return Opacity(
      opacity: ((1.0 - progress) * 0.55).clamp(0.0, 1.0),
      child: Transform.scale(
        scale: 0.72 + eased * 0.62,
        child: Container(
          width: 94,
          height: 94,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: accent.withValues(alpha: 0.7),
              width: 1.4,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAppRow(Color accent) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildAppIcon(accent),
        const SizedBox(width: 10),
        Flexible(
          child: ExcludeSemantics(
            // Already named by the prompt's spoken status ("... to open
            // Camera"), so announcing the label again is just repetition.
            child: Text(
              widget.app.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.2,
                shadows: [Shadow(color: Colors.black, blurRadius: 8)],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAppIcon(Color accent) {
    final ui.Image? icon = widget.app.decodedIcon;
    return Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: accent.withValues(alpha: 0.35), width: 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: icon == null
          ? Icon(widget.app.fallbackIcon, size: 18, color: accent)
          : RawImage(image: icon, fit: BoxFit.cover, filterQuality: FilterQuality.medium),
    );
  }

  Widget _buildActions(Color accent) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _pillButton(
          label: 'CANCEL',
          semanticLabel: 'Cancel and stay on the lock screen',
          onTap: widget.onCancel,
          accent: accent,
          filled: false,
        ),
        if (widget.onUseCredential != null) ...[
          const SizedBox(width: 12),
          _pillButton(
            label: 'USE PIN',
            semanticLabel: 'Use the device PIN instead of the fingerprint',
            onTap: () => widget.onUseCredential!.call(),
            accent: accent,
            filled: true,
          ),
        ],
      ],
    );
  }

  Widget _pillButton({
    required String label,
    required String semanticLabel,
    required VoidCallback onTap,
    required Color accent,
    required bool filled,
  }) {
    return Semantics(
      // `container` gives the button a node of its own instead of folding its
      // label into the prompt's, so a reader lands on a control it can name and
      // press rather than on one long description. The tap action is declared
      // here rather than left to the InkWell because `excludeSemantics` drops
      // the InkWell's own node — and with it the action, leaving a button a
      // reader could hear but not press.
      container: true,
      button: true,
      label: semanticLabel,
      onTap: onTap,
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            // 44 logical pixels is the smallest target a finger hits reliably;
            // the prompt is the only thing on screen, so there is no reason to
            // shrink it to fit.
            constraints: const BoxConstraints(minHeight: 44),
            padding: const EdgeInsets.symmetric(horizontal: 18),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: filled
                  ? accent.withValues(alpha: 0.18)
                  : Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: filled
                    ? accent.withValues(alpha: 0.75)
                    : Colors.white.withValues(alpha: 0.22),
                width: filled ? 1.2 : 0.9,
              ),
            ),
            child: Text(
              label,
              style: TextStyle(
                color: filled ? accent : Colors.white.withValues(alpha: 0.82),
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.6,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
