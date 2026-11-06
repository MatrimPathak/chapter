/// ISBN validation and normalization. Mirrors
/// functions/src/catalog/isbn.ts; keep both in sync (both have tests).
abstract final class Isbn {
  static final _isbn10 = RegExp(r'^\d{9}[\dX]$');
  static final _isbn13 = RegExp(r'^97[89]\d{10}$');

  /// Removes spaces and hyphens and upper-cases a trailing x.
  static String clean(String input) => input.replaceAll(RegExp(r'[\s-]'), '').toUpperCase();

  static bool isValid10(String input) {
    final isbn = clean(input);
    if (!_isbn10.hasMatch(isbn)) return false;
    var sum = 0;
    for (var i = 0; i < 10; i++) {
      final ch = isbn[i];
      final value = ch == 'X' ? 10 : int.parse(ch);
      sum += value * (10 - i);
    }
    return sum % 11 == 0;
  }

  static bool isValid13(String input) {
    final isbn = clean(input);
    if (!_isbn13.hasMatch(isbn)) return false;
    var sum = 0;
    for (var i = 0; i < 13; i++) {
      sum += int.parse(isbn[i]) * (i.isEven ? 1 : 3);
    }
    return sum % 10 == 0;
  }

  /// Converts a valid ISBN-10 to ISBN-13 (978 prefix).
  static String to13(String isbn10) {
    final core = '978${clean(isbn10).substring(0, 9)}';
    var sum = 0;
    for (var i = 0; i < 12; i++) {
      sum += int.parse(core[i]) * (i.isEven ? 1 : 3);
    }
    return '$core${(10 - sum % 10) % 10}';
  }

  /// Canonical ISBN-13 for any valid ISBN-10/13, or `null` when invalid.
  static String? normalize(String input) {
    final isbn = clean(input);
    if (isValid13(isbn)) return isbn;
    if (isValid10(isbn)) return to13(isbn);
    return null;
  }

  /// Interprets a scanned barcode. Books carry EAN-13 barcodes starting with
  /// 978/979 (Bookland); other EAN-13s (e.g. a price add-on or a non-book
  /// product) are rejected.
  static String? fromBarcode(String raw) {
    final digits = clean(raw);
    return isValid13(digits) ? digits : null;
  }
}
