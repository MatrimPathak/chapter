import 'package:freezed_annotation/freezed_annotation.dart';

part 'reading_position.freezed.dart';
part 'reading_position.g.dart';

/// A position in a specific edition, in that edition's own units
/// (docs/03 §6). Converted to a work-level fraction by `ProgressMapper`.
@Freezed(unionKey: 'type')
sealed class ReadingPosition with _$ReadingPosition {
  const factory ReadingPosition.page({required int page}) = PagePosition;

  /// 0–100.
  const factory ReadingPosition.percent({required double percent}) = PercentPosition;
  const factory ReadingPosition.audio({required int seconds}) = AudioPosition;
  const factory ReadingPosition.location({required int location, int? totalLocations}) =
      KindleLocation;
  const factory ReadingPosition.finished() = FinishedPosition;

  factory ReadingPosition.fromJson(Map<String, dynamic> json) => _$ReadingPositionFromJson(json);
}
