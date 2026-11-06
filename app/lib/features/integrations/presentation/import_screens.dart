import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/design_system/design_system.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../library/domain/library_models.dart';
import '../application/clippings_importer.dart';
import '../data/import_queue.dart';
import '../data/platform_ports.dart';
import '../domain/kindle_clippings.dart';
import '../domain/reading_import.dart';

/// Picks a file, keeping every failure on this screen.
Future<String?> _pickFile(BuildContext context, WidgetRef ref, List<String> extensions) async {
  final l10n = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.of(context);
  try {
    return await ref.read(textFilePickerProvider).pick(extensions);
  } on FileTooLargeException {
    messenger.showSnackBar(SnackBar(content: Text(l10n.importTooLarge)));
  } on Object {
    messenger.showSnackBar(SnackBar(content: Text(l10n.importCouldNotRead)));
  }
  return null;
}

final _importProgressProvider = StreamProvider<ImportProgress>((ref) {
  if (ref.watch(currentUserIdProvider) == null) return Stream.value(const ImportProgress());
  return ref.read(importQueueProvider).watchProgress();
});

/// Goodreads or StoryGraph: choose a file, preview, then a background import.
class CsvImportScreen extends ConsumerStatefulWidget {
  const CsvImportScreen({super.key});

  @override
  ConsumerState<CsvImportScreen> createState() => _CsvImportScreenState();
}

class _CsvImportScreenState extends ConsumerState<CsvImportScreen> {
  ImportPreview? _preview;
  String? _error;

  Future<void> _choose() async {
    final l10n = AppLocalizations.of(context);
    final content = await _pickFile(context, ref, const ['csv']);
    if (content == null || !mounted) return;
    final preview = parseReadingExport(content);
    setState(() {
      _preview = preview;
      _error = preview == null ? l10n.importNotRecognized : null;
    });
  }

  Future<void> _start() async {
    final preview = _preview;
    if (preview == null) return;
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final queue = ref.read(importQueueProvider);
    final earlier = await queue.countAlreadyDone(preview.books);
    await queue.enqueue(preview.books);
    if (earlier > 0) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.importAlreadyDone(earlier))));
    }
    if (!mounted) return;
    setState(() => _preview = null);
    unawaited(ref.read(importRunnerProvider)?.run());
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final progress = ref.watch(_importProgressProvider).value ?? const ImportProgress();
    final preview = _preview;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.importCsvTitle)),
      body: ListView(
        padding: const EdgeInsets.all(ChapterSpacing.gutter),
        children: [
          if (preview != null)
            _PreviewView(preview: preview, onStart: _start)
          else ...[
            Text(l10n.importCsvBody, style: context.textTheme.bodyMedium),
            const SizedBox(height: ChapterSpacing.lg),
            ChapterButton(
              key: const Key('import-choose'),
              label: l10n.integrationChooseFile,
              expand: true,
              onPressed: _choose,
            ),
            if (_error != null) ...[
              const SizedBox(height: ChapterSpacing.sm),
              Text(_error!, key: const Key('import-error'), style: context.textTheme.bodyMedium),
            ],
          ],
          if (!progress.isEmpty) ...[
            const SizedBox(height: ChapterSpacing.xl),
            _ProgressView(progress: progress),
          ],
        ],
      ),
    );
  }
}

class _PreviewView extends StatelessWidget {
  const _PreviewView({required this.preview, required this.onStart});

  final ImportPreview preview;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final source = preview.source == ImportSource.goodreads
        ? l10n.integrationGoodreads
        : l10n.integrationStorygraph;
    final style = context.textTheme.bodyMedium;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.importFound(preview.books.length, source),
          key: const Key('import-found'),
          style: context.textTheme.titleMedium,
        ),
        const SizedBox(height: ChapterSpacing.sm),
        Text(
          '${l10n.statusRead}: ${preview.count(ReadingStatus.read)}\n'
          '${l10n.statusReading}: ${preview.count(ReadingStatus.reading)}\n'
          '${l10n.statusWantToRead}: ${preview.count(ReadingStatus.wantToRead)}\n'
          '${l10n.statusDnf}: ${preview.count(ReadingStatus.dnf)}',
          style: style,
        ),
        if (preview.skippedRows > 0) ...[
          const SizedBox(height: ChapterSpacing.sm),
          Text(l10n.importSkipped(preview.skippedRows), style: style),
        ],
        const SizedBox(height: ChapterSpacing.md),
        Text(l10n.importPreviewNote, style: context.textTheme.bodySmall),
        const SizedBox(height: ChapterSpacing.lg),
        ChapterButton(
          key: const Key('import-start'),
          label: l10n.importStart,
          expand: true,
          onPressed: preview.books.isEmpty ? null : onStart,
        ),
      ],
    );
  }
}

class _ProgressView extends ConsumerWidget {
  const _ProgressView({required this.progress});

  final ImportProgress progress;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final style = context.textTheme.bodyMedium;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text(l10n.importProgressTitle, style: context.textTheme.titleMedium),
        ),
        const SizedBox(height: ChapterSpacing.sm),
        Text(l10n.importAdded(progress.added), key: const Key('import-added'), style: style),
        if (progress.existing > 0) Text(l10n.importExisting(progress.existing), style: style),
        if (progress.removedEarlier > 0)
          Text(l10n.importRemovedEarlier(progress.removedEarlier), style: style),
        if (progress.pending > 0) ...[
          Text(
            l10n.importWaiting(progress.pending),
            key: const Key('import-waiting'),
            style: style,
          ),
          const SizedBox(height: ChapterSpacing.xs),
          Text(l10n.importWaitingNote, style: context.textTheme.bodySmall),
        ],
        if (progress.unmatched.isNotEmpty) ...[
          const SizedBox(height: ChapterSpacing.lg),
          Text(
            l10n.importUnmatched(progress.unmatched.length),
            key: const Key('import-unmatched'),
            style: context.textTheme.titleSmall,
          ),
          const SizedBox(height: ChapterSpacing.xs),
          Text(l10n.importUnmatchedNote, style: context.textTheme.bodySmall),
          for (final title in progress.unmatched)
            Padding(
              padding: const EdgeInsets.only(top: ChapterSpacing.xs),
              child: Text(title, style: style),
            ),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton(
              style: TextButton.styleFrom(padding: EdgeInsets.zero),
              onPressed: () => ref.read(importQueueProvider).clearUnmatched(),
              child: Text(l10n.importClearUnmatched),
            ),
          ),
        ],
      ],
    );
  }
}

/// Kindle `My Clippings.txt`, read on the device.
class ClippingsImportScreen extends ConsumerStatefulWidget {
  const ClippingsImportScreen({super.key});

  @override
  ConsumerState<ClippingsImportScreen> createState() => _ClippingsImportScreenState();
}

class _ClippingsImportScreenState extends ConsumerState<ClippingsImportScreen> {
  ClippingsPlan? _plan;
  String? _message;
  bool _saving = false;

  Future<void> _choose() async {
    final l10n = AppLocalizations.of(context);
    final content = await _pickFile(context, ref, const ['txt']);
    if (content == null || !mounted) return;
    final file = parseClippings(content);
    if (file == null) {
      setState(() {
        _plan = null;
        _message = l10n.importNotClippings;
      });
      return;
    }
    final entries = await ref.read(libraryRepositoryProvider).watchEntries().first;
    if (!mounted) return;
    setState(() {
      _plan = planClippings(file, entries);
      _message = null;
    });
  }

  Future<void> _import() async {
    final plan = _plan;
    if (plan == null || _saving) return;
    final l10n = AppLocalizations.of(context);
    setState(() => _saving = true);
    var message = l10n.importCouldNotRead;
    try {
      final added = await importClippings(plan, ref.read(notesRepositoryProvider));
      message = l10n.importNotesAdded(added, plan.matched.length - added);
    } on Object {
      // Stays on this screen; anything already saved is kept.
    }
    if (!mounted) return;
    setState(() {
      _saving = false;
      _message = message;
      _plan = ClippingsPlan(matched: const [], unmatched: plan.unmatched, skipped: plan.skipped);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final plan = _plan;
    final style = context.textTheme.bodyMedium;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.importClippingsTitle)),
      body: ListView(
        padding: const EdgeInsets.all(ChapterSpacing.gutter),
        children: [
          Text(l10n.importClippingsBody, style: style),
          const SizedBox(height: ChapterSpacing.lg),
          if (plan != null && plan.matched.isNotEmpty) ...[
            Text(
              l10n.importClippingsFound(plan.matched.length),
              key: const Key('clippings-found'),
              style: context.textTheme.titleMedium,
            ),
            const SizedBox(height: ChapterSpacing.md),
            ChapterButton(
              key: const Key('clippings-import'),
              label: l10n.importStart,
              expand: true,
              isLoading: _saving,
              onPressed: _import,
            ),
          ] else
            ChapterButton(
              key: const Key('import-choose'),
              label: l10n.integrationChooseFile,
              expand: true,
              onPressed: _choose,
            ),
          if (_message != null) ...[
            const SizedBox(height: ChapterSpacing.md),
            Text(_message!, key: const Key('clippings-message'), style: style),
          ],
          if (plan != null && plan.skipped > 0) ...[
            const SizedBox(height: ChapterSpacing.md),
            Text(l10n.importSkipped(plan.skipped), style: style),
          ],
          if (plan != null && plan.unmatched.isNotEmpty) ...[
            const SizedBox(height: ChapterSpacing.lg),
            Text(l10n.importClippingsUnmatched, style: context.textTheme.titleSmall),
            const SizedBox(height: ChapterSpacing.xs),
            Text(l10n.importClippingsUnmatchedNote, style: context.textTheme.bodySmall),
            for (final e in plan.unmatched.entries)
              Padding(
                padding: const EdgeInsets.only(top: ChapterSpacing.xs),
                child: Text('${e.key} (${e.value})', style: style),
              ),
          ],
        ],
      ),
    );
  }
}
