import 'package:chapter/core/database/app_database.dart';
import 'package:chapter/features/reading/application/notification_permission.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late int prompts;
  late bool allowed;
  const flag = 'notification_permission_asked';

  Future<bool> start({bool answer = false}) => askForPermissionOnce(
    isAllowed: () async => allowed,
    ask: () async {
      prompts++;
      allowed = answer;
      return answer;
    },
    wasAsked: () => db.hasFlag(flag),
    markAsked: () => db.setFlag(flag),
  );

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    prompts = 0;
    allowed = false;
  });
  tearDown(() => db.close());

  test('a declined prompt is not shown again at the next session', () async {
    expect(await start(), isFalse);
    expect(await start(), isFalse);
    expect(await start(), isFalse);
    expect(prompts, 1);
  });

  test('accepting is reported and needs no further prompts', () async {
    expect(await start(answer: true), isTrue);
    expect(await start(), isTrue);
    expect(prompts, 1);
  });

  test('already allowed never prompts', () async {
    allowed = true;
    expect(await start(), isTrue);
    expect(prompts, 0);
    expect(await db.hasFlag(flag), isFalse);
  });

  test('turning notifications on in system settings after a decline is honoured', () async {
    await start();
    allowed = true;
    expect(await start(), isTrue);
    expect(prompts, 1);
  });

  test('the flag belongs to the database it was set in', () async {
    await start();
    final other = AppDatabase(NativeDatabase.memory());
    addTearDown(other.close);
    expect(await other.hasFlag(flag), isFalse);
  });
}
