/// Typed failures returned across layer boundaries.
///
/// Exceptions never cross from `data` into `domain`/`presentation`; repositories
/// catch them and map to a [Failure].
sealed class Failure {
  const Failure(this.message, {this.cause});

  /// Developer-facing description. Never shown verbatim to users.
  final String message;

  /// Original error, kept for logging and crash reports.
  final Object? cause;

  @override
  String toString() => '$runtimeType: $message';
}

final class NetworkFailure extends Failure {
  const NetworkFailure(super.message, {super.cause});
}

final class UnauthorizedFailure extends Failure {
  const UnauthorizedFailure(super.message, {super.cause});
}

/// The user deliberately aborted an interactive flow (e.g. closed sign-in).
final class CancelledFailure extends Failure {
  const CancelledFailure(super.message, {super.cause});
}

final class RateLimitedFailure extends Failure {
  const RateLimitedFailure(super.message, {super.cause});
}

final class NotFoundFailure extends Failure {
  const NotFoundFailure(super.message, {super.cause});
}

final class ValidationFailure extends Failure {
  const ValidationFailure(super.message, {super.cause});
}

final class ProviderUnavailableFailure extends Failure {
  const ProviderUnavailableFailure(super.message, {super.cause});
}

final class UnknownFailure extends Failure {
  const UnknownFailure(super.message, {super.cause});
}
