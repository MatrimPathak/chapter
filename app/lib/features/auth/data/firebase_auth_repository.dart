import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../../core/error/failure.dart';
import '../../../core/error/result.dart';
import '../domain/app_user.dart';
import '../domain/auth_repository.dart';

/// Firebase Auth implementation (docs/05 §1.1).
class FirebaseAuthRepository implements AuthRepository {
  FirebaseAuthRepository({
    required FirebaseAuth auth,
    required GoogleSignIn googleSignIn,
    required bool usingEmulators,
    String? googleServerClientId,
  }) : _auth = auth,
       _google = googleSignIn,
       _usingEmulators = usingEmulators,
       _serverClientId = googleServerClientId;

  final FirebaseAuth _auth;
  final GoogleSignIn _google;
  final bool _usingEmulators;
  final String? _serverClientId;
  Future<void>? _googleInit;

  @override
  Stream<AppUser?> authStateChanges() => _auth.authStateChanges().map(_toAppUser);

  @override
  AppUser? get currentUser => _toAppUser(_auth.currentUser);

  @override
  Future<Result<AppUser>> signInWithGoogle() async {
    try {
      await (_googleInit ??= _google.initialize(serverClientId: _serverClientId));
      final account = await _google.authenticate();
      final idToken = account.authentication.idToken;
      if (idToken == null) {
        return const Result.err(UnknownFailure('Google returned no ID token'));
      }
      final credential = GoogleAuthProvider.credential(idToken: idToken);
      return _signInWith(() => _auth.signInWithCredential(credential));
    } on GoogleSignInException catch (e) {
      return Result.err(
        e.code == GoogleSignInExceptionCode.canceled
            ? CancelledFailure('Google sign-in cancelled', cause: e)
            : UnknownFailure('Google sign-in failed: ${e.code}', cause: e),
      );
    } on PlatformException catch (e) {
      return Result.err(UnknownFailure('Google sign-in failed: ${e.code}', cause: e));
    }
  }

  @override
  Future<Result<AppUser>> signInWithApple() {
    final provider = AppleAuthProvider()
      ..addScope('email')
      ..addScope('name');
    return _signInWith(() => _auth.signInWithProvider(provider));
  }

  @override
  Future<Result<AppUser>> signInWithEmulatorTestAccount() {
    if (!_usingEmulators) {
      return Future.value(
        const Result.err(UnauthorizedFailure('Test accounts only exist on the emulator')),
      );
    }
    return _signInWith(() => _auth.signInWithCredential(_emulatorCredential()));
  }

  /// The Auth emulator accepts unsigned JSON ID tokens for federated
  /// providers; this never works against real Firebase.
  static AuthCredential _emulatorCredential() => GoogleAuthProvider.credential(
    idToken: jsonEncode({
      'sub': 'chapter-test-reader',
      'email': 'reader@chapter.test',
      'email_verified': true,
      'name': 'Test Reader',
    }),
  );

  @override
  Future<bool> accountStillExists() async {
    try {
      await _auth.currentUser?.reload();
      return true;
    } on FirebaseAuthException catch (e) {
      return e.code != 'user-not-found';
    } on Exception {
      return true;
    }
  }

  @override
  Future<Result<void>> prepareAccountDeletion() async {
    final user = _auth.currentUser;
    if (_usingEmulators || user == null) return const Result.ok(null);
    if (!user.providerData.any((p) => p.providerId == 'apple.com')) {
      return const Result.ok(null);
    }
    try {
      final credential = await user.reauthenticateWithProvider(AppleAuthProvider());
      final code = credential.additionalUserInfo?.authorizationCode;
      if (code != null) await _auth.revokeTokenWithAuthorizationCode(code);
      return const Result.ok(null);
    } on FirebaseAuthException catch (e) {
      return Result.err(_mapAuthError(e));
    }
  }

  @override
  Future<Result<void>> reauthenticate() async {
    final user = _auth.currentUser;
    if (user == null) return const Result.err(UnauthorizedFailure('Not signed in'));
    try {
      if (_usingEmulators) {
        await user.reauthenticateWithCredential(_emulatorCredential());
      } else if (user.providerData.any((p) => p.providerId == 'apple.com')) {
        await user.reauthenticateWithProvider(AppleAuthProvider());
      } else {
        await (_googleInit ??= _google.initialize(serverClientId: _serverClientId));
        final account = await _google.authenticate();
        final idToken = account.authentication.idToken;
        if (idToken == null) {
          return const Result.err(UnknownFailure('Google returned no ID token'));
        }
        await user.reauthenticateWithCredential(GoogleAuthProvider.credential(idToken: idToken));
      }
      // The next callable must carry the new sign-in time.
      await user.getIdToken(true);
      return const Result.ok(null);
    } on GoogleSignInException catch (e) {
      return Result.err(
        e.code == GoogleSignInExceptionCode.canceled
            ? CancelledFailure('Google sign-in cancelled', cause: e)
            : UnknownFailure('Google sign-in failed: ${e.code}', cause: e),
      );
    } on FirebaseAuthException catch (e) {
      return Result.err(_mapAuthError(e));
    } on PlatformException catch (e) {
      return Result.err(UnknownFailure('Sign-in failed: ${e.code}', cause: e));
    }
  }

  @override
  Future<Result<void>> signOut() async {
    try {
      await _auth.signOut();
      if (_googleInit != null) await _google.signOut();
      return const Result.ok(null);
    } on Exception catch (e) {
      return Result.err(UnknownFailure('Sign-out failed', cause: e));
    }
  }

  Future<Result<AppUser>> _signInWith(Future<UserCredential> Function() action) async {
    try {
      final credential = await action();
      final user = _toAppUser(credential.user);
      if (user == null) {
        return const Result.err(UnknownFailure('Sign-in returned no user'));
      }
      return Result.ok(user);
    } on FirebaseAuthException catch (e) {
      return Result.err(_mapAuthError(e));
    }
  }

  static Failure _mapAuthError(FirebaseAuthException e) => switch (e.code) {
    'canceled' ||
    'web-context-canceled' ||
    'popup-closed-by-user' => CancelledFailure('Sign-in cancelled', cause: e),
    'network-request-failed' => NetworkFailure('Network error during sign-in', cause: e),
    'too-many-requests' => RateLimitedFailure('Too many sign-in attempts', cause: e),
    'user-disabled' ||
    'invalid-credential' => UnauthorizedFailure('Sign-in rejected: ${e.code}', cause: e),
    _ => UnknownFailure('Sign-in failed: ${e.code}', cause: e),
  };

  static AppUser? _toAppUser(User? user) => user == null
      ? null
      : AppUser(
          uid: user.uid,
          displayName: user.displayName,
          email: user.email,
          photoUrl: user.photoURL,
        );
}
