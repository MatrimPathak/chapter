# 05 — Security & Offline Strategy

## 1. Security

### 1.1 Authentication

- Firebase Auth with Google Sign-In (`google_sign_in` v7 `authenticate()` → `GoogleAuthProvider.credential` → `signInWithCredential`). On iOS, Sign in with Apple is also offered (approved).
- Sessions persist through Firebase's default persistence. The app listens to `authStateChanges()` and treats the sign-in as gone when the ID token can't be refreshed.
- **Sensitive actions** (account deletion, data export containing an email) require reauthentication if the last sign-in is older than 5 minutes.
- Sign-out flushes the outbox if online (with a timeout). Then it **closes and detaches the per-uid Drift database**, clears image caches, and resets providers. If unsynced changes remain, the user is warned: "You have 3 changes not yet synced. Sign out anyway?" The local file is kept and will sync the next time the same user signs in.

### 1.2 Authorization

- Firestore rules: owner-only access to `users/{uid}/**`, a schema check on every write, and a read-only catalog (see doc 03 §8).
- Callables require `context.auth`, **App Check enforced**, and validate their input with zod.
- **Per-user rate limits** (token bucket in `ops_rateLimits/{uid}`): search 30/min, ISBN lookup 30/min, work fetch 60/min.
- Cloud Storage: deny-all rules until a feature needs it.

### 1.3 Secrets

| Secret | Location |
|---|---|
| Hardcover token, Google Books key | Cloud Secret Manager (`defineSecret`), only available to the catalog functions |
| Spotify client ID and secret (Tier B) | Secret Manager. The token exchange happens server-side, and tokens are stored in `private_integrations/{uid}/services/spotify` (no client access), and Unlink deletes them. The public `spotifyOAuthCallback` is protected by single-use `state`. |
| Firebase options (API key, etc.) | In the client, by design. These are identifiers, not secrets, and are protected by rules and App Check. |

The repository includes a `.gitignore` for `google-services.json`, `GoogleService-Info.plist` and any service-account JSON. A pre-commit secret scan (`gitleaks`) is recommended.

### 1.4 Input validation

- The client validates ISBN checksums, page bounds (0 to total), ratings, note lengths and goal targets in the domain layer.
- The server repeats the same checks (zod in functions, `valid*()` in rules). The client is never trusted.

### 1.5 Privacy

- **Analytics are off until the user opts in** (asked during onboarding and changeable in Preferences). `setAnalyticsCollectionEnabled(false)` is set at startup until consent is given.
- Crashlytics is on by default with an opt-out toggle. Custom keys are limited to non-content values (screen, flavor, sync queue depth).
- **No book titles, notes, search queries or emails are sent in analytics events.** Events are coarse, for example `session_completed{duration_bucket}`.
- Export: complete JSON and CSV, generated locally from Drift and shared through the share sheet, so it works offline.
- Account deletion: the `deleteAccount` callable runs `recursiveDelete(users/{uid})` and `private_integrations/{uid}`, then `auth.deleteUser`. The client then wipes the local database and caches. The deletion is irreversible and is confirmed by typing "DELETE".

### 1.5a Telemetry and backup (Phase 8)

- Crash reports carry the error type and stack only. Messages are removed (`crash_scrubber.dart`), because a SQLite error lists its parameters and a layout error can quote on-screen text.
- Analytics has four coarse events, a closed enum in `analytics.dart` with one duration bucket. A test fails if anything else sends events.
- Collection is off in the manifest and Info.plist from the first moment, not only once Dart has started.
- Android cloud backup and device transfer are off: a restored backup would bring back a deleted account's database. The iOS equivalent is written but never run (docs/07 §4).

### 1.5b Account deletion as built (Phase 8)

Order: app stops sync and waits for any push → callable checks the sign-in is under 5 minutes old (`failed-precondition` otherwise; the app reauthenticates once and retries) → server revokes refresh tokens, deletes `users/{uid}`, `private_integrations/{uid}` and the user's `ops_rateLimits` documents, then the Auth user → app marks the wipe pending, discards any session (restoring Do Not Disturb), signs out, deletes the database files and temporary files. The marker finishes the wipe on the next launch if the app is killed. Each server step can repeat safely.

**Second devices:** an ID token already issued stays valid for up to an hour, so another online device could still write. `sweepDeletedAccounts` deletes the account's documents again 65 minutes later and then removes its `deleted_accounts` record. Other devices also wipe their local copy when `user.reload()` reports the account gone, on launch and on returning to the app.

### 1.7 Rules audit (Phase 8)

Every row is covered in `functions/test/rules/firestore.rules.test.ts`, which runs against the emulator.

| Path | Owner read | Owner create/update | Hard delete | Other user | Signed out | Shape checked |
|---|---|---|---|---|---|---|
| `users/{uid}` | ✅ | ✅ valid only | ❌ | ❌ | ❌ | ✅ allow-list, clocks |
| `.../library/{id}` | ✅ | ✅ valid only | ❌ (tombstone) | ❌ | ❌ | ✅ |
| `.../readThroughs/{id}` | ✅ | ✅ valid only | ❌ | ❌ | ❌ | ✅ |
| `.../userEditions/{id}` | ✅ | ✅ valid only | ❌ | ❌ | ❌ | ✅ |
| `.../progressEvents/{id}` | ✅ | create only | ❌ | ❌ | ❌ | ✅ |
| `.../sessions/{id}` | ✅ | create only | ❌ | ❌ | ❌ | ✅ |
| `.../sessionTombstones/{id}` | ✅ | create only | ❌ | ❌ | ❌ | ✅ |
| `.../notes/{id}` | ✅ | ✅ valid only | ❌ (tombstone) | ❌ | ❌ | ✅ |
| `.../goals/{id}` | ✅ | ✅ valid only | ❌ (tombstone) | ❌ | ❌ | ✅ |
| `.../shelves/{id}` | ✅ | ✅ valid only | ❌ (tombstone) | ❌ | ❌ | ✅ |
| `.../shelfBooks/{shelfId_workId}` | ✅ | ✅ valid only | ❌ (tombstone) | ❌ | ❌ | ✅ |
| `users/{uid}/<anything else>` | ❌ | ❌ | ❌ | ❌ | ❌ | n/a |
| `users` (listing) | ❌ | | | ❌ | ❌ | |
| `catalog_*` (5 collections) | ✅ signed in | ❌ | ❌ | same | ❌ | n/a |
| `private_integrations`, `ops_*`, `catalog_searchCache`, anything else | ❌ | ❌ | ❌ | ❌ | ❌ | n/a |

Only the Admin SDK in `deleteAccount` deletes user documents.

### 1.6 Reliability

- Retries: exponential backoff with jitter (base 1 s, max 5 min) for outbox pushes. Callables get 2 retries for idempotent reads only.
- Errors are mapped to a sealed `Failure` (`network`, `unauthorized`, `rateLimited`, `notFound`, `validation`, `providerUnavailable`, `unknown`). The UI shows a human message and a retry button where it makes sense.

## 2. Offline-first design

### 2.1 Write path (never blocked by the network)

```
UI action
  → Repository.method()
     → drift.transaction {
          apply mutation to local tables      (UI updates instantly via watch())
          set row.syncState = pending
          insert outbox rows (same batchId)
          advance HLC
       }
  → SyncEngine.nudge()
```

### 2.2 Push

- Runs when nudged, on app resume, when connectivity changes, and every 5 minutes while in the foreground.
- Takes outbox rows **in order** and groups them by `batchId` into Firestore `WriteBatch`es (≤ 500 operations).
- Uses `set(merge: true)` with `updatedAt: serverTimestamp()` and the client `hlc`.
- On success, deletes the outbox rows and sets `syncState = synced`.
- On a permanent error (rules rejection), the row is moved to a quarantined `dead_letter` state and shown in Sync settings with an option to export it. The data stays in Drift and is never thrown away silently.

### 2.3 Pull

- One Firestore snapshot listener per user collection, `where('updatedAt', '>', cursor).orderBy('updatedAt')`, attached while the app is in the foreground.
- Each incoming document goes through `ConflictPolicy.resolve(local, remote)` (doc 03 §4) and is written to Drift. The cursor then advances.
- If an incoming document has a pending local outbox entry with a higher HLC, the local version wins and stays queued.

### 2.4 First sign-in on a new device

A full pull (paginated, 500 per page) behind a progress indicator. Catalog documents the user references are fetched in batches of up to 30 IDs using `whereIn`.

### 2.5 Offline catalog behaviour

- Book details, author and series pages render from cached `catalog_*` tables. Covers come from the `cached_network_image` disk cache.
- Search while offline: searches the local library and catalog cache. A banner reads "Showing saved results. Connect to search all books."
- Scanning while offline: the ISBN is validated, and if it isn't cached locally the book is added to a **"Pending lookups"** queue that resolves automatically when the connection returns.

### 2.6 Sync status UI

- A global `SyncStatus` (`synced`, `syncing`, `pending(n)`, `offline`, `error`).
- A subtle `SyncBadge` in Profile, and on any item that has pending changes.
- No banners for normal offline use. A banner appears only when there are errors needing action.

### 2.7 Timer durability

- `active_session` row: `startedAt`, `pauses[]`, `plannedEnd`, `state`. Written on every transition.
- Elapsed time = `now − startedAt − Σ pauses`. It is never accumulated by a ticking `Timer`; a ticker only repaints the UI.
- The timer-end notification is scheduled through `flutter_local_notifications.zonedSchedule` at `plannedEnd` and rescheduled on pause and resume.
- On launch, if an `active_session` exists:
  - **Past `plannedEnd`:** auto-complete with `completion = recovered`, then open the summary.
  - **Before `plannedEnd`:** resume the session screen.
- Clock sanity: if the device clock moved backwards (`now < lastTransitionAt`), elapsed time is clamped and the session is flagged for review in the summary.
