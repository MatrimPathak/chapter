import 'package:chapter/app/router/routes.dart';
import 'package:chapter/features/catalog/domain/catalog_models.dart';
import 'package:flutter_test/flutter_test.dart';

CatalogEdition _edition(String id, String? language, {int? pages}) =>
    CatalogEdition(id: id, workId: 'w', language: language, pageCount: pages);

CatalogWork _work(List<CatalogEdition> editions, String? defaultId) => CatalogWork(
  id: 'w',
  title: 'T',
  editions: editions,
  defaultEditionId: defaultId,
  refreshedAt: '2026-11-09',
);

void main() {
  test('passes over a non-English default for an English edition', () {
    final work = _work([
      _edition('es', 'spa', pages: 400),
      _edition('en', 'eng', pages: 420),
    ], 'es');
    expect(work.defaultEdition?.id, 'en');
  });

  test('keeps an English default', () {
    final work = _work([_edition('a', 'eng'), _edition('b', 'eng', pages: 420)], 'a');
    expect(work.defaultEdition?.id, 'a');
  });

  test('keeps the default when no edition is English', () {
    final work = _work([_edition('fr', 'fre'), _edition('es', 'spa')], 'es');
    expect(work.defaultEdition?.id, 'es');
  });

  test('carries a chosen edition in the book route', () {
    expect(AppRoutes.book('id:w', editionId: 'e1'), '/book/id%3Aw?edition=e1');
    expect(AppRoutes.book('id:w'), '/book/id%3Aw');
  });
}
