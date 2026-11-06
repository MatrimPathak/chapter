import 'package:flutter/material.dart';

import '../tokens/chapter_tokens.dart';

enum ChapterButtonVariant { primary, secondary, text }

/// The single button component used across the app.
class ChapterButton extends StatelessWidget {
  const ChapterButton({
    required this.label,
    required this.onPressed,
    super.key,
    this.variant = ChapterButtonVariant.primary,
    this.icon,
    this.isLoading = false,
    this.expand = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final ChapterButtonVariant variant;
  final Widget? icon;

  /// Shows a progress indicator and disables the button.
  final bool isLoading;

  /// Fills the available width.
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final callback = isLoading ? null : onPressed;
    final Widget child = isLoading
        ? SizedBox.square(
            dimension: 20,
            child: CircularProgressIndicator(strokeWidth: 2, semanticsLabel: label),
          )
        : Text(label, textAlign: TextAlign.center);
    final leading = isLoading ? null : icon;

    final Widget button = switch (variant) {
      ChapterButtonVariant.primary =>
        leading == null
            ? FilledButton(onPressed: callback, child: child)
            : FilledButton.icon(onPressed: callback, icon: leading, label: child),
      ChapterButtonVariant.secondary =>
        leading == null
            ? OutlinedButton(onPressed: callback, child: child)
            : OutlinedButton.icon(onPressed: callback, icon: leading, label: child),
      ChapterButtonVariant.text =>
        leading == null
            ? TextButton(onPressed: callback, child: child)
            : TextButton.icon(onPressed: callback, icon: leading, label: child),
    };

    final semantic = Semantics(
      button: true,
      enabled: callback != null,
      label: isLoading ? label : null,
      excludeSemantics: isLoading,
      child: button,
    );
    return expand
        ? SizedBox(
            width: double.infinity,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: ChapterSizes.minTouchTarget),
              child: semantic,
            ),
          )
        : semantic;
  }
}
