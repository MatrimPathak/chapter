import 'package:flutter/material.dart';

import '../theme/chapter_theme.dart';
import '../tokens/chapter_tokens.dart';

/// Shows a Chapter-styled modal bottom sheet with an optional title.
Future<T?> showChapterSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  String? title,
  bool enableDrag = true,
}) => showModalBottomSheet<T>(
  context: context,
  enableDrag: enableDrag,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (sheetContext) => Padding(
    padding: EdgeInsets.only(
      left: ChapterSpacing.gutter,
      right: ChapterSpacing.gutter,
      bottom: MediaQuery.viewInsetsOf(sheetContext).bottom + ChapterSpacing.xl,
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (title != null) ...[
          Text(title, style: sheetContext.textTheme.headlineSmall),
          const SizedBox(height: ChapterSpacing.lg),
        ],
        builder(sheetContext),
      ],
    ),
  ),
);

/// Confirmation dialog. Returns `true` only when the user confirms.
Future<bool> showChapterConfirmDialog({
  required BuildContext context,
  required String title,
  required String body,
  required String confirmLabel,
  required String cancelLabel,
  bool destructive = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      final colors = dialogContext.chapterColors;
      return AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(cancelLabel),
          ),
          TextButton(
            style: destructive ? TextButton.styleFrom(foregroundColor: colors.error) : null,
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(confirmLabel),
          ),
        ],
      );
    },
  );
  return result ?? false;
}
