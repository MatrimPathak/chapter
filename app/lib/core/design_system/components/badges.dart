import 'package:flutter/material.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../sync/sync_status.dart';
import '../theme/chapter_theme.dart';
import '../tokens/chapter_tokens.dart';

/// Marks a value converted across editions or otherwise estimated
/// (docs/03 §7). Every approximate number in the UI must carry this.
class ApproximateBadge extends StatelessWidget {
  const ApproximateBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.chapterColors;
    final label = AppLocalizations.of(context).approximate;
    return Semantics(
      label: label,
      child: ExcludeSemantics(
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: ChapterSpacing.sm,
            vertical: ChapterSpacing.xxs,
          ),
          decoration: BoxDecoration(
            border: Border.all(color: colors.line),
            borderRadius: BorderRadius.circular(ChapterRadius.pill),
          ),
          child: Text('≈ $label', style: context.textTheme.labelSmall),
        ),
      ),
    );
  }
}

/// Compact indicator of the global sync state (docs/05 §2.6).
class SyncBadge extends StatelessWidget {
  const SyncBadge({required this.status, super.key});

  final SyncStatus status;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.chapterColors;
    final (IconData icon, Color color, String label) = switch (status) {
      SyncSynced() => (Icons.cloud_done_outlined, colors.inkMuted, l10n.syncSynced),
      SyncSyncing() => (Icons.cloud_sync_outlined, colors.inkMuted, l10n.syncSyncing),
      SyncPending(:final count) => (
        Icons.cloud_upload_outlined,
        colors.inkMuted,
        l10n.syncPending(count),
      ),
      SyncOffline() => (Icons.cloud_off_outlined, colors.inkMuted, l10n.syncOffline),
      SyncError() => (Icons.error_outline, colors.error, l10n.syncError),
    };
    return Semantics(
      liveRegion: true,
      label: label,
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: ChapterSpacing.xs),
            Flexible(
              child: Text(label, style: context.textTheme.labelMedium?.copyWith(color: color)),
            ),
          ],
        ),
      ),
    );
  }
}
