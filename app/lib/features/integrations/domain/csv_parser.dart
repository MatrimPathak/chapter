/// Minimal RFC 4180 reader: quoted fields, doubled quotes, newlines inside
/// quotes, LF or CRLF. Malformed input degrades into odd fields; it never throws.
List<List<String>> parseCsv(String input) {
  final text = input.startsWith('﻿') ? input.substring(1) : input;
  final rows = <List<String>>[];
  var row = <String>[];
  final field = StringBuffer();
  var inQuotes = false;

  void endField() {
    row.add(field.toString());
    field.clear();
  }

  void endRow() {
    endField();
    if (row.length > 1 || row.first.isNotEmpty) rows.add(row);
    row = <String>[];
  }

  for (var i = 0; i < text.length; i++) {
    final c = text[i];
    if (inQuotes) {
      if (c == '"') {
        if (i + 1 < text.length && text[i + 1] == '"') {
          field.write('"');
          i++;
        } else {
          inQuotes = false;
        }
      } else {
        field.write(c);
      }
    } else if (c == '"' && field.isEmpty) {
      inQuotes = true;
    } else if (c == ',') {
      endField();
    } else if (c == '\n') {
      endRow();
    } else if (c != '\r') {
      field.write(c);
    }
  }
  if (field.isNotEmpty || row.isNotEmpty) endRow();
  return rows;
}

/// A short stable id for [input] (FNV-1a, 64 bits, in hex). Not cryptographic:
/// it only has to give every device the same id for the same book or clipping.
String stableHash(String input) {
  var hash = 0xcbf29ce484222325;
  for (final unit in input.codeUnits) {
    hash ^= unit & 0xff;
    hash *= 0x100000001b3; // wraps at 64 bits
    hash ^= unit >> 8;
    hash *= 0x100000001b3;
  }
  String part(int v) => v.toRadixString(16).padLeft(8, '0');
  return part(hash >>> 32) + part(hash & 0xFFFFFFFF);
}

/// For comparing titles and names: lower case, no punctuation or accents that
/// exports disagree on, single spaces.
String normalizeText(String input) => input
    .toLowerCase()
    .replaceAll(RegExp(r"[’'`]"), '')
    .replaceAll('&', ' and ')
    .replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ')
    .trim();

/// A title without its subtitle or bracketed series: "Dune: Book 1 (Dune)" → "dune".
String normalizeTitle(String title) {
  final noBrackets = title.replaceAll(RegExp(r'[\(\[].*?[\)\]]'), ' ');
  final main = noBrackets.split(RegExp(r'\s*[:–—]\s+|:\s*')).first;
  final normalized = normalizeText(main);
  return normalized.isEmpty ? normalizeText(title) : normalized;
}
