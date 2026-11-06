import { HttpsError } from "firebase-functions/v2/https";

/** Minimal shape of a callable request we depend on. */
export interface AuthContext {
  auth?: { uid: string } | null;
}

/**
 * Returns the caller's uid or throws `unauthenticated`.
 * Every callable (catalog in Phase 3, account deletion in Phase 8) must call
 * this first; App Check enforcement is configured on the callable itself.
 */
export function requireUid(request: AuthContext): string {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Sign in required.");
  }
  return uid;
}
