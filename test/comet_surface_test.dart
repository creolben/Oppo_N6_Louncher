import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mylauncher/core/search_coordinator.dart';
import 'package:mylauncher/core/search_providers/fixture_search_provider.dart';
import 'package:mylauncher/models/web_search.dart';
import 'package:mylauncher/ui/widgets/comet_orb.dart';
import 'package:mylauncher/ui/widgets/comet_search_surface.dart';

class _StaticProvider implements SearchProvider {
  final String answer;
  final List<SearchSource> sources;

  _StaticProvider({required this.answer, this.sources = const []});

  @override
  String get name => 'Static';

  @override
  bool get requiresKey => false;

  @override
  bool get isAvailable => true;

  @override
  Stream<SearchChunk> search(String query) async* {
    yield SearchChunk(delta: answer, sources: sources);
  }
}

Widget _host(SearchCoordinator coordinator, {String? initialQuery}) {
  return MaterialApp(
    theme: ThemeData(brightness: Brightness.dark),
    home: Scaffold(
      backgroundColor: Colors.black,
      body: CometSearchSurface(
        coordinator: coordinator,
        onClose: () {},
        initialQuery: initialQuery,
      ),
    ),
  );
}

/// Pumps until an async provider's stream has been consumed and rendered.
///
/// `pumpAndSettle` cannot be used anywhere in this file: the comet orb animates
/// on a repeating controller, so the tree never reaches a steady state. Pumping
/// a bounded number of frames also drains the microtask queue, which is what
/// lets `async*` provider output land.
Future<void> _pumpUntilRendered(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  group('CometOrb', () {
    testWidgets('renders and animates without throwing', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: Center(child: CometOrb(size: 40)))),
      );
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(CometOrb), findsOneWidget);
      expect(tester.takeException(), isNull);

      // Let the repeating controller advance, then confirm it settles cleanly
      // when the tree goes away — a leaked ticker is a real launcher bug.
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    });

    testWidgets('honours the reduced-motion setting', (tester) async {
      await tester.pumpWidget(
        const MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: MaterialApp(
            home: Scaffold(body: Center(child: CometOrb(size: 40))),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.byType(CometOrb), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('CometSearchSurface', () {
    testWidgets('shows the teaching idle state before any query', (tester) async {
      final coordinator = SearchCoordinator(providers: [FixtureSearchProvider()]);
      await tester.pumpWidget(_host(coordinator));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Ask the cosmos'), findsOneWidget);
      expect(
        find.text('Type a question to get an answer with sources.'),
        findsOneWidget,
      );
    });

    testWidgets('states handoff-only mode when no provider can answer',
        (tester) async {
      final coordinator = SearchCoordinator();
      await tester.pumpWidget(_host(coordinator));
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        find.text('Type a question to send it to your search app.'),
        findsOneWidget,
      );
    });

    testWidgets('renders an answer with tappable citation and source card',
        (tester) async {
      final coordinator = SearchCoordinator(
        providers: [
          _StaticProvider(
            answer: 'The build is CPH2765 [1].',
            sources: const [
              SearchSource(
                title: 'OPPO Find N6',
                url: 'https://www.oppo.com/en/find-n6/',
                index: 1,
              ),
            ],
          ),
        ],
      );

      await tester.pumpWidget(_host(coordinator, initialQuery: 'find n6'));
      await _pumpUntilRendered(tester);

      // The answer prose and its resolved source card both render. The answer
      // goes through RichText (inline citation chips are WidgetSpans), so the
      // rich-text finder is required rather than a plain find.text.
      expect(find.textContaining('CPH2765', findRichText: true), findsOneWidget);
      expect(find.text('OPPO Find N6'), findsOneWidget);
      // Domain derived from the url, not hardcoded.
      expect(find.text('oppo.com'), findsOneWidget);
    });

    testWidgets('offers a truthful handoff action after an answer',
        (tester) async {
      final coordinator = SearchCoordinator(
        providers: [_StaticProvider(answer: 'Something [1].', sources: const [
          SearchSource(title: 'S', url: 'https://s.example', index: 1),
        ])],
      );

      await tester.pumpWidget(_host(coordinator, initialQuery: 'q'));
      await _pumpUntilRendered(tester);

      // The probe reports unknown in tests, so the neutral label must be used
      // rather than claiming a chooser will appear.
      expect(find.text('Open in search app'), findsOneWidget);
    });

    testWidgets('explains a missing key instead of hanging', (tester) async {
      final coordinator = SearchCoordinator(
        providers: [_LockedProvider()],
      );

      await tester.pumpWidget(_host(coordinator, initialQuery: 'q'));
      await _pumpUntilRendered(tester);

      expect(find.text('Inline answers are not connected'), findsOneWidget);
      expect(find.textContaining('needs an API key'), findsOneWidget);
    });

    testWidgets('disposes a mid-stream search without leaking', (tester) async {
      final coordinator = SearchCoordinator(providers: [FixtureSearchProvider()]);
      await tester.pumpWidget(_host(coordinator, initialQuery: 'coloros'));
      await tester.pump(const Duration(milliseconds: 500));

      // Tear down while the stream is still producing.
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull);
    });
  });
}

class _LockedProvider implements SearchProvider {
  @override
  String get name => 'Locked';

  @override
  bool get requiresKey => true;

  @override
  bool get isAvailable => false;

  @override
  Stream<SearchChunk> search(String query) =>
      const Stream<SearchChunk>.empty();
}
