import 'package:chapter/core/database/app_database.dart';
import 'package:chapter/core/sync/lww_store.dart';
import 'package:chapter/core/utils/clock.dart';
import 'package:chapter/core/utils/id_generator.dart';
import 'package:chapter/features/auth/domain/app_user.dart';
import 'package:chapter/features/profile/data/lww_profile_repository.dart';
import 'package:chapter/features/profile/domain/user_preferences.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late LwwStore store;
  late LwwProfileRepository repo;
  var nudges = 0;

  setUp(() {
    nudges = 0;
    db = AppDatabase(NativeDatabase.memory());
    store = LwwStore(
      db: db,
      clock: FakeClock(DateTime.utc(2026, 11, 4)),
      ids: const UuidV7Generator(),
    );
    repo = LwwProfileRepository(store: store, uid: 'u1', onLocalWrite: () => nudges++);
  });

  tearDown(() => db.close());

  Future<int> outboxCount() async => (await db.select(db.outboxEntries).get()).length;

  test('emits defaults before anything is stored', () async {
    expect(await repo.watchPreferences().first, const UserPreferences());
  });

  test('completing onboarding stores consent and queues one sync', () async {
    await repo.completeOnboarding(analytics: true, crash: false);
    final prefs = await repo.watchPreferences().first;
    expect(prefs.onboardingDone, isTrue);
    expect(prefs.analyticsConsent, isTrue);
    expect(prefs.crashConsent, isFalse);
    expect(await outboxCount(), 1);
    expect(nudges, 1);
  });

  test('setConsents only writes the fields provided', () async {
    await repo.setConsents(crash: false);
    final fields = (await store.read('users/u1')).fields;
    expect(fields.keys, ['crashConsent']);
  });

  test('syncIdentity writes only changed, non-null identity fields', () async {
    const user = AppUser(uid: 'u1', displayName: 'Ada', email: 'ada@x.test');
    await repo.syncIdentity(user);
    await repo.syncIdentity(user);
    expect(await outboxCount(), 1, reason: 'second call is a no-op');
    final fields = (await store.read('users/u1')).fields;
    expect(fields, {'displayName': 'Ada', 'email': 'ada@x.test'});
  });

  test('theme changes are observable', () async {
    await repo.setTheme(ThemePreference.dark);
    expect((await repo.watchPreferences().first).theme, ThemePreference.dark);
  });
}
