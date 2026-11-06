import 'app/app_config.dart';
import 'bootstrap.dart';
import 'core/firebase/firebase_options_dev.dart';

/// Development entry point:
/// `flutter run --flavor dev -t lib/main_dev.dart`
/// (start emulators first: `firebase emulators:start` in the repo root).
Future<void> main() => bootstrap(AppConfig.dev(), DevFirebaseOptions.currentPlatform);
