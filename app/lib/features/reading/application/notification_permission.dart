/// Requests the notification permission at most once.
///
/// Android shows its prompt again after a single decline, so asking at every
/// session start nags a reader who already said no. They can still turn
/// notifications on in the system settings, which [isAllowed] picks up.
Future<bool> askForPermissionOnce({
  required Future<bool> Function() isAllowed,
  required Future<bool> Function() ask,
  required Future<bool> Function() wasAsked,
  required Future<void> Function() markAsked,
}) async {
  if (await isAllowed()) return true;
  if (await wasAsked()) return false;
  final allowed = await ask();
  await markAsked();
  return allowed;
}
