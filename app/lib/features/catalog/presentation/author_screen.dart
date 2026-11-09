import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/routes.dart';
import '../../../core/design_system/design_system.dart';
import '../../../core/error/failure.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../domain/catalog_models.dart';
import 'catalog_detail_providers.dart';

/// Author details: photo (with credit), dates, biography and known works.
/// "Books in your library" is added with the library in Phase 4.
class AuthorScreen extends ConsumerWidget {
  const AuthorScreen({required this.authorKey, super.key});

  final String authorKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final author = ref.watch(authorDetailProvider(authorKey));
    return Scaffold(
      appBar: AppBar(),
      body: author.when(
        data: (a) => _AuthorView(author: a),
        loading: () => LoadingState(label: l10n.loading),
        error: (error, _) => ErrorState(
          message: error is NotFoundFailure ? l10n.bookNotFound : l10n.genericError,
          retryLabel: l10n.retry,
          onRetry: () => ref.invalidate(authorDetailProvider(authorKey)),
        ),
      ),
    );
  }
}

class _AuthorView extends StatelessWidget {
  const _AuthorView({required this.author});

  final CatalogAuthor author;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.chapterColors;
    final dates = switch ((author.birthDate, author.deathDate)) {
      (final String b, final String d) => l10n.authorBornDied(b, d),
      (final String b, null) => l10n.authorBorn(b),
      _ => null,
    };
    final initial = author.name.trim().isEmpty ? '?' : author.name.trim()[0].toUpperCase();

    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: ChapterSpacing.gutter),
          sliver: SliverList.list(
            children: [
              Center(
                child: ExcludeSemantics(
                  child: CircleAvatar(
                    radius: 64,
                    backgroundColor: colors.accentSoft,
                    foregroundImage: author.photoUrl == null
                        ? null
                        : CachedNetworkImageProvider(author.photoUrl!),
                    child: Text(initial, style: context.textTheme.headlineLarge),
                  ),
                ),
              ),
              const SizedBox(height: ChapterSpacing.lg),
              Semantics(
                header: true,
                child: Text(
                  author.name,
                  textAlign: TextAlign.center,
                  style: context.textTheme.displayMedium,
                ),
              ),
              if (dates != null)
                Text(dates, textAlign: TextAlign.center, style: context.textTheme.bodySmall),
              if (author.photoUrl != null && author.photoCredit != null)
                Padding(
                  padding: const EdgeInsets.only(top: ChapterSpacing.xs),
                  child: Text(
                    l10n.authorPhotoCredit(author.photoCredit!),
                    textAlign: TextAlign.center,
                    style: context.textTheme.labelSmall,
                  ),
                ),
              const SizedBox(height: ChapterSpacing.lg),
              ChapterCard(
                child: Text(
                  author.bio ?? l10n.authorNoBio,
                  style: author.bio == null
                      ? context.textTheme.bodyMedium?.copyWith(color: colors.inkMuted)
                      : context.textTheme.bodyLarge,
                ),
              ),
              if (author.works.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: ChapterSpacing.xl, bottom: ChapterSpacing.md),
                  child: ChapterSectionHeader(title: l10n.authorWorks),
                ),
            ],
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            ChapterSpacing.gutter,
            0,
            ChapterSpacing.gutter,
            ChapterSpacing.xxxl,
          ),
          sliver: SliverList.separated(
            itemCount: author.works.length,
            separatorBuilder: (_, _) => const SizedBox(height: ChapterSpacing.md),
            itemBuilder: (context, i) {
              final w = author.works[i];
              return ChapterCard(
                padding: EdgeInsets.zero,
                child: BookListTile(
                  padding: const EdgeInsets.all(ChapterSpacing.lg),
                  data: BookCardData(
                    title: w.title,
                    coverUrl: w.coverUrl,
                    caption: w.firstPublishedYear?.toString(),
                  ),
                  onTap: () => context.push(AppRoutes.book(workKeyOf(w))),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
