import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/now_playing.dart';
import '../../ui/theme/luminous_home_theme.dart';

/// The lock screen's now-playing card.
///
/// It mirrors the platform's primary media session — art, title, artist, a thin
/// progress line and three transport buttons — using only [LuminousHomeTheme]
/// tokens, so it reads as part of the same design system as the rest of the
/// launcher rather than a second palette.
///
/// It owns one clock: a 1-second periodic timer that runs only while playback
/// is actually moving and only while the widget is mounted. Position is
/// extrapolated by [NowPlaying.positionAt], which the native side deliberately
/// does not do — it emits on metadata/transport changes only, never per tick.
class NowPlayingCard extends StatefulWidget {
  final NowPlaying nowPlaying;

  /// Sends `playPause`, `next` or `previous` to the platform. Injectable so a
  /// test can hold the transport without a platform channel.
  final Future<bool> Function(String command)? onCommand;

  const NowPlayingCard({super.key, required this.nowPlaying, this.onCommand});

  @override
  State<NowPlayingCard> createState() => _NowPlayingCardState();
}

class _NowPlayingCardState extends State<NowPlayingCard> {
  Timer? _progressTimer;

  @override
  void initState() {
    super.initState();
    _syncProgressTimer();
  }

  @override
  void didUpdateWidget(covariant NowPlayingCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncProgressTimer();
  }

  @override
  void dispose() {
    _progressTimer?.cancel();
    super.dispose();
  }

  /// Starts the once-a-second repaint only while playing.
  ///
  /// No per-frame work: the position is a function of the wall clock, so one
  /// tick a second is enough to move the bar. A paused card needs no timer at
  /// all, and leaving one running would burn a wakeup per second on the lock
  /// screen for a line that never moves.
  void _syncProgressTimer() {
    if (widget.nowPlaying.isPlaying) {
      _progressTimer ??= Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else {
      _progressTimer?.cancel();
      _progressTimer = null;
    }
  }

  Future<void> _send(String command) async {
    HapticFeedback.selectionClick();
    final handler = widget.onCommand;
    if (handler == null) return;
    try {
      await handler(command);
    } catch (error) {
      debugPrint('CF_MEDIA: transport command "$command" failed: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = widget.nowPlaying;
    // The card is a fixed 420dp surface on a lock screen; an accessibility text
    // scale of 2.0 would overflow it. Clamping here keeps the type readable
    // while the rest of the panel still scales freely.
    final textScaler = MediaQuery.textScalerOf(
      context,
    ).clamp(maxScaleFactor: 1.4);

    return MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: textScaler),
      child: Material(
        type: MaterialType.transparency,
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
          decoration: BoxDecoration(
            color: LuminousHomeTheme.glassOpaqueStrong,
            borderRadius: BorderRadius.circular(LuminousHomeTheme.cardRadius),
            border: Border.all(color: LuminousHomeTheme.hairlineStrong),
            boxShadow: LuminousHomeTheme.floatingShadow,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  _art(),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          media.title ?? media.appLabel,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: LuminousHomeTheme.textPrimary,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _subtitle(media),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: LuminousHomeTheme.textSecondary,
                            fontSize: 12,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (media.hasDuration) ...[
                const SizedBox(height: 10),
                _progressBar(media),
              ],
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _transportButton(
                    icon: Icons.skip_previous_rounded,
                    label: 'Previous track',
                    enabled: media.canPrev,
                    onPressed: () => unawaited(_send('previous')),
                  ),
                  _transportButton(
                    icon: media.isPlaying
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                    // The label flips with state because the same button is
                    // both: a screen reader must hear what the next press does.
                    label: media.isPlaying ? 'Pause' : 'Play',
                    enabled: media.canPlayPause,
                    onPressed: () => unawaited(_send('playPause')),
                  ),
                  _transportButton(
                    icon: Icons.skip_next_rounded,
                    label: 'Next track',
                    enabled: media.canNext,
                    onPressed: () => unawaited(_send('next')),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _subtitle(NowPlaying media) {
    final artist = media.artist;
    if (artist == null || artist.isEmpty) return media.appLabel;
    return '$artist • ${media.appLabel}';
  }

  Widget _art() {
    const double size = 56;
    final radius = BorderRadius.circular(LuminousHomeTheme.iconRadius);
    final art = widget.nowPlaying.art;
    if (art == null || art.isEmpty) {
      return ClipRRect(
        borderRadius: radius,
        child: Container(
          width: size,
          height: size,
          color: LuminousHomeTheme.glassStrong,
          child: const Icon(
            Icons.music_note_rounded,
            color: LuminousHomeTheme.textSecondary,
            size: 24,
          ),
        ),
      );
    }
    return ClipRRect(
      borderRadius: radius,
      child: Image.memory(
        art,
        width: size,
        height: size,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (context, error, stackTrace) => Container(
          width: size,
          height: size,
          color: LuminousHomeTheme.glassStrong,
          child: const Icon(
            Icons.music_note_rounded,
            color: LuminousHomeTheme.textSecondary,
            size: 24,
          ),
        ),
      ),
    );
  }

  /// Elapsed and remaining time either side of a 3dp progress line.
  ///
  /// The labels are the reason the bar exists: a bare line tells the user
  /// nothing they can act on. Both ride the existing once-a-second timer while
  /// playing, and neither is shown when the platform did not report a length —
  /// a count against an unknown total would be a guess.
  Widget _progressBar(NowPlaying media) {
    final total = media.durationMs!;
    final position = media.positionAt(DateTime.now());
    final progress =
        (position.inMilliseconds / total).clamp(0.0, 1.0).toDouble();
    final remaining = Duration(
      milliseconds: (total - position.inMilliseconds).clamp(0, total).toInt(),
    );
    final labelStyle = const TextStyle(
      color: LuminousHomeTheme.textSecondary,
      fontSize: 10,
      fontWeight: FontWeight.w500,
      fontFeatures: [FontFeature.tabularFigures()],
    );

    return Row(
      children: [
        Text(_formatTime(position), style: labelStyle),
        const SizedBox(width: 8),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 4,
              // The track is a hairline-strong tone so the unfilled part is
              // visible against the opaque card, not a hole in it.
              backgroundColor: LuminousHomeTheme.hairlineStrong,
              color: LuminousHomeTheme.aqua,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text('-${_formatTime(remaining)}', style: labelStyle),
      ],
    );
  }

  /// `m:ss`, or `h:mm:ss` for a track longer than an hour.
  static String _formatTime(Duration duration) {
    final int total = duration.inSeconds;
    final int hours = total ~/ 3600;
    final int minutes = (total % 3600) ~/ 60;
    final int seconds = total % 60;
    final String twoDigitSeconds = seconds.toString().padLeft(2, '0');
    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:$twoDigitSeconds';
    }
    return '$minutes:$twoDigitSeconds';
  }

  /// A transport button with an explicit 48dp target and its own Semantics
  /// label, so a reader hears the action and a touch anywhere in the target
  /// lands it.
  Widget _transportButton({
    required IconData icon,
    required String label,
    required bool enabled,
    required VoidCallback onPressed,
  }) {
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      onTap: enabled ? onPressed : null,
      child: ExcludeSemantics(
        child: SizedBox(
          width: LuminousHomeTheme.minimumTouchTarget,
          height: LuminousHomeTheme.minimumTouchTarget,
          child: IconButton(
            onPressed: enabled ? onPressed : null,
            padding: EdgeInsets.zero,
            icon: Icon(
              icon,
              size: 26,
              color: enabled
                  ? LuminousHomeTheme.textPrimary
                  : LuminousHomeTheme.textMuted,
            ),
          ),
        ),
      ),
    );
  }
}
