import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../domain/catalog_models.dart';

/// Route-friendly key for a work: `id:<uuid>` or `ref:<provider>:<externalId>`.
/// (Strings have value equality, so they work as provider family keys.)
WorkTarget workTargetFromKey(String key) {
  final parts = key.split(':');
  if (parts.first == 'ref' && parts.length >= 3) {
    return WorkByRef(
      ProviderRef(
        provider: CatalogProvider.values.byName(parts[1]),
        externalId: parts.sublist(2).join(':'),
      ),
    );
  }
  return WorkById(parts.length > 1 ? parts.sublist(1).join(':') : key);
}

String workKeyOf(WorkSummary summary) => summary.id != null
    ? 'id:${summary.id}'
    : 'ref:${summary.ref.provider.name}:${summary.ref.externalId}';

final workDetailProvider = FutureProvider.autoDispose.family<CatalogWork, String>((ref, key) async {
  final result = await ref.watch(catalogRepositoryProvider).getWork(workTargetFromKey(key));
  return result.fold((work) => work, (failure) => throw failure);
});

/// Author key: `id:<uuid>` or `ref:<provider>:<externalId>`.
final authorDetailProvider = FutureProvider.autoDispose.family<CatalogAuthor, String>((
  ref,
  key,
) async {
  final parts = key.split(':');
  final repo = ref.watch(catalogRepositoryProvider);
  final result = parts.first == 'ref' && parts.length >= 3
      ? await repo.getAuthor(
          ref: ProviderRef(
            provider: CatalogProvider.values.byName(parts[1]),
            externalId: parts.sublist(2).join(':'),
          ),
        )
      : await repo.getAuthor(authorId: parts.length > 1 ? parts.sublist(1).join(':') : key);
  return result.fold((author) => author, (failure) => throw failure);
});

final seriesDetailProvider = FutureProvider.autoDispose.family<CatalogSeries, String>((
  ref,
  seriesId,
) async {
  final result = await ref.watch(catalogRepositoryProvider).getSeries(seriesId);
  return result.fold((series) => series, (failure) => throw failure);
});
