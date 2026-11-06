import '../../auth/domain/app_user.dart';
import 'user_preferences.dart';

/// Profile and preferences of the signed-in user. Writes are local-first and
/// sync in the background.
abstract interface class ProfileRepository {
  Stream<UserPreferences> watchPreferences();

  Future<void> setTheme(ThemePreference theme);

  /// Last-used reading timer length, in minutes (1–600).
  Future<void> setDefaultTimer(int minutes);

  Future<void> setConsents({bool? analytics, bool? crash});

  Future<void> completeOnboarding({required bool analytics, required bool crash});

  /// Copies identity fields from the auth provider into the profile when
  /// they changed. Called after sign-in.
  Future<void> syncIdentity(AppUser user);
}
