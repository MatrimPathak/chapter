import 'package:firebase_core/firebase_core.dart';

/// Production Firebase options.
///
/// **Not configured yet** (PROJECT_STATUS.md blocker B1): the `chapter-prod`
/// project has to be created by the owner first. Then generate this file with:
///
/// ```
/// flutterfire configure --project=chapter-prod \
///   --out=lib/core/firebase/firebase_options_prod.dart \
///   --android-package-name=com.chapterreads.chapter \
///   --ios-bundle-id=com.chapterreads.chapter
/// ```
///
/// Until then the prod entry point fails fast with a clear message instead of
/// silently running against the wrong backend.
abstract final class ProdFirebaseOptions {
  static FirebaseOptions get currentPlatform => throw UnsupportedError(
    'Production Firebase is not configured. Run `flutterfire configure` for '
    'chapter-prod (see lib/core/firebase/firebase_options_prod.dart).',
  );
}
