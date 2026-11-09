/**
 * FirestoreCatalogStore against the Firestore emulator:
 *   firebase emulators:exec --only firestore --project demo-chapter "npm --prefix functions run test:integration"
 */
import { deleteApp, initializeApp, type App } from "firebase-admin/app";
import { getFirestore, type Firestore } from "firebase-admin/firestore";
import { afterAll, beforeAll, beforeEach, describe, expect, it } from "vitest";

import { FirestoreCatalogStore } from "../../src/catalog/firestoreStore";
import type { CatalogWork } from "../../src/catalog/types";

let app: App;
let db: Firestore;
let store: FirestoreCatalogStore;

const work = (id: string, isbn: string, editionId: string): CatalogWork => ({
  id,
  title: "The Deal",
  subtitle: null,
  authors: [{ id: "a1", name: "Elle Kennedy" }],
  description: null,
  firstPublishedDate: "2015",
  language: null,
  genres: [],
  series: [],
  coverUrl: null,
  pageCount: 374,
  defaultEditionId: editionId,
  editions: [
    {
      id: editionId,
      workId: id,
      format: "paperback",
      isbn10: null,
      isbn13: isbn,
      publisher: null,
      publishedDate: null,
      pageCount: 374,
      audioDurationSec: null,
      language: null,
      coverUrl: null,
      providerIds: { openLibrary: `OL-${editionId}` },
    },
  ],
  providerIds: { openLibrary: `OLW-${id}` },
  provenance: {},
  refreshedAt: "2026-11-04T00:00:00.000Z",
});

beforeAll(() => {
  if (!process.env.FIRESTORE_EMULATOR_HOST)
    throw new Error("Run under the Firestore emulator");
  app = initializeApp({ projectId: "demo-chapter" }, "integration");
  db = getFirestore(app);
  store = new FirestoreCatalogStore(db);
});

beforeEach(async () => {
  await fetch(
    `http://${process.env.FIRESTORE_EMULATOR_HOST}/emulator/v1/projects/demo-chapter/databases/(default)/documents`,
    {
      method: "DELETE",
    },
  );
});

afterAll(async () => {
  await deleteApp(app);
});

describe("FirestoreCatalogStore", () => {
  it("touches refreshedAt only when the work is unchanged", async () => {
    const saved = work("w1", "9780349440842", "e1");
    await store.saveWork(saved, { authors: [], series: [] });
    const later = "2026-11-05T00:00:00.000Z";

    await store.touchWorkIfUnchanged("w1", "2020-01-01T00:00:00.000Z", later);
    expect((await store.getWork("w1"))?.refreshedAt).toBe(saved.refreshedAt);

    await store.touchWorkIfUnchanged("w1", saved.refreshedAt, later);
    expect(await store.getWork("w1")).toEqual({ ...saved, refreshedAt: later });

    await expect(
      store.touchWorkIfUnchanged("missing", saved.refreshedAt, later),
    ).resolves.toBeUndefined();
  });

  it("saves a work with indexes and stubs in one transaction", async () => {
    await store.saveWork(work("w1", "9780349440842", "e1"), {
      authors: [
        {
          id: "a1",
          refKey: "author:openLibrary:OL6761347A",
          name: "Elle Kennedy",
        },
      ],
      series: [],
    });
    expect((await store.getWork("w1"))?.title).toBe("The Deal");
    expect(await store.findByIsbn(["9780349440842"])).toEqual({
      workId: "w1",
      editionId: "e1",
    });
    const ids = await store.findIdsByRefKeys([
      "openLibrary:OLW-w1",
      "edition:openLibrary:OL-e1",
      "author:openLibrary:OL6761347A",
      "nope:x",
    ]);
    expect(Object.fromEntries(ids)).toEqual({
      "openLibrary:OLW-w1": "w1",
      "edition:openLibrary:OL-e1": "e1",
      "author:openLibrary:OL6761347A": "a1",
    });
    expect((await store.getAuthor("a1"))?.name).toBe("Elle Kennedy");
  });

  it("never re-points an ISBN already owned by another work", async () => {
    await store.saveWork(work("w1", "9780349440842", "e1"), {
      authors: [],
      series: [],
    });
    await store.saveWork(work("w2", "9780349440842", "e2"), {
      authors: [],
      series: [],
    });
    expect((await store.findByIsbn(["9780349440842"]))?.workId).toBe("w1");
  });

  it("expires cached values", async () => {
    const now = new Date("2026-11-04T10:00:00Z");
    await store.putCached("k", { a: 1 }, new Date(now.getTime() + 1000));
    expect(await store.getCached("k", now)).toEqual({ a: 1 });
    expect(
      await store.getCached("k", new Date(now.getTime() + 2000)),
    ).toBeNull();
  });

  it("rate-limits with a transactional token bucket", async () => {
    const t = new Date("2026-11-04T10:00:00Z");
    const results = [];
    for (let i = 0; i < 4; i++)
      results.push(await store.consumeRate("u1", "search", 3, t));
    expect(results).toEqual([true, true, true, false]);
    expect(
      await store.consumeRate(
        "u1",
        "search",
        3,
        new Date(t.getTime() + 20_000),
      ),
    ).toBe(true);
  });
});
