import 'package:chapter/app/providers.dart';
import 'package:chapter/core/design_system/design_system.dart';
import 'package:chapter/features/catalog/data/catalog_remote.dart';
import 'package:chapter/features/integrations/data/platform_ports.dart';
import 'package:chapter/features/integrations/data/spotify_remote.dart';
import 'package:chapter/features/integrations/domain/spotify.dart';
import 'package:chapter/features/integrations/presentation/integrations_providers.dart';
import 'package:chapter/features/integrations/presentation/spotify_widgets.dart';
import 'package:chapter/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _track = SpotifyTrack(
  title: 'Gymnopédie No.1',
  artists: ['Erik Satie'],
  isPlaying: true,
  url: 'https://open.spotify.com/track/1',
);

class _FakeRemote implements SpotifyRemote {
  SpotifyStatus current = const SpotifyStatus(SpotifyLinkState.unlinked);
  Object? statusError;
  SpotifyTrack? track = _track;
  SpotifyFailure? nowPlayingFailure;
  SpotifyFailure? commandFailure;
  Object? beginLinkError;
  List<SpotifyPlaylist> lists = const [SpotifyPlaylist(id: 'abc123defg', name: 'Focus')];

  int statusCalls = 0;
  int nowPlayingCalls = 0;
  int beginLinkCalls = 0;
  int disconnectCalls = 0;
  int pauseCalls = 0;
  final played = <String?>[];

  @override
  Future<SpotifyStatus> status() async {
    statusCalls++;
    final error = statusError;
    if (error != null) throw error;
    return current;
  }

  @override
  Future<Uri> beginLink() async {
    beginLinkCalls++;
    final error = beginLinkError;
    if (error != null) throw error;
    return Uri.parse('https://accounts.spotify.com/authorize?x=1');
  }

  @override
  Future<void> disconnect() async {
    disconnectCalls++;
    current = const SpotifyStatus(SpotifyLinkState.unlinked);
  }

  @override
  Future<SpotifyTrack?> nowPlaying() async {
    nowPlayingCalls++;
    final failure = nowPlayingFailure;
    if (failure != null) throw SpotifyException(failure);
    return track;
  }

  @override
  Future<List<SpotifyPlaylist>> playlists() async => lists;

  void _command() {
    final failure = commandFailure;
    if (failure != null) throw SpotifyException(failure);
  }

  @override
  Future<void> play({String? playlistId}) async {
    _command();
    played.add(playlistId);
  }

  @override
  Future<void> pause() async {
    _command();
    pauseCalls++;
  }
}

class _FakeOpener implements LinkOpener {
  final opened = <Uri>[];
  bool result = true;

  @override
  Future<bool> open(Uri uri) async {
    opened.add(uri);
    return result;
  }
}

class _FakeCatalogRemote implements CatalogRemote {
  Map<String, dynamic> response = const {};
  Object? error;
  String? name;
  Map<String, Object?>? data;

  @override
  Future<Map<String, dynamic>> call(String name, Map<String, Object?> data) async {
    this.name = name;
    this.data = data;
    final e = error;
    if (e != null) throw e;
    return response;
  }
}

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  required _FakeRemote remote,
  _FakeOpener? opener,
  String? uid = 'u1',
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        spotifyRemoteProvider.overrideWithValue(remote),
        linkOpenerProvider.overrideWithValue(opener ?? _FakeOpener()),
        currentUserIdProvider.overrideWithValue(uid),
      ],
      child: MaterialApp(
        theme: ChapterTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: Center(child: child)),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

void _setLifecycle(WidgetTester tester, List<AppLifecycleState> states) {
  for (final state in states) {
    tester.binding.handleAppLifecycleStateChanged(state);
  }
}

const _hide = [AppLifecycleState.inactive, AppLifecycleState.hidden];
const _show = [AppLifecycleState.inactive, AppLifecycleState.resumed];

/// Removes the widget so its timers end before the test does.
Future<void> _finish(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump();
}

void main() {
  const linked = SpotifyStatus(SpotifyLinkState.linked, displayName: 'Ada');

  group('SpotifyLinkRow', () {
    testWidgets('offers Link Spotify to a signed-in user', (tester) async {
      await _pump(tester, const SpotifyLinkRow(), remote: _FakeRemote());
      expect(find.text('Link Spotify'), findsOneWidget);
    });

    testWidgets('shows nothing when the server is not configured', (tester) async {
      final remote = _FakeRemote()..current = SpotifyStatus.hidden;
      await _pump(tester, const SpotifyLinkRow(), remote: remote);
      expect(find.byKey(const Key('spotify-link')), findsNothing);
    });

    testWidgets('shows nothing when the status check fails', (tester) async {
      final remote = _FakeRemote()..statusError = StateError('offline');
      await _pump(tester, const SpotifyLinkRow(), remote: remote);
      expect(find.byKey(const Key('spotify-link')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('makes no call when nobody is signed in', (tester) async {
      final remote = _FakeRemote();
      await _pump(tester, const SpotifyLinkRow(), remote: remote, uid: null);
      expect(remote.statusCalls, 0);
    });

    testWidgets("opens Spotify's login page", (tester) async {
      final opener = _FakeOpener();
      await _pump(tester, const SpotifyLinkRow(), remote: _FakeRemote(), opener: opener);
      await tester.tap(find.byKey(const Key('spotify-link')));
      await tester.pump();
      await tester.pump();
      expect(opener.opened.single.host, 'accounts.spotify.com');
    });

    testWidgets('explains when the login page cannot open', (tester) async {
      final opener = _FakeOpener()..result = false;
      await _pump(tester, const SpotifyLinkRow(), remote: _FakeRemote(), opener: opener);
      await tester.tap(find.byKey(const Key('spotify-link')));
      await tester.pump();
      await tester.pump();
      expect(find.text('Couldn’t reach Spotify. Try again.'), findsOneWidget);
    });

    testWidgets('explains when starting the login fails', (tester) async {
      final remote = _FakeRemote()..beginLinkError = StateError('down');
      await _pump(tester, const SpotifyLinkRow(), remote: remote);
      await tester.tap(find.byKey(const Key('spotify-link')));
      await tester.pump();
      await tester.pump();
      expect(find.text('Couldn’t reach Spotify. Try again.'), findsOneWidget);
    });

    testWidgets('shows the account after returning from the browser', (tester) async {
      final remote = _FakeRemote();
      await _pump(tester, const SpotifyLinkRow(), remote: remote);
      remote.current = linked;
      _setLifecycle(tester, _hide);
      _setLifecycle(tester, _show);
      await tester.pump();
      await tester.pump();
      expect(find.text('Linked as Ada'), findsOneWidget);
    });

    testWidgets('unlinks after confirming', (tester) async {
      final remote = _FakeRemote()..current = linked;
      await _pump(tester, const SpotifyLinkRow(), remote: remote);
      await tester.tap(find.byKey(const Key('spotify-unlink')));
      await tester.pumpAndSettle();
      expect(remote.disconnectCalls, 0);
      await tester.tap(find.widgetWithText(TextButton, 'Unlink').last);
      await tester.pumpAndSettle();
      expect(remote.disconnectCalls, 1);
      expect(find.text('Link Spotify'), findsOneWidget);
    });

    testWidgets('keeps the link when unlinking is cancelled', (tester) async {
      final remote = _FakeRemote()..current = linked;
      await _pump(tester, const SpotifyLinkRow(), remote: remote);
      await tester.tap(find.byKey(const Key('spotify-unlink')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(remote.disconnectCalls, 0);
    });

    testWidgets('offers Reconnect and Unlink after a login expires', (tester) async {
      final opener = _FakeOpener();
      final remote = _FakeRemote()..current = const SpotifyStatus(SpotifyLinkState.reconnect);
      await _pump(tester, const SpotifyLinkRow(), remote: remote, opener: opener);
      expect(find.text('Reconnect Spotify'), findsOneWidget);
      expect(find.byKey(const Key('spotify-unlink')), findsOneWidget);
      await tester.tap(find.text('Reconnect Spotify'));
      await tester.pump();
      await tester.pump();
      expect(opener.opened, hasLength(1));
    });
  });

  group('SpotifyNowPlayingCard', () {
    testWidgets('does nothing for someone who has not linked', (tester) async {
      final remote = _FakeRemote();
      await _pump(tester, const SpotifyNowPlayingCard(), remote: remote);
      await tester.pump(const Duration(minutes: 1));
      expect(remote.nowPlayingCalls, 0);
      expect(find.byKey(const Key('spotify-card')), findsNothing);
    });

    testWidgets('shows the track, artist and Spotify attribution', (tester) async {
      final remote = _FakeRemote()..current = linked;
      await _pump(tester, const SpotifyNowPlayingCard(), remote: remote);
      expect(find.text('Gymnopédie No.1'), findsOneWidget);
      expect(find.text('Erik Satie'), findsOneWidget);
      expect(find.text('On Spotify'), findsOneWidget);
      await _finish(tester);
    });

    testWidgets('links back to the track on Spotify', (tester) async {
      final opener = _FakeOpener();
      final remote = _FakeRemote()..current = linked;
      await _pump(tester, const SpotifyNowPlayingCard(), remote: remote, opener: opener);
      await tester.tap(find.byKey(const Key('spotify-track')));
      await tester.pump();
      expect(opener.opened.single.toString(), _track.url);
      await _finish(tester);
    });

    testWidgets('polls every 15 seconds', (tester) async {
      final remote = _FakeRemote()..current = linked;
      await _pump(tester, const SpotifyNowPlayingCard(), remote: remote);
      expect(remote.nowPlayingCalls, 1);
      await tester.pump(const Duration(seconds: 14));
      expect(remote.nowPlayingCalls, 1);
      await tester.pump(const Duration(seconds: 1));
      expect(remote.nowPlayingCalls, 2);
      await _finish(tester);
    });

    testWidgets('stops polling while the app is hidden and resumes after', (tester) async {
      final remote = _FakeRemote()..current = linked;
      await _pump(tester, const SpotifyNowPlayingCard(), remote: remote);
      _setLifecycle(tester, _hide);
      await tester.pump(const Duration(minutes: 5));
      expect(remote.nowPlayingCalls, 1);
      _setLifecycle(tester, _show);
      await tester.pump();
      expect(remote.nowPlayingCalls, 2);
      await _finish(tester);
    });

    testWidgets('stops polling when removed from the screen', (tester) async {
      final remote = _FakeRemote()..current = linked;
      await _pump(tester, const SpotifyNowPlayingCard(), remote: remote);
      await _finish(tester);
      await tester.pump(const Duration(minutes: 5));
      expect(remote.nowPlayingCalls, 1);
    });

    testWidgets('hides itself on failure and retries a minute later', (tester) async {
      final remote = _FakeRemote()
        ..current = linked
        ..nowPlayingFailure = SpotifyFailure.other;
      await _pump(tester, const SpotifyNowPlayingCard(), remote: remote);
      expect(find.byKey(const Key('spotify-card')), findsNothing);
      await tester.pump(const Duration(seconds: 59));
      expect(remote.nowPlayingCalls, 1);
      remote.nowPlayingFailure = null;
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(remote.nowPlayingCalls, 2);
      expect(find.byKey(const Key('spotify-card')), findsOneWidget);
      await _finish(tester);
    });

    testWidgets('stops when the login has expired', (tester) async {
      final remote = _FakeRemote()
        ..current = linked
        ..nowPlayingFailure = SpotifyFailure.reconnect;
      await _pump(tester, const SpotifyNowPlayingCard(), remote: remote);
      remote.current = const SpotifyStatus(SpotifyLinkState.reconnect);
      await tester.pump();
      await tester.pump();
      expect(remote.statusCalls, 2);
      await tester.pump(const Duration(minutes: 5));
      expect(remote.nowPlayingCalls, 1);
      expect(find.byKey(const Key('spotify-card')), findsNothing);
    });

    testWidgets('pauses and refreshes soon after', (tester) async {
      final remote = _FakeRemote()..current = linked;
      await _pump(tester, const SpotifyNowPlayingCard(), remote: remote);
      await tester.tap(find.byKey(const Key('spotify-toggle')));
      await tester.pump();
      expect(remote.pauseCalls, 1);
      expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
      await tester.pump(SpotifyNowPlayingCard.afterCommand);
      expect(remote.nowPlayingCalls, 2);
      await _finish(tester);
    });

    testWidgets('resumes a paused track without choosing a playlist', (tester) async {
      final remote = _FakeRemote()
        ..current = linked
        ..track = _track.withPlaying(false);
      await _pump(tester, const SpotifyNowPlayingCard(), remote: remote);
      await tester.tap(find.byKey(const Key('spotify-toggle')));
      await tester.pump();
      expect(remote.played, [null]);
      await _finish(tester);
    });

    for (final (failure, message) in const [
      (SpotifyFailure.noDevice, 'Open Spotify on one of your devices, then try again.'),
      (SpotifyFailure.premiumRequired, 'Controlling playback needs Spotify Premium.'),
      (SpotifyFailure.other, 'Spotify couldn’t do that. Try again.'),
    ]) {
      testWidgets('explains $failure', (tester) async {
        final remote = _FakeRemote()
          ..current = linked
          ..commandFailure = failure;
        await _pump(tester, const SpotifyNowPlayingCard(), remote: remote);
        await tester.tap(find.byKey(const Key('spotify-toggle')));
        await tester.pump();
        expect(find.text(message), findsOneWidget);
        expect(find.byIcon(Icons.pause_rounded), findsOneWidget);
        await _finish(tester);
      });
    }

    testWidgets('offers playlists when nothing is playing, and starts one', (tester) async {
      final remote = _FakeRemote()
        ..current = linked
        ..track = null;
      await _pump(tester, const SpotifyNowPlayingCard(), remote: remote);
      expect(find.text('Nothing playing on Spotify'), findsOneWidget);
      await tester.tap(find.byKey(const Key('spotify-choose-playlist')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Focus'));
      await tester.pumpAndSettle();
      expect(remote.played, ['abc123defg']);
      await _finish(tester);
    });
  });

  group('status provider', () {
    test('turns any failure into hidden', () async {
      final remote = _FakeRemote()..statusError = StateError('offline');
      final container = ProviderContainer(
        overrides: [
          spotifyRemoteProvider.overrideWithValue(remote),
          currentUserIdProvider.overrideWithValue('u1'),
        ],
      );
      addTearDown(container.dispose);
      final status = await container.read(spotifyStatusProvider.future);
      expect(status.state, SpotifyLinkState.hidden);
    });
  });

  group('CallableSpotifyRemote', () {
    late _FakeCatalogRemote fake;
    late CallableSpotifyRemote remote;

    setUp(() {
      fake = _FakeCatalogRemote();
      remote = CallableSpotifyRemote(fake);
    });

    test('hides the row when the server is not configured', () async {
      fake.response = {'available': false, 'state': 'unlinked', 'displayName': null};
      expect((await remote.status()).state, SpotifyLinkState.hidden);
    });

    test('reads a linked status', () async {
      fake.response = {'available': true, 'state': 'linked', 'displayName': 'Ada'};
      final status = await remote.status();
      expect(status.state, SpotifyLinkState.linked);
      expect(status.displayName, 'Ada');
    });

    test('reads a track and no track', () async {
      fake.response = {
        'track': {
          'title': 'Song',
          'artists': <Object?>['A'],
          'isPlaying': true,
          'imageUrl': null,
          'url': null,
        },
      };
      expect((await remote.nowPlaying())?.title, 'Song');
      fake.response = {'track': null};
      expect(await remote.nowPlaying(), isNull);
    });

    test('omits the playlist when resuming', () async {
      fake.response = {'ok': true};
      await remote.play();
      expect(fake.data, isEmpty);
      await remote.play(playlistId: 'abc');
      expect(fake.data, {'playlistId': 'abc'});
    });

    for (final (message, failure) in const [
      ('not-linked', SpotifyFailure.notLinked),
      ('reconnect', SpotifyFailure.reconnect),
      ('no-device', SpotifyFailure.noDevice),
      ('premium-required', SpotifyFailure.premiumRequired),
      ('rate-limited', SpotifyFailure.other),
    ]) {
      test('maps $message', () async {
        fake.error = CatalogRemoteException('failed-precondition', message);
        await expectLater(
          remote.pause(),
          throwsA(isA<SpotifyException>().having((e) => e.failure, 'failure', failure)),
        );
      });
    }

    test('wraps unexpected errors', () async {
      fake.error = StateError('no firebase');
      await expectLater(
        remote.nowPlaying(),
        throwsA(isA<SpotifyException>().having((e) => e.failure, 'f', SpotifyFailure.other)),
      );
    });
  });
}
