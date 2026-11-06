# Chapter

*Your reading life, in one place.* A calm, private reading tracker for Android and iOS, built with Flutter and Firebase.

**Status:** in development and not released. Android runs against local emulators. iOS has never been compiled. See [PROJECT_STATUS.md](PROJECT_STATUS.md).

## Repository layout

| Path | What it is |
|---|---|
| `app/` | The Flutter app ([setup](app/README.md)) |
| `functions/` | Cloud Functions in TypeScript: book metadata and account deletion |
| `firebase/` | Firestore security rules and indexes |
| `docs/` | Product, architecture, data, integration, security, roadmap and release documents |

## Running it

The `dev` flavor uses the Firebase Emulator Suite with an offline demo project, so it needs no cloud account or secrets. See [app/README.md](app/README.md).

## Licence

Copyright © 2026 Matrim Pathak. All rights reserved.

The source is public to read. No licence is granted to copy, modify or distribute it. Third-party components keep their own licences, including the fonts in `app/assets/fonts` (SIL Open Font License).

## Security

See [SECURITY.md](SECURITY.md).
