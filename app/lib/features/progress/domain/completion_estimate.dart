import 'package:meta/meta.dart';

import 'progress_event.dart';

@immutable
class CompletionEstimate {
  const CompletionEstimate({required this.finishOn, required this.fractionPerDay});

  /// Approximate day the book will be finished at the current pace.
  final DateTime finishOn;
  final double fractionPerDay;
}

/// Estimates when the current read-through will be finished.
///
/// Honest by construction (brief §12): returns `null` unless there are at
/// least [minReadingDays] distinct days with forward progress in the last
/// [window], and the pace is positive. Rereads are excluded by passing only
/// the active read-through's events.
abstract final class CompletionEstimator {
  static const minReadingDays = 3;
  static const window = Duration(days: 30);

  static CompletionEstimate? estimate(List<ProgressEvent> events, DateTime now) {
    if (events.isEmpty) return null;
    final sorted = [...events]..sort(ProgressEvent.compare);
    final current = sorted.last.fraction;
    if (current >= 1) return null;

    final since = now.subtract(window);
    final recent = sorted.where((e) => e.recordedAt.isAfter(since)).toList();
    if (recent.length < 2) return null;

    // Days on which progress moved forward compared with the previous event.
    final readingDays = <DateTime>{};
    for (var i = 1; i < recent.length; i++) {
      if (recent[i].fraction > recent[i - 1].fraction) {
        final d = recent[i].recordedAt.toLocal();
        readingDays.add(DateTime(d.year, d.month, d.day));
      }
    }
    if (readingDays.length < minReadingDays) return null;

    final gained = recent.last.fraction - recent.first.fraction;
    final days = recent.last.recordedAt.difference(recent.first.recordedAt).inHours / 24;
    if (gained <= 0 || days <= 0) return null;
    final perDay = gained / days;
    final remainingDays = (1 - current) / perDay;
    if (!remainingDays.isFinite || remainingDays > 3650) return null;
    final finish = now.add(Duration(hours: (remainingDays * 24).ceil()));
    return CompletionEstimate(
      finishOn: DateTime(finish.year, finish.month, finish.day),
      fractionPerDay: perDay,
    );
  }
}
