import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mylauncher/models/now_playing.dart';

/// The now-playing snapshot parser and position extrapolator.
///
/// The native side sends a value plus an update anchor and deliberately does
/// not tick; everything about the moving progress line is decided here, so
/// these are the rules the card relies on.

void main() {
  group('NowPlaying.fromMap', () {
    test('parses a full snapshot', () {
      final media = NowPlaying.fromMap({
        'packageName': 'com.spotify.music',
        'appLabel': 'Spotify',
        'title': 'Song',
        'artist': 'Artist',
        'album': 'Album',
        'durationMs': 200000,
        'positionMs': 1000,
        'positionUpdatedAtMs': 123456,
        'speed': 1.25,
        'state': 'playing',
        'canPrev': true,
        'canNext': true,
        'canPlayPause': true,
        'art': Uint8List.fromList([1, 2, 3]),
      });

      expect(media.packageName, equals('com.spotify.music'));
      expect(media.appLabel, equals('Spotify'));
      expect(media.title, equals('Song'));
      expect(media.artist, equals('Artist'));
      expect(media.album, equals('Album'));
      expect(media.durationMs, equals(200000));
      expect(media.positionMs, equals(1000));
      expect(media.positionUpdatedAtMs, equals(123456));
      expect(media.speed, equals(1.25));
      expect(media.isPlaying, isTrue);
      expect(media.canPrev, isTrue);
      expect(media.canNext, isTrue);
      expect(media.canPlayPause, isTrue);
      expect(media.art, equals(Uint8List.fromList([1, 2, 3])));
    });

    test('missing fields read as unknown rather than crashing', () {
      final media = NowPlaying.fromMap({'packageName': 'com.test.music'});

      expect(media.packageName, equals('com.test.music'));
      expect(media.title, isNull);
      expect(media.artist, isNull);
      expect(media.album, isNull);
      expect(media.durationMs, isNull);
      expect(media.hasDuration, isFalse);
      expect(media.positionMs, equals(0));
      expect(media.positionUpdatedAtMs, equals(0));
      expect(media.speed, equals(1.0));
      expect(media.state, equals('stopped'));
      expect(media.isPlaying, isFalse);
      expect(media.canPrev, isFalse);
      expect(media.canNext, isFalse);
      expect(media.canPlayPause, isFalse);
      expect(media.art, isNull);
    });

    test('blank strings are treated as missing', () {
      final media = NowPlaying.fromMap({
        'packageName': 'com.test.music',
        'title': '   ',
        'artist': '',
      });

      expect(media.title, isNull);
      expect(media.artist, isNull);
    });
  });

  group('NowPlaying.positionAt', () {
    final anchor = DateTime(2026, 1, 1, 12, 0, 0);

    NowPlaying playing({int positionMs = 1000, int? durationMs = 60000}) {
      return NowPlaying(
        packageName: 'com.test.music',
        appLabel: 'Music',
        title: 'Track',
        state: 'playing',
        positionMs: positionMs,
        durationMs: durationMs,
        receivedAt: anchor,
      );
    }

    test('extrapolates from the anchor while playing', () {
      final media = playing();
      expect(
        media.positionAt(anchor.add(const Duration(seconds: 5))),
        equals(const Duration(seconds: 6)),
      );
    });

    test('scales with playback speed', () {
      final media = NowPlaying(
        packageName: 'com.test.music',
        appLabel: 'Music',
        state: 'playing',
        positionMs: 0,
        speed: 2.0,
        receivedAt: anchor,
      );
      expect(
        media.positionAt(anchor.add(const Duration(seconds: 5))),
        equals(const Duration(seconds: 10)),
      );
    });

    test('clamps to the duration when one is known', () {
      final media = playing();
      expect(
        media.positionAt(anchor.add(const Duration(minutes: 5))),
        equals(const Duration(seconds: 60)),
      );
    });

    test('a paused session does not advance', () {
      final media = NowPlaying(
        packageName: 'com.test.music',
        appLabel: 'Music',
        state: 'paused',
        positionMs: 3000,
        durationMs: 60000,
        receivedAt: anchor,
      );
      expect(
        media.positionAt(anchor.add(const Duration(seconds: 30))),
        equals(const Duration(seconds: 3)),
      );
    });
  });

  group('NowPlaying identity', () {
    test('equality ignores position and art but tracks track and state', () {
      final base = NowPlaying(
        packageName: 'com.test.music',
        appLabel: 'Music',
        title: 'Track',
        artist: 'Artist',
        state: 'playing',
        positionMs: 0,
      );
      final later = NowPlaying(
        packageName: 'com.test.music',
        appLabel: 'Music',
        title: 'Track',
        artist: 'Artist',
        state: 'playing',
        positionMs: 30000,
      );
      final paused = NowPlaying(
        packageName: 'com.test.music',
        appLabel: 'Music',
        title: 'Track',
        artist: 'Artist',
        state: 'paused',
      );

      expect(base, equals(later));
      expect(base.hashCode, equals(later.hashCode));
      expect(base, isNot(equals(paused)));
    });
  });
}
