import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

/// Options for the **offline demo project** used with the Firebase Emulator
/// Suite. `demo-*` project ids never reach real Google services, so these
/// values are intentionally fake and safe to commit.
///
/// Once the real `chapter-dev` project exists, replace this file with the
/// output of `flutterfire configure` (see PROJECT_STATUS.md, blocker B1).
abstract final class DevFirebaseOptions {
  static const projectId = 'demo-chapter';

  /// Fake, but in the AIza… / 39-character *format* the Android Functions SDK
  /// validates. Never used against real Google APIs (demo-* project).
  static const _demoApiKey = 'AIzaSyDemoChapterEmulatorOnlyNotARealKe';

  static FirebaseOptions get currentPlatform => switch (defaultTargetPlatform) {
    TargetPlatform.iOS => const FirebaseOptions(
      apiKey: _demoApiKey,
      appId: '1:000000000000:ios:0000000000000000000000',
      messagingSenderId: '000000000000',
      projectId: projectId,
      iosBundleId: 'com.chapterreads.chapter.dev',
    ),
    _ => const FirebaseOptions(
      apiKey: _demoApiKey,
      appId: '1:000000000000:android:0000000000000000000000',
      messagingSenderId: '000000000000',
      projectId: projectId,
    ),
  };
}
