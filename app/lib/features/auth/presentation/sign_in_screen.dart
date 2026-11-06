import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/design_system/design_system.dart';
import '../../../core/error/failure.dart';
import '../../../l10n/generated/app_localizations.dart';
import 'auth_controller.dart';

class SignInScreen extends ConsumerWidget {
  const SignInScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final colors = context.chapterColors;
    final state = ref.watch(signInControllerProvider);
    final controller = ref.read(signInControllerProvider.notifier);
    final config = ref.watch(appConfigProvider);
    final isIos = defaultTargetPlatform == TargetPlatform.iOS;

    ref.listen(signInControllerProvider, (_, next) {
      final failure = next.failure;
      if (failure == null) return;
      final message = failure is CancelledFailure ? l10n.signInCancelled : l10n.signInFailed;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));
      controller.clearFailure();
    });

    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: ChapterSpacing.xl),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: ChapterSpacing.xxxl),
                      Text(
                        l10n.appName,
                        style: context.textTheme.displayLarge,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: ChapterSpacing.sm),
                      Text(
                        l10n.tagline,
                        style: context.textTheme.titleLarge?.copyWith(
                          color: colors.inkMuted,
                          fontWeight: FontWeight.w400,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: ChapterSpacing.xxxl),
                      ChapterButton(
                        label: l10n.signInWithGoogle,
                        expand: true,
                        isLoading: state.inProgress == SignInMethod.google,
                        onPressed: state.inProgress == null
                            ? () => controller.signIn(SignInMethod.google)
                            : null,
                      ),
                      if (isIos) ...[
                        const SizedBox(height: ChapterSpacing.md),
                        ChapterButton(
                          label: l10n.signInWithApple,
                          expand: true,
                          variant: ChapterButtonVariant.secondary,
                          icon: const Icon(Icons.apple),
                          isLoading: state.inProgress == SignInMethod.apple,
                          onPressed: state.inProgress == null
                              ? () => controller.signIn(SignInMethod.apple)
                              : null,
                        ),
                      ],
                      if (config.useEmulators) ...[
                        const SizedBox(height: ChapterSpacing.md),
                        ChapterButton(
                          label: l10n.signInWithEmulator,
                          expand: true,
                          variant: ChapterButtonVariant.text,
                          isLoading: state.inProgress == SignInMethod.emulator,
                          onPressed: state.inProgress == null
                              ? () => controller.signIn(SignInMethod.emulator)
                              : null,
                        ),
                      ],
                      const SizedBox(height: ChapterSpacing.xl),
                      Text(
                        l10n.signInPrivacyNote,
                        style: context.textTheme.bodySmall,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: ChapterSpacing.xxxl),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
