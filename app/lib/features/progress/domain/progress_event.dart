import 'package:meta/meta.dart';

import 'reading_position.dart';

enum ProgressSource { manual, session, import }

/// One immutable entry in the progress log (D4).
@immutable
class ProgressEvent {
  const ProgressEvent({
    required this.id,
    required this.workId,
    required this.readThroughId,
    required this.position,
    required this.fraction,
    required this.isApproximate,
    required this.source,
    required this.recordedAt,
    this.editionId,
    this.sessionId,
  });

  final String id;
  final String workId;
  final String readThroughId;
  final String? editionId;
  final ReadingPosition position;
  final double fraction;
  final bool isApproximate;
  final ProgressSource source;
  final String? sessionId;
  final DateTime recordedAt;

  /// Total order used to pick the "current" event: newest recording time,
  /// ties broken by id (UUIDv7 is time-ordered), so every device agrees.
  static int compare(ProgressEvent a, ProgressEvent b) {
    final byTime = a.recordedAt.compareTo(b.recordedAt);
    return byTime != 0 ? byTime : a.id.compareTo(b.id);
  }

  /// The current progress of a log: the newest event, or `null`.
  static ProgressEvent? latest(Iterable<ProgressEvent> events) {
    ProgressEvent? best;
    for (final e in events) {
      if (best == null || compare(e, best) > 0) best = e;
    }
    return best;
  }
}
