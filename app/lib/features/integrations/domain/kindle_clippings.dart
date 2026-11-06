import 'package:meta/meta.dart';

import 'csv_parser.dart';

enum ClippingKind { highlight, note }

/// One highlight or note from a Kindle's `My Clippings.txt`.
@immutable
class Clipping {
  const Clipping({
    required this.title,
    required this.kind,
    required this.text,
    this.author,
    this.page,
    this.location,
  });

  final String title;
  final String? author;
  final ClippingKind kind;
  final String text;
  final int? page;

  /// Start of the Kindle location range.
  final int? location;

  /// Stable across imports and devices: reimporting finds the same id.
  String get key =>
      stableHash('${normalizeTitle(title)}|${kind.name}|${location ?? page ?? ''}|$text');
}

@immutable
class ClippingsFile {
  const ClippingsFile({required this.clippings, required this.skipped});

  final List<Clipping> clippings;

  /// Entries that couldn't be read: not in the expected shape, or from a device
  /// language this parser doesn't understand. Bookmarks don't count: they carry
  /// no text.
  final int skipped;
}

// Kindle writes this line in the device's language. English, German, French,
// Spanish, Italian, Portuguese, Dutch, Japanese and Chinese.
final _bookmarkRe = RegExp(
  r'bookmark|lesezeichen|signet|marcador|segnalibro|bladwijzer|ブックマーク|书签|書籤',
  caseSensitive: false,
);
final _highlightRe = RegExp(
  r'highlight|markierung|surlign|subrayado|evidenziazione|destaque|markering|ハイライト|标注|標註|标记|醒目',
  caseSensitive: false,
);
final _noteRe = RegExp(r'\bnote\b|notiz|\bnota\b|notitie|メモ|笔记|筆記', caseSensitive: false);
final _pageRe = RegExp(
  r'(?:\bpage|\bseite|\bp[áa]gina|\bpagina)\s+(\d+)|第\s*(\d+)\s*页|(\d+)\s*ページ',
  caseSensitive: false,
);
final _locationRe = RegExp(
  r'(?:\blocation|\bposition|\bemplacement|\bposici[óo]n|\bposizione|\bposi[çc][ãa]o|\blocatie|位置(?:No\.)?|位置\s*#)\s*#?\s*(\d+)',
  caseSensitive: false,
);

int? _firstNumber(RegExp re, String line) {
  final m = re.firstMatch(line);
  if (m == null) return null;
  for (var i = 1; i <= m.groupCount; i++) {
    final v = int.tryParse(m.group(i) ?? '');
    if (v != null) return v;
  }
  return null;
}

final _trailingAuthorRe = RegExp(r'^(.*)\s*\(([^()]*)\)\s*$');

/// Parses `My Clippings.txt`, on the device. `null` if it isn't one.
/// Exact repeats are dropped; Kindle appends every highlight, even re-saved ones.
ClippingsFile? parseClippings(String content) {
  final text = content.replaceAll('﻿', '').replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  if (!text.contains('==========')) return null;

  final seen = <String>{};
  final out = <Clipping>[];
  var skipped = 0;
  for (final block in text.split('==========')) {
    final lines = block.trim().split('\n');
    if (lines.length == 1 && lines.first.trim().isEmpty) continue;
    if (lines.length < 2 || !lines[1].trimLeft().startsWith('-')) {
      skipped++;
      continue;
    }
    final meta = lines[1];
    if (_bookmarkRe.hasMatch(meta)) continue;
    final ClippingKind kind;
    if (_highlightRe.hasMatch(meta)) {
      kind = ClippingKind.highlight;
    } else if (_noteRe.hasMatch(meta)) {
      kind = ClippingKind.note;
    } else {
      skipped++;
      continue;
    }
    final body = lines.skip(2).join('\n').trim();
    if (body.isEmpty) {
      skipped++;
      continue;
    }

    var title = lines.first.trim();
    String? author;
    final m = _trailingAuthorRe.firstMatch(title);
    if (m != null && m.group(1)!.trim().isNotEmpty) {
      title = m.group(1)!.trim();
      author = m.group(2)!.trim();
    }
    final clip = Clipping(
      title: title,
      author: author,
      kind: kind,
      text: body,
      page: _firstNumber(_pageRe, meta),
      location: _firstNumber(_locationRe, meta),
    );
    if (seen.add(clip.key)) out.add(clip);
  }
  return ClippingsFile(clippings: out, skipped: skipped);
}

/// The library book a clipping belongs to: same title and, when both are known,
/// an author in common. `null` when there's no match or more than one.
String? matchLibraryBook(
  Clipping clip,
  Iterable<({String workId, String title, List<String> authors})> library,
) {
  final title = normalizeTitle(clip.title);
  final matches = library.where((b) => normalizeTitle(b.title) == title).toList();
  if (matches.isEmpty) return null;
  final author = clip.author;
  if (author == null) return matches.length == 1 ? matches.single.workId : null;
  final withAuthor = matches.where((b) => sharesAuthor(author, b.authors)).toList();
  return withAuthor.length == 1 ? withAuthor.single.workId : null;
}

/// Whether [name] ("Kennedy, Elle" or "Elle Kennedy") shares a surname with one
/// of [authors]. Kindle and catalogs write the same name in different orders.
bool sharesAuthor(String name, List<String> authors) {
  final words = normalizeText(name).split(' ').where((w) => w.length > 1).toSet();
  if (words.isEmpty) return false;
  for (final a in authors) {
    final other = normalizeText(a).split(' ').where((w) => w.length > 1).toSet();
    if (other.isNotEmpty && other.last == words.last) return true;
    if (words.intersection(other).length >= 2) return true;
    if (name.contains(',') && other.contains(words.first)) return true;
  }
  return false;
}
