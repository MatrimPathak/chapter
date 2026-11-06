import 'package:meta/meta.dart';

/// A document whose fields are merged independently by last-writer-wins,
/// using a packed HLC string per field (see `Hlc.pack`, which sorts
/// lexicographically).
///
/// Used for `users/{uid}` (profile/preferences) and later for library entries,
/// so that changing the theme on one device and the analytics consent on
/// another keeps both changes.
@immutable
final class LwwDocument {
  const LwwDocument({required this.fields, required this.clocks});

  const LwwDocument.empty() : fields = const {}, clocks = const {};

  final Map<String, Object?> fields;
  final Map<String, String> clocks;

  /// Merges [other] into this document. For each field the value with the
  /// higher clock wins; ties keep this document's value (merge is
  /// idempotent and commutative for distinct clocks).
  LwwDocument merge(LwwDocument other) {
    final mergedFields = Map<String, Object?>.of(fields);
    final mergedClocks = Map<String, String>.of(clocks);
    other.clocks.forEach((field, theirClock) {
      final ours = mergedClocks[field];
      if (ours == null || theirClock.compareTo(ours) > 0) {
        mergedClocks[field] = theirClock;
        mergedFields[field] = other.fields[field];
      }
    });
    return LwwDocument(fields: mergedFields, clocks: mergedClocks);
  }

  /// Fields of [other] that would change this document when merged.
  Set<String> winningFieldsOf(LwwDocument other) => {
    for (final entry in other.clocks.entries)
      if (clocks[entry.key] == null || entry.value.compareTo(clocks[entry.key]!) > 0) entry.key,
  };

  @override
  bool operator ==(Object other) =>
      other is LwwDocument && _mapEquals(other.fields, fields) && _mapEquals(other.clocks, clocks);

  @override
  int get hashCode => Object.hash(
    Object.hashAllUnordered(fields.entries.map((e) => Object.hash(e.key, e.value))),
    Object.hashAllUnordered(clocks.entries.map((e) => Object.hash(e.key, e.value))),
  );

  @override
  String toString() => 'LwwDocument($fields, $clocks)';
}

bool _mapEquals<K, V>(Map<K, V> a, Map<K, V> b) {
  if (a.length != b.length) return false;
  for (final entry in a.entries) {
    if (!b.containsKey(entry.key) || b[entry.key] != entry.value) return false;
  }
  return true;
}
