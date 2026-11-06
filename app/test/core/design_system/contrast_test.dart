import 'dart:math' as math;

import 'package:chapter/core/design_system/design_system.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

/// WCAG 2.x relative luminance contrast ratio.
double contrast(Color a, Color b) {
  double channel(double c) =>
      c <= 0.03928 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
  double luminance(Color c) =>
      0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b);
  final la = luminance(a);
  final lb = luminance(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

void main() {
  for (final (name, c) in [('light', ChapterColors.light), ('dark', ChapterColors.dark)]) {
    group('$name palette meets WCAG AA', () {
      final pairs = {
        'ink on paper': (c.ink, c.paper, 4.5),
        'ink on surface': (c.ink, c.surface, 4.5),
        'muted on paper': (c.inkMuted, c.paper, 4.5),
        'muted on surface': (c.inkMuted, c.surface, 4.5),
        'onAccent on accent': (c.onAccent, c.accent, 4.5),
        'accent on paper': (c.accent, c.paper, 4.5),
        'accent text on accentSoft': (c.accent, c.accentSoft, 3.0),
        'ink on accentSoft': (c.ink, c.accentSoft, 4.5),
        'error on paper': (c.error, c.paper, 4.5),
        'ink on cover placeholders': (c.ink, c.coverPlaceholders.first, 4.5),
      };
      pairs.forEach((label, pair) {
        test(label, () {
          final ratio = contrast(pair.$1, pair.$2);
          expect(
            ratio,
            greaterThanOrEqualTo(pair.$3),
            reason: '$label = ${ratio.toStringAsFixed(2)}',
          );
        });
      });
      test('ink on every cover placeholder', () {
        for (final bg in c.coverPlaceholders) {
          expect(contrast(c.ink, bg), greaterThanOrEqualTo(4.5));
        }
      });
    });
  }
}
