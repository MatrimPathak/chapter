# Chapter — Flutter app

Architecture and decisions live in [`../docs`](../docs); project status is in [`../PROJECT_STATUS.md`](../PROJECT_STATUS.md).

## First-time setup

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs
```

Generated files (`*.g.dart`, `*.freezed.dart`, `lib/l10n/generated/`) are not committed. Re-run `build_runner` after changing Freezed models or Drift tables.

## Run (dev, against the Firebase Emulator Suite)

From the repository root, start the emulators. The project id `demo-chapter` is offline and touches no cloud resources:

```bash
firebase emulators:start --only auth,firestore --project demo-chapter
```

Then run the app:

```bash
flutter run --flavor dev -t lib/main_dev.dart
```

On the sign-in screen, use **Continue with test account (emulator)**. Real Google and Apple sign-in need the real Firebase projects (PROJECT_STATUS.md, blocker B1).

`--dart-define` options:

| Define | Default | Purpose |
|---|---|---|
| `USE_EMULATORS` | `true` (dev) | Connect to the local emulators |
| `EMULATOR_HOST` | `10.0.2.2` on Android, `localhost` otherwise | Use your machine's LAN IP for a physical device |
| `GOOGLE_SERVER_CLIENT_ID` | — | OAuth web client id for Google Sign-In on Android |

## Checks

```bash
dart format --set-exit-if-changed lib test
flutter analyze
flutter test
```
