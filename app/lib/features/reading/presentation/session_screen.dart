import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../core/design_system/design_system.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../integrations/presentation/spotify_widgets.dart';
import '../../library/domain/library_models.dart';
import '../../library/presentation/library_providers.dart';
import '../../library/presentation/library_sheets.dart';
import '../../progress/domain/progress_mapper.dart';
import '../../progress/domain/reading_position.dart';
import '../application/session_controller.dart';
import '../domain/reading_session.dart';
import '../domain/session_clock.dart';
import '../domain/session_ports.dart';
import 'session_flow.dart';

/// Full-screen focus timer, and the summary once the session has ended.
/// Survives being closed: everything shown is derived from the persisted
/// session.
class SessionScreen extends ConsumerStatefulWidget {
  const SessionScreen({super.key});

  @override
  ConsumerState<SessionScreen> createState() => _SessionScreenState();
}

class _SessionScreenState extends ConsumerState<SessionScreen> {
  Timer? _ticker;
  late final FocusMode _focus;

  @override
  void initState() {
    super.initState();
    _focus = ref.read(focusModeProvider);
    // Repaint once a second; elapsed time itself comes from timestamps.
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {});
      unawaited(ref.read(sessionControllerProvider.notifier).tick());
    });
    unawaited(_focus.keepScreenOn(on: true));
  }

  @override
  void dispose() {
    _ticker?.cancel();
    unawaited(_focus.keepScreenOn(on: false));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionControllerProvider);
    return session.when(
      loading: () => const Scaffold(body: SizedBox.shrink()),
      error: (_, _) => Scaffold(
        appBar: AppBar(),
        body: ErrorState(message: AppLocalizations.of(context).genericError),
      ),
      data: (s) {
        if (s == null) {
          // Saved or discarded: leave.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && context.canPop()) context.pop();
          });
          return const Scaffold(body: SizedBox.shrink());
        }
        return s.isEnded ? _SummaryView(session: s) : _TimerView(session: s);
      },
    );
  }
}

/// Whether this session is on an audiobook edition.
bool _isAudio(WidgetRef ref, ActiveSession s) {
  final editions = ref.watch(userEditionsProvider(s.workId)).value ?? const <UserEdition>[];
  return editions.where((e) => e.editionId == s.editionId).firstOrNull?.metrics.isAudio ?? false;
}

class _TimerView extends ConsumerWidget {
  const _TimerView({required this.session});

  final ActiveSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final now = ref.read(clockProvider).now();
    final clock = session.clock;
    final paused = clock.state == ClockState.paused;
    final remaining = clock.remaining(now);
    final elapsed = clock.elapsed(now);
    final fraction = clock.planned.inSeconds == 0
        ? 0.0
        : elapsed.inSeconds / clock.planned.inSeconds;
    final entry = ref.watch(libraryEntryProvider(session.workId)).value;
    final controller = ref.read(sessionControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(),
      // Fills the screen when it fits, and scrolls when large text makes it not.
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: const EdgeInsets.all(ChapterSpacing.gutter),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: constraints.maxHeight - ChapterSpacing.gutter * 2,
              ),
              child: IntrinsicHeight(
                child: Column(
                  children: [
                    if (entry != null) _SessionBook(book: entry.book),
                    const Spacer(),
                    Semantics(
                      liveRegion: true,
                      label: '${formatClock(remaining)} ${l10n.sessionRemaining}',
                      child: ChapterProgressRing(
                        fraction: fraction.clamp(0.0, 1.0),
                        size: 260,
                        strokeWidth: 6,
                        color: context.chapterColors.highlight,
                        // The ring has a fixed size; large text scales down to fit inside it.
                        center: Padding(
                          padding: const EdgeInsets.all(ChapterSpacing.xl),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  formatClock(remaining),
                                  key: const Key('session-remaining'),
                                  style: context.textTheme.displayMedium?.copyWith(
                                    fontFamily: ChapterTypography.sans,
                                    fontWeight: FontWeight.w500,
                                    fontFeatures: const [FontFeature.tabularFigures()],
                                  ),
                                ),
                                Text(
                                  paused ? l10n.sessionPaused : l10n.sessionRemaining,
                                  style: context.textTheme.bodyMedium,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: ChapterSpacing.lg),
                    ChapterPill(
                      label: _isAudio(ref, session)
                          ? l10n.sessionListened(formatClock(elapsed))
                          : l10n.sessionElapsed(formatClock(elapsed)),
                    ),
                    if (session.focusModeOn) ...[
                      const SizedBox(height: ChapterSpacing.md),
                      // Not chips: their labels can't wrap at large text sizes.
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.do_not_disturb_on_outlined, size: 18),
                          const SizedBox(width: ChapterSpacing.sm),
                          Flexible(child: Text(l10n.sessionDndOn, textAlign: TextAlign.center)),
                          IconButton(
                            icon: const Icon(Icons.close_rounded),
                            tooltip: l10n.sessionDndOff,
                            onPressed: () => unawaited(controller.disableFocus()),
                          ),
                        ],
                      ),
                    ],
                    if (!session.focusModeOn && platformSupportsDnd) ...[
                      const SizedBox(height: ChapterSpacing.md),
                      TextButton.icon(
                        icon: const Icon(Icons.do_not_disturb_on_outlined, size: 18),
                        label: Text(l10n.sessionDndTurnOn, textAlign: TextAlign.center),
                        onPressed: () => unawaited(enableFocusFlow(context, ref)),
                      ),
                    ],
                    // Keyed: the rows above come and go, and polling lives in its state.
                    const SpotifyNowPlayingCard(key: ValueKey('spotify-now-playing')),
                    const Spacer(),
                    _ControlRow(
                      primary: ChapterButton(
                        label: paused ? l10n.sessionResume : l10n.sessionPause,
                        expand: true,
                        icon: Icon(paused ? Icons.play_arrow_rounded : Icons.pause_rounded),
                        onPressed: () =>
                            unawaited(paused ? controller.resume() : controller.pause()),
                      ),
                      secondary: ChapterButton(
                        label: l10n.sessionEnd,
                        variant: ChapterButtonVariant.secondary,
                        expand: true,
                        onPressed: () async {
                          final ok = await showChapterConfirmDialog(
                            context: context,
                            title: l10n.sessionEndConfirmTitle,
                            body: l10n.sessionEndConfirmBody,
                            confirmLabel: l10n.sessionEnd,
                            cancelLabel: l10n.cancel,
                          );
                          if (ok) await controller.end();
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Side by side, or stacked when large text wouldn't fit them across.
class _ControlRow extends StatelessWidget {
  const _ControlRow({required this.primary, required this.secondary});

  final Widget primary;
  final Widget secondary;

  @override
  Widget build(BuildContext context) {
    final large = MediaQuery.textScalerOf(context).scale(10) > 15;
    if (large) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          primary,
          const SizedBox(height: ChapterSpacing.sm),
          secondary,
        ],
      );
    }
    return Row(
      children: [
        Expanded(child: primary),
        const SizedBox(width: ChapterSpacing.md),
        Expanded(child: secondary),
      ],
    );
  }
}

class _SummaryView extends ConsumerStatefulWidget {
  const _SummaryView({required this.session});

  final ActiveSession session;

  @override
  ConsumerState<_SummaryView> createState() => _SummaryViewState();
}

class _SummaryViewState extends ConsumerState<_SummaryView> {
  late final TextEditingController _minutes;
  ReadingPosition? _end;
  bool _saving = false;

  ActiveSession get s => widget.session;

  @override
  void initState() {
    super.initState();
    final elapsed = s.clock.elapsed(s.clock.endedAt!);
    _minutes = TextEditingController(text: (elapsed.inSeconds / 60).round().toString());
  }

  @override
  void dispose() {
    _minutes.dispose();
    super.dispose();
  }

  Duration _readingTime() {
    final m = int.tryParse(_minutes.text.trim());
    final elapsed = s.clock.elapsed(s.clock.endedAt!);
    // Untouched field keeps second precision.
    if (m == null || m == (elapsed.inSeconds / 60).round()) return elapsed;
    return Duration(minutes: m.clamp(0, 24 * 60));
  }

  Future<void> _save(ReadingPosition? position) async {
    if (_saving) return;
    setState(() => _saving = true);
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final saved = await ref
        .read(sessionControllerProvider.notifier)
        .save(readingTime: _readingTime(), endPosition: position);
    messenger.showSnackBar(
      SnackBar(content: Text(saved == null ? l10n.summaryBookRemoved : l10n.summarySaved)),
    );
  }

  Future<void> _discard() async {
    final l10n = AppLocalizations.of(context);
    final ok = await showChapterConfirmDialog(
      context: context,
      title: l10n.summaryDiscardConfirmTitle,
      body: l10n.summaryDiscardConfirmBody,
      confirmLabel: l10n.summaryDiscard,
      cancelLabel: l10n.cancel,
      destructive: true,
    );
    if (ok) await ref.read(sessionControllerProvider.notifier).discard();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final entryAsync = ref.watch(libraryEntryProvider(s.workId));
    final editionsAsync = ref.watch(userEditionsProvider(s.workId));
    // The position form picks page/time/percent from the edition when it is
    // created, so wait for the edition before building it.
    final ready = entryAsync.hasValue && editionsAsync.hasValue;
    final entry = entryAsync.value;
    final editions = editionsAsync.value ?? const <UserEdition>[];
    final edition = editions
        .where((e) => e.editionId == (s.editionId ?? entry?.activeEditionId))
        .firstOrNull;
    final metrics =
        edition?.metrics ?? EditionMetrics(format: 'other', pageCount: entry?.book.pageCount);

    final endFraction = _end == null ? null : ProgressMapper.toFraction(_end!, metrics)?.fraction;
    final pages = _pagesRead(metrics, endFraction);
    final hours = _readingTime().inSeconds / 3600;
    String pct(double f) => l10n.progressPercentLabel((f * 100).round());

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text(l10n.summaryTitle),
        actions: [TextButton(onPressed: _discard, child: Text(l10n.summaryDiscard))],
      ),
      body: ListView(
        padding: const EdgeInsets.all(ChapterSpacing.gutter),
        children: [
          if (s.recovered) _Banner(text: l10n.summaryRecovered, icon: Icons.restore),
          if (s.clock.clockAdjusted)
            _Banner(text: l10n.summaryClockAdjusted, icon: Icons.warning_amber_rounded),
          if (entry != null) _SessionBook(book: entry.book),
          const SizedBox(height: ChapterSpacing.lg),
          TextField(
            key: const Key('summary-minutes'),
            controller: _minutes,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: metrics.isAudio ? l10n.summaryMinutesListened : l10n.summaryMinutes,
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: ChapterSpacing.md),
          Wrap(
            spacing: ChapterSpacing.sm,
            runSpacing: ChapterSpacing.sm,
            children: [
              if (s.startFraction != null || endFraction != null)
                ChapterPill(
                  label: l10n.summaryProgressChange(
                    pct(s.startFraction ?? 0),
                    endFraction == null ? '…' : pct(endFraction),
                  ),
                  tone: ChapterPillTone.accent,
                ),
              if (pages != null)
                ChapterPill(label: l10n.summaryPagesRead(pages), tone: ChapterPillTone.accent),
              if (pages != null && hours >= 1 / 60)
                ChapterPill(
                  label: l10n.summaryPagesPerHour((pages / hours).toStringAsFixed(0)),
                  tone: ChapterPillTone.highlight,
                ),
            ],
          ),
          const SizedBox(height: ChapterSpacing.xl),
          ChapterSectionHeader(title: l10n.summaryEndPosition),
          const SizedBox(height: ChapterSpacing.sm),
          if (!ready)
            const LoadingSkeleton(height: 120)
          else
            ChapterCard(
              child: ProgressForm(
                key: ValueKey((metrics.format, metrics.pageCount, metrics.audioDurationSec)),
                metrics: metrics,
                initialFraction: s.startFraction ?? 0,
                autofocus: false,
                submitLabel: l10n.summarySave,
                onChanged: (pos) => setState(() => _end = pos),
                onSubmit: (pos) => unawaited(_save(pos)),
              ),
            ),
        ],
      ),
    );
  }

  int? _pagesRead(EditionMetrics metrics, double? endFraction) {
    final start = s.startPosition;
    final end = _end;
    if (start is PagePosition && end is PagePosition) {
      final d = end.page - start.page;
      return d >= 0 ? d : null;
    }
    final pages = metrics.isAudio ? null : metrics.pageCount;
    final from = s.startFraction ?? 0;
    if (pages == null || endFraction == null || endFraction < from) return null;
    return ((endFraction - from) * pages).round();
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.text, required this.icon});

  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: ChapterSpacing.md),
    child: ChapterCard(
      child: Row(
        children: [
          Icon(icon),
          const SizedBox(width: ChapterSpacing.md),
          Expanded(child: Text(text, style: context.textTheme.bodyMedium)),
        ],
      ),
    ),
  );
}

/// The book being read, at the top of the timer and the summary.
class _SessionBook extends StatelessWidget {
  const _SessionBook({required this.book});

  final BookSummary book;

  @override
  Widget build(BuildContext context) => ChapterCard(
    child: Row(
      children: [
        BookCover(title: book.title, author: book.authorLine, imageUrl: book.coverUrl, width: 56),
        const SizedBox(width: ChapterSpacing.lg),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(book.title, style: context.textTheme.headlineSmall),
              if (book.authorLine.isNotEmpty)
                Text(book.authorLine, style: context.textTheme.bodySmall),
            ],
          ),
        ),
      ],
    ),
  );
}
