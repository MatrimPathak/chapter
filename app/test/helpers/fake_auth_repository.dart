import 'dart:async';

import 'package:chapter/core/error/failure.dart';
import 'package:chapter/core/error/result.dart';
import 'package:chapter/features/auth/domain/app_user.dart';
import 'package:chapter/features/auth/domain/auth_repository.dart';

class FakeAuthRepository implements AuthRepository {
  FakeAuthRepository({AppUser? initialUser}) : _user = initialUser;

  static const testUser = AppUser(uid: 'u1', displayName: 'Ada Reader', email: 'ada@chapter.test');

  AppUser? _user;
  final _controller = StreamController<AppUser?>.broadcast();

  /// Result returned by the next sign-in call; defaults to success.
  Failure? nextFailure;
  int signOutCalls = 0;
  int reauthCalls = 0;
  bool accountExists = true;
  Failure? nextPrepareFailure;
  int prepareCalls = 0;

  @override
  Future<bool> accountStillExists() async {
    if (!accountExists && signOutWhenChecked) await signOut();
    return accountExists;
  }

  /// Firebase's SDK signs out by itself when told the account is gone.
  bool signOutWhenChecked = false;

  @override
  Future<Result<void>> prepareAccountDeletion() async {
    prepareCalls++;
    final f = nextPrepareFailure;
    return f == null ? const Result.ok(null) : Result.err(f);
  }

  Failure? nextReauthFailure;

  @override
  Future<Result<void>> reauthenticate() async {
    reauthCalls++;
    final f = nextReauthFailure;
    return f == null ? const Result.ok(null) : Result.err(f);
  }

  @override
  AppUser? get currentUser => _user;

  @override
  Stream<AppUser?> authStateChanges() => Stream<AppUser?>.multi((sink) {
    sink.add(_user);
    final sub = _controller.stream.listen(sink.add);
    sink.onCancel = sub.cancel;
  });

  Future<Result<AppUser>> _signIn() async {
    final failure = nextFailure;
    if (failure != null) {
      nextFailure = null;
      return Result.err(failure);
    }
    _user = testUser;
    _controller.add(_user);
    return const Result.ok(testUser);
  }

  @override
  Future<Result<AppUser>> signInWithGoogle() => _signIn();

  @override
  Future<Result<AppUser>> signInWithApple() => _signIn();

  @override
  Future<Result<AppUser>> signInWithEmulatorTestAccount() => _signIn();

  @override
  Future<Result<void>> signOut() async {
    signOutCalls++;
    _user = null;
    _controller.add(null);
    return const Result.ok(null);
  }

  Future<void> dispose() => _controller.close();
}
