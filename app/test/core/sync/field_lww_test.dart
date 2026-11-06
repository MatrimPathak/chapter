import 'package:chapter/core/sync/field_lww.dart';
import 'package:flutter_test/flutter_test.dart';

LwwDocument doc(Map<String, (Object?, String)> entries) => LwwDocument(
  fields: entries.map((k, v) => MapEntry(k, v.$1)),
  clocks: entries.map((k, v) => MapEntry(k, v.$2)),
);

void main() {
  test('newer clock wins per field; other fields are preserved', () {
    final a = doc({'theme': ('dark', '2'), 'analytics': (false, '1')});
    final b = doc({'theme': ('light', '1'), 'analytics': (true, '3')});
    final merged = a.merge(b);
    expect(merged.fields, {'theme': 'dark', 'analytics': true});
    expect(merged.clocks, {'theme': '2', 'analytics': '3'});
  });

  test('merge is commutative and idempotent', () {
    final a = doc({'x': (1, '5'), 'y': (2, '1')});
    final b = doc({'x': (3, '4'), 'z': (9, '2')});
    expect(a.merge(b), b.merge(a));
    expect(a.merge(b).merge(b), a.merge(b));
  });

  test('winningFieldsOf reports only fields that would change', () {
    final server = doc({'theme': ('dark', '5')});
    final patch = doc({'theme': ('light', '4'), 'crash': (true, '6')});
    expect(server.winningFieldsOf(patch), {'crash'});
  });
}
