import 'package:chapter/app/router/routes.dart';
import 'package:chapter/app/router/session_phase.dart';
import 'package:flutter_test/flutter_test.dart';

String? redirect(SessionPhase phase, String location) => redirectFor(phase, Uri.parse(location));

void main() {
  group('signed out', () {
    test('any app route goes to sign-in, remembering the deep link', () {
      expect(redirect(SessionPhase.signedOut, '/library'), '/sign-in?from=%2Flibrary');
    });

    test('sign-in itself stays', () {
      expect(redirect(SessionPhase.signedOut, AppRoutes.signIn), isNull);
    });

    test('splash forwards to sign-in keeping the original deep link', () {
      expect(
        redirect(SessionPhase.signedOut, '/splash?from=%2Fprofile'),
        '/sign-in?from=%2Fprofile',
      );
    });
  });

  test('loading shows splash', () {
    expect(redirect(SessionPhase.loading, '/home'), '/splash?from=%2Fhome');
    expect(redirect(SessionPhase.loading, AppRoutes.splash), isNull);
  });

  test('needs onboarding goes to onboarding', () {
    expect(redirect(SessionPhase.needsOnboarding, '/home'), '/onboarding?from=%2Fhome');
    expect(redirect(SessionPhase.needsOnboarding, AppRoutes.onboarding), isNull);
  });

  group('ready', () {
    test('app routes are left alone', () {
      expect(redirect(SessionPhase.ready, '/library'), isNull);
    });

    test('gate routes go home', () {
      expect(redirect(SessionPhase.ready, AppRoutes.signIn), AppRoutes.home);
      expect(redirect(SessionPhase.ready, AppRoutes.splash), AppRoutes.home);
    });

    test('gate routes restore the deep link', () {
      expect(redirect(SessionPhase.ready, '/sign-in?from=%2Fprofile'), '/profile');
    });

    test('a deep link pointing at a gate route is ignored', () {
      expect(redirect(SessionPhase.ready, '/sign-in?from=%2Fsign-in'), AppRoutes.home);
    });

    test('external or relative deep links are ignored', () {
      expect(
        redirect(SessionPhase.ready, '/sign-in?from=https%3A%2F%2Fevil.example'),
        AppRoutes.home,
      );
    });
  });
}
