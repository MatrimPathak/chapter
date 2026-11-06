import 'package:meta/meta.dart';

enum GoalMetric {
  books,
  pages,
  minutes;

  static GoalMetric? parse(Object? v) => values.where((m) => m.name == v).firstOrNull;
}

enum GoalPeriod {
  year,
  month,
  custom;

  static GoalPeriod? parse(Object? v) => values.where((p) => p.name == v).firstOrNull;
}

/// Field names of `users/{uid}/goals/{id}`, validated by firestore.rules.
abstract final class GoalFields {
  static const metric = 'metric';
  static const period = 'period';
  static const start = 'start';
  static const end = 'end';
  static const target = 'target';
  static const createdAt = 'createdAt';
  static const deleted = 'deleted';
}

/// A reading goal. Its progress is always computed by `StatsEngine`, never
/// stored, so it can't drift from the underlying sessions and events.
/// [start] and [end] are inclusive local dates, `YYYY-MM-DD`.
@immutable
class Goal {
  const Goal({
    required this.id,
    required this.metric,
    required this.period,
    required this.start,
    required this.end,
    required this.target,
  });

  /// `null` for tombstoned or incomplete documents.
  static Goal? fromFields(String id, Map<String, Object?> f) {
    if (f[GoalFields.deleted] == true) return null;
    final metric = GoalMetric.parse(f[GoalFields.metric]);
    final period = GoalPeriod.parse(f[GoalFields.period]);
    final start = f[GoalFields.start];
    final end = f[GoalFields.end];
    final target = f[GoalFields.target];
    if (metric == null || period == null || start is! String || end is! String || target is! num) {
      return null;
    }
    return Goal(
      id: id,
      metric: metric,
      period: period,
      start: start,
      end: end,
      target: target.toInt(),
    );
  }

  final String id;
  final GoalMetric metric;
  final GoalPeriod period;
  final String start;
  final String end;
  final int target;

  /// The period has finished; the goal stays as history.
  bool isEnded(String today) => today.compareTo(end) > 0;

  bool isUpcoming(String today) => today.compareTo(start) < 0;

  bool get isValid => target > 0 && start.compareTo(end) <= 0;

  static String _two(int v) => v.toString().padLeft(2, '0');

  static (String, String) yearRange(int year) => ('$year-01-01', '$year-12-31');

  static (String, String) monthRange(int year, int month) {
    final lastDay = DateTime.utc(year, month + 1, 0).day;
    return ('$year-${_two(month)}-01', '$year-${_two(month)}-${_two(lastDay)}');
  }
}
