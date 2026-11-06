import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/design_system/design_system.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../domain/stats_engine.dart';

/// One month of reading days. Colour deepens with reading time; a day without
/// reading is just a plain day, never marked as missed. Tap a day for details.
class ReadingCalendar extends StatefulWidget {
  const ReadingCalendar({
    required this.stats,
    required this.today,
    required this.weekStartsOn,
    required this.initialYear,
    super.key,
  });

  final StatsEngine stats;
  final String today;

  /// 1 = Monday … 7 = Sunday.
  final int weekStartsOn;
  final int initialYear;

  @override
  State<ReadingCalendar> createState() => _ReadingCalendarState();
}

class _ReadingCalendarState extends State<ReadingCalendar> {
  late DateTime _month = _initial();
  String? _selected;

  DateTime _initial() {
    final t = DateTime.parse(widget.today);
    if (t.year == widget.initialYear) return DateTime(t.year, t.month);
    // A past year opens on its last month with any reading, not on an empty December.
    final active = widget.stats
        .monthly(widget.initialYear)
        .where((p) => p.books > 0 || p.pages > 0 || p.seconds > 0)
        .map((p) => p.month);
    return DateTime(
      widget.initialYear,
      active.isEmpty ? 12 : active.reduce((a, b) => a > b ? a : b),
    );
  }

  @override
  void didUpdateWidget(ReadingCalendar old) {
    super.didUpdateWidget(old);
    if (old.initialYear != widget.initialYear) {
      _month = _initial();
      _selected = null;
    }
  }

  static String _date(int y, int m, int d) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '$y-${two(m)}-${two(d)}';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.chapterColors;
    final locale = Localizations.localeOf(context).toString();
    final daysInMonth = DateUtils.getDaysInMonth(_month.year, _month.month);
    final lead = (DateTime(_month.year, _month.month).weekday - widget.weekStartsOn) % 7;
    final symbols = DateFormat.E(locale).dateSymbols.NARROWWEEKDAYS;
    final selected = _selected;
    final isCurrent =
        _date(_month.year, _month.month, 1).compareTo(widget.today) > 0 ||
        widget.today.startsWith(_date(_month.year, _month.month, 1).substring(0, 7));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            IconButton(
              tooltip: l10n.insightsPreviousMonth,
              icon: const Icon(Icons.chevron_left),
              onPressed: () => setState(() {
                _month = DateTime(_month.year, _month.month - 1);
                _selected = null;
              }),
            ),
            Expanded(
              child: Text(
                DateFormat.yMMMM(locale).format(_month),
                textAlign: TextAlign.center,
                style: context.textTheme.titleSmall,
              ),
            ),
            IconButton(
              tooltip: l10n.insightsNextMonth,
              icon: const Icon(Icons.chevron_right),
              onPressed: isCurrent
                  ? null
                  : () => setState(() {
                      _month = DateTime(_month.year, _month.month + 1);
                      _selected = null;
                    }),
            ),
          ],
        ),
        Row(
          children: [
            for (var i = 0; i < 7; i++)
              Expanded(
                child: Text(
                  symbols[(widget.weekStartsOn + i) % 7],
                  textAlign: TextAlign.center,
                  style: context.textTheme.bodySmall,
                ),
              ),
          ],
        ),
        const SizedBox(height: ChapterSpacing.xs),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            mainAxisSpacing: ChapterSpacing.xs,
            crossAxisSpacing: ChapterSpacing.xs,
          ),
          itemCount: lead + daysInMonth,
          itemBuilder: (context, i) {
            if (i < lead) return const SizedBox.shrink();
            final d = i - lead + 1;
            final date = _date(_month.year, _month.month, d);
            final activity = widget.stats.day(date);
            final level = _level(activity);
            final dark = level >= 3;
            final isSelected = selected == date;
            return Semantics(
              button: true,
              selected: isSelected,
              label: _dayLabel(l10n, locale, date, activity),
              excludeSemantics: true,
              child: InkWell(
                key: ValueKey('calendar-$date'),
                borderRadius: BorderRadius.circular(ChapterRadius.sm),
                onTap: () => setState(() => _selected = isSelected ? null : date),
                child: Container(
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: level == 0
                        ? colors.surface
                        : Color.lerp(colors.accentSoft, colors.accent, (level - 1) / 3),
                    borderRadius: BorderRadius.circular(ChapterRadius.sm),
                    border: isSelected ? Border.all(color: colors.ink, width: 2) : null,
                  ),
                  child: Text(
                    '$d',
                    style: context.textTheme.bodySmall?.copyWith(
                      color: dark ? colors.onAccent : colors.ink,
                    ),
                  ),
                ),
              ),
            );
          },
        ),
        if (selected != null) ...[
          const SizedBox(height: ChapterSpacing.sm),
          Text(
            _dayLabel(l10n, locale, selected, widget.stats.day(selected)),
            key: const Key('calendar-detail'),
            style: context.textTheme.bodyMedium,
          ),
        ],
      ],
    );
  }

  /// 0 = no reading; 1–4 by time, or 1 for days with only pages or a finish.
  static int _level(DayActivity a) {
    if (!a.isActive) return 0;
    final minutes = a.seconds / 60;
    if (minutes >= 60) return 4;
    if (minutes >= 30) return 3;
    if (minutes >= 15) return 2;
    return 1;
  }

  static String _dayLabel(AppLocalizations l10n, String locale, String date, DayActivity a) {
    final day = DateFormat.MMMd(locale).format(DateTime.parse(date));
    if (!a.isActive) return l10n.insightsDayNone(day);
    final parts = [
      if (a.seconds > 0) l10n.readMinutes((a.seconds / 60).ceil()),
      if (a.pages > 0) l10n.summaryPagesRead(a.pages),
      if (a.books > 0) l10n.insightsDayFinished(a.books),
    ];
    return '$day: ${parts.join(' · ')}';
  }
}
