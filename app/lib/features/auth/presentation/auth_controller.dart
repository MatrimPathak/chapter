import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/error/failure.dart';
import '../../../core/error/result.dart';
import '../domain/app_user.dart';

enum SignInMethod { google, apple, emulator }

/// Drives the sign-in screen. State is `null` when idle; while a sign-in is
/// running it holds the method in progress. The last failure is exposed
/// separately so the UI can show it once.
class SignInState {
  const SignInState({this.inProgress, this.failure});

  final SignInMethod? inProgress;
  final Failure? failure;
}

class SignInController extends Notifier<SignInState> {
  @override
  SignInState build() => const SignInState();

  Future<void> signIn(SignInMethod method) async {
    if (state.inProgress != null) return;
    state = SignInState(inProgress: method);
    final repo = ref.read(authRepositoryProvider);
    final Result<AppUser> result = await switch (method) {
      SignInMethod.google => repo.signInWithGoogle(),
      SignInMethod.apple => repo.signInWithApple(),
      SignInMethod.emulator => repo.signInWithEmulatorTestAccount(),
    };
    // On success the router guard navigates away; nothing else to do here.
    state = SignInState(failure: result.failureOrNull);
  }

  void clearFailure() => state = const SignInState();
}

final signInControllerProvider = NotifierProvider<SignInController, SignInState>(
  SignInController.new,
);

/// Signs out after trying briefly to push pending changes. Pending changes
/// are never discarded: they stay in this user's local database and sync on
/// the next sign-in (docs/05 §1.1).
Future<Result<void>> signOut(Ref ref) async {
  final engine = ref.read(syncEngineProvider);
  try {
    await engine.flush().timeout(const Duration(seconds: 5));
  } on TimeoutException {
    // Fall through: the outbox is persisted.
  }
  return ref.read(authRepositoryProvider).signOut();
}

/// Exposes [signOut] and the pending-change count to widgets.
final signOutActionProvider = Provider<SignOutAction>(SignOutAction.new);

class SignOutAction {
  SignOutAction(this._ref);

  final Ref _ref;

  Future<int> pendingChanges() => _ref.read(syncEngineProvider).pendingCount();

  Future<Result<void>> call() => signOut(_ref);
}
