import 'dart:math';

import 'package:chapter/features/integrations/domain/csv_parser.dart';
import 'package:chapter/features/integrations/domain/kindle_clippings.dart';
import 'package:chapter/features/integrations/domain/reading_import.dart';
import 'package:chapter/features/library/domain/library_models.dart';
import 'package:flutter_test/flutter_test.dart';

const goodreadsHeader =
    'Book Id,Title,Author,Author l-f,Additional Authors,ISBN,ISBN13,My Rating,Average Rating,'
    'Publisher,Binding,Number of Pages,Year Published,Original Publication Year,Date Read,'
    'Date Added,Bookshelves,Bookshelves with positions,Exclusive Shelf,My Review,Spoiler,'
    'Private Notes,Read Count,Owned Copies';

String goodreadsRow({
  String id = '1',
  String title = 'The Deal',
  String author = 'Elle Kennedy',
  String additional = '',
  String isbn = '="0349440847"',
  String isbn13 = '="9780349440842"',
  String rating = '4',
  String pages = '374',
  String read = '2021/03/04',
  String added = '2021/01/02',
  String shelf = 'read',
  String review = 'Fun',
  String count = '1',
  String owned = '0',
}) =>
    '$id,"$title",$author,"x, y",$additional,"${isbn.replaceAll('"', '""')}",'
    '"${isbn13.replaceAll('"', '""')}",$rating,4.1,Pub,Paperback,$pages,2015,2015,$read,$added,'
    ',,$shelf,"$review",,,$count,$owned';

const storygraphHeader =
    'Title,Authors,Contributors,ISBN/UID,Format,Read Status,Date Added,Last Date Read,Dates Read,'
    'Read Count,Moods,Pace,Character- or Plot-Driven?,Strong Character Development?,'
    'Loveable Characters?,Diverse Characters?,Flawed Characters?,Star Rating,Review,'
    'Content Warnings,Content Warning Description,Tags,Owned?';

void main() {
  group('parseCsv', () {
    test('quotes, doubled quotes, commas and newlines inside fields', () {
      expect(parseCsv('a,"b,c","d ""e"" f"\n"g\nh",i,j\n'), [
        ['a', 'b,c', 'd "e" f'],
        ['g\nh', 'i', 'j'],
      ]);
    });

    test('BOM, CRLF, a missing last newline and blank lines', () {
      expect(parseCsv('﻿a,b\r\n\r\n1,2'), [
        ['a', 'b'],
        ['1', '2'],
      ]);
    });

    test('an unterminated quote keeps the text and does not throw', () {
      expect(parseCsv('a,"b\nc'), [
        ['a', 'b\nc'],
      ]);
    });
  });

  group('stable ids', () {
    test('hash is stable and differs by input', () {
      expect(stableHash('abc'), stableHash('abc'));
      expect(stableHash('abc'), isNot(stableHash('abd')));
      expect(stableHash('abc'), hasLength(16));
      expect(stableHash('abc'), matches(RegExp(r'^[0-9a-f]{16}$')));
    });

    test('titles compare without subtitles, series or punctuation', () {
      expect(normalizeTitle('The Deal: An Off-Campus Novel'), 'the deal');
      expect(normalizeTitle('The Deal (Off-Campus, #1)'), 'the deal');
      expect(normalizeTitle("Ender's Game"), 'enders game');
      expect(normalizeTitle('(Weird)'), 'weird');
    });
  });

  group('Goodreads', () {
    ImportPreview parse(List<String> rows) =>
        parseReadingExport([goodreadsHeader, ...rows].join('\n'))!;

    test('maps a finished book', () {
      final b = parse([goodreadsRow(owned: '1')]).books.single;
      expect(b.source, ImportSource.goodreads);
      expect(b.title, 'The Deal');
      expect(b.authors, ['Elle Kennedy']);
      expect(b.isbn, '9780349440842', reason: 'the ="..." wrapper is removed');
      expect(b.pageCount, 374);
      expect(b.status, ReadingStatus.read);
      expect(b.rating, 4);
      expect(b.review, 'Fun');
      expect(b.finishedOn, [DateTime(2021, 3, 4, 12)]);
      expect(b.undatedReads, 0);
      expect(b.owned, isTrue);
      expect(b.dateAdded, DateTime(2021, 1, 2, 12));
    });

    test('shelves map to statuses; custom shelves are Want to Read', () {
      final p = parse([
        goodreadsRow(shelf: 'currently-reading', read: '', count: '0'),
        goodreadsRow(id: '2', shelf: 'to-read', read: '', count: '0'),
        goodreadsRow(id: '3', shelf: 'did-not-finish', read: '', count: '0'),
        goodreadsRow(id: '4', shelf: 'someday-maybe', read: '', count: '0'),
      ]);
      expect(p.books.map((b) => b.status), [
        ReadingStatus.reading,
        ReadingStatus.wantToRead,
        ReadingStatus.dnf,
        ReadingStatus.wantToRead,
      ]);
      expect(p.books.every((b) => b.finishedOn.isEmpty && b.undatedReads == 0), isTrue);
    });

    test('read twice with one date gives one dated read and one undated', () {
      final b = parse([goodreadsRow(count: '2')]).books.single;
      expect(b.finishedOn, hasLength(1));
      expect(b.undatedReads, 1);
    });

    test('Read with no date is one undated read, so it counts nowhere', () {
      final b = parse([goodreadsRow(read: '', count: '0')]).books.single;
      expect(b.finishedOn, isEmpty);
      expect(b.undatedReads, 1);
    });

    test('rating 0 means unrated; HTML in reviews becomes text', () {
      final b = parse([goodreadsRow(rating: '0', review: 'One<br/>Two <b>three</b>')]).books.single;
      expect(b.rating, isNull);
      expect(b.review, 'One\nTwo three');
    });

    test('blank and invalid ISBNs fall back to none', () {
      final b = parse([goodreadsRow(isbn: '=""', isbn13: '="123"')]).books.single;
      expect(b.isbn, isNull);
    });

    test('a bad date is ignored, not guessed', () {
      final b = parse([goodreadsRow(read: '2021/02/31')]).books.single;
      expect(b.finishedOn, isEmpty);
      expect(b.undatedReads, 1);
    });

    test('rows with no title are counted; repeats collapse; keys are stable', () {
      final p = parse([
        goodreadsRow(title: ''),
        goodreadsRow(id: '7'),
        goodreadsRow(id: '7', rating: '5'),
      ]);
      expect(p.skippedRows, 1);
      expect(p.books.single.rating, 5);
      expect(p.books.single.key, parse([goodreadsRow(id: '7')]).books.single.key);
    });

    test('additional authors are kept', () {
      final b = parse([goodreadsRow(additional: '"Ann Lee, Bo Ng"')]).books.single;
      expect(b.authors, ['Elle Kennedy', 'Ann Lee', 'Bo Ng']);
    });
  });

  group('StoryGraph', () {
    ImportedBook one(String row) => parseReadingExport('$storygraphHeader\n$row')!.books.single;

    test('maps reads, quarter stars and owned', () {
      final b = one(
        'The Deal,"Elle Kennedy, Ann Lee",,9780349440842,paperback,read,2021/01/02,2023/01/09,'
        '"2021/05/01-2021/05/20, 2023/01/02-2023/01/09",2,funny,fast,,,,,,4.25,Good,,,,Yes',
      );
      expect(b.source, ImportSource.storygraph);
      expect(b.authors, ['Elle Kennedy', 'Ann Lee']);
      expect(b.isbn, '9780349440842');
      expect(b.status, ReadingStatus.read);
      expect(b.rating, 4.5, reason: 'quarter stars round to half stars');
      expect(b.finishedOn, [DateTime(2021, 5, 20, 12), DateTime(2023, 1, 9, 12)]);
      expect(b.undatedReads, 0);
      expect(b.owned, isTrue);
    });

    test('statuses, including paused; an ASIN is not an ISBN', () {
      expect(one('A,B,,B00ABC1234,ebook,paused,,,,0,,,,,,,,,,,,,No').status, ReadingStatus.reading);
      expect(one('A,B,,B00ABC1234,ebook,to-read,,,,0,,,,,,,,,,,,,').isbn, isNull);
      expect(one('A,B,,,ebook,did-not-finish,,,,0,,,,,,,,,,,,,').status, ReadingStatus.dnf);
    });

    test('Last Date Read is used when Dates Read is empty', () {
      final b = one('A,B,,,ebook,read,,2022/06/07,,1,,,,,,,,,,,,,');
      expect(b.finishedOn, [DateTime(2022, 6, 7, 12)]);
    });

    test('a five-star cap holds for out-of-range values', () {
      expect(one('A,B,,,ebook,read,,,,1,,,,,,,,9,,,,,').rating, 5);
    });
  });

  test('anything else is not an export', () {
    expect(parseReadingExport(''), isNull);
    expect(parseReadingExport('a,b,c\n1,2,3'), isNull);
    expect(parseReadingExport('Exclusive Shelf,Other\nread,x'), isNull, reason: 'no Title column');
  });

  test('ImportedBook survives the queue', () {
    final b = parseReadingExport('$goodreadsHeader\n${goodreadsRow(count: '2')}')!.books.single;
    final back = ImportedBook.fromJson(b.toJson());
    expect(back.key, b.key);
    expect(back.title, b.title);
    expect(back.finishedOn, b.finishedOn);
    expect(back.undatedReads, 1);
    expect(back.status, b.status);
  });

  group('Kindle clippings', () {
    const sample =
        '﻿The Deal (Elle Kennedy)\r\n'
        '- Your Highlight on page 45 | location 678-680 | Added on Thursday, 6 February 2025 09:10:06\r\n'
        '\r\n'
        'A line I liked\r\n'
        '==========\r\n'
        'The Deal (Elle Kennedy)\r\n'
        '- Your Note on Location 700 | Added on Thursday, May 9, 2019 5:36:43 PM\r\n'
        '\r\n'
        'My thought\r\n'
        '==========\r\n'
        'The Deal (Elle Kennedy)\r\n'
        '- Your Bookmark on Location 800 | Added on Thursday, May 9, 2019 5:36:43 PM\r\n'
        '\r\n'
        '\r\n'
        '==========\r\n'
        'Dune: Book One (Dune Chronicles) (Frank Herbert)\r\n'
        '- Your Highlight on Location 10-12 | Added on Monday, December 18, 2017 1:39:43 PM\r\n'
        '\r\n'
        'Fear is the mind-killer.\r\n'
        'Second line.\r\n'
        '==========\r\n';

    test('highlights and notes, with page, location and author; bookmarks skipped', () {
      final f = parseClippings(sample)!;
      expect(f.skipped, 0);
      expect(f.clippings, hasLength(3));
      final a = f.clippings.first;
      expect(a.title, 'The Deal');
      expect(a.author, 'Elle Kennedy');
      expect(a.kind, ClippingKind.highlight);
      expect(a.page, 45);
      expect(a.location, 678);
      expect(a.text, 'A line I liked');
      expect(f.clippings[1].kind, ClippingKind.note);
      expect(f.clippings[1].page, isNull);
      expect(f.clippings[1].location, 700);
      final dune = f.clippings[2];
      expect(dune.title, 'Dune: Book One (Dune Chronicles)');
      expect(dune.author, 'Frank Herbert');
      expect(dune.text, 'Fear is the mind-killer.\nSecond line.');
    });

    test('exact repeats collapse; keys are stable', () {
      final f = parseClippings(sample + sample)!;
      expect(f.clippings, hasLength(3));
      expect(f.clippings.first.key, parseClippings(sample)!.clippings.first.key);
    });

    test('unknown languages and broken entries are counted, not guessed', () {
      final f = parseClippings(
        'Le Livre (Auteur)\n- Qwerty uiop 5\n\nTexte\n==========\nJust a line\n==========\n',
      )!;
      expect(f.clippings, isEmpty);
      expect(f.skipped, 2);
    });

    test('other files are not clippings', () {
      expect(parseClippings('Title,Author\nA,B'), isNull);
    });

    const library = [
      (workId: 'deal', title: 'The Deal: Off-Campus 1', authors: ['Elle Kennedy']),
      (workId: 'dune', title: 'Dune', authors: ['Frank Herbert']),
      (workId: 'twin1', title: 'Twins', authors: ['Ann Lee']),
      (workId: 'twin2', title: 'Twins', authors: ['Bo Ng']),
    ];

    Clipping clip(String title, [String? author]) =>
        Clipping(title: title, author: author, kind: ClippingKind.highlight, text: 'x');

    test('matching is by title and author, and refuses to guess', () {
      expect(matchLibraryBook(clip('The Deal', 'Elle Kennedy'), library), 'deal');
      expect(matchLibraryBook(clip('The Deal', 'Kennedy, Elle'), library), 'deal');
      expect(
        matchLibraryBook(clip('Dune: Book One (Dune Chronicles)', 'Frank Herbert'), library),
        'dune',
      );
      expect(matchLibraryBook(clip('Dune'), library), 'dune');
      expect(matchLibraryBook(clip('The Deal', 'Someone Else'), library), isNull);
      expect(matchLibraryBook(clip('Unknown'), library), isNull);
      expect(matchLibraryBook(clip('Twins'), library), isNull, reason: 'two candidates');
      expect(matchLibraryBook(clip('Twins', 'Bo Ng'), library), 'twin2');
    });
  });

  group('randomized input never throws', () {
    const alphabet = 'ab,"\n\r=/-: ()0123456789=<>é﻿';
    String noise(Random r, int n) => String.fromCharCodes([
      for (var i = 0; i < n; i++) alphabet.codeUnitAt(r.nextInt(alphabet.length)),
    ]);

    for (final seed in [1, 2, 3, 4, 5, 6]) {
      test('seed $seed', () {
        final r = Random(seed);
        for (var i = 0; i < 200; i++) {
          final body = noise(r, r.nextInt(400));
          parseCsv(body);
          parseReadingExport('$goodreadsHeader\n$body');
          parseReadingExport('$storygraphHeader\n$body');
          parseClippings('$body\n==========\n${noise(r, 40)}\n==========');
          normalizeTitle(body);
        }
      });
    }

    test('a whole export as noise keeps every field in range', () {
      final r = Random(9);
      final rows = [
        for (var i = 0; i < 500; i++)
          goodreadsRow(
            id: '$i',
            rating: noise(r, 2).replaceAll(RegExp(r'[,"\n\r]'), ''),
            pages: noise(r, 3).replaceAll(RegExp(r'[,"\n\r]'), ''),
            read: noise(r, 10).replaceAll(RegExp(r'[,"\n\r]'), ''),
            count: noise(r, 2).replaceAll(RegExp(r'[,"\n\r]'), ''),
          ),
      ];
      final p = parseReadingExport([goodreadsHeader, ...rows].join('\n'))!;
      for (final b in p.books) {
        final rating = b.rating;
        if (rating != null) expect(LibraryEntry.isValidRating(rating), isTrue);
        final pages = b.pageCount;
        if (pages != null) expect(pages, greaterThan(0));
        expect(b.undatedReads, lessThanOrEqualTo(50));
      }
    });
  });
}
