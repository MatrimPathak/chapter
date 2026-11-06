# 02 — System Architecture, Folder Structure, Navigation, Dependencies

## 1. High-level architecture

```
┌──────────────────────────── Flutter app ─────────────────────────────┐
│  Presentation  (screens, widgets, Riverpod Notifiers)                │
│        │ watches                                                     │
│  Domain        (entities, repository interfaces, domain services:    │
│                 ProgressMapper, MetadataMerge rules, StatsEngine,    │
│                 SessionClock, IsbnValidator)                         │
│        │ implemented by                                              │
│  Data          (repositories → Drift DAOs  +  Outbox  +  remote DS)  │
│        │                         │                                   │
│   ┌────▼─────┐            ┌──────▼──────┐        ┌───────────────┐   │
│   │  Drift   │◄──pull─────│ SyncEngine  │──push─►│ Firestore SDK │   │
│   │ (SQLite) │  (apply)   │ (outbox,HLC)│        └───────┬───────┘   │
│   └──────────┘            └─────────────┘                │           │
│        ▲ single source of truth for UI                   │           │
│   CatalogRemoteDS ── callable ──────────────────────┐    │           │
└─────────────────────────────────────────────────────┼────┼───────────┘
                                                      │    │
                 ┌────────────────────────────────────▼────▼──────────┐
                 │ Firebase                                           │
                 │  Auth · App Check · Firestore · Cloud Functions    │
                 │  Analytics (opt-in) · Crashlytics                  │
                 │                                                    │
                 │  Cloud Functions (TypeScript, Node 22):            │
                 │   catalog.search / lookupIsbn / getWork /          │
                 │   getAuthor / getSeries / refreshWork              │
                 │   account.delete  · scheduled cache cleanup        │
                 │      │                                             │
                 │   MetadataOrchestrator                             │
                 │     ├─ HardcoverProvider   (GraphQL, secret token) │
                 │     ├─ OpenLibraryProvider (REST, no key)          │
                 │     └─ GoogleBooksProvider (REST, secret key)      │
                 └────────────────────────────────────────────────────┘
```

### Key decisions

| # | Decision | Why |
|---|---|---|
| D1 | **The metadata provider implementations run in Cloud Functions (TypeScript), not in the app.** | Hardcover's terms require its token to be used only from a backend. Google Books needs an API key. Rule 4 forbids secrets in the client. A server-side orchestrator also gives a shared catalog cache, global rate limiting against Hardcover's 60 requests/minute limit, and lets providers change without an app release. The `BookMetadataProvider` interface lives server-side. The app depends on a `CatalogRepository` abstraction. **Consequence: the Firebase Blaze (pay-as-you-go) plan is required (approved).** |
| D2 | **Drift is the single source of truth for all UI.** Firestore is a sync target, not something the UI reads. | Statistics, filters and sorts need relational queries offline. Firestore's offline cache can't do aggregation or joins, and its eviction is opaque. One local store avoids two caches drifting apart. Firestore's own offline persistence is **disabled** to avoid storing everything twice. The outbox guarantees offline writes are kept. |
| D3 | **A transactional outbox plus a hybrid logical clock (HLC)** for sync. | Every local mutation and its outbox entry are written in one SQLite transaction, so no change can be lost. The HLC gives a total order across devices even when device clocks are skewed. |
| D4 | **Append-only logs for progress and sessions.** | `ProgressEvent` and `ReadingSession` are never updated in place, so merging is a set union with no conflicts. "Current progress" is a projection of the latest event. History survives rereads and metadata refreshes. |
| D5 | **Work and Edition are separate aggregates.** User data hangs off the Work. Edition-specific numbers (pages, duration) live on the Edition. | This is required for unified progress and multi-format reading. |
| D6 | **User corrections live in user space, never in the global catalog.** | A provider refresh can never overwrite a user's corrected page count or edition data, and one user's edit can't affect another user. |
| D7 | **App Check is enforced on all callables, with per-user rate limits.** | Prevents quota abuse of the metadata providers. |
| D8 | **Feature-first Clean Architecture without ceremonial use-case classes.** | A use-case class is created only when logic spans repositories (for example `CompleteSessionUseCase`). Simple CRUD goes directly from Notifier to Repository. Less boilerplate, still testable. |

## 2. Layer rules

- `presentation` → `domain` only. Widgets never import `data`, Drift or Firebase.
- `domain` → pure Dart. No Flutter, Firebase or Drift imports, so it is 100 % unit-testable.
- `data` → `domain` and `core`. Implements the repository interfaces.
- Features never import another feature's `data` or `presentation`. Cross-feature use goes through `domain` interfaces exposed by providers.
- Errors: repositories return `Result<T, Failure>` (a sealed class). Exceptions never cross a layer boundary.
- Time: inject `Clock`. `DateTime.now()` is not allowed in domain or data, which keeps the timer, statistics and the HLC testable.

## 3. Repository layout (monorepo)

```
Chapter/
├── app/                         Flutter application
├── functions/                   Cloud Functions (TypeScript)
├── firebase/
│   ├── firestore.rules
│   ├── firestore.indexes.json
│   └── storage.rules            (deny-all until needed)
├── firebase.json / .firebaserc  (aliases: dev, prod)
├── docs/                        architecture docs (this folder)
└── PROJECT_STATUS.md
```

## 4. Flutter folder structure (`app/lib`)

```
lib/
├── main_dev.dart                  flavor entry → bootstrap(Flavor.dev)
├── main_prod.dart
├── bootstrap.dart                 Firebase init, Crashlytics zone, ProviderScope
├── app/
│   ├── app.dart                   MaterialApp.router, theme, l10n
│   ├── flavor.dart
│   └── router/
│       ├── app_router.dart        GoRouter + redirect guard
│       ├── routes.dart            typed route constants / builders
│       └── scaffold_with_nav.dart StatefulShellRoute shell + mini session bar
├── core/
│   ├── design_system/
│   │   ├── tokens/                colors, typography, spacing, radii, elevation, motion
│   │   ├── theme/                 ChapterTheme (ThemeExtension), light/dark ThemeData
│   │   └── components/            ChapterButton, ChapterTextField, BookCover,
│   │                              BookCard(grid/list/continue), ProgressBar/Ring,
│   │                              ChapterNavBar, ChapterSheet, ChapterDialog,
│   │                              EmptyState, ErrorState, LoadingSkeleton, RatingStars,
│   │                              SyncBadge, ApproximateBadge
│   ├── database/                  AppDatabase (Drift), tables/, daos/, migrations/
│   ├── sync/                      SyncEngine, Outbox, Hlc, RemoteMapper,
│   │                              ConflictPolicy, SyncStatusNotifier
│   ├── firebase/                  firebase_options_{dev,prod}.dart, app_check
│   ├── network/                   CallableClient, RetryPolicy, error mapping
│   ├── error/                     Failure (sealed), Result
│   ├── analytics/                 AnalyticsService (consent-gated), event names
│   ├── l10n/                      ARB files
│   └── utils/                     Clock, IdGenerator(uuid v7), Isbn, Debouncer, logger
└── features/
    ├── auth/        {data, domain, presentation}   sign-in, auth state, reauth
    ├── home/        presentation only (composes other features' providers)
    ├── catalog/     {data, domain, presentation}   search, book detail, author,
    │                                                series, editions browser
    ├── scanner/     {domain, presentation}          camera, ISBN parse, confirm
    ├── library/     {data, domain, presentation}   entries, statuses, flags, filters
    ├── progress/    {data, domain, presentation}   events, read-throughs, ProgressMapper
    ├── reading/     {data, domain, presentation}   timer, sessions, focus/DND, summary
    ├── notes/       {data, domain, presentation}
    ├── goals/       {data, domain, presentation}
    ├── insights/    {domain, presentation}          StatsEngine, calendar, charts
    ├── integrations/{data, domain, presentation}   audible, kindle_clippings,
    │                                                spotify, csv_import
    └── profile/     {data, domain, presentation}   prefs, export, account deletion

test/               mirrors lib/ (unit + widget)
integration_test/   end-to-end flows against the Firebase Emulator Suite
android/app/src/main/kotlin/.../FocusModeChannel.kt   DND platform channel
```

### Functions layout (`functions/src`)

```
src/
├── index.ts                     exports
├── catalog/
│   ├── providers/
│   │   ├── BookMetadataProvider.ts   interface
│   │   ├── hardcover/               client.ts, queries.graphql.ts, mapper.ts
│   │   ├── openLibrary/
│   │   └── googleBooks/
│   ├── orchestrator.ts             fan-out, failover, circuit breaker
│   ├── merge.ts                    field-level merge + provenance
│   ├── identity.ts                 dedupe / resolve internal IDs
│   ├── cache.ts                    searchCache + catalog persistence
│   └── callables.ts                search, lookupIsbn, getWork, getAuthor, getSeries
├── account/deleteAccount.ts
├── shared/                         rateLimiter, appCheck, validation (zod), logger
└── test/                           vitest + recorded provider fixtures
```

## 5. State management (Riverpod)

- Hand-written Riverpod 3 providers (`Provider`, `StreamProvider`, `NotifierProvider`). **Phase 2 deviation:** `riverpod_generator` was dropped because its `analyzer` requirement conflicts with `drift_dev`; the provider API is the same without codegen.
- Drift `watch()` streams are exposed as `StreamProvider`s, so the UI updates reactively after local writes and after the sync engine applies pulled data.
- Scoping: `currentUserIdProvider` is the root. All user-data providers depend on it, so they are disposed and rebuilt on sign-out or sign-in. Each user gets **a separate Drift database file per uid**, which makes sign-out isolation trivial.
- Long-lived services (`SyncEngine`, `SessionController`) are `keepAlive` providers.

## 6. Navigation architecture (GoRouter)

```
/splash                         auth state resolving
/sign-in
/onboarding                     goal + privacy consent (first run)

StatefulShellRoute.indexedStack (bottom nav, state preserved per tab)
├── /home
├── /library
├── /read                               Focus tab: pick book, presets, history
├── /search
│     └── /search/scan                  (fullscreen, root navigator)
│           └── /search/scan/confirm?isbn=
└── /profile
      ├── /profile/goals      (implemented as root route /goals, likewise /insights)
      ├── /profile/insights   ── /profile/insights/calendar
      ├── /profile/preferences
      ├── /profile/connections
      ├── /profile/export
      └── /profile/account

Global (root navigator, reachable from any tab):
/book/:workId                     ?tab=overview|editions|notes|history
/book/:workId/progress            (sheet)
/book/:workId/notes/:noteId
/author/:authorId
/series/:seriesId
/session/active                   fullscreen timer
/session/:sessionId/summary
```

- **Redirect guard:** unauthenticated users go to `/sign-in`. Authenticated users without onboarding go to `/onboarding`. Deep links are preserved through `from=`.
- **Active session bar:** while a session runs, a compact bar above the nav bar in the shell shows the book and remaining time. Tapping it opens `/session/active`. On cold start, recovering an unfinished session routes to `/session/active`.
- **Bottom nav order (approved):** Home · Library · **Read** (centre, emphasised) · Search · Profile. Read sits in the thumb-reachable centre because the core loop is "read"; Search is still one tap away. (Approved 2026-11-04.)

## 7. Dependency list

Versions are resolved to the latest stable when Phase 2 starts and then pinned in `pubspec.lock`.

### App: runtime

| Package | Justification |
|---|---|
| `flutter_riverpod`, `riverpod_annotation` | State management and dependency injection, as required. |
| `go_router` | Required. Declarative routing, `StatefulShellRoute`, redirect guards, deep links. |
| `freezed_annotation`, `json_annotation` | Immutable models, sealed unions (`ReadingPosition`, `Failure`), JSON. |
| `firebase_core`, `firebase_auth` | Auth. |
| `google_sign_in` | Google provider (v7 API, `authenticate()`). |
| ~~`sign_in_with_apple`~~ | **Not needed (Phase 2):** Sign in with Apple uses `firebase_auth`'s built-in `AppleAuthProvider`, so no extra package. |
| `cloud_firestore` | Sync target. |
| `cloud_functions` | Catalog callables and account deletion. |
| `firebase_app_check` | Protects callables and provider quotas from abuse. |
| `firebase_analytics`, `firebase_crashlytics` | Required. Consent-gated. |
| `drift`, `drift_flutter` | Local relational database with reactive queries and migrations. `drift_flutter` bundles sqlite3 and handles paths. |
| `mobile_scanner` | Barcode scanning (ML Kit on Android, Vision on iOS). Handles the camera permission itself, so `permission_handler` is not needed for this. |
| `flutter_local_notifications`, `timezone` | Timer-end notification scheduled with exact timestamps, so it works even if the app is killed. Ongoing-session notification. |
| `cached_network_image` | Disk-cached covers, so covers show offline. |
| ~~`fl_chart`~~ | Not used: Insights bars are plain widgets styled with tokens (PROJECT_STATUS TD-37). |
| `intl` | Date, number and plural formatting, and l10n. |
| `uuid` | UUIDv7 (time-ordered) client IDs, required for offline creation. |
| `connectivity_plus` | A hint that triggers sync attempts. The real signal is the result of a sync. |
| `share_plus` | Hands export files to the system share sheet. |
| `url_launcher` | Spotify and Audible deep links, the privacy policy. |

**Deliberately excluded:** `google_fonts` (fonts are bundled as assets, so they work offline with no runtime fetch to Google), `dio`/`http` (the app makes no direct HTTP calls; everything goes through Firebase), `permission_handler` (not needed yet), `get_it` (Riverpod already does DI), `hive`/`isar` (Drift covers this), `firebase_storage` (no user uploads in v1; profile photos come from the auth provider).

### App: dev

`build_runner`, `freezed`, `json_serializable`, `drift_dev`, `flutter_lints` (plus stricter project rules), `mocktail`, `flutter_test`, `integration_test`.

### Functions

`firebase-functions`, `firebase-admin`, `zod` (input validation). Uses Node 22's native `fetch`, so no axios or GraphQL client library. Dev: `typescript`, `vitest`, `@firebase/rules-unit-testing`, `eslint`.

## 8. Environments

| Flavor | Firebase project | Notes |
|---|---|---|
| `dev` | `chapter-dev` | Emulator Suite for local development and tests. Debug App Check provider. |
| `prod` | `chapter-reads-prod` | Play Integrity / App Attest. Analytics consent required. |

Separate `firebase_options_*.dart` are generated by `flutterfire configure` for each flavor. Android `productFlavors` and iOS schemes map to the entry points. Provider secrets (`HARDCOVER_TOKEN`, `GOOGLE_BOOKS_KEY`) live in **Cloud Secret Manager** through `defineSecret`, never in the repository.
