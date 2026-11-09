# Chapter — Project Status

_Last updated: 2026-11-09 (bug-fix round in progress; register in Chronicle doc 15)_

This is Chapter's **central development tracker**. It is governed by the `chapter-phase-guard` skill (`.claude/skills/chapter-phase-guard/SKILL.md`): every phase gets a pre-phase and a post-phase update here, and all changes stay unstaged until you explicitly approve Git publishing. It is mirrored to Chronicle (`DOC-70718024`). The detailed specs live in `docs/` (canonical). There is deliberately no separate `CHAPTER.md`, to avoid duplicate trackers.

## Current state

| | |
|---|---|
| Last phase | **Series page content: merged and deployed** as `8dfa0c4` (PR #8, 2026-11-09). All 8 roadmap phases are complete. |
| Active phase | None. Release is BLOCKED on owner items: docs/07 |
| Git publishing authorization | **NOT GRANTED.** Approval covered PRs #1 to #5, #7 and #8 only. |
| Repository | Public at `MatrimPathak/chapter`. `main` at `8dfa0c4`, four required CI checks. |

---

## A. Product overview

- **Vision:** Chapter, *"Your reading life, in one place."* A calm, private reading companion built around the loop Pick a book → Read → Record a session → Update progress → Resume. Not a social network or a Goodreads clone. Details: [docs/01](docs/01-product-requirements.md), Chronicle 00 (master brief).
- **Core functionality:** discovery and ISBN scanning; library with statuses and flags; Work/Edition model with unified cross-format progress; durable reading timer and sessions; goals, calendar and honest insights; notes, ratings, authors and series; Audible/Kindle (manual) and Spotify (deep-link) integrations; offline-first sync; export and account deletion.
- **Technology stack:** Flutter/Dart, Material 3 with a custom design system, Riverpod, GoRouter, Freezed/json_serializable · Firebase Auth (Google + Apple on iOS), Firestore, Cloud Functions (TypeScript), App Check, Analytics (opt-in), Crashlytics · Drift/SQLite as the local source of truth · Metadata from Hardcover → Open Library → Google Books, called server-side only.
- **Architecture:** feature-first Clean Architecture (presentation → domain ← data). Drift is the source of truth, with a transactional outbox and HLC sync to Firestore. Book providers sit behind a server-side `BookMetadataProvider` abstraction. Details: [docs/02](docs/02-system-architecture.md), [docs/03](docs/03-data-architecture.md), [docs/05](docs/05-security-and-offline.md).

## B. Development roadmap

The approved 8-phase roadmap ([docs/06](docs/06-roadmap.md)) takes precedence over the skill's generic 13-phase list, as the skill allows. The mapping:

| Approved phase | Covers skill phases | Status | Sprint | Epic | Depends on | Acceptance criteria (summary) |
|---|---|---|---|---|---|---|
| 1 Architecture | 1 (planning part) | **COMPLETED** | S0 `SPR-42047023` ✅ | `EPIC-71627278` ✅ | — | 10 deliverables documented, API restrictions identified, user approval ✅ |
| 2 Foundation | 1 (setup), 2 (auth), 12 (sync core), 13 (rules core) | **COMPLETED WITH WARNINGS** | S1 `SPR-23171703` ✅ | `EPIC-44901932` | 1 | Sign in/out on Android (iOS through CI); profile syncs across 2 devices; rules tests and golden tests pass |
| 3 Discovery | 3, 6, 10 (author/series pages) | **COMPLETED WITH WARNINGS** | S2 `SPR-98903782` ✅ | `EPIC-18960125` | 2, `SPIKE-88083021` | Search works with Hardcover disabled; scan-to-add < 10 s; merge fixture tests |
| 4 Library & editions | 4, 5, 7 | **COMPLETED WITH WARNINGS** | S3 `SPR-37736430` ✅ | `EPIC-56567522` | 3 | Lossless offline sync (forced-conflict test); unified progress tests |
| 5 Reading experience | 8 | **COMPLETED WITH WARNINGS** | S4 `SPR-95482499` ✅ | `EPIC-67485420` | 4 | Exact recovery after the app is killed; DND restored on every exit path |
| 6 Goals & insights | 9, 10 (notes, ratings) | **COMPLETED WITH WARNINGS** | S5 `SPR-77033075` ✅ | `EPIC-36313679` | 5 | StatsEngine handles empty, sparse and dense data with no misleading output |
| 7 Integrations | 11 | **COMPLETED WITH WARNINGS** | S6 `SPR-71995979` ✅ | `EPIC-20596928` | 4 | Each integration fails independently (fault-injection tests) |
| 8 Quality & release | 12 (soak), 13 | **COMPLETED WITH WARNINGS** (store acceptance BLOCKED) | S7 `SPR-01414265` ✅ | `EPIC-07850843` | 2–7 | NFR targets met; export and deletion verified; store-ready |

Releases: v0.1.0-alpha `RLS-90193041` (Phases 2–4) · v0.2.0-beta `RLS-56098621` (5–6) · v1.0.0 `RLS-88037731` (7–8). Dates are tentative.

## C. Feature status

Statuses: NOT STARTED · PLANNED · IN PROGRESS · IN REVIEW · COMPLETED · BLOCKED. "Designed" doesn't mean "implemented": modules marked NOT STARTED are design only.

| # | Module | Phase | Status | Notes |
|---|---|---|---|---|
| 1 | Authentication & onboarding | 2 | COMPLETED WITH WARNINGS | Code complete and tested. Verified end to end on the Android emulator with the Auth emulator. Real Google/Apple sign-in BLOCKED on B1. |
| 2 | Book discovery & search | 3 | COMPLETED WITH WARNINGS | Live via Open Library. Hardcover and Google Books are implemented but disabled until secrets exist (W9, W10). |
| 3 | Personal library | 4 | COMPLETED WITH WARNINGS | Add (detail + scanner), statuses, favourite, remove (tombstone), Library tab with shelves, grid/list, sort, favourites filter and search. Author/genre/series filters and progress sort added in Phase 6. Wishlist UI still deferred (W18). |
| 4 | Book & edition management | 4 | COMPLETED WITH WARNINGS | Owned editions, active-edition switch, overrides in the model. Override and calibration editing UI deferred (W18). |
| 5 | ISBN barcode scanning | 3 | COMPLETED WITH WARNINGS | Scan, validation, lookup and confirmation done. Physical-device test pending (W12). "Add to library" (owned by default) and duplicate detection added in Phase 4. |
| 6 | Reading progress | 4 | COMPLETED WITH WARNINGS | Append-only events, ProgressMapper (proportional, calibrated, unknown length), page/percent/time sheet, Mark as read at 100 %, honest finish estimate, Continue Reading on Home. |
| 7 | Reading sessions & focus timer | 5 | COMPLETED WITH WARNINGS | Durable timer, recovery, end alert, editable summary, history, Android DND. Verified on the Android emulator. iOS code is written but has never been compiled (W22). |
| 8 | Reading goals | 6 | COMPLETED | Year, month, custom; books, pages, minutes; history kept; progress computed, never stored. |
| 9 | Reading calendar & insights | 6 | COMPLETED WITH WARNINGS | StatsEngine with thresholds, calendar, bars, rankings, neutral streaks. Unprofiled on large histories (W31). |
| 10 | Author & series management | 3 (pages), 6 (organization) | IN PROGRESS | Author and series pages done (Phase 3). Series entities need Hardcover (W11). Library can filter by author and series (Phase 6). |
| 11 | Personal notes & ratings | 6 | COMPLETED WITH WARNINGS | Notes with page anchors and conflict copies; half-star rating and review. |
| 12 | Audible integration | 7 | COMPLETED WITH WARNINGS | Manual only, because there is no public API: audiobook edition, time progress, listening labels, store link. Goodreads, StoryGraph and Kindle clippings imports are also in this phase; none tested with real export files (W35). |
| 13 | Spotify integration | 7 | COMPLETED WITH WARNINGS | Search links only. Web API (Tier B) not built; it needs your Spotify developer app, a Premium account and secrets. |
| 14 | Offline synchronization | 2 (core) → 8 | COMPLETED WITH WARNINGS | Soak-tested across three simulated devices in Phase 8. Phase 2 core done (outbox, HLC, per-field LWW, SyncEngine, Firestore transaction push). Phase 4 adds collection pull with persisted cursors, atomic multi-document batches and append-only creates. |
| 15 | Profile & settings | 2 (prefs), 8 (export/deletion) | COMPLETED WITH WARNINGS | Export and deletion done in Phase 8. Phase 2 part done: identity, theme, consents, sync status, sign-out. Export and deletion in Phase 8. |

Open blockers and spikes: **B3 store accounts, release key and App Check registration** (yours; docs/07) · Hardcover production permission and token `SPIKE-88083021` (Hardcover stays disabled until resolved) · iOS build pipeline `SPIKE-29567026` · B1 Firebase projects · B2 Android licenses.

## D. Technical decisions

| # | Date | Area | Decision | Ref |
|---|---|---|---|---|
| TD-1 | 2026-11-04 | Metadata / Firebase | Providers implemented in Cloud Functions (TypeScript); Blaze plan accepted; secrets in Secret Manager | docs/02 D1 |
| TD-2 | 2026-11-04 | Auth | Android + iOS for v1; Sign in with Apple on iOS (App Store 4.8) | docs/01 §8 |
| TD-3 | 2026-11-04 | Navigation | Home · Library · **Read** · Search · Profile | docs/02 §6 |
| TD-4 | 2026-11-04 | Offline sync | Drift as the single source of truth; transactional outbox + HLC; Firestore offline persistence disabled | docs/02 D2–D3 |
| TD-5 | 2026-11-04 | Data model | Append-only ProgressEvents and Sessions; ReadThroughs for rereads; per-field LWW for library entries | docs/03 §4 |
| TD-6 | 2026-11-04 | Book/Edition | Work and Edition are separate aggregates; progress belongs to the work as a fraction; cross-format mapping is labelled approximate | docs/02 D5, docs/03 §7 |
| TD-7 | 2026-11-04 | Metadata | Field-level merge with provenance; auto-merge only on hard identifiers; user corrections stay in user space | docs/04 §1, docs/02 D6 |
| TD-8 | 2026-11-04 | Firestore | Flat user subcollections and a split global catalog (changed from the brief's proposal) | docs/03 §2 |
| TD-9 | 2026-11-04 | Integrations | No unofficial Audible or Kindle APIs; Spotify Tier A deep links by default, Tier B Web API behind a flag | docs/04 §2–4 |
| TD-10 | 2026-11-04 | Product | Optional DNF status, half-star ratings, Want to Read as the default status on add | docs/01 §8 |
| TD-12 | 2026-11-04 | State mgmt | `riverpod_generator` dropped (its `analyzer` conflicts with `drift_dev`); providers are hand-written with Riverpod 3.3 | docs/02 §5 |
| TD-13 | 2026-11-04 | Auth | Apple sign-in through `firebase_auth`'s `AppleAuthProvider`; the `sign_in_with_apple` package is not needed | docs/02 §7 |
| TD-14 | 2026-11-04 | Firestore | `users/{uid}` profile fields are flat (not nested `preferences{}`) for per-field LWW and rule allow-listing | docs/03 §2.2 |
| TD-15 | 2026-11-04 | Dev env | `dev` flavor runs against the Firebase Emulator Suite with offline project `demo-chapter`; the emulator-only test sign-in exists only when `USE_EMULATORS` is true | app/README.md |
| TD-16 | 2026-11-04 | Build | Generated code is not committed; CI runs `build_runner`. Kotlin Gradle plugin 2.3.0 (required by firebase_auth 7). Formatter page width 100. | — |
| TD-17 | 2026-11-04 | Firestore | Catalog editions are embedded in `catalog_works` (≤ 50) instead of a `catalog_editions` collection: one read per detail screen, with `catalog_isbn` for lookups | docs/03 §2.1 |
| TD-18 | 2026-11-04 | Metadata | Hardcover and Google Books are enabled only when their secrets are set; Google keyless access is unusable (quota 0) | docs/04 §1.5–1.6 |
| TD-19 | 2026-11-04 | Tooling | Functions ESLint `no-non-null-assertion` off (tsconfig `noUncheckedIndexedAccess` makes `!` the idiomatic narrowing); `explicit_to_json` on for json_serializable | functions/eslint.config.mjs, app/build.yaml |
| TD-20 | 2026-11-04 | Dev env | The demo Firebase API key uses the `AIza…`/39-character format the Android Functions SDK validates; Riverpod auto-retry disabled app-wide (explicit "Try again" instead); Gradle heap 3 GB | firebase_options_dev.dart, bootstrap.dart |
| TD-21 | 2026-11-04 | Scope | "Add to library" and library-level duplicate detection move from Phase 3 to Phase 4, where the library entity exists. Phase 3 does catalog-level dedupe | this file |
| TD-23 | 2026-11-04 | Sync | A multi-document change commits locally in one SQLite transaction with a shared outbox `batchId`, but rows are pushed one by one, in order (not as one Firestore WriteBatch). Every op is idempotent (LWW merge or create-if-absent), so a partial push is safe and completes on retry | lww_store.dart, sync_engine.dart |
| TD-24 | 2026-11-04 | Progress | Current progress is the *newest* event (recordedAt, ties broken by UUIDv7 id), not the highest fraction, so a reader can move backwards. Events are never edited | progress_event.dart |
| TD-25 | 2026-11-04 | Library | Entries are keyed by work id and denormalize a book summary (offline Home/Library). Removal is a `removed` tombstone; read-throughs and events are kept, and a re-add continues the history | library_models.dart |
| TD-26 | 2026-11-04 | Status rules | Reading opens a read-through (or resumes an open one); Read/DNF close it; pausing (to Want to Read) keeps it open; Read without tracking records a finished read-through without a start date; finishing a tracked read appends a 100 % event; logging progress implies Reading | lww_library_repository.dart |
| TD-27 | 2026-11-04 | State | User-scoped stream providers watch only the uid and *read* the repository; shelf joins happen in widgets, not in derived providers. Avoids Riverpod's "markNeedsBuild during build" assertion on sign-out | library_providers.dart |
| TD-28 | 2026-11-05 | Focus | Android DND uses `setInterruptionFilter` on every API level, not a hand-built `AutomaticZenRule`. Confirmed on API 36: the system creates a visible rule, "Do Not Disturb (Chapter Dev)". Previous filter stored with the live session and cleared once restored | docs/04 §5, FocusModeChannel.kt |
| TD-29 | 2026-11-05 | Notifications | End alert scheduled for an absolute UTC instant; exact only when the system already allows it, otherwise inexact (Play restricts the exact-alarm permission). Recorded time never depends on it. Ongoing notification carries `timeoutAfter` so it clears itself if the process dies | local_session_notifications.dart |
| TD-30 | 2026-11-05 | Sessions | Live session lives in one `active_sessions` row, written before any side effect. Ended sessions wait in that row for the summary; saving deletes it in the same transaction as the session and progress event. Saved sessions are create-only | session_service.dart |
| TD-31 | 2026-11-05 | Exit order | Exit path restores DND first, then clears the stored filter, then touches notifications. Notification failures are ignored, so they can't block DND or saving | session_service.dart |
| TD-32 | 2026-11-05 | Dependencies | `wakelock_plus` conflicts with `connectivity_plus` (SDK constraint), so screen wake goes through our own `chapter/focus` channel | channel_focus_mode.dart |
| TD-33 | 2026-11-05 | Focus | DND is also restored natively by `FocusRestoreReceiver` (alarm at the planned end, re-armed after reboot), so it needs no running app. Chapter only undoes DND it turned on itself, and only while that DND is still in place; DND the reader had on, or changed since, is left alone. A paused session holds DND for at most its remaining time + 1 hour; resuming turns it back on | FocusRestore.kt, session_service.dart |
| TD-34 | 2026-11-05 | Stats | `StatsEngine` is pure and computed on demand from read-throughs, sessions and progress events. Pages = forward movement in the progress log per read-through (high-water mark), so re-reading isn't double counted and a reread counts again. Each risky statistic returns null below its threshold (constants in stats_engine.dart). Sessions bucket by stored local date; events by the device's current zone | stats_engine.dart |
| TD-35 | 2026-11-05 | Notes | Per-field LWW plus a text history of clocks. If an incoming edit doesn't descend from this device's text, the local text becomes a conflict copy whose id derives from the losing clock, so devices converge on one copy. A history over 20 edits can only cause an extra copy, never lost text | lww_notes_repository.dart |
| TD-36 | 2026-11-05 | Sessions | A deleted session is a create-only tombstone in its own table and collection, so it wins whichever arrives first. Its progress event stays, because the book really is at that page, but it is excluded from statistics | lww_library_repository.dart |
| TD-37 | 2026-11-05 | Charts | Bars are drawn with plain widgets and tokens rather than `fl_chart` (docs/02), avoiding another dependency conflict; the charts needed are simple | insights_screen.dart |
| TD-38 | 2026-11-05 | Finish dates | Finishing a tracked book means now. Otherwise the app asks: today, a date (no future dates; stored as local midday) or "I don't remember" (Read shelf only, counts nowhere). A dated untracked read also gets a 100 % event on that date, so books and pages goals agree. Dates can be corrected on the book page | library_sheets.dart, lww_library_repository.dart |
| TD-39 | 2026-11-05 | Import | Imports go through a persistent `import_rows` queue, not a blocking loop: the server allows 30 ISBN lookups a minute. Single-flight runner, concurrency 3, one-minute pause on rate limits, five minutes on other failures, and every failure contained. The queue lives in the per-user database, so sign-out can't leak it to another account | import_queue.dart, import_runner.dart |
| TD-40 | 2026-11-05 | Import | Matching is strict: ISBN, then exact normalised title with a shared author. A missed book is listed; a wrong one would corrupt history. Existing entries are never overwritten, only an empty rating or review is filled, and a removed book stays removed | import_runner.dart, lww_library_repository.dart |
| TD-41 | 2026-11-05 | Import | Imported read-throughs, events and notes use ids derived from the file's content (`imp_<key>_…`, `kc_<hash>`) and create-if-absent writes, so reimporting, on any device, can't duplicate or restore deleted notes | lww_library_repository.dart, clippings_importer.dart |
| TD-42 | 2026-11-05 | Integrations | The status provider is the failure boundary: anything thrown or emitted as an error becomes `unavailable` on that card. Platform plugins sit behind `LinkOpener` and `TextFilePicker` so failures can be injected in tests | integrations_providers.dart, platform_ports.dart |
| TD-43 | 2026-11-05 | Spotify | Tier A uses public search links, not curated playlists, until real playlists are chosen. Tier B isn't in the app at all | integration.dart |
| TD-44 | 2026-11-05 | Import | Failed lookups retry after 30 s, doubling to the 5-minute limit, and success resets it. On the emulator a slow first run left books waiting the full 5 minutes although the server had finished | import_runner.dart |
| TD-45 | 2026-11-05 | Library | Adding a removed book as Read restores its finished read when none is in progress, instead of recording a new one and asking for a date. Adding it as Reading still starts a reread | lww_library_repository.dart |
| TD-46 | 2026-11-05 | Sync | Remote clocks are always adopted, however far ahead (was: refuse beyond an hour). A later local edit must beat what it saw, and refusal stalled sync. Clocks may run ahead of real time, which only affects ordering. A wrong-clock device that edits while others are offline can still win that field, as last-writer-wins allows. One failing document no longer blocks its batch; the cursor stays back so it's redelivered next launch | hlc.dart, sync_engine.dart |
| TD-47 | 2026-11-05 | Privacy | Crash reports send the error's type and stack, never its message. Harder debugging, accepted, to keep the consent screen's promise | crash_scrubber.dart |
| TD-48 | 2026-11-05 | Account | The server enforces a sign-in within 5 minutes for deletion; the client only reacts. Order: revoke tokens, delete data, delete Auth user last, so any failure can be retried | deleteAccount.ts |
| TD-49 | 2026-11-05 | Backup | Android cloud backup and device transfer are off. The server holds the synced copy, and a restore could bring back deleted accounts. Unsynced changes don't survive a phone change | AndroidManifest.xml |
| TD-52 | 2026-11-06 | Toolchain | Flutter 3.47.9, Dart 3.13. Needed for `google_sign_in_ios` 6.4.0, whose GoogleSignIn 10 resolves the shared-library conflict with Firebase 13 under Swift Package Manager | pubspec.yaml, ci.yml |
| TD-22 | 2026-11-04 | Metadata | Open Library author works come from search sorted by editions; bios and descriptions are cleaned of HTML and Markdown; page count falls back to a print edition | docs/04 §1.5 |
| TD-11 | 2026-11-04 | Process | Tracked in Flowboard/Chronicle; `docs/` canonical; lifecycle governed by `chapter-phase-guard`; no Git staging or publishing without explicit approval | this file |

## Phase 8 plan (pre-phase record) — Quality & Release

**Started:** 2026-11-05 · **Sprint:** S7 `SPR-01414265` · **Epic:** `EPIC-07850843` · **Stories:** Export and deletion `US-04422663`, Release hardening `US-80940502`

**Git check before starting:** branch `main`, no commits, nothing staged; Phase 1–7 work untracked. Publishing NOT GRANTED.

**Objectives:** let readers take their data and leave for good; find what breaks under load, offline time and assistive settings; get everything into the repo that a store release needs, and list exactly what only you can do.

**Scope (in):**
1. **Export:** complete JSON and readable CSV files, built locally from Drift and handed to the share sheet. Works offline. No reauthentication, because the export carries no account email.
2. **Account deletion:**
   - `deleteAccount` callable: requires a sign-in within the last 5 minutes, deletes `users/{uid}` recursively, revokes tokens and deletes the Auth user. Safe to retry.
   - App: typed `DELETE`, reauthentication, sync stopped first, session and Do Not Disturb cleaned up, local database wiped. Needs a connection, and says so.
3. **Offline soak:** a randomized multi-device test with a flaky network, which must converge and lose nothing.
4. **Full rules audit:** every collection, allowed and denied, recorded in a table.
5. **Performance:** measure with 2,000 books (library queries, statistics, progress save, list scrolling); fix what misses. Cold start measured on the emulator as a rough figure only.
6. **Accessibility:** automated tap-target, label and contrast checks on the main screens in both themes; 200 % text with no overflow; fix what fails.
7. **Telemetry and security audit:** prove no content reaches analytics or crash reports; scan for secrets; dependency audit; check emulator-only code can't ship.
8. **Release readiness:** real app icon and splash in place of Flutter's, Android release signing from an uncommitted key file, R8, a prod build that compiles or a precise list of why not, privacy policy draft and in-app screen, licences, store listing drafts, Data safety answers, a release runbook.
9. **Carry-overs:** W25 (wrong year in search), W34 (calendar opens on December), W31 if measurement shows a problem.

**Scope (out):**
- Wishlist UI and edition override and calibration UI (W18): I recommend v1.1, since none blocks release.
- Instrumenting success metrics: Analytics has no events today, so nothing is sent even with consent. Adding events is a product decision.
- Background import (W36) and Spotify Tier B.

**Only you can do these, so they stay BLOCKED (B1, B2, new B3):**
- Real Firebase projects, Blaze billing, deployed functions and rules, Secret Manager values (B1).
- Play Console and Apple Developer accounts, release keystore, App Check registration, submission (B3).
- Legal review and hosting of the privacy policy, and the contact email in it.
- Real-device checks: cold start on a Pixel 6a class phone, TalkBack and VoiceOver by a person, iOS through CI (`SPIKE-29567026`), crash-free rate (needs real users).

**Acceptance criteria:**
- AC1: Format, analyze and all tests green (app and functions); rules suite green.
- AC2: Export works offline and contains every user collection, with a test that fails if a new collection is left out. CSV escapes correctly.
- AC3: Emulator test: no user documents and no Auth user remain after deletion; deleting twice is safe; another user's data untouched; stale sign-in, no sign-in rejected.
- AC4: After deletion on the device: signed out, local database file gone, no session or DND left behind.
- AC5: Soak converges with no lost events across hundreds of randomized steps and several seeds.
- AC6: Rules audit table complete, with a test for each allowed and denied case.
- AC7: Measured 2,000-book figures recorded. Local progress save < 50 ms in the test environment.
- AC8: Accessibility checks pass on the main screens in light and dark; no overflow at 200 % text.
- AC9: No content in telemetry, shown by inspection and a test; no secrets in the repo.
- AC10: Release build compiles with the config in the repo, or each missing input is named.
- AC11: Manual on the Android emulator: export while offline, delete an account end to end.

**Risks:**
- **A second device can bring data back.** Its token stays valid up to an hour, so it could write again after deletion. Revoking tokens doesn't stop an already issued one. Will be measured against the cost of a rule check on every write.
- **Emulator numbers aren't phone numbers.** NFR targets for cold start and crash-free rate can't be claimed from here, and I won't claim them.
- **The privacy policy is a draft by an AI, not legal advice.** It needs your review before publishing.
- Machine has 8 GB; long builds and emulators run one at a time.

**Blockers:** B1, B2, new B3 (store accounts and signing), `SPIKE-88083021`, `SPIKE-29567026`. They block release, not this phase's code.

## Phase 7 plan (pre-phase record) — Integrations

**Started:** 2026-11-05 · **Sprint:** S6 `SPR-71995979` · **Epic:** `EPIC-20596928` · **Stories:** Audible and Kindle `US-28320381`, CSV import `US-14073275`, Spotify `US-88150897`

**Git check before starting:** branch `main`, no commits, nothing staged; Phase 1–6 work untracked. Publishing NOT GRANTED.

**Objectives:** bring your reading history with you and connect to other services, only in ways those services actually allow, with each integration able to fail without touching anything else.

**Scope (in):**
1. **Framework:** an `Integration` interface (declared capabilities, status) and Profile → Connected services, one card each. A failure shows only on its own card.
2. **Goodreads and StoryGraph CSV import**, parsed on the device:
   - Preview before anything changes.
   - A persistent queue resolves each book through the catalog (ISBN, then a strict title-and-author match) and adds it. The server allows 30 ISBN lookups a minute and a first lookup can take about 7 s, so a large import runs in the background, survives restarts and shows progress.
   - Shelves, ratings, reviews, read dates and owned copies are mapped. Books already in the library are never overwritten; only an empty rating or review is filled.
   - Rows that can't be matched are listed, not dropped. Reimporting creates no duplicates.
   - Imported dated reads count in statistics on their own dates, like any other dated read (TD-38).
3. **Kindle `My Clippings.txt`:** parsed on the device into quotes and notes with page and location, matched to books in the library. Unmatched books are listed. Reimporting creates no duplicates and doesn't bring back deleted or overwrite edited notes.
4. **Audible (manual):** add an audiobook edition with its duration, h:mm:ss progress, sessions labelled as listening, an open-Audible link, and plain copy that automatic sync isn't possible.
5. **Spotify Tier A:** "Music for reading" links on the Read tab. They open Spotify's own search through `url_launcher`, with no account or API. If they fail, only that card is affected.

**Scope (out):**
- **Spotify Tier B** (Web API, OAuth, currently playing): not built. It needs a Spotify developer app, a Premium owner account and server-side secrets from you, and Development Mode allows only 5 users. Nothing for it ships in the app.
- **Curated Spotify playlists:** search links instead, because I won't invent playlist IDs. Real curated URLs can replace them when you choose some.
- **Unofficial Audible or Kindle APIs:** never.
- Kindle location entry in the progress sheet; automatic Kindle or Audible sync (impossible); exporting (Phase 8).

**Acceptance criteria:**
- AC1: Format, analyze and all tests green (app and functions).
- AC2: CSV and clippings parsers tested on quoting, BOM, CRLF, `="..."` ISBNs, bad dates, missing columns and malformed files, including randomized input that must never throw.
- AC3: A 1,000-row import completes through the queue with fakes, survives a restart mid-way, and pauses and resumes on rate limits and network failure.
- AC4: Reimporting (CSV and clippings) creates no duplicates, including on a second simulated device.
- AC5: Unmatched rows are reported, never silently dropped. Existing library data is never overwritten.
- AC6: Fault injection: each integration failing leaves other cards, Home and Library working.
- AC7: Rules tests for the new note `location` field; migration test v5 → v6.
- AC8: Manual on the Android emulator: import a CSV and a clippings file, add an audiobook edition and log time, open the Spotify and Audible links.
- AC9: No private API or scraping anywhere; copy never claims automatic sync.

**Dependencies:** Phase 3 catalog, Phase 4 library, Phase 6 notes and statistics; `url_launcher` and `file_picker` (new, resolved without conflicts).

**Risks:**
- **Real export formats:** no real Goodreads, StoryGraph or device `My Clippings.txt` file is available here, so fixtures are written from public descriptions of the formats. Parsers match by header name and report what they can't read. Please try your own files.
- **Metadata quality:** many rows may not match because Hardcover and Google Books are disabled (W9, W10) and Open Library data varies. Matching is strict on purpose: a missed book is listed, a wrong book would corrupt your history.
- **Time:** large imports take a while (at best about 34 minutes per 1,000 rows at the current limit).
- iOS can't be built here (`SPIKE-29567026`); `file_picker` and `url_launcher` are untested on iOS.

**Existing blockers:** B1, B2, `SPIKE-88083021`, `SPIKE-29567026`. None block Phase 7 on Android.

## Phase 6 plan (pre-phase record) — Goals & Insights

**Started:** 2026-11-05 · **Sprint:** S5 `SPR-77033075` · **Epic:** `EPIC-36313679` · **Stories:** goals `US-98201131`, insights `US-92210602`, notes and ratings `US-22523306`, carry-overs `US-06658059`

**Git check before starting:** branch `main`, no commits, nothing staged; Phase 1–5 work untracked. Publishing NOT GRANTED.

**Objectives:** show readers what they've read without pressure or misleading numbers, and let them keep their thoughts on a book.

**Scope (in):**
1. **StatsEngine (pure domain):** computed from read-throughs, sessions and progress events, never stored. Books finished, pages, hours, average session, pages per hour, books per month, monthly trend, yearly summary, top authors and genres, streaks (current and longest), weekday activity, per-day heatmap data.
   - Every statistic has a minimum-data threshold and returns "not enough data" below it; never NaN or Infinity.
   - Pages come from forward movement in the progress log (sessions write events, so nothing is counted twice). Audio positions don't count as pages. Unknown-length books contribute no pages.
   - Sessions bucket by their stored local date, so a later time-zone change doesn't move them.
2. **Goals:** metric (books, pages, minutes), period (year, month, custom). Create, edit, delete; ended goals stay as history. Progress is computed, never stored. Shown gently on Home and in a Goals screen, with no streak-loss or "behind" language.
3. **Insights screen:** yearly summary, calendar heatmap, monthly trend, weekday activity, top authors and genres, streaks shown neutrally. Charts drawn with design tokens (replacing `fl_chart` from docs/02 unless it proves necessary, to avoid another dependency conflict).
4. **Notes:** note, quote or observation, with optional page anchor. Add, edit, delete offline on the book page. Concurrent edits on two devices keep both texts: the older one becomes a conflict-copy note. Copy ids are deterministic so devices can't create duplicates.
5. **Ratings and reviews:** half-star rating 0.5–5 and an optional review, on the book page. Validated in the client and the rules.
6. **Carry-overs:** library filters by author, genre and series; sort by progress; pages remaining; delete a saved session (append-only tombstone, excluded from statistics); Read and Update progress on the Continue Reading card.
7. **Sync and rules:** `goals`, `notes` (per-field LWW with tombstones), `sessionTombstones` (create-only), rating and review on `library`; schema-checked rules with tests. Drift schema v5.

**Scope (out):** editing a saved session's numbers (delete and re-log instead); notes search or an all-notes screen; series organization beyond Phase 3 pages (`SPIKE-88083021`); calibration, edition override and wishlist UI (W18, remaining); server-side anything; exports (Phase 8).

**Acceptance criteria:**
- AC1: Format, analyze and all tests green (app and functions).
- AC2: StatsEngine tests cover empty, sparse and dense data, including randomized input: no NaN, Infinity or negative values, and nothing shown below its threshold.
- AC3: Day bucketing tested across midnight and time-zone offsets; DST-safe streaks.
- AC4: Goal progress matches the underlying sessions and events (tests), works offline, and edits keep history.
- AC5: Two devices editing one note offline: both texts survive, devices converge, no duplicate copies (tests).
- AC6: Rating validated in the client and rules; rules tests for all new collections (owner-only, schema-checked, tombstones create-only).
- AC7: A deleted session disappears from lists and statistics on both devices, regardless of sync order.
- AC8: Migration test v4 → v5.
- AC9: Manual end to end on the Android emulator: goal, sessions, Insights, note, rating, filters.

**Dependencies:** Phases 4–5 data (read-throughs, progress events, sessions).

**Risks:**
- Misleading statistics are the main product risk. Mitigated by thresholds, plain definitions and randomized tests.
- The note conflict logic is new sync behaviour; detection relies on each edit recording which version it was based on.
- Recomputing statistics on large histories can be slow; memoized per input, not profiled here.
- 8 GB machine: emulator instability (W20, W23).

**Existing blockers:** B1, B2, `SPIKE-88083021`, `SPIKE-29567026`. None block Phase 6 on Android.

## Phase 5 plan (pre-phase record) — Reading Experience

**Started:** 2026-11-04 · **Sprint:** S4 `SPR-95482499` · **Epic:** `EPIC-67485420` · **Stories:** timer `US-40867577`, summary and history `US-45232030`, focus mode `US-10916362`

**Git check before starting:** branch `main`, no commits, nothing staged; Phase 1–4 work untracked. Publishing NOT GRANTED.

**Objectives:** the core loop *Pick a book → Read → Record a session → Update progress*. A timer that can't lose time (killing the app, rebooting the phone or moving the clock doesn't corrupt it), a summary you can edit before saving, and an optional focus mode that always gives your Do Not Disturb setting back.

**Scope (in):**
1. **Session clock (domain, pure):** elapsed time = time running minus pauses, from timestamps only; a ticker only repaints. Clock moved backwards → elapsed is clamped and the session is flagged in the summary.
2. **Active session durability:** a singleton `active_session` Drift row written on every transition (start, pause, resume, end). On launch:
   - before the planned end → resume the timer screen;
   - past the planned end → the session ends *at* the planned end (`completion = recovered`) and the summary opens;
   - an ended-but-unsaved session (killed during the summary) → the summary reopens.
3. **Timer UI:** Read tab (pick a book you're reading, presets 15/20/30/45/60/90/120 min or custom, recent sessions); full-screen timer (remaining, elapsed, current progress, pause/resume/end); active session bar above the nav bar; "Read" on Continue Reading starts the timer with your last duration.
4. **End notification:** scheduled at the planned end with `flutter_local_notifications`, rescheduled on pause/resume, cancelled on end; plus an ongoing notification while a session runs. Android 13+ notification permission is asked when you start your first session.
5. **Summary:** time read, pages read, pages per hour, old → new progress, editable minutes and end position; Save writes the session, a progress event (`source: session`) and the status change in **one** local transaction / outbox batch; Discard leaves nothing behind.
6. **Sessions sync:** `users/{uid}/sessions/{id}`, append-only (create-if-absent, like progress events); Firestore rules with schema checks and rules tests; pulled into a local `sessions` table.
7. **History:** recent sessions on the Read tab and per book on the book page.
8. **Focus mode:**
   - Android: Kotlin `FocusModeChannel`. Explanation screen first, Notification Policy Access only after you tap, previous interruption filter stored and restored on end, cancel, crash recovery and permission denial. Off by default; a Profile switch.
   - iOS: in-app focus screen (screen kept awake, nav hidden) and a short guide to setting up a Reading Focus. No copy claims Chapter controls DND.

**Scope (out):** reading statistics, streaks and goals (Phase 6); editing or deleting saved sessions (Phase 6, with tombstones); a stopwatch mode with no planned duration; iOS Focus Filter (v2).

**Acceptance criteria:**
- AC1: Format, analyze and all tests green (app and functions).
- AC2: Session clock unit tests: exact elapsed over 2 h with pauses (fake clock, ±1 s), backwards clock clamped and flagged.
- AC3: Recovery: a new app instance over the same database resumes a running session with the correct elapsed time, ends an overdue one at its planned end as `recovered`, and reopens an unsaved summary (tests) — plus a manual kill-and-relaunch on the emulator.
- AC4: Summary save is atomic (session + progress event + status in one batch); edited values persist; Discard writes nothing.
- AC5: Rules tests: sessions owner-only, schema-checked, create-only.
- AC6: Focus mode: the previous DND state is restored on end, cancel, recovery and denied permission (Dart tests with a fake channel; manual Android emulator check of the Kotlin side). Never changed without consent.
- AC7: The end notification is scheduled at the planned end, moved on pause/resume and cancelled on end (tests with a fake notifier) and fires on the emulator.
- AC8: Manual end to end on the Android emulator: start a session, kill the app, relaunch → recovered; finish → summary → save → progress and history updated.

**Dependencies:** Phase 4 library/progress and the batch outbox; `flutter_local_notifications` + `timezone`, `wakelock_plus` (new packages).

**Risks:**
- Exact alarms: Google Play restricts `SCHEDULE_EXACT_ALARM`/`USE_EXACT_ALARM` for non-alarm apps. Plan: exact scheduling only when the system already allows it, otherwise inexact (the notification may be a little late; *the recorded time is still exact* because it comes from timestamps).
- Android 15 changed DND for apps: `setInterruptionFilter` now creates an implicit system rule. Plan: use `setInterruptionFilter` on all versions (the system shows it as a Chapter rule on 15+), instead of building our own `AutomaticZenRule` with a condition provider. Recorded as a deviation from docs/04 §5 if it holds.
- The Kotlin channel and notifications can't be unit-tested; they're covered by fakes in Dart plus manual emulator checks. iOS can't be built here (`SPIKE-29567026`).
- Emulator instability on this 8 GB machine (W20).

**Existing blockers:** B1 (real Firebase), B2 (Android licenses), `SPIKE-29567026` (iOS CI). None block Phase 5 on Android.

## Phase 4 plan (pre-phase record) — Library, Editions & Progress

**Started:** 2026-11-04 · **Sprint:** S3 `SPR-37736430` · **Epic:** `EPIC-56567522`

**Objectives:** a personal library you can add to from anywhere, honest progress tracking across editions and formats, and Continue Reading on Home. Everything works offline and syncs without losing a progress update.

**Scope (in):**
1. **Sync engine:**
   - User *collections* with cursor-based pull (`updatedAt > cursor`).
   - Per-field LWW documents for `library`, `readThroughs` and `userEditions`.
   - Append-only `progressEvents` (create-if-absent; never updated or deleted by clients).
   - Firestore rules with schema checks for all four collections, plus rules tests.
2. **Library:**
   - Statuses: Want to Read, Reading, Read, Did Not Finish; Wishlist and Favorite flags.
   - Add from book detail and from the scanner (default Want to Read, TD-10).
   - Duplicate detection: already in the library → show the status and offer "I own this edition".
   - Remove from the library.
3. **Library tab:** status tabs, grid/list toggle, sort (title, author, date added, progress, recently read), filters (author, genre, series), in-library search.
4. **Editions:**
   - Owned editions (`userEditions`) and switching the active (reading) edition.
   - Per-user overrides of page count and audio duration (never written to the catalog, D6).
5. **Read-throughs:** starting Reading opens one; Read or DNF closes it; "Read again" opens a new one, and earlier history is kept.
6. **Progress:**
   - Append-only `ProgressEvent` log; progress sheet by page, percent, slider, or audio time for audiobooks.
   - `ProgressMapper`: proportional, calibrated and unknown-length.
   - Approximate label whenever formats differ.
   - Offer "Mark as read" at 100 %; pages remaining.
   - Estimated completion date only with enough history (≥ 3 reading days in the last 30).
7. **Home:** Continue Reading carousel ordered by latest activity, with "Update progress".

**Scope (out):** reading timer and sessions (Phase 5); ratings, reviews and notes (Phase 6); calibration-point editing UI (the mapper supports it; UI later); the offline pending-ISBN-lookups queue (stays deferred — it needs a background resolver; tracked as a known limitation).

**Acceptance criteria:**
- AC1: Format, analyze and all tests are green (app and functions).
- AC2: Forced-conflict sync test: two devices edit the same book offline (status on one, progress on the other, same field on both), and they converge with zero lost progress events.
- AC3: Unified progress across formats is correct in unit tests (e.g. Kindle p.187/400 → 46.75 % → about 5 h 18 m of an 11 h 20 m audiobook), and is labelled approximate.
- AC4: Rules tests: owner-only, schema-checked, events immutable.
- AC5: Adding the same work twice (search or scan) never creates two library entries.
- AC6: Rereading keeps the previous read-through and its progress events.
- AC7: Continue Reading is ordered by latest activity (widget test).
- AC8: Library sort, filter and search work (unit and widget tests); a 2k-book list scrolls smoothly (build-time check only — no profiler on this machine; see risks).
- AC9: Manual end to end on the Android emulator: add a book, update progress, see it on Home and in Library.

**Dependencies:** Phase 2 sync engine; Phase 3 catalog (`CatalogWork`, editions).

**Risks:** the sync engine's collection pull is the most data-critical code so far (mitigated by tests with two simulated devices); the estimated-completion statistic must not mislead (threshold plus "approximately"); performance with 2k entries can't be profiled here.

**Existing blockers:** B1 (real Firebase), B2 (Android licenses), `SPIKE-88083021` (Hardcover; doesn't block Phase 4).

## Phase 3 plan (pre-phase record) — Discovery

**Started:** 2026-11-04 · **Sprint:** S2 `SPR-98903782` · **Epic:** `EPIC-18960125`

**Objectives:** find any book reliably, regardless of which metadata provider is up. Show normalized book, author and series details. Look up a book by scanning its ISBN barcode.

**Scope (in):**
1. Server (Cloud Functions, TypeScript): the `BookMetadataProvider` interface and the Hardcover (GraphQL), Open Library and Google Books providers with mappers; the orchestrator (fallback chain, per-provider timeout, circuit breaker, Hardcover budget); field-level merge with provenance; identity/dedupe on hard identifiers only (ISBN, provider id); catalog persistence (`catalog_works/editions/authors/series/isbn/providerIndex`) in transactions; 24 h search cache; per-user rate limit; callables `catalogSearch`, `catalogLookupIsbn`, `catalogGetWork`, `catalogGetAuthor`, `catalogGetSeries`, `catalogTrending`; input validation with zod; App Check enforced in production only.
2. App: `CatalogRepository` (domain) with a callable data source and a Drift cache (catalog tables, search cache, recent searches); Search tab (debounce, suggestions from recents, pagination, loading/empty/error/offline states, Open Library trending); Book detail; Author screen; Series screen (by position, primary vs. novellas); ISBN scanner (camera permission, ISBN-10/13 detection, checksum validation, lookup, confirmation sheet).
3. Shared: ISBN validation and normalization in both Dart and TypeScript, with tests.

**Scope (out, moved with reasons):**
- **"Add to library" and duplicate detection against *your library* move to Phase 4.** The library entity doesn't exist until then. Phase 3 does catalog-level dedupe (the same ISBN or provider id resolves to the same work), and the confirmation sheet shows the book with the add action disabled and labelled as coming next.
- Editions browser UI beyond listing editions on the detail screen (Phase 4, with the active-edition switch).

**Acceptance criteria:**
- AC1: Format, analyze and all tests are green (app and functions).
- AC2: Each provider's mapper is tested against recorded fixtures. Open Library and Google Books fixtures are recorded from the live public APIs. Hardcover fixtures are built from its documented schema, because there's no token yet (`SPIKE-88083021`).
- AC3: Fault-injection tests show search still works with Hardcover (or any single provider) down or timing out, and the circuit breaker opens after 5 failures.
- AC4: Merge tests: series comes from Hardcover and page count from the ISBN-matched edition; provenance is recorded; user-space data is never written; fuzzy title matches never auto-merge.
- AC5: ISBN-10/13 checksum and 10→13 conversion tests pass in Dart and TypeScript.
- AC6: Callables reject unauthenticated callers and invalid input, and enforce per-user rate limits (tests). Catalog rules still deny client writes.
- AC7: App widget tests cover search (debounce, pagination, empty/error/offline), the detail/author/series screens, and the scanner confirmation flow against fakes.
- AC8: Manual end to end on the Android emulator: search a real title through the Functions emulator (live Open Library) → open the detail screen.
- AC9: Scanning a physical book to its detail in under 10 s. **Expected to stay unverified** in this environment (the Android emulator camera can't read a real barcode); needs a device test.

**Dependencies:** Phase 2 foundation; Functions emulator; network access to Open Library and Google Books (public, read-only); new packages: `zod` (functions), `cloud_functions` and `mobile_scanner` (app).

**Risks:**
- Hardcover's schema changes or access is denied (beta API, no token yet). Mitigated: the provider is disabled when no secret is set, and the fallback chain covers it.
- Google Books keyless quota is low. A key can be added later as a secret.
- Provider data quality (series, page counts).
- `mobile_scanner` native build issues on Windows.

**Existing blockers:**
- `SPIKE-88083021`: no Hardcover token or permission, so Hardcover can't be verified live.
- B1: real Firebase projects (the dev flavor uses emulators).

## Phase 2 plan (pre-phase record) — Foundation

**Objectives:** a runnable, tested app skeleton that every later phase builds on: the project structure, design system, authentication, navigation shell, local database and sync engine core, security rules, functions scaffold, and CI.

**Scope (in):**
1. Monorepo: `app/` (Flutter), `functions/` (TypeScript), `firebase/` (rules, indexes), `firebase.json`, `.gitignore`, CI workflow.
2. Flutter app with `dev` and `prod` entry points and flavor config, strict lints, codegen (Freezed, json_serializable, Riverpod generator, Drift), l10n scaffold.
3. Core: `Result`/`Failure`, `Clock`, UUIDv7 IDs, hybrid logical clock (HLC), logger.
4. Design system: tokens (color, type, spacing, radius, elevation, motion), light and dark themes, core components (button, text field, book cover, book cards, progress bar/ring, nav bar, sheet, dialog, empty/error/loading states, rating stars, sync and approximate badges).
5. Auth: domain interface, Firebase implementation (Google via `google_sign_in` v7, Apple on iOS), auth state, sign-out, profile bootstrap.
6. Router: GoRouter with redirect guard (splash, sign-in, onboarding) and a 5-tab `StatefulShellRoute` (Home · Library · Read · Search · Profile) with proper empty-state screens.
7. Drift: per-uid database, profile/preferences tables, outbox, sync_state, migrations harness.
8. SyncEngine core: transactional outbox, push (batched), pull (cursor), per-field LWW `ConflictPolicy`, sync status. First synced entity: profile and preferences.
9. Firestore rules (users/profile + catalog read-only, user collections deny-by-default until their phase) with emulator-based rules tests.
10. Functions project skeleton (TypeScript, lint, test runner). There are no deployed functions yet.

**Scope (out):** catalog and providers (Phase 3), library, progress and sessions entities (Phases 4–5), account deletion and export (Phase 8), real store signing.

**Acceptance criteria:**
- AC1: `flutter analyze` is clean; `dart format` makes no changes; all unit and widget tests pass.
- AC2: Domain is unit-tested: HLC ordering, Result, conflict policy, outbox atomicity.
- AC3: Design-system components render in light and dark themes and at 2× text scale (widget tests).
- AC4: The router guard sends signed-out users to sign-in and keeps tab state (widget tests).
- AC5: A preference change made offline is queued in the outbox and pushed when online, and two simulated devices converge (tests with a fake remote).
- AC6: Firestore rules tests pass on the emulator (owner allowed, other users denied, catalog read-only).
- AC7: The functions project builds, lints and tests.
- AC8: The app builds for Android (dev flavor).
- AC9: Real Google/Apple sign-in on a device against real Firebase projects. **Expected to be BLOCKED** until you create the Firebase projects (see blockers).

**Dependencies:** approved docs 02, 03 and 05; Flutter 3.41.9 / Dart 3.11.5; Java 21 (emulators); Node (functions).

**Risks:** package-version churn (google_sign_in v7 API, Riverpod 3, Drift); Android licenses not accepted on this machine (may block AC8); no iOS build locally (`SPIKE-29567026`).

**Existing blockers:**
- **B1 (partly done 2026-11-06, see history):** production is `chapter-reads-prod`; Blaze, Auth and function deployment remain. Original note: Firebase projects `chapter-dev` and `chapter-prod` don't exist. Creating them needs you: billing (Blaze), OAuth consent screen, SHA-1 fingerprints, Apple developer setup. Until then, `dev` runs against the Firebase Emulator Suite with the offline project ID `demo-chapter`, and the real `firebase_options_*.dart` files are generated after setup.
- **B2:** Android SDK licenses are not accepted. Fix with `flutter doctor --android-licenses` (interactive, so you need to run it).

## E. Development history

### 2026-11-09 — Series page content: merged and deployed

- **Merged** by the owner as `8dfa0c4` (PR #8). CI passed on `main`. All 8 functions deployed at the owner's instruction.
- **Checked on the emulator against live Hardcover:** *Dune* shows 6 numbered books in order with the right author and covers, then *Hunters of Dune*, *Sandworms of Dune* and *A Dűne I.* as extras. The saved 99-book list was replaced.
- **Still open:** those unnumbered sequels are labelled "Novella or extra", and a translation can appear when it has no position (logged in Chronicle).
- **Git publishing authorization:** covered PR #8 and this deploy only. This entry is unstaged.

### 2026-11-09 — Series page content (COMPLETED WITH WARNINGS)

- **Objective:** `BUG-25548037`. Series pages list translations, box sets and companion books.
- **Scope:** the Hardcover series query and how saved series refresh. Functions code and tests only.
- **Acceptance criteria:** one entry per position, excluding duplicates, partial books and collections; companions at position 0 come after the main books; saved series pick up the new list; *Dune* starts with *Dune*, *Dune Messiah*, *Children of Dune*.
- **Risks:** the query can only be proven against live Hardcover after a deploy, and a deploy needs approval.
- **Done:** Hardcover series query returns one book per position, the most-read first, excluding duplicates, partial books and collections, per Hardcover's docs. Position 0 companions come last and are not counted. Unnumbered books are fetched separately, most-read first, and capped at 20, so any beyond that are not shown. Saved series refresh once through `entriesVersion` when the query succeeds.
- **Checks:** functions lint, build, typecheck and Prettier pass; 85 of 85 unit tests.
- **Not verified:** the query against live Hardcover, which needs a deploy. If it fails, `getSeries` keeps serving a saved non-empty list, so the old entries can stay visible after the deploy. Position-0 prequels in other series also move to the end.
- **Files:** `functions/src/catalog/providers/hardcover.ts`, `service.ts`, `types.ts`, `providers.test.ts`, `service.test.ts`.
- **Git publishing authorization:** commit, push and PR approved by the owner ("Approved, open a PR"). Merge and functions deploy NOT GRANTED.

### 2026-11-09 — Bug-fix round: merged and deployed

- **Merged** by the owner as `4902a65` (PR #7). CI passed on `main`. Review fixes on the PR: a failed series retry waits a day (Codex), and it can no longer overwrite a concurrent refresh (CodeRabbit). Functions unit tests: 83 of 83.
- **Deployed** all 8 functions to `chapter-reads-prod` at the owner's instruction.
- **Checked on the emulator against production:** a Title search for "dune" lists *Dune* first; an uncached All search for "foundation" lists exact titles first; a book opened fresh from Hardcover reached its Series page, the first time that page has run on a device.
- **Still open:** the cached All search for "dune" keeps its old order for up to a day. *Chapterhouse Dune* still has no series link, cause unconfirmed. The Series page lists translations, box sets and wrong-author entries. Both are logged in Chronicle.
- **Git publishing authorization:** covered PR #7 and this deploy only.

### 2026-11-09 — Bug-fix round (COMPLETED WITH WARNINGS)

- **Objectives:** four open issues the owner asked to fix: repeated notification prompt (`BUG-83003235`), "dune" ranking (`BUG-02975591`), missing series link (`BUG-42344944`), no pixel golden tests (`BUG-30759161`).
- **Scope:** app and functions code and tests only. No new dependencies, no schema change.
- **Acceptance criteria:** the permission is requested at most once per signed-in account on Android; exact title matches rank first, without reordering unrelated results; a book with a name-only series regains its link on its next refresh when Hardcover knows its ISBN; golden tests cover the design system in light, dark and 200 % text.
- **Risks:** goldens are generated on Windows and CI runs on Linux, so font rendering may differ. Search and series changes need a functions deploy, which is not authorized, so they can only be tested locally.
- **Done:** Android asks for notification permission at most once per signed-in account, and a system-settings change is honoured (`notification_permission.dart`, `AppDatabase.hasFlag`/`setFlag`). Search puts exact title matches first, then titles starting with the query, ignoring case, accents, punctuation and a leading article; other results and author or series searches keep their order. A work with a name-only series and no Hardcover id now refreshes at most daily and enriches through ISBN, so it can gain its series id. 24 pixel golden images, generated on Linux, cover buttons and fields, book cards, progress and badges, states, surfaces and the nav bar, in light and dark at 100 % and 200 % text.
- **Checks:** `flutter analyze` clean; 510 of 510 app tests (481 before, 5 permission, 24 golden); after the final test-only lint fix, analyzer and golden tests re-run and pass. Functions: lint and build pass, 81 of 81 unit tests, Prettier clean. Golden images inspected by eye.
- **Device check (notification prompt):** on the Android emulator with a production debug build, the prompt appeared on the first session and was declined. There was no prompt on a second session or on a third after a full app restart, while Android still allowed one. After granting through the system, a session showed its ongoing notification with no prompt. All test sessions were discarded, so nothing reached production.
- **Not verified:** the permission change on a physical phone; the search and series changes on production (they need a functions deploy, not authorized); whether Hardcover knows an ISBN for *Chapterhouse Dune*; golden images generated on Windows failed on Linux CI, so the reference images are now generated on Linux and compared exactly, with real fonts. The golden tests run only on Linux and are skipped on Windows. Cached searches keep their old order for up to a day after a deploy.
- **Files:** modified `app/lib/app/providers.dart`, `app/lib/core/database/app_database.dart`, `app/lib/features/reading/data/local_session_notifications.dart`, `functions/src/catalog/service.ts`, `functions/src/catalog/service.test.ts`. New `app/lib/features/reading/application/notification_permission.dart`, `app/test/features/reading/notification_permission_test.dart`, `app/test/goldens/design_system_golden_test.dart`, 24 images in `app/test/goldens/images/`. No dependencies or schema changes.
- **Git publishing authorization:** commit, push and PR approved by the owner ("Approved, open a PR"). Merge and functions deploy NOT GRANTED.

### 2026-11-09 — Stitch design integration: merged (PR #5)

- **Commit:** `df4f0aa` on local branch `stitch-design-integration`, from `main` at `33eedec`. 112 files changed as Git counts them (114 paths with 2 renames), 2,343 insertions, 904 deletions. Owner's instruction: "Commit the changes".
- **Pushed and opened as [PR #5](https://github.com/MatrimPathak/chapter/pull/5)** at the owner's instruction ("Push and open a PR").
- **Merged** by the owner on 2026-11-09 at 08:44 UTC as `aca4b9f` on `main`. The merged tree is identical to the reviewed branch at `0bab1c4`. The CI run on `main` had not finished when this was written.
- **CI on `df4f0aa`:** all four required jobs passed. Codex reported no findings. CodeRabbit requested changes with two findings in `tool/apply_icon.ps1`, both confirmed.
- **Review fix `0bab1c4` (Auto-fix):** icons are now written as 24-bit RGB, because App Store Connect rejects icons with an alpha channel (all 15 iOS icons were RGBA), and the script now stops on errors. 21 regenerated PNGs compared pixel by pixel: identical. All four required CI jobs passed on this commit. Both CodeRabbit threads were answered and resolved; its change request still showed at merge.
- **Git publishing authorization:** covered this work only. Merged by the owner. Nothing further is authorized.

### 2026-11-09 — Stitch design integration: Phase F refinement (COMPLETED WITH WARNINGS)

- **Done:** Barcode Scanner in a rounded frame with help below; onboarding, Connected services, About and Delete account on cards; global card theme; overflow tests for every listed screen on a small phone (320x568) and tablet (800x1280), in light and dark.
- **Checks:** `flutter analyze` clean; 481 of 481 app tests. On the emulator with real data, in light and dark: goal, progress, saved session, quote; Home, Insights with calendar, Goals, Notes and Scanner render correctly.
- **Chronicle:** brought up to date on 2026-11-09 at your instruction. It had fallen behind: Stitch work was recorded only here. New epics `EPIC-77959018` and `EPIC-36571515`, 24 new bug tickets, docs 16 to 26, register and status updated. Stories, sprints and release links were missed at first and added the same day: 16 stories, Sprint 8 (completed), Sprint 9 (completed after the merge), all linked to release v1.0.0. As read from Chronicle after the merge: 168 tickets, 27 open, of which 18 are bugs. No release is marked released because nothing has shipped.
- **Release bundle:** `app-prod-release.aab`, 79.8 MB, signed with the upload key, built on the third attempt after the Gradle crash (W52). Never run.
- **Not verified:** a release build on a device, Play Integrity, a real phone, TalkBack by a person, the Series page on a device, iOS. CI has not run this work. Tablet checked for overflow only.
- **Left on production:** the test account holds *Chapterhouse Dune*, a 12-book goal, one session and one test quote.

### 2026-11-09 — Stitch design integration: Phase E secondary screens (COMPLETED WITH WARNINGS)

- **Done:** Goals with ring and cards; Insights with a two-column stat grid and sections on cards, including the calendar; Author with a centred portrait and works on cards; Series on cards; new Notes screen (`/notes`, `NotesScreen`) listing every note with search and type filters, opened from Profile and Home; Profile with a centred header, totals and grouped settings; Splash and Sign-in with the Stitch logo (`assets/images/chapter_logo.png`, `ChapterLogo`).
- **Checks:** `flutter analyze` clean. Full test run 424 passed, 1 failed (the theme test looking up a heading that had scrolled away); fixed and that file passes, full suite not re-run after that test-only fix. New test covers the Notes screen. Seen on the emulator: Android launch screen with the new icon (the in-app Splash and Sign-in were not caught), Profile, empty Notes, empty Goals, empty Insights, Author, in light or dark. Phase D's dark timer and summary now also seen. Session recovery worked on the device: an abandoned session came back as a summary.
- **Not seen with real data on a device:** Goals with a goal, Insights with reading history and the calendar, Notes with notes (covered by tests), and the Series page (this book had no Hardcover series link, so its series name opens a search).
- **Not restyled beyond the theme:** Barcode Scanner, onboarding consent, Connected services, imports, About, Delete account. They pick up the new colours and type only.
- **Differences from Stitch, on purpose:** no archetype, peak hour, format breakdown, tags, Obsidian, cloud backup, follow author, or series progress. Author's works are listed without per-book add buttons.
- **Emulator:** had to be cold-booted after going offline twice with a stale snapshot.

### 2026-11-09 — Stitch design integration: Phase D reading experience (COMPLETED WITH WARNINGS)

- **Done:** focus timer with the book on a card, a thin terracotta ring, sans-serif digits, Pause as the main action; session summary with the book card, stat pills and the position form on a card; Reading tab sections on cards; reading history on cards; update-progress sheet with new -10, -1, +1, +10 page buttons. Session, recovery and Do Not Disturb logic unchanged.
- **Checks:** `flutter analyze` clean; 421 of 421 app tests, plus 3 new page-button tests (added after that run). Built with the upload key; timer, end, summary and discard exercised on the emulator in light. Dark: only the Reading tab was seen.
- **Differences from Stitch, on purpose:** no soundscapes, dimming, page-turn sounds or photo capture. The session summary keeps the editable minutes field, which Stitch doesn't show. Summary has no large "Session completed" hero; Stitch's stat tiles are pills, which fit real values and large text.
- **Not tested:** the timer and summary in dark mode (Android's notification prompt blocked the run, then the emulator went offline with little memory free; moved to Phase F); saving a session on production in this phase; the Do Not Disturb flow on the new layout on a device.
- **Left on the emulator:** one unsaved test session, and the app set to Dark. Local to the emulator; the session can be discarded next time it's opened.
- **Noticed:** Android asks for notification permission at each session start after being declined, until it stops asking on its own. Existing behaviour.

### 2026-11-08 — Stitch design integration: Phase C primary screens (COMPLETED WITH WARNINGS)

- **Home:** larger current-book card with Read and Update, other books in progress, goal rings, this week's reading bars with streak, up next, latest note, sync status, and an empty state with Search, Scan and Import. Real data only; empty sections are hidden. New `allNotesProvider`, on a new `watchAllNotes`.
- **Library:** shelves as pills with counts, list view on cards as the default (grid still one tap away), Add book button, empty state with Search, Scan and Import. Filters, sort and favourites unchanged.
- **Search:** results on cards, "Have a book in hand?" scan card, section headings. Controller and providers unchanged.
- **Book Details:** centred large cover and title, actions before progress, progress, About and details on cards. Library logic unchanged.
- **Checks:** `flutter analyze` clean; 421 of 421 app tests. Five tests assumed the old layout (buttons above the fold, grid default) and now scroll first or look for the list. Built with the upload key; compared with Stitch on the emulator in light and dark with a real book. Not pixel-perfect.
- **Differences from Stitch, on purpose:** other in-progress books stack vertically instead of a side-scrolling row, so they keep their Read and Update actions and large text still fits. No quote banner, no per-item delete on recent searches (no backend). Trending stays a cover row; per-book "add" buttons in search results are left to the book page.
- **Observed:** a production search for "dune" now ranks *Chapterhouse: Dune* first; that's the order the catalog returned, and I haven't looked into why. Left on production: *Chapterhouse Dune* on the test account's Reading shelf.

### 2026-11-08 — Stitch design integration: Phase B navigation (COMPLETED)

- **Done:** tabs are Home, Library, Search, Reading, Profile, with only the current tab highlighted; the always-on Read disc is gone. Filter chips and selectors use forest green; explicit page transitions. Launch screen matches the paper colour in light and dark.
- **App icon from Stitch, as real adaptive layers:** `tool/apply_icon.ps1` splits `tool/icon_source.png` into a transparent foreground (book and ribbon, inside the 66dp safe circle), a separate background (the green gradient) and a monochrome layer for Android 13 themed icons. iOS, legacy Android and store graphics come from the same file. Replaces `tool/generate_icons.py`.
- **Checks:** `flutter analyze` clean; 421 of 421 app tests. Built with the upload key; tab order, labels and selection seen on the emulator. A Gradle JVM crash ("GC Thread", access violation) stopped one build; the same build then passed, W52 again.
- **Not yet:** the icon's look on a launcher with themed icons on. A hairline of the ribbon's edge remains in the monochrome layer.

### 2026-11-07 — Stitch design integration (IN PROGRESS: Phase A foundation done)

- **Second Stitch run:** 65 screens listed, 44 new. **Of 13 screens named "(Dark)", only "Add to Library Sheet (Dark)" renders dark;** the others use the light palette, and their HTML has no dark tokens. Some are mislabelled ("Barcode Scanner (Dark)" shows an author page). The new screens also include excluded features: soundscapes, photo text capture, voice, tags, haptics. No screens came back by name for: Reading tab, reading history, notes and insights empty states, new Profile, sync states, connected services, imports, export, delete account, sign out, About, privacy policy, component sheet. Dark mode therefore follows the tokens and the one real dark sheet.
- **Phase A done:** Newsreader and Plus Jakarta Sans bundled (static files from Google Fonts, SIL OFL), Literata and Inter removed; colours, type scale, radii and shadows from Stitch, light and dark; theme remapped; new shared `ChapterCard`, `ChapterSectionHeader`, `ChapterStatTile`, `ChapterQuote`, `ChapterPill`; contrast test extended to the new colours.
- **Phase A checks:** `flutter analyze` clean. Full test run 419 passed, 2 failed, both my new test's own finder, fixed: design-system tests then 47 of 47. Full suite not re-run after that test-only fix. Built with the upload key and seen on the emulator in light and dark: fonts load, tokens apply, no crash.
- **Phase A leftovers:** app icon not replaced yet. Filter chips and the appearance selector still use terracotta where Stitch uses forest green. The Read tab still has its always-on disc (Phase B). Screens keep their old layouts until phases C to E.

### 2026-11-07 — Stitch design integration: inspection

- **Objective:** apply the Stitch project "Chapter Reading Companion UX/UI" (`11303033065343118952`, your choice) to the existing app. Integration, not a rewrite: repositories, providers, sync, Firebase and tests stay.
- **Retrieved:** all 21 listed screens (20 designs and the app icon) with screenshots and HTML, the theme and its design brief. 17 hidden instances are icon concepts. The older "Book Tracker Flutter App" project is not used.
- **Phases:** A foundation, B navigation, C primary screens, D reading, E secondary screens, F refinement. Each gets its own checks.
- **Acceptance:** every implemented screen compared with its Stitch reference on a rendered device; real data only; `flutter analyze` clean; all tests pass; Android build works; light and dark checked.
- **Findings:** the design brief's palette (`#F7F4EE`, `#405B4B`) differs from what the screens render (`#FCF9F8`, `#294335`). The "Quiet Reading Room (Dark Theme)" screen renders light, so **no dark design exists**. The header logo is a broken image in the exports. Many designed features have no backend.
- **Risks:** about 6,800 lines of screen code and 43 test files depend on it; widget tests find text, so copy changes break them. New fonts must be bundled. Colour changes must pass the contrast test.
- **Dependencies:** your decisions on features with no backend, wording and dark theme.

### 2026-11-07 — Next steps after Firebase production

- **Published and deployed:** PR #4, head `c19682e`, merged by you as `33eedec`; all four CI checks and CodeRabbit passed on the head commit. All 8 functions deployed from `main`. Open Dependabot alerts: 0. Review also caught a breaker gap, fixed before merge: a malformed search counted as healthy.
- **W9 verified through the app after the deploy:** series searches for "wheel of time" and "hunger games" return the right books in order, which only Hardcover can answer. Title, author and ISBN searches return results too, though the app can't show which provider answered those. "stormlight archive" and "harry potter" still showed no results by series: empty responses cached before the fix, which expire within a day (`SEARCH_TTL`).
- **Sweep:** logs show `sweepDeletedAccounts` starting on schedule; what it did wasn't checked.
- **Sign-in on a fresh emulator boot failed once,** from Google's service timing out; the retry worked. Not seen on a phone.
- **Left on production:** a new, empty Chapter account for your Google account, from this test.

- **Account deletion tested on production (W50):** at your request, your account on `chapter-reads-prod` through the app: the server asked for a recent sign-in, you were re-picked in Google's dialog, the app returned to sign-in, its local database file was gone, and the Auth export no longer listed an account. Both calls logged `auth` and `app` VALID. One run. Firestore documents not yet seen from outside the app; the sweep hasn't been observed.
- **Dependabot alerts:** all 8 were development-only; deployed functions use `@grpc/grpc-js` 1.14.7, and `npm audit --omit=dev` was already clean. Fixed: `vitest` 3 to 4.1.12, which drops `tinypool`; overrides for `@grpc/grpc-js` under `@firebase/firestore`, which pins `~1.9`, and `minimatch` under `@typescript-eslint/typescript-estree`, which asks for `^10`. Both overrides go past what those packages declare; tests pass, but revisit when upstream moves. `npm audit` reports 0. Lint, typecheck, build, 67 unit, 67 rules and 9 integration tests pass. No redeploy needed. Local only, not published.
- **Hardcover bug found live (W9):** every search narrowed to title, author, ISBN or series got `results: null` with status 200, because we sent fewer fields without our own `typos`. Our code read that as "0 results": series search always came back empty, and the other three silently fell through to Open Library. Fixed in `hardcover.ts`: one `typos` value per field, and a response with no hits list now counts as failed. 5 new tests; 72 unit tests pass. Confirmed with direct calls using your token: all four narrowed searches return results when `typos` is sent.
- **Google Books (W10):** your key works: a direct ISBN lookup returned status 200 and 1 result. Not observed through the app.
- **Release bundle:** `app-prod-release.aab`, version `0.1.0+1`, signed with the upload key, 79.6 MB, on the second try: the first died with "daemon disappeared" while other work was running. Built but never run. `release_check.py` still fails on the privacy policy (3 markers) and the 0.x version. Local build output only.

### 2026-11-06 — Firebase production, B1 (COMPLETED WITH WARNINGS)

- **Objective:** a production Firebase project the release build can sign in to and sync with.
- **Decisions by you:** a new project, leaving the existing `chapter-booktracker` untouched (it uses package `com.matrimpathak.chapter`, one user account, database in nam5). Database and functions in Mumbai, `asia-south1`.
- **Scope:** create the project and apps; create the database; set the functions and client region; generate production config; deploy rules, indexes and functions; add secrets if provided.
- **Acceptance:** a release build signs in with a real Google account, adds a book and shows "All changes saved".
- **Depends on you:** Blaze billing, enabling Google sign-in, App Check registration, the Hardcover token and Google Books key.
- **Done:** project `chapter-reads-prod` (`chapter-prod` was taken globally), Android and iOS apps as `com.chapterreads.chapter`, Firestore in `asia-south1` with delete protection, security rules live, production config in `firebase_options_prod.dart`, functions and client set to `asia-south1` with a test that they match.
- **Deployed after you turned on Blaze and Google sign-in and set both secrets:** TTL policies on `catalog_searchCache` and `ops_rateLimits`; all 8 functions in `asia-south1`. `sweepDeletedAccounts` failed the first time with a 409 on the build bucket, while the deploy still exited 0, and succeeded on a second deploy.
- **Live check:** an anonymous call to `catalogSearch` gets 401 UNAUTHENTICATED. That shows the function is reachable and refuses anonymous callers, not that providers, App Check or sign-in work.
- **Tested on the emulator against production (debug build, your upload key, App Check debug token):** real Google sign-in; server logged `auth: VALID, app: VALID` after failing correctly with `app: INVALID` before the token was added; search returned real results; *Project Hail Mary* added; Profile shows "All changes saved".
- **Seen from outside the app:** you confirmed the book in the Firestore console under `users/…/library`.
- **Acceptance not fully met:** this was a debug build; the release-build check waits for Play internal testing.
- **Upload key:** created and registered in Firebase, kept outside the repo with `key.properties` git-ignored. Production debug builds sign with it on machines that have `key.properties`; dev stays on the debug key, so existing dev installs keep their local data. Flutter's migrator added two flags to `gradle.properties`.
- **Not yet verified:** a release build, Play Integrity, account deletion, the sweep firing, which providers served the results.
- **Verification:** functions lint, build, 67 tests. App analyze clean, 406 tests. **One full app run before that stopped early** ("did not complete", 105 tests not finished), right after clearing `build/test_cache`; the rerun passed with no changes in between, cause unknown (W54 reopened). Nothing has signed in or synced yet.
- **Published:** PR #3 from `chore/firebase-production`, head `0704ca8`, merged by you as `5a083e8` on 2026-11-06. All four CI checks and CodeRabbit passed on the head commit. Review found one real bug, fixed before merge: signing all debug builds with the upload key would have broken dev installs.
- **API keys:** `firebase_options_prod.dart` holds the real keys, which identify the project and aren't secrets. GitHub opened 2 secret scanning alerts for them; they stay open until you restrict the keys and dismiss them.
- **Open from the push:** 8 Dependabot alerts in `functions/package-lock.json`, 2 critical.
- **App Check:** Play Integrity needs the app known to Play, so "adds a book" on a release build may have to wait for internal testing or use a debug token.
- **Risks:** the database location is permanent. Functions in a different region from the client's setting would fail every call. App Check is enforced on every callable, so nothing server-side works in a release build until it's registered.

### 2026-11-06 — Public repository and first CI

- **Published:** `MatrimPathak/chapter`, public, all rights reserved. Secret scanning, push protection, Dependabot alerts and private vulnerability reporting on. `main` requires the four CI checks, no force pushes or deletion.
- **CI green on PR #1:** Flutter app, functions and rules, Android release with R8, and an unsigned iOS build. **iOS compiles for the first time; it has never run.**
- **Fixes:** format check limited to tracked files; Auth emulator in CI; iOS target 15.0; Firebase pinned to 12.19.0 in `app/ios/Podfile`, because FirebaseAnalytics 12.19.3 isn't on CocoaPods. Stopgap: Firebase stops publishing to CocoaPods from October 2026, so iOS should move to Swift Package Manager.
- **Build trouble was this PC:** R8 crashes and hangs never appeared on CI. Use CI for release builds.
- **Done in PR #2 (merged as `28b44b1`):** iOS moved to Swift Package Manager; CocoaPods and the Firebase pin are gone; Firebase on iOS is 13.1.1; Flutter upgraded to 3.47.9 (TD-52). Still compile only: iOS has never run.
- **Timing:** iOS took about 23 minutes on CI under CocoaPods, 11 minutes on the last Swift Package Manager run.

### 2026-11-06 — Backlog work

- **W37 measured through the app:** real 214-book Goodreads export on the emulator, release build, live Open Library: 206 added, 8 listed as not found (96 %). One library. Wrong matches weren't audited; 147+ were by ISBN. About 30 books a minute, the server limit.
- **Offline recovery seen for real:** the Firebase emulators stopped mid-import, cause not found. The import paused with nothing lost, and resumed by itself after they returned.
- **W35 partly closed:** a real StoryGraph export (21 rows, shared publicly by its owner on an open-source project's issue, kept out of the repo) parsed exactly as an independent count: 17/2/2 by shelf, 3 rated, 4 dated, including a two-read row and quarter stars. Real Kindle files remain untested.
- **W58 fixed:** Audible links use the device country's store. `audible.co.uk` and `audible.de` kept the search in a script check; `audible.in` answered 503 to that script, so India is unconfirmed.
- **W11 fixed for now:** without a series page, tapping the series name searches for it. No dedicated test.
- **W52 evidence:** one more release build failed with "daemon disappeared", then passed on retry. Supports low memory, still unproven.

### 2026-11-06 — Warning round after Phase 8 (your request: finish all warnings and issues)

**Every warning's current status is in Chronicle doc 15, Issues & Bugs Register (`DOC-15970246`).** That register replaces the "Warnings" lists below where they disagree.

**Fixed:** W4 fonts, W5 second-device onboarding, W8 Kotlin caches (root cause: different drives), W15, W16, W17 (measured), W18 wishlist and edition details, W28, W30, W32, W34, W45, W46, W47 sweep, W49, W53, W56, W57.
**Written but never run:** W48 iOS code.
**Your decisions (2026-11-06):** W36 large imports stay foreground-only; W51 crash reports stay on by default, with the switch at setup. Both closed.
**Still open:** W35, W37, W48, W50, W52, W54, W58. **Yours:** W1, W2, W3, W7, W9–W12, W22, W38, W55. **Machine or Android limits:** W6, W14, W20, W23, W24, W27, W33. **Closed with reasons:** W13, W19, W25, W26, W31.

**New decisions:** TD-50 the device wipe never depends on signed-in providers. TD-51 `kotlin.incremental=false` and Gradle heap 4 GB, after the cross-drive cache failures and a 45-minute R8 hang; a clean release build then took 84 s, one sample only.

**Bug tickets:** at your request, every warning and every earlier bug now has a BUG ticket in Flowboard under its phase's epic, listed in Chronicle doc 15 (80 tickets; see doc 15 for current status). This replaces the earlier "no BUG tickets" notes in the history below.

**Verification:** app 404 tests; functions 67; emulator 67 rules + 9 integration (before the last, font-only change). Checked on the emulator: second-device onboarding, wishlist, page override, timer at 200 % text with Do Not Disturb, delete with a live session (DND restored, nothing left), account deleted elsewhere wipes the device (debug build); final release build signs in and syncs with the new fonts.

### 2026-11-05 — Phase 8: Quality & Release (COMPLETED WITH WARNINGS — approved by you)

**The code is finished. The app is not released and can't be from here:** that needs your accounts, keys and a legal review (B1, B3), and iOS has never been compiled. docs/07 lists every remaining step.

**Implemented**
- **Export:** Profile → Export my data. One complete JSON file and three CSV files (library, sessions, notes), built on the device and handed to the share sheet. Works offline. The account email is left out, so it needs no reauthentication. CSV cells can't run as spreadsheet formulas.
- **Account deletion:** Profile → Delete account. Typed `DELETE`, sign-in within 5 minutes (reauthenticates once if not), sync halted first, server delete, session and Do Not Disturb cleaned up, database and temporary files removed, finishing on next launch if killed.
- **Offline soak:** three devices, 400 random steps, flaky server and network, skewed clocks, 5 seeds.
- **Rules audit:** table in docs/05 §1.7; matrix tests for every collection.
- **Performance tests** with 2,000 books, 10,000 events and 3,000 sessions.
- **Accessibility tests:** tap targets, labels and contrast on 14 screens in light and dark (plus sign-in), and no overflow at 200 % text.
- **Release:** real icon and splash colour, release signing from an uncommitted key file, R8 shrinking, privacy policy draft and in-app screen, About and licences, store listing and Data safety drafts, release runbook, CI jobs for an Android release build and an unsigned iOS build.

**Files**
- **Created:**
  - App: `lib/app/crash_scrubber.dart`, `lib/features/profile/application/{data_exporter,account_actions}.dart`, `lib/features/profile/data/account_ports.dart`, `lib/features/profile/presentation/{delete_account_screen,about_screen}.dart`, `assets/legal/privacy_policy.md`, `tool/generate_icons.py`, generated icons, `android/key.properties.example`, `android/app/proguard-rules.pro`, `android/app/src/main/res/{xml/data_extraction_rules,values/colors,mipmap-anydpi-v26/ic_launcher}.xml`
  - App tests: `test/features/profile/account_test.dart`, `test/soak/offline_soak_test.dart`, `test/performance/large_library_test.dart`, `test/accessibility/accessibility_test.dart`, `test/privacy/telemetry_audit_test.dart`
  - Functions: `src/account/deleteAccount{,.test}.ts`, `test/integration/deleteAccount.test.ts`
  - Docs: `docs/07-release-runbook.md`, `docs/store/{listing,data-safety}.md`, `docs/store/assets/*`
- **Modified:**
  - App: `pubspec.yaml`, `pubspec.lock`, `android/app/build.gradle.kts`, `android/app/src/main/AndroidManifest.xml`, launch backgrounds, `ios/Runner/Info.plist`, iOS app icons, `lib/bootstrap.dart`, `lib/app/{providers,telemetry}.dart`, `lib/app/router/{app_router,routes}.dart`, `lib/core/database/app_database.dart`, `lib/core/sync/{hlc,sync_engine}.dart`, `lib/features/auth/{data/firebase_auth_repository,domain/auth_repository}.dart`, `lib/features/insights/presentation/reading_calendar.dart`, `lib/features/library/presentation/library_screen.dart`, `lib/features/profile/presentation/profile_screen.dart`, `lib/features/reading/presentation/{session_screen,active_session_bar}.dart`, `lib/l10n/app_en.arb`, test helpers and sync, reading, insights and app-flow tests
  - Repo: `functions/src/index.ts`, `functions/src/catalog/firestoreStore.ts`, `functions/package.json`, `functions/test/rules/firestore.rules.test.ts`, `firebase/firestore.indexes.json`, `.github/workflows/ci.yml`, `docs/04`, `docs/05`, `PROJECT_STATUS.md`

**Verification (executed 2026-11-05)**

| Check | Result |
|---|---|
| App: format / analyze / `flutter test` | ✅ 0 changes / no issues / **391 passed** |
| Functions: lint / typecheck / `npm test` | ✅ / ✅ / **67 passed** |
| Firestore and Auth emulators: rules + integration | ✅ **67 + 8 passed**, on the last two runs. One run just before failed 32 rules tests with nothing changed in the rules; cause not captured (W54) |
| Dev release APK with R8 (83 MB) | ✅ Built and run on the emulator |
| Prod app bundle (55 MB) | ✅ Builds, debug-signed. It can't start until `firebase_options_prod.dart` exists: this shows it compiles, not that it runs |
| CI jobs | ⚠️ Written, never run: there is no remote |

**Measured with 2,000 books** (this PC, in-memory database, not a phone):

| What | Result | Target |
|---|---|---|
| Progress save | median 0.7 ms, p95 0.9 ms | < 50 ms ✅ here |
| Library entries | 53 ms | |
| Latest progress | 186 ms | |
| Statistics input + engine | 338 + 23 ms | |
| Export | 798 ms | |
| Time to first frame, release build, Android emulator | 3.3 s first launch, then 1.6–1.8 s | < 2.0 s to interactive on a Pixel 6a: **not shown** |

List scrolling with 2,000 books was **not measured**; the plan's "library queries, statistics, progress save" were. W31 needs no change on these numbers, though a phone will be several times slower.

Checked on the emulator, in the release build with R8: fresh sign-in; CSV import with live lookups; launcher icon; export in airplane mode reaching the share sheet with all four files; delete in airplane mode refused with nothing removed; delete online. That run reauthenticated when the sign-in had gone stale, and afterwards there were 0 user documents, 0 Auth users and 0 rate-limit documents, the local database and temp folders were empty, and the shared catalog was untouched. It landed on the sign-in screen.

**Not checked on a device** (tests only): deleting with a session running and Do Not Disturb on; a kill between the server deleting and the wipe; the server's new retry; opening an exported file in a real app; About, privacy and licences screens beyond the accessibility tests; the fixes to the timer layout at 200 % text. **Not checked at all:** TalkBack or VoiceOver by a person; iOS (nothing compiled); a real device; real Firebase, Google sign-in or App Check; TTL policies (emulators ignore them); crash-free rate; a store upload.

**Acceptance criteria**
- ✅ AC1–AC6, AC9, AC11.
- ⚠️ AC7: figures recorded and save target met in tests, but list scrolling wasn't measured, and none of this is a phone.
- ⚠️ AC8: automated checks pass after fixes. They check sizes, labels and contrast, not real screen-reader use.
- ⚠️ AC10: both builds compile. Missing inputs for a real release: Firebase prod config, signing key.
- ❌ From the story: "NFR targets met" can't be claimed for cold start or crash-free rate. "Builds accepted by Play Console and App Store Connect" is BLOCKED on B3.

**Bugs found and fixed during the phase** (before any commit, so no BUG tickets)
1. **One phone with a wrong clock could stop sync on all others, permanently (found by the soak test; the worst bug of the project so far).** A remote clock over an hour ahead made `Hlc.receive` throw, which rolled back that document, abandoned the rest of its batch and never advanced the cursor, so it failed again every launch. All silent. Remote clocks are now always adopted, and a failing document no longer holds back the others (TD-46). Since Phase 2.
2. **Crash reports could carry reading content.** A SQLite error message lists its parameters, which can be note text, and layout errors can quote on-screen text, despite the consent screen's promise. Now only the error type and stack go (TD-47). Nothing was ever sent, because telemetry has never run in production.
3. **Android cloud backup would have restored a deleted account's database.** Backup is now off.
4. **Rate-limit documents survived deletion.** They're keyed by uid. They're now deleted, with a test.
5. **Those same documents and the search cache would never have expired:** TTL policies were missing from the index config.
6. **Telemetry had a brief window on at startup,** before Dart turned it off. Now off in the manifest and Info.plist.
7. **HLC counter overflow** would have blocked all writes while clocks run ahead. It now moves on a millisecond.
8. **Timer screen overflowed at 200 % text** in three places, and by 10 px at normal size with my replacement button; the session bar overflowed too. Library's search field had a 24 dp tap target.
9. **My own mistakes, caught by tests:** a bad splice duplicated the timer block; a test tap was missing because a message covered the button (Phase 7).

**Deviations from the plan**
- W25 closed without a code change: Open Library itself reports 2000 for that work (checked live). Hardcover would correct it once enabled.
- W34 fixed: a past year opens on its last active month. Tested only through existing calendar tests, with no dedicated test or device check.
- W31 left alone, on the measurements above.
- Export omits the account email, a deliberate choice to keep it offline (docs/05 §1.1).
- Docs said reauthenticate only for some actions; the server enforces the 5 minutes rather than trusting the client.
- Offline deletion isn't possible, by design.

**Warnings / known limitations**
- W47: **A second device online during deletion could recreate documents** under the deleted uid for up to an hour (an issued token stays valid). Unreachable by anyone, but they'd remain until removed by hand. Fixing it costs an extra read on every write or a delayed sweep. The privacy policy states this.
- W48: **iOS gaps known in advance:** Sign in with Apple token revocation isn't built (guideline 5.1.1(v)), and iCloud backup isn't excluded. Details in docs/07 §4.
- W49: Other devices keep their local copy after deletion until signed out or uninstalled. Stated on the delete screen and in the policy.
- W50: **Unexplained, once:** the first server deletion failed with gRPC code 1 (cancelled), and the retry a minute later worked. The app handled it correctly, nothing was lost, and the server now retries once by itself. The cause wasn't found, so watch for it on real Firebase.
- W51: Crash reports default to on with a switch at setup, per docs/05. Some regions prefer opt-in: your call (docs/store/data-safety.md).
- W52: **Release Gradle builds failed within seconds twice** in about seven attempts, each time soon after stopping the daemon, and passed on an immediate retry with no change. The error wasn't captured. Looks like this machine, but unproven.
- W53: `npm audit`: 9 moderate advisories through `uuid` in Firebase's dependencies. Fixing needs a breaking downgrade via `--force`, so left alone. The advisory is about a caller-supplied buffer, which this code doesn't use, by my reading of it.
- W54: **Two intermittent test failures, causes not found:** the accessibility run hung once in about six runs, and the rules suite failed 32 tests once. Both passed on rerun, on a busy 8 GB machine, which may be why. If CI flakes, look there first.
- W55: The privacy policy is an AI-written draft, with placeholders and a visible "DRAFT" line **that the app displays as is**. It must be reviewed and completed before release.
- W56: Functions files are a mix of quote styles; only ESLint is enforced. Cosmetic.
- W57: Analytics has no events, so the success metrics in docs/01 §7 can't be measured yet.
- Still open from before: W18 (wishlist and edition override UI, proposed for v1.1), W28, W30, W32, W35, W36, W37, W38.

**Remaining tasks:** everything in docs/07, starting with Firebase production and your real export files.

**Recommended next step:** Git publishing decision, then the runbook. This is the last roadmap phase.

### 2026-11-05 — Phase 7: Integrations (COMPLETED WITH WARNINGS — approved by you)

**Implemented**
- **Connected services** (Profile): one card per service, saying what it does and doesn't do. A failure shows only on its own card.
- **Goodreads and StoryGraph CSV import:** parsed on the device, previewed before anything changes, then a persistent queue resolves each book (ISBN, then a strict title-and-author match). It resumes after a restart and pauses on rate limits and lost connections. Shelves, ratings, reviews, read dates and owned copies are mapped. Unmatched books are listed.
- **Kindle `My Clippings.txt`:** quotes and notes with page and location, matched to books in the library. Unmatched books are listed.
- **Audible (manual):** book menu → Add audiobook edition (Audible or other, length as h:mm:ss), `h:mm:ss` progress, "listened" on the timer and summary, Find on Audible, and plain copy that automatic sync isn't possible.
- **Spotify Tier A:** Music for reading on the Read tab, opening Spotify search links. No account or API.
- **Data:** Drift schema v6 (`import_rows`); note `location` field, allowed by the rules; imported dated reads count on their own dates.

**Files**
- **Created (app):**
  - `lib/features/integrations/domain/{integration,csv_parser,reading_import,kindle_clippings}.dart`
  - `lib/features/integrations/data/{import_queue,platform_ports}.dart`
  - `lib/features/integrations/application/{import_runner,clippings_importer}.dart`
  - `lib/features/integrations/presentation/{integrations_providers,integrations_screen,import_screens}.dart`
  - Tests: `test/features/integrations/{parsers,import,integrations_flow}_test.dart`
- **Modified:**
  - App: `pubspec.yaml`, `pubspec.lock`, `android/app/src/main/AndroidManifest.xml`, `lib/core/database/{tables,app_database}.dart`, `lib/app/providers.dart`, `lib/app/router/{app_router,routes,scaffold_with_nav}.dart`, `lib/features/library/{data/lww_library_repository,domain/library_repository,presentation/library_sheets}.dart`, `lib/features/notes/{domain/note,data/lww_notes_repository,presentation/book_notes_section}.dart`, `lib/features/insights/domain/stats_engine.dart`, `lib/features/profile/presentation/profile_screen.dart`, `lib/features/reading/presentation/{read_screen,session_screen}.dart`, `lib/l10n/app_en.arb`, `test/core/database/migration_test.dart`, `test/helpers/test_app.dart`, `test/app/app_flow_test.dart`, `test/features/reading/session_flow_test.dart`, `test/features/insights/{stats_engine,insights_flow}_test.dart`
  - Repo: `firebase/firestore.rules`, `functions/test/rules/firestore.rules.test.ts`, `docs/03-data-architecture.md`, `docs/04-integrations.md`, `PROJECT_STATUS.md`

**Verification (executed 2026-11-05)**

| Check | Result |
|---|---|
| App: `dart format --set-exit-if-changed` / `flutter analyze` / `flutter test` | ✅ 0 changes / no issues / **317 passed** (after the warning fixes) |
| Functions: lint / `npm test` | ✅ / **57 passed** |
| Firestore emulator: rules + catalog store integration tests | ✅ **35 + 4 passed** |
| Dev APK build | ✅ |
| Android emulator (API 36) | ✅ See below |

Checked on the emulator: the real system file picker (`.csv` selectable, `.txt` greyed out, and the reverse for Kindle); CSV preview; import with live Open Library lookups (Dune and The Hobbit added, an invented title listed as not found); Dune with 5 stars, review, finish date and owned edition; clippings import (quote, `p. 8 · loc. 120`, unmatched book listed); audiobook edition; 2:50:00 of 11:20:00 showing 25%; timer "listened" and summary "Minutes listened"; Find on Audible and a Spotify link dispatched to the browser (confirmed in logcat).

Checked on the emulator after the warning fixes (fresh install): typing replaces the prefilled progress time; "Start a listening session"; audiobook add, then the menu offers Edit; the picker lists the audiobook once and switching away and back works; finish, remove and re-add as Read asks for no date and stays "Read 2 times"; "All changes saved" with no rule denials in the emulator log. During this run two ISBN lookups stayed pending for the full 5 minutes, then finished ("Added: 2"). The server had finished them in about 10 s and the retry took 78 ms, so the likely cause is the client's 20 s limit during a slow cold start. That is inferred, not proven. Nothing was lost.

**Not re-run on a device after the last two changes** (tests only): the shorter retry wait and the audiobook length selection. Built into the APK, not installed. (That build failed once and passed on an immediate retry with no code change; the first error wasn't captured.) Saving a changed audiobook length was also only tested in a widget test: the device run saved the same value.

**Not checked on a device** (automated tests only): restart mid-import, rate-limit and offline pauses, the 1,000-row import, reimporting, StoryGraph files, edited or deleted notes on reimport, failure injection, a second device. **Not checked at all:** the Audible and Spotify pages themselves (Chrome stopped at its first-run terms, which I didn't accept, and the Spotify app isn't installed on the emulator); that the saved audio session appears in history; imported data reaching the Firestore emulator (the new rules have tests, but the documents weren't inspected); TalkBack; iOS (nothing compiled, W38).

**Acceptance criteria**
- ✅ AC1–AC7, AC9. AC3 uses fakes for the catalog, not real lookups at scale. AC4 uses two simulated devices.
- ⚠️ AC8: run on the emulator, except that the link destinations were never seen. Links are confirmed only as far as being handed to the browser.

**Bugs found and fixed during the phase** (before any commit, so no BUG tickets)
1. **A failing integration still offered its action.** `yield*` forwards stream errors past a `catch`, so the card kept a live button instead of "unavailable". Found by the new fault-injection tests.
2. **The import runner could take down the app shell** when a dependency failed to initialise, because the shell watches it. Now contained; import is simply unavailable. Found by existing app-flow tests.
3. **Negative hex in the import key:** the 64-bit hash could go negative. Fixed before use.

4. **Failing-link test wasn't testing anything:** the message from the previous tap covered the last link, so the tap missed. The test now waits and counts attempts. The app was fine.

**Deviations from the plan**
- Search links, not curated playlists (planned: no invented playlist IDs). docs/04 updated.
- Spotify Tier B not built (planned: needs your Spotify developer app, a Premium account and server-side secrets).
- Kindle location isn't an entry option in the progress sheet (planned).
- Audiobook lengths are entered by hand. Catalog metadata rarely has them.
- `Integration` has no `connect()`/`disconnect()` as sketched in docs/04 §7: nothing connects to an account yet. Tier B would add them.
- The Music card sits on the Read tab only; a failure hides it (per docs/04), and on Connected services it shows as unavailable.

**Warnings / known limitations**
- W35: **No real export files were available.** Goodreads, StoryGraph and `My Clippings.txt` fixtures were written from public descriptions of the formats. Non-English Kindle files are untested and probably won't parse. Please try your own files.
- W36: Large imports are slow and only run while the app is open: about 34 minutes per 1,000 rows at best, at the current lookup limit. They resume on the next launch. Background running would need OS background work (Phase 8 or later).
- W37: Partly fixed: the import screen now separates added, already in library and removed earlier. Still unknown: match rate on real libraries, with Hardcover and Google Books off (W9, W10) and strict matching.
- W38: `file_picker` and `url_launcher` are untested on iOS; no iOS build exists (`SPIKE-29567026`). The iOS app may need its own URL scheme and document-type setup.
- W39: **Fixed** (TD-45): removing a book and adding it back as Read restores the earlier read, with no date prompt. To record a real extra read, use Reading then Read.
- W40: **Fixed:** progress fields and the audiobook length select their value, so typing replaces it.
- W41: **Fixed:** the book page says "Start a listening session" on audiobooks. Session notifications now say "Session", for both.
- W42: **Fixed:** a book has one typed audiobook edition to edit, and the edition picker lists it, so switching back no longer means adding it again. Two devices adding one at the same moment could still create two; both would be listed.
- W43: **Fixed:** music link labels are in the ARB file.
- W44: **Fixed:** Chronicle doc 07 refreshed as a short summary. This file stays the full record.
- W45: Re-adding a removed book follows the add sheet, so "I own this edition" is cleared unless ticked again. Seen on the emulator.
- W46: Import counts are totals across all files ever imported, because finished rows are kept to recognise reimports.
- Earlier warnings remain open (not part of this fix round): W18, W25, W28, W30, W31, W32, W34.

**Remaining tasks:** try real export files; a physical-device run; an accessibility pass (Phase 8).

**Recommended next phase:** Phase 8 — Quality & Release.

### 2026-11-05 — Phase 6: Goals & Insights (COMPLETED WITH WARNINGS — approved by you)

**Implemented**
- **StatsEngine:** totals, day activity, average session, pages per hour, books per month, monthly points, weekday activity, top authors and genres, streaks, goal progress; thresholds on every statistic that could mislead.
- **Insights screen** (Profile): year switcher, totals, month calendar with day details, monthly and weekday bars, rankings, habits. "Not enough data yet" below thresholds.
- **Goals** (Profile, and running goals on Home): create, edit target, delete; past goals kept as history.
- **Notes** on the book page: note, quote or observation, optional page; add, edit, delete; conflict copies.
- **Rating and review** on the book page.
- **Carry-overs:** library filters by author, genre and series; progress sort; pages left; delete a saved session; Read and Update on Continue Reading.
- **Sync and rules:** `notes`, `goals`, `sessionTombstones`, and `rating`/`review` on `library`; Drift schema v5 (`session_tombstones`).

**Files**
- **Created (app):**
  - `lib/features/goals/{domain/goal,data/lww_goal_repository,presentation/goals_screen}.dart`
  - `lib/features/insights/{domain/stats_engine,presentation/insights_providers,presentation/insights_screen,presentation/reading_calendar}.dart`
  - `lib/features/notes/{domain/note,data/lww_notes_repository,presentation/book_notes_section}.dart`
  - Tests: `test/features/insights/{stats_engine,insights_flow}_test.dart`, `test/features/notes/notes_sync_test.dart`
- **Modified:**
  - App: `lib/core/database/{tables,app_database}.dart`, `lib/core/design_system/components/{book_card,chapter_overlays}.dart`, `lib/app/providers.dart`, `lib/app/router/{app_router,routes}.dart`, `lib/features/home/presentation/home_screen.dart`, `lib/features/library/{data/lww_library_repository,domain/library_models,domain/library_repository,presentation/library_providers,presentation/library_screen,presentation/library_sheets}.dart`, `lib/features/profile/presentation/profile_screen.dart`, `lib/features/reading/presentation/read_screen.dart`, `lib/l10n/app_en.arb`, `test/core/database/migration_test.dart`, `test/features/reading/session_flow_test.dart`
  - Repo: `firebase/firestore.rules`, `functions/test/rules/firestore.rules.test.ts`, `docs/02-system-architecture.md`, `docs/03-data-architecture.md`, `PROJECT_STATUS.md`

**Verification (executed 2026-11-05)**

| Check | Result |
|---|---|
| App: `dart format --set-exit-if-changed` / `flutter analyze` / `flutter test` | ✅ 0 changes / no issues / **244 passed** |
| Functions: lint / `npm test` | ✅ / **57 passed** |
| Firestore emulator: rules + catalog store integration tests | ✅ **33 + 4 passed** |
| Dev APK build | ✅ |
| Android emulator (API 36) | ✅ See below |

Checked on the emulator: 4-star rating; quote note with a page; Read and Update on Continue Reading; session saved at p.150 (30 pages); Insights with sparse data (real totals; "Not enough data yet" elsewhere); empty Goals; pages goal on Home matching Insights (150 of 1000); deleting the session (goal → 120 of 1000, book still at 38%); tombstone, note, goals and rating reached the Firestore emulator through the real rules; data survived an emulator crash; custom-date goal picker; filter sheet and options.

Also checked after the finish-date fix: adding a book as Read prompts; future days disabled; a 2019 date shows on the book page, and Insights gives 2026 0 books and 2019 1 book, 392 pages; "I don't remember" stores null through the real rules.

**Not checked on a device** (automated tests only): correcting to another date, marking Read from the shelf picker, charts with dense data, a filter actually applied, editing or deleting a note, writing a review, half-star taps, editing or deleting a goal, a real second device (conflict copies and tombstone order use two simulated devices). Not checked anywhere: VoiceOver/TalkBack on the calendar and bars.

**Acceptance criteria**
- ✅ AC1–AC8. AC2 includes randomized hostile input (NaN, Infinity, negatives, duplicates, unknown works). AC5 and AC7 use two simulated devices.
- ⚠️ AC9: run on the emulator, but a library filter was only opened, not applied, and the list above wasn't covered.

**Bugs found and fixed during the phase** (before any commit, so no BUG tickets)
1. **Update progress didn't open from Home** in a widget test, when the book page hadn't been opened. The sheet waited on providers nothing was watching; it now reads the repository directly, and this works on the emulator. The cause wasn't pinned down further, and the code dates from Phase 4.
2. **Text in a note or review sheet was lost if the sheet was dismissed.** Found by accident on the emulator. It now asks first (tap outside, back), and swiping the sheet away is off for these two. Fixed and covered by a widget test; not rerun on a device.
3. **`conflictOf` limit too short:** found on review, not by a failure. A copy of a copy could have an id over the 64 characters the rules allowed, so the limit is now 300.

**Deviations from the plan**
- Bars use plain widgets, not `fl_chart` (TD-37).
- Goals' metric and period can't be changed after creation, only the target; delete and re-add for the rest.
- Goals and Insights live under Profile, per docs/02; there is no new tab.

**Warnings / known limitations**
- W28: Deleted-session pages come back later. Deleting removes that session's pages from statistics, but the reader's next progress beyond that point counts all the movement since the last kept event, including those pages. A deleted session's time never returns.
- W30: **Fixed** (TD-38): marking an untracked book Read asks when it was finished. What remains: all of a book's pages land on its finish date, and changing or clearing a finish date moves or removes the book but not its pages, because progress events are never edited.
- W34: In Insights, a past year's calendar opens on December even if the reading was earlier in the year, and years are stepped one at a time.
- W31: Statistics recompute over the whole history on any change, on the UI thread. Not profiled with large histories (Phase 8).
- W32: A book removed from the library still counts as finished, but leaves author and genre rankings, and its pages stop counting unless an edition with a page count is on record.
- W18 (remaining): wishlist UI, edition override and calibration UI.
- W33: Android emulator crashed once more during this run (W20). Unrelated to the app as far as could be seen; no crash log was captured because the log command hung.
- W25 is still open: search shows 2000 as the year for The Deal.

**Remaining tasks:** W25 (investigate), a physical-device run, an accessibility pass (Phase 8).

**Recommended next phase:** Phase 7 — Integrations.


### 2026-11-05 — Phase 5: Reading Experience (COMPLETED WITH WARNINGS — approved by you)

**Implemented**
- **Timer:** `SessionClock` (elapsed derived from timestamps, capped at the planned duration, backwards clock clamped and flagged); `SessionService` lifecycle; `SessionController` with serialized transitions.
- **Recovery:** on launch, a running session resumes, an overdue one ends at its planned end as `recovered`, an ended-but-unsaved one reopens its summary.
- **UI:** Read tab (book, presets 15–120 min, custom, DND switch, recent sessions); full-screen timer; active session bar; summary (editable minutes and position, pages read, pages per hour, old → new progress, Save, Discard); "Read" on Continue Reading; "Start a reading session" and session history on the book page.
- **Notifications:** ongoing countdown and end alert.
- **Focus:** Kotlin `FocusModeChannel`, explanation before settings, DND chip on the timer (turn on or off mid-session); iOS channel (screen wake only) and a Focus setup guide.
- **Sync:** `users/{uid}/sessions` create-only with schema-checked rules; Drift schema v4 (`active_sessions`, `sessions`).

**Files**
- **Created (app):**
  - `lib/features/reading/domain/{session_clock,reading_session,session_ports}.dart`
  - `lib/features/reading/application/{session_service,session_controller}.dart`
  - `lib/features/reading/data/{drift_active_session_store,local_session_notifications,channel_focus_mode}.dart`
  - `lib/features/reading/presentation/{session_flow,session_screen,active_session_bar}.dart`
  - `android/app/src/main/kotlin/com/chapterreads/chapter/{FocusModeChannel,FocusRestore}.kt`
  - Tests: `test/features/reading/{session_clock,session_service,session_flow}_test.dart`, `test/core/database/migration_test.dart`, `test/helpers/fake_session_ports.dart`
- **Modified:**
  - App: `lib/features/reading/presentation/read_screen.dart`, `lib/core/database/{tables,app_database}.dart`, `lib/app/providers.dart`, `lib/app/router/{app_router,routes,scaffold_with_nav}.dart`, `lib/features/home/presentation/home_screen.dart`, `lib/features/library/{data/lww_library_repository,domain/library_repository,presentation/library_providers,presentation/library_sheets}.dart`, `lib/features/profile/{domain/profile_repository,data/lww_profile_repository}.dart`, `lib/l10n/app_en.arb`, `pubspec.yaml` (+flutter_local_notifications, timezone), `android/app/build.gradle.kts` (desugaring), `android/app/src/main/AndroidManifest.xml`, `android/app/src/main/kotlin/com/chapterreads/chapter/MainActivity.kt`, `ios/Runner/AppDelegate.swift`, `test/helpers/test_app.dart`, `test/features/library/lww_library_repository_test.dart`
  - Repo: `firebase/firestore.rules`, `functions/test/rules/firestore.rules.test.ts`, `docs/03-data-architecture.md`, `docs/04-integrations.md`, `PROJECT_STATUS.md`

**Verification (executed 2026-11-05)**

| Check | Result |
|---|---|
| App: `dart format --set-exit-if-changed` / `flutter analyze` / `flutter test` | ✅ 0 changes / no issues / **181 passed** |
| Functions: lint / build / `npm test` | ✅ / ✅ / **57 passed** |
| Firestore emulator: rules + catalog store integration tests | ✅ **24 + 4 passed** |
| Dev APK build | ✅ (one build failed with Gradle "Truncated class file", W23) |
| Android emulator (API 36) | ✅ See below |

Checked on the emulator: custom duration; DND on (`zen_mode` 1, system rule shown) and back off (0) after End and after recovery; kill mid-session and relaunch → timer continues; timer expiring while dead → recovered summary with the page count; Save → Home, Read history, Firestore emulator (session `recovered`, 25 pages, 60 s, progress event); Discard; end alert with the app backgrounded and with the process killed (`kill -9`); ongoing notification clears itself after process death; access-denied explainer changes nothing.

Also checked after the W21 fix: DND restored with the process dead (`zen_mode` 1 → 0, no app running) and after a reboot mid-session without opening the app; DND the reader already had on stays on after End and leaves no Chapter rule behind; DND chip on and off; Pause and Resume (time frozen while paused).

**Not checked on a device** (unit or widget tests only): Discard with DND on, a second device receiving a session, the end alert being rescheduled after a reboot, the `Sessions` list on the book page, and resuming after the 1-hour pause limit. The native restore can't be unit-tested; the Dart side uses a fake that mirrors it.

**Acceptance criteria**
- ✅ AC1–AC8. AC6 was partial until W21 was fixed; DND is now restored on end, cancel, recovery, denied access, with the process dead and after a reboot. One exception: see W27.

**Bugs found and fixed during the phase** (before any commit, so no BUG tickets)
1. Red-screen crash after Custom duration: the text controller was disposed during the dialog's closing animation. Found on the emulator only.
2. Summary said "no page count" for a 392-page book: the form chose its mode before the edition loaded.
3. Running out in the background cancelled the end alert, so the reader was never told.
4. The ongoing notification stayed after process death.
5. The end alert could be silenced by our own DND (it fired before the restore).
6. Each relaunch of an unsaved session re-applied the old DND filter, overwriting later changes by the reader.
7. A notification error could stop DND being restored.
8. `SessionScreen.dispose` used `ref` after unmount.
9. DND stayed on until relaunch if the app was dead when the timer ended (W21, fixed with TD-33).

**Deviations from the plan**
- Focus mode is a per-session switch on the Read tab, not a Profile setting.
- Continue Reading has one action, "Read" (starts the timer). Update progress is on the book page. `US-57758694` asked for both on the card.
- Screen wake uses our own channel (TD-32); DND uses `setInterruptionFilter` (TD-28).
- `US-45232030` asks for one Firestore WriteBatch on save. Save is one local transaction, but pushes are ordered and per-operation (TD-23), so another device can briefly see the session before its progress event (W19).

**Warnings / known limitations**
- W21: **Fixed** (TD-33).
- W27: Android cancels an app's alarms on Force stop (Settings or `am force-stop`), so in that one case DND stays on until Chapter is next opened. The restore alarm is inexact (about 45 s late on the emulator, possibly later in Doze), and the end alert can fire just before it and be silenced.
- W22: The iOS Swift code (`AppDelegate.swift`, focus channel, notification delegate) has **never been compiled**; no macOS here (`SPIKE-29567026`). It could break the iOS build.
- W23: Gradle reported "Truncated class file" on one build and failed once more without a captured log; retries succeeded. Stop the Gradle daemon before running the emulator on this 8 GB machine (it caused ANRs).
- W24: With inexact alarms the end alert can be late when the app is dead (the API 36 emulator gave a window of about 44 s). Recorded time is unaffected.
- W25: Search results showed "2000" as the year for The Deal, which looks wrong (Phase 3 metadata). Not investigated.
- W26: Saved sessions can now be deleted (Phase 6); editing their numbers is out of scope.

**Remaining tasks:** an iOS build once CI exists, a physical-device run.

**Recommended next phase:** Phase 6 — Goals & insights.


### 2026-11-04 — Phase 4: Library, Editions & Progress (COMPLETED WITH WARNINGS — approved by you)

**Implemented**
- **Sync engine:**
  - `SyncRemote.createIfAbsent` and `watchCollection(since)`, with `RemoteDoc`.
  - `LwwStore.batch`: atomic multi-document writes plus append ops sharing one outbox batch; `watchCollection` / `readCollection`.
  - `SyncEngine.watchCollection` with a cursor persisted in `sync_meta`; create ops are pushed as create-if-absent.
  - Firestore rules for `library`, `readThroughs`, `userEditions` (per-field LWW, schema-checked, no deletes) and `progressEvents` (create-only, immutable).
- **Domain:** `ReadingPosition` (Freezed union), `ProgressMapper`, `ProgressEvent`, `CompletionEstimator` (≥ 3 reading days in 30), `LibraryEntry`, `BookSummary`, `ReadThrough`, `UserEdition`.
- **Data:** `LwwLibraryRepository` with the status rules (TD-26), duplicate-safe add, edition switching, ownership, favourite, tombstone removal, and remote progress applied insert-or-ignore. Drift schema v3 adds `progress_events`.
- **UI:**
  - Book detail: Add to library sheet (shelf, edition, "I own this edition"), status picker, favourite, change edition, remove, progress bar with approximate badge, finish estimate, read count.
  - Progress sheet: page / percent / audio time, slider, validation, "Mark as read" at 100 %.
  - Scanner: "Add to library" on the found sheet (owned by default).
  - Library tab: shelves with counts, grid/list, sort (recent, title, author, date added), favourites filter, in-library search.
  - Home: Continue Reading, ordered by latest activity, with Update.

**Files**
- **Created (app):**
  - `lib/features/progress/domain/{reading_position,progress_mapper,progress_event,completion_estimate}.dart`
  - `lib/features/library/domain/{library_models,library_repository}.dart`, `lib/features/library/data/lww_library_repository.dart`
  - `lib/features/library/presentation/{library_providers,library_sheets,progress_format}.dart`
  - Tests: `test/features/progress/{progress_mapper,completion_estimate}_test.dart`, `test/features/library/{lww_library_repository,library_flow}_test.dart`
- **Modified:**
  - App: `lib/core/database/{tables,app_database}.dart`, `lib/core/sync/{sync_remote,firestore_sync_remote,lww_store,sync_engine}.dart`, `lib/app/providers.dart`, `lib/features/{home/presentation/home_screen,library/presentation/library_screen,catalog/presentation/book_detail_screen,scanner/presentation/scan_screen}.dart`, `lib/l10n/app_en.arb`, `test/helpers/fake_sync_remote.dart`, `test/features/catalog/discovery_flow_test.dart`
  - Repo: `firebase/firestore.rules`, `functions/test/rules/firestore.rules.test.ts`, `docs/03-data-architecture.md`, `PROJECT_STATUS.md`

**Verification (all executed 2026-11-04)**

| Check | Result |
|---|---|
| App: `dart format --set-exit-if-changed` / `flutter analyze` / `flutter test` | ✅ 0 changes / no issues / **144 passed** |
| Functions: lint / build / `npm test` | ✅ / ✅ / **57 passed** |
| Firestore emulator: rules tests + catalog store integration tests | ✅ **21 + 4 passed** |
| Dev APK build | ✅ |
| Manual end to end on the Android emulator (Auth, Firestore and Functions emulators; live Open Library) | ✅ search → The Deal → Add (Reading, owned paperback) → progress p.187 → "p. 187 of 392 · 48%" → Home Continue Reading 48 % → Library "Reading (1)". The Firestore emulator holds the library entry, read-through, user edition and progress event (page 187, fraction 0.477). Data survived an app restart. |

**Acceptance criteria**
- ✅ AC1, AC3 (Kindle p.187/400 → 19,074 s of 40,800 s, approximate), AC4, AC5, AC6, AC7, AC9.
- ✅ AC2: two simulated devices. Offline edits to different fields merge; the same field on both resolves to the later edit even when pushed out of order; all progress events from both devices are kept; pushing an event twice creates it once.
- ⚠️ AC8: sort and search are tested. Filters by author/genre/series are **not built** (only favourites), and 2k-book scrolling is **not measured** (W17, W18).

**Bugs found and fixed during the phase** (before any commit, so no BUG tickets)
1. Riverpod "markNeedsBuild during build" when signing out with Home/Library mounted (TD-27).
2. Library grid cards overflowed (5.4 px at 1×, more at larger text) because of a fixed aspect ratio. Replaced with self-sizing rows, plus a 2× text-scale regression test.

**Deviations from the plan**
- Not built (W18): author/genre/series filters, "progress" and "recently read" sorts ("recently updated" covers the latter), wishlist UI, page-count/duration override UI, calibration UI, "pages remaining" text.

**Warnings / known limitations**
- W17: Performance with ~2k entries is unmeasured (no profiler here). First sign-in on a device downloads the whole collection.
- W18: The UI scope gaps listed under Deviations.
- W19: Another device can briefly see half of a multi-document change while the outbox drains (TD-23).
- W20: The Android emulator is unstable on this 8 GB machine (ANR on cold boot; the emulator process died once). After an Auth emulator restart the app keeps a stale session (`INVALID_REFRESH_TOKEN`); clear app data.
- W5 (onboarding shown again on a second device before the profile arrives) is still open.

**Remaining tasks:** the W18 UI items (suggested for Phase 6, alongside organization), a 2k-book performance check on a real device, and B1/B2 as before.

**Recommended next phase:** Phase 5 — Reading experience (timer, sessions, recovery after the app is killed).


### 2026-11-04 — Phase 3: Discovery (COMPLETED WITH WARNINGS — approved by you)

**Implemented**
- **Server (`functions/src/catalog/`):**
  - `BookMetadataProvider` interface and three providers: Open Library (live), Hardcover GraphQL and Google Books (both secret-gated).
  - `MetadataOrchestrator`: priority fallback, per-provider timeouts, circuit breakers, parallel ISBN lookups.
  - `mergeWork`: field-level priorities, provenance per field, ISBN-matched page count with a print-edition fallback, genre normalization, earliest publication year, editions deduplicated by ISBN.
  - `CatalogService`: identity on hard identifiers only, 30-day freshness, serves stale data when providers are down, 24 h search / 6 h trending cache, per-user rate limits.
  - `FirestoreCatalogStore`: transactional saves; an ISBN is never re-pointed to another work.
  - Six callables (`catalogSearch`, `catalogLookupIsbn`, `catalogGetWork`, `catalogGetAuthor`, `catalogGetSeries`, `catalogTrending`) with zod validation, typed errors, and App Check enforced in production.
- **App:**
  - Catalog models (Freezed).
  - `CatalogRepositoryImpl`: network-first with a Drift cache (schema v2 migration adds `catalog_cache_entries` and `recent_searches`), offline search over cached books, recent searches.
  - Search tab: 350 ms debounce, field filters, pagination, recents, trending, offline/degraded banners.
  - Book detail (clickable authors and series, description, details, editions), Author screen, Series screen (reading order, novellas marked).
  - ISBN scanner: `mobile_scanner`, Bookland EAN-13 only, manual entry, confirmation sheet.
  - Routes `/book/:key`, `/author/:key`, `/series/:id` and `/search/scan` on the root navigator. Camera permission strings for Android and iOS.
- **Shared:** ISBN validation in Dart and TypeScript with mirrored tests.

**Files**
- **Created (functions):**
  - `src/catalog/{types,isbn,http,ids,rateLimiter,merge,orchestrator,store,firestoreStore,service,callables}.ts`
  - `src/catalog/providers/{BookMetadataProvider,openLibrary,googleBooks,hardcover}.ts`
  - Tests: `src/catalog/*.test.ts`, `src/catalog/providers/providers.test.ts`, `test/integration/firestoreStore.test.ts`, `test/helpers/fixtures.ts`
  - Fixtures: `test/fixtures/*.json` + `README.md`
  - `.secret.local` (gitignored, empty values)
- **Created (app):**
  - `lib/features/catalog/{domain,data,presentation}/…`, `lib/features/scanner/{domain/isbn.dart, presentation/scan_controller.dart, presentation/scan_screen.dart}`
  - `build.yaml`
  - Tests: `test/helpers/fake_catalog.dart`, `test/features/catalog/*`, `test/features/scanner/*`
- **Modified:**
  - Functions: `functions/src/index.ts`, `functions/package.json` (+zod, scripts), `functions/eslint.config.mjs`
  - App: `app/lib/{app/providers.dart, app/router/app_router.dart, app/router/routes.dart, bootstrap.dart, core/database/{tables,app_database}.dart, core/firebase/firebase_options_dev.dart, features/search/presentation/search_screen.dart, l10n/app_en.arb}`, `app/pubspec.yaml` (+cloud_functions, mobile_scanner; dev +fake_async, sqlite3), `app/android/{gradle.properties, app/src/main/AndroidManifest.xml}`, `app/ios/Runner/Info.plist`, `app/test/helpers/test_app.dart`
  - Repo: `.github/workflows/ci.yml` (integration tests), `docs/03-data-architecture.md`, `docs/04-integrations.md`, `PROJECT_STATUS.md`
- **Deleted:** `functions/test/fixtures/openlibrary_author_works.json`, replaced by `openlibrary_author_search.json`.

**Verification (all executed 2026-11-04)**

| Check | Result |
|---|---|
| App: `dart format --set-exit-if-changed` / `flutter analyze` / `flutter test` | ✅ 0 changes / no issues / **106 passed** |
| Functions: lint / typecheck / build / `npm test` | ✅ / ✅ / ✅ / **57 passed** |
| Firestore emulator: rules tests + catalog store integration tests | ✅ **12 + 4 passed** |
| Live smoke of callables (Functions emulator → live Open Library) | ✅ unauthenticated callers rejected; invalid input rejected with field errors; search ~3.3 s; first ISBN lookup ~7.4 s (merged, 16 editions, provenance), repeat 0.2 s; trending OK |
| Dev APK build | ✅ |
| Manual end to end on the Android emulator | ✅ live trending covers → search "the deal elle kennedy" → book detail (cover, author link, "Part of Off-Campus", 392 pages, description, genres) → author screen (photo + credit, dates, clean bio, books ordered by popularity with covers) |

**Acceptance criteria:**
- ✅ AC1–AC8.
  - AC2: Hardcover and Google fixtures are schema-built; see W9 and W10.
- ⚠️ AC9 (physical barcode scan under 10 s) **unverified**: no camera device here. The flow is covered by widget tests through a camera seam, and the server lookup takes about 7 s on first lookup.
- "Add to library" and duplicate detection against the library are deliberately moved to Phase 4 (TD-21).

**Bugs found and fixed during the phase** (before any commit, so no BUG tickets):
1. Manual ISBN entry: the entry sheet's `pop()` dismissed the "found" sheet opened above it.
2. The Android Functions SDK rejected the demo API key format.
3. Riverpod 3's default auto-retry looped failed callables, which would burn rate limits.
4. The Gradle `-Xmx8G` template default got the daemon killed on this 8 GB machine.
5. Open Library bios showed raw HTML and Markdown.
6. The author "Books" list showed recent translations without covers.
7. No page count when a work was opened from search.

**Warnings / known limitations**
- W9: Hardcover is implemented from its documentation but not verified live (`SPIKE-88083021`).
- W10: Google Books is disabled until a key exists; its fixtures are schema-built.
- W11: Without Hardcover there are no series entities, so the series name isn't tappable.
- W12: AC9 needs a physical-device scan test.
- W13: The first ISBN lookup takes about 7 s, because Open Library needs chained calls (cached afterwards).
- W14: On this machine the Functions emulator needs `FUNCTIONS_DISCOVERY_TIMEOUT=60`, and the Firestore emulator must run outside the sandbox.
- W15: Firestore TTL policies for `catalog_searchCache` and `ops_rateLimits` (`expiresAt`) must be configured in the console after B1.
- W16: The "Popular this week" heading is fixed text but uses Open Library's *daily* trending feed.

**Remaining tasks:** `SPIKE-88083021` (Hardcover token and permission), a Google Books key, a device scan test, and the TTL policies after B1.

**Recommended next phase:** Phase 4 — Library, Editions & Progress (includes "Add to library" and library duplicate detection).

### 2026-11-04 — Phase 2: Foundation (COMPLETED WITH WARNINGS — approved by you)

**Implemented**
- Monorepo: `app/` (Flutter 3.41.9, Android + iOS, `dev`/`prod` flavors), `functions/` (TypeScript), `firebase/` (rules, indexes, storage rules), `firebase.json`, `.firebaserc` (`demo-chapter`), root `.gitignore`, `.github/workflows/ci.yml`.
- Core: `Result`/`Failure`, `Clock`, UUIDv7 `IdGenerator`, HLC, per-field `LwwDocument`.
- Local persistence: Drift `AppDatabase` (one file per uid) with `lww_documents`, `outbox_entries`, `sync_meta`.
- Sync: `LwwStore` (local write and outbox entry in one transaction), `SyncEngine` (ordered single-flight push, backoff with jitter, dead-letter queue, pull-merge, status stream), `FirestoreSyncRemote` (server-side LWW merge in a transaction; `permission-denied` goes to the dead-letter queue).
- Design system: colour, type, spacing, radius, motion tokens; light and dark `ChapterTheme`; ChapterButton, ChapterTextField, BookCover (monogram fallback), BookGridCard, BookListTile, ContinueReadingCard, progress bar and ring, ChapterNavBar (emphasised Read), sheet and confirm dialog, Empty/Error/Loading states, RatingStars (half stars), SyncBadge, ApproximateBadge. English l10n (ARB).
- Auth: `AuthRepository` + `FirebaseAuthRepository` (Google via google_sign_in 7 → Firebase credential; Apple via `AppleAuthProvider`; emulator-only test account), sign-in controller, splash, sign-in, onboarding (analytics consent off by default).
- Profile: `UserPreferences` (Freezed, tolerant parsing), `LwwProfileRepository`, Profile screen (identity, sync badge, theme, consents, sign-out with an unsynced-changes warning).
- Navigation: GoRouter with a pure, unit-tested `redirectFor` guard (splash, sign-in, onboarding, deep-link `from`), 5-tab `StatefulShellRoute` (Home · Library · Read · Search · Profile). Library, Read and Search show honest empty states until their phases.
- Bootstrap: flavor entry points, emulator wiring, Firestore persistence off, App Check (prod), telemetry disabled until consent (prod builds only).
- Rules: owner-only `users/{uid}` with field allow-list, types and ranges, required `fieldClock` and server `updatedAt`, no client delete; sub-collections denied; catalog read-only; everything else denied.
- Functions: TypeScript project (strict, ESLint, Vitest), `requireUid` helper, emulator rules test suite. No deployed functions yet.

**Files**
- Created: `.firebaserc`, `.gitignore`, `.github/workflows/ci.yml`, `firebase.json`, `firebase/{firestore.rules, firestore.indexes.json, storage.rules}`, `functions/{package.json, package-lock.json, tsconfig.json, tsconfig.build.json, eslint.config.mjs, src/index.ts, src/shared/auth.ts, src/shared/auth.test.ts, test/rules/firestore.rules.test.ts}`, and the `app/` project: `pubspec.yaml`, `pubspec.lock`, `analysis_options.yaml`, `l10n.yaml`, `README.md`, Dart sources under `lib/` (incl. `l10n/app_en.arb`), 14 test files under `test/`, Android flavor config (`android/app/build.gradle.kts`, `android/settings.gradle.kts`, `src/main/AndroidManifest.xml`, `src/dev/AndroidManifest.xml`, `src/dev/res/xml/network_security_config.xml`), plus `flutter create` platform scaffolding (android/ios).
- Modified: `docs/02-system-architecture.md` (TD-12, TD-13), `docs/03-data-architecture.md` (TD-14), `PROJECT_STATUS.md`.
- Deleted: template `app/lib/main.dart`, `app/test/widget_test.dart` (never committed).
- Dependencies (app): flutter_riverpod 3.3, go_router 17.5, freezed_annotation 3.1, json_annotation, firebase_core 5.1, firebase_auth 7.0, google_sign_in 7.2, cloud_firestore 7.1, firebase_app_check 0.5, firebase_analytics 13, firebase_crashlytics 6, drift 2.34, drift_flutter 0.3, meta, uuid 4.6, intl 0.20.2, connectivity_plus 7.3, cached_network_image 3.4. Dev: build_runner, freezed, json_serializable, drift_dev, mocktail. Functions: firebase-admin 13, firebase-functions 6; dev: typescript, eslint 9, typescript-eslint, vitest 3, @firebase/rules-unit-testing 4, firebase 11.

**Verification (all actually executed on 2026-11-04)**

| Command | Result |
|---|---|
| `dart format --set-exit-if-changed lib test` | ✅ 0 changes |
| `flutter analyze` | ✅ No issues |
| `flutter test` | ✅ 75 passed (HLC, LWW, Result, sync engine with 2 simulated devices, profile repo, preferences, redirect guard, design system in light/dark at 1×/2×, WCAG contrast, full app flows) |
| `npm run lint` / `typecheck` / `build` / `test` (functions) | ✅ all pass (2 unit tests) |
| `firebase emulators:exec … test:rules` | ✅ 12 rules tests passed |
| `flutter build apk --debug --flavor dev -t lib/main_dev.dart` | ✅ `app-dev-debug.apk` (after the Kotlin 2.3.0 / compilerOptions fixes) |
| Manual end to end on the Android emulator (Galaxy S23 AVD) + Auth/Firestore emulators | ✅ sign-in screen → emulator test sign-in → onboarding → Home ("Good evening, Test", 5-tab nav). `users/{uid}` arrived in Firestore with field clocks, accepted by the real rules. |

**Acceptance criteria:** AC1 ✅ · AC2 ✅ · AC3 ✅ (widget render tests in both themes at 2× text; *no pixel golden files*, see W3) · AC4 ✅ · AC5 ✅ · AC6 ✅ · AC7 ✅ · AC8 ✅ · AC9 ⛔ BLOCKED (B1).

**Bugs found and fixed during the phase** (caught before any commit, so no BUG tickets): `SyncEngine.flush()` returned before an in-flight push finished; `ErrorState` overflowed at 2× text; user-scoped providers threw during the sign-out transition.

**Warnings / known limitations**
- W1: Real Google/Apple sign-in is unverified until the Firebase projects exist (B1). `firebase_options_prod.dart` deliberately fails fast.
- W2: iOS was not built or run (Windows host; `SPIKE-29567026`). The iOS dev bundle id and the Apple capability are not configured yet.
- W3: Design-system tests are render/overflow/semantics tests, not pixel golden files (goldens differ by host OS; to add once CI is the reference renderer).
- W4: Fonts use the platform serif/sans; bundling Literata/Inter (OFL) needs your OK to download font files.
- W5: First sign-in on a second device can show onboarding again before the server profile arrives (it converges by LWW afterwards). Revisit with the Phase 4 initial-pull work.
- W6: The Firestore emulator JVM crashes inside the Claude Code sandbox on this machine and runs fine outside it. CI is unaffected.
- W7: Android SDK licenses are still unaccepted (B2) but didn't block the debug build. Release builds may need them.
- W8: The Kotlin daemon logs "could not close incremental caches" on Windows (project on D:, Gradle cache on C:). Harmless; the build falls back and succeeds.

**Remaining tasks:** resolve B1 (create Firebase projects, run `flutterfire configure`, SHA-1s, OAuth client), the iOS CI spike, a decision on font bundling, the Hardcover permission spike before Phase 3.

**Recommended next phase:** Phase 3 — Discovery (start with the provider layer behind `SPIKE-88083021`).

### 2026-11-04 — Phase 1: Architecture (COMPLETED)
- **Work:** Phase 1 deliverables (PRD, architecture, folder structure, Firestore and Drift schema, Dart models, integration architecture, navigation, dependencies, security and offline strategy, roadmap, API-restriction analysis). Approved by you with no changes.
- **Files created:** `docs/01-product-requirements.md`, `docs/02-system-architecture.md`, `docs/03-data-architecture.md`, `docs/04-integrations.md`, `docs/05-security-and-offline.md`, `docs/06-roadmap.md`, `PROJECT_STATUS.md`.
- **Files modified:** the same docs, to record approvals and add tracking IDs.
- **Tests executed:** none. This phase was documentation only, and no code exists.
- **External records:** Flowboard workspace `WKSP-59039244`, project `PRJ-94436488`: 8 Chronicle docs (00–07), 3 releases, 8 sprints (S0 completed), 8 epics, 25 stories, 2 spikes, dependency links.
- **Known problems:** none in the code. Third-party risks R1–R8 are listed in docs/06.
- **Remaining:** Phase 2, on hold until you say to start.

### 2026-11-04 — Governance adoption
- **Work:** adopted the `chapter-phase-guard` lifecycle. Restructured this tracker into the required sections A–E and mapped the skill's 13 generic phases onto the approved 8-phase roadmap.
- **Files modified:** `PROJECT_STATUS.md`. (`.claude/skills/chapter-phase-guard/SKILL.md` was added by you.)
- **Tests executed:** none (documentation only).

---

## Project tracking IDs (Flowboard / Chronicle)

Workspace **Chapter** `WKSP-59039244` · Project **Chapter App** `PRJ-94436488`.

| Item | IDs |
|---|---|
| Chronicle docs | 00 Master brief `DOC-90691931` (Chronicle only) · 01 `DOC-36659258` · 02 `DOC-95881978` · 03 `DOC-64935784` · 04 `DOC-94477985` · 05 `DOC-12011711` · 06 `DOC-64928677` · 07 Project Status `DOC-70718024` · 08 Phase 2 report `DOC-23098336` · 09 Phase 3 report `DOC-64497171` · 10 Phase 4 report `DOC-52039370` · 11 Phase 5 report `DOC-22015742` · 12 Phase 6 report `DOC-11433631` · 13 Phase 7 report `DOC-81505952` · 14 Phase 8 report `DOC-41775005` · 15 Issues & Bugs Register `DOC-15970246` |
| Phase 8 stories | Export and deletion `US-04422663` (DONE) · Release hardening `US-80940502` (backlog: blocked on B1 and B3) |
| Phase 7 stories (DONE) | Audible and Kindle `US-28320381` · CSV import `US-14073275` · Spotify `US-88150897` |
| Phase 6 stories (DONE) | Goals `US-98201131` · Insights `US-92210602` · Notes and ratings `US-22523306` · Carry-overs `US-06658059` |
| Phase 5 stories (DONE) | Timer `US-40867577` · Summary and history `US-45232030` · Focus mode `US-10916362` |
| Phase 4 stories (DONE) | Sync collections `US-28172966` · Add + duplicates `US-82936892` · Library `US-97438512` · Work/Edition progress `US-75781175` · Progress sheet `US-62202456` · Continue Reading `US-57758694` |
| Phase 3 stories | Providers `US-52329946` · Merge/identity `US-24121525` · Search `US-89913727` · Book/author/series `US-51229985` · Scanner `US-87648119` |
| Phase 2 stories | Scaffold `US-62742777` · Firebase setup `US-11492374` · Sign-in `US-81077474` · Design system `US-65026969` · Router shell `US-22505491` · Drift/sync skeleton `US-76698562` · Rules + CI `US-54762351` |

Bugs are logged as `BUG-` tickets with a root-cause analysis (RCA) once code exists.

## Git state

| | |
|---|---|
| Branch | `main` |
| Remote | `origin`: `MatrimPathak/chapter` (public) |
| Plan (agreed 2026-11-06) | Public repo `MatrimPathak/chapter`; no licence granted, all rights reserved; author `Matrim Pathak`, GitHub noreply email |
| Publishing | Granted by you on 2026-11-06 for the first publish only. Later changes need approval again. |

## Environment notes

- Toolchain found: Dart 3.11.5, Firebase CLI 15.16.0, Node 25.9.0. Flutter is installed (an upgrade is available). Functions will target the Node 22 runtime.
- Development is on Windows, so iOS builds need macOS CI (`SPIKE-29567026`).
