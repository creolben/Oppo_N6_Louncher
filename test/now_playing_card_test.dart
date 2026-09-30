import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mylauncher/features/lockscreen/now_playing_card.dart';
import 'package:mylauncher/models/now_playing.dart';

/// The lock screen's now-playing card: what it renders and what its transport
/// buttons do. No platform channel is involved — the command seam is injected.

NowPlaying _media({
  String state = 'paused',
  bool canPrev = true,
  bool canNext = true,
  bool canPlayPause = true,
}) {
  return NowPlaying(
    packageName: 'com.test.music',
    appLabel: 'Music',
    title: 'Track One',
    artist: 'Artist One',
    durationMs: 180000,
    positionMs: 30000,
    state: state,
    canPrev: canPrev,
    canNext: canNext,
    canPlayPause: canPlayPause,
  );
}

Future<void> _pump(
  WidgetTester tester,
  NowPlaying media, {
  Future<bool> Function(String command)? onCommand,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: NowPlayingCard(nowPlaying: media, onCommand: onCommand),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('renders the title and artist from the session', (tester) async {
    await _pump(tester, _media());

    expect(find.text('Track One'), findsOneWidget);
    expect(find.textContaining('Artist One'), findsOneWidget);
  });

  testWidgets('shows elapsed and remaining time beside the progress line', (
    tester,
  ) async {
    await _pump(tester, _media());

    // 30 s into a 3:00 track: elapsed on the left, remaining on the right.
    expect(find.text('0:30'), findsOneWidget);
    expect(find.text('-2:30'), findsOneWidget);
  });

  testWidgets('the play/pause label flips with playback state', (tester) async {
    final semantics = tester.ensureSemantics();

    await _pump(tester, _media(state: 'playing'));
    expect(find.bySemanticsLabel('Pause'), findsOneWidget);
    expect(find.bySemanticsLabel('Play'), findsNothing);

    await _pump(tester, _media(state: 'paused'));
    expect(find.bySemanticsLabel('Play'), findsOneWidget);
    expect(find.bySemanticsLabel('Pause'), findsNothing);

    semantics.dispose();
  });

  testWidgets('tapping next sends the next command through the seam', (
    tester,
  ) async {
    final commands = <String>[];
    final semantics = tester.ensureSemantics();

    await _pump(
      tester,
      _media(),
      onCommand: (command) async {
        commands.add(command);
        return true;
      },
    );

    await tester.tap(find.bySemanticsLabel('Next track'));
    await tester.pump();

    expect(commands, equals(['next']));

    semantics.dispose();
  });
}
