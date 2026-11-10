import '../../../core/sync/lww_store.dart';
import '../../auth/domain/app_user.dart';
import '../domain/profile_repository.dart';
import '../domain/user_preferences.dart';

/// [ProfileRepository] backed by the local LWW store (`users/{uid}`).
class LwwProfileRepository implements ProfileRepository {
  LwwProfileRepository({
    required LwwStore store,
    required String uid,
    required void Function() onLocalWrite,
  }) : _store = store,
       _onLocalWrite = onLocalWrite,
       path = 'users/$uid';

  final LwwStore _store;
  final void Function() _onLocalWrite;
  final String path;

  @override
  Stream<UserPreferences> watchPreferences() =>
      _store.watch(path).map((doc) => UserPreferences.fromFields(doc.fields)).distinct();

  @override
  Future<void> setTheme(ThemePreference theme) => _write({ProfileFields.theme: theme.name});

  @override
  Future<void> setDefaultTimer(int minutes) =>
      _write({ProfileFields.defaultTimerMin: minutes.clamp(1, 600)});

  @override
  Future<void> setBookViews({
    String? librarySort,
    bool? libraryGrid,
    String? shelfSort,
    bool? shelfGrid,
    bool? addBooksGrid,
  }) => _write({
    ProfileFields.librarySort: ?librarySort,
    ProfileFields.libraryGrid: ?libraryGrid,
    ProfileFields.shelfSort: ?shelfSort,
    ProfileFields.shelfGrid: ?shelfGrid,
    ProfileFields.addBooksGrid: ?addBooksGrid,
  });

  @override
  Future<void> setConsents({bool? analytics, bool? crash}) =>
      _write({ProfileFields.analyticsConsent: ?analytics, ProfileFields.crashConsent: ?crash});

  @override
  Future<void> completeOnboarding({required bool analytics, required bool crash}) => _write({
    ProfileFields.analyticsConsent: analytics,
    ProfileFields.crashConsent: crash,
    ProfileFields.onboardingDone: true,
  });

  @override
  Future<void> syncIdentity(AppUser user) async {
    final current = (await _store.read(path)).fields;
    final identity = {
      ProfileFields.displayName: user.displayName,
      ProfileFields.photoUrl: user.photoUrl,
      ProfileFields.email: user.email,
    };
    final changed = {
      for (final e in identity.entries)
        if (e.value != null && current[e.key] != e.value) e.key: e.value,
    };
    await _write(changed);
  }

  Future<void> _write(Map<String, Object?> changes) async {
    if (changes.isEmpty) return;
    await _store.write(path, changes);
    _onLocalWrite();
  }
}
