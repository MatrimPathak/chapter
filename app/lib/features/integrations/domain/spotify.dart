import 'package:flutter/foundation.dart';

/// `hidden` covers anything that means the row can't work right now: not
/// signed in, not configured on the server, or a failed status check.
enum SpotifyLinkState { hidden, unlinked, linked, reconnect }

@immutable
final class SpotifyStatus {
  const SpotifyStatus(this.state, {this.displayName});

  factory SpotifyStatus.fromJson(Map<String, dynamic> json) {
    if (json['available'] != true) return hidden;
    return SpotifyStatus(switch (json['state']) {
      'linked' => SpotifyLinkState.linked,
      'reconnect' => SpotifyLinkState.reconnect,
      _ => SpotifyLinkState.unlinked,
    }, displayName: json['displayName'] as String?);
  }

  static const hidden = SpotifyStatus(SpotifyLinkState.hidden);

  final SpotifyLinkState state;
  final String? displayName;
}

/// Shown while it plays. Never stored: Spotify's policy rules out keeping
/// listening data or building statistics from it.
@immutable
final class SpotifyTrack {
  const SpotifyTrack({
    required this.title,
    required this.artists,
    required this.isPlaying,
    this.imageUrl,
    this.url,
  });

  factory SpotifyTrack.fromJson(Map<String, dynamic> json) => SpotifyTrack(
    title: json['title'] as String,
    artists: [for (final a in json['artists'] as List<dynamic>) a as String],
    isPlaying: json['isPlaying'] == true,
    imageUrl: json['imageUrl'] as String?,
    url: json['url'] as String?,
  );

  final String title;
  final List<String> artists;
  final bool isPlaying;
  final String? imageUrl;
  final String? url;

  SpotifyTrack withPlaying(bool playing) => SpotifyTrack(
    title: title,
    artists: artists,
    isPlaying: playing,
    imageUrl: imageUrl,
    url: url,
  );
}

@immutable
final class SpotifyPlaylist {
  const SpotifyPlaylist({required this.id, required this.name, this.imageUrl});

  factory SpotifyPlaylist.fromJson(Map<String, dynamic> json) => SpotifyPlaylist(
    id: json['id'] as String,
    name: json['name'] as String,
    imageUrl: json['imageUrl'] as String?,
  );

  final String id;
  final String name;
  final String? imageUrl;
}

enum SpotifyFailure { notLinked, reconnect, noDevice, premiumRequired, other }

final class SpotifyException implements Exception {
  const SpotifyException(this.failure);

  final SpotifyFailure failure;

  @override
  String toString() => 'SpotifyException($failure)';
}
