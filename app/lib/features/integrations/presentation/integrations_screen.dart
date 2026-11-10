import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/router/routes.dart';
import '../../../core/design_system/design_system.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../domain/integration.dart';
import '../domain/spotify.dart';
import 'integrations_providers.dart';

/// Profile → Connected services. Says plainly what each one does and doesn't
/// do. A failure shows on its own card only.
class IntegrationsScreen extends ConsumerWidget {
  const IntegrationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final integrations = ref.watch(integrationsProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.integrationsTitle)),
      body: ListView(
        padding: const EdgeInsets.all(ChapterSpacing.gutter),
        children: [for (final i in integrations) _Card(id: i.id)],
      ),
    );
  }
}

class _Card extends ConsumerWidget {
  const _Card({required this.id});

  final IntegrationId id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final status = ref.watch(integrationStatusProvider(id)).value;
    final unavailable = status == IntegrationStatus.unavailable;
    final (title, body, action) = switch (id) {
      IntegrationId.goodreads => (
        l10n.integrationGoodreads,
        l10n.integrationGoodreadsBody,
        l10n.integrationChooseFile,
      ),
      IntegrationId.storygraph => (
        l10n.integrationStorygraph,
        l10n.integrationStorygraphBody,
        l10n.integrationChooseFile,
      ),
      IntegrationId.kindle => (
        l10n.integrationKindle,
        l10n.integrationKindleBody,
        l10n.integrationChooseFile,
      ),
      IntegrationId.audible => (l10n.integrationAudible, l10n.integrationAudibleBody, null),
      IntegrationId.spotify => (
        l10n.integrationSpotify,
        ref.watch(spotifyStatusProvider).value?.state == SpotifyLinkState.linked
            ? l10n.integrationSpotifyBodyLinked
            : l10n.integrationSpotifyBody,
        l10n.integrationOpenLinks,
      ),
    };
    return Card(
      key: ValueKey('integration-${id.name}'),
      margin: const EdgeInsets.only(bottom: ChapterSpacing.md),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(ChapterSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(header: true, child: Text(title, style: context.textTheme.headlineSmall)),
            const SizedBox(height: ChapterSpacing.xs),
            Text(body, style: context.textTheme.bodyMedium),
            if (unavailable) ...[
              const SizedBox(height: ChapterSpacing.sm),
              Text(
                l10n.integrationUnavailable,
                key: ValueKey('integration-${id.name}-unavailable'),
                style: context.textTheme.bodySmall,
              ),
            ] else if (action != null) ...[
              const SizedBox(height: ChapterSpacing.sm),
              ChapterButton(
                key: ValueKey('integration-${id.name}-action'),
                label: action,
                variant: ChapterButtonVariant.secondary,
                onPressed: () => _open(context, ref),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _open(BuildContext context, WidgetRef ref) {
    switch (id) {
      case IntegrationId.goodreads || IntegrationId.storygraph:
        context.push(AppRoutes.importCsv);
      case IntegrationId.kindle:
        context.push(AppRoutes.importClippings);
      case IntegrationId.spotify:
        showMusicSheet(context, ref);
      case IntegrationId.audible:
        break;
    }
  }
}
