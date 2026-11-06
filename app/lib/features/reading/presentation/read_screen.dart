import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/providers.dart';
import '../../../app/router/routes.dart';
import '../../../core/design_system/design_system.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../integrations/presentation/integrations_providers.dart';
import '../../library/domain/library_models.dart';
import '../../library/presentation/library_providers.dart';
import '../application/session_controller.dart';
import '../domain/reading_session.dart';
import 'session_flow.dart';

/// Read tab: pick a book and a duration, optionally turn on focus mode,
/// start; recent sessions below.
class ReadScreen extends ConsumerStatefulWidget {
  const ReadScreen({super.key});

  static const presets = [15, 20, 30, 45, 60, 90, 120];

  @override
  ConsumerState<ReadScreen> createState() => _ReadScreenState();
}

class _ReadScreenState extends ConsumerState<ReadScreen> {
  String? _workId;
  int? _minutes;
  bool _focus = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final active = ref.watch(sessionControllerProvider).value;
    final shelf = watchShelf(ref).value ?? const <ShelfItem>[];
    final reading = continueReading(shelf);
    final want = shelf.where((i) => i.entry.status == ReadingStatus.wantToRead).toList();
    final candidates = [...reading, ...want];
    final recent = ref.watch(recentSessionsProvider).value ?? const <ReadingSession>[];
    final titles = {for (final i in shelf) i.entry.workId: i.entry.book.title};

    final workId = _workId != null && candidates.any((c) => c.entry.workId == _workId)
        ? _workId
        : candidates.firstOrNull?.entry.workId;
    final minutes = _minutes ?? ref.watch(preferencesProvider).value?.defaultTimerMin ?? 30;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.navRead)),
      body: ListView(
        padding: const EdgeInsets.all(ChapterSpacing.gutter),
        children: [
          if (active != null)
            Card(
              child: ListTile(
                leading: const Icon(Icons.timer_outlined),
                title: Text(l10n.readInProgress),
                subtitle: Text(titles[active.workId] ?? ''),
                trailing: TextButton(
                  onPressed: () => context.push(AppRoutes.session),
                  child: Text(l10n.readOpenSession),
                ),
              ),
            )
          else if (candidates.isEmpty)
            EmptyState(
              icon: Icons.timer_outlined,
              title: l10n.readEmptyTitle,
              body: l10n.readNoReadingBooks,
              actionLabel: l10n.navLibrary,
              onAction: () => context.go(AppRoutes.library),
            )
          else ...[
            Text(l10n.readPickBook, style: context.textTheme.titleMedium),
            const SizedBox(height: ChapterSpacing.sm),
            RadioGroup<String>(
              groupValue: workId,
              onChanged: (v) => setState(() => _workId = v),
              child: Column(
                children: [
                  for (final c in candidates.take(8))
                    RadioListTile<String>(
                      contentPadding: EdgeInsets.zero,
                      value: c.entry.workId,
                      title: Text(c.entry.book.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(
                        c.entry.book.authorLine,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: ChapterSpacing.lg),
            Text(l10n.readDuration, style: context.textTheme.titleMedium),
            const SizedBox(height: ChapterSpacing.sm),
            Wrap(
              spacing: ChapterSpacing.sm,
              runSpacing: ChapterSpacing.sm,
              children: [
                for (final p in ReadScreen.presets)
                  ChoiceChip(
                    label: Text(l10n.readMinutes(p)),
                    selected: minutes == p,
                    onSelected: (_) => setState(() => _minutes = p),
                  ),
                ChoiceChip(
                  label: Text(
                    ReadScreen.presets.contains(minutes)
                        ? l10n.readCustom
                        : l10n.readMinutes(minutes),
                  ),
                  selected: !ReadScreen.presets.contains(minutes),
                  onSelected: (_) => unawaited(_pickCustom(minutes)),
                ),
              ],
            ),
            const SizedBox(height: ChapterSpacing.md),
            if (platformSupportsDnd)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(l10n.readFocusMode),
                subtitle: Text(l10n.readFocusModeBody),
                value: _focus,
                onChanged: (v) => setState(() => _focus = v),
              )
            else
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.do_not_disturb_on_outlined),
                title: Text(l10n.readFocusIosTitle),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => unawaited(showFocusGuide(context)),
              ),
            const SizedBox(height: ChapterSpacing.md),
            ChapterButton(
              key: const Key('read-start'),
              label: l10n.readStart,
              expand: true,
              icon: const Icon(Icons.play_arrow_rounded),
              onPressed: workId == null
                  ? null
                  : () => unawaited(
                      startReadingSession(
                        context,
                        ref,
                        workId,
                        planned: Duration(minutes: minutes),
                        focus: _focus,
                      ),
                    ),
            ),
          ],
          const SizedBox(height: ChapterSpacing.md),
          const MusicCard(),
          if (recent.isNotEmpty) ...[
            const SizedBox(height: ChapterSpacing.xl),
            Semantics(
              header: true,
              child: Text(l10n.readRecent, style: context.textTheme.titleMedium),
            ),
            for (final r in recent.take(10))
              SessionHistoryTile(session: r, title: titles[r.workId]),
          ],
        ],
      ),
    );
  }

  Future<void> _pickCustom(int current) async {
    final value = await showDialog<int>(
      context: context,
      builder: (_) => _CustomMinutesDialog(initial: current),
    );
    if (value != null && mounted) setState(() => _minutes = value);
  }
}

/// Owns its text controller, so it is disposed only after the dialog's
/// closing animation (disposing it from the caller crashed on device).
class _CustomMinutesDialog extends StatefulWidget {
  const _CustomMinutesDialog({required this.initial});

  final int initial;

  @override
  State<_CustomMinutesDialog> createState() => _CustomMinutesDialogState();
}

class _CustomMinutesDialogState extends State<_CustomMinutesDialog> {
  late final _text = TextEditingController(text: '${widget.initial}');

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _submit() {
    final v = int.tryParse(_text.text.trim());
    if (v != null && v >= 1 && v <= 600) Navigator.of(context).pop(v);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.readCustomTitle),
      content: TextField(
        key: const Key('custom-minutes'),
        controller: _text,
        autofocus: true,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(labelText: l10n.readCustomHint),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(l10n.cancel)),
        FilledButton(onPressed: _submit, child: Text(l10n.progressSave)),
      ],
    );
  }
}

/// One saved session: "Title" / "25 min · Nov 4 · 40 pages". Can be deleted.
class SessionHistoryTile extends ConsumerWidget {
  const SessionHistoryTile({required this.session, this.title, super.key});

  final ReadingSession session;
  final String? title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final date = DateFormat.MMMd(
      Localizations.localeOf(context).toString(),
    ).format(session.startedAt.toLocal());
    final minutes = (session.activeDurationSec / 60).round();
    final detail = [
      l10n.sessionHistoryItem(minutes, date),
      if (session.pagesRead != null) l10n.summaryPagesRead(session.pagesRead!),
    ].join(' · ');
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.history_rounded),
      title: Text(title ?? detail, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: title == null ? null : Text(detail),
      trailing: IconButton(
        tooltip: l10n.sessionDelete,
        icon: const Icon(Icons.delete_outline),
        onPressed: () => unawaited(_delete(context, ref)),
      ),
    );
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final repo = ref.read(libraryRepositoryProvider);
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showChapterConfirmDialog(
      context: context,
      title: l10n.sessionDeleteTitle,
      body: l10n.sessionDeleteBody,
      confirmLabel: l10n.sessionDelete,
      cancelLabel: l10n.cancel,
      destructive: true,
    );
    if (!ok) return;
    await repo.deleteSession(session.id);
    messenger.showSnackBar(SnackBar(content: Text(l10n.sessionDeleted)));
  }
}
