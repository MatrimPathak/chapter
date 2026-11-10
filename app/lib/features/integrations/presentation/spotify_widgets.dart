import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/design_system/design_system.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../domain/spotify.dart';
import 'integrations_providers.dart';

/// Link, Reconnect or Unlink, in Profile. The only place to change the link.
class SpotifyLinkRow extends ConsumerStatefulWidget {
  const SpotifyLinkRow({super.key});

  @override
  ConsumerState<SpotifyLinkRow> createState() => _SpotifyLinkRowState();
}

class _SpotifyLinkRowState extends ConsumerState<SpotifyLinkRow> {
  // Spotify's login happens in the browser, so look again on the way back.
  late final _lifecycle = AppLifecycleListener(
    onResume: () => ref.invalidate(spotifyStatusProvider),
  );
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _lifecycle; // Starts listening.
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  Future<void> _link() async {
    if (_busy) return;
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    var opened = false;
    try {
      final url = await ref.read(spotifyRemoteProvider).beginLink();
      opened = await ref.read(linkOpenerProvider).open(url);
    } on Object {
      opened = false;
    }
    if (!opened) messenger.showSnackBar(SnackBar(content: Text(l10n.spotifyLinkFailed)));
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _unlink() async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showChapterConfirmDialog(
      context: context,
      title: l10n.spotifyUnlinkTitle,
      body: l10n.spotifyUnlinkBody,
      confirmLabel: l10n.spotifyUnlink,
      cancelLabel: l10n.cancel,
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref.read(spotifyRemoteProvider).disconnect();
      ref.invalidate(spotifyStatusProvider);
    } on Object {
      messenger.showSnackBar(SnackBar(content: Text(l10n.spotifyLinkFailed)));
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final status = ref.watch(spotifyStatusProvider).value ?? SpotifyStatus.hidden;
    final unlink = TextButton(
      key: const Key('spotify-unlink'),
      onPressed: _busy ? null : _unlink,
      child: Text(l10n.spotifyUnlink),
    );
    final name = status.displayName;
    return switch (status.state) {
      SpotifyLinkState.hidden => const SizedBox.shrink(),
      SpotifyLinkState.unlinked => ListTile(
        key: const Key('spotify-link'),
        leading: const Icon(Icons.music_note_outlined),
        title: Text(l10n.spotifyLink),
        subtitle: Text(l10n.spotifyLinkBody),
        trailing: const Icon(Icons.open_in_new, size: 18),
        enabled: !_busy,
        onTap: _link,
      ),
      SpotifyLinkState.linked => ListTile(
        key: const Key('spotify-linked'),
        leading: const Icon(Icons.music_note_outlined),
        title: Text(l10n.integrationSpotify),
        subtitle: Text(name == null ? l10n.spotifyLinked : l10n.spotifyLinkedAs(name)),
        trailing: unlink,
      ),
      SpotifyLinkState.reconnect => ListTile(
        key: const Key('spotify-reconnect'),
        leading: const Icon(Icons.music_note_outlined),
        title: Text(l10n.spotifyReconnect),
        subtitle: Text(l10n.spotifyReconnectBody),
        trailing: unlink,
        enabled: !_busy,
        onTap: _link,
      ),
    };
  }
}

/// What's playing, on the reading timer, for linked users only. Polls only
/// while this is on screen and the app is visible. If Spotify fails, this
/// simply isn't there; the timer never depends on it.
class SpotifyNowPlayingCard extends ConsumerStatefulWidget {
  const SpotifyNowPlayingCard({super.key});

  static const pollInterval = Duration(seconds: 15);
  static const retryInterval = Duration(seconds: 60);
  static const afterCommand = Duration(milliseconds: 1500);

  @override
  ConsumerState<SpotifyNowPlayingCard> createState() => _SpotifyNowPlayingCardState();
}

class _SpotifyNowPlayingCardState extends ConsumerState<SpotifyNowPlayingCard> {
  late final AppLifecycleListener _lifecycle;
  Timer? _timer;
  SpotifyTrack? _track;
  bool _linked = false;
  bool _visible = true;
  bool _fetching = false;
  bool _loaded = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onHide: () {
        _visible = false;
        _timer?.cancel();
      },
      onShow: () {
        _visible = true;
        unawaited(_poll());
      },
    );
    ref.listenManual(spotifyStatusProvider, (_, next) {
      final linked = next.value?.state == SpotifyLinkState.linked;
      if (linked == _linked) return;
      _linked = linked;
      if (linked) {
        unawaited(_poll());
      } else {
        _timer?.cancel();
      }
    }, fireImmediately: true);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _lifecycle.dispose();
    super.dispose();
  }

  void _schedule(Duration delay) {
    _timer?.cancel();
    if (mounted && _linked && _visible) _timer = Timer(delay, () => unawaited(_poll()));
  }

  Future<void> _poll() async {
    _timer?.cancel();
    if (!_linked || !_visible || _fetching) return;
    _fetching = true;
    var next = SpotifyNowPlayingCard.pollInterval;
    try {
      final track = await ref.read(spotifyRemoteProvider).nowPlaying();
      if (mounted) {
        setState(() {
          _track = track;
          _loaded = true;
          _failed = false;
        });
      }
    } on SpotifyException catch (e) {
      if (!mounted) return;
      setState(() => _failed = true);
      if (_endsLink(e.failure)) {
        ref.invalidate(spotifyStatusProvider);
        return;
      }
      next = SpotifyNowPlayingCard.retryInterval;
    } finally {
      _fetching = false;
    }
    _schedule(next);
  }

  static bool _endsLink(SpotifyFailure failure) =>
      failure == SpotifyFailure.reconnect || failure == SpotifyFailure.notLinked;

  /// Runs a playback command, then shows the result once Spotify has caught up.
  Future<bool> _command(Future<void> Function() run) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await run();
    } on SpotifyException catch (e) {
      if (_endsLink(e.failure)) ref.invalidate(spotifyStatusProvider);
      messenger.showSnackBar(
        SnackBar(
          content: Text(switch (e.failure) {
            SpotifyFailure.noDevice => l10n.spotifyNoDevice,
            SpotifyFailure.premiumRequired => l10n.spotifyPremiumRequired,
            _ => l10n.spotifyCommandFailed,
          }),
        ),
      );
      return false;
    }
    _schedule(SpotifyNowPlayingCard.afterCommand);
    return true;
  }

  Future<void> _toggle(SpotifyTrack track) async {
    final remote = ref.read(spotifyRemoteProvider);
    final done = await _command(track.isPlaying ? remote.pause : remote.play);
    if (done && mounted) setState(() => _track = track.withPlaying(!track.isPlaying));
  }

  Future<void> _choosePlaylist() async {
    final playlist = await showChapterSheet<SpotifyPlaylist>(
      context: context,
      title: AppLocalizations.of(context).spotifyPlaylistsTitle,
      builder: (_) => const _PlaylistList(),
    );
    if (playlist == null || !mounted) return;
    final remote = ref.read(spotifyRemoteProvider);
    await _command(() => remote.play(playlistId: playlist.id));
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(spotifyStatusProvider).value;
    if (status?.state != SpotifyLinkState.linked || !_loaded || _failed) {
      return const SizedBox.shrink();
    }
    final l10n = AppLocalizations.of(context);
    final track = _track;
    final choose = IconButton(
      key: const Key('spotify-choose-playlist'),
      icon: const Icon(Icons.queue_music_rounded),
      tooltip: l10n.spotifyChoosePlaylist,
      onPressed: () => unawaited(_choosePlaylist()),
    );
    return Padding(
      padding: const EdgeInsets.only(top: ChapterSpacing.md),
      child: ChapterCard(
        key: const Key('spotify-card'),
        child: track == null
            ? Row(
                children: [
                  const Icon(Icons.music_note_outlined),
                  const SizedBox(width: ChapterSpacing.md),
                  Expanded(child: Text(l10n.spotifyNothingPlaying)),
                  choose,
                ],
              )
            : Row(
                children: [
                  Expanded(child: _TrackDetails(track: track)),
                  choose,
                  IconButton(
                    key: const Key('spotify-toggle'),
                    icon: Icon(track.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded),
                    tooltip: track.isPlaying ? l10n.spotifyPause : l10n.spotifyPlay,
                    onPressed: () => unawaited(_toggle(track)),
                  ),
                ],
              ),
      ),
    );
  }
}

/// Cover art, title, artist and attribution, linking back as Spotify requires.
class _TrackDetails extends ConsumerWidget {
  const _TrackDetails({required this.track});

  final SpotifyTrack track;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final url = track.url;
    return Semantics(
      button: url != null,
      hint: url == null ? null : l10n.spotifyOpenTrack,
      child: GestureDetector(
        key: const Key('spotify-track'),
        behavior: HitTestBehavior.opaque,
        onTap: url == null ? null : () => unawaited(openExternal(context, ref, Uri.parse(url))),
        child: Row(
          children: [
            _Artwork(url: track.imageUrl),
            const SizedBox(width: ChapterSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                  if (track.artists.isNotEmpty)
                    Text(
                      track.artists.join(', '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.textTheme.bodySmall,
                    ),
                  Text(l10n.spotifyOnSpotify, style: context.textTheme.labelSmall),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Artwork extends StatelessWidget {
  const _Artwork({required this.url});

  final String? url;

  @override
  Widget build(BuildContext context) {
    const fallback = Icon(Icons.music_note_outlined);
    final image = url;
    // A fixed size also keeps the timer's intrinsic layout away from the image.
    return SizedBox.square(
      dimension: 48,
      child: image == null
          ? fallback
          : ClipRRect(
              borderRadius: BorderRadius.circular(ChapterSpacing.xs),
              child: CachedNetworkImage(
                imageUrl: image,
                fit: BoxFit.cover,
                errorWidget: (_, _, _) => fallback,
              ),
            ),
    );
  }
}

class _PlaylistList extends ConsumerStatefulWidget {
  const _PlaylistList();

  @override
  ConsumerState<_PlaylistList> createState() => _PlaylistListState();
}

class _PlaylistListState extends ConsumerState<_PlaylistList> {
  late final Future<List<SpotifyPlaylist>> _playlists = ref.read(spotifyRemoteProvider).playlists();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return FutureBuilder(
      future: _playlists,
      builder: (context, snapshot) {
        if (snapshot.hasError) return Text(l10n.spotifyPlaylistsFailed);
        final playlists = snapshot.data;
        if (playlists == null) {
          return const Center(child: CircularProgressIndicator());
        }
        if (playlists.isEmpty) return Text(l10n.spotifyPlaylistsEmpty);
        return ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.6),
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final playlist in playlists)
                ListTile(
                  key: ValueKey('spotify-playlist-${playlist.id}'),
                  contentPadding: EdgeInsets.zero,
                  leading: _Artwork(url: playlist.imageUrl),
                  title: Text(playlist.name, maxLines: 2, overflow: TextOverflow.ellipsis),
                  onTap: () => Navigator.of(context).pop(playlist),
                ),
            ],
          ),
        );
      },
    );
  }
}
