import '../../../core/error/result.dart';
import 'app_user.dart';

/// Authentication boundary. Implementations map provider errors to
/// `Failure`s; nothing here depends on Firebase.
abstract interface class AuthRepository {
  /// Emits the current user (or `null`) and every subsequent change.
  Stream<AppUser?> authStateChanges();

  AppUser? get currentUser;

  Future<Result<AppUser>> signInWithGoogle();

  /// iOS only (App Store guideline 4.8).
  Future<Result<AppUser>> signInWithApple();

  /// Development only: signs in against the Auth emulator with a test
  /// account. Returns a failure when emulators are not in use.
  Future<Result<AppUser>> signInWithEmulatorTestAccount();

  Future<Result<void>> signOut();

  /// Signs the current user in again, for sensitive actions. Fails with
  /// `CancelledFailure` if they back out.
  Future<Result<void>> reauthenticate();

  /// `false` only when the server says this account no longer exists. Offline
  /// and every other failure mean `true`: never wipe on a guess.
  Future<bool> accountStillExists();

  /// On Sign in with Apple accounts, signs in again and revokes Apple's tokens,
  /// as App Store guideline 5.1.1(v) expects when an account is deleted.
  /// Elsewhere it does nothing. Fails with `CancelledFailure` if they back out.
  Future<Result<void>> prepareAccountDeletion();
}
