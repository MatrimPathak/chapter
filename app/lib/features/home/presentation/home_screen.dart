import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/providers.dart';
import '../../../app/router/routes.dart';
import '../../../core/design_system/design_system.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../goals/domain/goal.dart';
import '../../goals/presentation/goals_screen.dart';
import '../../insights/domain/stats_engine.dart';
import '../../insights/presentation/insights_providers.dart';
import '../../library/domain/library_models.dart';
import '../../library/presentation/library_providers.dart';
import '../../library/presentation/library_screen.dart' show cardData;
import '../../library/presentation/library_sheets.dart';
import '../../notes/domain/note.dart';
import '../../reading/presentation/session_flow.dart';

/// Home: what you're reading now, then goals, this week, what's next and your
/// latest note. Every section comes from the reader's own data and is left out
/// when there is nothing to show.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  static const _maxUpNext = 3;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final user = ref.watch(authStateProvider).value;
    final now = ref.watch(clockProvider).now();
    final name = user?.firstName;
    final greeting = name == null
        ? l10n.greetingNoName
        : now.hour < 12
        ? l10n.greetingMorning(name)
        : now.hour < 18
        ? l10n.greetingAfternoon(name)
        : l10n.greetingEvening(name);
    final shelf = watchShelf(ref).value ?? const <ShelfItem>[];
    final reading = continueReading(shelf);
    final upNext = shelf.where((i) => i.entry.status == ReadingStatus.wantToRead).toList()
      ..sort((a, b) => b.lastActivity.compareTo(a.lastActivity));
    final stats = watchStats(ref);
    final today = stats?.dayOf(now);
    final goals = [
      for (final g in ref.watch(goalsProvider).value ?? const <Goal>[])
        if (today != null && !g.isEnded(today) && !g.isUpcoming(today)) g,
    ].take(2).toList();
    final sync = ref.watch(syncStatusProvider).value;
    final note = ref.watch(allNotesProvider).value?.firstOrNull;
    final hasActivity = stats != null && stats.totals().seconds > 0;

    void openBook(String workId) => context.push(AppRoutes.book('id:$workId'));

    final sections = <Widget>[
      if (goals.isNotEmpty && stats != null)
        Column(
          children: [
            for (final g in goals)
              Padding(
                padding: const EdgeInsets.only(bottom: ChapterSpacing.md),
                child: GoalCard(goal: g, progress: stats.goalProgress(g), compact: true),
              ),
          ],
        ),
      if (reading.isNotEmpty) ...[
        ChapterSectionHeader(title: l10n.homeContinueReading),
        ContinueReadingCard(
          data: cardData(l10n, reading.first),
          resumeLabel: l10n.homeRead,
          secondaryLabel: l10n.homeResume,
          onSecondary: () => showProgressSheet(context, ref, reading.first.entry.workId),
          onTap: () => openBook(reading.first.entry.workId),
          onResume: () => startReadingSession(context, ref, reading.first.entry.workId),
        ),
      ],
      if (reading.length > 1) ...[
        ChapterSectionHeader(title: l10n.homeAlsoReading),
        for (final item in reading.skip(1))
          ContinueReadingCard(
            data: cardData(l10n, item),
            resumeLabel: l10n.homeRead,
            secondaryLabel: l10n.homeResume,
            onSecondary: () => showProgressSheet(context, ref, item.entry.workId),
            onTap: () => openBook(item.entry.workId),
            onResume: () => startReadingSession(context, ref, item.entry.workId),
          ),
      ],
      if (hasActivity) _WeekCard(stats: stats, now: now),
      if (upNext.isNotEmpty) ...[
        ChapterSectionHeader(title: l10n.homeUpNext),
        ChapterCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (final item in upNext.take(_maxUpNext))
                BookListTile(data: cardData(l10n, item), onTap: () => openBook(item.entry.workId)),
            ],
          ),
        ),
      ],
      if (note != null) ...[
        ChapterSectionHeader(
          title: l10n.homeRecentNote,
          actionLabel: l10n.homeViewAll,
          onAction: () => context.push(AppRoutes.notes),
        ),
        _RecentNote(note: note, shelf: shelf, onTap: () => openBook(note.workId)),
      ],
    ];

    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                ChapterSpacing.gutter,
                ChapterSpacing.xl,
                ChapterSpacing.gutter,
                0,
              ),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Semantics(
                      header: true,
                      child: Text(greeting, style: context.textTheme.displayMedium),
                    ),
                    if (sync != null) ...[
                      const SizedBox(height: ChapterSpacing.xs),
                      SyncBadge(status: sync),
                    ],
                    const SizedBox(height: ChapterSpacing.xl),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: ChapterSpacing.gutter),
              sliver: SliverList.separated(
                itemCount: sections.length,
                separatorBuilder: (_, _) => const SizedBox(height: ChapterSpacing.md),
                itemBuilder: (_, i) => sections[i],
              ),
            ),
            if (reading.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: EmptyState(
                  icon: Icons.auto_stories_outlined,
                  title: l10n.homeEmptyTitle,
                  body: l10n.homeEmptyBody,
                  actionLabel: l10n.navSearch,
                  onAction: () => context.go(AppRoutes.search),
                  extraActions: [
                    ChapterButton(
                      label: l10n.scanTitle,
                      variant: ChapterButtonVariant.secondary,
                      icon: const Icon(Icons.qr_code_scanner_rounded),
                      onPressed: () => context.push(AppRoutes.scan),
                    ),
                    ChapterButton(
                      label: l10n.homeImportLibrary,
                      variant: ChapterButtonVariant.text,
                      onPressed: () => context.push(AppRoutes.integrations),
                    ),
                  ],
                ),
              )
            else
              const SliverToBoxAdapter(child: SizedBox(height: ChapterSpacing.xxxl)),
          ],
        ),
      ),
    );
  }
}

/// This week's reading minutes, Monday first, with the current streak.
class _WeekCard extends StatelessWidget {
  const _WeekCard({required this.stats, required this.now});

  final StatsEngine stats;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.chapterColors;
    final locale = Localizations.localeOf(context).toString();
    final today = DateTime(now.year, now.month, now.day);
    final monday = today.subtract(Duration(days: today.weekday - DateTime.monday));
    final days = [
      for (var i = 0; i < DateTime.daysPerWeek; i++)
        DateTime(monday.year, monday.month, monday.day + i),
    ];
    final minutes = [for (final d in days) stats.day(stats.dayOf(d)).seconds ~/ 60];
    final most = minutes.fold(0, (a, b) => a > b ? a : b);
    final total = minutes.fold(0, (a, b) => a + b);
    final streak = stats.streaks(stats.dayOf(now)).current;
    final letter = DateFormat('EEEEE', locale);
    const barArea = 72.0;

    return ChapterCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(l10n.homeThisWeek, style: context.textTheme.headlineSmall)),
              if (streak > 0)
                ChapterPill(
                  label: l10n.homeStreak(streak),
                  icon: Icons.local_fire_department_outlined,
                  tone: ChapterPillTone.highlight,
                ),
            ],
          ),
          Text(
            l10n.homeWeekMinutes(total),
            style: context.textTheme.bodySmall?.copyWith(color: colors.inkMuted),
          ),
          const SizedBox(height: ChapterSpacing.lg),
          // The numbers above say it all for screen readers.
          ExcludeSemantics(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < days.length; i++)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: ChapterSpacing.xs),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Container(
                            height: most == 0 || minutes[i] == 0
                                ? ChapterSpacing.xs
                                : ChapterSpacing.xs +
                                      (barArea - ChapterSpacing.xs) * minutes[i] / most,
                            decoration: BoxDecoration(
                              color: days[i] == today
                                  ? colors.highlight
                                  : minutes[i] == 0
                                  ? colors.surfaceMuted
                                  : colors.accent,
                              borderRadius: BorderRadius.circular(ChapterRadius.cover),
                            ),
                          ),
                          const SizedBox(height: ChapterSpacing.xs),
                          Text(letter.format(days[i]), style: context.textTheme.labelSmall),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RecentNote extends StatelessWidget {
  const _RecentNote({required this.note, required this.shelf, required this.onTap});

  final Note note;
  final List<ShelfItem> shelf;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final title = shelf.where((i) => i.entry.workId == note.workId).firstOrNull?.entry.book.title;
    final source = [?title, if (note.page != null) l10n.homeNotePage(note.page!)].join(' · ');
    return ChapterCard(
      onTap: onTap,
      child: ChapterQuote(text: note.text, source: source.isEmpty ? null : source),
    );
  }
}
