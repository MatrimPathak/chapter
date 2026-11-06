import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/error/failure.dart';
import '../domain/catalog_models.dart';

enum SearchStatus { idle, loading, loadingMore, ready, error }

/// State of the Search tab. Immutable; replaced on every change.
class SearchState {
  const SearchState({
    this.query = '',
    this.field = SearchField.all,
    this.status = SearchStatus.idle,
    this.results = const [],
    this.page = 0,
    this.hasMore = false,
    this.fromCache = false,
    this.degraded = false,
    this.failure,
  });

  final String query;
  final SearchField field;
  final SearchStatus status;
  final List<WorkSummary> results;
  final int page;
  final bool hasMore;
  final bool fromCache;
  final bool degraded;
  final Failure? failure;

  bool get hasQuery => query.trim().length >= 2;

  SearchState copyWith({
    String? query,
    SearchField? field,
    SearchStatus? status,
    List<WorkSummary>? results,
    int? page,
    bool? hasMore,
    bool? fromCache,
    bool? degraded,
    Failure? failure,
  }) => SearchState(
    query: query ?? this.query,
    field: field ?? this.field,
    status: status ?? this.status,
    results: results ?? this.results,
    page: page ?? this.page,
    hasMore: hasMore ?? this.hasMore,
    fromCache: fromCache ?? this.fromCache,
    degraded: degraded ?? this.degraded,
    failure: failure,
  );
}

/// Debounced, paginated search. Stale responses (from a query the user has
/// since changed) are discarded using a request generation counter.
class SearchController extends Notifier<SearchState> {
  static const debounce = Duration(milliseconds: 350);

  Timer? _debounce;
  int _generation = 0;

  @override
  SearchState build() {
    ref.onDispose(() => _debounce?.cancel());
    return const SearchState();
  }

  /// Called on every keystroke.
  void setQuery(String query) {
    _debounce?.cancel();
    final trimmed = query.trim();
    if (trimmed.length < 2) {
      _generation++;
      state = SearchState(query: query, field: state.field);
      return;
    }
    state = state.copyWith(query: query);
    _debounce = Timer(debounce, () => unawaited(_runFirstPage()));
  }

  /// Submit (keyboard action or tapping a recent search): search immediately
  /// and remember the query.
  Future<void> submit(String query) async {
    _debounce?.cancel();
    state = state.copyWith(query: query);
    if (!state.hasQuery) return;
    unawaited(ref.read(catalogRepositoryProvider).addRecentSearch(query));
    await _runFirstPage();
  }

  void setField(SearchField field) {
    if (field == state.field) return;
    state = state.copyWith(field: field);
    if (state.hasQuery) unawaited(_runFirstPage());
  }

  Future<void> retry() => _runFirstPage();

  Future<void> loadMore() async {
    if (!state.hasMore || state.status != SearchStatus.ready || state.fromCache) return;
    final generation = _generation;
    state = state.copyWith(status: SearchStatus.loadingMore);
    final result = await ref
        .read(catalogRepositoryProvider)
        .search(state.query, field: state.field, page: state.page + 1);
    if (generation != _generation) return;
    result.fold(
      (page) => state = state.copyWith(
        status: SearchStatus.ready,
        results: [...state.results, ..._withoutDuplicates(page.results)],
        page: page.page,
        hasMore: page.hasMore,
      ),
      // Keep what we have; just stop paginating.
      (failure) => state = state.copyWith(status: SearchStatus.ready, hasMore: false),
    );
  }

  Future<void> _runFirstPage() async {
    final generation = ++_generation;
    state = state.copyWith(status: SearchStatus.loading, results: const [], page: 0);
    final result = await ref
        .read(catalogRepositoryProvider)
        .search(state.query, field: state.field);
    if (generation != _generation) return;
    state = result.fold(
      (page) => state.copyWith(
        status: SearchStatus.ready,
        results: page.results,
        page: page.page,
        hasMore: page.hasMore,
        fromCache: page.fromCache,
        degraded: page.degraded,
      ),
      (failure) => state.copyWith(status: SearchStatus.error, failure: failure),
    );
  }

  Iterable<WorkSummary> _withoutDuplicates(List<WorkSummary> next) {
    final seen = {for (final r in state.results) '${r.ref.provider.name}:${r.ref.externalId}'};
    return next.where((r) => seen.add('${r.ref.provider.name}:${r.ref.externalId}'));
  }
}

final searchControllerProvider = NotifierProvider<SearchController, SearchState>(
  SearchController.new,
);

final recentSearchesProvider = StreamProvider<List<String>>(
  (ref) => ref.watch(catalogRepositoryProvider).watchRecentSearches(),
);

final trendingProvider = FutureProvider<SearchPage>((ref) async {
  final result = await ref.watch(catalogRepositoryProvider).trending();
  return result.fold((page) => page, (failure) => throw failure);
});
