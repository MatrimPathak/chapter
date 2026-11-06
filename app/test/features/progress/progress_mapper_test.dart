import 'package:chapter/features/progress/domain/progress_mapper.dart';
import 'package:chapter/features/progress/domain/reading_position.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const kindle = EditionMetrics(format: 'kindle', pageCount: 400);
  const paperback = EditionMetrics(format: 'paperback', pageCount: 374);
  const audio = EditionMetrics(format: 'audiobook', audioDurationSec: 40800);

  group('toFraction', () {
    test('page in a known-length edition is proportional', () {
      final f = ProgressMapper.toFraction(const ReadingPosition.page(page: 187), kindle)!;
      expect(f.fraction, closeTo(0.4675, 1e-9));
      expect(f.isApproximate, isFalse);
    });

    test('front and back matter are excluded', () {
      const ed = EditionMetrics(
        format: 'paperback',
        pageCount: 420,
        contentStartPage: 10,
        contentEndPage: 410,
      );
      expect(ProgressMapper.toFraction(const ReadingPosition.page(page: 5), ed)!.fraction, 0);
      expect(ProgressMapper.toFraction(const ReadingPosition.page(page: 210), ed)!.fraction, 0.5);
      expect(ProgressMapper.toFraction(const ReadingPosition.page(page: 415), ed)!.fraction, 1);
    });

    test('audio seconds over duration', () {
      final f = ProgressMapper.toFraction(const ReadingPosition.audio(seconds: 20400), audio)!;
      expect(f.fraction, 0.5);
    });

    test('percent and finished work without a length', () {
      const unknown = EditionMetrics.unknown();
      expect(
        ProgressMapper.toFraction(const ReadingPosition.percent(percent: 42), unknown)!.fraction,
        closeTo(0.42, 1e-9),
      );
      expect(ProgressMapper.toFraction(const ReadingPosition.finished(), unknown)!.fraction, 1);
    });

    test('page in an unknown-length book cannot be converted', () {
      expect(
        ProgressMapper.toFraction(
          const ReadingPosition.page(page: 50),
          const EditionMetrics.unknown(),
        ),
        isNull,
      );
    });

    test('a page position is meaningless for an audiobook', () {
      expect(ProgressMapper.toFraction(const ReadingPosition.page(page: 50), audio), isNull);
    });

    test('values are clamped to 0–1', () {
      expect(ProgressMapper.toFraction(const ReadingPosition.page(page: 999), kindle)!.fraction, 1);
      expect(
        ProgressMapper.toFraction(const ReadingPosition.percent(percent: -3), kindle)!.fraction,
        0,
      );
    });

    test('kindle location needs a total', () {
      expect(
        ProgressMapper.toFraction(const ReadingPosition.location(location: 10), kindle),
        isNull,
      );
      expect(
        ProgressMapper.toFraction(
          const ReadingPosition.location(location: 2500, totalLocations: 5000),
          kindle,
        )!.fraction,
        0.5,
      );
    });
  });

  group('fromFraction', () {
    test('brief example: Kindle p.187/400 → audiobook ≈ 19,074 s, approximate', () {
      final f = ProgressMapper.toFraction(const ReadingPosition.page(page: 187), kindle)!;
      final p = ProgressMapper.fromFraction(f.fraction, audio, source: kindle);
      expect(p.position, const ReadingPosition.audio(seconds: 19074));
      expect(p.isApproximate, isTrue);
    });

    test('print → print with a different page count is approximate', () {
      final p = ProgressMapper.fromFraction(0.5, paperback, source: kindle);
      expect(p.position, const ReadingPosition.page(page: 187));
      expect(p.isApproximate, isTrue);
    });

    test('same edition round-trips exactly', () {
      final p = ProgressMapper.fromFraction(0.4675, kindle, source: kindle);
      expect(p.position, const ReadingPosition.page(page: 187));
      expect(p.isApproximate, isFalse);
    });

    test('unknown target length falls back to percent', () {
      final p = ProgressMapper.fromFraction(0.25, const EditionMetrics.unknown(), source: kindle);
      expect(p.position, const ReadingPosition.percent(percent: 25));
    });

    test('100 % is finished in any edition', () {
      final p = ProgressMapper.fromFraction(1, audio, source: kindle);
      expect(p.position, const ReadingPosition.finished());
      expect(p.isApproximate, isFalse);
    });

    test('calibration anchors interpolate piecewise and are exact near an anchor', () {
      const calibrated = EditionMetrics(
        format: 'audiobook',
        audioDurationSec: 40800,
        calibration: [CalibrationPoint(page: 100, audioSeconds: 11520)],
      );
      final near = ProgressMapper.fromFraction(
        0.25,
        calibrated,
        source: kindle,
        sourcePosition: const ReadingPosition.page(page: 100),
      );
      expect(near.position, const ReadingPosition.audio(seconds: 11520));
      expect(near.isApproximate, isFalse);

      // Halfway between the anchor (100 → 11520) and the end (400 → 40800).
      final far = ProgressMapper.fromFraction(
        0.625,
        calibrated,
        source: kindle,
        sourcePosition: const ReadingPosition.page(page: 250),
      );
      expect(far.position, const ReadingPosition.audio(seconds: 26160));
      expect(far.isApproximate, isTrue);
    });
  });

  test('mediumOf groups formats', () {
    expect(mediumOf('paperback'), MediumKind.print);
    expect(mediumOf('kindle'), MediumKind.digital);
    expect(mediumOf('audiobook'), MediumKind.audio);
    expect(mediumOf('other'), MediumKind.unknown);
  });
}
