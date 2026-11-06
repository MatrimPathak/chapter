import 'package:freezed_annotation/freezed_annotation.dart';

part 'app_user.freezed.dart';

/// The signed-in user as seen by the rest of the app.
@freezed
abstract class AppUser with _$AppUser {
  const factory AppUser({
    required String uid,
    String? displayName,
    String? email,
    String? photoUrl,
  }) = _AppUser;

  const AppUser._();

  /// First name for greetings, if known.
  String? get firstName {
    final name = displayName?.trim();
    if (name == null || name.isEmpty) return null;
    return name.split(RegExp(r'\s+')).first;
  }
}
