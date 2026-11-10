import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/design_system/design_system.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../domain/integration.dart';
import '../domain/spotify.dart';

/// One integration's status. The provider is the boundary: anything it does
/// wrong becomes "unavailable" on its own card and goes no further.
final integrationStatusProvider = StreamProvider.family<IntegrationStatus, IntegrationId>((
  ref,
  id,
) async* {
  try {
    final integration = ref.watch(integrationsProvider).firstWhere((i) => i.id == id);
    // `yield*` forwards stream errors past a catch, so convert them here.
    yield* integration.status.transform(
      StreamTransformer.fromHandlers(
        handleError: (_, _, sink) => sink.add(IntegrationStatus.unavailable),
      ),
    );
  } on Object {
    yield IntegrationStatus.unavailable;
  }
}, retry: (_, _) => null);

/// This user's Spotify link. Any failure means "not shown", never an error.
final spotifyStatusProvider = FutureProvider<SpotifyStatus>((ref) async {
  if (ref.watch(currentUserIdProvider) == null) return SpotifyStatus.hidden;
  try {
    return await ref.watch(spotifyRemoteProvider).status();
  } on Object {
    return SpotifyStatus.hidden;
  }
}, retry: (_, _) => null);

/// Opens [uri]; a failure only shows a message.
Future<void> openExternal(BuildContext context, WidgetRef ref, Uri uri) async {
  final l10n = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.of(context);
  var opened = false;
  try {
    opened = await ref.read(linkOpenerProvider).open(uri);
  } on Object {
    opened = false;
  }
  if (!opened) messenger.showSnackBar(SnackBar(content: Text(l10n.integrationLinkFailed)));
}

/// The Spotify links. Spotify opens them, linked account or not.
Future<void> showMusicSheet(BuildContext context, WidgetRef ref) {
  final l10n = AppLocalizations.of(context);
  return showChapterSheet<void>(
    context: context,
    title: l10n.musicTitle,
    builder: (sheet) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          ref.read(spotifyStatusProvider).value?.state == SpotifyLinkState.linked
              ? l10n.musicBodyLinked
              : l10n.musicBody,
          style: context.textTheme.bodyMedium,
        ),
        const SizedBox(height: ChapterSpacing.sm),
        for (final (label, query) in [
          (l10n.musicLinkReading, ExternalLinks.readingSearch),
          (l10n.musicLinkClassical, ExternalLinks.classicalSearch),
          (l10n.musicLinkAmbient, ExternalLinks.ambientSearch),
        ])
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.music_note_outlined),
            title: Text(label),
            trailing: const Icon(Icons.open_in_new, size: 18),
            onTap: () => openExternal(context, ref, ExternalLinks.spotifySearch(query)),
          ),
      ],
    ),
  );
}

/// On the Read tab. If Spotify's integration fails, this simply isn't there.
class MusicCard extends ConsumerWidget {
  const MusicCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(integrationStatusProvider(IntegrationId.spotify)).value;
    if (status != IntegrationStatus.available) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    return ListTile(
      key: const Key('music-card'),
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.music_note_outlined),
      title: Text(l10n.musicTitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => showMusicSheet(context, ref),
    );
  }
}
