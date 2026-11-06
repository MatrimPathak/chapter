import '../../../core/sync/lww_store.dart';
import '../../../core/sync/sync_engine.dart';
import '../../../core/utils/clock.dart';
import '../../../core/utils/id_generator.dart';
import '../domain/goal.dart';

/// Goals over the local LWW store (`users/{uid}/goals`). Local-first. Progress
/// is never stored here; `StatsEngine` computes it.
class LwwGoalRepository {
  LwwGoalRepository({
    required LwwStore store,
    required Clock clock,
    required IdGenerator ids,
    required String uid,
    required void Function() onLocalWrite,
  }) : _store = store,
       _clock = clock,
       _ids = ids,
       _onLocalWrite = onLocalWrite,
       path = 'users/$uid/goals';

  final LwwStore _store;
  final Clock _clock;
  final IdGenerator _ids;
  final void Function() _onLocalWrite;
  final String path;

  /// Newest period first.
  Stream<List<Goal>> watchGoals() => _store.watchCollection(path).map((docs) {
    final list = [for (final e in docs.entries) ?Goal.fromFields(e.key, e.value.fields)]
      ..sort((a, b) {
        final byEnd = b.end.compareTo(a.end);
        return byEnd != 0 ? byEnd : a.id.compareTo(b.id);
      });
    return list;
  });

  /// Creates a goal, or `null` if it is invalid.
  Future<String?> create({
    required GoalMetric metric,
    required GoalPeriod period,
    required String start,
    required String end,
    required int target,
  }) async {
    final id = _ids.newId();
    final goal = Goal(
      id: id,
      metric: metric,
      period: period,
      start: start,
      end: end,
      target: target,
    );
    if (!goal.isValid) return null;
    await _store.write('$path/$id', {
      GoalFields.metric: metric.name,
      GoalFields.period: period.name,
      GoalFields.start: start,
      GoalFields.end: end,
      GoalFields.target: target,
      GoalFields.createdAt: _clock.now().toUtc().toIso8601String(),
    });
    _onLocalWrite();
    return id;
  }

  /// Changes a goal. Only the given fields change, so an edit never disturbs
  /// other goals or the history they compute from.
  Future<bool> update(Goal goal, {int? target, String? start, String? end}) async {
    final next = Goal(
      id: goal.id,
      metric: goal.metric,
      period: goal.period,
      start: start ?? goal.start,
      end: end ?? goal.end,
      target: target ?? goal.target,
    );
    if (!next.isValid) return false;
    await _store.write('$path/${goal.id}', {
      GoalFields.target: ?target,
      GoalFields.start: ?start,
      GoalFields.end: ?end,
    });
    _onLocalWrite();
    return true;
  }

  Future<void> delete(String id) async {
    await _store.write('$path/$id', {GoalFields.deleted: true});
    _onLocalWrite();
  }

  Future<void> attachSync(SyncEngine engine) => engine.watchCollection(path, engine.applyLww);
}
