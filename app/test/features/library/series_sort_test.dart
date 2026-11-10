import 'package:chapter/features/library/domain/library_models.dart';
import 'package:chapter/features/library/presentation/library_providers.dart';
import 'package:flutter_test/flutter_test.dart';

BookSummary _book(String title, {String? series, double? position}) =>
    BookSummary(title: title, seriesName: series, seriesPosition: position);

void main() {
  test('keeps each series together in reading order, others last', () {
    final books = [
      _book('Zebra'),
      _book('Book Two', series: 'B Saga', position: 2),
      _book('An Extra', series: 'B Saga'),
      _book('Other', series: 'A Saga', position: 1),
      _book('Apple'),
      _book('Novella', series: 'B Saga', position: 1.5),
      _book('Book One', series: 'B Saga', position: 1),
    ]..sort(compareBySeriesOrder);
    expect(books.map((b) => b.title), [
      'Other',
      'Book One',
      'Novella',
      'Book Two',
      'An Extra',
      'Apple',
      'Zebra',
    ]);
  });
}
