import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/router/routes.dart';
import '../../../core/design_system/design_system.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../goals/domain/goal.dart';
import '../../goals/presentation/goals_screen.dart';
import '../../insights/presentation/insights_providers.dart';
import '../../library/presentation/library_providers.dart';
import '../../library/presentation/library_screen.dart' show cardData;
import '../../library/presentation/library_sheets.dart';
import '../../reading/presentation/session_flow.dart';

/// Home: greeting and Continue Reading (Phase 4). Activity, goals and
/// insights sections arrive in Phases 5–6.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final user = ref.watch(authStateProvider).value;
    final hour = ref.watch(clockProvider).now().hour;
    final name = user?.firstName;
    final greeting = name == null
        ? l10n.greetingNoName
        : hour < 12
        ? l10n.greetingMorning(name)
        : hour < 18
        ? l10n.greetingAfternoon(name)
        : l10n.greetingEvening(name);
    final reading = continueReading(watchShelf(ref).value ?? const []);
    final stats = watchStats(ref);
    final today = stats?.dayOf(ref.watch(clockProvider).now());
    final goals = [
      for (final g in ref.watch(goalsProvider).value ?? const <Goal>[])
        if (today != null && !g.isEnded(today) && !g.isUpcoming(today)) g,
    ].take(2).toList();

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
                child: Semantics(
                  header: true,
                  child: Text(greeting, style: context.textTheme.headlineLarge),
                ),
              ),
            ),
            if (goals.isNotEmpty && stats != null)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(
                  ChapterSpacing.gutter,
                  ChapterSpacing.xl,
                  ChapterSpacing.gutter,
                  0,
                ),
                sliver: SliverList.list(
                  children: [
                    for (final g in goals)
                      GoalCard(goal: g, progress: stats.goalProgress(g), compact: true),
                  ],
                ),
              ),
            if (reading.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: EmptyState(
                  title: l10n.homeEmptyTitle,
                  body: l10n.homeEmptyBody,
                  actionLabel: l10n.navSearch,
                  onAction: () => context.go(AppRoutes.search),
                ),
              )
            else ...[
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(
                  ChapterSpacing.gutter,
                  ChapterSpacing.xl,
                  ChapterSpacing.gutter,
                  ChapterSpacing.md,
                ),
                sliver: SliverToBoxAdapter(
                  child: Semantics(
                    header: true,
                    child: Text(l10n.homeContinueReading, style: context.textTheme.titleLarge),
                  ),
                ),
              ),
              SliverList.separated(
                itemCount: reading.length,
                separatorBuilder: (_, _) => const SizedBox(height: ChapterSpacing.md),
                itemBuilder: (context, i) {
                  final item = reading[i];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: ChapterSpacing.gutter),
                    child: ContinueReadingCard(
                      data: cardData(l10n, item),
                      resumeLabel: l10n.homeRead,
                      secondaryLabel: l10n.homeResume,
                      onSecondary: () => showProgressSheet(context, ref, item.entry.workId),
                      onTap: () => context.push(AppRoutes.book('id:${item.entry.workId}')),
                      onResume: () => startReadingSession(context, ref, item.entry.workId),
                    ),
                  );
                },
              ),
              const SliverToBoxAdapter(child: SizedBox(height: ChapterSpacing.xxxl)),
            ],
          ],
        ),
      ),
    );
  }
}
