import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/router/routes.dart';
import '../../../core/design_system/design_system.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../library/presentation/library_providers.dart';
import '../application/session_controller.dart';
import '../domain/session_clock.dart';
import 'session_flow.dart';

/// Compact bar above the nav bar while a session runs (docs/02 §6): book and
/// remaining time; tap to open the timer.
class ActiveSessionBar extends ConsumerStatefulWidget {
  const ActiveSessionBar({super.key});

  @override
  ConsumerState<ActiveSessionBar> createState() => _ActiveSessionBarState();
}

class _ActiveSessionBarState extends ConsumerState<ActiveSessionBar> {
  Timer? _ticker;

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _ensureTicker(bool needed) {
    if (needed && _ticker == null) {
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else if (!needed) {
      _ticker?.cancel();
      _ticker = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(sessionControllerProvider).value;
    _ensureTicker(s != null && s.clock.state == ClockState.running);
    if (s == null) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final title = ref.watch(libraryEntryProvider(s.workId)).value?.book.title ?? '';
    final now = ref.read(clockProvider).now();
    final status = switch (s.clock.state) {
      ClockState.running => '${formatClock(s.clock.remaining(now))} ${l10n.sessionRemaining}',
      ClockState.paused => l10n.sessionPaused,
      ClockState.ended => l10n.summaryTitle,
    };
    return Material(
      color: Theme.of(context).colorScheme.secondaryContainer,
      child: InkWell(
        key: const Key('active-session-bar'),
        onTap: () => context.push(AppRoutes.session),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: ChapterSpacing.gutter,
            vertical: ChapterSpacing.sm,
          ),
          child: Row(
            children: [
              const Icon(Icons.timer_outlined, size: 20),
              const SizedBox(width: ChapterSpacing.sm),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.textTheme.titleSmall,
                ),
              ),
              const SizedBox(width: ChapterSpacing.sm),
              Flexible(
                child: Text(
                  status,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.textTheme.bodyMedium,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
