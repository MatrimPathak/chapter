import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/sync/lww_store.dart';
import '../../../core/sync/sync_engine.dart';
import '../../../core/sync/sync_remote.dart';
import '../../../core/utils/clock.dart';
import '../../../core/utils/id_generator.dart';
import '../../integrations/domain/reading_import.dart';
import '../../progress/domain/progress_event.dart';
import '../../progress/domain/progress_mapper.dart';
import '../../progress/domain/reading_position.dart';
import '../../reading/domain/reading_session.dart';
import '../../reading/domain/session_clock.dart';
import '../domain/library_models.dart';
import '../domain/library_repository.dart';

/// [LibraryRepository] over the local LWW store and the append-only
/// `progress_events` table. Paths mirror Firestore:
/// `users/{uid}/library|readThroughs|userEditions|progressEvents`.
class LwwLibraryRepository implements LibraryRepository {
  LwwLibraryRepository({
    required LwwStore store,
    required AppDatabase db,
    required Clock clock,
    required IdGenerator ids,
    required String uid,
    required void Function() onLocalWrite,
  }) : _store = store,
       _db = db,
       _clock = clock,
       _ids = ids,
       _onLocalWrite = onLocalWrite,
       libraryPath = 'users/$uid/library',
       readThroughsPath = 'users/$uid/readThroughs',
       editionsPath = 'users/$uid/userEditions',
       progressPath = 'users/$uid/progressEvents',
       sessionsPath = 'users/$uid/sessions',
       sessionTombstonesPath = 'users/$uid/sessionTombstones';

  final LwwStore _store;
  final AppDatabase _db;
  final Clock _clock;
  final IdGenerator _ids;
  final void Function() _onLocalWrite;

  final String libraryPath;
  final String readThroughsPath;
  final String editionsPath;
  final String progressPath;
  final String sessionsPath;
  final String sessionTombstonesPath;

  // ─── Reads ───

  @override
  Stream<List<LibraryEntry>> watchEntries() => _store
      .watchCollection(libraryPath)
      .map(
        (docs) => [for (final e in docs.entries) ?LibraryEntry.fromFields(e.key, e.value.fields)],
      );

  @override
  Stream<List<LibraryEntry>> watchEntriesIncludingRemoved() => _store
      .watchCollection(libraryPath)
      .map(
        (docs) => [
          for (final e in docs.entries)
            ?LibraryEntry.fromFields(e.key, e.value.fields, includeRemoved: true),
        ],
      );

  @override
  Future<void> setWishlist(String workId, {required bool wishlist}) async {
    await _store.write('$libraryPath/$workId', {LibraryFields.isWishlist: wishlist});
    _onLocalWrite();
  }

  @override
  Future<void> saveEditionDetails(UserEdition e) async {
    await _store.write('$editionsPath/${e.editionId}', {
      ..._editionFields(e),
      'pageCountOverride': e.pageCountOverride,
      'audioDurationOverride': e.audioDurationOverride,
      'contentStartPage': e.contentStartPage,
      'contentEndPage': e.contentEndPage,
      'calibrationJson': e.calibration.isEmpty ? null : CalibrationCodec.encode(e.calibration),
    });
    _onLocalWrite();
  }

  @override
  Stream<LibraryEntry?> watchEntry(String workId) =>
      _store.watch('$libraryPath/$workId').map((d) => LibraryEntry.fromFields(workId, d.fields));

  @override
  Stream<List<ReadThrough>> watchReadThroughs(String workId) =>
      _store.watchCollection(readThroughsPath).map((docs) {
        final list =
            [
                for (final e in docs.entries) ?ReadThrough.fromFields(e.key, e.value.fields),
              ].where((rt) => rt.workId == workId).toList()
              ..sort((a, b) => a.ordinal.compareTo(b.ordinal));
        return list;
      });

  @override
  Stream<List<UserEdition>> watchEditions(String workId) => _store
      .watchCollection(editionsPath)
      .map(
        (docs) => [
          for (final e in docs.entries) ?UserEdition.fromFields(e.key, e.value.fields),
        ].where((ed) => ed.workId == workId).toList(),
      );

  @override
  Stream<List<ProgressEvent>> watchProgress(String readThroughId) {
    final q = _db.select(_db.progressEvents)
      ..where((t) => t.readThroughId.equals(readThroughId))
      ..orderBy([(t) => OrderingTerm.asc(t.recordedAt), (t) => OrderingTerm.asc(t.id)]);
    return q.watch().map((rows) => rows.map(progressFromRow).toList());
  }

  @override
  Stream<Map<String, ProgressEvent>> watchLatestProgress() =>
      _db.select(_db.progressEvents).watch().map((rows) {
        final latest = <String, ProgressEvent>{};
        for (final e in rows.map(progressFromRow)) {
          final current = latest[e.readThroughId];
          if (current == null || ProgressEvent.compare(e, current) > 0) latest[e.readThroughId] = e;
        }
        return latest;
      });

  // ─── Writes ───

  @override
  Future<AddResult> add({
    required String workId,
    required BookSummary book,
    ReadingStatus status = ReadingStatus.wantToRead,
    UserEdition? edition,
    ReadFinish finish = const ReadFinish.now(),
  }) async {
    final existing = await _store.read('$libraryPath/$workId');
    if (LibraryEntry.fromFields(workId, existing.fields) != null) return AddResult.alreadyInLibrary;

    final now = _iso(_clock.now());
    final restoring = status == ReadingStatus.read && await restoresFinishedRead(workId);
    final plan = restoring
        ? _StatusPlan.none
        : await _statusPlan(workId, existing.fields, status, finish);
    final finished = _finishedEvent(plan, workId, edition?.editionId);
    await _store.batch((b) {
      b.write('$libraryPath/$workId', {
        ...book.toFields(),
        LibraryFields.status: status.name,
        LibraryFields.addedAt: now,
        LibraryFields.statusChangedAt: now,
        LibraryFields.isWishlist: false,
        LibraryFields.removed: false,
        if (edition != null) LibraryFields.activeEditionId: edition.editionId,
        ...plan.libraryChanges,
      });
      if (edition != null) b.write('$editionsPath/${edition.editionId}', _editionFields(edition));
      plan.apply(b);
      if (finished != null) _appendEvent(b, finished);
    });
    _onLocalWrite();
    return AddResult.added;
  }

  @override
  Future<void> setStatus(
    String workId,
    ReadingStatus status, {
    ReadFinish finish = const ReadFinish.now(),
  }) async {
    final doc = await _store.read('$libraryPath/$workId');
    final entry = LibraryEntry.fromFields(workId, doc.fields);
    if (entry == null || entry.status == status) return;
    final plan = await _statusPlan(workId, doc.fields, status, finish);
    final finished = _finishedEvent(plan, workId, entry.activeEditionId);
    await _store.batch((b) {
      b.write('$libraryPath/$workId', {
        LibraryFields.status: status.name,
        LibraryFields.statusChangedAt: _iso(_clock.now()),
        ...plan.libraryChanges,
      });
      plan.apply(b);
      if (finished != null) _appendEvent(b, finished);
    });
    _onLocalWrite();
  }

  @override
  Future<bool> hasOpenReadThrough(String workId) async {
    final throughs = await _readThroughsOf(workId);
    return throughs.values.any((t) => t.outcome == ReadThroughOutcome.inProgress);
  }

  @override
  Future<bool> restoresFinishedRead(String workId) async {
    final doc = await _store.read('$libraryPath/$workId');
    if (doc.fields[LibraryFields.removed] != true) return false;
    final throughs = (await _readThroughsOf(workId)).values;
    return throughs.any((t) => t.outcome == ReadThroughOutcome.finished) &&
        !throughs.any((t) => t.outcome == ReadThroughOutcome.inProgress);
  }

  @override
  Future<void> setFinishDate(String readThroughId, ReadFinish finish) async {
    final path = '$readThroughsPath/$readThroughId';
    final rt = ReadThrough.fromFields(readThroughId, (await _store.read(path)).fields);
    if (rt == null || rt.outcome != ReadThroughOutcome.finished) return;
    final at = finish.resolve(_clock.now());
    final started = rt.startedAt;
    await _store.write(path, {
      'finishedAt': at == null ? null : _iso(at),
      // A read can't end before it began, so an earlier finish moves the start.
      if (at != null && started != null && at.isBefore(started)) 'startedAt': _iso(at),
    });
    _onLocalWrite();
  }

  @override
  Future<void> setStartDate(String readThroughId, DateTime date) async {
    final path = '$readThroughsPath/$readThroughId';
    final rt = ReadThrough.fromFields(readThroughId, (await _store.read(path)).fields);
    if (rt == null) return;
    final finished = rt.finishedAt;
    if (finished != null && date.isAfter(finished)) return;
    await _store.write(path, {'startedAt': _iso(date)});
    _onLocalWrite();
  }

  @override
  Future<ImportOutcome> importBook({
    required String workId,
    required BookSummary book,
    required ImportedBook imported,
    UserEdition? edition,
  }) async {
    final path = '$libraryPath/$workId';
    final doc = await _store.read(path);
    // Removed on purpose.
    if (doc.fields[LibraryFields.removed] == true) return ImportOutcome.removedEarlier;
    final existing = LibraryEntry.fromFields(workId, doc.fields);
    final throughs = await _readThroughsOf(workId);
    var ordinal = throughs.values.fold(0, (m, t) => t.ordinal > m ? t.ordinal : m);
    final writes = <String, Map<String, Object?>>{};
    final events = <ProgressEvent>[];
    final editionId = existing?.activeEditionId ?? edition?.editionId;
    final known = {for (final t in throughs.values) t.id};
    final finishedDays = {
      for (final t in throughs.values)
        if (t.outcome == ReadThroughOutcome.finished && t.finishedAt != null)
          _localDay(t.finishedAt!),
    };
    String? last;

    // Dated reads, unless that day's read is already recorded.
    for (var i = 0; i < imported.finishedOn.length; i++) {
      final at = imported.finishedOn[i];
      final id = 'imp_${imported.key}_$i';
      if (known.contains(id) || !finishedDays.add(_localDay(at))) continue;
      writes['$readThroughsPath/$id'] = {
        'workId': workId,
        'ordinal': ++ordinal,
        'finishedAt': _iso(at),
        'outcome': ReadThroughOutcome.finished.name,
      };
      last = id;
      events.add(
        ProgressEvent(
          id: 'imp_${imported.key}_e$i',
          workId: workId,
          readThroughId: id,
          editionId: editionId,
          position: const ReadingPosition.finished(),
          fraction: 1,
          isApproximate: false,
          source: ProgressSource.import,
          recordedAt: at,
        ),
      );
    }

    // Undated reads, only as far as the export says there were more reads.
    final finishedNow =
        throughs.values.where((t) => t.outcome == ReadThroughOutcome.finished).length +
        writes.length;
    final wanted = imported.finishedOn.length + imported.undatedReads;
    for (var i = 0; i < wanted - finishedNow; i++) {
      final id = 'imp_${imported.key}_u$i';
      if (known.contains(id)) continue;
      writes['$readThroughsPath/$id'] = {
        'workId': workId,
        'ordinal': ++ordinal,
        'outcome': ReadThroughOutcome.finished.name,
      };
      last = id;
    }

    final library = <String, Object?>{};
    if (existing == null) {
      if (imported.status == ReadingStatus.reading || imported.status == ReadingStatus.dnf) {
        final id = 'imp_${imported.key}_s';
        if (!known.contains(id)) {
          writes['$readThroughsPath/$id'] = {
            'workId': workId,
            'ordinal': ++ordinal,
            'outcome': imported.status == ReadingStatus.reading
                ? ReadThroughOutcome.inProgress.name
                : ReadThroughOutcome.abandoned.name,
          };
        }
        last = id;
      }
      final now = _iso(_clock.now());
      library.addAll({
        ...book.toFields(),
        LibraryFields.status: imported.status.name,
        LibraryFields.addedAt: imported.dateAdded == null ? now : _iso(imported.dateAdded!),
        LibraryFields.statusChangedAt: now,
        LibraryFields.isWishlist: false,
        LibraryFields.removed: false,
        LibraryFields.rating: imported.rating,
        LibraryFields.review: imported.review,
        LibraryFields.activeEditionId: ?edition?.editionId,
        LibraryFields.activeReadThroughId: ?last,
      });
    } else {
      if (existing.rating == null && imported.rating != null) {
        library[LibraryFields.rating] = imported.rating;
      }
      if (existing.review == null && imported.review != null) {
        library[LibraryFields.review] = imported.review;
      }
    }

    final addEdition = edition != null && existing == null;
    await _store.batch((b) {
      if (library.isNotEmpty) b.write(path, library);
      if (addEdition) b.write('$editionsPath/${edition.editionId}', _editionFields(edition));
      for (final w in writes.entries) {
        b.write(w.key, w.value);
      }
      for (final e in events) {
        _appendEvent(b, e);
      }
    });
    _onLocalWrite();
    return existing == null ? ImportOutcome.added : ImportOutcome.alreadyInLibrary;
  }

  static String _localDay(DateTime t) {
    final l = t.toLocal();
    return '${l.year}-${l.month}-${l.day}';
  }

  /// A finished read-through with a known date gets a 100 % event, on that
  /// date, so pages goals and book goals agree.
  ProgressEvent? _finishedEvent(_StatusPlan plan, String workId, String? editionId) {
    final through = plan.finishedEventFor;
    final at = plan.finishedAt;
    if (through == null || at == null) return null;
    return ProgressEvent(
      id: _ids.newId(),
      workId: workId,
      readThroughId: through,
      editionId: editionId,
      position: const ReadingPosition.finished(),
      fraction: 1,
      isApproximate: false,
      source: ProgressSource.manual,
      recordedAt: at,
    );
  }

  @override
  Future<ProgressEvent?> recordProgress(
    String workId,
    ReadingPosition position, {
    ProgressSource source = ProgressSource.manual,
  }) async {
    final doc = await _store.read('$libraryPath/$workId');
    final entry = LibraryEntry.fromFields(workId, doc.fields);
    if (entry == null) return null;

    final metrics = await _metricsFor(entry);
    final mapped = ProgressMapper.toFraction(position, metrics);
    if (mapped == null) return null;

    // Logging progress implies reading: open (or reopen) a read-through.
    final needsReading = entry.status != ReadingStatus.reading;
    final plan = needsReading
        ? await _statusPlan(workId, doc.fields, ReadingStatus.reading)
        : _StatusPlan.none;
    final readThroughId = plan.readThroughId ?? entry.activeReadThroughId;
    if (readThroughId == null) return null; // unreachable: reading always has one

    final event = ProgressEvent(
      id: _ids.newId(),
      workId: workId,
      readThroughId: readThroughId,
      editionId: entry.activeEditionId,
      position: position,
      fraction: mapped.fraction,
      isApproximate: mapped.isApproximate,
      source: source,
      recordedAt: _clock.now(),
    );
    await _store.batch((b) {
      if (needsReading) {
        b.write('$libraryPath/$workId', {
          LibraryFields.status: ReadingStatus.reading.name,
          LibraryFields.statusChangedAt: _iso(_clock.now()),
          ...plan.libraryChanges,
        });
      }
      plan.apply(b);
      _appendEvent(b, event);
    });
    _onLocalWrite();
    return event;
  }

  @override
  Future<void> setActiveEdition(String workId, UserEdition edition) async {
    final doc = await _store.read('$libraryPath/$workId');
    final entry = LibraryEntry.fromFields(workId, doc.fields);
    if (entry == null) return;
    final existing = await _store.read('$editionsPath/${edition.editionId}');
    await _store.batch((b) {
      if (UserEdition.fromFields(edition.editionId, existing.fields) == null) {
        b.write('$editionsPath/${edition.editionId}', _editionFields(edition));
      }
      b.write('$libraryPath/$workId', {
        LibraryFields.activeEditionId: edition.editionId,
        // Library, home and the book page all show the edition being read.
        if (edition.coverUrl != null) LibraryFields.coverUrl: edition.coverUrl,
      });
    });
    _onLocalWrite();
  }

  @override
  Future<void> saveAudiobookEdition(UserEdition edition) async {
    await _store.batch((b) {
      b.write('$editionsPath/${edition.editionId}', _editionFields(edition));
      b.write('$libraryPath/${edition.workId}', {LibraryFields.activeEditionId: edition.editionId});
    });
    _onLocalWrite();
  }

  @override
  Future<void> setOwned(UserEdition edition, {required bool owned}) async {
    final path = '$editionsPath/${edition.editionId}';
    final existing = UserEdition.fromFields(edition.editionId, (await _store.read(path)).fields);
    await _store.write(path, {if (existing == null) ..._editionFields(edition), 'owned': owned});
    _onLocalWrite();
  }

  @override
  Future<void> setFavorite(String workId, {required bool favorite}) async {
    await _store.write('$libraryPath/$workId', {LibraryFields.isFavorite: favorite});
    _onLocalWrite();
  }

  @override
  Future<void> remove(String workId) async {
    await _store.write('$libraryPath/$workId', {LibraryFields.removed: true});
    _onLocalWrite();
  }

  // ─── Sync (remote → local) ───

  /// Subscribes [engine] to the four user collections. LWW documents merge
  /// per field; progress events are insert-or-ignore.
  Future<void> attachSync(SyncEngine engine) => Future.wait([
    engine.watchCollection(libraryPath, engine.applyLww),
    engine.watchCollection(readThroughsPath, engine.applyLww),
    engine.watchCollection(editionsPath, engine.applyLww),
    engine.watchCollection(progressPath, applyRemoteProgress),
    engine.watchCollection(sessionsPath, applyRemoteSession),
    engine.watchCollection(sessionTombstonesPath, applyRemoteSessionTombstone),
  ]);

  /// Applies a progress event pulled from the server. Insert-or-ignore:
  /// events are immutable, so a known id is already up to date.
  Future<void> applyRemoteProgress(RemoteDoc doc) async {
    final d = doc.data;
    final position = d['position'];
    final recordedAt = DateTime.tryParse(d['recordedAt'] as String? ?? '');
    if (position is! Map || recordedAt == null) return;
    await _db
        .into(_db.progressEvents)
        .insert(
          ProgressEventsCompanion.insert(
            id: doc.id,
            workId: d['workId']! as String,
            readThroughId: d['readThroughId']! as String,
            editionId: Value(d['editionId'] as String?),
            positionJson: jsonEncode(position),
            fraction: (d['fraction']! as num).toDouble(),
            isApproximate: d['isApproximate'] == true,
            source: d['source'] as String? ?? 'manual',
            sessionId: Value(d['sessionId'] as String?),
            recordedAt: recordedAt,
          ),
          mode: InsertMode.insertOrIgnore,
        );
  }

  // ─── Sessions (Phase 5) ───

  @override
  Stream<List<ReadingSession>> watchSessions({String? workId, int limit = 50}) {
    final q = _db.select(_db.sessions)
      ..orderBy([(t) => OrderingTerm.desc(t.startedAt)])
      ..limit(limit);
    if (workId != null) q.where((t) => t.workId.equals(workId));
    // A tombstone wins whatever order the session and it arrive in.
    final deleted = _db.selectOnly(_db.sessionTombstones)..addColumns([_db.sessionTombstones.id]);
    q.where((t) => t.id.isNotInQuery(deleted));
    return q.watch().map((rows) => [for (final r in rows) ?sessionFromJson(r.id, r.dataJson)]);
  }

  @override
  Future<ReadingSession?> completeSession(
    ActiveSession active, {
    required int activeDurationSec,
    ReadingPosition? endPosition,
  }) async {
    final end = active.clock.endedAt;
    if (end == null) throw StateError('Session must be ended before it is saved');
    final workId = active.workId;
    final doc = await _store.read('$libraryPath/$workId');
    final entry = LibraryEntry.fromFields(workId, doc.fields);
    if (entry == null) return null; // removed from the library meanwhile

    final metrics = await _metricsFor(entry);
    final mapped = endPosition == null ? null : ProgressMapper.toFraction(endPosition, metrics);
    final needsReading = entry.status != ReadingStatus.reading;
    final plan = needsReading
        ? await _statusPlan(workId, doc.fields, ReadingStatus.reading)
        : _StatusPlan.none;
    final readThroughId = plan.readThroughId ?? entry.activeReadThroughId;
    if (readThroughId == null) return null;

    final session = ReadingSession(
      id: active.id,
      workId: workId,
      readThroughId: readThroughId,
      editionId: active.editionId ?? entry.activeEditionId,
      startedAt: active.clock.startedAt,
      endedAt: end,
      plannedDurationSec: active.clock.planned.inSeconds,
      activeDurationSec: activeDurationSec.clamp(0, 24 * 3600),
      pauses: active.clock.pauses,
      startPosition: active.startPosition,
      endPosition: mapped == null ? null : endPosition,
      startFraction: active.startFraction,
      endFraction: mapped?.fraction,
      pagesRead: _pagesRead(active, endPosition, mapped?.fraction, metrics),
      localDate: ReadingSession.localDateOf(active.clock.startedAt),
      tzOffsetMin: active.clock.startedAt.toLocal().timeZoneOffset.inMinutes,
      completion: active.completion,
      clockAdjusted: active.clock.clockAdjusted,
    );
    final event = mapped == null
        ? null
        : ProgressEvent(
            id: _ids.newId(),
            workId: workId,
            readThroughId: readThroughId,
            editionId: session.editionId,
            position: endPosition!,
            fraction: mapped.fraction,
            isApproximate: mapped.isApproximate,
            source: ProgressSource.session,
            sessionId: session.id,
            recordedAt: end,
          );
    final data = sessionToJson(session);
    await _store.batch((b) {
      if (needsReading) {
        b.write('$libraryPath/$workId', {
          LibraryFields.status: ReadingStatus.reading.name,
          LibraryFields.statusChangedAt: _iso(_clock.now()),
          ...plan.libraryChanges,
        });
      }
      plan.apply(b);
      b.append('$sessionsPath/${session.id}', data, () async {
        await _insertSession(session.id, data);
        // The live timer row goes in the same transaction: a crash can't
        // leave both a saved session and a resumable timer.
        await _db.delete(_db.activeSessions).go();
      });
      if (event != null) _appendEvent(b, event);
    });
    _onLocalWrite();
    return session;
  }

  @override
  Future<void> deleteSession(String sessionId) async {
    await _store.batch((b) {
      b.append('$sessionTombstonesPath/$sessionId', {
        'deletedAt': _iso(_clock.now()),
      }, () => _insertTombstone(sessionId));
    });
    _onLocalWrite();
  }

  /// Applies a deletion pulled from the server (insert-or-ignore).
  Future<void> applyRemoteSessionTombstone(RemoteDoc doc) => _insertTombstone(doc.id);

  Future<void> _insertTombstone(String sessionId) => _db
      .into(_db.sessionTombstones)
      .insert(SessionTombstonesCompanion.insert(id: sessionId), mode: InsertMode.insertOrIgnore);

  @override
  Stream<Set<String>> watchDeletedSessionIds() =>
      _db.select(_db.sessionTombstones).watch().map((rows) => {for (final r in rows) r.id});

  @override
  Stream<List<ReadThrough>> watchAllReadThroughs() => _store
      .watchCollection(readThroughsPath)
      .map(
        (docs) => [for (final e in docs.entries) ?ReadThrough.fromFields(e.key, e.value.fields)],
      );

  @override
  Stream<List<UserEdition>> watchAllEditions() => _store
      .watchCollection(editionsPath)
      .map(
        (docs) => [for (final e in docs.entries) ?UserEdition.fromFields(e.key, e.value.fields)],
      );

  @override
  Stream<List<ProgressEvent>> watchAllProgress() =>
      _db.select(_db.progressEvents).watch().map((rows) => rows.map(progressFromRow).toList());

  @override
  Future<bool> setRating(String workId, double? rating) async {
    if (rating != null && !LibraryEntry.isValidRating(rating)) return false;
    await _store.write('$libraryPath/$workId', {LibraryFields.rating: rating});
    _onLocalWrite();
    return true;
  }

  @override
  Future<bool> setReview(String workId, String? review) async {
    final clean = review?.trim();
    if (clean != null && clean.length > LibraryEntry.maxReviewLength) return false;
    await _store.write('$libraryPath/$workId', {
      LibraryFields.review: clean == null || clean.isEmpty ? null : clean,
    });
    _onLocalWrite();
    return true;
  }

  /// Applies a session pulled from the server (insert-or-ignore).
  Future<void> applyRemoteSession(RemoteDoc doc) async {
    final data = Map<String, Object?>.of(doc.data)..remove(RemoteDoc.updatedAtKey);
    if (sessionFromJson(doc.id, jsonEncode(data)) == null) return;
    await _insertSession(doc.id, data);
  }

  Future<void> _insertSession(String id, Map<String, Object?> data) => _db
      .into(_db.sessions)
      .insert(
        SessionsCompanion.insert(
          id: id,
          workId: data['workId']! as String,
          readThroughId: data['readThroughId']! as String,
          startedAt: DateTime.parse(data['startedAt']! as String),
          endedAt: DateTime.parse(data['endedAt']! as String),
          activeDurationSec: (data['activeDurationSec']! as num).toInt(),
          localDate: data['localDate']! as String,
          dataJson: jsonEncode(data),
        ),
        mode: InsertMode.insertOrIgnore,
      );

  static int? _pagesRead(
    ActiveSession a,
    ReadingPosition? end,
    double? endFraction,
    EditionMetrics metrics,
  ) {
    final start = a.startPosition;
    if (start is PagePosition && end is PagePosition) {
      final d = end.page - start.page;
      return d >= 0 ? d : null;
    }
    final pages = metrics.isAudio ? null : metrics.pageCount;
    final from = a.startFraction ?? 0;
    if (pages == null || endFraction == null || endFraction < from) return null;
    return ((endFraction - from) * pages).round();
  }

  static Map<String, Object?> sessionToJson(ReadingSession s) => {
    'workId': s.workId,
    'readThroughId': s.readThroughId,
    'editionId': ?s.editionId,
    'startedAt': _iso(s.startedAt),
    'endedAt': _iso(s.endedAt),
    'plannedDurationSec': s.plannedDurationSec,
    'activeDurationSec': s.activeDurationSec,
    'pauses': [for (final p in s.pauses.take(50)) p.toJson()],
    if (s.startPosition != null) 'startPosition': s.startPosition!.toJson(),
    if (s.endPosition != null) 'endPosition': s.endPosition!.toJson(),
    'startFraction': ?s.startFraction,
    'endFraction': ?s.endFraction,
    'pagesRead': ?s.pagesRead,
    'localDate': s.localDate,
    'tzOffsetMin': s.tzOffsetMin,
    'completion': s.completion.name,
    'clockAdjusted': s.clockAdjusted,
  };

  static ReadingSession? sessionFromJson(String id, String json) {
    try {
      final d = jsonDecode(json) as Map<String, dynamic>;
      ReadingPosition? pos(Object? v) =>
          v is Map ? ReadingPosition.fromJson(v.cast<String, dynamic>()) : null;
      return ReadingSession(
        id: id,
        workId: d['workId'] as String,
        readThroughId: d['readThroughId'] as String,
        editionId: d['editionId'] as String?,
        startedAt: DateTime.parse(d['startedAt'] as String),
        endedAt: DateTime.parse(d['endedAt'] as String),
        plannedDurationSec: (d['plannedDurationSec'] as num).toInt(),
        activeDurationSec: (d['activeDurationSec'] as num).toInt(),
        pauses: [
          for (final p in (d['pauses'] as List? ?? const []))
            PauseInterval.fromJson((p as Map).cast<String, Object?>()),
        ],
        startPosition: pos(d['startPosition']),
        endPosition: pos(d['endPosition']),
        startFraction: (d['startFraction'] as num?)?.toDouble(),
        endFraction: (d['endFraction'] as num?)?.toDouble(),
        pagesRead: (d['pagesRead'] as num?)?.toInt(),
        localDate: d['localDate'] as String,
        tzOffsetMin: (d['tzOffsetMin'] as num?)?.toInt() ?? 0,
        completion: SessionCompletion.parse(d['completion']),
        clockAdjusted: d['clockAdjusted'] == true,
      );
    } on Object {
      return null; // malformed remote/local data never crashes the list
    }
  }

  // ─── Internals ───

  /// Works out the read-through changes for moving to [status].
  Future<_StatusPlan> _statusPlan(
    String workId,
    Map<String, Object?> libraryFields,
    ReadingStatus status, [
    ReadFinish finish = const ReadFinish.now(),
  ]) async {
    final activeId = libraryFields[LibraryFields.activeReadThroughId] as String?;
    final throughs = await _readThroughsOf(workId);
    final active = activeId == null ? null : throughs[activeId];
    final open = active != null && active.outcome == ReadThroughOutcome.inProgress ? active : null;
    final nextOrdinal = throughs.values.fold(0, (m, rt) => rt.ordinal > m ? rt.ordinal : m) + 1;
    final now = _iso(_clock.now());

    switch (status) {
      case ReadingStatus.reading:
        if (open != null) return _StatusPlan.none;
        final id = _ids.newId();
        return _StatusPlan(
          readThroughId: id,
          libraryChanges: {LibraryFields.activeReadThroughId: id},
          writes: {
            '$readThroughsPath/$id': {
              'workId': workId,
              'ordinal': nextOrdinal,
              'startedAt': now,
              'outcome': ReadThroughOutcome.inProgress.name,
            },
          },
        );
      case ReadingStatus.read:
        final finishedAt = finish.resolve(_clock.now());
        final finishedIso = finishedAt == null ? null : _iso(finishedAt);
        if (open != null) {
          return _StatusPlan(
            readThroughId: open.id,
            writes: {
              '$readThroughsPath/${open.id}': {
                'finishedAt': finishedIso,
                'outcome': ReadThroughOutcome.finished.name,
              },
            },
            finishedEventFor: open.id,
            finishedAt: finishedAt,
          );
        }
        // Marked read without tracking: record a finished read-through.
        final id = _ids.newId();
        return _StatusPlan(
          readThroughId: id,
          libraryChanges: {LibraryFields.activeReadThroughId: id},
          writes: {
            '$readThroughsPath/$id': {
              'workId': workId,
              'ordinal': nextOrdinal,
              'finishedAt': finishedIso,
              'outcome': ReadThroughOutcome.finished.name,
            },
          },
          finishedEventFor: id,
          finishedAt: finishedAt,
        );
      case ReadingStatus.dnf:
        if (open == null) return _StatusPlan.none;
        return _StatusPlan(
          readThroughId: open.id,
          writes: {
            '$readThroughsPath/${open.id}': {
              'finishedAt': now,
              'outcome': ReadThroughOutcome.abandoned.name,
            },
          },
        );
      case ReadingStatus.wantToRead || ReadingStatus.none:
        // Pausing keeps the open read-through; going back to Reading resumes it.
        return _StatusPlan.none;
    }
  }

  Future<Map<String, ReadThrough>> _readThroughsOf(String workId) async {
    final docs = await _store.readCollection(readThroughsPath);
    return {
      for (final rt in [
        for (final e in docs.entries) ?ReadThrough.fromFields(e.key, e.value.fields),
      ])
        if (rt.workId == workId) rt.id: rt,
    };
  }

  Future<EditionMetrics> _metricsFor(LibraryEntry entry) async {
    final editionId = entry.activeEditionId;
    if (editionId != null) {
      final ed = UserEdition.fromFields(
        editionId,
        (await _store.read('$editionsPath/$editionId')).fields,
      );
      if (ed != null) return ed.metrics;
    }
    return EditionMetrics(format: 'other', pageCount: entry.book.pageCount);
  }

  void _appendEvent(StoreBatch b, ProgressEvent e) {
    final positionJson = e.position.toJson();
    b.append(
      '$progressPath/${e.id}',
      {
        'workId': e.workId,
        'readThroughId': e.readThroughId,
        'editionId': ?e.editionId,
        'position': positionJson,
        'fraction': e.fraction,
        'isApproximate': e.isApproximate,
        'source': e.source.name,
        'sessionId': ?e.sessionId,
        'recordedAt': _iso(e.recordedAt),
      },
      () => _db
          .into(_db.progressEvents)
          .insert(
            ProgressEventsCompanion.insert(
              id: e.id,
              workId: e.workId,
              readThroughId: e.readThroughId,
              editionId: Value(e.editionId),
              positionJson: jsonEncode(positionJson),
              fraction: e.fraction,
              isApproximate: e.isApproximate,
              source: e.source.name,
              sessionId: Value(e.sessionId),
              recordedAt: e.recordedAt,
            ),
            mode: InsertMode.insertOrIgnore,
          ),
    );
  }

  Map<String, Object?> _editionFields(UserEdition e) => {
    'workId': e.workId,
    'format': e.format,
    'owned': e.owned,
    'isbn13': e.isbn13,
    'publisher': e.publisher,
    'coverUrl': e.coverUrl,
    'pageCount': e.pageCount != null && e.pageCount! > 0 ? e.pageCount : null,
    'audioDurationSec': e.audioDurationSec != null && e.audioDurationSec! > 0
        ? e.audioDurationSec
        : null,
  };

  static String _iso(DateTime t) => t.toUtc().toIso8601String();

  /// Converts a local row to the domain event.
  ProgressEvent progressFromRow(ProgressEventRow r) => ProgressEvent(
    id: r.id,
    workId: r.workId,
    readThroughId: r.readThroughId,
    editionId: r.editionId,
    position: ReadingPosition.fromJson(jsonDecode(r.positionJson) as Map<String, dynamic>),
    fraction: r.fraction,
    isApproximate: r.isApproximate,
    source: ProgressSource.values.firstWhere(
      (s) => s.name == r.source,
      orElse: () => ProgressSource.manual,
    ),
    sessionId: r.sessionId,
    recordedAt: r.recordedAt,
  );
}

/// Read-through side effects of a status change, applied inside the same
/// [LwwStore.batch] as the library write.
final class _StatusPlan {
  const _StatusPlan({
    this.readThroughId,
    this.libraryChanges = const {},
    this.writes = const {},
    this.finishedEventFor,
    this.finishedAt,
  });

  static const none = _StatusPlan();

  final String? readThroughId;
  final Map<String, Object?> libraryChanges;
  final Map<String, Map<String, Object?>> writes;

  /// Read-through that gets a 100 % progress event, if [finishedAt] is known.
  final String? finishedEventFor;
  final DateTime? finishedAt;

  void apply(StoreBatch b) {
    for (final w in writes.entries) {
      b.write(w.key, w.value);
    }
  }
}
