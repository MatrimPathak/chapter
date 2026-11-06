import 'package:chapter/core/sync/hlc.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final t0 = DateTime.utc(2026, 11, 4, 12);

  group('Hlc.send', () {
    test('adopts physical time when it moves forward', () {
      final hlc = const Hlc.zero('a').send(t0);
      expect(hlc.wallMs, t0.millisecondsSinceEpoch);
      expect(hlc.counter, 0);
    });

    test('increments counter when physical time does not advance', () {
      final first = const Hlc.zero('a').send(t0);
      final second = first.send(t0);
      final third = second.send(t0.subtract(const Duration(seconds: 5)));
      expect(second > first, isTrue);
      expect(third > second, isTrue);
      expect(third.wallMs, first.wallMs);
      expect(third.counter, 2);
    });
  });

  group('Hlc.receive', () {
    test('result is greater than both local and remote', () {
      final local = const Hlc.zero('a').send(t0);
      final remote = Hlc(t0.millisecondsSinceEpoch + 500, 3, 'b');
      final merged = local.receive(remote, t0);
      expect(merged > local, isTrue);
      expect(merged > remote, isTrue);
      expect(merged.nodeId, 'a');
    });

    test('adopts a remote clock however far ahead, and later events follow it', () {
      final remote = Hlc(t0.add(const Duration(days: 400)).millisecondsSinceEpoch, 7, 'b');
      final merged = const Hlc.zero('a').receive(remote, t0);
      expect(merged > remote, isTrue);
      expect(merged.send(t0) > remote, isTrue, reason: 'an edit here still wins');
    });

    test('running out of counter moves on a millisecond instead of failing', () {
      const full = Hlc(1000, Hlc.maxCounter, 'a');
      final next = full.send(DateTime.fromMillisecondsSinceEpoch(5));
      expect(next > full, isTrue);
      expect(next.wallMs, 1001);
      final merged = full.receive(
        const Hlc(1000, Hlc.maxCounter, 'b'),
        DateTime.fromMillisecondsSinceEpoch(5),
      );
      expect(merged > full, isTrue);
    });
  });

  group('pack/parse', () {
    test('round-trips', () {
      final hlc = Hlc(t0.millisecondsSinceEpoch, 42, 'node-1');
      expect(Hlc.parse(hlc.pack()), hlc);
    });

    test('string order matches clock order', () {
      final clocks = [
        const Hlc(5, 0, 'b'),
        const Hlc(1000000, 2, 'a'),
        const Hlc(1000000, 10, 'a'),
        const Hlc(1000000, 10, 'b'),
        const Hlc(99999999999, 0, 'a'),
      ];
      final byString = [...clocks]..sort((x, y) => x.pack().compareTo(y.pack()));
      final byClock = [...clocks]..sort();
      expect(byString, byClock);
    });

    test('rejects malformed input', () {
      expect(() => Hlc.parse('nope'), throwsFormatException);
    });
  });
}
