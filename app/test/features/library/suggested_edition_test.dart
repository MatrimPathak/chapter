import 'package:chapter/features/catalog/domain/catalog_models.dart';
import 'package:chapter/features/library/presentation/library_sheets.dart';
import 'package:flutter_test/flutter_test.dart';

const _work = CatalogWork(
  id: 'w',
  title: 'T',
  refreshedAt: '2026-11-10',
  editions: [
    CatalogEdition(id: 'a', workId: 'w', format: 'paperback', language: 'spa', pageCount: 500),
    CatalogEdition(id: 'b', workId: 'w', format: 'paperback', language: 'eng', pageCount: 420),
    CatalogEdition(id: 'c', workId: 'w', format: 'paperback', language: 'eng', pageCount: 440),
    CatalogEdition(id: 'd', workId: 'w', format: 'hardcover', language: 'ger', pageCount: 430),
    CatalogEdition(id: 'e', workId: 'w', format: 'audiobook', audioDurationSec: 40800),
    CatalogEdition(id: 'f', workId: 'w', language: 'eng', pageCount: 410),
  ],
);

List<String> _ids(String format) => [for (final e in editionsForFormat(_work, format)) e.id];

void main() {
  test('lists only English editions of the format when there are any', () {
    expect(_ids('paperback'), ['b', 'c', 'f']);
  });

  test('includes unlabelled editions under print formats only', () {
    expect(_ids('hardcover'), ['f']);
    expect(_ids('kindle'), isEmpty);
  });

  test('Audible includes other audiobooks', () {
    expect(_ids('audible'), ['e']);
  });

  test('a format missing from the catalog lists nothing', () {
    expect(_ids('kindle'), isEmpty);
  });

  test('gives pages, or a length for Audible, or nothing', () {
    expect(editionValue(_work.editions[1], 'paperback'), '420');
    expect(editionValue(_work.editions[4], 'audible'), contains('11:20'));
    expect(editionValue(null, 'kindle'), '');
  });
}
