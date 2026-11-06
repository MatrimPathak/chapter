import 'package:chapter/features/scanner/domain/isbn.dart';
import 'package:flutter_test/flutter_test.dart';

/// Same cases as functions/src/catalog/isbn.test.ts.
void main() {
  test('validates ISBN-13 checksums', () {
    expect(Isbn.isValid13('9780349440842'), isTrue);
    expect(Isbn.isValid13('978-0-349-44084-2'), isTrue);
    expect(Isbn.isValid13('9780349440843'), isFalse);
    expect(Isbn.isValid13('1234567890123'), isFalse);
  });

  test('validates ISBN-10 checksums including X', () {
    expect(Isbn.isValid10('0349440840'), isTrue);
    expect(Isbn.isValid10('080442957X'), isTrue);
    expect(Isbn.isValid10('080442957x'), isTrue);
    expect(Isbn.isValid10('0349440841'), isFalse);
  });

  test('converts ISBN-10 to ISBN-13', () {
    expect(Isbn.to13('0349440840'), '9780349440842');
    expect(Isbn.to13('080442957X'), '9780804429573');
  });

  test('normalizes valid input and rejects junk', () {
    expect(Isbn.normalize(' 0-349-44084-0 '), '9780349440842');
    expect(Isbn.normalize('the deal'), isNull);
    expect(Isbn.normalize('0349440841'), isNull);
  });

  test('accepts only Bookland EAN-13 barcodes', () {
    expect(Isbn.fromBarcode('9780349440842'), '9780349440842');
    expect(Isbn.fromBarcode('5012345678900'), isNull); // non-book EAN-13
    expect(Isbn.fromBarcode('0349440840'), isNull); // ISBN-10 is never a barcode
  });
}
