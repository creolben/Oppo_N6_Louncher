import 'dart:typed_data';

/// One media session as the platform reported it, for the lock screen's
/// now-playing card.
///
/// The native side resolves the *primary* session (the first PLAYING one, else
/// the most recent PAUSED/BUFFERING one) and sends a snapshot of it. The
/// position travels as a value plus the platform's own update timestamp, so
/// the card can advance it between snapshots without a native round trip per
/// second.
class NowPlaying {
  /// Package that owns the session.
  final String packageName;

  /// Human-readable app name, for the card's secondary line.
  final String appLabel;

  final String? title;
  final String? artist;
  final String? album;

  /// Track length in milliseconds, or null when the platform did not report
  /// one. Null means "unknown", so the card draws no progress bar rather than
  /// one against a made-up length.
  final int? durationMs;

  /// Playback position in milliseconds at [receivedAt].
  final int positionMs;

  /// Android's `SystemClock.elapsedRealtime` at which [positionMs] was true.
  ///
  /// Kept as the platform's own reading. Dart has no equivalent monotonic
  /// clock, so [positionAt] anchors on [receivedAt] instead — see there.
  final int positionUpdatedAtMs;

  /// Playback rate; 1.0 is normal speed.
  final double speed;

  /// One of `playing`, `paused`, `buffering`, `stopped`.
  final String state;

  final bool canPrev;
  final bool canNext;
  final bool canPlayPause;

  /// Album art as PNG bytes, already bounded by the native side, or null.
  final Uint8List? art;

  /// Wall-clock instant [positionMs] was known to be true.
  ///
  /// The platform's [positionUpdatedAtMs] is elapsed realtime since boot, which
  /// has no Dart counterpart, so the model anchors on the moment the snapshot
  /// was parsed. That is at most one platform-channel hop late, which is well
  /// inside the one-second resolution the card draws at.
  final DateTime receivedAt;

  NowPlaying({
    required this.packageName,
    required this.appLabel,
    this.title,
    this.artist,
    this.album,
    this.durationMs,
    this.positionMs = 0,
    this.positionUpdatedAtMs = 0,
    this.speed = 1.0,
    this.state = 'stopped',
    this.canPrev = false,
    this.canNext = false,
    this.canPlayPause = false,
    this.art,
    DateTime? receivedAt,
  }) : receivedAt = receivedAt ?? DateTime.now();

  bool get isPlaying => state == 'playing';

  bool get hasDuration => durationMs != null && durationMs! > 0;

  /// Builds a snapshot from the native `media` event map.
  ///
  /// Every field is optional on the wire: a session can legitimately have no
  /// title, no artist, no duration and no art, and a missing field must read as
  /// "unknown" rather than crashing the lock screen.
  factory NowPlaying.fromMap(
    Map<String, dynamic> map, {
    DateTime? receivedAt,
  }) {
    final packageName = map['packageName'] as String? ?? '';
    return NowPlaying(
      packageName: packageName,
      appLabel: _nonEmpty(map['appLabel']) ?? packageName,
      title: _nonEmpty(map['title']),
      artist: _nonEmpty(map['artist']),
      album: _nonEmpty(map['album']),
      durationMs: (map['durationMs'] as num?)?.toInt(),
      positionMs: (map['positionMs'] as num?)?.toInt() ?? 0,
      positionUpdatedAtMs: (map['positionUpdatedAtMs'] as num?)?.toInt() ?? 0,
      speed: (map['speed'] as num?)?.toDouble() ?? 1.0,
      state: map['state'] as String? ?? 'stopped',
      canPrev: map['canPrev'] == true,
      canNext: map['canNext'] == true,
      canPlayPause: map['canPlayPause'] == true,
      art: map['art'] is Uint8List ? map['art'] as Uint8List : null,
      receivedAt: receivedAt,
    );
  }

  /// Where playback is at [now].
  ///
  /// While playing, the last known position is advanced by the wall-clock time
  /// since it was received, scaled by [speed]. While paused or stopped it does
  /// not move at all. The result is clamped to [durationMs] when one is known,
  /// so a track that ends between the timer's ticks cannot report a position
  /// past its own end.
  Duration positionAt(DateTime now) {
    var position = positionMs.toDouble();
    if (isPlaying) {
      final elapsedMs = now.difference(receivedAt).inMilliseconds;
      if (elapsedMs > 0) {
        final rate = speed > 0 ? speed : 1.0;
        position += elapsedMs * rate;
      }
    }
    final total = durationMs;
    if (total != null && total > 0) {
      position = position.clamp(0, total.toDouble()).toDouble();
    } else if (position < 0) {
      position = 0;
    }
    return Duration(milliseconds: position.round());
  }

  /// A snapshot stands for the same track across position updates, so equality
  /// deliberately ignores position, art and capabilities: only identity and
  /// transport state decide whether the card needs rebuilding.
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NowPlaying &&
          other.packageName == packageName &&
          other.title == title &&
          other.artist == artist &&
          other.state == state;

  @override
  int get hashCode => Object.hash(packageName, title, artist, state);

  static String? _nonEmpty(Object? value) {
    if (value is String && value.trim().isNotEmpty) return value;
    return null;
  }
}
