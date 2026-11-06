import { getAuth, type Auth } from "firebase-admin/auth";
import {
  getFirestore,
  Timestamp,
  type Firestore,
} from "firebase-admin/firestore";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import { onSchedule } from "firebase-functions/v2/scheduler";

import {
  RATE_LIMIT_COLLECTION,
  rateLimitDocId,
} from "../catalog/firestoreStore";
import { RATE_LIMITS } from "../catalog/service";
import { requireUid } from "../shared/auth";
import { REGION } from "../shared/region";

/** Deleting an account needs a sign-in this recent (docs/05 §1). */
export const RECENT_SIGN_IN_SECONDS = 5 * 60;

/** The client reauthenticates and retries when it sees this message. */
export const RECENT_SIGN_IN_REQUIRED = "recent-sign-in-required";

const CLOCK_SKEW_SECONDS = 60;

/** Server-only (closed by the rules' default deny). */
export const DELETED_ACCOUNTS = "deleted_accounts";

/** Longer than an ID token lives. */
const SWEEP_DELAY_MS = 65 * 60 * 1000;
const SWEEP_BATCH = 50;

export function requireRecentSignIn(
  authTimeSeconds: unknown,
  nowSeconds: number,
): void {
  const fresh =
    typeof authTimeSeconds === "number" &&
    nowSeconds - authTimeSeconds <= RECENT_SIGN_IN_SECONDS &&
    authTimeSeconds - nowSeconds <= CLOCK_SKEW_SECONDS;
  if (!fresh) {
    throw new HttpsError("failed-precondition", RECENT_SIGN_IN_REQUIRED);
  }
}

function isUserNotFound(error: unknown): boolean {
  return (error as { code?: unknown } | null)?.code === "auth/user-not-found";
}

/**
 * Removes everything the account owns. Safe to run again after any partial
 * failure: the Auth user goes last, so a failed run can be retried.
 *
 * Revoking tokens stops other devices renewing theirs. A token already issued
 * stays valid for up to an hour, so a device online in that window could still
 * write. [sweepDeletedAccounts] removes anything written back.
 */
export async function deleteUserData(
  uid: string,
  db: Firestore,
  auth: Auth,
  now: Date = new Date(),
): Promise<void> {
  // First, so a failure later still leaves the sweep scheduled.
  await db.doc(`${DELETED_ACCOUNTS}/${uid}`).set({
    sweepAfter: Timestamp.fromMillis(now.getTime() + SWEEP_DELAY_MS),
  });
  try {
    await auth.revokeRefreshTokens(uid);
  } catch (error) {
    if (!isUserNotFound(error)) throw error;
  }
  await deleteDocuments(uid, db);
  try {
    await auth.deleteUser(uid);
  } catch (error) {
    if (!isUserNotFound(error)) throw error;
  }
}

async function deleteDocuments(uid: string, db: Firestore): Promise<void> {
  await db.recursiveDelete(db.doc(`users/${uid}`));
  await db.recursiveDelete(db.doc(`private_integrations/${uid}`));
  const limits = db.batch();
  for (const action of Object.keys(RATE_LIMITS)) {
    limits.delete(
      db.collection(RATE_LIMIT_COLLECTION).doc(rateLimitDocId(uid, action)),
    );
  }
  await limits.commit();
}

/**
 * Second pass over accounts deleted over an hour ago, once every token issued
 * before deletion has expired. The record holds only the uid and goes too.
 */
export async function sweepDeleted(db: Firestore, now: Date): Promise<number> {
  const due = await db
    .collection(DELETED_ACCOUNTS)
    .where("sweepAfter", "<=", Timestamp.fromDate(now))
    .limit(SWEEP_BATCH)
    .get();
  for (const record of due.docs) {
    await deleteDocuments(record.id, db);
    await record.ref.delete();
  }
  return due.size;
}

export const sweepDeletedAccounts = onSchedule(
  {
    region: REGION,
    schedule: "every 30 minutes",
    maxInstances: 1,
    timeoutSeconds: 300,
  },
  async () => {
    await sweepDeleted(getFirestore(), new Date());
  },
);

/** Deletion is safe to repeat, so one quick retry covers a transient failure. */
export async function withOneRetry(
  action: () => Promise<void>,
  wait: () => Promise<void> = () =>
    new Promise((done) => setTimeout(done, 1000)),
): Promise<void> {
  try {
    await action();
  } catch {
    await wait();
    await action();
  }
}

export const deleteAccount = onCall(
  {
    region: REGION,
    enforceAppCheck: process.env.FUNCTIONS_EMULATOR !== "true",
    maxInstances: 10,
    memory: "256MiB",
    // A large library is many small deletes.
    timeoutSeconds: 300,
  },
  async (request) => {
    const uid = requireUid(request);
    requireRecentSignIn(request.auth?.token.auth_time, Date.now() / 1000);
    try {
      await withOneRetry(() => deleteUserData(uid, getFirestore(), getAuth()));
    } catch (error) {
      console.error("deleteAccount failed", {
        code: (error as { code?: unknown }).code,
      });
      throw new HttpsError(
        "internal",
        "Account deletion failed. It is safe to try again.",
      );
    }
    return { deleted: true };
  },
);
