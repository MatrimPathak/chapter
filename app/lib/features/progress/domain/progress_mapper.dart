import 'package:meta/meta.dart';

import 'reading_position.dart';

/// Broad kind of an edition for conversion purposes: page-based formats map
/// to each other proportionally; audio is a different medium.
enum MediumKind { print, digital, audio, unknown }

MediumKind mediumOf(String format) => switch (format) {
  'paperback' || 'hardcover' || 'massMarket' => MediumKind.print,
  'ebook' || 'kindle' || 'epub' => MediumKind.digital,
  'audiobook' || 'audible' => MediumKind.audio,
  _ => MediumKind.unknown,
};

/// A user-paired anchor between a page and an audio timestamp
/// ("page 100 ≈ 3:12:00").
@immutable
class CalibrationPoint {
  const CalibrationPoint({required this.page, required this.audioSeconds});

  final int page;
  final int audioSeconds;

  Map<String, Object?> toJson() => {'page': page, 'audioSeconds': audioSeconds};

  static CalibrationPoint? fromJson(Object? json) {
    if (json is! Map) return null;
    final page = json['page'];
    final seconds = json['audioSeconds'];
    if (page is! num || seconds is! num) return null;
    return CalibrationPoint(page: page.toInt(), audioSeconds: seconds.toInt());
  }
}

/// What the mapper needs to know about one edition. Values already include
/// the user's overrides (docs/02 D6).
@immutable
class EditionMetrics {
  const EditionMetrics({
    required this.format,
    this.pageCount,
    this.audioDurationSec,
    this.contentStartPage,
    this.contentEndPage,
    this.calibration = const [],
  });

  /// Unknown edition with no known length.
  const EditionMetrics.unknown()
    : format = 'other',
      pageCount = null,
      audioDurationSec = null,
      contentStartPage = null,
      contentEndPage = null,
      calibration = const [];

  final String format;
  final int? pageCount;
  final int? audioDurationSec;

  /// Pages before this (front matter) count as 0 %.
  final int? contentStartPage;

  /// Pages after this (back matter) count as 100 %.
  final int? contentEndPage;
  final List<CalibrationPoint> calibration;

  MediumKind get medium => mediumOf(format);
  bool get isAudio => medium == MediumKind.audio;

  /// True when a page/time position can be converted to a fraction.
  bool get hasLength => isAudio ? (audioDurationSec ?? 0) > 0 : (pageCount ?? 0) > 0;

  int get _start => (contentStartPage ?? 0).clamp(0, pageCount ?? 0);
  int get _end => (contentEndPage ?? pageCount ?? 0).clamp(_start, pageCount ?? 0);
}

@immutable
class MappedFraction {
  const MappedFraction(this.fraction, {required this.isApproximate});

  /// 0.0–1.0, the canonical work-level progress.
  final double fraction;
  final bool isApproximate;

  @override
  bool operator ==(Object other) =>
      other is MappedFraction && other.fraction == fraction && other.isApproximate == isApproximate;

  @override
  int get hashCode => Object.hash(fraction, isApproximate);

  @override
  String toString() => 'MappedFraction($fraction, approximate: $isApproximate)';
}

@immutable
class MappedPosition {
  const MappedPosition(this.position, {required this.isApproximate});

  final ReadingPosition position;
  final bool isApproximate;
}

/// Converts between edition positions and the work-level fraction
/// (docs/03 §7). Pure and deterministic; fully unit-tested.
///
/// Resolution order:
/// 1. Calibrated: user-paired page↔audio anchors, piecewise-linear.
/// 2. Proportional (default): page/total or seconds/duration.
/// 3. Unknown length: only percent or "finished" can be expressed.
///
/// Every conversion **across media** (print/ebook ↔ audio) is marked
/// approximate unless a calibration anchor is close by.
abstract final class ProgressMapper {
  /// Position in [edition] → fraction of the work. Returns `null` when the
  /// position can't be converted (e.g. a page in a book of unknown length).
  static MappedFraction? toFraction(ReadingPosition position, EditionMetrics edition) {
    switch (position) {
      case FinishedPosition():
        return const MappedFraction(1, isApproximate: false);
      case PercentPosition(:final percent):
        return MappedFraction((percent / 100).clamp(0.0, 1.0), isApproximate: false);
      case KindleLocation(:final location, :final totalLocations):
        final total = totalLocations;
        if (total == null || total <= 0) return null;
        return MappedFraction((location / total).clamp(0.0, 1.0), isApproximate: false);
      case PagePosition(:final page):
        if (edition.isAudio || !edition.hasLength) return null;
        final start = edition._start;
        final end = edition._end;
        if (end <= start) return null;
        return MappedFraction(
          ((page - start) / (end - start)).clamp(0.0, 1.0),
          isApproximate: false,
        );
      case AudioPosition(:final seconds):
        final duration = edition.audioDurationSec;
        if (!edition.isAudio || duration == null || duration <= 0) return null;
        return MappedFraction((seconds / duration).clamp(0.0, 1.0), isApproximate: false);
    }
  }

  /// Fraction of the work → position in [target]. [source] is the edition
  /// the fraction was recorded in; crossing media marks the result
  /// approximate (and so does an unknown source).
  static MappedPosition fromFraction(
    double fraction,
    EditionMetrics target, {
    EditionMetrics? source,
    ReadingPosition? sourcePosition,
  }) {
    final f = fraction.clamp(0.0, 1.0);
    final crossMedium = source == null || _crossesMedium(source, target);

    if (f >= 1) return const MappedPosition(ReadingPosition.finished(), isApproximate: false);

    // Calibrated page → audio when the user paired anchors on the audio edition.
    if (target.isAudio && sourcePosition is PagePosition && target.calibration.isNotEmpty) {
      final calibrated = _calibratedSeconds(sourcePosition.page, target, source);
      if (calibrated != null) return calibrated;
    }

    if (target.isAudio && (target.audioDurationSec ?? 0) > 0) {
      return MappedPosition(
        ReadingPosition.audio(seconds: (f * target.audioDurationSec!).round()),
        isApproximate: crossMedium,
      );
    }
    if (!target.isAudio && target.hasLength) {
      final start = target._start;
      final end = target._end;
      return MappedPosition(
        ReadingPosition.page(page: (start + f * (end - start)).round()),
        isApproximate: crossMedium || !_samePageCount(source, target),
      );
    }
    // Unknown length: percent is the only honest representation.
    return MappedPosition(ReadingPosition.percent(percent: f * 100), isApproximate: crossMedium);
  }

  static bool _crossesMedium(EditionMetrics a, EditionMetrics b) =>
      a.isAudio != b.isAudio || a.medium == MediumKind.unknown && b.medium == MediumKind.unknown;

  static bool _samePageCount(EditionMetrics? a, EditionMetrics b) =>
      a != null && a.pageCount != null && a.pageCount == b.pageCount;

  /// Piecewise-linear interpolation through (0, 0), the user's anchors and
  /// (pageCount, duration). Exact (not approximate) within ±2 % of an anchor.
  static MappedPosition? _calibratedSeconds(int page, EditionMetrics audio, EditionMetrics? print) {
    final duration = audio.audioDurationSec;
    final pages = print?.pageCount;
    if (duration == null || duration <= 0) return null;
    final points = <CalibrationPoint>[
      const CalibrationPoint(page: 0, audioSeconds: 0),
      ...audio.calibration.where((p) => p.page > 0 && p.audioSeconds > 0),
      if (pages != null && pages > 0) CalibrationPoint(page: pages, audioSeconds: duration),
    ]..sort((a, b) => a.page.compareTo(b.page));
    if (points.length < 3) return null; // no user anchor
    for (var i = 0; i < points.length - 1; i++) {
      final a = points[i];
      final b = points[i + 1];
      if (page >= a.page && page <= b.page && b.page > a.page) {
        final t = (page - a.page) / (b.page - a.page);
        final seconds = (a.audioSeconds + t * (b.audioSeconds - a.audioSeconds)).round();
        final nearest = points
            .where((p) => p.page > 0 && p.page != pages)
            .map((p) => (p.page - page).abs())
            .fold<int>(1 << 30, (m, d) => d < m ? d : m);
        final tolerance = ((pages ?? 100) * 0.02).ceil();
        return MappedPosition(
          ReadingPosition.audio(seconds: seconds),
          isApproximate: nearest > tolerance,
        );
      }
    }
    return null;
  }
}
