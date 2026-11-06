import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/providers.dart';
import '../../../app/router/routes.dart';
import '../../../core/design_system/design_system.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../insights/domain/stats_engine.dart';
import '../../insights/presentation/insights_providers.dart';
import '../domain/goal.dart';

String goalValueText(AppLocalizations l10n, Goal goal, GoalProgress p) => switch (goal.metric) {
  GoalMetric.books => l10n.goalBooksOf(p.value, p.target),
  GoalMetric.pages => l10n.goalPagesOf(p.value, p.target),
  GoalMetric.minutes => l10n.goalMinutesOf(p.value, p.target),
};

String goalPeriodText(BuildContext context, Goal goal) {
  final locale = Localizations.localeOf(context).toString();
  final start = DateTime.parse(goal.start);
  return switch (goal.period) {
    GoalPeriod.year => '${start.year}',
    GoalPeriod.month => DateFormat.yMMMM(locale).format(start),
    GoalPeriod.custom =>
      '${DateFormat.yMMMd(locale).format(start)} – '
          '${DateFormat.yMMMd(locale).format(DateTime.parse(goal.end))}',
  };
}

class GoalsScreen extends ConsumerWidget {
  const GoalsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final goals = ref.watch(goalsProvider).value;
    final stats = watchStats(ref);
    final loaded = goals != null && stats != null;
    final today = stats?.dayOf(ref.watch(clockProvider).now()) ?? '';
    final current = loaded ? goals.where((g) => !g.isEnded(today)).toList() : const <Goal>[];
    final history = loaded ? goals.where((g) => g.isEnded(today)).toList() : const <Goal>[];

    return Scaffold(
      appBar: AppBar(title: Text(l10n.goalsTitle)),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('add-goal'),
        icon: const Icon(Icons.add),
        label: Text(l10n.goalAdd),
        onPressed: () => unawaited(_showGoalSheet(context, ref)),
      ),
      body: !loaded
          ? LoadingState(label: l10n.loading)
          : goals.isEmpty
          ? EmptyState(
              icon: Icons.flag_outlined,
              title: l10n.goalsEmptyTitle,
              body: l10n.goalsEmptyBody,
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(
                ChapterSpacing.gutter,
                ChapterSpacing.sm,
                ChapterSpacing.gutter,
                96,
              ),
              children: [
                for (final g in current) GoalCard(goal: g, progress: stats.goalProgress(g)),
                if (history.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.only(
                      top: ChapterSpacing.xl,
                      bottom: ChapterSpacing.sm,
                    ),
                    child: Semantics(
                      header: true,
                      child: Text(l10n.goalsHistory, style: context.textTheme.titleMedium),
                    ),
                  ),
                  for (final g in history) GoalCard(goal: g, progress: stats.goalProgress(g)),
                ],
              ],
            ),
    );
  }
}

/// A goal and where it stands: numbers only, no judgement.
class GoalCard extends ConsumerWidget {
  const GoalCard({required this.goal, required this.progress, this.compact = false, super.key});

  final Goal goal;
  final GoalProgress progress;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final value = goalValueText(l10n, goal, progress);
    final period = goalPeriodText(context, goal);
    return Card(
      margin: const EdgeInsets.only(bottom: ChapterSpacing.md),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: compact
            ? () => context.push(AppRoutes.goals)
            : () => unawaited(_showGoalSheet(context, ref, goal: goal)),
        child: Padding(
          padding: const EdgeInsets.all(ChapterSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(value, style: context.textTheme.titleMedium),
              Text(period, style: context.textTheme.bodySmall),
              const SizedBox(height: ChapterSpacing.sm),
              ChapterProgressBar(fraction: progress.fraction, semanticLabel: '$value, $period'),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> _showGoalSheet(BuildContext context, WidgetRef ref, {Goal? goal}) {
  final l10n = AppLocalizations.of(context);
  return showChapterSheet<void>(
    context: context,
    title: goal == null ? l10n.goalAdd : l10n.goalEdit,
    builder: (_) => _GoalForm(goal: goal),
  );
}

class _GoalForm extends ConsumerStatefulWidget {
  const _GoalForm({this.goal});

  final Goal? goal;

  @override
  ConsumerState<_GoalForm> createState() => _GoalFormState();
}

class _GoalFormState extends ConsumerState<_GoalForm> {
  late GoalMetric _metric = widget.goal?.metric ?? GoalMetric.books;
  late GoalPeriod _period = widget.goal?.period ?? GoalPeriod.year;
  late final _target = TextEditingController(text: widget.goal?.target.toString() ?? '');
  DateTimeRange? _custom;
  String? _error;

  bool get _editing => widget.goal != null;

  @override
  void dispose() {
    _target.dispose();
    super.dispose();
  }

  (String, String)? _range() {
    final now = ref.read(clockProvider).now();
    String date(DateTime d) => DateFormat('yyyy-MM-dd').format(d);
    return switch (_period) {
      GoalPeriod.year => Goal.yearRange(now.year),
      GoalPeriod.month => Goal.monthRange(now.year, now.month),
      GoalPeriod.custom => _custom == null ? null : (date(_custom!.start), date(_custom!.end)),
    };
  }

  Future<void> _pickRange() async {
    final now = ref.read(clockProvider).now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 5),
      initialDateRange: _custom,
    );
    if (picked != null && mounted) setState(() => _custom = picked);
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    final target = int.tryParse(_target.text.trim());
    if (target == null || target <= 0 || target > 1000000) {
      setState(() => _error = l10n.goalInvalidTarget);
      return;
    }
    final repo = ref.read(goalRepositoryProvider);
    final goal = widget.goal;
    if (goal != null) {
      await repo.update(goal, target: target);
    } else {
      final range = _range();
      if (range == null) {
        setState(() => _error = l10n.goalPickDates);
        return;
      }
      await repo.create(
        metric: _metric,
        period: _period,
        start: range.$1,
        end: range.$2,
        target: target,
      );
    }
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final l10n = AppLocalizations.of(context);
    final repo = ref.read(goalRepositoryProvider);
    final navigator = Navigator.of(context);
    final ok = await showChapterConfirmDialog(
      context: context,
      title: l10n.goalDeleteTitle,
      body: l10n.goalDeleteBody,
      confirmLabel: l10n.goalDelete,
      cancelLabel: l10n.cancel,
      destructive: true,
    );
    if (!ok) return;
    await repo.delete(widget.goal!.id);
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toString();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!_editing) ...[
          Text(l10n.goalWhat, style: context.textTheme.titleSmall),
          const SizedBox(height: ChapterSpacing.sm),
          Wrap(
            spacing: ChapterSpacing.sm,
            children: [
              for (final m in GoalMetric.values)
                ChoiceChip(
                  label: Text(switch (m) {
                    GoalMetric.books => l10n.insightsBooks,
                    GoalMetric.pages => l10n.insightsPages,
                    GoalMetric.minutes => l10n.goalMinutes,
                  }),
                  selected: _metric == m,
                  onSelected: (_) => setState(() => _metric = m),
                ),
            ],
          ),
          const SizedBox(height: ChapterSpacing.lg),
          Text(l10n.goalWhen, style: context.textTheme.titleSmall),
          const SizedBox(height: ChapterSpacing.sm),
          Wrap(
            spacing: ChapterSpacing.sm,
            children: [
              for (final p in GoalPeriod.values)
                ChoiceChip(
                  label: Text(switch (p) {
                    GoalPeriod.year => l10n.goalThisYear,
                    GoalPeriod.month => l10n.goalThisMonth,
                    GoalPeriod.custom => l10n.readCustom,
                  }),
                  selected: _period == p,
                  onSelected: (_) {
                    setState(() => _period = p);
                    if (p == GoalPeriod.custom) unawaited(_pickRange());
                  },
                ),
            ],
          ),
          if (_period == GoalPeriod.custom && _custom != null) ...[
            const SizedBox(height: ChapterSpacing.sm),
            Text(
              '${DateFormat.yMMMd(locale).format(_custom!.start)} – '
              '${DateFormat.yMMMd(locale).format(_custom!.end)}',
              style: context.textTheme.bodyMedium,
            ),
          ],
          const SizedBox(height: ChapterSpacing.lg),
        ],
        TextField(
          key: const Key('goal-target'),
          controller: _target,
          autofocus: _editing,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(labelText: l10n.goalTarget, errorText: _error),
        ),
        const SizedBox(height: ChapterSpacing.lg),
        ChapterButton(
          key: const Key('goal-save'),
          label: l10n.progressSave,
          expand: true,
          onPressed: _save,
        ),
        if (_editing) ...[
          const SizedBox(height: ChapterSpacing.sm),
          ChapterButton(
            label: l10n.goalDelete,
            expand: true,
            variant: ChapterButtonVariant.text,
            onPressed: _delete,
          ),
        ],
      ],
    );
  }
}
