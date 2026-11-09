import 'package:flutter/material.dart';

import '../../../core/design_system/design_system.dart';
import '../../../l10n/generated/app_localizations.dart';

/// Shown while the auth state and local profile load.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      body: Center(
        child: Semantics(
          label: l10n.loading,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ChapterLogo(),
              const SizedBox(height: ChapterSpacing.lg),
              Text(l10n.appName, style: context.textTheme.displayMedium),
              const SizedBox(height: ChapterSpacing.xs),
              Text(l10n.tagline, style: ChapterTypography.quote(context.chapterColors.inkMuted)),
            ],
          ),
        ),
      ),
    );
  }
}
