import '../../models/web_search.dart';

/// A provider that answers from local data, with no network and no key.
///
/// This is what makes Option 2 work: the full ask-first experience — streaming
/// answer, citation markers, source chips, latency, cancellation — is real and
/// inspectable today, while the retrieval half stays behind [SearchProvider].
/// Replacing this with an HTTP provider is a one-line registration change.
class FixtureSearchProvider implements SearchProvider {
  @override
  String get name => 'Fixture';

  /// No credential needed: this provider answers from local data.
  @override
  bool get requiresKey => false;

  @override
  bool get isAvailable => true;

  @override
  Stream<SearchChunk> search(String query) async* {
    final trimmed = query.trim();
    final content = _lookup(trimmed);

    // Simulate real search latency so the flight state is actually visible
    // during design review rather than flashing past in one frame.
    await Future<void>.delayed(const Duration(milliseconds: 420));

    // Emit sources before the prose, mirroring how a real provider discovers
    // results while composing — the chips appear as the answer is written.
    yield SearchChunk(sources: content.sources, delta: '');

    // Stream word-by-word so the surface's append behaviour is exercised the
    // same way a token stream would exercise it.
    final words = content.answer.split(' ');
    for (var i = 0; i < words.length; i++) {
      yield SearchChunk(delta: i == words.length - 1 ? words[i] : '${words[i]} ');
      await Future<void>.delayed(const Duration(milliseconds: 18));
    }
  }

  _FixtureContent _lookup(String query) {
    final q = query.toLowerCase();

    if (q.contains('find n6') || q.contains('fold')) {
      return const _FixtureContent(
        answer:
            'The OPPO Find N6 is a book-style foldable running ColorOS 16 on Android 16. '
            'It reports build CPH2765_16.0.10.500 with a ROM version of V16.1.0, and exposes '
            'hinge angle through sensor type 36 [1]. Third-party launchers can hold the HOME '
            'role on this build, though ACTION_WEB_SEARCH resolves to a chooser rather than a '
            'default handler [2].',
        sources: [
          SearchSource(
            title: 'OPPO Find N6 specifications',
            url: 'https://www.oppo.com/en/smartphones/series-find-n/find-n6/',
            index: 1,
          ),
          SearchSource(
            title: 'Android foldables: make your app fold aware',
            url: 'https://developer.android.com/develop/adaptive-apps/guides/foldables',
            index: 2,
          ),
        ],
      );
    }

    if (q.contains('coloros') || q.contains('android 16')) {
      return const _FixtureContent(
        answer:
            'ColorOS 16 ships on Android 16. On the tested Find N6 build, the system assistant '
            'is Google (GsaVoiceInteractionService), the default browser role is held by Brave, '
            'and the launcher role is held by this app [1]. No OPPO first-party web-search '
            'activity responds to ACTION_WEB_SEARCH, so that intent raises a system chooser [2].',
        sources: [
          SearchSource(
            title: 'Android 16 release notes',
            url: 'https://developer.android.com/about/versions/16',
            index: 1,
          ),
          SearchSource(
            title: 'Android role-based delegation',
            url: 'https://developer.android.com/reference/android/app/role/RoleManager',
            index: 2,
          ),
        ],
      );
    }

    return _FixtureContent(
      answer:
          'This is a fixture answer for "$query". No network request was made and no API key '
          'was used — the surface, streaming, citations and error states you are looking at are '
          'the real ones, wired to local data. Registering an HTTP-backed SearchProvider replaces '
          'this text with live results and changes nothing else [1].',
      sources: [
        SearchSource(
          title: 'Wire a real provider',
          url: 'https://developer.android.com/reference/android/content/Intent#ACTION_WEB_SEARCH',
          index: 1,
        ),
      ],
    );
  }
}

class _FixtureContent {
  final String answer;
  final List<SearchSource> sources;

  const _FixtureContent({required this.answer, required this.sources});
}
