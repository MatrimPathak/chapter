import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/design_system/design_system.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../insights/presentation/insights_providers.dart';
import '../../library/domain/library_models.dart';
import '../domain/note.dart';

/// The reader's own words on a book: rating, review and notes. Private, and
/// never sent to analytics.
class BookNotesSection extends ConsumerWidget {
  const BookNotesSection({required this.entry, super.key});

  final LibraryEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final notes = ref.watch(bookNotesProvider(entry.workId)).value ?? const <Note>[];
    final review = entry.review;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Heading(l10n.ratingTitle),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: RatingStars(
            rating: entry.rating,
            onChanged: (r) =>
                unawaited(ref.read(libraryRepositoryProvider).setRating(entry.workId, r)),
          ),
        ),
        if (review != null) ...[
          const SizedBox(height: ChapterSpacing.sm),
          Text(review, style: context.textTheme.bodyMedium),
        ],
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton(
            key: const Key('edit-review'),
            style: TextButton.styleFrom(padding: EdgeInsets.zero),
            onPressed: () => unawaited(_showReviewSheet(context, ref)),
            child: Text(review == null ? l10n.reviewAdd : l10n.reviewEdit),
          ),
        ),
        _Heading(l10n.notesTitle),
        for (final n in notes) _NoteTile(note: n),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            key: const Key('add-note'),
            style: TextButton.styleFrom(padding: EdgeInsets.zero),
            icon: const Icon(Icons.add),
            label: Text(l10n.noteAdd),
            onPressed: () => unawaited(_showNoteSheet(context, entry.workId)),
          ),
        ),
      ],
    );
  }

  Future<void> _showReviewSheet(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return showChapterSheet<void>(
      context: context,
      title: l10n.reviewTitle,
      enableDrag: false, // a swipe would skip the unsaved-text check
      builder: (_) => _ReviewForm(entry: entry),
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

/// Asks before closing a sheet (tap outside, back) that holds unsaved text:
/// it's the reader's own writing.
class _DiscardGuard extends StatelessWidget {
  const _DiscardGuard({required this.dirty, required this.child});

  final bool dirty;
  final Widget child;

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !dirty,
    onPopInvokedWithResult: (didPop, _) async {
      if (didPop) return;
      final l10n = AppLocalizations.of(context);
      final navigator = Navigator.of(context);
      final discard = await showChapterConfirmDialog(
        context: context,
        title: l10n.discardTitle,
        body: l10n.discardBody,
        confirmLabel: l10n.summaryDiscard,
        cancelLabel: l10n.discardKeepEditing,
        destructive: true,
      );
      if (discard && navigator.mounted) navigator.pop();
    },
    child: child,
  );
}

class _ReviewForm extends ConsumerStatefulWidget {
  const _ReviewForm({required this.entry});

  final LibraryEntry entry;

  @override
  ConsumerState<_ReviewForm> createState() => _ReviewFormState();
}

class _ReviewFormState extends ConsumerState<_ReviewForm> {
  late final _text = TextEditingController(text: widget.entry.review ?? '');
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    final ok = await ref.read(libraryRepositoryProvider).setReview(widget.entry.workId, _text.text);
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop();
    } else {
      setState(() => _error = l10n.textTooLong);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final form = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: const Key('review-text'),
          controller: _text,
          autofocus: true,
          minLines: 3,
          maxLines: 8,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(hintText: l10n.reviewHint, errorText: _error),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: ChapterSpacing.lg),
        ChapterButton(label: l10n.progressSave, expand: true, onPressed: _save),
      ],
    );
    return _DiscardGuard(dirty: _text.text.trim() != (widget.entry.review ?? ''), child: form);
  }
}

class _NoteTile extends ConsumerWidget {
  const _NoteTile({required this.note});

  final Note note;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final meta = [
      _kindLabel(l10n, note.kind),
      if (note.page != null) l10n.notePageAnchor(note.page!),
      if (note.location != null) l10n.noteLocationAnchor(note.location!),
      if (note.isConflictCopy) l10n.noteConflictCopy,
    ].join(' · ');
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(note.text, style: context.textTheme.bodyMedium),
      subtitle: Text(meta, style: context.textTheme.bodySmall),
      onTap: () => unawaited(_showNoteSheet(context, note.workId, note: note)),
    );
  }
}

String _kindLabel(AppLocalizations l10n, NoteKind kind) => switch (kind) {
  NoteKind.note => l10n.noteKindNote,
  NoteKind.quote => l10n.noteKindQuote,
  NoteKind.observation => l10n.noteKindObservation,
};

Future<void> _showNoteSheet(BuildContext context, String workId, {Note? note}) {
  final l10n = AppLocalizations.of(context);
  return showChapterSheet<void>(
    context: context,
    title: note == null ? l10n.noteAdd : l10n.noteEdit,
    enableDrag: false, // a swipe would skip the unsaved-text check
    builder: (_) => _NoteForm(workId: workId, note: note),
  );
}

class _NoteForm extends ConsumerStatefulWidget {
  const _NoteForm({required this.workId, this.note});

  final String workId;
  final Note? note;

  @override
  ConsumerState<_NoteForm> createState() => _NoteFormState();
}

class _NoteFormState extends ConsumerState<_NoteForm> {
  late final _text = TextEditingController(text: widget.note?.text ?? '');
  late final _page = TextEditingController(text: widget.note?.page?.toString() ?? '');
  late NoteKind _kind = widget.note?.kind ?? NoteKind.note;
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    _page.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    final rawPage = _page.text.trim();
    final page = rawPage.isEmpty ? null : int.tryParse(rawPage);
    final repo = ref.read(notesRepositoryProvider);
    final note = widget.note;
    final bool ok;
    if ((rawPage.isNotEmpty && (page == null || page < 0)) || _text.text.trim().isEmpty) {
      ok = false;
    } else if (note == null) {
      ok = await repo.add(workId: widget.workId, text: _text.text, kind: _kind, page: page) != null;
    } else {
      ok = await repo.edit(note.id, text: _text.text, kind: _kind, page: page);
    }
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop();
    } else {
      setState(() => _error = l10n.noteInvalid);
    }
  }

  Future<void> _delete() async {
    final l10n = AppLocalizations.of(context);
    final repo = ref.read(notesRepositoryProvider);
    final navigator = Navigator.of(context);
    final ok = await showChapterConfirmDialog(
      context: context,
      title: l10n.noteDeleteTitle,
      body: l10n.noteDeleteBody,
      confirmLabel: l10n.noteDelete,
      cancelLabel: l10n.cancel,
      destructive: true,
    );
    if (!ok) return;
    await repo.delete(widget.note!.id);
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final form = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: ChapterSpacing.sm,
          children: [
            for (final k in NoteKind.values)
              ChoiceChip(
                label: Text(_kindLabel(l10n, k)),
                selected: _kind == k,
                onSelected: (_) => setState(() => _kind = k),
              ),
          ],
        ),
        const SizedBox(height: ChapterSpacing.md),
        TextField(
          key: const Key('note-text'),
          controller: _text,
          autofocus: widget.note == null,
          minLines: 3,
          maxLines: 8,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(hintText: l10n.noteHint, errorText: _error),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: ChapterSpacing.md),
        TextField(
          key: const Key('note-page'),
          controller: _page,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(labelText: l10n.notePageOptional),
        ),
        const SizedBox(height: ChapterSpacing.lg),
        ChapterButton(
          key: const Key('note-save'),
          label: l10n.progressSave,
          expand: true,
          onPressed: _save,
        ),
        if (widget.note != null) ...[
          const SizedBox(height: ChapterSpacing.sm),
          ChapterButton(
            label: l10n.noteDelete,
            expand: true,
            variant: ChapterButtonVariant.text,
            onPressed: _delete,
          ),
        ],
      ],
    );
    return _DiscardGuard(dirty: _text.text.trim() != (widget.note?.text ?? ''), child: form);
  }
}
