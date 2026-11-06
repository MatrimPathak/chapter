import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/design_system/design_system.dart';
import '../../../l10n/generated/app_localizations.dart';

/// First-run privacy consent. Analytics default to **off** (docs/05 §1.5).
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  bool _analytics = false;
  bool _crash = true;
  bool _saving = false;

  Future<void> _continue() async {
    setState(() => _saving = true);
    await ref
        .read(profileRepositoryProvider)
        .completeOnboarding(analytics: _analytics, crash: _crash);
    // The router guard moves on once the preference stream updates.
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(ChapterSpacing.xl),
          children: [
            const SizedBox(height: ChapterSpacing.xxl),
            Text(l10n.onboardingTitle, style: context.textTheme.displaySmall),
            const SizedBox(height: ChapterSpacing.md),
            Text(l10n.onboardingBody, style: context.textTheme.bodyLarge),
            const SizedBox(height: ChapterSpacing.xl),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.consentAnalyticsTitle),
              subtitle: Text(l10n.consentAnalyticsBody),
              value: _analytics,
              onChanged: (v) => setState(() => _analytics = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.consentCrashTitle),
              subtitle: Text(l10n.consentCrashBody),
              value: _crash,
              onChanged: (v) => setState(() => _crash = v),
            ),
            const SizedBox(height: ChapterSpacing.xxl),
            ChapterButton(
              label: l10n.onboardingContinue,
              expand: true,
              isLoading: _saving,
              onPressed: _continue,
            ),
          ],
        ),
      ),
    );
  }
}
