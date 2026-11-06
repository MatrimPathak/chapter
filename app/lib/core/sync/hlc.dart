import 'package:meta/meta.dart';

/// Hybrid Logical Clock timestamp.
///
/// Gives a total order of events across devices even when wall clocks are
/// skewed: `(wallMs, counter, nodeId)` compared lexicographically.
/// Serialised as a fixed-width string so string comparison == HLC comparison,
/// which lets Firestore rules and server code compare clocks without parsing.
@immutable
final class Hlc implements Comparable<Hlc> {
  const Hlc(this.wallMs, this.counter, this.nodeId)
    : assert(wallMs >= 0),
      assert(counter >= 0 && counter <= maxCounter);

  /// The zero clock; lower than any real timestamp.
  const Hlc.zero(String nodeId) : this(0, 0, nodeId);

  /// Parses the output of [pack].
  factory Hlc.parse(String packed) {
    final parts = packed.split(':');
    if (parts.length != 3) {
      throw FormatException('Invalid HLC', packed);
    }
    return Hlc(int.parse(parts[0]), int.parse(parts[1]), parts[2]);
  }

  static const int maxCounter = 0xFFFF;

  final int wallMs;
  final int counter;
  final String nodeId;

  /// Timestamp for a local event happening at [now].
  Hlc send(DateTime now) {
    final physical = now.millisecondsSinceEpoch;
    if (physical > wallMs) return Hlc(physical, 0, nodeId);
    return _bump(wallMs, counter + 1);
  }

  /// Merges a [remote] timestamp observed at [now] into this local clock.
  ///
  /// A remote clock is always adopted, however far ahead: refusing would stop
  /// sync on every device because one phone has the wrong date, and a later
  /// edit here must still win over what it saw. Clocks then run ahead of real
  /// time, which only affects ordering, and ordering stays correct.
  Hlc receive(Hlc remote, DateTime now) {
    final physical = now.millisecondsSinceEpoch;
    final wall = [wallMs, remote.wallMs, physical].reduce((a, b) => a > b ? a : b);
    final int next;
    if (wall == wallMs && wall == remote.wallMs) {
      next = (counter > remote.counter ? counter : remote.counter) + 1;
    } else if (wall == wallMs) {
      next = counter + 1;
    } else if (wall == remote.wallMs) {
      next = remote.counter + 1;
    } else {
      next = 0;
    }
    return _bump(wall, next);
  }

  Hlc _bump(int wall, int nextCounter) {
    // Possible while running ahead of real time. Moving on a millisecond keeps
    // the order; failing here would block every write.
    if (nextCounter > maxCounter) return Hlc(wall + 1, 0, nodeId);
    return Hlc(wall, nextCounter, nodeId);
  }

  /// Fixed-width, lexicographically sortable representation.
  String pack() =>
      '${wallMs.toString().padLeft(15, '0')}:'
      '${counter.toString().padLeft(5, '0')}:$nodeId';

  @override
  int compareTo(Hlc other) {
    final byWall = wallMs.compareTo(other.wallMs);
    if (byWall != 0) return byWall;
    final byCounter = counter.compareTo(other.counter);
    if (byCounter != 0) return byCounter;
    return nodeId.compareTo(other.nodeId);
  }

  bool operator >(Hlc other) => compareTo(other) > 0;
  bool operator <(Hlc other) => compareTo(other) < 0;

  @override
  bool operator ==(Object other) =>
      other is Hlc && other.wallMs == wallMs && other.counter == counter && other.nodeId == nodeId;

  @override
  int get hashCode => Object.hash(wallMs, counter, nodeId);

  @override
  String toString() => pack();
}
