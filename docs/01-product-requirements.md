# 01 — Product Requirements Document

**Product:** Chapter
**Tagline:** Your reading life, in one place.
**Status:** v1. ✅ Approved 2026-11-04.
**Platforms (v1):** Android and iOS phones. Tablet layouts are responsive. Web and desktop are out of scope for v1, but the architecture does not prevent them.

---

## 1. Vision

Chapter is a calm, private reading companion. The core loop:

> **Pick a book → Read → Record a session → Update progress → Resume whenever you want.**

Every screen should help with this loop or with understanding the reader's own history. Anything else is out of scope.

## 2. Principles

1. **Covers and progress come first.** Nothing visual competes with the book.
2. **Private by default.** No social graph, feeds, followers, or public profiles.
3. **Honest data.** Approximate values are labelled as approximate. If there is too little data for a statistic, Chapter says so instead of showing a misleading number.
4. **The reader owns their data.** Full export is available at any time and offline.
5. **Works offline.** Reading happens on planes, in basements and in parks.
6. **No dark patterns.** No streak-loss guilt, no nagging notifications, no artificial badges.

## 3. Target users

| Persona | Need |
|---|---|
| **Committed reader** (30–80 books a year, mixed formats) | One place for the library, progress across Kindle, paper and audio, and an honest yearly summary. |
| **Habit builder** (wants to read more) | A low-friction timer, a gentle goal, and visible consistency without gamification. |
| **Series reader** | Correct reading order, what is owned, and what comes next. |
| **Migrating reader** (from Goodreads or StoryGraph) | Import existing history and leave again at any time. |

## 4. Scope

### 4.1 In scope for v1 (Phases 2–6 and 8)

| Area | Requirements |
|---|---|
| **Auth** | Google Sign-In through Firebase Auth, plus Sign in with Apple on iOS. Persistent sessions, logout, account deletion, display name and photo. |
| **Discovery** | Search by title, author, ISBN, series and publisher (where the provider supports it). Debounced search, suggestions, pagination, caching, and loading, empty and error states. |
| **Metadata** | A normalized Work/Edition/Author/Series model, field-level merging across providers, provenance tracking, and refreshes that never touch user data. |
| **Book details** | Cover, titles, clickable authors, description, publication information, ISBNs, series, editions, the user's status, progress, rating, notes and reading history. |
| **Author and series screens** | Biography, photo (when licensed and available), known works, books from the library, and series order, ownership and the next unread book. |
| **Library** | Want to Read, Currently Reading, Read and DNF (mutually exclusive statuses), plus Wishlist and Favorites (independent flags). Sort, filter, in-library search, grid and list views. |
| **Continue Reading** | A home-screen carousel ordered by the most recent session or progress update, with one-tap resume. |
| **Editions** | Multiple editions per work, an active edition, and unified progress across formats with labelled approximation. |
| **Barcode scanning** | ISBN-10 and ISBN-13 detection and checksum validation, provider lookup, a confirmation sheet, and duplicate detection. |
| **Progress** | Enter a page, a percentage or audio time, or use a slider. Shows pages remaining and an estimated completion date (with a confidence threshold). Supports books with unknown length. Offers to mark the book as Read at 100%. Rereads are preserved. |
| **Sessions and timer** | Presets of 15, 20, 30, 45, 60, 90 and 120 minutes, or a custom duration. Pause, resume and end. Durations are based on timestamps, survive the app being killed, complete automatically, and end with a summary the user can edit. |
| **Focus mode** | Android: an optional Do Not Disturb mode with explicit consent that restores the previous setting afterwards. iOS: a fallback focus experience (see doc 04). |
| **Goals** | Yearly, monthly and custom goals for books, pages or minutes. Goals can be edited, and past periods are kept as history. |
| **Insights and calendar** | A reading calendar, totals, averages, trends, top authors and genres, streaks, and activity by weekday. Every statistic has a minimum-data threshold. |
| **Notes and ratings** | Notes, quotes and observations with optional page or position anchors. A 0.5–5 star rating (half stars) and an optional review. |
| **Offline** | Every user-data feature works offline. Changes queue, sync when the connection returns, and show their sync status. |
| **Export** | JSON (complete) and CSV (library and sessions), generated on the device. |
| **Privacy** | Analytics are opt-in. Crash reporting can be turned off. No PII in telemetry. |

### 4.2 In scope for v1.x (Phase 7, integrations)

- **Audible:** manual linking of an audiobook edition, audio-time progress, listening duration, and opening the Audible app. **No automatic sync** (see doc 04).
- **Kindle:** manual progress by page, percentage or location; importing highlights from `My Clippings.txt`. **No automatic sync.**
- **Spotify:** curated reading playlists opened through Spotify deep links (works for every user). Account linking through the Web API only within Spotify's quota rules (see doc 04).
- **Import:** Goodreads and StoryGraph CSV exports.

### 4.3 Non-goals

Social feeds, friends, public reviews, leaderboards, badges, recommendation AI, an e-reader or audiobook player, piracy-adjacent features, scraping private accounts, and buying books inside the app.

## 5. Key user stories and acceptance criteria

| # | Story | Acceptance criteria |
|---|---|---|
| US-1 | As a reader, I scan a paperback and add it in under 10 seconds. | The camera opens from Search. A valid ISBN is detected and checksum-verified. The confirmation sheet shows the cover, title, author and edition format. If the book is already in the library, the sheet says so and offers to add this edition. One tap adds the book with Want to Read as the default status. |
| US-2 | I resume my current book from Home. | The Continue Reading card shows the cover, title, author, current/total, percentage and "last read 2 days ago". Tapping **Read** starts the timer for that book with my last-used duration. |
| US-3 | I read for 30 minutes and log progress. | The timer survives backgrounding and the app being killed. When it ends, a notification fires. The summary shows minutes, pages read, pages per hour, and old and new progress, and lets me edit them before saving. |
| US-4 | I switch from paperback to Audible. | After I change the active edition, progress converts proportionally and is labelled "≈ approximate". My history keeps both editions. |
| US-5 | I reread a book. | Starting a reread creates a new read-through. Earlier sessions, dates and progress stay visible in the reading history. |
| US-6 | I log progress on a plane. | The progress is saved locally and immediately, with a "pending sync" marker. It syncs on reconnect, and nothing is lost even if another device edited the same book. |
| US-7 | I see my year in reading. | The yearly summary shows books, pages, hours, monthly trend, top authors and genres. Any metric without enough data shows "Not enough data yet". |
| US-8 | I leave Chapter. | The export produces JSON and CSV files through the share sheet, offline. Account deletion removes all server data, after reauthentication and a typed confirmation. |
| US-9 | A metadata provider is down. | Search still returns results from the fallback providers. A degraded-mode indicator is shown only if all providers fail. |

## 6. Non-functional requirements

| Category | Target |
|---|---|
| Cold start to interactive Home | < 2.0 s on a mid-range Android device (Pixel 6a class), offline-capable |
| Search first results | p50 < 800 ms on a cache miss, < 150 ms on a cache hit |
| Progress save (local) | < 50 ms, never blocked by the network |
| Timer accuracy | ±1 s over 2 h, independent of process lifetime |
| Crash-free sessions | ≥ 99.5 % |
| Accessibility | WCAG AA contrast, dynamic type up to 200 %, full screen-reader labels, touch targets of at least 48 dp |
| Localization-ready | All strings in ARB files. English ships at launch. |

## 7. Success metrics (privacy-preserving, opt-in only)

Weekly reading sessions per active user, the share of users with at least one progress update per week, 30-day retention, and the share of scans that end in a successful add. No content-level telemetry (book titles and notes are never sent to analytics).

## 8. Product decisions (approved 2026-11-04)

1. **Sign in with Apple on iOS.** It is required by App Store Review Guideline 4.8 when Google Sign-In is offered. It ships in Phase 2.
2. **Default status on add:** Want to Read.
3. **Rating granularity:** half stars.
4. **"Did Not Finish" status:** included as an optional fourth status.
