import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/router/routes.dart';
import '../../../core/design_system/design_system.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../application/session_controller.dart';
import '../application/session_service.dart';

/// Starts a session for [workId] (or opens the running one) and shows the
/// timer. [planned] defaults to the last-used duration.
Future<void> startReadingSession(
  BuildContext context,
  WidgetRef ref,
  String workId, {
  Duration? planned,
  bool focus = false,
}) async {
  final controller = ref.read(sessionControllerProvider.notifier);
  final active = await ref.read(sessionControllerProvider.future);
  if (active == null) {
    final minutes = ref.read(preferencesProvider).value?.defaultTimerMin ?? 30;
    await controller.start(workId, planned ?? Duration(minutes: minutes));
    if (focus && context.mounted) await enableFocusFlow(context, ref);
  }
  if (context.mounted) unawaited(context.push(AppRoutes.session));
}

/// Turns Do Not Disturb on for the running session, explaining first when
/// the system needs the user to grant access. Never opens settings without
/// a tap; never claims iOS can do it.
Future<void> enableFocusFlow(BuildContext context, WidgetRef ref) async {
  final l10n = AppLocalizations.of(context);
  final result = await ref.read(sessionControllerProvider.notifier).enableFocus();
  if (!context.mounted) return;
  switch (result) {
    case FocusResult.enabled:
      return;
    case FocusResult.needsAccess:
      final open = await showDialog<bool>(
        context: context,
        builder: (d) => AlertDialog(
          title: Text(l10n.readFocusAccessTitle),
          content: Text(l10n.readFocusAccessBody),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(d).pop(false),
              child: Text(l10n.readFocusNotNow),
            ),
            FilledButton(
              onPressed: () => Navigator.of(d).pop(true),
              child: Text(l10n.readFocusOpenSettings),
            ),
          ],
        ),
      );
      if (open ?? false) await ref.read(focusModeProvider).openAccessSettings();
    case FocusResult.unsupported:
      await showFocusGuide(context);
    case FocusResult.failed:
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.readFocusFailed)));
  }
}

/// iOS: how to set up a Reading Focus (Chapter can't switch it on).
Future<void> showFocusGuide(BuildContext context) {
  final l10n = AppLocalizations.of(context);
  return showChapterSheet<void>(
    context: context,
    title: l10n.readFocusIosTitle,
    builder: (_) => Text(l10n.readFocusIosBody, style: context.textTheme.bodyLarge),
  );
}

/// Whether this platform can toggle Do Not Disturb at all.
bool get platformSupportsDnd => defaultTargetPlatform == TargetPlatform.android;

/// `1:05:09` or `25:00`.
String formatClock(Duration d) {
  final s = d.inSeconds.abs();
  final h = s ~/ 3600;
  final m = (s % 3600) ~/ 60;
  final sec = s % 60;
  String two(int v) => v.toString().padLeft(2, '0');
  return h > 0 ? '$h:${two(m)}:${two(sec)}' : '${two(m)}:${two(sec)}';
}
