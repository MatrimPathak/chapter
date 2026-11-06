import 'package:meta/meta.dart';

/// A pause inside a session. [end] is `null` while paused.
@immutable
class PauseInterval {
  const PauseInterval(this.start, [this.end]);

  final DateTime start;
  final DateTime? end;

  Duration lengthAt(DateTime now) {
    final e = end ?? now;
    return e.isBefore(start) ? Duration.zero : e.difference(start);
  }

  Map<String, Object?> toJson() => {
    'start': start.toUtc().toIso8601String(),
    if (end != null) 'end': end!.toUtc().toIso8601String(),
  };

  static PauseInterval fromJson(Map<String, Object?> j) => PauseInterval(
    DateTime.parse(j['start']! as String),
    j['end'] == null ? null : DateTime.parse(j['end']! as String),
  );

  @override
  bool operator ==(Object other) =>
      other is PauseInterval && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);
}

enum ClockState { running, paused, ended }

/// Timestamp-based session timer (docs/05 §2.7).
///
/// Elapsed time is *derived* — `now − startedAt − Σ pauses`, capped at the
/// planned duration — never accumulated by a ticking timer, so it survives
/// the process being killed. If the device clock moves backwards past the
/// last transition, time is clamped at that transition and the session is
/// flagged ([clockAdjusted]) for the summary.
@immutable
class SessionClock {
  const SessionClock({
    required this.startedAt,
    required this.planned,
    required this.lastTransitionAt,
    this.pauses = const [],
    this.endedAt,
    this.clockAdjusted = false,
  });

  factory SessionClock.start(DateTime now, Duration planned) =>
      SessionClock(startedAt: now, planned: planned, lastTransitionAt: now);

  final DateTime startedAt;
  final Duration planned;
  final List<PauseInterval> pauses;
  final DateTime? endedAt;

  /// Latest transition time; guards against the clock moving backwards.
  final DateTime lastTransitionAt;
  final bool clockAdjusted;

  ClockState get state => endedAt != null
      ? ClockState.ended
      : (pauses.isNotEmpty && pauses.last.end == null)
      ? ClockState.paused
      : ClockState.running;

  /// [now] clamped so time never runs backwards.
  DateTime _safe(DateTime now) => now.isBefore(lastTransitionAt) ? lastTransitionAt : now;

  /// True if [now] is earlier than the last recorded transition.
  bool clockWentBack(DateTime now) => now.isBefore(lastTransitionAt);

  Duration pausedAt(DateTime now) {
    final at = endedAt ?? _safe(now);
    return pauses.fold(Duration.zero, (sum, p) => sum + p.lengthAt(at));
  }

  /// Active (non-paused) reading time, capped at [planned].
  Duration elapsed(DateTime now) {
    final at = endedAt ?? _safe(now);
    final raw = at.difference(startedAt) - pausedAt(at);
    if (raw.isNegative) return Duration.zero;
    return raw > planned ? planned : raw;
  }

  Duration remaining(DateTime now) => planned - elapsed(now);

  /// When the timer reaches zero if it keeps running (moves with pauses).
  DateTime plannedEndAt(DateTime now) => startedAt.add(planned + pausedAt(now));

  /// Running and out of time: the session completes at [plannedEndAt].
  bool isOverdue(DateTime now) => state == ClockState.running && elapsed(now) >= planned;

  SessionClock _transition(DateTime now, {List<PauseInterval>? pauses, DateTime? endedAt}) {
    final back = clockWentBack(now);
    final at = _safe(now);
    return SessionClock(
      startedAt: startedAt,
      planned: planned,
      pauses: pauses ?? this.pauses,
      endedAt: endedAt,
      lastTransitionAt: at,
      clockAdjusted: clockAdjusted || back,
    );
  }

  SessionClock pause(DateTime now) {
    if (state != ClockState.running) return this;
    final at = _safe(now);
    return _transition(now, pauses: [...pauses, PauseInterval(at)]);
  }

  SessionClock resume(DateTime now) {
    if (state != ClockState.paused) return this;
    final at = _safe(now);
    final closed = [...pauses]..[pauses.length - 1] = PauseInterval(pauses.last.start, at);
    return _transition(now, pauses: closed);
  }

  /// Ends the session at [now], or at the planned end if that is earlier
  /// (a timer that ran out while the app was dead ends when it ran out).
  SessionClock end(DateTime now) {
    if (state == ClockState.ended) return this;
    var at = _safe(now);
    final closedPauses = [for (final p in pauses) p.end == null ? PauseInterval(p.start, at) : p];
    final paused = closedPauses.fold(Duration.zero, (s, p) => s + p.lengthAt(at));
    final plannedEnd = startedAt.add(planned + paused);
    if (state == ClockState.running && at.isAfter(plannedEnd)) at = plannedEnd;
    return SessionClock(
      startedAt: startedAt,
      planned: planned,
      pauses: closedPauses,
      endedAt: at,
      lastTransitionAt: _safe(now),
      clockAdjusted: clockAdjusted || clockWentBack(now),
    );
  }

  Map<String, Object?> toJson() => {
    'startedAt': startedAt.toUtc().toIso8601String(),
    'plannedSec': planned.inSeconds,
    'pauses': [for (final p in pauses) p.toJson()],
    if (endedAt != null) 'endedAt': endedAt!.toUtc().toIso8601String(),
    'lastTransitionAt': lastTransitionAt.toUtc().toIso8601String(),
    'clockAdjusted': clockAdjusted,
  };

  static SessionClock fromJson(Map<String, Object?> j) => SessionClock(
    startedAt: DateTime.parse(j['startedAt']! as String),
    planned: Duration(seconds: (j['plannedSec']! as num).toInt()),
    pauses: [
      for (final p in (j['pauses'] as List? ?? const []))
        PauseInterval.fromJson((p as Map).cast<String, Object?>()),
    ],
    endedAt: j['endedAt'] == null ? null : DateTime.parse(j['endedAt']! as String),
    lastTransitionAt: DateTime.parse(j['lastTransitionAt']! as String),
    clockAdjusted: j['clockAdjusted'] == true,
  );

  @override
  bool operator ==(Object other) =>
      other is SessionClock &&
      other.startedAt == startedAt &&
      other.planned == planned &&
      other.endedAt == endedAt &&
      other.lastTransitionAt == lastTransitionAt &&
      other.clockAdjusted == clockAdjusted &&
      _listEq(other.pauses, pauses);

  @override
  int get hashCode => Object.hash(
    startedAt,
    planned,
    endedAt,
    lastTransitionAt,
    clockAdjusted,
    Object.hashAll(pauses),
  );
}

bool _listEq<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
