import '../../../l10n/generated/app_localizations.dart';
import '../../progress/domain/progress_event.dart';
import '../../progress/domain/progress_mapper.dart';
import '../../progress/domain/reading_position.dart';
import '../domain/library_models.dart';

String statusLabel(AppLocalizations l10n, ReadingStatus s) => switch (s) {
  ReadingStatus.none => l10n.statusNone,
  ReadingStatus.wantToRead => l10n.statusWantToRead,
  ReadingStatus.reading => l10n.statusReading,
  ReadingStatus.read => l10n.statusRead,
  ReadingStatus.dnf => l10n.statusDnf,
};

/// `3:12:05` / `45:10`.
String formatDuration(int seconds) {
  final h = seconds ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  final s = seconds % 60;
  String two(int v) => v.toString().padLeft(2, '0');
  return h > 0 ? '$h:${two(m)}:${two(s)}' : '$m:${two(s)}';
}

/// Parses `h:mm:ss`, `mm:ss` or plain minutes. `null` when invalid.
int? parseDuration(String input) {
  final parts = input.trim().split(':');
  if (parts.isEmpty || parts.length > 3) return null;
  final nums = parts.map(int.tryParse).toList();
  if (nums.any((n) => n == null || n < 0)) return null;
  final v = nums.cast<int>();
  return switch (v.length) {
    1 => v[0] * 60,
    2 => v[0] * 60 + v[1],
    _ => v[0] * 3600 + v[1] * 60 + v[2],
  };
}

/// Position of [progress] expressed in [edition] (the one being read now),
/// converting across editions when it was logged elsewhere.
MappedPosition? currentPosition(
  ProgressEvent? progress,
  UserEdition? edition,
  List<UserEdition> all,
  LibraryEntry entry,
) {
  if (progress == null) return null;
  final target =
      edition?.metrics ?? EditionMetrics(format: 'other', pageCount: entry.book.pageCount);
  if (progress.editionId == edition?.editionId && !progress.isApproximate) {
    return MappedPosition(progress.position, isApproximate: false);
  }
  final source = all.where((e) => e.editionId == progress.editionId).firstOrNull?.metrics;
  return ProgressMapper.fromFraction(
    progress.fraction,
    target,
    source: source,
    sourcePosition: progress.position,
  );
}

/// "p. 187 of 400 · 47%", "3:12:00 of 11:20:00 · 28%" or "47%".
String progressLabel(
  AppLocalizations l10n,
  double fraction,
  MappedPosition? position,
  EditionMetrics metrics,
) {
  final percent = l10n.progressPercentLabel((fraction * 100).round());
  final pos = position?.position;
  final total = metrics.pageCount;
  final duration = metrics.audioDurationSec;
  final detail = switch (pos) {
    PagePosition(:final page) when total != null => l10n.progressPageOf(page, total),
    AudioPosition(:final seconds) when duration != null =>
      '${formatDuration(seconds)} / ${formatDuration(duration)}',
    _ => null,
  };
  return detail == null ? percent : '$detail · $percent';
}
