import 'package:uuid/uuid.dart';

/// Generates client-side identifiers. UUIDv7 is time-ordered, which keeps
/// append-only collections (sessions, progress events) naturally sorted and
/// allows creating records offline without server round-trips.
abstract interface class IdGenerator {
  String newId();
}

final class UuidV7Generator implements IdGenerator {
  const UuidV7Generator();

  static const _uuid = Uuid();

  @override
  String newId() => _uuid.v7();
}
