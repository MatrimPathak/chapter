import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../app/providers.dart';
import '../../../core/design_system/design_system.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../domain/stats_engine.dart';
import 'insights_providers.dart';
import 'reading_calendar.dart';

/// What you've read, plainly. Every number that would mislead on little data
/// says "not enough data yet" instead. No targets, no guilt.
class InsightsScreen extends ConsumerStatefulWidget {
  const InsightsScreen({super.key});

  @override
  ConsumerState<InsightsScreen> createState() => _InsightsScreenState();
}

class _InsightsScreenState extends ConsumerState<InsightsScreen> {
  int? _year;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final stats = watchStats(ref);
    final now = ref.watch(clockProvider).now();
    final year = _year ?? now.year;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.insightsTitle)),
      body: stats == null
          ? LoadingState(label: l10n.loading)
          : stats.totals().isEmpty
          ? EmptyState(
              icon: Icons.insights_outlined,
              title: l10n.insightsEmptyTitle,
              body: l10n.insightsEmptyBody,
            )
          : _Body(
              stats: stats,
              year: year,
              today: stats.dayOf(now),
              onYear: (y) => setState(() => _year = y),
              maxYear: now.year,
            ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({
    required this.stats,
    required this.year,
    required this.today,
    required this.onYear,
    required this.maxYear,
  });

  final StatsEngine stats;

  /// Years with any activity, newest first, so a long history is a tap away.
  Future<void> _chooseYear(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final years = {
      maxYear,
      year,
      for (final d in stats.activeDays) int.parse(d.substring(0, 4)),
    }.toList()..sort((a, b) => b.compareTo(a));
    final picked = await showChapterSheet<int>(
      context: context,
      title: l10n.insightsChooseYear,
      builder: (sheet) => ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(sheet).height * 0.5),
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final y in years)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('$y'),
                trailing: y == year ? const Icon(Icons.check) : null,
                onTap: () => Navigator.of(sheet).pop(y),
              ),
          ],
        ),
      ),
    );
    if (picked != null) onYear(picked);
  }

  final int year;
  final String today;
  final ValueChanged<int> onYear;
  final int maxYear;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final from = '$year-01-01';
    final to = '$year-12-31';
    final t = stats.totals(from: from, to: to);
    final streaks = stats.streaks(today);
    final average = stats.averageSession(from: from, to: to);
    final pace = stats.pagesPerHour(from: from, to: to);
    final rate = stats.booksPerMonth(today);
    final weekdays = stats.weekdaySeconds(from: from, to: to);
    final authors = stats.topAuthors(from: from, to: to);
    final genres = stats.topGenres(from: from, to: to);
    final notEnough = l10n.insightsNotEnough;
    final weekStart = ref.watch(preferencesProvider).value?.weekStartsOn ?? 1;

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        ChapterSpacing.gutter,
        0,
        ChapterSpacing.gutter,
        ChapterSpacing.xxxl,
      ),
      children: [
        Row(
          children: [
            IconButton(
              tooltip: l10n.insightsPreviousYear,
              icon: const Icon(Icons.chevron_left),
              onPressed: () => onYear(year - 1),
            ),
            Expanded(
              child: TextButton(
                key: const Key('year-picker'),
                onPressed: () => _chooseYear(context),
                child: Text(
                  '$year',
                  semanticsLabel: '$year. ${l10n.insightsChooseYear}',
                  textAlign: TextAlign.center,
                  style: context.textTheme.titleLarge,
                ),
              ),
            ),
            IconButton(
              tooltip: l10n.insightsNextYear,
              icon: const Icon(Icons.chevron_right),
              onPressed: year >= maxYear ? null : () => onYear(year + 1),
            ),
          ],
        ),
        LayoutBuilder(
          builder: (context, constraints) {
            final width = (constraints.maxWidth - ChapterSpacing.md) / 2;
            return Wrap(
              spacing: ChapterSpacing.md,
              runSpacing: ChapterSpacing.md,
              children: [
                _Stat(width: width, label: l10n.insightsBooks, value: '${t.books}'),
                _Stat(
                  width: width,
                  label: l10n.insightsPages,
                  value: NumberFormat.decimalPattern().format(t.pages),
                ),
                _Stat(
                  width: width,
                  label: l10n.insightsHours,
                  value: (t.seconds / 3600).toStringAsFixed(1),
                ),
                _Stat(width: width, label: l10n.insightsSessions, value: '${t.sessions}'),
              ],
            );
          },
        ),
        _Heading(l10n.insightsCalendar),
        ChapterCard(
          child: ReadingCalendar(
            stats: stats,
            today: today,
            weekStartsOn: weekStart,
            initialYear: year,
          ),
        ),
        _Heading(l10n.insightsMonthly),
        ChapterCard(
          child: stats.hasTrend(year)
              ? _Bars(
                  label: l10n.insightsMonthlyLabel,
                  values: [for (final p in stats.monthly(year)) p.seconds / 60],
                  labels: [
                    for (var m = 1; m <= 12; m++)
                      DateFormat.MMMMd().dateSymbols.NARROWMONTHS[m - 1],
                  ],
                  valueText: (v) => l10n.readMinutes(v.round()),
                )
              : _Muted(notEnough),
        ),
        _Heading(l10n.insightsWeekdays),
        ChapterCard(
          child: weekdays != null
              ? _Bars(
                  label: l10n.insightsWeekdaysLabel,
                  values: [for (final s in weekdays) s / 60],
                  // intl's list starts on Sunday; statistics start on Monday.
                  labels: [
                    for (var d = 1; d <= 7; d++) DateFormat.E().dateSymbols.NARROWWEEKDAYS[d % 7],
                  ],
                  valueText: (v) => l10n.readMinutes(v.round()),
                )
              : _Muted(notEnough),
        ),
        _Heading(l10n.insightsAuthors),
        ChapterCard(child: authors != null ? _Ranking(authors) : _Muted(notEnough)),
        _Heading(l10n.insightsGenres),
        ChapterCard(child: genres != null ? _Ranking(genres) : _Muted(notEnough)),
        _Heading(l10n.insightsHabits),
        ChapterCard(
          child: Column(
            children: [
              _Fact(
                l10n.insightsAverageSession,
                average == null ? notEnough : l10n.readMinutes((average.inSeconds / 60).round()),
              ),
              _Fact(l10n.insightsPagesPerHour, pace == null ? notEnough : pace.toStringAsFixed(0)),
              _Fact(l10n.insightsBooksPerMonth, rate == null ? notEnough : rate.toStringAsFixed(1)),
              _Fact(l10n.insightsDaysInARow, '${streaks.current}'),
              _Fact(
                l10n.insightsLongestRun,
                streaks.readingDays < StatsEngine.minDaysForLongestStreak
                    ? notEnough
                    : '${streaks.longest}',
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: ChapterSpacing.xl, bottom: ChapterSpacing.sm),
    child: Semantics(header: true, child: Text(text, style: context.textTheme.headlineMedium)),
  );
}

class _Muted extends StatelessWidget {
  const _Muted(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(text, style: context.textTheme.bodySmall);
}

class _Stat extends StatelessWidget {
  const _Stat({required this.width, required this.label, required this.value});

  final double width;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Semantics(
    label: '$label: $value',
    excludeSemantics: true,
    child: SizedBox(
      width: width,
      child: ChapterCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value, style: context.textTheme.displaySmall),
            Text(label, style: context.textTheme.bodySmall),
          ],
        ),
      ),
    ),
  );
}

class _Fact extends StatelessWidget {
  const _Fact(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: ChapterSpacing.xs),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: Text(label, style: context.textTheme.bodyMedium)),
        const SizedBox(width: ChapterSpacing.md),
        Flexible(
          child: Text(value, style: context.textTheme.bodyMedium, textAlign: TextAlign.end),
        ),
      ],
    ),
  );
}

class _Ranking extends StatelessWidget {
  const _Ranking(this.items);

  final List<RankedName> items;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(children: [for (final r in items) _Fact(r.name, l10n.seriesBooks(r.count))]);
  }
}

/// Simple token-coloured bars. Spoken as one label per bar.
class _Bars extends StatelessWidget {
  const _Bars({
    required this.label,
    required this.values,
    required this.labels,
    required this.valueText,
  });

  final String label;
  final List<double> values;
  final List<String> labels;
  final String Function(double) valueText;

  static const _height = 96.0;

  @override
  Widget build(BuildContext context) {
    final colors = context.chapterColors;
    final max = values.fold(0.0, (m, v) => v > m ? v : m);
    return Semantics(
      label:
          '$label. ${[for (var i = 0; i < values.length; i++) '${labels[i]}: ${valueText(values[i])}'].join(', ')}',
      excludeSemantics: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < values.length; i++)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: ChapterSpacing.xxs),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      height: max <= 0 ? 2 : (values[i] / max * _height).clamp(2.0, _height),
                      decoration: BoxDecoration(
                        color: values[i] > 0 ? colors.accent : colors.surfaceMuted,
                        borderRadius: BorderRadius.circular(ChapterRadius.sm),
                      ),
                    ),
                    const SizedBox(height: ChapterSpacing.xs),
                    Text(labels[i], style: context.textTheme.bodySmall),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
