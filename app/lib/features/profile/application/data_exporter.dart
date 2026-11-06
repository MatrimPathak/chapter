import 'dart:convert';

import 'package:drift/drift.dart' show ValueSerializer;
import 'package:meta/meta.dart';

import '../../../core/database/app_database.dart';

@immutable
class ExportFile {
  const ExportFile(this.name, this.content);

  final String name;
  final String content;
}

/// Builds the reader's export from the local database alone, so it works
/// offline (docs/05 §1.5). JSON is complete; the CSV files are for reading in
/// a spreadsheet. Nothing here touches the network.
class DataExporter {
  DataExporter(this._db, this._uid, this._now);

  final AppDatabase _db;
  final String _uid;
  final DateTime _now;

  /// Tables whose rows are in the JSON, by Drift table name. A test fails if a
  /// table is in neither set, so a new table can't be missed silently.
  static const exportedTables = {
    'lww_documents',
    'progress_events',
    'sessions',
    'session_tombstones',
    'active_sessions',
    'recent_searches',
    'import_rows',
    'outbox_entries',
  };

  /// Not the reader's data: public book metadata and sync bookkeeping.
  static const excludedTables = {'catalog_cache_entries', 'sync_meta'};

  static const _dates = ValueSerializer.defaults(serializeDateTimeValuesAsString: true);

  Future<List<ExportFile>> build() async {
    final docs = await _db.select(_db.lwwDocuments).get();
    final collections = <String, List<Map<String, Object?>>>{};
    Map<String, Object?> profile = const {};
    final prefix = 'users/$_uid';
    for (final d in docs) {
      if (d.path == prefix) {
        // No account email: export needs no reauthentication this way, so it
        // works offline (docs/05 §1.1).
        profile = _decode(d.fieldsJson)..remove('email');
      } else if (d.path.startsWith('$prefix/')) {
        final parts = d.path.substring(prefix.length + 1).split('/');
        collections.putIfAbsent(parts.first, () => []).add({
          'id': parts.last,
          ..._decode(d.fieldsJson),
        });
      }
    }

    final events = await _db.select(_db.progressEvents).get();
    final sessions = await _db.select(_db.sessions).get();
    final outbox = await _db.select(_db.outboxEntries).get();
    final json = <String, Object?>{
      'format': 'chapter-export',
      'version': 1,
      'exportedAt': _now.toUtc().toIso8601String(),
      'userId': _uid,
      'profile': profile,
      ...collections,
      'progressEvents': [for (final r in events) _row(r.toJson(serializer: _dates))],
      'sessions': [for (final r in sessions) _row(r.toJson(serializer: _dates))],
      'sessionTombstones': [for (final r in await _db.select(_db.sessionTombstones).get()) r.id],
      'activeSession': [
        for (final r in await _db.select(_db.activeSessions).get())
          _row(r.toJson(serializer: _dates)),
      ],
      'recentSearches': [
        for (final r in await _db.select(_db.recentSearches).get())
          _row(r.toJson(serializer: _dates)),
      ],
      'importedRows': [
        for (final r in await _db.select(_db.importRows).get()) _row(r.toJson(serializer: _dates)),
      ],
      // Everything here is also above: this says what hasn't reached the server.
      'changesNotYetSynced': outbox.length,
      'changesRejectedByServer': [
        for (final r in outbox)
          if (r.deadLetter) {'path': r.docPath, 'error': r.lastError},
      ],
    };

    final day = _now.toIso8601String().substring(0, 10);
    return [
      ExportFile('chapter-export-$day.json', const JsonEncoder.withIndent('  ').convert(json)),
      ExportFile('chapter-library-$day.csv', _libraryCsv(collections, events)),
      ExportFile('chapter-sessions-$day.csv', _sessionsCsv(collections, sessions)),
      ExportFile('chapter-notes-$day.csv', _notesCsv(collections)),
    ];
  }

  static Map<String, Object?> _decode(String json) =>
      (jsonDecode(json) as Map).cast<String, Object?>();

  /// Unwraps columns that hold JSON, so the export reads as plain nested data.
  static Map<String, Object?> _row(Map<String, Object?> row) => {
    for (final e in row.entries)
      if (e.key.endsWith('Json') && e.value is String)
        e.key.substring(0, e.key.length - 4): _tryDecode(e.value! as String)
      else
        e.key: e.value,
  };

  static Object? _tryDecode(String s) {
    try {
      return jsonDecode(s);
    } on FormatException {
      return s;
    }
  }

  static Map<String, String> _titles(Map<String, List<Map<String, Object?>>> c) => {
    for (final b in c['library'] ?? const <Map<String, Object?>>[])
      b['id']! as String: (b['title'] as String?) ?? '',
  };

  String _libraryCsv(Map<String, List<Map<String, Object?>>> c, List<ProgressEventRow> events) {
    final finished = <String, List<String>>{};
    for (final t in c['readThroughs'] ?? const <Map<String, Object?>>[]) {
      if (t['outcome'] != 'finished') continue;
      final at = t['finishedAt'] as String?;
      finished
          .putIfAbsent(t['workId']! as String, () => [])
          .add(at == null ? 'date unknown' : _day(at));
    }
    final latest = <String, ProgressEventRow>{};
    for (final e in events) {
      final current = latest[e.readThroughId];
      if (current == null || e.recordedAt.isAfter(current.recordedAt)) latest[e.readThroughId] = e;
    }
    return _csv(
      const [
        'Title',
        'Authors',
        'Shelf',
        'Rating',
        'Favourite',
        'Pages',
        'Series',
        'Date added',
        'Finished',
        'Progress %',
        'Review',
      ],
      [
        for (final b in c['library'] ?? const <Map<String, Object?>>[])
          if (b['removed'] != true)
            [
              b['title'],
              ((b['authorNames'] as List?) ?? const []).join('; '),
              b['status'],
              b['rating'],
              b['isFavorite'] == true ? 'yes' : 'no',
              b['pageCount'],
              b['seriesName'],
              b['addedAt'] is String ? _day(b['addedAt']! as String) : null,
              (finished[b['id']] ?? const <String>[]).join('; '),
              switch (latest[b['activeReadThroughId']]) {
                final e? => (e.fraction * 100).round(),
                null => null,
              },
              b['review'],
            ],
      ],
    );
  }

  String _sessionsCsv(Map<String, List<Map<String, Object?>>> c, List<SessionRow> sessions) {
    final titles = _titles(c);
    return _csv(
      const ['Book', 'Date', 'Started', 'Ended', 'Minutes'],
      [
        for (final s in sessions)
          [
            titles[s.workId],
            s.localDate,
            s.startedAt.toUtc().toIso8601String(),
            s.endedAt.toUtc().toIso8601String(),
            (s.activeDurationSec / 60).round(),
          ],
      ],
    );
  }

  String _notesCsv(Map<String, List<Map<String, Object?>>> c) {
    final titles = _titles(c);
    return _csv(
      const ['Book', 'Kind', 'Page', 'Location', 'Created', 'Text'],
      [
        for (final n in c['notes'] ?? const <Map<String, Object?>>[])
          if (n['deleted'] != true)
            [
              titles[n['workId']],
              n['kind'],
              n['page'],
              n['location'],
              n['createdAt'] is String ? _day(n['createdAt']! as String) : null,
              n['text'],
            ],
      ],
    );
  }

  static String _day(String iso) =>
      DateTime.tryParse(iso)?.toLocal().toIso8601String().substring(0, 10) ?? iso;

  /// RFC 4180, with a BOM so spreadsheets read UTF-8.
  static String _csv(List<String> header, List<List<Object?>> rows) {
    final out = StringBuffer('﻿')..write('${header.map(csvCell).join(',')}\r\n');
    for (final r in rows) {
      out.write('${r.map(csvCell).join(',')}\r\n');
    }
    return out.toString();
  }

  /// Quotes as needed. Text that a spreadsheet would run as a formula gets a
  /// leading apostrophe: a review can come from an imported file.
  @visibleForTesting
  static String csvCell(Object? value) {
    if (value == null) return '';
    if (value is num) return value.toString();
    var s = value.toString();
    if (s.startsWith(RegExp(r'[=+\-@\t\r]'))) s = "'$s";
    final needsQuotes = s.contains(RegExp(r'[",\r\n]'));
    return needsQuotes ? '"${s.replaceAll('"', '""')}"' : s;
  }
}
