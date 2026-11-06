import 'package:chapter/features/reading/domain/session_clock.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final t0 = DateTime.utc(2026, 11, 4, 20);
  DateTime at(Duration d) => t0.add(d);

  test('elapsed comes from timestamps and is exact over two hours', () {
    final c = SessionClock.start(t0, const Duration(hours: 3));
    expect(c.elapsed(at(const Duration(hours: 2))), const Duration(hours: 2));
    expect(c.remaining(at(const Duration(hours: 2))), const Duration(hours: 1));
  });

  test('pauses are excluded and move the planned end', () {
    var c = SessionClock.start(t0, const Duration(minutes: 30));
    c = c.pause(at(const Duration(minutes: 10)));
    expect(c.state, ClockState.paused);
    // Time spent paused doesn't count.
    expect(c.elapsed(at(const Duration(minutes: 25))), const Duration(minutes: 10));
    c = c.resume(at(const Duration(minutes: 25)));
    expect(c.state, ClockState.running);
    expect(c.elapsed(at(const Duration(minutes: 30))), const Duration(minutes: 15));
    expect(c.plannedEndAt(at(const Duration(minutes: 30))), at(const Duration(minutes: 45)));
  });

  test('2 h with several pauses stays exact to the second', () {
    var c = SessionClock.start(t0, const Duration(hours: 2));
    var now = t0;
    var expected = Duration.zero;
    for (var i = 0; i < 12; i++) {
      now = now.add(const Duration(minutes: 9, seconds: 59));
      expected += const Duration(minutes: 9, seconds: 59);
      c = c.pause(now);
      now = now.add(const Duration(minutes: 3, seconds: 7));
      c = c.resume(now);
    }
    expect(c.elapsed(now), expected);
  });

  test('elapsed is capped at the planned duration and the timer is overdue', () {
    final c = SessionClock.start(t0, const Duration(minutes: 20));
    expect(c.elapsed(at(const Duration(hours: 5))), const Duration(minutes: 20));
    expect(c.isOverdue(at(const Duration(minutes: 20))), isTrue);
    expect(c.isOverdue(at(const Duration(minutes: 19))), isFalse);
  });

  test('ending after the planned end ends at the planned end', () {
    var c = SessionClock.start(t0, const Duration(minutes: 20));
    c = c.pause(at(const Duration(minutes: 5))).resume(at(const Duration(minutes: 8)));
    c = c.end(at(const Duration(hours: 9)));
    expect(c.endedAt, at(const Duration(minutes: 23)));
    expect(c.elapsed(at(const Duration(hours: 10))), const Duration(minutes: 20));
  });

  test('ending while paused closes the pause', () {
    var c = SessionClock.start(t0, const Duration(minutes: 20));
    c = c.pause(at(const Duration(minutes: 5))).end(at(const Duration(minutes: 9)));
    expect(c.state, ClockState.ended);
    expect(c.pauses.single.end, at(const Duration(minutes: 9)));
    expect(c.elapsed(at(const Duration(minutes: 30))), const Duration(minutes: 5));
  });

  test('clock moved backwards is clamped and flagged', () {
    var c = SessionClock.start(t0, const Duration(minutes: 30));
    c = c.pause(at(const Duration(minutes: 10)));
    // Device clock jumps back 1 h.
    final back = at(const Duration(minutes: -50));
    expect(c.clockWentBack(back), isTrue);
    expect(c.elapsed(back), const Duration(minutes: 10));
    c = c.resume(back);
    expect(c.clockAdjusted, isTrue);
    expect(c.elapsed(at(const Duration(minutes: 12))), const Duration(minutes: 12));
  });

  test('round-trips through JSON', () {
    var c = SessionClock.start(t0, const Duration(minutes: 45));
    c = c.pause(at(const Duration(minutes: 3)));
    expect(SessionClock.fromJson(c.toJson()), c);
    c = c.resume(at(const Duration(minutes: 4))).end(at(const Duration(minutes: 20)));
    expect(SessionClock.fromJson(c.toJson()), c);
  });

  test('transitions in the wrong state are no-ops', () {
    final c = SessionClock.start(t0, const Duration(minutes: 30));
    expect(c.resume(at(const Duration(minutes: 1))), c);
    final ended = c.end(at(const Duration(minutes: 2)));
    expect(ended.pause(at(const Duration(minutes: 3))), ended);
    expect(ended.end(at(const Duration(minutes: 4))), ended);
  });
}
