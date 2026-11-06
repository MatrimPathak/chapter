import 'package:chapter/features/progress/domain/completion_estimate.dart';
import 'package:chapter/features/progress/domain/progress_event.dart';
import 'package:chapter/features/progress/domain/reading_position.dart';
import 'package:flutter_test/flutter_test.dart';

ProgressEvent ev(String id, DateTime at, double fraction) => ProgressEvent(
  id: id,
  workId: 'w',
  readThroughId: 'r',
  position: ReadingPosition.percent(percent: fraction * 100),
  fraction: fraction,
  isApproximate: false,
  source: ProgressSource.manual,
  recordedAt: at,
);

void main() {
  final now = DateTime(2026, 11, 10, 20);

  test('needs at least three reading days in the last 30', () {
    final twoDays = [
      ev('a', DateTime(2026, 11, 8, 20), 0.1),
      ev('b', DateTime(2026, 11, 9, 20), 0.2),
      ev('c', DateTime(2026, 11, 10, 20), 0.3),
    ];
    // Only two days moved forward (9th, 10th).
    expect(CompletionEstimator.estimate(twoDays, now), isNull);
  });

  test('estimates from the pace over the window', () {
    final events = [
      ev('a', DateTime(2026, 11, 6, 20), 0),
      ev('b', DateTime(2026, 11, 7, 20), 0.1),
      ev('c', DateTime(2026, 11, 8, 20), 0.2),
      ev('d', DateTime(2026, 11, 10, 20), 0.4),
    ];
    final e = CompletionEstimator.estimate(events, now)!;
    expect(e.fractionPerDay, closeTo(0.1, 1e-9));
    expect(e.finishOn, DateTime(2026, 11, 16));
  });

  test('ignores events older than 30 days', () {
    final events = [
      ev('a', DateTime(2026, 8, 31), 0.1),
      ev('b', DateTime(2026, 9, 2), 0.2),
      ev('c', DateTime(2026, 9, 3), 0.3),
      ev('d', DateTime(2026, 9, 4), 0.4),
    ];
    expect(CompletionEstimator.estimate(events, now), isNull);
  });

  test('no estimate for a finished book', () {
    final events = [
      ev('a', DateTime(2026, 11, 6), 0.2),
      ev('b', DateTime(2026, 11, 7), 0.5),
      ev('c', DateTime(2026, 11, 8), 0.8),
      ev('d', DateTime(2026, 11, 9, 12), 1),
    ];
    expect(CompletionEstimator.estimate(events, now), isNull);
  });

  test('latest() orders by time then id', () {
    final t = DateTime(2026, 11, 2);
    expect(ProgressEvent.latest([ev('b', t, 0.2), ev('a', t, 0.9)])!.id, 'b');
    expect(ProgressEvent.latest(const []), isNull);
  });
}
