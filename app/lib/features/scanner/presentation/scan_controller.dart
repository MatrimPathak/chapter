import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/error/failure.dart';
import '../../catalog/domain/catalog_models.dart';
import '../domain/isbn.dart';

sealed class ScanState {
  const ScanState();
}

final class ScanIdle extends ScanState {
  const ScanIdle();
}

final class ScanNotABook extends ScanState {
  const ScanNotABook();
}

final class ScanLookingUp extends ScanState {
  const ScanLookingUp(this.isbn);
  final String isbn;
}

final class ScanFound extends ScanState {
  const ScanFound(this.isbn, this.lookup);
  final String isbn;
  final WorkLookup lookup;
}

final class ScanNotFound extends ScanState {
  const ScanNotFound(this.isbn);
  final String isbn;
}

final class ScanFailed extends ScanState {
  const ScanFailed(this.isbn, this.failure);
  final String isbn;
  final Failure failure;
}

/// Turns a detected barcode (or typed ISBN) into a catalog lookup.
/// Duplicate detections while a lookup is running are ignored.
class ScanController extends Notifier<ScanState> {
  @override
  ScanState build() => const ScanIdle();

  bool get isBusy => state is ScanLookingUp || state is ScanFound;

  /// From the camera: only Bookland EAN-13 (978/979) counts.
  Future<void> onBarcode(String raw) async {
    if (isBusy) return;
    final isbn = Isbn.fromBarcode(raw);
    if (isbn == null) {
      state = const ScanNotABook();
      return;
    }
    await _lookup(isbn);
  }

  /// From manual entry: ISBN-10 or ISBN-13. Returns false when invalid.
  Future<bool> onTyped(String input) async {
    final isbn = Isbn.normalize(input);
    if (isbn == null) return false;
    await _lookup(isbn);
    return true;
  }

  void reset() => state = const ScanIdle();

  Future<void> _lookup(String isbn) async {
    state = ScanLookingUp(isbn);
    final result = await ref.read(catalogRepositoryProvider).lookupIsbn(isbn);
    state = result.fold(
      (lookup) => ScanFound(isbn, lookup),
      (failure) => failure is NotFoundFailure ? ScanNotFound(isbn) : ScanFailed(isbn, failure),
    );
  }
}

final scanControllerProvider = NotifierProvider.autoDispose<ScanController, ScanState>(
  ScanController.new,
);
