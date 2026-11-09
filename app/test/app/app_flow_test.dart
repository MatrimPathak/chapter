import 'package:chapter/app/app_config.dart';
import 'package:chapter/core/error/failure.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_auth_repository.dart';
import '../helpers/test_app.dart';

void main() {
  testWidgets('signed-out users land on sign-in', (tester) async {
    await pumpChapterApp(tester);
    expect(find.text('Continue with Google'), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    await unmountApp(tester);
  });

  testWidgets('emulator test sign-in is only offered when using emulators', (tester) async {
    await pumpChapterApp(
      tester,
      config: const AppConfig(flavor: Flavor.prod, useEmulators: false, emulatorHost: ''),
    );
    expect(find.text('Continue with test account (emulator)'), findsNothing);
    await unmountApp(tester);
  });

  testWidgets('cancelled sign-in shows a message and stays on sign-in', (tester) async {
    final auth = FakeAuthRepository()..nextFailure = const CancelledFailure('closed');
    await pumpChapterApp(tester, auth: auth);
    await tester.tap(find.text('Continue with Google'));
    await settle(tester);
    expect(find.text('Sign-in was cancelled.'), findsOneWidget);
    expect(find.text('Continue with Google'), findsOneWidget);
    await unmountApp(tester);
  });

  testWidgets('first sign-in → onboarding → home with greeting', (tester) async {
    await pumpChapterApp(tester);
    await tester.tap(find.text('Continue with Google'));
    await settle(tester);

    expect(find.text('Before you begin'), findsOneWidget);
    final analytics = find.widgetWithText(SwitchListTile, 'Share anonymous usage statistics');
    expect(tester.widget<SwitchListTile>(analytics).value, isFalse, reason: 'opt-in');

    await tester.tap(find.text('Start reading'));
    await settle(tester);

    expect(find.text('Good morning, Ada'), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
    await unmountApp(tester);
  });

  testWidgets('tabs switch and the Profile tab signs out to sign-in', (tester) async {
    tester.view.physicalSize = const Size(1080, 6000);
    addTearDown(tester.view.reset);
    final auth = FakeAuthRepository(initialUser: FakeAuthRepository.testUser);
    await pumpChapterApp(tester, auth: auth);
    // Complete onboarding for the pre-signed-in user.
    await tester.tap(find.text('Start reading'));
    await settle(tester);

    await tester.tap(find.text('Library'));
    await settle(tester);
    expect(find.text('Your library is empty'), findsOneWidget);

    await tester.tap(find.text('Reading'));
    await settle(tester);
    expect(find.text('Nothing to read yet'), findsOneWidget);

    await tester.tap(find.text('Profile'));
    await settle(tester);
    expect(find.text('ada@chapter.test'), findsOneWidget);

    await tester.tap(find.text('Sign out'));
    await settle(tester);
    // Pending identity/onboarding changes were pushed to the fake remote,
    // so no confirmation dialog is needed.
    expect(auth.signOutCalls, 1);
    expect(find.text('Continue with Google'), findsOneWidget);
    await unmountApp(tester);
  });

  testWidgets('theme preference switches the app to dark mode', (tester) async {
    final auth = FakeAuthRepository(initialUser: FakeAuthRepository.testUser);
    await pumpChapterApp(tester, auth: auth);
    await tester.tap(find.text('Start reading'));
    await settle(tester);
    await tester.tap(find.text('Profile'));
    await settle(tester);
    await tester.scrollUntilVisible(
      find.text('Dark'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.ensureVisible(find.text('Dark'));
    await settle(tester);
    await tester.tap(find.text('Dark'));
    await settle(tester);

    final context = tester.element(find.text('Dark'));
    expect(Theme.of(context).brightness, Brightness.dark);
    await unmountApp(tester);
  });
}
