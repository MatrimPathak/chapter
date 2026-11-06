import 'package:cloud_functions/cloud_functions.dart';

/// Thin seam over the catalog callables so the repository can be tested
/// without Firebase.
abstract interface class CatalogRemote {
  /// Calls the callable [name] and returns its JSON result.
  /// Throws [CatalogRemoteException] on any failure.
  Future<Map<String, dynamic>> call(String name, Map<String, Object?> data);
}

/// Error from a callable, with the Cloud Functions error code
/// (`not-found`, `unavailable`, `invalid-argument`, ...).
final class CatalogRemoteException implements Exception {
  const CatalogRemoteException(this.code, [this.message]);
  final String code;
  final String? message;

  @override
  String toString() => 'CatalogRemoteException($code, $message)';
}

class FunctionsCatalogRemote implements CatalogRemote {
  FunctionsCatalogRemote(this._functions);

  final FirebaseFunctions _functions;

  static const _timeout = Duration(seconds: 20);

  @override
  Future<Map<String, dynamic>> call(String name, Map<String, Object?> data) async {
    try {
      final result = await _functions
          .httpsCallable(name, options: HttpsCallableOptions(timeout: _timeout))
          .call<Object?>(data);
      final json = _deepJson(result.data);
      if (json is! Map<String, dynamic>) {
        throw const CatalogRemoteException('internal', 'Unexpected response shape');
      }
      return json;
    } on FirebaseFunctionsException catch (e) {
      throw CatalogRemoteException(e.code, e.message);
    }
  }

  /// Platform channels return `Map<Object?, Object?>`; convert recursively.
  static Object? _deepJson(Object? value) => switch (value) {
    final Map<Object?, Object?> map => {
      for (final e in map.entries) e.key.toString(): _deepJson(e.value),
    },
    final List<Object?> list => [for (final v in list) _deepJson(v)],
    _ => value,
  };
}
