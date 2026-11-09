import 'dart:async';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../app/analytics.dart';
import '../../../app/providers.dart';
import '../../../core/design_system/design_system.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../catalog/domain/catalog_models.dart';
import '../../integrations/domain/integration.dart';
import '../../integrations/presentation/integrations_providers.dart';
import '../../notes/presentation/book_notes_section.dart';
import '../../progress/domain/completion_estimate.dart';
import '../../progress/domain/progress_mapper.dart';
import '../../progress/domain/reading_position.dart';
import '../../reading/presentation/read_screen.dart' show SessionHistoryTile;
import '../../reading/presentation/session_flow.dart';
import '../domain/library_models.dart';
import '../domain/library_repository.dart';
import 'library_providers.dart';
import 'progress_format.dart';

void _snack(BuildContext context, String message) => ScaffoldMessenger.of(context)
  ..hideCurrentSnackBar()
  ..showSnackBar(SnackBar(content: Text(message)));

String _formatName(String format) => switch (format) {
  'paperback' => 'Paperback',
  'hardcover' => 'Hardcover',
  'massMarket' => 'Mass market paperback',
  'ebook' => 'Ebook',
  'kindle' => 'Kindle',
  'epub' => 'EPUB',
  'audiobook' => 'Audiobook',
  'audible' => 'Audible',
  _ => 'Edition',
};

String editionLabel(AppLocalizations l10n, UserEdition e) => [
  _formatName(e.format),
  ?e.publisher,
  if (e.effectivePageCount != null) l10n.bookPages(e.effectivePageCount!),
  if (e.effectiveAudioDuration != null) formatDuration(e.effectiveAudioDuration!),
].join(' · ');

// ─── Add to library ───

/// Adds [work] after letting the user pick shelf, edition and ownership.
/// Duplicate-safe: an existing entry is reported, never overwritten.
Future<void> showAddToLibrarySheet(
  BuildContext context,
  WidgetRef ref,
  CatalogWork work, {
  String? editionId,
  bool owned = false,
  bool scanned = false,
}) async {
  final l10n = AppLocalizations.of(context);
  final repo = ref.read(libraryRepositoryProvider);
  // Coming back after a removal: ownership and edition are still on record.
  final previous = await repo.watchEditions(work.id).first;
  if (!context.mounted) return;
  final choice = await showChapterSheet<_AddChoice>(
    context: context,
    title: l10n.libraryAddTitle,
    builder: (_) => _AddForm(
      work: work,
      initialEditionId: editionId ?? work.defaultEdition?.id,
      initialOwned: owned || previous.any((e) => e.owned),
    ),
  );
  if (choice == null || !context.mounted) return;
  var finish = const ReadFinish.now();
  if (choice.status == ReadingStatus.read && !await repo.restoresFinishedRead(work.id)) {
    if (!context.mounted) return;
    final asked = await askFinishDate(context, ref);
    if (asked == null) return;
    finish = asked;
  }
  if (!context.mounted) return;
  final edition = work.editions.where((e) => e.id == choice.editionId).firstOrNull;
  final result = await repo.add(
    workId: work.id,
    book: bookSummaryOf(work),
    status: choice.status,
    finish: finish,
    edition: edition == null ? null : userEditionOf(edition, owned: choice.owned),
  );
  if (result == AddResult.added) {
    ref.read(analyticsProvider)(scanned ? AppEvent.scanAdded : AppEvent.bookAdded);
  }
  if (!context.mounted) return;
  _snack(
    context,
    result == AddResult.added
        ? l10n.libraryAdded(statusLabel(l10n, choice.status))
        : l10n.libraryAlreadyIn,
  );
}

class _AddChoice {
  const _AddChoice(this.status, this.editionId, this.owned);
  final ReadingStatus status;
  final String? editionId;
  final bool owned;
}

class _AddForm extends StatefulWidget {
  const _AddForm({required this.work, required this.initialEditionId, required this.initialOwned});

  final CatalogWork work;
  final String? initialEditionId;
  final bool initialOwned;

  @override
  State<_AddForm> createState() => _AddFormState();
}

class _AddFormState extends State<_AddForm> {
  late ReadingStatus _status = ReadingStatus.wantToRead;
  late String? _editionId = widget.initialEditionId;
  late bool _owned = widget.initialOwned;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final editions = widget.work.editions.take(30).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l10n.libraryAddShelf, style: context.textTheme.titleSmall),
        const SizedBox(height: ChapterSpacing.sm),
        Wrap(
          spacing: ChapterSpacing.sm,
          runSpacing: ChapterSpacing.sm,
          children: [
            for (final s in const [
              ReadingStatus.wantToRead,
              ReadingStatus.reading,
              ReadingStatus.read,
            ])
              ChoiceChip(
                label: Text(statusLabel(l10n, s)),
                selected: _status == s,
                onSelected: (_) => setState(() => _status = s),
              ),
          ],
        ),
        if (editions.isNotEmpty) ...[
          const SizedBox(height: ChapterSpacing.lg),
          DropdownButtonFormField<String>(
            initialValue: _editionId,
            isExpanded: true,
            decoration: InputDecoration(labelText: l10n.libraryAddEdition),
            items: [
              for (final e in editions)
                DropdownMenuItem(
                  value: e.id,
                  child: Text(
                    editionLabel(l10n, userEditionOf(e)),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: (v) => setState(() => _editionId = v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.libraryOwnEdition),
            value: _owned,
            onChanged: (v) => setState(() => _owned = v),
          ),
        ],
        const SizedBox(height: ChapterSpacing.lg),
        ChapterButton(
          label: l10n.libraryAddTitle,
          expand: true,
          onPressed: () => Navigator.of(context).pop(_AddChoice(_status, _editionId, _owned)),
        ),
      ],
    );
  }
}

// ─── Status, edition, remove ───

Future<void> showStatusPicker(BuildContext context, WidgetRef ref, LibraryEntry entry) async {
  final l10n = AppLocalizations.of(context);
  final repo = ref.read(libraryRepositoryProvider);
  final status = await showChapterSheet<ReadingStatus>(
    context: context,
    title: l10n.libraryAddShelf,
    builder: (sheet) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final s in const [
          ReadingStatus.wantToRead,
          ReadingStatus.reading,
          ReadingStatus.read,
          ReadingStatus.dnf,
        ])
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(statusLabel(l10n, s)),
            trailing: s == entry.status ? const Icon(Icons.check) : null,
            onTap: () => Navigator.of(sheet).pop(s),
          ),
      ],
    ),
  );
  if (status == null || !context.mounted) return;
  var finish = const ReadFinish.now();
  // A book being tracked is finishing now; otherwise today would be a guess.
  if (status == ReadingStatus.read && !await repo.hasOpenReadThrough(entry.workId)) {
    if (!context.mounted) return;
    final asked = await askFinishDate(context, ref);
    if (asked == null) return;
    finish = asked;
  }
  await repo.setStatus(entry.workId, status, finish: finish);
}

enum _FinishChoice { today, pick, unknown }

/// Asks when a book was finished; `null` if the reader backs out. A finish date
/// decides which year and goal the book counts towards, so it's never assumed.
Future<ReadFinish?> askFinishDate(BuildContext context, WidgetRef ref, {DateTime? current}) async {
  final l10n = AppLocalizations.of(context);
  final now = ref.read(clockProvider).now();
  final choice = await showChapterSheet<_FinishChoice>(
    context: context,
    title: l10n.finishTitle,
    builder: (sheet) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.today_outlined),
          title: Text(l10n.finishToday),
          onTap: () => Navigator.of(sheet).pop(_FinishChoice.today),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.calendar_month_outlined),
          title: Text(l10n.finishPick),
          onTap: () => Navigator.of(sheet).pop(_FinishChoice.pick),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.help_outline),
          title: Text(l10n.finishUnknown),
          subtitle: Text(l10n.finishUnknownBody),
          onTap: () => Navigator.of(sheet).pop(_FinishChoice.unknown),
        ),
      ],
    ),
  );
  switch (choice) {
    case null:
      return null;
    case _FinishChoice.today:
      return const ReadFinish.now();
    case _FinishChoice.unknown:
      return const ReadFinish.unknown();
    case _FinishChoice.pick:
      if (!context.mounted) return null;
      final picked = await showDatePicker(
        context: context,
        firstDate: DateTime(1900),
        lastDate: now,
        currentDate: now,
        initialDate: current != null && current.isBefore(now) ? current : now,
      );
      // Midday, so the date stays the same in nearby time zones.
      return picked == null
          ? null
          : ReadFinish.on(DateTime(picked.year, picked.month, picked.day, 12));
  }
}

Future<void> showEditionPicker(
  BuildContext context,
  WidgetRef ref,
  CatalogWork work,
  LibraryEntry entry,
) async {
  final l10n = AppLocalizations.of(context);
  final repo = ref.read(libraryRepositoryProvider);
  final typed = typedAudiobookEditions(await repo.watchEditions(entry.workId).first, work);
  if (!context.mounted) return;
  final picked = await showChapterSheet<UserEdition>(
    context: context,
    title: l10n.libraryChangeEdition,
    builder: (sheet) => ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(sheet).height * 0.6),
      child: ListView(
        shrinkWrap: true,
        children: [
          for (final e in typed)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(editionLabel(l10n, e)),
              trailing: e.editionId == entry.activeEditionId ? const Icon(Icons.check) : null,
              onTap: () => Navigator.of(sheet).pop(e),
            ),
          for (final e in work.editions.take(40))
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(editionLabel(l10n, userEditionOf(e))),
              subtitle: e.isbn13 == null ? null : Text(e.isbn13!),
              trailing: e.id == entry.activeEditionId ? const Icon(Icons.check) : null,
              onTap: () => Navigator.of(sheet).pop(userEditionOf(e)),
            ),
        ],
      ),
    ),
  );
  if (picked != null) await repo.setActiveEdition(entry.workId, picked);
}

/// Audiobook editions the reader typed in, as opposed to catalog ones.
List<UserEdition> typedAudiobookEditions(List<UserEdition> editions, CatalogWork work) => [
  for (final e in editions)
    if (e.metrics.isAudio && !work.editions.any((c) => c.id == e.editionId)) e,
];

Future<void> confirmRemoveFromLibrary(
  BuildContext context,
  WidgetRef ref,
  LibraryEntry entry,
) async {
  final l10n = AppLocalizations.of(context);
  final repo = ref.read(libraryRepositoryProvider);
  final ok = await showChapterConfirmDialog(
    context: context,
    title: l10n.libraryRemoveConfirmTitle,
    body: l10n.libraryRemoveConfirmBody,
    confirmLabel: l10n.libraryRemove,
    cancelLabel: l10n.cancel,
    destructive: true,
  );
  if (!ok) return;
  await repo.remove(entry.workId);
  if (context.mounted) _snack(context, l10n.libraryRemoved);
}

// ─── Progress ───

enum _Mode { page, percent, time }

/// Logs progress for [workId] in its active edition, in pages, percent or
/// audio time; offers "Mark as read" at 100 %.
Future<void> showProgressSheet(BuildContext context, WidgetRef ref, String workId) async {
  final l10n = AppLocalizations.of(context);
  final repo = ref.read(libraryRepositoryProvider);
  // Straight from the repository: this sheet opens from screens that don't
  // watch these providers, and Riverpod pauses unwatched ones (their `.future`
  // would never complete).
  final entry = await repo.watchEntry(workId).first;
  if (entry == null || !context.mounted) return;
  final editions = await repo.watchEditions(workId).first;
  final latest = await repo.watchLatestProgress().first;
  if (!context.mounted) return;
  final edition = editions.where((e) => e.editionId == entry.activeEditionId).firstOrNull;
  final progress = entry.activeReadThroughId == null ? null : latest[entry.activeReadThroughId];
  final metrics =
      edition?.metrics ?? EditionMetrics(format: 'other', pageCount: entry.book.pageCount);

  final position = await showChapterSheet<ReadingPosition>(
    context: context,
    title: l10n.progressTitle,
    builder: (sheet) => ProgressForm(
      onSubmit: (pos) => Navigator.of(sheet).pop(pos),
      metrics: metrics,
      initialFraction: progress?.fraction ?? 0,
      current: currentPosition(progress, edition, editions, entry),
    ),
  );
  if (position == null || !context.mounted) return;
  final event = await repo.recordProgress(workId, position);
  if (!context.mounted) return;
  if (event == null) {
    _snack(context, l10n.progressInvalid);
    return;
  }
  if (event.fraction >= 1) {
    final finish = await showChapterConfirmDialog(
      context: context,
      title: l10n.progressMarkRead,
      body: l10n.progressFinishedPrompt,
      confirmLabel: l10n.progressMarkRead,
      cancelLabel: l10n.cancel,
    );
    if (finish) await repo.setStatus(workId, ReadingStatus.read);
  } else if (context.mounted) {
    _snack(context, l10n.progressSaved);
  }
  ref.read(analyticsProvider)(AppEvent.progressUpdated);
}

/// Position entry by page, percent or audio time, with a slider. Used by
/// the progress sheet and the session summary.
class ProgressForm extends StatefulWidget {
  const ProgressForm({
    required this.metrics,
    required this.initialFraction,
    required this.onSubmit,
    this.current,
    this.submitLabel,
    this.autofocus = true,
    this.onChanged,
    super.key,
  });

  final void Function(ReadingPosition position) onSubmit;

  /// Called with the parsed position (or `null` if invalid) as it changes.
  final void Function(ReadingPosition? position)? onChanged;
  final String? submitLabel;
  final bool autofocus;

  final EditionMetrics metrics;
  final double initialFraction;
  final MappedPosition? current;

  @override
  State<ProgressForm> createState() => _ProgressFormState();
}

class _ProgressFormState extends State<ProgressForm> {
  late _Mode _mode;
  late double _fraction = widget.initialFraction.clamp(0.0, 1.0);
  final _text = TextEditingController();
  final _focus = FocusNode();
  String? _error;

  EditionMetrics get m => widget.metrics;
  bool get _hasPages => !m.isAudio && (m.pageCount ?? 0) > 0;
  bool get _hasTime => m.isAudio && (m.audioDurationSec ?? 0) > 0;

  @override
  void initState() {
    super.initState();
    _mode = _hasTime
        ? _Mode.time
        : _hasPages
        ? _Mode.page
        : _Mode.percent;
    _syncText();
    _focus.addListener(_selectAll);
  }

  @override
  void dispose() {
    _focus.dispose();
    _text.dispose();
    super.dispose();
  }

  /// Selects the prefilled value, so typing replaces it. After the frame,
  /// because the tap that gave focus places the caret first.
  void _selectAll() {
    if (!_focus.hasFocus) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_focus.hasFocus) return;
      _text.selection = TextSelection(baseOffset: 0, extentOffset: _text.text.length);
    });
  }

  void _syncText() {
    final pos = ProgressMapper.fromFraction(_fraction, m, source: m).position;
    _text.text = switch (_mode) {
      _Mode.page => switch (pos) {
        PagePosition(:final page) => '$page',
        FinishedPosition() => '${m.pageCount}',
        _ => '',
      },
      _Mode.time => switch (pos) {
        AudioPosition(:final seconds) => formatDuration(seconds),
        FinishedPosition() => formatDuration(m.audioDurationSec!),
        _ => '',
      },
      _Mode.percent => (_fraction * 100).round().toString(),
    };
  }

  ReadingPosition? _parse() {
    final raw = _text.text.trim();
    switch (_mode) {
      case _Mode.page:
        final page = int.tryParse(raw);
        if (page == null || page < 0 || page > (m.pageCount ?? 0)) return null;
        return ReadingPosition.page(page: page);
      case _Mode.percent:
        final pct = double.tryParse(raw.replaceAll('%', ''));
        if (pct == null || pct < 0 || pct > 100) return null;
        return pct >= 100
            ? const ReadingPosition.finished()
            : ReadingPosition.percent(percent: pct);
      case _Mode.time:
        final s = parseDuration(raw);
        if (s == null || s > (m.audioDurationSec ?? 0)) return null;
        return ReadingPosition.audio(seconds: s);
    }
  }

  /// The -10, -1, +1, +10 page buttons.
  void _nudge(int delta) {
    final current = int.tryParse(_text.text.trim()) ?? (_fraction * (m.pageCount ?? 0)).round();
    _text.text = '${(current + delta).clamp(0, m.pageCount ?? 0)}';
    _onText('');
  }

  void _onText(String _) {
    final pos = _parse();
    final f = pos == null ? null : ProgressMapper.toFraction(pos, m);
    setState(() {
      _error = pos == null && _text.text.isNotEmpty
          ? AppLocalizations.of(context).progressInvalid
          : null;
      if (f != null) _fraction = f.fraction;
    });
    widget.onChanged?.call(pos);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final approx = widget.current?.isApproximate ?? false;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedButton<_Mode>(
          segments: [
            if (_hasPages) ButtonSegment(value: _Mode.page, label: Text(l10n.progressPage)),
            if (_hasTime) ButtonSegment(value: _Mode.time, label: Text(l10n.progressTime)),
            ButtonSegment(value: _Mode.percent, label: Text(l10n.progressPercent)),
          ],
          selected: {_mode},
          onSelectionChanged: (s) => setState(() {
            _mode = s.first;
            _error = null;
            _syncText();
            _selectAll();
          }),
        ),
        if (!_hasPages && !_hasTime) ...[
          const SizedBox(height: ChapterSpacing.sm),
          Text(l10n.progressUnknownLength, style: context.textTheme.bodySmall),
        ],
        const SizedBox(height: ChapterSpacing.lg),
        TextField(
          key: const Key('progress-input'),
          controller: _text,
          focusNode: _focus,
          autofocus: widget.autofocus,
          keyboardType: _mode == _Mode.time
              ? TextInputType.datetime
              : const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: switch (_mode) {
              _Mode.page => l10n.progressPageHint,
              _Mode.percent => l10n.progressPercentHint,
              _Mode.time => l10n.progressTimeHint,
            },
            suffixText: switch (_mode) {
              _Mode.page => '/ ${m.pageCount}',
              _Mode.time => '/ ${formatDuration(m.audioDurationSec ?? 0)}',
              _Mode.percent => '%',
            },
            errorText: _error,
          ),
          onChanged: _onText,
          onSubmitted: (_) => _save(),
        ),
        if (approx) ...[
          const SizedBox(height: ChapterSpacing.sm),
          Row(
            children: [
              const ApproximateBadge(),
              const SizedBox(width: ChapterSpacing.sm),
              Expanded(child: Text(l10n.progressApproxHint, style: context.textTheme.bodySmall)),
            ],
          ),
        ],
        if (_mode == _Mode.page) ...[
          const SizedBox(height: ChapterSpacing.md),
          Row(
            children: [
              for (final delta in const [-10, -1, 1, 10]) ...[
                if (delta != -10) const SizedBox(width: ChapterSpacing.sm),
                Expanded(
                  child: OutlinedButton(
                    key: Key('progress-nudge-$delta'),
                    style: OutlinedButton.styleFrom(padding: EdgeInsets.zero),
                    onPressed: () => _nudge(delta),
                    child: Text(delta > 0 ? '+$delta' : '\u2212${-delta}'),
                  ),
                ),
              ],
            ],
          ),
        ],
        const SizedBox(height: ChapterSpacing.sm),
        Slider(
          value: _fraction,
          label: l10n.progressPercentLabel((_fraction * 100).round()),
          divisions: 200,
          onChanged: (v) {
            setState(() {
              _fraction = v;
              _error = null;
              _syncText();
            });
            widget.onChanged?.call(_parse());
          },
        ),
        const SizedBox(height: ChapterSpacing.sm),
        ChapterButton(
          label: widget.submitLabel ?? l10n.progressSave,
          expand: true,
          onPressed: _save,
        ),
      ],
    );
  }

  void _save() {
    final pos = _parse();
    if (pos == null) {
      setState(() => _error = AppLocalizations.of(context).progressInvalid);
      return;
    }
    widget.onSubmit(pos);
  }
}

// ─── Book detail section ───

/// The user's relationship with a work on the book detail screen: add
/// button, or shelf, progress and actions once it's in the library.
class LibrarySection extends ConsumerWidget {
  const LibrarySection({required this.work, super.key});

  final CatalogWork work;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final entry = ref.watch(libraryEntryProvider(work.id)).value;
    if (entry == null) {
      return ChapterButton(
        label: l10n.bookAddToLibrary,
        expand: true,
        icon: const Icon(Icons.add),
        onPressed: () => unawaited(showAddToLibrarySheet(context, ref, work)),
      );
    }
    final editions = ref.watch(userEditionsProvider(work.id)).value ?? const [];
    final throughs = ref.watch(readThroughsProvider(work.id)).value ?? const [];
    final latest = ref.watch(latestProgressProvider).value ?? const {};
    final edition = editions.where((e) => e.editionId == entry.activeEditionId).firstOrNull;
    final progress = entry.activeReadThroughId == null ? null : latest[entry.activeReadThroughId];
    final metrics =
        edition?.metrics ?? EditionMetrics(format: 'other', pageCount: entry.book.pageCount);
    final position = currentPosition(progress, edition, editions, entry);
    final finishedCount = throughs.where((t) => t.outcome == ReadThroughOutcome.finished).length;
    final typedAudio = typedAudiobookEditions(editions, work);
    final editableAudio =
        typedAudio.where((e) => e.editionId == entry.activeEditionId).firstOrNull ??
        typedAudio.firstOrNull;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                key: const Key('status-button'),
                icon: const Icon(Icons.bookmark_outline),
                label: Text(statusLabel(l10n, entry.status)),
                onPressed: () => unawaited(showStatusPicker(context, ref, entry)),
              ),
            ),
            IconButton(
              tooltip: entry.isFavorite ? l10n.libraryUnfavorite : l10n.libraryFavorite,
              icon: Icon(entry.isFavorite ? Icons.favorite : Icons.favorite_border),
              onPressed: () => unawaited(
                ref
                    .read(libraryRepositoryProvider)
                    .setFavorite(entry.workId, favorite: !entry.isFavorite),
              ),
            ),
            PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'edition') unawaited(showEditionPicker(context, ref, work, entry));
                if (v == 'audio') unawaited(showAudiobookSheet(context, ref, entry, editableAudio));
                if (v == 'remove') unawaited(confirmRemoveFromLibrary(context, ref, entry));
                if (v == 'wishlist') {
                  unawaited(
                    ref
                        .read(libraryRepositoryProvider)
                        .setWishlist(entry.workId, wishlist: !entry.isWishlist),
                  );
                }
                if (v == 'details' && edition != null) {
                  unawaited(showEditionDetailsSheet(context, edition));
                }
              },
              itemBuilder: (_) => [
                if (work.editions.length + typedAudio.length > 1)
                  PopupMenuItem(value: 'edition', child: Text(l10n.libraryChangeEdition)),
                PopupMenuItem(
                  value: 'audio',
                  child: Text(editableAudio == null ? l10n.audioAddEdition : l10n.audioEditEdition),
                ),
                if (edition != null)
                  PopupMenuItem(value: 'details', child: Text(l10n.editionDetails)),
                PopupMenuItem(
                  value: 'wishlist',
                  child: Text(entry.isWishlist ? l10n.wishlistRemove : l10n.wishlistAdd),
                ),
                PopupMenuItem(value: 'remove', child: Text(l10n.libraryRemove)),
              ],
            ),
          ],
        ),
        if (edition != null) ...[
          const SizedBox(height: ChapterSpacing.xs),
          Text(
            [
              editionLabel(l10n, edition),
              if (edition.owned) l10n.libraryOwnEdition,
              if (entry.isWishlist) l10n.wishlistLabel,
            ].join(' · '),
            style: context.textTheme.bodySmall,
          ),
        ],
        if (edition?.format == 'audible') ...[
          const SizedBox(height: ChapterSpacing.sm),
          Text(l10n.audioNoSync, style: context.textTheme.bodySmall),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              key: const Key('open-audible'),
              style: TextButton.styleFrom(padding: EdgeInsets.zero),
              icon: const Icon(Icons.open_in_new, size: 18),
              label: Text(l10n.audioOpenAudible),
              onPressed: () => openExternal(
                context,
                ref,
                ExternalLinks.audibleSearch(
                  work.title,
                  country: PlatformDispatcher.instance.locale.countryCode,
                ),
              ),
            ),
          ),
        ],
        if (entry.status == ReadingStatus.reading) ...[
          const SizedBox(height: ChapterSpacing.lg),
          ChapterButton(
            label: metrics.isAudio ? l10n.audioStartSession : l10n.bookStartSession,
            expand: true,
            icon: const Icon(Icons.timer_outlined),
            onPressed: () => unawaited(startReadingSession(context, ref, entry.workId)),
          ),
          const SizedBox(height: ChapterSpacing.sm),
          ChapterButton(
            label: l10n.libraryUpdateProgress,
            expand: true,
            variant: ChapterButtonVariant.secondary,
            onPressed: () => unawaited(showProgressSheet(context, ref, entry.workId)),
          ),
          if (progress != null) ...[
            const SizedBox(height: ChapterSpacing.md),
            ChapterCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          progressLabel(l10n, progress.fraction, position, metrics),
                          style: context.textTheme.titleMedium,
                        ),
                      ),
                      if (position?.isApproximate ?? false) const ApproximateBadge(),
                    ],
                  ),
                  const SizedBox(height: ChapterSpacing.sm),
                  ChapterProgressBar(
                    fraction: progress.fraction,
                    color: context.chapterColors.highlight,
                  ),
                  const SizedBox(height: ChapterSpacing.xs),
                  if (_pagesLeft(progress.fraction, metrics) case final left?)
                    Text(l10n.progressPagesLeft(left), style: context.textTheme.bodySmall),
                  _FinishEstimate(readThroughId: entry.activeReadThroughId!),
                ],
              ),
            ),
          ],
        ] else if (entry.status == ReadingStatus.wantToRead) ...[
          const SizedBox(height: ChapterSpacing.sm),
          ChapterButton(
            label: l10n.libraryStartReading,
            expand: true,
            variant: ChapterButtonVariant.secondary,
            onPressed: () => unawaited(
              ref.read(libraryRepositoryProvider).setStatus(entry.workId, ReadingStatus.reading),
            ),
          ),
        ],
        _BookSessions(workId: entry.workId),
        BookNotesSection(entry: entry),
        if (finishedCount > 0) ...[
          const SizedBox(height: ChapterSpacing.sm),
          Text(l10n.libraryReadCount(finishedCount), style: context.textTheme.bodySmall),
          for (final t in throughs.where((t) => t.outcome == ReadThroughOutcome.finished))
            _FinishedTile(through: t),
        ],
      ],
    );
  }
}

/// The reader's corrections to an edition: real page count, where the text
/// starts and ends, audio length, and page-to-time match points.
Future<void> showEditionDetailsSheet(BuildContext context, UserEdition edition) {
  final l10n = AppLocalizations.of(context);
  return showChapterSheet<void>(
    context: context,
    title: l10n.editionDetails,
    enableDrag: false,
    builder: (_) => _EditionDetailsForm(edition: edition),
  );
}

class _EditionDetailsForm extends ConsumerStatefulWidget {
  const _EditionDetailsForm({required this.edition});

  final UserEdition edition;

  @override
  ConsumerState<_EditionDetailsForm> createState() => _EditionDetailsFormState();
}

class _EditionDetailsFormState extends ConsumerState<_EditionDetailsForm> {
  late final bool _audio = widget.edition.metrics.isAudio;
  late final _pages = TextEditingController(
    text: widget.edition.pageCountOverride?.toString() ?? '',
  );
  late final _start = TextEditingController(
    text: widget.edition.contentStartPage?.toString() ?? '',
  );
  late final _end = TextEditingController(text: widget.edition.contentEndPage?.toString() ?? '');
  late final _length = TextEditingController(
    text: widget.edition.audioDurationOverride == null
        ? ''
        : formatDuration(widget.edition.audioDurationOverride!),
  );
  final _pointPage = TextEditingController();
  final _pointTime = TextEditingController();
  late final List<CalibrationPoint> _points = [...widget.edition.calibration];
  String? _error;

  @override
  void dispose() {
    for (final c in [_pages, _start, _end, _length, _pointPage, _pointTime]) {
      c.dispose();
    }
    super.dispose();
  }

  void _addPoint() {
    final page = int.tryParse(_pointPage.text.trim());
    final raw = _pointTime.text.trim();
    final seconds = raw.contains(':') ? parseDuration(raw) : null;
    if (page == null || page <= 0 || seconds == null || seconds <= 0) {
      setState(() => _error = AppLocalizations.of(context).editionInvalid);
      return;
    }
    setState(() {
      _error = null;
      _points
        ..add(CalibrationPoint(page: page, audioSeconds: seconds))
        ..sort((a, b) => a.page.compareTo(b.page));
      _pointPage.clear();
      _pointTime.clear();
    });
  }

  static int? _number(TextEditingController c) =>
      c.text.trim().isEmpty ? null : int.tryParse(c.text.trim()) ?? -1;

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    final pages = _number(_pages);
    final start = _number(_start);
    final end = _number(_end);
    final rawLength = _length.text.trim();
    final length = rawLength.isEmpty
        ? null
        : (rawLength.contains(':') ? parseDuration(rawLength) : null) ?? -1;
    final bad =
        (pages != null && pages <= 0) ||
        (start != null && start < 0) ||
        (end != null && end <= 0) ||
        (start != null && end != null && end <= start) ||
        (length != null && length <= 0);
    if (bad) {
      setState(() => _error = l10n.editionInvalid);
      return;
    }
    final e = widget.edition;
    final navigator = Navigator.of(context);
    await ref
        .read(libraryRepositoryProvider)
        .saveEditionDetails(
          UserEdition(
            editionId: e.editionId,
            workId: e.workId,
            format: e.format,
            owned: e.owned,
            isbn13: e.isbn13,
            publisher: e.publisher,
            coverUrl: e.coverUrl,
            pageCount: e.pageCount,
            audioDurationSec: e.audioDurationSec,
            pageCountOverride: pages,
            audioDurationOverride: length,
            contentStartPage: start,
            contentEndPage: end,
            calibration: _points,
          ),
        );
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    const gap = SizedBox(height: ChapterSpacing.md);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_audio) ...[
          TextField(
            key: const Key('edition-length'),
            controller: _length,
            keyboardType: TextInputType.datetime,
            decoration: InputDecoration(labelText: l10n.editionLengthOverride),
          ),
          gap,
          Text(l10n.calibrationTitle, style: context.textTheme.titleSmall),
          Text(l10n.calibrationHelp, style: context.textTheme.bodySmall),
          for (final p in _points)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.calibrationRow(p.page, formatDuration(p.audioSeconds))),
              trailing: IconButton(
                tooltip: l10n.calibrationRemove,
                icon: const Icon(Icons.close_rounded),
                onPressed: () => setState(() => _points.remove(p)),
              ),
            ),
          Row(
            children: [
              Expanded(
                child: TextField(
                  key: const Key('point-page'),
                  controller: _pointPage,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(labelText: l10n.calibrationPage),
                ),
              ),
              const SizedBox(width: ChapterSpacing.sm),
              Expanded(
                child: TextField(
                  key: const Key('point-time'),
                  controller: _pointTime,
                  keyboardType: TextInputType.datetime,
                  decoration: InputDecoration(labelText: l10n.calibrationTime),
                ),
              ),
            ],
          ),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton(
              key: const Key('point-add'),
              onPressed: _addPoint,
              child: Text(l10n.calibrationAdd),
            ),
          ),
        ] else ...[
          TextField(
            key: const Key('edition-pages'),
            controller: _pages,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: l10n.editionPageOverride),
          ),
          gap,
          TextField(
            key: const Key('edition-start'),
            controller: _start,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: l10n.editionContentStart),
          ),
          gap,
          TextField(
            key: const Key('edition-end'),
            controller: _end,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: l10n.editionContentEnd),
          ),
        ],
        if (_error != null) ...[
          gap,
          Text(_error!, key: const Key('edition-error'), style: context.textTheme.bodySmall),
        ],
        gap,
        ChapterButton(
          key: const Key('edition-save'),
          label: l10n.progressSave,
          expand: true,
          onPressed: _save,
        ),
      ],
    );
  }
}

/// Adds an audiobook edition the reader enters themselves, or changes [existing]
/// so a book doesn't collect duplicates. Saving makes it active. Progress so far
/// carries over as a fraction, labelled approximate.
Future<void> showAudiobookSheet(
  BuildContext context,
  WidgetRef ref,
  LibraryEntry entry,
  UserEdition? existing,
) {
  final l10n = AppLocalizations.of(context);
  return showChapterSheet<void>(
    context: context,
    title: existing == null ? l10n.audioAddEdition : l10n.audioEditEdition,
    builder: (_) => _AudiobookForm(entry: entry, existing: existing),
  );
}

class _AudiobookForm extends ConsumerStatefulWidget {
  const _AudiobookForm({required this.entry, required this.existing});

  final LibraryEntry entry;
  final UserEdition? existing;

  @override
  ConsumerState<_AudiobookForm> createState() => _AudiobookFormState();
}

class _AudiobookFormState extends ConsumerState<_AudiobookForm> {
  late final _duration = TextEditingController(
    text: widget.existing?.audioDurationSec == null
        ? ''
        : formatDuration(widget.existing!.audioDurationSec!),
  );
  late String _format = widget.existing?.format ?? 'audible';
  String? _error;

  @override
  void initState() {
    super.initState();
    // Typing replaces the length being corrected.
    _duration.selection = TextSelection(baseOffset: 0, extentOffset: _duration.text.length);
  }

  @override
  void dispose() {
    _duration.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    final raw = _duration.text.trim();
    // Needs h:mm:ss or mm:ss: a bare number would be ambiguous.
    final seconds = raw.contains(':') ? parseDuration(raw) : null;
    if (seconds == null || seconds <= 0 || seconds > 1000000) {
      setState(() => _error = l10n.audioInvalid);
      return;
    }
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final existing = widget.existing;
    await ref
        .read(libraryRepositoryProvider)
        .saveAudiobookEdition(
          UserEdition(
            editionId: existing?.editionId ?? ref.read(idGeneratorProvider).newId(),
            workId: widget.entry.workId,
            format: _format,
            owned: existing?.owned ?? false,
            audioDurationSec: seconds,
          ),
        );
    navigator.pop();
    messenger.showSnackBar(SnackBar(content: Text(l10n.audioAdded)));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: ChapterSpacing.sm,
          children: [
            ChoiceChip(
              label: Text(l10n.audioFormatAudible),
              selected: _format == 'audible',
              onSelected: (_) => setState(() => _format = 'audible'),
            ),
            ChoiceChip(
              label: Text(l10n.audioFormatOther),
              selected: _format == 'audiobook',
              onSelected: (_) => setState(() => _format = 'audiobook'),
            ),
          ],
        ),
        const SizedBox(height: ChapterSpacing.md),
        TextField(
          key: const Key('audio-duration'),
          controller: _duration,
          autofocus: true,
          keyboardType: TextInputType.datetime,
          decoration: InputDecoration(labelText: l10n.audioDuration, errorText: _error),
        ),
        const SizedBox(height: ChapterSpacing.lg),
        ChapterButton(
          key: const Key('audio-save'),
          label: l10n.progressSave,
          expand: true,
          onPressed: _save,
        ),
      ],
    );
  }
}

/// One finished read: tap to set or correct its date.
class _FinishedTile extends ConsumerWidget {
  const _FinishedTile({required this.through});

  final ReadThrough through;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final at = through.finishedAt?.toLocal();
    final locale = Localizations.localeOf(context).toString();
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      title: Text(
        at == null ? l10n.finishedNoDate : l10n.finishedOn(DateFormat.yMMMd(locale).format(at)),
        style: context.textTheme.bodyMedium,
      ),
      trailing: Icon(Icons.edit_calendar_outlined, semanticLabel: l10n.finishChangeDate),
      onTap: () async {
        final repo = ref.read(libraryRepositoryProvider);
        final finish = await askFinishDate(context, ref, current: at);
        if (finish != null) await repo.setFinishDate(through.id, finish);
      },
    );
  }
}

/// Pages to go in a page-based edition of known length.
int? _pagesLeft(double fraction, EditionMetrics metrics) {
  final pages = metrics.pageCount;
  if (metrics.isAudio || pages == null || pages <= 0) return null;
  final left = ((1 - fraction) * pages).ceil();
  return left > 0 ? left : null;
}

class _FinishEstimate extends ConsumerWidget {
  const _FinishEstimate({required this.readThroughId});

  final String readThroughId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final events = ref.watch(progressLogProvider(readThroughId)).value;
    if (events == null) return const SizedBox.shrink();
    final now = ref.watch(clockProvider).now();
    final estimate = CompletionEstimator.estimate(events, now);
    if (estimate == null) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final date = DateFormat.MMMd(
      Localizations.localeOf(context).toString(),
    ).format(estimate.finishOn);
    return Padding(
      padding: const EdgeInsets.only(top: ChapterSpacing.xs),
      child: Text(l10n.progressFinishBy(date), style: context.textTheme.bodySmall),
    );
  }
}

class _BookSessions extends ConsumerWidget {
  const _BookSessions({required this.workId});

  final String workId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessions = ref.watch(bookSessionsProvider(workId)).value ?? const [];
    if (sessions.isEmpty) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: ChapterSpacing.lg),
        ChapterSectionHeader(title: l10n.sessionHistoryTitle),
        const SizedBox(height: ChapterSpacing.sm),
        ChapterCard(
          padding: const EdgeInsets.symmetric(horizontal: ChapterSpacing.lg),
          child: Column(
            children: [for (final s in sessions.take(5)) SessionHistoryTile(session: s)],
          ),
        ),
      ],
    );
  }
}
