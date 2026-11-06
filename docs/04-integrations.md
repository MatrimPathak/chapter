# 04 — API Integration Architecture & Third-Party Constraints

Verified on 2026-11-04. Re-verify each provider's terms before Phase 3 and Phase 7.

## 1. Book metadata

### 1.1 Provider interface (server-side, TypeScript)

```ts
export interface BookMetadataProvider {
  readonly id: 'hardcover' | 'openLibrary' | 'googleBooks';
  readonly capabilities: ReadonlySet<
    'searchTitle' | 'searchAuthor' | 'searchIsbn' | 'searchSeries' | 'searchPublisher'
    | 'work' | 'editions' | 'author' | 'series' | 'trending'>;
  search(q: SearchQuery, page: Page, signal: AbortSignal): Promise<ProviderResult<RawWorkHit[]>>;
  lookupIsbn(isbn13: string, signal: AbortSignal): Promise<ProviderResult<RawEdition | null>>;
  getWork(externalId: string, signal: AbortSignal): Promise<ProviderResult<RawWork>>;
  getEditions(externalWorkId: string, signal: AbortSignal): Promise<ProviderResult<RawEdition[]>>;
  getAuthor(externalId: string, signal: AbortSignal): Promise<ProviderResult<RawAuthor>>;
  getSeries(externalId: string, signal: AbortSignal): Promise<ProviderResult<RawSeries>>;
}
// ProviderResult = { ok: true, data, fetchedAt } | { ok: false, error: 'unavailable'|'rateLimited'|'notFound'|'unsupported'|'invalid' }
```

Every provider has its own mapper, which turns the provider's raw format into the `Raw*` types. The orchestrator never sees provider-specific JSON.

### 1.2 Orchestration

- **Search:** query Hardcover first. If it fails, is rate-limited, or returns no results, query Open Library, then Google Books. Results come from the first provider that answers well, with a 2.5 s per-provider timeout. Capability routing: series search uses Hardcover, then Open Library (which has limited series data); publisher search uses Google Books (`inpublisher:`), then Open Library.
- **ISBN lookup:** query **all available providers in parallel** (ISBN lookups are cheap and exact), then merge the results.
- **Work detail:** start from the primary record, then *enrich* missing or low-quality fields from the other providers.
- **Circuit breaker for each provider:** after 5 consecutive failures, the provider is skipped for 60 s.
- **Hardcover budget:** one global token gets 60 requests per minute. A token bucket in each function instance (`maxInstances` kept low for the hardcover worker) plus 429 backoff. When the budget runs out, requests skip straight to Open Library. **Caching is the main defence:** search results are cached for 24 h, and work records are cached indefinitely with refreshes no more than every 30 days.

### 1.3 Field-level merge

Each field has a priority list and a quality rule.

| Field | Priority | Quality rule |
|---|---|---|
| series, seriesPosition | Hardcover > Open Library | Must have both an ID and a position. |
| pageCount (edition) | ISBN-matched edition from any provider > Hardcover > Open Library > Google | Must be between 10 and 10,000. If providers disagree by more than 15 %, prefer the value from the edition whose ISBN matches. |
| description | Hardcover > Google > Open Library | Strip HTML, require ≥ 80 characters, drop "No description available". |
| cover | Choose the largest image that loads | Prefer Hardcover's image, then the Open Library cover ID, then the Google thumbnail upgraded to `zoom=1`. |
| genres | Union, normalized to the Chapter genre vocabulary | Cap at 8. |
| authors | Hardcover > Open Library > Google | Match by provider ID, then by normalized name. |

`provenance[field] = {provider, fetchedAt}` is written for every field. A refresh re-runs the merge but **only touches catalog documents**. User data is in a separate namespace (D6), so a refresh can't reach it.

### 1.4 Identity and deduplication

The internal ID is a UUIDv7. Records resolve to the same work through `catalog_providerIndex` and `catalog_isbn`. Records are merged automatically **only on hard identifiers** (ISBN, provider ID). Fuzzy title/author matches never merge automatically, because merging two different books would corrupt user data.

### 1.5 Provider facts and constraints

| Provider | Access | Constraints that matter |
|---|---|---|
| **Hardcover** (GraphQL) | Personal API token from account settings | **Backend only** (the docs forbid browser/client use). **60 requests/minute.** Tokens **expire every year on January 1** and **may be reset without notice during the beta**. The API is "heavily in flux". Requests act as the token owner's account. Some filter operators are disabled, with a 30 s query timeout. **Risk R2:** production use needs explicit permission from Hardcover. The app must work if Hardcover disappears, which it does because of fallback. |
| **Open Library** | Public, no key | Send an identifying `User-Agent` (app name and contact). Be polite with rate limits (~1 request/s unidentified, higher when identified). Load covers by **cover ID** (`/b/id/…`), not by ISBN, because the ISBN cover endpoint is IP rate-limited. Data quality varies; series data is sparse. Provides `/trending/*.json` for the discovery section. Author works come from `search.json?q=author_key:…&sort=editions` rather than `/authors/{id}/works.json`, which is ordered by recency and returns translations without covers first. Bios contain HTML and Markdown and are cleaned server-side. |
| **Google Books** | API key (server-side) | The default quota is about 1,000 requests/day (check the GCP console; an increase can be requested). Good descriptions and publisher search. Weak series data and occasional mismatched ISBNs. **Keyless requests are unusable** (on 2026-11-04 they returned HTTP 429 with a per-day limit of 0), so the provider is disabled until `GOOGLE_BOOKS_KEY` is set. |

### 1.6 Implementation status (Phase 3)

| Provider | Status |
|---|---|
| Open Library | Live and verified end to end (search, ISBN, work, author, trending). |
| Hardcover | Implemented from the documented GraphQL shapes and tested against schema fixtures. **Not verified live**: no token yet (`SPIKE-88083021`). It is disabled until the `HARDCOVER_TOKEN` secret is set. |
| Google Books | Implemented and tested against schema fixtures. Disabled until the `GOOGLE_BOOKS_KEY` secret is set. |

Consequence while Hardcover is off: series entities (ids, positions, reading order) don't exist, so the book screen shows the series *name* only and the series screen is unreachable.

## 2. Audible

**Finding:** Audible has **no public developer program or documented API** for libraries or listening progress. Existing libraries (such as `mkb79/audible`) reverse-engineer the private API used by Audible's own apps, by imitating device registration.

**Decision:** Chapter will **not** use them. That would break the rule against bypassing authentication and private accounts, would likely violate Amazon's terms, and could stop working without notice.

**What we build:**
- Audiobook editions (format `audible`) with duration, from metadata or entered by the user.
- Manual audio progress in `h:mm:ss`, with a slider over the duration.
- Listening sessions use the same timer, labelled "Listening".
- Cross-format progress through `ProgressMapper` (approximate unless calibrated).
- An "Open in Audible" action through a store or web link when available. **No deep-link playback control is promised.**
- Copy in the app: *"Chapter can't read your Audible progress automatically. Audible doesn't offer a public API."*

**Implemented (Phase 7):** audiobook editions are added from the book menu with a typed length, not from metadata, which rarely has it. "Open in Audible" is a web search link. The timer says "listened" and the summary "Minutes listened".

## 3. Kindle

**Finding:** Amazon offers **no public API** for Kindle reading progress, libraries or highlights.

**What we build:**
- Manual progress by page, percentage or Kindle location.
- **`My Clippings.txt` import** (Phase 7). Physical Kindle devices write this file over USB. It is parsed on the device into notes and quotes with locations. This is legitimate because it is the user's own file.
- Never claim automatic Kindle sync.

**Implemented (Phase 7):** clippings import is done, on the device, for English-format files; matching needs the book in the library, and books that don't match are listed. Location entry in the progress sheet is **not** built.

## 4. Spotify

**Findings:**
- As of **February 11, 2026** (new apps) and **March 9, 2026** (existing apps), **Development Mode** requires the app owner to hold **Spotify Premium**, allows **at most 5 authorized users**, supports a reduced endpoint set, and caps search at 10 results per request.
- **Extended Quota** (needed for public release to everyone) is gated by Spotify's review, which is aimed at established organisations. An indie app should **assume it will not be granted**.
- July 2026: quotas are counted per developer account. Spotify also announced changes to how long refresh tokens last.

**Decision (two tiers, both independent of core features; approved):**

| Tier | Available to | Capability |
|---|---|---|
| **A. Deep links** (default) | Everyone, no account linking | Curated "Reading" playlists (public Spotify playlist URLs kept in Remote Config or Firestore) that open in the Spotify app or web player through `url_launcher`. No API calls and no quota. |
| **B. Web API linking** (behind a feature flag) | Allow-listed testers, or everyone if Extended Quota is ever granted | OAuth PKCE (with token exchange and refresh done server-side), "currently playing" on the session screen, start a playlist on the active device (**the listener needs Premium** for playback control). Playback in the background is not assumed. |

If Spotify fails, the only effect is that the music card is hidden.

**Implemented (Phase 7):** Tier A only, with public search links (`open.spotify.com/search/...`) in place of curated playlists until real ones are chosen. Tier B is not in the app.

## 5. Focus / Do Not Disturb

| Platform | Capability | Implementation |
|---|---|---|
| **Android** | Supported, with explicit user consent | A platform channel (`FocusModeChannel.kt`). On **API 35+**, use an `AutomaticZenRule` ("Chapter reading"), which the system shows to the user and turns off cleanly. On older versions, use `NotificationManager.setInterruptionFilter`. Both need **Notification Policy Access**, which the user must grant manually in Settings. Chapter shows an explanation screen first and never opens Settings without the user tapping. Chapter stores the previous filter and restores it when the session ends, is cancelled, or is recovered after a crash. |
| **iOS** | **Not possible.** No public API turns Focus or DND on or off. | Fallback: an in-app focus screen (dimmed UI, keeps the screen awake while the timer is visible, hides the nav bar), plus a guide for setting up a "Reading" Focus in iOS Settings. A later option is a Focus Filter (App Intents) so Chapter *reacts* when the user's Reading Focus is on. That is v2 and needs native Swift. |

**Implementation note (Phase 5, 2026-11-05):** Android uses `NotificationManager.setInterruptionFilter` on every API level rather than a hand-built `AutomaticZenRule`. On Android 15+ the system turns this call into an implicit, user-visible "Chapter" rule by itself, so a custom rule (which needs a condition provider) adds no user benefit. The previous filter is returned to Dart, stored with the live session in the database, and restored on end, discard, crash recovery and failure. `FocusRestoreReceiver` also restores it natively at the planned end (re-armed after a reboot), so a dead app can't leave DND on; only a Force stop cancels that alarm, and the next launch then restores it. Chapter only undoes DND it turned on itself and that is still in place. Focus mode is opt-in per session (a switch on the Read tab). Session notifications use `flutter_local_notifications`; the end notification is an absolute UTC instant, exact only when the system already allows exact alarms (Google Play restricts that permission), otherwise inexact. The recorded reading time never depends on the notification.

## 6. Other legitimate integrations (Phase 7)

- **Goodreads CSV import.** Goodreads closed its API in 2020, but users can still export a CSV. Map shelves to statuses, and import ratings, read dates, ISBNs and reviews.
- **StoryGraph CSV import.**
- **Calendar/Health:** not planned.

**Implemented (Phase 7):** both CSV imports, through a persistent queue limited by the lookup rate (see docs/03 §11). Failed lookups retry after 30 s, up to every 5 minutes. Real export files have not been tested.

## 7. Integration framework (app)

```dart
abstract interface class Integration {
  IntegrationId get id;
  IntegrationCapabilities get capabilities;   // declared, never assumed
  Stream<IntegrationStatus> get status;       // disconnected | connected | degraded | unavailable
  Future<Result<void, Failure>> connect();
  Future<void> disconnect();
}
```

Each integration is isolated in its own provider. If one throws, its failure is caught at the provider boundary and shown only on its own card in Profile → Connected services.

**Implemented (Phase 7):** `id`, `capabilities` and `status` only. `connect()` and `disconnect()` wait for something that connects to an account (Tier B).

## 8. Feature feasibility summary

| Feature | Feasibility | Reason |
|---|---|---|
| Automatic Kindle progress sync | ❌ Not possible | No public API |
| Automatic Audible progress sync | ❌ Not possible (legitimately) | No public API. Only reverse-engineered private APIs exist, which we won't use. |
| Exact page ↔ audio timestamp mapping | ⚠️ Approximate only | No public alignment data. Proportional or user-calibrated. |
| Spotify account features for all users | ⚠️ Restricted | Development Mode allows 5 users and the owner needs Premium. Extended Quota is unlikely. |
| Spotify playback control | ⚠️ Premium listeners only, active device needed | Spotify policy |
| iOS Do Not Disturb toggle | ❌ Not possible | No public API. Fallback provided. |
| Android Do Not Disturb toggle | ✅ With user-granted policy access | |
| Hardcover as primary in production | ⚠️ Uncertain | Beta, personal tokens, 60 requests/min, yearly expiry. Needs permission (SPIKE-88083021). |
| Reliable series reading order | ⚠️ Partial | Metadata is incomplete. Chronological order differs from publication order. Users can override the order. |
| Author photos | ⚠️ Partial | Availability and licensing vary. Show an attribution or a monogram fallback. |
| Discovery / "popular" sections | ✅ Limited | Open Library trending; Hardcover trending if the API offers it. |
| Background timer on iOS | ✅ With design | Elapsed time comes from timestamps, and the end time is a scheduled local notification. No background execution is needed. |

## Sources

- Hardcover API: Getting Started — https://docs.hardcover.app/api/getting-started
- Spotify February 2026 Dev Mode migration guide — https://developer.spotify.com/documentation/web-api/tutorials/february-2026-migration-guide
- Spotify Web API changelog, July 2026 — https://developer.spotify.com/documentation/web-api/references/changes/july-2026
- API Evangelist: Audible (no public program) — https://providers.apievangelist.com/providers/audible/
