/**
 * Account deletion against the Firestore and Auth emulators:
 *   npm run test:emulator
 */
import { deleteApp, initializeApp, type App } from "firebase-admin/app";
import { getAuth, type Auth } from "firebase-admin/auth";
import { getFirestore, type Firestore } from "firebase-admin/firestore";
import { afterAll, beforeAll, beforeEach, describe, expect, it } from "vitest";

import {
  DELETED_ACCOUNTS,
  deleteUserData,
  sweepDeleted,
} from "../../src/account/deleteAccount";
import { FirestoreCatalogStore } from "../../src/catalog/firestoreStore";
import { RATE_LIMITS } from "../../src/catalog/service";

const COLLECTIONS = [
  "library",
  "readThroughs",
  "userEditions",
  "progressEvents",
  "sessions",
  "sessionTombstones",
  "notes",
  "goals",
];

let app: App;
let db: Firestore;
let auth: Auth;

async function seed(uid: string): Promise<void> {
  await auth.createUser({ uid });
  await db.doc(`users/${uid}`).set({ displayName: "Reader" });
  await db.doc(`private_integrations/${uid}`).set({ spotify: "x" });
  await db.doc(`private_integrations/${uid}/tokens/a`).set({ value: "x" });
  for (const c of COLLECTIONS) {
    await db.doc(`users/${uid}/${c}/a`).set({ value: 1 });
    await db.doc(`users/${uid}/${c}/b`).set({ value: 2 });
  }
}

async function remaining(uid: string): Promise<string[]> {
  const found: string[] = [];
  for (const root of [`users/${uid}`, `private_integrations/${uid}`]) {
    const doc = db.doc(root);
    if ((await doc.get()).exists) found.push(root);
    for (const collection of await doc.listCollections()) {
      const docs = await collection.listDocuments();
      found.push(...docs.map((d) => d.path));
    }
  }
  return found;
}

beforeAll(() => {
  app = initializeApp({ projectId: "demo-chapter" }, "delete-account-test");
  db = getFirestore(app);
  auth = getAuth(app);
});

afterAll(() => deleteApp(app));

beforeEach(async () => {
  for (const uid of ["alice", "bob"]) {
    await auth.deleteUser(uid).catch(() => undefined);
    await db.recursiveDelete(db.doc(`users/${uid}`));
    await db.recursiveDelete(db.doc(`private_integrations/${uid}`));
    await db.doc(`${DELETED_ACCOUNTS}/${uid}`).delete();
  }
});

describe("deleteUserData", () => {
  it("leaves no documents and no Auth user, and leaves other users alone", async () => {
    await seed("alice");
    await seed("bob");
    expect((await remaining("alice")).length).toBeGreaterThan(
      COLLECTIONS.length,
    );

    await deleteUserData("alice", db, auth);

    expect(await remaining("alice")).toEqual([]);
    await expect(auth.getUser("alice")).rejects.toMatchObject({
      code: "auth/user-not-found",
    });

    const bob = await remaining("bob");
    expect(bob).toHaveLength(2 + 1 + COLLECTIONS.length * 2);
    expect((await auth.getUser("bob")).uid).toBe("bob");
  });

  it("sweeps what a second device writes back, once tokens have expired", async () => {
    await seed("alice");
    await seed("bob");
    const at = new Date("2026-11-05T10:00:00Z");
    await deleteUserData("alice", db, auth, at);

    // Another phone, still holding a valid token, pushes a change.
    await db.doc("users/alice/library/late").set({ value: 1 });

    await sweepDeleted(db, new Date("2026-11-05T10:30:00Z"));
    expect(await remaining("alice")).toEqual(["users/alice/library/late"]);

    expect(await sweepDeleted(db, new Date("2026-11-05T11:10:00Z"))).toBe(1);
    expect(await remaining("alice")).toEqual([]);
    expect((await db.doc(`${DELETED_ACCOUNTS}/alice`).get()).exists).toBe(
      false,
    );
    expect((await remaining("bob")).length).toBeGreaterThan(0);
    expect(await sweepDeleted(db, new Date("2026-11-06T00:00:00Z"))).toBe(0);
  });

  it("removes the per-user rate-limit documents too", async () => {
    await seed("alice");
    await seed("bob");
    const store = new FirestoreCatalogStore(db);
    for (const action of Object.keys(RATE_LIMITS)) {
      await store.consumeRate("alice", action, 10, new Date());
      await store.consumeRate("bob", action, 10, new Date());
    }
    await deleteUserData("alice", db, auth);
    const ids = (await db.collection("ops_rateLimits").listDocuments()).map(
      (d) => d.id,
    );
    expect(ids.filter((id) => id.includes("alice"))).toEqual([]);
    expect(ids.filter((id) => id.includes("bob"))).toHaveLength(
      Object.keys(RATE_LIMITS).length,
    );
  });

  it("can run again after it already finished", async () => {
    await seed("alice");
    await deleteUserData("alice", db, auth);
    await expect(deleteUserData("alice", db, auth)).resolves.toBeUndefined();
    expect(await remaining("alice")).toEqual([]);
  });

  it("finishes the job when an earlier run stopped part way", async () => {
    await seed("alice");
    await auth.deleteUser("alice"); // Auth gone, data left behind
    await deleteUserData("alice", db, auth);
    expect(await remaining("alice")).toEqual([]);

    await seed("alice");
    await db.recursiveDelete(db.doc("users/alice")); // data gone, Auth left behind
    await deleteUserData("alice", db, auth);
    expect(await remaining("alice")).toEqual([]);
    await expect(auth.getUser("alice")).rejects.toMatchObject({
      code: "auth/user-not-found",
    });
  });
});
