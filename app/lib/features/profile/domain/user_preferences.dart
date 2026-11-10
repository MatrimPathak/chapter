import 'package:freezed_annotation/freezed_annotation.dart';

part 'user_preferences.freezed.dart';

enum ThemePreference { system, light, dark }

/// Field names in `users/{uid}`. Shared by the repository, the Firestore
/// rules allow-list (`firebase/firestore.rules`) and tests — keep in sync.
abstract final class ProfileFields {
  static const displayName = 'displayName';
  static const photoUrl = 'photoUrl';
  static const email = 'email';
  static const onboardingDone = 'onboardingDone';
  static const theme = 'theme';
  static const analyticsConsent = 'analyticsConsent';
  static const crashConsent = 'crashConsent';
  static const defaultTimerMin = 'defaultTimerMin';
  static const weekStartsOn = 'weekStartsOn';
  static const librarySort = 'librarySort';
  static const libraryGrid = 'libraryGrid';
  static const shelfSort = 'shelfSort';
  static const shelfGrid = 'shelfGrid';
  static const addBooksGrid = 'addBooksGrid';

  static const all = {
    displayName,
    photoUrl,
    email,
    onboardingDone,
    theme,
    analyticsConsent,
    crashConsent,
    defaultTimerMin,
    weekStartsOn,
    librarySort,
    libraryGrid,
    shelfSort,
    shelfGrid,
    addBooksGrid,
  };
}

/// User preferences with privacy-first defaults: analytics **off** until the
/// user opts in, crash reports on but switchable (docs/05 §1.5).
@freezed
abstract class UserPreferences with _$UserPreferences {
  const factory UserPreferences({
    @Default(false) bool onboardingDone,
    @Default(ThemePreference.system) ThemePreference theme,
    @Default(false) bool analyticsConsent,
    @Default(true) bool crashConsent,
    @Default(30) int defaultTimerMin,
    @Default(DateTime.monday) int weekStartsOn,
    @Default('recent') String librarySort,
    @Default(false) bool libraryGrid,
    @Default('recent') String shelfSort,
    @Default(false) bool shelfGrid,
    @Default(false) bool addBooksGrid,
  }) = _UserPreferences;

  const UserPreferences._();

  /// Reads preferences from raw document fields, ignoring unknown or
  /// malformed values (defaults apply) so a bad remote value can't crash
  /// the app.
  factory UserPreferences.fromFields(Map<String, Object?> f) {
    const d = UserPreferences();
    T read<T>(String key, T fallback) {
      final value = f[key];
      return value is T ? value : fallback;
    }

    final themeName = read<String?>(ProfileFields.theme, null);
    final timer = read<num>(ProfileFields.defaultTimerMin, d.defaultTimerMin).toInt();
    final weekStart = read<num>(ProfileFields.weekStartsOn, d.weekStartsOn).toInt();
    return UserPreferences(
      onboardingDone: read(ProfileFields.onboardingDone, d.onboardingDone),
      theme: ThemePreference.values.firstWhere((t) => t.name == themeName, orElse: () => d.theme),
      analyticsConsent: read(ProfileFields.analyticsConsent, d.analyticsConsent),
      crashConsent: read(ProfileFields.crashConsent, d.crashConsent),
      defaultTimerMin: timer >= 1 && timer <= 600 ? timer : d.defaultTimerMin,
      weekStartsOn: weekStart >= 1 && weekStart <= 7 ? weekStart : d.weekStartsOn,
      librarySort: read(ProfileFields.librarySort, d.librarySort),
      libraryGrid: read(ProfileFields.libraryGrid, d.libraryGrid),
      shelfSort: read(ProfileFields.shelfSort, d.shelfSort),
      shelfGrid: read(ProfileFields.shelfGrid, d.shelfGrid),
      addBooksGrid: read(ProfileFields.addBooksGrid, d.addBooksGrid),
    );
  }
}
