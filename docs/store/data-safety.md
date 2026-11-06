# Data safety and app privacy answers (draft)

Based on what the code does as of Phase 8. The forms' wording changes, and these are your declarations to make, so check them against each form before submitting.

**Basics**
- Data collected: yes. Shared with third parties for their own use: no. Processors (Google Firebase) don't count as sharing on Play.
- Encrypted in transit: yes (HTTPS only; plain HTTP exists only in the dev flavor, for the local emulators).
- Users can request deletion: yes, in the app. Play also needs a web link (see docs/07 §3).
- Ads: none. Tracking across apps: none.

| Data | Collected | Why | Required? | Notes |
|---|---|---|---|---|
| Name | Yes | Account | Required | From Google or Apple |
| Email address | Yes | Account | Required | Apple may give a relay address |
| Profile photo | Yes | Account | Required | A URL from the provider |
| User IDs | Yes | Account, sync | Required | Firebase uid |
| Other user-generated content (notes, quotes, reviews) | Yes | App functionality | Optional | Synced to the account |
| App interactions / other actions (library, progress, sessions, goals) | Yes | App functionality | Required for the app's purpose | Not used for analytics |
| Search history | Processed, not stored against the user | Book lookup | Optional | Searches go through our servers to book data providers without account details. Recent searches stay on the device. The server cache is keyed by query with no user link. |
| Crash logs | Yes | Stability | Optional, **on by default** | Error type and stack only; messages are removed (`crash_scrubber.dart`) |
| Diagnostics | Yes | Stability | Optional | Comes with Crashlytics |
| Analytics / app activity | Only with opt-in | Analytics | Optional, **off by default** | Plus four coarse events (session completed with a duration bucket, progress updated, book added, scan added), defined in `analytics.dart`, with no content |
| Device or other IDs | Only with opt-in analytics, and for App Check | Security, analytics | | Advertising ID collection is off in the manifest |
| Photos / camera | **Not collected** | Barcode scan on the device | | Frames aren't stored or sent |
| Files | **Not collected** | Import is read on the device | | The file isn't uploaded; imported book data becomes reading data |
| Location, contacts, payment, health, messages | **No** | | | |

**Permissions to explain**
- Camera: barcode scanning, on request.
- Notifications: session running and timer end.
- Run at startup (`RECEIVE_BOOT_COMPLETED`): restores timer alerts and Do Not Disturb after a reboot.
- Do Not Disturb access: optional focus mode, granted in system settings.

**Decided (2026-11-06):** crash reports stay on by default, per docs/05 §1.5, with a switch at setup. Some regions and reviewers prefer opt-in; if one objects, it's one line in `user_preferences.dart`.
