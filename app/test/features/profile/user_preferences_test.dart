import 'package:chapter/features/profile/domain/user_preferences.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('defaults are privacy-first', () {
    const p = UserPreferences();
    expect(p.analyticsConsent, isFalse);
    expect(p.crashConsent, isTrue);
    expect(p.onboardingDone, isFalse);
    expect(p.theme, ThemePreference.system);
  });

  test('reads known fields', () {
    final p = UserPreferences.fromFields({
      'theme': 'dark',
      'analyticsConsent': true,
      'crashConsent': false,
      'onboardingDone': true,
      'defaultTimerMin': 45,
      'weekStartsOn': 7,
    });
    expect(p.theme, ThemePreference.dark);
    expect(p.analyticsConsent, isTrue);
    expect(p.crashConsent, isFalse);
    expect(p.onboardingDone, isTrue);
    expect(p.defaultTimerMin, 45);
    expect(p.weekStartsOn, 7);
  });

  test('malformed or out-of-range values fall back to defaults', () {
    final p = UserPreferences.fromFields({
      'theme': 'neon',
      'analyticsConsent': 'yes',
      'defaultTimerMin': -5,
      'weekStartsOn': 12,
    });
    expect(p, const UserPreferences());
  });
}
