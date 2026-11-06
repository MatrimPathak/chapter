import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

/// Production Firebase options for `chapter-reads-prod`.
///
/// These identify the project to Google and aren't secrets: access is decided
/// by Firestore rules, App Check and Auth. Values come from
/// `firebase apps:sdkconfig`.
abstract final class ProdFirebaseOptions {
  static const projectId = 'chapter-reads-prod';

  static FirebaseOptions get currentPlatform => switch (defaultTargetPlatform) {
    TargetPlatform.iOS => const FirebaseOptions(
      apiKey: 'AIzaSyBUO_OAg-g2W_BcZfN_bnodHot9cH3O2jo',
      appId: '1:80245747744:ios:0957e323696490f94d8c45',
      messagingSenderId: '80245747744',
      projectId: projectId,
      iosBundleId: 'com.chapterreads.chapter',
    ),
    _ => const FirebaseOptions(
      apiKey: 'AIzaSyAM9XxoxnRG9z7s3LwSKi89CMstZC8CZ3k',
      appId: '1:80245747744:android:09f586779176e0014d8c45',
      messagingSenderId: '80245747744',
      projectId: projectId,
    ),
  };
}
