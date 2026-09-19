import 'package:flutter_test/flutter_test.dart';
import 'package:mylauncher/core/search_coordinator.dart';
import 'package:mylauncher/core/search_providers/fixture_search_provider.dart';
import 'package:mylauncher/models/web_search.dart';
import 'package:mylauncher/ui/widgets/answer_body.dart';

/// A provider with scripted behaviour, so coordinator states can be driven
/// deterministically instead of waiting on fixture timing.
class _ScriptedProvider implements SearchProvider {
  final List<SearchChunk> chunks;
  final Object? error;
  final bool available;
  final bool needsKey;

  _ScriptedProvider({
    this.chunks = const [],
    this.error,
    this.available = true,
    this.needsKey = false,
  });

  @override
  String get name => 'Scripted';

  @override
  bool get requiresKey => needsKey;

  @override
  bool get isAvailable => available;

  @override
  Stream<SearchChunk> search(String query) async* {
    if (error != null) throw error!;
    for (final chunk in chunks) {
      yield chunk;
    }
  }
}

/// A provider that never completes, for exercising cancellation.
class _HangingProvider implements SearchProvider {
  @override
  String get name => 'Hanging';

  @override
  bool get requiresKey => false;

  @override
  bool get isAvailable => true;

  @override
  Stream<SearchChunk> search(String query) {
    return Stream<SearchChunk>.periodic(
      const Duration(milliseconds: 5),
      (_) => const SearchChunk(delta: 'x'),
    );
  }
}

void main() {
  group('Citation parsing', () {
    const sources = [
      SearchSource(title: 'One', url: 'https://one.example/a', index: 1),
      SearchSource(title: 'Two', url: 'https://two.example/b', index: 2),
    ];

    test('splits prose around valid markers', () {
      final segments = parseAnswerSegments('Alpha [1] beta [2] gamma', sources);

      expect(segments.length, 5);
      expect((segments[0] as AnswerText).text, 'Alpha ');
      expect((segments[1] as AnswerCitation).number, 1);
      expect((segments[2] as AnswerText).text, ' beta ');
      expect((segments[3] as AnswerCitation).number, 2);
      expect((segments[4] as AnswerText).text, ' gamma');
    });

    test('leaves markers with no matching source as literal text', () {
      // A citation that resolves to nothing must not render as a dead chip.
      final segments = parseAnswerSegments('Alpha [9] beta', sources);

      expect(segments.length, 1);
      expect((segments.single as AnswerText).text, 'Alpha [9] beta');
    });

    test('tolerates a marker split across a stream boundary', () {
      // This is the real streaming hazard: a chunk boundary inside "[1".
      final partial = parseAnswerSegments('Reported earlier [1', sources);
      expect(partial.length, 1);
      expect((partial.single as AnswerText).text, 'Reported earlier [1');

      final completed = parseAnswerSegments('Reported earlier [1]', sources);
      expect(completed.length, 2);
      expect((completed.last as AnswerCitation).number, 1);
    });

    test('handles empty and marker-free input', () {
      expect(parseAnswerSegments('', sources), isEmpty);
      final plain = parseAnswerSegments('No citations here', sources);
      expect(plain.length, 1);
      expect((plain.single as AnswerText).text, 'No citations here');
    });

    test('resolves a trailing marker at the very end of the answer', () {
      final segments = parseAnswerSegments('Done [2]', sources);
      expect(segments.length, 2);
      expect((segments.last as AnswerCitation).number, 2);
    });
  });

  group('Source display', () {
    test('strips www and derives domain from url', () {
      const source = SearchSource(
        title: 'T',
        url: 'https://www.example.com/path',
        index: 1,
      );
      expect(source.displayDomain, 'example.com');
    });

    test('prefers an explicit domain when supplied', () {
      const source = SearchSource(
        title: 'T',
        url: 'https://www.example.com/path',
        index: 1,
        domain: 'example.com',
      );
      expect(source.displayDomain, 'example.com');
    });
  });

  group('SearchCoordinator', () {
    test('accumulates streamed deltas instead of replacing them', () async {
      final coordinator = SearchCoordinator(
        providers: [
          _ScriptedProvider(chunks: const [
            SearchChunk(delta: 'Hello '),
            SearchChunk(delta: 'brave '),
            SearchChunk(delta: 'world'),
          ]),
        ],
      );

      await coordinator.search('q');
      expect(coordinator.result.answer, 'Hello brave world');
      expect(coordinator.result.phase, SearchPhase.complete);
    });

    test('collects sources and de-duplicates by url', () async {
      final coordinator = SearchCoordinator(
        providers: [
          _ScriptedProvider(chunks: const [
            SearchChunk(sources: [
              SearchSource(title: 'A', url: 'https://a.example', index: 1),
            ]),
            SearchChunk(
              delta: 'text',
              sources: [
                SearchSource(title: 'A again', url: 'https://a.example', index: 1),
                SearchSource(title: 'B', url: 'https://b.example', index: 2),
              ],
            ),
          ]),
        ],
      );

      await coordinator.search('q');
      expect(coordinator.result.sources.length, 2);
      expect(coordinator.result.sources.map((s) => s.url), [
        'https://a.example',
        'https://b.example',
      ]);
    });

    test('reports needsKey rather than failing when a provider is locked',
        () async {
      final coordinator = SearchCoordinator(
        providers: [
          _ScriptedProvider(available: false, needsKey: true),
        ],
      );

      await coordinator.search('q');
      expect(coordinator.result.phase, SearchPhase.needsKey);
      expect(coordinator.isHandoffOnly, isTrue);
      expect(coordinator.lockedProviderNames, ['Scripted']);
    });

    test('reports unavailable when no provider is registered at all', () async {
      final coordinator = SearchCoordinator();
      await coordinator.search('q');

      expect(coordinator.result.phase, SearchPhase.unavailable);
      expect(coordinator.isHandoffOnly, isTrue);
      expect(coordinator.activeProvider, isNull);
    });

    test('skips a locked provider in favour of an available one', () async {
      final coordinator = SearchCoordinator(
        providers: [
          _ScriptedProvider(available: false, needsKey: true),
          _ScriptedProvider(chunks: const [SearchChunk(delta: 'fallback')]),
        ],
      );

      await coordinator.search('q');
      expect(coordinator.activeProvider, isNotNull);
      expect(coordinator.result.answer, 'fallback');
      expect(coordinator.isHandoffOnly, isFalse);
    });

    test('surfaces a thrown provider error as a failed search', () async {
      final coordinator = SearchCoordinator(
        providers: [_ScriptedProvider(error: StateError('boom'))],
      );

      await coordinator.search('q');
      expect(coordinator.result.phase, SearchPhase.failed);
      expect(coordinator.result.errorMessage, contains('boom'));
    });

    test('ignores an empty query', () async {
      final coordinator = SearchCoordinator(providers: [_ScriptedProvider()]);
      await coordinator.search('   ');
      expect(coordinator.result.phase, SearchPhase.idle);
    });

    test('cancelling mid-flight stops further accumulation', () async {
      final coordinator = SearchCoordinator(providers: [_HangingProvider()]);

      final pending = coordinator.search('q');
      await Future<void>.delayed(const Duration(milliseconds: 30));
      final seenBeforeCancel = coordinator.result.answer.length;

      await coordinator.cancel();
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(coordinator.result.answer.length, seenBeforeCancel);
      // Let the hanging stream's future settle so no timer survives the test.
      await pending.timeout(
        const Duration(seconds: 1),
        onTimeout: () {},
      );
    });

    test('reset returns to idle', () async {
      final coordinator = SearchCoordinator(
        providers: [_ScriptedProvider(chunks: const [SearchChunk(delta: 'x')])],
      );
      await coordinator.search('q');
      coordinator.reset();

      expect(coordinator.result.phase, SearchPhase.idle);
      expect(coordinator.result.answer, isEmpty);
    });
  });

  group('FixtureSearchProvider', () {
    test('streams a non-empty answer with at least one source', () async {
      final provider = FixtureSearchProvider();
      expect(provider.isAvailable, isTrue);
      expect(provider.requiresKey, isFalse);

      final chunks = await provider.search('oppo find n6').toList();
      expect(chunks, isNotEmpty);

      final text = chunks.map((c) => c.delta).join();
      expect(text.trim(), isNotEmpty);
      expect(chunks.expand((c) => c.sources), isNotEmpty);
    });

    test('emits deltas that concatenate without loss', () async {
      final provider = FixtureSearchProvider();
      final chunks = await provider.search('coloros').toList();
      final joined = chunks.map((c) => c.delta).join();
      expect(joined, contains('ColorOS'));
      // Word-splitting must not leave doubled or missing spaces.
      expect(joined, isNot(contains('  ')));
    });

    test('answers unknown queries rather than returning nothing', () async {
      final provider = FixtureSearchProvider();
      final chunks = await provider.search('zzzz not a real topic').toList();
      final joined = chunks.map((c) => c.delta).join();
      expect(joined.trim(), isNotEmpty);
    });
  });
}
