import 'app/app_config.dart';
import 'bootstrap.dart';
import 'core/firebase/firebase_options_prod.dart';

/// Production entry point:
/// `flutter run --flavor prod -t lib/main_prod.dart --release`
Future<void> main() => bootstrap(AppConfig.prod(), ProdFirebaseOptions.currentPlatform);
