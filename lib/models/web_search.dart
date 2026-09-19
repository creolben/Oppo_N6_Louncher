/// Data model for the comet web-search surface.
///
/// Deliberately transport-agnostic: nothing in here knows whether an answer
/// arrived from a fixture, a streaming HTTP provider, or the native handoff.
/// The answer panel renders this model and only this model, which is what lets
/// a real provider be dropped in later without touching a single widget.
library;

/// One streamed fragment of an answer.
///
/// Providers emit [delta]s in order; the surface appends rather than replacing,
/// so a non-streaming provider can simply emit one large delta and behave
/// identically from the renderer's point of view.
class SearchChunk {
  /// Incremental answer text. Never a full replacement.
  final String delta;

  /// Sources that became known while producing this chunk.
  final List<SearchSource> sources;

  const SearchChunk({this.delta = '', this.sources = const []});
}

/// A citable result backing part of an answer.
class SearchSource {
  final String title;
  final String url;

  /// Short display label for the source chip. Derived from [url] when null.
  final String? domain;

  /// 1-based position, used for the `[1]` style citation markers.
  final int index;

  const SearchSource({
    required this.title,
    required this.url,
    required this.index,
    this.domain,
  });

  /// Host portion of [url], stripped of `www.`, for chip labels.
  String get displayDomain {
    if (domain != null && domain!.isNotEmpty) return domain!;
    final host = Uri.tryParse(url)?.host ?? '';
    return host.startsWith('www.') ? host.substring(4) : host;
  }
}

/// The status of a search, as the surface needs to render it.
///
/// [needsKey] and [unavailable] exist so the surface never shows a spinner for
/// a provider that will never answer — the single most common way an
/// "ask-first" feature feels broken.
enum SearchPhase { idle, searching, streaming, complete, needsKey, unavailable, failed }

/// A point-in-time view of a search, suitable for handing straight to widgets.
class SearchResult {
  final SearchPhase phase;
  final String query;

  /// Answer text accumulated so far.
  final String answer;

  /// Whether the provider supports incremental output. Non-streaming results
  /// render the same way; the surface only uses this to decide whether to show
  /// a shimmer.
  final bool isStreaming;

  final List<SearchSource> sources;

  /// Human-readable failure reason, shown verbatim in the error state.
  final String? errorMessage;

  /// Name of the provider that produced this, for provenance in the UI.
  final String providerName;

  const SearchResult({
    required this.phase,
    required this.query,
    this.answer = '',
    this.isStreaming = false,
    this.sources = const [],
    this.errorMessage,
    this.providerName = '',
  });

  bool get hasAnswer => answer.trim().isNotEmpty;

  SearchResult copyWith({
    SearchPhase? phase,
    String? answer,
    bool? isStreaming,
    List<SearchSource>? sources,
    String? errorMessage,
    String? providerName,
  }) {
    return SearchResult(
      phase: phase ?? this.phase,
      query: query,
      answer: answer ?? this.answer,
      isStreaming: isStreaming ?? this.isStreaming,
      sources: sources ?? this.sources,
      errorMessage: errorMessage ?? this.errorMessage,
      providerName: providerName ?? this.providerName,
    );
  }
}

/// A web-search backend.
///
/// This is the seam the whole feature is built around. Implementations are
/// registered in preference order; [SearchCoordinator] picks the first
/// available one and falls back to the native handoff when none are.
abstract class SearchProvider {
  /// Shown in the UI as provenance, e.g. "Fixture".
  String get name;

  /// True when this provider needs a credential the user has not supplied.
  /// Returning true here is what produces the [SearchPhase.needsKey] state
  /// instead of a failed request.
  bool get requiresKey => false;

  /// Whether this provider can currently answer. A provider that returns false
  /// is skipped by the coordinator.
  bool get isAvailable;

  /// Streams an answer to [query].
  ///
  /// Must emit at least one [SearchChunk] on success. Throwing is treated as a
  /// failed search; the coordinator surfaces `error.message`.
  Stream<SearchChunk> search(String query);
}
