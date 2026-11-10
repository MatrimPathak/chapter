/**
 * Spotify link storage against the Firestore emulator:
 *   npm run test:emulator
 */
import { deleteApp, initializeApp, type App } from "firebase-admin/app";
import { getFirestore, type Firestore } from "firebase-admin/firestore";
import { afterAll, beforeAll, beforeEach, describe, expect, it } from "vitest";

import { FirestoreSpotifyStore } from "../../src/spotify/store";

const NOW = 1_800_000_000_000;
const UID = "spotify-store-user";
const link = {
  status: "linked" as const,
  accessToken: "a",
  accessTokenExpiresAt: NOW,
  refreshToken: "r",
  displayName: null,
};

let app: App;
let db: Firestore;
let store: FirestoreSpotifyStore;

beforeAll(() => {
  app = initializeApp({ projectId: "demo-chapter" }, "spotify-store-test");
  db = getFirestore(app);
  store = new FirestoreSpotifyStore(db);
});

afterAll(() => deleteApp(app));

beforeEach(() => db.recursiveDelete(db.doc(`private_integrations/${UID}`)));

describe("FirestoreSpotifyStore", () => {
  it("accepts a login attempt once only", async () => {
    await store.saveState(UID, { nonceHash: "h", expiresAt: NOW + 1000 });
    expect(await store.consumeState(UID, "h", NOW)).toBe(true);
    expect(await store.consumeState(UID, "h", NOW)).toBe(false);
  });

  it("never accepts two simultaneous uses", async () => {
    await store.saveState(UID, { nonceHash: "h", expiresAt: NOW + 1000 });
    const results = await Promise.all([
      store.consumeState(UID, "h", NOW),
      store.consumeState(UID, "h", NOW),
    ]);
    expect(results.filter(Boolean).length).toBeLessThanOrEqual(1);
  });

  it("refuses an expired attempt and removes it", async () => {
    await store.saveState(UID, { nonceHash: "h", expiresAt: NOW });
    expect(await store.consumeState(UID, "h", NOW)).toBe(false);
    // Would pass if the expired attempt were still stored.
    expect(await store.consumeState(UID, "h", 0)).toBe(false);
  });

  it("leaves a pending attempt in place when the nonce is wrong", async () => {
    await store.saveState(UID, { nonceHash: "h", expiresAt: NOW + 1000 });
    expect(await store.consumeState(UID, "other", NOW)).toBe(false);
    expect(await store.consumeState(UID, "h", NOW)).toBe(true);
  });

  it("round-trips and deletes a link", async () => {
    await store.saveLink(UID, link);
    expect(await store.loadLink(UID)).toEqual(link);
    await store.deleteLink(UID);
    expect(await store.loadLink(UID)).toBeNull();
  });
});
