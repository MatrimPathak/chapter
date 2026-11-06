# 03 — Data Architecture: Firestore Schema, Local Schema, Core Dart Models

## 1. Domain model overview

```
            ┌────────── global catalog (server-written, read-only to clients) ──────────┐
            │  Author ◄──M:N──► Work ──1:N──► Edition          Series ──1:N──► SeriesEntry ──► Work
            └──────────────────────────┬────────────────────────────────────────────────┘
                                       │ workId
            ┌──────────────────────── user space (users/{uid}) ─────────────────────────┐
            │  LibraryEntry (1 per work)                                                 │
            │     ├── activeEditionId ──► UserEdition (owned/used editions + overrides)  │
            │     ├── ReadThrough (1..N; one per read/reread)                            │
            │     │      ├── ProgressEvent (append-only)                                 │
            │     │      └── ReadingSession (append-only)                                │
            │     └── Note (0..N)                                                        │
            │  Goal (0..N) · Preferences · Profile                                       │
            └────────────────────────────────────────────────────────────────────────────┘
```

## 2. Firestore schema (final proposal)

I evaluated the suggested schema and changed two things:

- **Flat user subcollections** instead of `books/{workId}/editions`. The sync engine runs one incremental listener per collection (`where updatedAt > cursor`). Deep nesting would need one listener per book, or collection-group queries, which can't be scoped to a single user cheaply.
- **The global catalog is split** into works, editions, authors and series, plus lookup indexes.

### 2.1 Global catalog (written only by Cloud Functions)

| Path | Purpose | Key fields |
|---|---|---|
| `catalog_works/{workId}` | Normalized work | `title, subtitle, authorIds[], authorNames[], description, firstPublishedDate, language, genres[], seriesRefs[{seriesId, position, positionLabel, isPrimary}], defaultEditionId, coverUrl, providerIds{hardcover, openLibrary, googleBooks}, provenance{field:{provider, fetchedAt}}, schemaVersion, refreshedAt` |
| ~~`catalog_editions/{editionId}`~~ | **Not used (Phase 3, TD-17).** Editions (≤ 50) are embedded in `catalog_works/{workId}.editions[]` with fields `id, workId, format, isbn10, isbn13, publisher, publishedDate, pageCount, audioDurationSec, language, coverUrl, providerIds{}`, so a detail screen costs one read. ISBN lookups go through `catalog_isbn`. | — |
| `catalog_authors/{authorId}` | Author | `name, sortName, bio, photoUrl, photoCredit, birthDate, deathDate, providerIds{}, knownWorkIds[] (capped at 50)` |
| `catalog_series/{seriesId}` | Series | `name, description, entries[{workId, position, positionLabel, isPrimary, title, coverUrl}], primaryCount, providerIds{}` |
| `catalog_isbn/{isbn13}` | ISBN → edition lookup | `editionId, workId` |
| `catalog_providerIndex/{provider}:{externalId}` | Deduplication | `kind (work/edition/author/series), internalId` |
| `catalog_searchCache/{sha256(normalizedQuery+page)}` | Search results cache | `results[] (summaries), providerUsed, expiresAt` (Firestore TTL policy, 24 h) |
| `ops_rateLimits/{uid}` | Per-user callable token bucket | Server-only |

The ISBN-10 is always normalized to ISBN-13 for the lookup key.

### 2.2 User space

| Path | Doc ID | Key fields |
|---|---|---|
| `users/{uid}` | uid | Flat per-field LWW document (implemented in Phase 2): `displayName, photoUrl, email, onboardingDone, theme, analyticsConsent, crashConsent, defaultTimerMin, weekStartsOn`, plus `fieldClock{field: hlc}` and `updatedAt`. Fields are flat rather than nested under `preferences{}` so each preference merges independently and the rules can allow-list them. `defaultStatus` and `focusModeEnabled` are added by the phases that use them. |
| `users/{uid}/library/{workId}` | workId | `status (none/wantToRead/reading/read/dnf), isWishlist, isFavorite, rating (0.5–5, null), review, activeEditionId, activeReadThroughId, progressSnapshot{fraction, positionJson, isApproximate, updatedAt}, addedAt, lastActivityAt, workSummary{title, authorNames[], coverUrl, pageCount, seriesId, seriesPosition, genres[]}, fieldClock{field: hlc}, hlc, updatedAt, deleted` |
| `users/{uid}/userEditions/{editionId}` | editionId | `workId, owned, format, overrides{pageCount, audioDurationSec, contentStartPage, contentEndPage}, calibration[{pageOrLoc, audioSec}], editionSummary{…}, hlc, updatedAt, deleted` |
| `users/{uid}/readThroughs/{id}` | uuid v7 | `workId, ordinal (1, 2, 3…), startedAt, finishedAt, outcome (inProgress/finished/abandoned), hlc, updatedAt, deleted` |
| `users/{uid}/progressEvents/{id}` | uuid v7 | `workId, readThroughId, editionId, position (tagged union JSON), fraction, isApproximate, source (manual/session/import), sessionId?, recordedAt, hlc, updatedAt` (**append-only**; corrections are new events, deletions are tombstones) |
| `users/{uid}/sessions/{id}` | uuid v7 | `workId, readThroughId, editionId, startedAt, endedAt, plannedDurationSec, activeDurationSec, pauses[{start, end}], startPosition, endPosition, pagesRead, localDate (YYYY-MM-DD in the user's zone), tzOffsetMin, completion (completed/endedEarly/recovered), hlc, updatedAt, deleted` |
| `users/{uid}/notes/{id}` | uuid v7 | `workId, readThroughId?, kind (note/quote/observation), text (≤ 10k chars), anchor{page?, positionJson?}, createdAt, hlc, updatedAt, deleted` |
| `users/{uid}/goals/{id}` | uuid v7 | `metric (books/pages/minutes), period (year/month/custom), start, end, target, archived, hlc, updatedAt, deleted` |

`workSummary` is denormalized onto the library entry so that library screens render from one collection. The sync engine refreshes it when the catalog changes (it is not user data and is safe to overwrite).

### 2.3 Required composite indexes

- `library`: `updatedAt ASC` (sync cursor). This is a single-field index and is automatic.
- All user collections sync only by `updatedAt`. Every complex query runs locally in Drift, which keeps the Firestore index count and read cost minimal.

### 2.4 Cost model

- **Reads:** the initial sync costs one read per document. After that, listeners only receive changed documents. Library screens read nothing from Firestore.
- **Writes:** one write per user mutation. Progress events and sessions are small. A heavy reader (2 sessions a day) produces about 1.5k writes a month, which is well inside free-tier scale for each user.
- **Catalog:** the search cache absorbs repeated queries, and `getWork` is cached in the catalog.

## 3. Consistency rules

| Operation | Mechanism |
|---|---|
| Complete a session (session + progress event + library snapshot + possibly status change) | **One Drift transaction** locally, then **one Firestore `WriteBatch`** when the outbox flushes. The outbox groups operations by `batchId`. |
| Mark as read | The same transaction sets `readThrough.finishedAt` and `library.status`. |
| Catalog upsert (work + editions + indexes) | A server-side Firestore **transaction**. ISBN index uniqueness is guaranteed by `create()` semantics. |
| Account deletion | A server function: `recursiveDelete(users/{uid})`, then delete the Auth user. It is idempotent and safe to retry. |

## 4. Conflict resolution (HLC = hybrid logical clock `wallMs:counter:deviceId`)

| Entity | Policy | Why nothing is lost |
|---|---|---|
| `progressEvents`, `sessions` | **Set union** (append-only, globally unique IDs) | No concurrent overwrites are possible. |
| `library.progressSnapshot` | **Derived.** Recomputed from the event with the highest `(recordedAt, hlc)` | The snapshot is a projection. The events remain the truth. |
| `library` other fields | **Per-field last-writer-wins** using `fieldClock` | Changing the rating on phone A and the status on phone B keeps both changes. |
| `notes`, `goals`, `userEditions`, `readThroughs` | **Document last-writer-wins** by HLC, with tombstones (`deleted: true`). Hard purge happens after 30 days. | For notes, if both sides edited text since the last sync, the losing version is **kept as a conflict copy note** ("Edited on another device"). It is never silently dropped. |

## 5. Local schema (Drift)

The local tables mirror the user collections one to one (same columns, with JSON columns for nested maps), plus:

| Table | Purpose |
|---|---|
| `catalog_works`, `catalog_editions`, `catalog_authors`, `catalog_series` | Cached copies of every catalog document the user has touched. |
| `outbox` | `id, batchId, collection, docId, opType (upsert/delete), payloadJson, hlc, attempts, lastError, createdAt` |
| `sync_state` | `collection, cursorUpdatedAt, lastPullAt, lastPushAt` |
| `search_cache` | `queryKey, resultsJson, expiresAt` |
| `recent_searches` | `query, searchedAt` |
| `active_session` | A singleton row holding a live timer's state, written on every state change and used for crash recovery. |

There is one database file per uid (`chapter_<uid>.sqlite`). Migrations are versioned with Drift's `stepByStep` and tested with `drift_dev schema` snapshots.

## 6. Core Dart models (domain layer; Freezed)

```dart
// ───────────── Catalog ─────────────
enum MetadataProvider { hardcover, openLibrary, googleBooks, user }

@freezed
class FieldProvenance with _$FieldProvenance {
  const factory FieldProvenance({
    required MetadataProvider provider,
    required DateTime fetchedAt,
  }) = _FieldProvenance;
}

@freezed
class SeriesRef with _$SeriesRef {
  const factory SeriesRef({
    required String seriesId,
    required String seriesName,
    double? position,        // 1, 2, 2.5 (novella)…
    String? positionLabel,   // "Book 2", "0.5", "Prequel"
    @Default(true) bool isPrimary,
  }) = _SeriesRef;
}

@freezed
class Work with _$Work {
  const factory Work({
    required String id,
    required String title,
    String? subtitle,
    required List<AuthorRef> authors,
    String? description,
    String? firstPublishedDate,   // partial dates allowed: "1997", "1997-06"
    String? language,
    @Default([]) List<String> genres,
    @Default([]) List<SeriesRef> series,
    String? coverUrl,
    String? defaultEditionId,
    @Default({}) Map<MetadataProvider, String> providerIds,
    @Default({}) Map<String, FieldProvenance> provenance,
    DateTime? refreshedAt,
  }) = _Work;
}

@freezed
class AuthorRef with _$AuthorRef {
  const factory AuthorRef({required String id, required String name, String? role}) = _AuthorRef;
}

enum EditionFormat { paperback, hardcover, massMarket, ebook, kindle, epub, audiobook, audible, other }

@freezed
class Edition with _$Edition {
  const factory Edition({
    required String id,
    required String workId,
    required EditionFormat format,
    String? isbn10,
    String? isbn13,
    String? asin,
    String? publisher,
    String? publishedDate,
    int? pageCount,
    int? audioDurationSec,
    String? language,
    String? coverUrl,
    String? platform,             // "Kindle", "Audible", "Kobo"…
    @Default({}) Map<MetadataProvider, String> providerIds,
    @Default({}) Map<String, FieldProvenance> provenance,
  }) = _Edition;
}

@freezed class Author with _$Author { /* id, name, sortName, bio, photoUrl, photoCredit, knownWorkIds, providerIds */ }
@freezed class Series with _$Series { /* id, name, description, entries: List<SeriesEntry> */ }
@freezed class SeriesEntry with _$SeriesEntry { /* workId, title, coverUrl, position, positionLabel, isPrimary */ }

// ───────────── Position & progress ─────────────
@Freezed(unionKey: 'type')
sealed class ReadingPosition with _$ReadingPosition {
  const factory ReadingPosition.page({required int page}) = PagePosition;
  const factory ReadingPosition.percent({required double percent}) = PercentPosition; // 0–100
  const factory ReadingPosition.audio({required int seconds}) = AudioPosition;
  const factory ReadingPosition.location({required int location, int? totalLocations}) = KindleLocation;
  const factory ReadingPosition.finished() = FinishedPosition;
}

@freezed
class UnifiedProgress with _$UnifiedProgress {
  const factory UnifiedProgress({
    required double fraction,          // 0.0–1.0, the canonical work-level value
    required ReadingPosition position, // as entered, in the source edition's units
    required String? editionId,
    required bool isApproximate,       // true when converted across editions or length unknown
    required DateTime updatedAt,
  }) = _UnifiedProgress;
}

@freezed
class ProgressEvent with _$ProgressEvent {
  const factory ProgressEvent({
    required String id,
    required String workId,
    required String readThroughId,
    String? editionId,
    required ReadingPosition position,
    required double fraction,
    required bool isApproximate,
    required ProgressSource source,   // manual | session | import
    String? sessionId,
    required DateTime recordedAt,
  }) = _ProgressEvent;
}

// ───────────── Library ─────────────
enum ReadingStatus { none, wantToRead, reading, read, dnf }

@freezed
class LibraryEntry with _$LibraryEntry {
  const factory LibraryEntry({
    required String workId,
    required ReadingStatus status,
    @Default(false) bool isWishlist,
    @Default(false) bool isFavorite,
    double? rating,                    // 0.5 steps, 0.5–5.0
    String? review,
    String? activeEditionId,
    String? activeReadThroughId,
    UnifiedProgress? progress,
    required DateTime addedAt,
    DateTime? lastActivityAt,
    required WorkSummary work,         // denormalized for list rendering
    @Default(SyncState.synced) SyncState syncState,
  }) = _LibraryEntry;
}

@freezed
class UserEdition with _$UserEdition {
  const factory UserEdition({
    required String editionId,
    required String workId,
    @Default(true) bool owned,
    int? pageCountOverride,
    int? audioDurationOverride,
    int? contentStartPage,             // skip front matter in fraction math
    int? contentEndPage,
    @Default([]) List<CalibrationPoint> calibration, // user-paired anchors for cross-format mapping
  }) = _UserEdition;
}

@freezed
class ReadThrough with _$ReadThrough {
  const factory ReadThrough({
    required String id,
    required String workId,
    required int ordinal,
    required DateTime startedAt,
    DateTime? finishedAt,
    required ReadThroughOutcome outcome, // inProgress | finished | abandoned
  }) = _ReadThrough;
}

// ───────────── Sessions ─────────────
@freezed
class ReadingSession with _$ReadingSession {
  const factory ReadingSession({
    required String id,
    required String workId,
    required String readThroughId,
    String? editionId,
    required DateTime startedAt,
    DateTime? endedAt,
    int? plannedDurationSec,
    required int activeDurationSec,     // derived from timestamps minus pauses
    @Default([]) List<PauseInterval> pauses,
    ReadingPosition? startPosition,
    ReadingPosition? endPosition,
    int? pagesRead,
    required String localDate,          // the user's calendar day at the start
    required SessionCompletion completion,
  }) = _ReadingSession;
}

// ───────────── Notes, goals, profile ─────────────
@freezed class Note with _$Note { /* id, workId, readThroughId?, kind, text, anchor (ReadingPosition?), createdAt, updatedAt */ }

enum GoalMetric { books, pages, minutes }
enum GoalPeriod { year, month, custom }
@freezed class Goal with _$Goal { /* id, metric, period, start, end, target, archived */ }

@freezed class UserProfile with _$UserProfile { /* uid, displayName, photoUrl, email, createdAt */ }
@freezed class UserPreferences with _$UserPreferences { /* theme, defaultStatus, defaultTimerMin, weekStartsOn, analyticsConsent, crashConsent, focusModeEnabled */ }
```

Goal progress, statistics and streaks are **computed** from sessions and events by `StatsEngine` and are never stored, so they can't drift from the underlying data.

## 7. Unified progress and conversion

```dart
abstract interface class ProgressMapper {
  /// Converts a position in [from] edition to a 0–1 fraction of the work.
  MappedFraction toFraction(ReadingPosition p, EditionMetrics from);
  /// Converts a work fraction to a position in [to] edition.
  MappedPosition fromFraction(double fraction, EditionMetrics to);
}
```

Mappers are resolved in this order:

1. **`CalibratedMapper`.** Used when the user has calibration points for both editions (for example "page 100 ≈ 3:12:00"). It interpolates piecewise-linearly between the anchors and is marked approximate only between widely spaced anchors.
2. **`ProportionalMapper`** (the default). It computes `fraction = (page − contentStart) / (contentEnd − contentStart)`, or `seconds / duration`. **Whenever source and target formats differ, the result is marked `isApproximate = true`.**
3. **`UnknownLengthMapper`.** Used when the length is unknown. It accepts only a percentage or a "finished" mark, and shows "page 143 of ?".

Example: page 187 of 400 in the Kindle edition gives a fraction of 0.4675. For the Audible edition (11 h 20 m = 40,800 s) that maps to ≈ 19,074 s, shown as "≈ 5 h 18 m", labelled approximate.

## 8. Firestore security rules (outline)

```
rules_version = '2';
service cloud.firestore {
  match /databases/{db}/documents {
    function signedIn() { return request.auth != null; }
    function isOwner(uid) { return signedIn() && request.auth.uid == uid; }

    match /catalog_works/{id}       { allow read: if signedIn(); allow write: if false; }
    match /catalog_editions/{id}    { allow read: if signedIn(); allow write: if false; }
    match /catalog_authors/{id}     { allow read: if signedIn(); allow write: if false; }
    match /catalog_series/{id}      { allow read: if signedIn(); allow write: if false; }
    match /catalog_isbn/{id}        { allow read: if signedIn(); allow write: if false; }
    match /catalog_providerIndex/{id} { allow read, write: if false; }
    match /catalog_searchCache/{id} { allow read, write: if false; }
    match /ops_rateLimits/{id}      { allow read, write: if false; }

    match /users/{uid} {
      allow read: if isOwner(uid);
      allow create, update: if isOwner(uid) && validProfile(request.resource.data);
      allow delete: if false;                         // only via the deleteAccount function

      match /library/{workId}         { allow read: if isOwner(uid); allow write: if isOwner(uid) && validLibrary(); }
      match /progressEvents/{id}      { allow read, create: if isOwner(uid) && validEvent();
                                        allow update: if isOwner(uid) && onlyTombstone(); allow delete: if false; }
      match /sessions/{id}            { allow read: if isOwner(uid); allow write: if isOwner(uid) && validSession(); }
      match /notes/{id}               { allow read: if isOwner(uid); allow write: if isOwner(uid) && validNote(); }
      match /goals/{id}               { allow read: if isOwner(uid); allow write: if isOwner(uid) && validGoal(); }
      match /readThroughs/{id}        { allow read: if isOwner(uid); allow write: if isOwner(uid) && validReadThrough(); }
      match /userEditions/{id}        { allow read: if isOwner(uid); allow write: if isOwner(uid) && validUserEdition(); }
    }
  }
}
```

The `valid*()` functions enforce field allow-lists, types, enum membership, string length caps (notes ≤ 10k characters, reviews ≤ 20k), numeric ranges (rating 0.5–5, fraction 0–1), and `request.resource.data.updatedAt == request.time`. Every rule is covered by `@firebase/rules-unit-testing` tests in Phase 2 and Phase 8.

## 9. Implementation notes (Phase 4, 2026-11-04)

What the code does where it differs from, or adds to, the design above:

- **Progress events are create-only.** The rules allow no update at all (the design allowed a tombstone update). A mistaken entry is corrected by logging a newer event, because the current progress is the newest event, not the highest fraction (PROJECT_STATUS TD-24). If "undo" is needed later it will be a new tombstone *event*, still append-only.
- **Library removal** is a `removed: true` field on the LWW entry. Read-throughs and events stay, so re-adding continues the history (TD-25).
- **Library entries denormalize a book summary** (`title`, `subtitle`, `authorNames`, `coverUrl`, `pageCount`, series fields, `genres`, `firstPublishedYear`) so Home and Library render offline without the catalog.
- **Collection pull:** `where updatedAt >= cursor orderBy updatedAt`. The cursor is the newest server `updatedAt` applied, stored per collection in `sync_meta` (`cursor:<path>`). Re-applying a document at the cursor is idempotent. No composite index is needed (single field).
- **Atomic local batches:** a status change plus its read-through plus a progress event commit in one SQLite transaction and share an outbox `batchId`. They are pushed in order, one op at a time (TD-23).
- **Drift schema v3** adds `progress_events` (index on `work_id, recorded_at`).
- **Sessions (Phase 5)** are create-only like progress events: `users/{uid}/sessions/{id}` with `workId, readThroughId, editionId?, startedAt, endedAt, plannedDurationSec, activeDurationSec, pauses[{start,end}], startPosition?, endPosition?, startFraction?, endFraction?, pagesRead?, localDate, tzOffsetMin, completion (completed | endedEarly | recovered), clockAdjusted, updatedAt`. The design's `hlc` and `deleted` fields are not used yet; deleting or editing a saved session is Phase 6 (it will be a new tombstone record, keeping the log append-only). Locally they live in `sessions` (schema v4) with the full document in `dataJson`.
- **`active_sessions`** (schema v4) holds the single live timer (`ActiveSession` JSON: clock with pauses, start position, `recovered`, `dndPreviousFilter`). Saving a session deletes it in the same transaction that inserts the session and its progress event.

## 10. Implementation notes (Phase 6, 2026-11-05)

- **Statistics** are computed by `StatsEngine`; definitions are in its class comment and PROJECT_STATUS TD-34.
- **Notes** use per-field LWW rather than the document LWW in §4, with `textHistory` (clocks of earlier text versions, last 20) and `conflictOf` (TD-35). `users/{uid}/notes/{id}`: `workId, kind, text, page?, createdAt, conflictOf?, textHistory, deleted`. The design's `readThroughId` and `positionJson` anchors aren't used; the anchor is a page.
- **Goals** use per-field LWW: `users/{uid}/goals/{id}`: `metric, period, start, end, target, createdAt, deleted`. The design's `archived` isn't needed: a goal whose end has passed is history.
- **Library** gains `rating` (0.5–5, half steps, or null) and `review` (≤ 20k characters).
- **`users/{uid}/sessionTombstones/{sessionId}`** `{deletedAt, updatedAt}` is create-only; locally `session_tombstones` (schema v5) (TD-36). This replaces the design's `deleted` field on sessions.
- **Read-through `finishedAt`** may be null: finished, date unknown. Such a read counts in no statistic (PROJECT_STATUS TD-38).

## 11. Implementation notes (Phase 7, 2026-11-05)

- **Schema v6:** `import_rows` (`key`, `state` pending/done/unmatched, `title`, `dataJson`, `queuedAt`). Local only and never synced; it lives in the per-user database.
- **Imported ids:** read-throughs `imp_<key>_<i>`, 100 % events `..._e<i>` with source `import`, undated reads `..._u<i>`, in-progress or DNF `..._s`. Kindle notes `kc_<hash>`. All create-if-absent, so reimporting on any device converges.
- **Notes:** optional `location` (0 to 100,000,000), allowed by the rules and kept on conflict copies.
- **Statistics:** imported events count pages like any other dated progress.
