import 'package:meta/meta.dart';

import '../../progress/domain/reading_position.dart';
import 'session_clock.dart';

/// How a session ended (docs/03 §6).
enum SessionCompletion {
  /// The timer ran to the planned duration.
  completed,

  /// The reader ended it before the planned duration.
  endedEarly,

  /// The app was not running when the timer ran out; ended at the planned
  /// end on the next launch.
  recovered;

  static SessionCompletion parse(Object? v) =>
      values.firstWhere((c) => c.name == v, orElse: () => SessionCompletion.completed);
}

/// The live (not yet saved) session: one singleton row in `active_session`,
/// rewritten on every transition so it survives the process being killed.
@immutable
class ActiveSession {
  const ActiveSession({
    required this.id,
    required this.workId,
    required this.clock,
    this.editionId,
    this.startPosition,
    this.startFraction,
    this.recovered = false,
    this.dndPreviousFilter,
  });

  final String id;
  final String workId;
  final String? editionId;
  final SessionClock clock;

  /// Progress when the session started (for pages read and the summary).
  final ReadingPosition? startPosition;
  final double? startFraction;

  /// Ended on relaunch because the timer ran out while the app was dead.
  final bool recovered;

  /// Set when Chapter turned Do Not Disturb on for this session: the
  /// interruption filter to restore afterwards. Persisted with the session so
  /// it is restored even after a crash.
  final int? dndPreviousFilter;

  bool get focusModeOn => dndPreviousFilter != null;

  bool get isEnded => clock.state == ClockState.ended;

  ActiveSession copyWith({
    SessionClock? clock,
    bool? recovered,
    int? Function()? dndPreviousFilter,
  }) => ActiveSession(
    id: id,
    workId: workId,
    editionId: editionId,
    clock: clock ?? this.clock,
    startPosition: startPosition,
    startFraction: startFraction,
    recovered: recovered ?? this.recovered,
    dndPreviousFilter: dndPreviousFilter == null ? this.dndPreviousFilter : dndPreviousFilter(),
  );

  SessionCompletion get completion {
    if (recovered) return SessionCompletion.recovered;
    final c = clock;
    final end = c.endedAt;
    if (end == null) return SessionCompletion.endedEarly;
    return c.elapsed(end) >= c.planned ? SessionCompletion.completed : SessionCompletion.endedEarly;
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'workId': workId,
    'editionId': editionId,
    'clock': clock.toJson(),
    'startPosition': startPosition?.toJson(),
    'startFraction': startFraction,
    'recovered': recovered,
    'dndPreviousFilter': dndPreviousFilter,
  };

  static ActiveSession fromJson(Map<String, Object?> j) => ActiveSession(
    id: j['id']! as String,
    workId: j['workId']! as String,
    editionId: j['editionId'] as String?,
    clock: SessionClock.fromJson((j['clock']! as Map).cast<String, Object?>()),
    startPosition: j['startPosition'] == null
        ? null
        : ReadingPosition.fromJson((j['startPosition']! as Map).cast<String, dynamic>()),
    startFraction: (j['startFraction'] as num?)?.toDouble(),
    recovered: j['recovered'] == true,
    dndPreviousFilter: (j['dndPreviousFilter'] as num?)?.toInt(),
  );
}

/// A saved session (append-only, D4).
@immutable
class ReadingSession {
  const ReadingSession({
    required this.id,
    required this.workId,
    required this.readThroughId,
    required this.startedAt,
    required this.endedAt,
    required this.plannedDurationSec,
    required this.activeDurationSec,
    required this.localDate,
    required this.tzOffsetMin,
    required this.completion,
    this.editionId,
    this.pauses = const [],
    this.startPosition,
    this.endPosition,
    this.startFraction,
    this.endFraction,
    this.pagesRead,
    this.clockAdjusted = false,
  });

  final String id;
  final String workId;
  final String readThroughId;
  final String? editionId;
  final DateTime startedAt;
  final DateTime endedAt;
  final int plannedDurationSec;
  final int activeDurationSec;
  final List<PauseInterval> pauses;
  final ReadingPosition? startPosition;
  final ReadingPosition? endPosition;
  final double? startFraction;
  final double? endFraction;
  final int? pagesRead;

  /// The reader's calendar day at the start, `YYYY-MM-DD`.
  final String localDate;
  final int tzOffsetMin;
  final SessionCompletion completion;
  final bool clockAdjusted;

  /// Pages per hour, when both pages and time are known.
  double? get pagesPerHour =>
      pagesRead == null || activeDurationSec < 60 ? null : pagesRead! * 3600 / activeDurationSec;

  static String localDateOf(DateTime t) {
    final l = t.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${l.year}-${two(l.month)}-${two(l.day)}';
  }
}
