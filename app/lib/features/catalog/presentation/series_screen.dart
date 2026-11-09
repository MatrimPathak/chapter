import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/routes.dart';
import '../../../core/design_system/design_system.dart';
import '../../../core/error/failure.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../domain/catalog_models.dart';
import 'catalog_detail_providers.dart';

/// Series in reading order (provider positions, not publication order).
/// Novellas and unnumbered entries are marked. Owned/read counts and "next
/// unread" arrive with the library in Phase 4.
class SeriesScreen extends ConsumerWidget {
  const SeriesScreen({required this.seriesId, super.key});

  final String seriesId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final series = ref.watch(seriesDetailProvider(seriesId));
    return Scaffold(
      appBar: AppBar(),
      body: series.when(
        data: (s) => _SeriesView(series: s),
        loading: () => LoadingState(label: l10n.loading),
        error: (error, _) => error is NotFoundFailure
            ? EmptyState(
                icon: Icons.collections_bookmark_outlined,
                title: l10n.seriesReadingOrder,
                body: l10n.seriesUnavailable,
              )
            : ErrorState(
                message: l10n.genericError,
                retryLabel: l10n.retry,
                onRetry: () => ref.invalidate(seriesDetailProvider(seriesId)),
              ),
      ),
    );
  }
}

class _SeriesView extends StatelessWidget {
  const _SeriesView({required this.series});

  final CatalogSeries series;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ListView(
      padding: const EdgeInsets.only(bottom: ChapterSpacing.xxxl),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: ChapterSpacing.gutter),
          child: ChapterCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  header: true,
                  child: Text(series.name, style: context.textTheme.displayMedium),
                ),
                const SizedBox(height: ChapterSpacing.xs),
                Text(
                  '${l10n.seriesBooks(series.primaryCount)} · ${l10n.seriesReadingOrder}',
                  style: context.textTheme.bodySmall,
                ),
                if (series.description != null) ...[
                  const SizedBox(height: ChapterSpacing.md),
                  Text(series.description!, style: context.textTheme.bodyLarge),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: ChapterSpacing.md),
        for (final entry in series.entries)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              ChapterSpacing.gutter,
              0,
              ChapterSpacing.gutter,
              ChapterSpacing.md,
            ),
            child: ChapterCard(
              padding: EdgeInsets.zero,
              child: BookListTile(
                padding: const EdgeInsets.all(ChapterSpacing.lg),
                data: BookCardData(
                  title: entry.work.title,
                  author: entry.work.authors.firstOrNull,
                  coverUrl: entry.work.coverUrl,
                  caption: entry.isPrimary ? null : l10n.seriesNovella,
                ),
                trailing: _PositionBadge(label: entry.positionLabel),
                onTap: () => context.push(AppRoutes.book(workKeyOf(entry.work))),
              ),
            ),
          ),
      ],
    );
  }
}

class _PositionBadge extends StatelessWidget {
  const _PositionBadge({required this.label});

  final String? label;

  @override
  Widget build(BuildContext context) {
    if (label == null) return const SizedBox(width: 32);
    return Container(
      constraints: const BoxConstraints(minWidth: 32),
      padding: const EdgeInsets.symmetric(horizontal: ChapterSpacing.sm, vertical: 2),
      decoration: BoxDecoration(
        border: Border.all(color: context.chapterColors.line),
        borderRadius: BorderRadius.circular(ChapterRadius.pill),
      ),
      child: Text(label!, textAlign: TextAlign.center, style: context.textTheme.labelMedium),
    );
  }
}
