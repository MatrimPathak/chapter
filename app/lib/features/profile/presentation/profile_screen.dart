import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/router/routes.dart';
import '../../../core/design_system/design_system.dart';
import '../../../core/sync/sync_status.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../auth/presentation/auth_controller.dart';
import '../application/account_actions.dart';
import '../domain/profile_repository.dart';
import '../domain/user_preferences.dart';

/// Profile: identity, sync state, reading, services, appearance, privacy, data
/// and account.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final user = ref.watch(authStateProvider).value;
    final prefs = ref.watch(preferencesProvider).value ?? const UserPreferences();
    final sync = ref.watch(syncStatusProvider).value ?? const SyncSynced();
    // Read lazily: the screen can rebuild briefly after sign-out.
    ProfileRepository repo() => ref.read(profileRepositoryProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.navProfile)),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: ChapterSpacing.lg),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: ChapterSpacing.gutter),
            child: Row(
              children: [
                _Avatar(name: user?.displayName, photoUrl: user?.photoUrl),
                const SizedBox(width: ChapterSpacing.lg),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (user?.displayName != null)
                        Text(user!.displayName!, style: context.textTheme.headlineSmall),
                      if (user?.email != null)
                        Text(user!.email!, style: context.textTheme.bodySmall),
                      const SizedBox(height: ChapterSpacing.xs),
                      SyncBadge(status: sync),
                    ],
                  ),
                ),
              ],
            ),
          ),
          _SectionHeader(l10n.profileReading),
          ListTile(
            leading: const Icon(Icons.flag_outlined),
            title: Text(l10n.goalsTitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push(AppRoutes.goals),
          ),
          ListTile(
            leading: const Icon(Icons.insights_outlined),
            title: Text(l10n.insightsTitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push(AppRoutes.insights),
          ),
          ListTile(
            leading: const Icon(Icons.hub_outlined),
            title: Text(l10n.profileConnected),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push(AppRoutes.integrations),
          ),
          _SectionHeader(l10n.profileAppearance),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: ChapterSpacing.gutter),
            child: SegmentedButton<ThemePreference>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(value: ThemePreference.system, label: Text(l10n.themeSystem)),
                ButtonSegment(value: ThemePreference.light, label: Text(l10n.themeLight)),
                ButtonSegment(value: ThemePreference.dark, label: Text(l10n.themeDark)),
              ],
              selected: {prefs.theme},
              onSelectionChanged: (s) => repo().setTheme(s.first),
            ),
          ),
          _SectionHeader(l10n.profilePrivacy),
          SwitchListTile(
            title: Text(l10n.consentAnalyticsTitle),
            subtitle: Text(l10n.consentAnalyticsBody),
            value: prefs.analyticsConsent,
            onChanged: (v) => repo().setConsents(analytics: v),
          ),
          SwitchListTile(
            title: Text(l10n.consentCrashTitle),
            subtitle: Text(l10n.consentCrashBody),
            value: prefs.crashConsent,
            onChanged: (v) => repo().setConsents(crash: v),
          ),
          _SectionHeader(l10n.profileYourData),
          ListTile(
            key: const Key('export-data'),
            leading: const Icon(Icons.ios_share_outlined),
            title: Text(l10n.exportTitle),
            subtitle: Text(l10n.exportSubtitle),
            onTap: () => _export(context, ref),
          ),
          _SectionHeader(l10n.profileAccount),
          ListTile(
            leading: const Icon(Icons.logout_rounded),
            title: Text(l10n.signOut),
            onTap: () => _signOut(context, ref),
          ),
          ListTile(
            key: const Key('delete-account'),
            leading: const Icon(Icons.delete_forever_outlined),
            title: Text(l10n.deleteTitle),
            onTap: () => context.push(AppRoutes.deleteAccount),
          ),
          ListTile(
            leading: const Icon(Icons.info_outline_rounded),
            title: Text(l10n.aboutTitle),
            onTap: () => context.push(AppRoutes.about),
          ),
        ],
      ),
    );
  }

  Future<void> _export(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(accountActionsProvider).exportData();
    } on Object {
      messenger.showSnackBar(SnackBar(content: Text(l10n.exportFailed)));
    }
  }

  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final action = ref.read(signOutActionProvider);
    final pending = await action.pendingChanges();
    if (pending > 0) {
      if (!context.mounted) return;
      final confirmed = await showChapterConfirmDialog(
        context: context,
        title: l10n.signOutPendingTitle,
        body: l10n.signOutPendingBody(pending),
        confirmLabel: l10n.signOut,
        cancelLabel: l10n.cancel,
      );
      if (!confirmed) return;
    }
    final result = await action();
    if (!result.isOk && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.genericError)));
    }
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      ChapterSpacing.gutter,
      ChapterSpacing.xl,
      ChapterSpacing.gutter,
      ChapterSpacing.sm,
    ),
    child: Semantics(
      header: true,
      child: Text(label.toUpperCase(), style: context.textTheme.labelSmall),
    ),
  );
}

class _Avatar extends StatelessWidget {
  const _Avatar({this.name, this.photoUrl});

  final String? name;
  final String? photoUrl;

  @override
  Widget build(BuildContext context) {
    final colors = context.chapterColors;
    final initial = (name?.trim().isNotEmpty ?? false)
        ? name!.trim().characters.first.toUpperCase()
        : '?';
    final url = photoUrl;
    return ExcludeSemantics(
      child: CircleAvatar(
        radius: 32,
        backgroundColor: colors.accentSoft,
        foregroundImage: url == null ? null : CachedNetworkImageProvider(url),
        child: Text(initial, style: context.textTheme.headlineSmall),
      ),
    );
  }
}
