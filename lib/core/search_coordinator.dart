import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/web_search.dart';
import 'launcher_bridge.dart';

/// Drives a web search from the UI surface.
///
/// Owns the choice of *how* a query is answered — a registered
/// [SearchProvider], or the native Android handoff — so the surface never has
/// to branch on transport. It also owns cancellation, which matters because
/// the surface can be dismissed mid-stream.
class SearchCoordinator extends ChangeNotifier {
  SearchCoordinator({List<SearchProvider> providers = const []})
      : _providers = List<SearchProvider>.from(providers);

  final List<SearchProvider> _providers;

  /// Providers that need a key but have none. Used to explain the
  /// [SearchPhase.needsKey] state rather than just failing.
  final List<SearchProvider> _lockedProviders = [];

  StreamSubscription<SearchChunk>? _subscription;
  int _generation = 0;
  SearchResult _result = const SearchResult(phase: SearchPhase.idle, query: '');

  SearchResult get result => _result;

  /// The first provider that can actually answer, or null when the feature is
  /// running in handoff-only mode.
  SearchProvider? get activeProvider {
    for (final p in _providers) {
      if (p.requiresKey && !p.isAvailable) {
        if (!_lockedProviders.contains(p)) _lockedProviders.add(p);
        continue;
      }
      if (p.isAvailable) return p;
    }
    return null;
  }

  /// True when no inline provider is configured, so the surface should present
  /// the native handoff as the primary action rather than a fallback.
  bool get isHandoffOnly => activeProvider == null;

  /// Names of providers that would work if a key were supplied.
  List<String> get lockedProviderNames =>
      _lockedProviders.map((p) => p.name).toList();

  /// Runs [query] through the active provider.
  ///
  /// Emits at least one notification before any network work so the surface can
  /// enter its searching state immediately, rather than appearing frozen.
  Future<void> search(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;

    await cancel();
    final generation = ++_generation;

    final provider = activeProvider;
    if (provider == null) {
      final locked = lockedProviderNames;
      _set(
        SearchResult(
          phase: locked.isEmpty ? SearchPhase.unavailable : SearchPhase.needsKey,
          query: trimmed,
          providerName: locked.isEmpty ? 'Handoff' : locked.first,
          errorMessage: locked.isEmpty
              ? 'No inline search provider is configured.'
              : '${locked.first} needs an API key before it can answer inline.',
        ),
      );
      return;
    }

    _set(
      SearchResult(
        phase: SearchPhase.searching,
        query: trimmed,
        isStreaming: true,
        providerName: provider.name,
      ),
    );

    final buffer = StringBuffer();
    final sources = <SearchSource>[];

    try {
      final stream = provider.search(trimmed);
      final completer = Completer<void>();

      _subscription = stream.listen(
        (chunk) {
          if (generation != _generation) return;
          buffer.write(chunk.delta);
          if (chunk.sources.isNotEmpty) {
            for (final s in chunk.sources) {
              if (!sources.any((existing) => existing.url == s.url)) {
                sources.add(s);
              }
            }
          }
          _set(
            _result.copyWith(
              phase: SearchPhase.streaming,
              answer: buffer.toString(),
              sources: List<SearchSource>.from(sources),
            ),
          );
        },
        onError: (Object error) {
          if (generation != _generation) return;
          _set(
            _result.copyWith(
              phase: SearchPhase.failed,
              errorMessage: error.toString(),
            ),
          );
          if (!completer.isCompleted) completer.complete();
        },
        onDone: () {
          if (generation != _generation) return;
          _set(
            _result.copyWith(
              phase: SearchPhase.complete,
              answer: buffer.toString(),
              sources: List<SearchSource>.from(sources),
            ),
          );
          if (!completer.isCompleted) completer.complete();
        },
        cancelOnError: true,
      );

      await completer.future;
    } catch (error) {
      if (generation != _generation) return;
      _set(
        _result.copyWith(
          phase: SearchPhase.failed,
          errorMessage: error.toString(),
        ),
      );
    }
  }

  /// Cancels any in-flight search. Safe to call when idle.
  Future<void> cancel() async {
    final sub = _subscription;
    _subscription = null;
    if (sub != null) {
      await sub.cancel();
    }
  }

  /// Clears back to the idle state without cancelling providers.
  void reset() {
    unawaited(cancel());
    _generation++;
    _set(const SearchResult(phase: SearchPhase.idle, query: ''));
  }

  /// Opens a URL through the platform.
  ///
  /// Routes via [LauncherBridge.openWebUrl], which uses the browser role
  /// holder. Do not assume it opens a chooser: on the tested ColorOS build the
  /// browser role is held and this launches silently.
  Future<bool> openSource(SearchSource source) =>
      LauncherBridge.openWebUrl(source.url);

  /// Hands the raw query to the platform's web-search handler.
  ///
  /// On the tested ColorOS 16 build this raises a chooser (seven handlers, no
  /// default), so callers should label the action honestly — see
  /// [LauncherBridge.describeWebSearchHandoff].
  Future<bool> openViaHandoff(String query) =>
      LauncherBridge.startWebSearch(query);

  void _set(SearchResult next) {
    _result = next;
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(cancel());
    super.dispose();
  }
}
