import 'package:flutter/animation.dart';
import 'package:flutter/painting.dart';

/// Spacing scale (logical pixels). Use these instead of literals.
abstract final class ChapterSpacing {
  static const double xxs = 2;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
  static const double xxxl = 48;

  /// Between screen sections, and above screen titles.
  static const double section = 36;

  /// Horizontal page gutter.
  static const double gutter = 20;
}

/// Corner radii. Deliberately restrained: covers are nearly square-cornered
/// like real books; surfaces are softly rounded, never pill-shaped cards.
abstract final class ChapterRadius {
  static const double cover = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double pill = 999;
}

/// Elevation is expressed mostly with colour, not shadows.
abstract final class ChapterElevation {
  static const double none = 0;
  static const double cover = 2;
  static const double sheet = 1;
}

/// Warm, nearly invisible shadows for light mode. Dark mode separates surfaces by
/// tone instead, so it has none.
abstract final class ChapterShadows {
  static const List<BoxShadow> card = [
    BoxShadow(color: Color(0x0A252525), blurRadius: 8, offset: Offset(0, 2)),
  ];
  static const List<BoxShadow> floating = [
    BoxShadow(color: Color(0x14252525), blurRadius: 24, offset: Offset(0, 8)),
  ];
  static const List<BoxShadow> cover = [
    BoxShadow(color: Color(0x33000000), blurRadius: 6, offset: Offset(0, 3)),
  ];
}

/// Motion: short and functional, no decorative animation.
abstract final class ChapterMotion {
  static const Duration fast = Duration(milliseconds: 150);
  static const Duration normal = Duration(milliseconds: 250);
  static const Curve standard = Curves.easeOutCubic;
}

/// Minimum interactive size (accessibility).
abstract final class ChapterSizes {
  static const double minTouchTarget = 48;
  static const double coverAspectRatio = 2 / 3;
}
