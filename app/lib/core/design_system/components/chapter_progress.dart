import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/chapter_theme.dart';
import '../tokens/chapter_tokens.dart';

/// Thin linear reading-progress bar. [fraction] is clamped to 0–1.
class ChapterProgressBar extends StatelessWidget {
  const ChapterProgressBar({
    required this.fraction,
    super.key,
    this.height = 6,
    this.semanticLabel,
    this.color,
  });

  final double fraction;
  final double height;
  final String? semanticLabel;

  /// Defaults to the accent.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final colors = context.chapterColors;
    final value = fraction.clamp(0.0, 1.0);
    return Semantics(
      label: semanticLabel,
      value: '${(value * 100).round()}%',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(ChapterRadius.pill),
        child: SizedBox(
          height: height,
          child: Stack(
            fit: StackFit.expand,
            children: [
              ColoredBox(color: colors.surfaceMuted),
              FractionallySizedBox(
                alignment: AlignmentDirectional.centerStart,
                widthFactor: value,
                child: ColoredBox(color: color ?? colors.accent),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Circular progress with an optional centred label (goals, timer).
class ChapterProgressRing extends StatelessWidget {
  const ChapterProgressRing({
    required this.fraction,
    super.key,
    this.size = 64,
    this.strokeWidth = 5,
    this.center,
    this.semanticLabel,
    this.color,
  });

  final double fraction;
  final double size;
  final double strokeWidth;
  final Widget? center;
  final String? semanticLabel;

  /// Defaults to the accent. The session timer uses the highlight.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final colors = context.chapterColors;
    final value = fraction.clamp(0.0, 1.0);
    return Semantics(
      label: semanticLabel,
      value: '${(value * 100).round()}%',
      child: SizedBox.square(
        dimension: size,
        child: CustomPaint(
          painter: _RingPainter(
            fraction: value,
            track: colors.surfaceMuted,
            fill: color ?? colors.accent,
            strokeWidth: strokeWidth,
          ),
          child: center == null ? null : Center(child: ExcludeSemantics(child: center)),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.fraction,
    required this.track,
    required this.fill,
    required this.strokeWidth,
  });

  final double fraction;
  final Color track;
  final Color fill;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final arcRect = rect.deflate(strokeWidth / 2);
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(arcRect, 0, math.pi * 2, false, base..color = track);
    if (fraction > 0) {
      canvas.drawArc(arcRect, -math.pi / 2, math.pi * 2 * fraction, false, base..color = fill);
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.fraction != fraction || old.track != track || old.fill != fill;
}
