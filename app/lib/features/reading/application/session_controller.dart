import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/analytics.dart';
import '../../../app/providers.dart';
import '../../progress/domain/reading_position.dart';
import '../domain/reading_session.dart';
import 'session_service.dart';

/// The live reading session for the signed-in user, or `null`.
///
/// Loading it runs crash recovery ([SessionService.load]). Transitions are
/// serialized, so the 1-second ticker can't race a button press.
class SessionController extends AsyncNotifier<ActiveSession?> {
  Future<void> _queue = Future.value();

  SessionService get _svc => ref.read(sessionServiceProvider);

  @override
  Future<ActiveSession?> build() async {
    if (ref.watch(currentUserIdProvider) == null) return null;
    return _svc.load();
  }

  Future<T> _serial<T>(Future<T> Function() op) {
    final next = _queue.then((_) => op());
    _queue = next.then((_) {}, onError: (Object _) {});
    return next;
  }

  ActiveSession? get _current => state.value;

  Future<ActiveSession> start(String workId, Duration planned) => _serial(() async {
    final s = await _svc.start(workId: workId, planned: planned);
    state = AsyncData(s);
    unawaited(ref.read(profileRepositoryProvider).setDefaultTimer(planned.inMinutes));
    return s;
  });

  Future<void> pause() => _apply(_svc.pause);

  Future<void> resume() => _apply(_svc.resume);

  Future<void> end() => _apply(_svc.end);

  /// Ticker hook: ends the session when its time is up.
  Future<void> tick() => _apply(_svc.checkOverdue);

  Future<FocusResult> enableFocus() => _serial(() async {
    final s = _current;
    if (s == null) return FocusResult.failed;
    final (next, result) = await _svc.enableFocus(s);
    state = AsyncData(next);
    return result;
  });

  Future<void> disableFocus() => _apply(_svc.disableFocus);

  Future<ReadingSession?> save({required Duration readingTime, ReadingPosition? endPosition}) =>
      _serial(() async {
        final s = _current;
        if (s == null) return null;
        final saved = await _svc.save(s, readingTime: readingTime, endPosition: endPosition);
        ref.read(analyticsProvider)(AppEvent.sessionCompleted, duration: readingTime);
        state = const AsyncData(null);
        return saved;
      });

  Future<void> discard() => _serial(() async {
    final s = _current;
    if (s == null) return;
    await _svc.discard(s);
    state = const AsyncData(null);
  });

  Future<void> _apply(Future<ActiveSession> Function(ActiveSession) op) => _serial(() async {
    final s = _current;
    if (s == null) return;
    final next = await op(s);
    if (!identical(next, s)) state = AsyncData(next);
  });
}

final sessionControllerProvider = AsyncNotifierProvider<SessionController, ActiveSession?>(
  SessionController.new,
);
