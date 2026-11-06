# Chapter — Release runbook

Everything a v1.0 release needs that can't be done from the repository, in order. Each step says who does it and how you know it worked.

## 1. Firebase production (blocker B1)

1. Project `chapter-reads-prod` exists, with its Android and iOS apps and its database in Mumbai (`asia-south1`). Move it to the Blaze plan and set a budget alert.
2. Enable Authentication (Google; Apple once the Apple account exists), Firestore, Functions, App Check, Analytics, Crashlytics.
3. The app's config is in `lib/core/firebase/firebase_options_prod.dart`. To regenerate the values: `firebase apps:sdkconfig`.
4. Set secrets. The functions declare both, and no function deploys until both exist, even with `--only functions:deleteAccount`. A value of one space keeps that provider off, with Open Library still working, because the code trims it to nothing:
   ```bash
   firebase functions:secrets:set HARDCOVER_TOKEN --project chapter-reads-prod
   ```
   ```bash
   firebase functions:secrets:set GOOGLE_BOOKS_KEY --project chapter-reads-prod
   ```
5. Deploy from the repository root:
   ```bash
   firebase deploy --only firestore:rules,firestore:indexes,functions --project chapter-reads-prod
   ```
   All of this is deployed as of 2026-11-06. On a first deploy, check every function was created: one failed with a 409 on the build bucket while the deploy still exited 0. This also applies the TTL policies on `catalog_searchCache` and `ops_rateLimits` (`expiresAt`), which the emulators can't test. Confirm them in the Firebase console.
6. **App Check:** the App Check API must be on. Android is registered with Play Integrity; registering the iOS app with App Attest remains. For testing, a debug build prints a debug token to add under Manage debug tokens; delete it afterwards. Every callable, including `deleteAccount`, enforces App Check, so without this nothing server-side works in a release build.
7. Pass the Google OAuth web client id at build time: `--dart-define=GOOGLE_SERVER_CLIENT_ID=80245747744-7cn3mrv8lju85m01nlo3ljl9j86g97l7.apps.googleusercontent.com`. It identifies the app and isn't a secret.
8. **Crashlytics symbols:** the Crashlytics Gradle plugin isn't applied, so Android reports aren't deobfuscated. Add it once a real `google-services.json` exists. Native crash reports are unreadable until then.

**Check:** a release build signs in with a real Google account, adds a book and shows "All changes saved".

## 2. Android signing and build (blocker B3)

1. Done 2026-11-06 on the owner's machine: upload key and `app/android/key.properties`. To recreate, see `app/android/key.properties.example`. **Back up the key and passwords outside the machine.**
2. The key's SHA-1 and SHA-256 are on the Firebase Android app. Add Play's app signing certificate too, or Google sign-in fails for installs from Play.
3. Build:
   ```bash
   flutter build appbundle --release --flavor prod -t lib/main_prod.dart --dart-define=GOOGLE_SERVER_CLIENT_ID=YOUR_ID
   ```

## 3. Play Console (blocker B3)

1. Create the app and upload to internal testing first.
2. Listing text and graphics: `docs/store/listing.md`, `docs/store/assets/`. You still need phone screenshots from a real build.
3. Data safety: answers in `docs/store/data-safety.md`.
4. Declarations you'll be asked about:
   - **Notification policy access:** Do Not Disturb is optional and the reader grants it in system settings.
   - **Exact alarms:** not requested.
   - **Account deletion:** Play requires a web link where someone can request deletion without the app. That page doesn't exist yet. It could simply explain the in-app steps and give the contact address.

## 4. iOS (spike `SPIKE-29567026`, blocker B3)

iOS compiles on CI (unsigned) but has **never run**, so expect work here. It targets iOS 15. Plugins and Firebase come through Swift Package Manager, not CocoaPods.

1. Apple Developer account; bundle id `com.chapterreads.chapter`; enable Sign in with Apple and App Attest.
2. Add a real `GoogleService-Info.plist` and the Google URL scheme.
3. Test on a device: session timer, notifications, Focus guidance, barcode scanner, file picker, share sheet.
4. **Sign in with Apple token revocation is written but has never run.** Test it: delete an Apple account, then check Apple ID settings no longer list Chapter.
5. The iCloud backup exclusion in `AppDelegate.swift` has never been compiled either. Check it.
6. App privacy answers follow `docs/store/data-safety.md`.

## 5. Before submitting

Run `python tool/release_check.py` from `app/`: it fails until the policy, Firebase config, key and version are done.

- [ ] Privacy policy reviewed by you, or a lawyer, for the places you'll offer the app. It is a draft written by an AI, not legal advice.
- [ ] `[CONTACT EMAIL]` and `[EFFECTIVE DATE]` filled in `app/assets/legal/privacy_policy.md`, and the "DRAFT" line removed. The app shows this file as it is.
- [ ] Policy published at a public URL and entered in both stores.
- [ ] Version set in `app/pubspec.yaml`.
- [ ] Real export files tried (W35).
- [ ] Physical Android device run, including a real TalkBack pass.
- [ ] Cold start measured on a mid-range phone, in a release build, against the 2 s target.
- [ ] Optional: a designer's app icon. To replace the generated one, see `app/tool/generate_icons.py`.

## 6. After launch

- Watch the crash-free rate against the 99.5 % target. It can only be measured with real users.
- Rotate the Hardcover token before it expires (January 1 each year).
