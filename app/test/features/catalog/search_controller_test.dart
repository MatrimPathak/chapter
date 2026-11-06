import 'package:chapter/app/providers.dart';
import 'package:chapter/core/error/failure.dart';
import 'package:chapter/core/error/result.dart';
import 'package:chapter/features/catalog/domain/catalog_models.dart';
import 'package:chapter/features/catalog/presentation/search_controller.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_catalog.dart';

void main() {
  late FakeCatalogRepository repo;
  late ProviderContainer container;

  setUp(() {
    repo = FakeCatalogRepository()
      ..onSearch = (q, field, page) => Result.ok(
        SearchPage(
          results: [summary('$q p$page', ext: '$q-$page')],
          page: page,
          hasMore: page < 2,
        ),
      );
    container = ProviderContainer(overrides: [catalogRepositoryProvider.overrideWithValue(repo)]);
  });

  tearDown(() => container.dispose());

  SearchController controller() => container.read(searchControllerProvider.notifier);
  SearchState state() => container.read(searchControllerProvider);

  test('debounces keystrokes into a single search', () {
    fakeAsync((async) {
      controller()
        ..setQuery('d')
        ..setQuery('de')
        ..setQuery('dea')
        ..setQuery('deal');
      async.elapse(const Duration(milliseconds: 349));
      expect(repo.searchCalls, isEmpty);
      async
        ..elapse(const Duration(milliseconds: 1))
        ..flushMicrotasks();
      expect(repo.searchCalls.map((c) => c.$1), ['deal']);
      expect(state().results.single.title, 'deal p1');
    });
  });

  test('queries shorter than two characters clear results without searching', () {
    fakeAsync((async) {
      controller().setQuery('x');
      async.elapse(const Duration(seconds: 1));
      expect(repo.searchCalls, isEmpty);
      expect(state().status, SearchStatus.idle);
    });
  });

  test('a slow stale response never overwrites a newer query', () {
    fakeAsync((async) {
      repo.searchDelay = const Duration(seconds: 2);
      controller().submit('first');
      async.elapse(const Duration(milliseconds: 100));
      repo.searchDelay = Duration.zero;
      controller().submit('second');
      async.elapse(const Duration(seconds: 3));
      expect(state().query, 'second');
      expect(state().results.single.title, 'second p1');
    });
  });

  test('loads the next page and stops when there are no more', () async {
    await controller().submit('deal');
    expect(state().hasMore, isTrue);
    await controller().loadMore();
    expect(state().results.map((r) => r.title), ['deal p1', 'deal p2']);
    expect(state().hasMore, isFalse);
    await controller().loadMore();
    expect(repo.searchCalls.length, 2);
  });

  test('changing the field re-runs the current query', () async {
    await controller().submit('kennedy');
    controller().setField(SearchField.author);
    await Future<void>.delayed(Duration.zero);
    expect(repo.searchCalls.last.$2, SearchField.author);
  });

  test('errors surface as an error state and retry recovers', () async {
    repo.onSearch = (_, _, _) => const Result.err(NetworkFailure('offline'));
    await controller().submit('deal');
    expect(state().status, SearchStatus.error);
    repo.onSearch = (q, _, page) => Result.ok(SearchPage(results: [summary(q)], page: page));
    await controller().retry();
    expect(state().status, SearchStatus.ready);
  });

  test('submitting remembers the query in recent searches', () async {
    await controller().submit('the deal');
    expect(repo.recents, ['the deal']);
  });
}
