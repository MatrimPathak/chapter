import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/router/routes.dart';
import '../../../core/design_system/design_system.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../insights/presentation/insights_providers.dart';
import '../../library/presentation/library_providers.dart';
import '../domain/note.dart';

/// Every note, quote and observation across the library, newest first. Notes
/// are written and edited on their book's page, which each card opens.
class NotesScreen extends ConsumerStatefulWidget {
  const NotesScreen({super.key});

  @override
  ConsumerState<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends ConsumerState<NotesScreen> {
  NoteKind? _kind;
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final notes = ref.watch(allNotesProvider);
    final shelf = watchShelf(ref).value ?? const <ShelfItem>[];
    final titles = {for (final i in shelf) i.entry.workId: i.entry.book.title};

    bool matches(Note n) {
      if (_kind != null && n.kind != _kind) return false;
      if (_query.isEmpty) return true;
      return n.text.toLowerCase().contains(_query) ||
          (titles[n.workId]?.toLowerCase().contains(_query) ?? false);
    }

    return Scaffold(
      appBar: AppBar(title: Text(l10n.notesTitle)),
      body: notes.when(
        loading: () => LoadingState(label: l10n.loading),
        error: (_, _) => ErrorState(message: l10n.genericError),
        data: (all) {
          if (all.isEmpty) {
            return EmptyState(
              icon: Icons.edit_note_rounded,
              title: l10n.notesEmptyTitle,
              body: l10n.notesEmptyBody,
            );
          }
          final visible = all.where(matches).toList();
          return ListView(
            padding: const EdgeInsets.fromLTRB(
              ChapterSpacing.gutter,
              ChapterSpacing.sm,
              ChapterSpacing.gutter,
              ChapterSpacing.xxxl,
            ),
            children: [
              ChapterTextField(
                hint: l10n.notesSearchHint,
                prefixIcon: const Icon(Icons.search_rounded),
                onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
              ),
              const SizedBox(height: ChapterSpacing.md),
              Wrap(
                spacing: ChapterSpacing.sm,
                runSpacing: ChapterSpacing.sm,
                children: [
                  ChoiceChip(
                    label: Text(l10n.libraryTabAll),
                    selected: _kind == null,
                    onSelected: (_) => setState(() => _kind = null),
                  ),
                  for (final (kind, label) in [
                    (NoteKind.note, l10n.noteKindNote),
                    (NoteKind.quote, l10n.noteKindQuote),
                    (NoteKind.observation, l10n.noteKindObservation),
                  ])
                    ChoiceChip(
                      label: Text(label),
                      selected: _kind == kind,
                      onSelected: (_) => setState(() => _kind = kind),
                    ),
                ],
              ),
              const SizedBox(height: ChapterSpacing.lg),
              if (visible.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: ChapterSpacing.xl),
                  child: Text(
                    l10n.libraryNoMatches,
                    textAlign: TextAlign.center,
                    style: context.textTheme.bodyMedium,
                  ),
                ),
              for (final note in visible)
                Padding(
                  padding: const EdgeInsets.only(bottom: ChapterSpacing.md),
                  child: _NoteCard(note: note, title: titles[note.workId]),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _NoteCard extends StatelessWidget {
  const _NoteCard({required this.note, required this.title});

  final Note note;
  final String? title;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.chapterColors;
    final date = DateFormat.yMMMd(
      Localizations.localeOf(context).toString(),
    ).format(note.createdAt.toLocal());
    final detail = [if (note.page != null) l10n.notePageAnchor(note.page!), date].join(' · ');
    return ChapterCard(
      onTap: () => context.push(AppRoutes.book('id:${note.workId}')),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null) Text(title!, style: context.textTheme.headlineSmall),
          Text(detail, style: context.textTheme.bodySmall?.copyWith(color: colors.inkMuted)),
          const SizedBox(height: ChapterSpacing.sm),
          if (note.kind == NoteKind.quote)
            ChapterQuote(text: note.text)
          else
            Text(note.text, style: context.textTheme.bodyLarge),
        ],
      ),
    );
  }
}
