import '../../catalog/data/catalog_remote.dart';
import '../domain/spotify.dart';

/// Spotify callables. Tokens stay on the server: nothing here can see one.
abstract interface class SpotifyRemote {
  Future<SpotifyStatus> status();

  /// The address of Spotify's login page for this user.
  Future<Uri> beginLink();
  Future<void> disconnect();
  Future<SpotifyTrack?> nowPlaying();
  Future<List<SpotifyPlaylist>> playlists();

  /// Starts [playlistId], or resumes what was playing when it is `null`.
  Future<void> play({String? playlistId});
  Future<void> pause();
}

class CallableSpotifyRemote implements SpotifyRemote {
  const CallableSpotifyRemote(this._remote);

  final CatalogRemote _remote;

  /// Every failure leaves here as a [SpotifyException].
  Future<Map<String, dynamic>> _call(String name, [Map<String, Object?> data = const {}]) async {
    try {
      return await _remote.call(name, data);
    } on CatalogRemoteException catch (e) {
      throw SpotifyException(switch (e.message) {
        'not-linked' => SpotifyFailure.notLinked,
        'reconnect' => SpotifyFailure.reconnect,
        'no-device' => SpotifyFailure.noDevice,
        'premium-required' => SpotifyFailure.premiumRequired,
        _ => SpotifyFailure.other,
      });
    } on Object {
      throw const SpotifyException(SpotifyFailure.other);
    }
  }

  @override
  Future<SpotifyStatus> status() async => SpotifyStatus.fromJson(await _call('spotifyStatus'));

  @override
  Future<Uri> beginLink() async => Uri.parse((await _call('spotifyBeginLink'))['url'] as String);

  @override
  Future<void> disconnect() => _call('spotifyDisconnect');

  @override
  Future<SpotifyTrack?> nowPlaying() async {
    final track = (await _call('spotifyNowPlaying'))['track'];
    return track is Map<String, dynamic> ? SpotifyTrack.fromJson(track) : null;
  }

  @override
  Future<List<SpotifyPlaylist>> playlists() async => [
    for (final p in (await _call('spotifyListPlaylists'))['playlists'] as List<dynamic>)
      SpotifyPlaylist.fromJson(p as Map<String, dynamic>),
  ];

  @override
  Future<void> play({String? playlistId}) => _call('spotifyPlay', {'playlistId': ?playlistId});

  @override
  Future<void> pause() => _call('spotifyPause');
}
