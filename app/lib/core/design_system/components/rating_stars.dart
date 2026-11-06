import 'package:flutter/material.dart';

import '../theme/chapter_theme.dart';

/// Half-star rating (0.5–5.0, approved TD-10). Read-only when [onChanged] is
/// null. Interactive mode: tap the left half of a star for x.5, the right
/// half for a whole star; tapping the current value clears it.
class RatingStars extends StatelessWidget {
  const RatingStars({required this.rating, super.key, this.onChanged, this.size = 24});

  /// `null` means unrated.
  final double? rating;
  final ValueChanged<double?>? onChanged;
  final double size;

  static double? normalize(double? value) {
    if (value == null) return null;
    final halfSteps = (value * 2).round().clamp(1, 10);
    return halfSteps / 2;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.chapterColors;
    final value = normalize(rating) ?? 0;
    final stars = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 1; i <= 5; i++)
          _Star(
            fill: value >= i ? 1 : (value >= i - 0.5 ? 0.5 : 0),
            size: size,
            color: colors.accent,
            empty: colors.line,
            onTapHalf: onChanged == null ? null : () => _set(i - 0.5),
            onTapWhole: onChanged == null ? null : () => _set(i.toDouble()),
          ),
      ],
    );
    final label = rating == null
        ? 'Not rated'
        : '${value.toStringAsFixed(value % 1 == 0 ? 0 : 1)} of 5 stars';

    if (onChanged == null) {
      return Semantics(
        label: label,
        child: ExcludeSemantics(child: stars),
      );
    }
    return Semantics(
      label: 'Rating',
      value: label,
      increasedValue: '${(value + 0.5).clamp(0.5, 5)} of 5 stars',
      decreasedValue: value <= 0.5 ? 'Not rated' : '${value - 0.5} of 5 stars',
      onIncrease: () => onChanged!((value + 0.5).clamp(0.5, 5)),
      onDecrease: () => onChanged!(value <= 0.5 ? null : value - 0.5),
      child: ExcludeSemantics(child: stars),
    );
  }

  void _set(double next) => onChanged!(rating == next ? null : next);
}

class _Star extends StatelessWidget {
  const _Star({
    required this.fill,
    required this.size,
    required this.color,
    required this.empty,
    this.onTapHalf,
    this.onTapWhole,
  });

  final double fill;
  final double size;
  final Color color;
  final Color empty;
  final VoidCallback? onTapHalf;
  final VoidCallback? onTapWhole;

  @override
  Widget build(BuildContext context) {
    final icon = switch (fill) {
      >= 1 => Icon(Icons.star_rounded, size: size, color: color),
      >= 0.5 => Icon(Icons.star_half_rounded, size: size, color: color),
      _ => Icon(Icons.star_outline_rounded, size: size, color: empty),
    };
    if (onTapHalf == null) return icon;
    // Interactive stars get a 48dp-tall hit area split into two halves.
    final width = size < 24 ? 24.0 : size;
    return SizedBox(
      width: width + 4,
      height: 48,
      child: Stack(
        alignment: Alignment.center,
        children: [
          icon,
          Row(
            children: [
              Expanded(
                child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: onTapHalf),
              ),
              Expanded(
                child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: onTapWhole),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
