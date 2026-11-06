# 06 — Implementation Roadmap

✅ Approved 2026-11-04. Mirrored in Chronicle (`DOC-64928677`).

Each phase ends with: green CI (analyze, unit/widget tests, functions tests, rules tests), a demoable build, and an updated `PROJECT_STATUS.md`. I'll wait for your sign-off at the end of each phase.

| Phase | Sprint / Epic | Milestone | Deliverables | Exit criteria |
|---|---|---|---|---|
| **1** ✅ | S0 `SPR-42047023` / `EPIC-71627278` | Architecture | Docs 01–06, PROJECT_STATUS | Approved 2026-11-04 |
| **2** | S1 `SPR-23171703` / `EPIC-44901932` | Foundation | Monorepo scaffold. Flutter app with `dev`/`prod` flavors. Two Firebase projects with flutterfire config. App Check. Google Sign-In and Apple on iOS. Auth guard and router shell with 5 tabs. Design tokens, light and dark themes, core components (button, input, cover, card, progress, nav bar, sheet, dialog, empty/error/loading states). Drift database (per-uid file), migrations harness. Outbox, HLC and SyncEngine skeleton with profile and preferences sync working end to end. Firestore rules with tests. Functions project (TypeScript), emulator setup. CI workflow. | Sign in and out on Android. Profile syncs across 2 devices or emulators. Rules tests pass. Golden tests for the core components. |
| **3** | S2 `SPR-98903782` / `EPIC-18960125` | Discovery | Server: `BookMetadataProvider` and the 3 providers, orchestrator, merge with provenance, identity/dedupe, catalog persistence, search cache, rate limiting. App: search (debounce, suggestions, pagination, recents, states), book detail, author and series screens, ISBN scanner with validation and confirmation, duplicate detection, Open Library trending. | Search works with Hardcover disabled. Scanning a real book adds it in < 10 s. Merge unit tests run against recorded fixtures. |
| **4** | S3 `SPR-37736430` / `EPIC-56567522` | Library and editions | Library entries, statuses and flags; grid and list views; sort, filter and search; Continue Reading on Home. Work/edition switching, UserEdition overrides, ReadThroughs and rereads. ProgressEvent log, progress sheet (page, percentage, slider, audio time), ProgressMapper (proportional, calibrated, unknown length), "Mark as Read" at 100 %, estimated completion date. | Offline add and progress changes sync without loss (integration test with a forced conflict). Unified progress is correct across formats in unit tests. |
| **5** | S4 `SPR-95482499` / `EPIC-67485420` | Reading experience | Timer with presets and custom duration, pause and resume, timestamp-based durability, crash recovery, end notification, editable session summary, session history, Android DND via `AutomaticZenRule`, iOS fallback focus screen, active session bar. | Killing the app mid-session and relaunching recovers it exactly. DND is restored in all exit paths. |
| **6** | S5 `SPR-77033075` / `EPIC-36313679` | Goals and insights | Goals (year, month, custom; books, pages, minutes) with history. StatsEngine with minimum-data thresholds. Calendar heatmap. Charts (monthly trend, weekday activity, top authors and genres), yearly summary, streaks (shown neutrally). Notes and quotes with anchors, ratings and reviews. | StatsEngine tests cover empty, sparse and dense data. No NaN or misleading values. |
| **7** | S6 `SPR-71995979` / `EPIC-20596928` | Integrations | Integration framework. Audible: manual audiobook editions and progress, open-in-app. Kindle `My Clippings.txt` import. Goodreads and StoryGraph CSV import. Spotify Tier A deep-link playlists, Tier B behind a feature flag. | Each integration can fail independently without affecting core features (fault-injection tests). |
| **8** | S7 `SPR-01414265` / `EPIC-07850843` | Quality and release | Offline soak tests, a full rules audit, performance profiling (startup, list scrolling with 2k books), accessibility pass (TalkBack, VoiceOver, dynamic type), JSON and CSV export, account deletion, privacy policy, store listings, prod config, Crashlytics, release signing. | Non-functional requirement targets met (doc 01 §6). Store submission ready. |

## Releases

| Release | ID | Phases | Target date |
|---|---|---|---|
| v0.1.0-alpha | `RLS-90193041` | 2–4 | 2026-12-20 |
| v0.2.0-beta | `RLS-56098621` | 5–6 | 2027-01-17 |
| v1.0.0 | `RLS-88037731` | 7–8 | 2027-02-14 |

The dates are tentative (2-week sprints).

## Testing strategy (cross-phase)

- **Domain unit tests:** ProgressMapper, merge rules (TypeScript), StatsEngine, HLC, ConflictPolicy, ISBN validation, session clock. Target ≥ 90 % coverage of the domain layer.
- **Repository tests:** in-memory Drift (`NativeDatabase.memory()`) with a fake remote.
- **Widget and golden tests:** design-system components in light and dark themes and at 2× text scale.
- **Integration tests:** `integration_test` against the Firebase Emulator Suite (Auth, Firestore, Functions) for sign-in, add book, offline progress, sync and conflict.
- **Rules tests:** `@firebase/rules-unit-testing` for every collection, covering both allowed and denied cases.
- **Provider tests:** recorded HTTP fixtures, with no live calls in CI. A separate manual "live smoke" script.

## Risks register

| ID | Risk | Impact | Mitigation |
|---|---|---|---|
| R1 | App Store guideline 4.8: Google login requires an equivalent privacy-focused option | iOS rejection | Sign in with Apple (approved, Phase 2) |
| R2 | Hardcover API terms, beta instability, 60 requests/min, yearly token expiry | Loss of the primary provider | Fallback chain, aggressive caching, ask Hardcover for permission (`SPIKE-88083021`), calendar reminder to rotate the token on January 1 |
| R3 | Blaze plan required for Functions and Secret Manager | Cost and billing account needed | Approved. Budget alerts. Expected cost is near zero at small scale. |
| R4 | Development is on Windows, so iOS builds need macOS | Can't build or test iOS locally | Cloud CI with macOS runners (Codemagic or GitHub Actions) — `SPIKE-29567026` |
| R5 | Spotify Extended Quota unlikely | Account features limited to 5 users | Tier A deep links as the default (approved) |
| R6 | The sync engine is custom code | Data-loss bugs | Append-only logs, outbox in the same transaction, extensive conflict tests, dead-letter queue instead of dropping data |
| R7 | Metadata quality and series gaps | Wrong series order or page counts | Provenance, user overrides in user space, report-issue path |
| R8 | Provider cover hotlinking and licensing | Broken or disallowed images | Use the providers' sanctioned cover URLs, device cache, monogram fallback |
