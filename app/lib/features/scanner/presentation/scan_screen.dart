import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../app/router/routes.dart';
import '../../../core/design_system/design_system.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../catalog/domain/catalog_models.dart';
import '../../library/presentation/library_sheets.dart';
import '../domain/isbn.dart';
import 'scan_controller.dart';

/// ISBN barcode scanner (brief §7). Camera permission is requested by
/// `mobile_scanner` when the preview starts; denial falls back to typing.
class ScanScreen extends ConsumerStatefulWidget {
  const ScanScreen({super.key, this.cameraBuilder});

  /// Test seam: replaces the live camera preview.
  final Widget Function(BuildContext context, void Function(String raw) onDetect)? cameraBuilder;

  @override
  ConsumerState<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends ConsumerState<ScanScreen> {
  MobileScannerController? _camera;

  @override
  void initState() {
    super.initState();
    if (widget.cameraBuilder == null) {
      _camera = MobileScannerController(
        formats: const [BarcodeFormat.ean13],
        detectionSpeed: DetectionSpeed.noDuplicates,
      );
    }
  }

  @override
  void dispose() {
    unawaited(_camera?.dispose());
    super.dispose();
  }

  void _onDetect(String raw) => ref.read(scanControllerProvider.notifier).onBarcode(raw);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(scanControllerProvider);

    ref.listen(scanControllerProvider, (_, next) {
      switch (next) {
        case ScanFound(:final lookup):
          unawaited(_camera?.stop());
          unawaited(_showFound(lookup));
        case ScanNotABook():
          _snack(l10n.scanNotBook);
          ref.read(scanControllerProvider.notifier).reset();
        case ScanNotFound(:final isbn):
          _snack(l10n.scanNotFound(isbn));
        case ScanFailed():
          _snack(l10n.genericError);
        case ScanIdle() || ScanLookingUp():
          break;
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.scanTitle),
        actions: [
          if (_camera != null)
            IconButton(
              tooltip: l10n.scanTorch,
              icon: const Icon(Icons.flashlight_on_outlined),
              onPressed: () => unawaited(_camera!.toggleTorch()),
            ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(ChapterSpacing.gutter),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: 3,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(ChapterRadius.lg),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      const ColoredBox(color: Colors.black),
                      if (widget.cameraBuilder != null)
                        widget.cameraBuilder!(context, _onDetect)
                      else
                        MobileScanner(
                          controller: _camera,
                          onDetect: (capture) {
                            final raw = capture.barcodes.firstOrNull?.rawValue;
                            if (raw != null) _onDetect(raw);
                          },
                          errorBuilder: (context, error) => _CameraUnavailable(
                            permissionDenied:
                                error.errorCode == MobileScannerErrorCode.permissionDenied,
                            onManual: _enterManually,
                          ),
                        ),
                      const _Viewfinder(),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: ChapterSpacing.lg),
              // Scrolls when large text wouldn't otherwise leave room for it.
              Flexible(
                flex: 2,
                child: SingleChildScrollView(
                  child: ChapterCard(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Semantics(
                          liveRegion: true,
                          child: Text(
                            state is ScanLookingUp
                                ? l10n.scanLookingUp(state.isbn)
                                : l10n.scanInstructions,
                            textAlign: TextAlign.center,
                            style: context.textTheme.bodyLarge,
                          ),
                        ),
                        if (state is ScanLookingUp) ...[
                          const SizedBox(height: ChapterSpacing.md),
                          const Center(child: CircularProgressIndicator()),
                        ],
                        const SizedBox(height: ChapterSpacing.lg),
                        ChapterButton(
                          label: l10n.scanEnterManually,
                          variant: ChapterButtonVariant.secondary,
                          onPressed: state is ScanLookingUp ? null : _enterManually,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _enterManually() async {
    final l10n = AppLocalizations.of(context);
    // Validate inside the sheet, close it, *then* look up — otherwise the
    // "found" sheet would open on top of this one and be dismissed with it.
    final isbn = await showChapterSheet<String>(
      context: context,
      title: l10n.scanManualTitle,
      builder: (sheetContext) => _ManualIsbnForm(
        onSubmit: (value) {
          final normalized = Isbn.normalize(value);
          if (normalized != null) Navigator.of(sheetContext).pop(normalized);
          return normalized != null;
        },
      ),
    );
    if (isbn != null && mounted) {
      await ref.read(scanControllerProvider.notifier).onTyped(isbn);
    }
  }

  Future<void> _showFound(WorkLookup lookup) async {
    final l10n = AppLocalizations.of(context);
    final work = lookup.work;
    final edition = work.editions.where((e) => e.id == lookup.editionId).firstOrNull;
    final action = await showChapterSheet<_FoundAction>(
      context: context,
      title: l10n.scanFound,
      builder: (sheetContext) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              BookCover(
                title: work.title,
                author: work.authors.firstOrNull?.name,
                imageUrl: edition?.coverUrl ?? work.coverUrl,
                width: 84,
              ),
              const SizedBox(width: ChapterSpacing.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(work.title, style: sheetContext.textTheme.headlineSmall),
                    if (work.authors.isNotEmpty)
                      Text(work.authorLine, style: sheetContext.textTheme.bodyMedium),
                    const SizedBox(height: ChapterSpacing.xs),
                    Text(
                      [
                        ?edition?.publisher,
                        if ((edition?.pageCount ?? work.pageCount) != null)
                          l10n.bookPages((edition?.pageCount ?? work.pageCount)!),
                        ?edition?.isbn13,
                      ].join(' · '),
                      style: sheetContext.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: ChapterSpacing.xl),
          ChapterButton(
            label: l10n.scanAddToLibrary,
            expand: true,
            icon: const Icon(Icons.add),
            onPressed: () => Navigator.of(sheetContext).pop(_FoundAction.add),
          ),
          const SizedBox(height: ChapterSpacing.sm),
          ChapterButton(
            label: l10n.scanViewBook,
            expand: true,
            variant: ChapterButtonVariant.secondary,
            onPressed: () => Navigator.of(sheetContext).pop(_FoundAction.view),
          ),
          const SizedBox(height: ChapterSpacing.sm),
          ChapterButton(
            label: l10n.scanAgain,
            expand: true,
            variant: ChapterButtonVariant.text,
            onPressed: () => Navigator.of(sheetContext).pop(_FoundAction.again),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (action == _FoundAction.add) {
      // A scanned copy is usually one the user holds: default to owned.
      await showAddToLibrarySheet(
        context,
        ref,
        work,
        scanned: true,
        editionId: lookup.editionId,
        owned: true,
      );
      if (!mounted) return;
    }
    if (action == _FoundAction.view) {
      context.pushReplacement(AppRoutes.book('id:${work.id}', editionId: lookup.editionId));
    } else {
      ref.read(scanControllerProvider.notifier).reset();
      unawaited(_camera?.start());
    }
  }
}

enum _FoundAction { add, view, again }

class _ManualIsbnForm extends StatefulWidget {
  const _ManualIsbnForm({required this.onSubmit});

  /// Returns false when the input is not a valid ISBN.
  final bool Function(String value) onSubmit;

  @override
  State<_ManualIsbnForm> createState() => _ManualIsbnFormState();
}

class _ManualIsbnFormState extends State<_ManualIsbnForm> {
  final _text = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _submit() {
    final ok = widget.onSubmit(_text.text);
    if (!ok && mounted) {
      setState(() => _error = AppLocalizations.of(context).scanManualInvalid);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ChapterTextField(
          controller: _text,
          autofocus: true,
          label: l10n.bookIsbn,
          hint: l10n.scanManualHint,
          errorText: _error,
          keyboardType: TextInputType.visiblePassword,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => _submit(),
        ),
        const SizedBox(height: ChapterSpacing.lg),
        ChapterButton(label: l10n.scanLookUp, expand: true, onPressed: _submit),
      ],
    );
  }
}

class _Viewfinder extends StatelessWidget {
  const _Viewfinder();

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: Center(
      child: Container(
        width: 240,
        height: 140,
        decoration: BoxDecoration(
          border: Border.all(color: Colors.white70, width: 2),
          borderRadius: BorderRadius.circular(ChapterRadius.md),
        ),
      ),
    ),
  );
}

class _CameraUnavailable extends StatelessWidget {
  const _CameraUnavailable({required this.permissionDenied, required this.onManual});

  final bool permissionDenied;
  final VoidCallback onManual;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ColoredBox(
      color: context.chapterColors.paper,
      child: EmptyState(
        icon: Icons.no_photography_outlined,
        title: permissionDenied ? l10n.scanPermissionTitle : l10n.scanCameraError,
        body: l10n.scanPermissionBody,
        actionLabel: l10n.scanEnterManually,
        onAction: onManual,
      ),
    );
  }
}
