/**
 * Firestore security rules tests. Run against the emulator:
 *   npm run test:rules:emulator      (from functions/)
 */
import { readFileSync } from "node:fs";
import { resolve } from "node:path";

import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
  type RulesTestEnvironment,
} from "@firebase/rules-unit-testing";
import {
  doc,
  getDoc,
  serverTimestamp,
  setDoc,
  deleteDoc,
  collection,
  addDoc,
  getDocs,
} from "firebase/firestore";
import { afterAll, beforeAll, beforeEach, describe, it } from "vitest";

let env: RulesTestEnvironment;

const clock = (n: number) => `${String(n).padStart(15, "0")}:00000:node`;

function profile(fields: Record<string, unknown>) {
  return {
    ...fields,
    fieldClock: Object.fromEntries(
      Object.keys(fields).map((k) => [k, clock(1)]),
    ),
    updatedAt: serverTimestamp(),
  };
}

beforeAll(async () => {
  env = await initializeTestEnvironment({
    projectId: "demo-chapter",
    firestore: {
      rules: readFileSync(
        resolve(__dirname, "../../../firebase/firestore.rules"),
        "utf8",
      ),
    },
  });
});

beforeEach(async () => {
  await env.clearFirestore();
});

afterAll(async () => {
  await env.cleanup();
});

describe("users/{uid}", () => {
  it("owner can create and read a valid profile", async () => {
    const db = env.authenticatedContext("alice").firestore();
    await assertSucceeds(
      setDoc(
        doc(db, "users/alice"),
        profile({ theme: "dark", analyticsConsent: false }),
      ),
    );
    await assertSucceeds(getDoc(doc(db, "users/alice")));
  });

  it("merging a single field keeps the document valid", async () => {
    const db = env.authenticatedContext("alice").firestore();
    await assertSucceeds(
      setDoc(doc(db, "users/alice"), profile({ theme: "dark" })),
    );
    await assertSucceeds(
      setDoc(
        doc(db, "users/alice"),
        {
          crashConsent: false,
          fieldClock: { theme: clock(1), crashConsent: clock(2) },
          updatedAt: serverTimestamp(),
        },
        { merge: true },
      ),
    );
  });

  it("other users cannot read or write", async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), "users/alice"), { theme: "dark" });
    });
    const bob = env.authenticatedContext("bob").firestore();
    await assertFails(getDoc(doc(bob, "users/alice")));
    await assertFails(
      setDoc(doc(bob, "users/alice"), profile({ theme: "light" })),
    );
  });

  it("signed-out clients are denied", async () => {
    const anon = env.unauthenticatedContext().firestore();
    await assertFails(getDoc(doc(anon, "users/alice")));
    await assertFails(
      setDoc(doc(anon, "users/alice"), profile({ theme: "light" })),
    );
  });

  it("rejects unknown fields", async () => {
    const db = env.authenticatedContext("alice").firestore();
    await assertFails(
      setDoc(doc(db, "users/alice"), profile({ isAdmin: true })),
    );
  });

  it("rejects wrong types and out-of-range values", async () => {
    const db = env.authenticatedContext("alice").firestore();
    await assertFails(
      setDoc(doc(db, "users/alice"), profile({ theme: "neon" })),
    );
    await assertFails(
      setDoc(doc(db, "users/alice"), profile({ analyticsConsent: "yes" })),
    );
    await assertFails(
      setDoc(doc(db, "users/alice"), profile({ defaultTimerMin: 0 })),
    );
    await assertFails(
      setDoc(doc(db, "users/alice"), profile({ weekStartsOn: 9 })),
    );
    await assertFails(
      setDoc(doc(db, "users/alice"), profile({ displayName: "x".repeat(201) })),
    );
  });

  it("requires a server timestamp and a field clock", async () => {
    const db = env.authenticatedContext("alice").firestore();
    await assertFails(
      setDoc(doc(db, "users/alice"), {
        theme: "dark",
        fieldClock: { theme: clock(1) },
      }),
    );
    await assertFails(
      setDoc(doc(db, "users/alice"), {
        theme: "dark",
        updatedAt: serverTimestamp(),
      }),
    );
    await assertFails(
      setDoc(doc(db, "users/alice"), {
        theme: "dark",
        fieldClock: { theme: clock(1), notAField: clock(1) },
        updatedAt: serverTimestamp(),
      }),
    );
  });

  it("clients cannot delete their user document", async () => {
    const db = env.authenticatedContext("alice").firestore();
    await assertSucceeds(
      setDoc(doc(db, "users/alice"), profile({ theme: "dark" })),
    );
    await assertFails(deleteDoc(doc(db, "users/alice")));
  });

  it("sub-collections are denied until their phase adds rules", async () => {
    const db = env.authenticatedContext("alice").firestore();
    await assertFails(
      addDoc(collection(db, "users/alice/library"), { status: "reading" }),
    );
    await assertFails(getDoc(doc(db, "users/alice/shelves/n1")));
  });
});

describe("library, read-throughs, editions (per-field LWW)", () => {
  const lww = (fields: Record<string, unknown>) => ({
    ...fields,
    fieldClock: Object.fromEntries(
      Object.keys(fields).map((k) => [k, clock(1)]),
    ),
    updatedAt: serverTimestamp(),
  });

  it("owner can add a library entry with a book summary", async () => {
    const db = env.authenticatedContext("alice").firestore();
    await assertSucceeds(
      setDoc(
        doc(db, "users/alice/library/w1"),
        lww({
          status: "wantToRead",
          isWishlist: false,
          title: "The Deal",
          authorNames: ["Elle Kennedy"],
          pageCount: 374,
        }),
      ),
    );
  });

  it("accepts the exact payload the app writes on add (nulls and empty lists)", async () => {
    const db = env.authenticatedContext("alice").firestore();
    await assertSucceeds(
      setDoc(
        doc(db, "users/alice/library/w1"),
        lww({
          title: "The Deal",
          subtitle: null,
          authorNames: ["Elle Kennedy"],
          coverUrl: null,
          pageCount: 374,
          seriesId: null,
          seriesName: null,
          seriesPosition: null,
          genres: [],
          firstPublishedYear: 2015,
          status: "reading",
          addedAt: "2026-11-04T09:00:00.000Z",
          statusChangedAt: "2026-11-04T09:00:00.000Z",
          isWishlist: false,
          removed: false,
          activeEditionId: "e1",
          activeReadThroughId: "019a4f2e-0000-7000-8000-000000000001",
        }),
      ),
    );
    await assertSucceeds(
      setDoc(
        doc(db, "users/alice/userEditions/e1"),
        lww({
          workId: "w1",
          format: "paperback",
          owned: true,
          isbn13: "9780349440842",
          publisher: null,
          coverUrl: null,
          pageCount: 374,
          audioDurationSec: null,
        }),
      ),
    );
  });

  it("rejects unknown statuses, fields and missing clocks", async () => {
    const db = env.authenticatedContext("alice").firestore();
    await assertFails(
      setDoc(doc(db, "users/alice/library/w1"), lww({ status: "burned" })),
    );
    await assertFails(
      setDoc(doc(db, "users/alice/library/w1"), lww({ isAdmin: true })),
    );
    await assertFails(
      setDoc(doc(db, "users/alice/library/w1"), {
        status: "reading",
        updatedAt: serverTimestamp(),
      }),
    );
  });

  it("other users cannot read or write a library", async () => {
    const owner = env.authenticatedContext("alice").firestore();
    await assertSucceeds(
      setDoc(doc(owner, "users/alice/library/w1"), lww({ status: "reading" })),
    );
    const bob = env.authenticatedContext("bob").firestore();
    await assertFails(getDoc(doc(bob, "users/alice/library/w1")));
    await assertFails(
      setDoc(doc(bob, "users/alice/library/w1"), lww({ status: "read" })),
    );
  });

  it("library entries are removed with a tombstone, never deleted", async () => {
    const db = env.authenticatedContext("alice").firestore();
    await assertSucceeds(
      setDoc(doc(db, "users/alice/library/w1"), lww({ status: "reading" })),
    );
    await assertFails(deleteDoc(doc(db, "users/alice/library/w1")));
  });

  it("validates read-throughs and user editions", async () => {
    const db = env.authenticatedContext("alice").firestore();
    await assertSucceeds(
      setDoc(
        doc(db, "users/alice/readThroughs/r1"),
        lww({
          workId: "w1",
          ordinal: 1,
          startedAt: "2026-11-04",
          outcome: "inProgress",
        }),
      ),
    );
    await assertFails(
      setDoc(
        doc(db, "users/alice/readThroughs/r1"),
        lww({ outcome: "paused" }),
      ),
    );
    await assertSucceeds(
      setDoc(
        doc(db, "users/alice/userEditions/e1"),
        lww({
          workId: "w1",
          owned: true,
          format: "paperback",
          pageCountOverride: 380,
        }),
      ),
    );
    await assertFails(
      setDoc(
        doc(db, "users/alice/userEditions/e1"),
        lww({ pageCountOverride: -5 }),
      ),
    );
  });
});

describe("progressEvents (append-only)", () => {
  const event = {
    workId: "w1",
    readThroughId: "r1",
    editionId: "e1",
    position: { type: "page", page: 187 },
    fraction: 0.4675,
    isApproximate: false,
    source: "manual",
    recordedAt: "2026-11-04T10:00:00.000Z",
  };

  it("owner can create a valid event", async () => {
    const db = env.authenticatedContext("alice").firestore();
    await assertSucceeds(
      setDoc(doc(db, "users/alice/progressEvents/p1"), {
        ...event,
        updatedAt: serverTimestamp(),
      }),
    );
  });

  it("events can never be changed or deleted", async () => {
    const db = env.authenticatedContext("alice").firestore();
    await assertSucceeds(
      setDoc(doc(db, "users/alice/progressEvents/p1"), {
        ...event,
        updatedAt: serverTimestamp(),
      }),
    );
    await assertFails(
      setDoc(doc(db, "users/alice/progressEvents/p1"), {
        ...event,
        fraction: 0.9,
        updatedAt: serverTimestamp(),
      }),
    );
    await assertFails(deleteDoc(doc(db, "users/alice/progressEvents/p1")));
  });

  it("rejects out-of-range fractions, unknown sources and other users", async () => {
    const db = env.authenticatedContext("alice").firestore();
    await assertFails(
      setDoc(doc(db, "users/alice/progressEvents/p2"), {
        ...event,
        fraction: 1.5,
        updatedAt: serverTimestamp(),
      }),
    );
    await assertFails(
      setDoc(doc(db, "users/alice/progressEvents/p3"), {
        ...event,
        source: "scraped",
        updatedAt: serverTimestamp(),
      }),
    );
    const bob = env.authenticatedContext("bob").firestore();
    await assertFails(
      setDoc(doc(bob, "users/alice/progressEvents/p4"), {
        ...event,
        updatedAt: serverTimestamp(),
      }),
    );
  });
});

describe("sessions (append-only)", () => {
  const session = {
    workId: "w1",
    readThroughId: "r1",
    editionId: "e1",
    startedAt: "2026-11-04T20:00:00.000Z",
    endedAt: "2026-11-04T20:30:00.000Z",
    plannedDurationSec: 1800,
    activeDurationSec: 1500,
    pauses: [
      { start: "2026-11-04T20:10:00.000Z", end: "2026-11-04T20:15:00.000Z" },
    ],
    startPosition: { type: "page", page: 100 },
    endPosition: { type: "page", page: 140 },
    startFraction: 0.25,
    endFraction: 0.35,
    pagesRead: 40,
    localDate: "2026-11-04",
    tzOffsetMin: 60,
    completion: "completed",
    clockAdjusted: false,
  };

  it("owner can create a session exactly as the app writes it", async () => {
    const db = env.authenticatedContext("alice").firestore();
    await assertSucceeds(
      setDoc(doc(db, "users/alice/sessions/s1"), {
        ...session,
        updatedAt: serverTimestamp(),
      }),
    );
  });

  it("sessions can never be changed or deleted, and others cannot read them", async () => {
    const db = env.authenticatedContext("alice").firestore();
    await assertSucceeds(
      setDoc(doc(db, "users/alice/sessions/s1"), {
        ...session,
        updatedAt: serverTimestamp(),
      }),
    );
    await assertFails(
      setDoc(doc(db, "users/alice/sessions/s1"), {
        ...session,
        activeDurationSec: 9,
        updatedAt: serverTimestamp(),
      }),
    );
    await assertFails(deleteDoc(doc(db, "users/alice/sessions/s1")));
    const bob = env.authenticatedContext("bob").firestore();
    await assertFails(getDoc(doc(bob, "users/alice/sessions/s1")));
    await assertFails(
      setDoc(doc(bob, "users/alice/sessions/s2"), {
        ...session,
        updatedAt: serverTimestamp(),
      }),
    );
  });

  it("rejects invalid durations, dates, completions and unknown fields", async () => {
    const db = env.authenticatedContext("alice").firestore();
    let n = 0;
    const bad = (patch: Record<string, unknown>) =>
      setDoc(doc(db, `users/alice/sessions/bad${n++}`), {
        ...session,
        ...patch,
        updatedAt: serverTimestamp(),
      });
    await assertFails(bad({ activeDurationSec: -1 }));
    await assertFails(bad({ activeDurationSec: 90000 }));
    await assertFails(bad({ localDate: "04/11/2026" }));
    await assertFails(bad({ completion: "abandoned" }));
    await assertFails(bad({ endFraction: 1.2 }));
    await assertFails(bad({ notes: "secret" }));
  });
});

describe("read-through finish dates", () => {
  it("can be set, cleared and missing", async () => {
    const db = env.authenticatedContext("alice").firestore();
    const lww = (fields: Record<string, unknown>) => ({
      ...fields,
      fieldClock: Object.fromEntries(
        Object.keys(fields).map((k) => [k, clock(1)]),
      ),
      updatedAt: serverTimestamp(),
    });
    const base = { workId: "w1", ordinal: 1, outcome: "finished" };
    await assertSucceeds(
      setDoc(
        doc(db, "users/alice/readThroughs/r1"),
        lww({ ...base, finishedAt: "2019-03-04T12:00:00.000Z" }),
      ),
    );
    await assertSucceeds(
      setDoc(
        doc(db, "users/alice/readThroughs/r1"),
        lww({ ...base, finishedAt: null }),
      ),
    );
    await assertSucceeds(
      setDoc(doc(db, "users/alice/readThroughs/r2"), lww(base)),
    );
    await assertFails(
      setDoc(
        doc(db, "users/alice/readThroughs/r3"),
        lww({ ...base, finishedAt: 5 }),
      ),
    );
  });
});

describe("ratings and reviews", () => {
  const lww = (fields: Record<string, unknown>) => ({
    ...fields,
    fieldClock: Object.fromEntries(
      Object.keys(fields).map((k) => [k, clock(1)]),
    ),
    updatedAt: serverTimestamp(),
  });

  it("accepts half stars, clearing, and a review within the limit", async () => {
    const db = env.authenticatedContext("alice").firestore();
    for (const rating of [0.5, 1, 3.5, 5, null]) {
      await assertSucceeds(
        setDoc(doc(db, "users/alice/library/w1"), lww({ rating })),
      );
    }
    await assertSucceeds(
      setDoc(
        doc(db, "users/alice/library/w1"),
        lww({ review: "x".repeat(20000) }),
      ),
    );
  });

  it("rejects anything else", async () => {
    const db = env.authenticatedContext("alice").firestore();
    for (const rating of [0, 0.25, 5.5, 3.3, -1, "5"]) {
      await assertFails(
        setDoc(doc(db, "users/alice/library/w1"), lww({ rating })),
      );
    }
    await assertFails(
      setDoc(
        doc(db, "users/alice/library/w1"),
        lww({ review: "x".repeat(20001) }),
      ),
    );
  });
});

describe("notes", () => {
  const lww = (fields: Record<string, unknown>) => ({
    ...fields,
    fieldClock: Object.fromEntries(
      Object.keys(fields).map((k) => [k, clock(1)]),
    ),
    updatedAt: serverTimestamp(),
  });
  const note = {
    workId: "w1",
    kind: "quote",
    text: "A line I liked",
    page: 42,
    createdAt: "2026-11-05T10:00:00.000Z",
    textHistory: [clock(1)],
  };

  it("owner can write notes, conflict copies and tombstones", async () => {
    const db = env.authenticatedContext("alice").firestore();
    await assertSucceeds(setDoc(doc(db, "users/alice/notes/n1"), lww(note)));
    await assertSucceeds(
      setDoc(doc(db, "users/alice/notes/n1"), lww({ ...note, page: null })),
    );
    await assertSucceeds(
      setDoc(
        doc(db, "users/alice/notes/n1_c_000_00000_node"),
        lww({ ...note, conflictOf: "n1" }),
      ),
    );
    await assertSucceeds(
      setDoc(doc(db, "users/alice/notes/n1"), lww({ ...note, deleted: true })),
    );
    await assertFails(deleteDoc(doc(db, "users/alice/notes/n1")));
  });

  it("rejects bad notes and other users", async () => {
    const db = env.authenticatedContext("alice").firestore();
    await assertFails(
      setDoc(doc(db, "users/alice/notes/n"), lww({ ...note, kind: "rant" })),
    );
    await assertFails(
      setDoc(
        doc(db, "users/alice/notes/n"),
        lww({ ...note, text: "x".repeat(10001) }),
      ),
    );
    await assertFails(
      setDoc(doc(db, "users/alice/notes/n"), lww({ ...note, page: -1 })),
    );
    await assertFails(
      setDoc(doc(db, "users/alice/notes/n"), lww({ ...note, secret: true })),
    );
    await assertFails(
      setDoc(doc(db, "users/alice/notes/n"), {
        ...note,
        updatedAt: serverTimestamp(),
      }),
    );
    const bob = env.authenticatedContext("bob").firestore();
    await assertFails(setDoc(doc(bob, "users/alice/notes/n"), lww(note)));
    await assertFails(getDoc(doc(bob, "users/alice/notes/n1")));
  });
});

describe("imported notes and reads", () => {
  const lww = (fields: Record<string, unknown>) => ({
    ...fields,
    fieldClock: Object.fromEntries(
      Object.keys(fields).map((k) => [k, clock(1)]),
    ),
    updatedAt: serverTimestamp(),
  });

  it("accepts a clipping with a Kindle location, and rejects a bad one", async () => {
    const db = env.authenticatedContext("alice").firestore();
    const note = {
      workId: "w1",
      kind: "quote",
      text: "A line",
      page: null,
      location: 678,
      createdAt: "2026-11-05T10:00:00.000Z",
    };
    await assertSucceeds(
      setDoc(doc(db, "users/alice/notes/kc_0123456789abcdef"), lww(note)),
    );
    await assertFails(
      setDoc(doc(db, "users/alice/notes/kc_x"), lww({ ...note, location: -1 })),
    );
    await assertFails(
      setDoc(
        doc(db, "users/alice/notes/kc_y"),
        lww({ ...note, location: "678" }),
      ),
    );
  });

  it("accepts an imported read and its progress event", async () => {
    const db = env.authenticatedContext("alice").firestore();
    await assertSucceeds(
      setDoc(
        doc(db, "users/alice/readThroughs/imp_goodreads_0123456789abcdef_0"),
        lww({
          workId: "w1",
          ordinal: 1,
          finishedAt: "2021-03-04T06:30:00.000Z",
          outcome: "finished",
        }),
      ),
    );
    await assertSucceeds(
      setDoc(
        doc(db, "users/alice/progressEvents/imp_goodreads_0123456789abcdef_e0"),
        {
          workId: "w1",
          readThroughId: "imp_goodreads_0123456789abcdef_0",
          position: { type: "finished" },
          fraction: 1,
          isApproximate: false,
          source: "import",
          recordedAt: "2021-03-04T06:30:00.000Z",
          updatedAt: serverTimestamp(),
        },
      ),
    );
  });
});

describe("goals", () => {
  const lww = (fields: Record<string, unknown>) => ({
    ...fields,
    fieldClock: Object.fromEntries(
      Object.keys(fields).map((k) => [k, clock(1)]),
    ),
    updatedAt: serverTimestamp(),
  });
  const goal = {
    metric: "books",
    period: "year",
    start: "2026-01-01",
    end: "2026-12-31",
    target: 24,
    createdAt: "2026-11-05T10:00:00.000Z",
  };

  it("owner can write goals and tombstones, never hard-delete", async () => {
    const db = env.authenticatedContext("alice").firestore();
    await assertSucceeds(setDoc(doc(db, "users/alice/goals/g1"), lww(goal)));
    await assertSucceeds(
      setDoc(doc(db, "users/alice/goals/g1"), lww({ ...goal, deleted: true })),
    );
    await assertFails(deleteDoc(doc(db, "users/alice/goals/g1")));
  });

  it("rejects bad goals and other users", async () => {
    const db = env.authenticatedContext("alice").firestore();
    await assertFails(
      setDoc(
        doc(db, "users/alice/goals/g"),
        lww({ ...goal, metric: "streak" }),
      ),
    );
    await assertFails(
      setDoc(
        doc(db, "users/alice/goals/g"),
        lww({ ...goal, period: "decade" }),
      ),
    );
    await assertFails(
      setDoc(doc(db, "users/alice/goals/g"), lww({ ...goal, target: 0 })),
    );
    await assertFails(
      setDoc(doc(db, "users/alice/goals/g"), lww({ ...goal, start: "soon" })),
    );
    const bob = env.authenticatedContext("bob").firestore();
    await assertFails(setDoc(doc(bob, "users/alice/goals/g"), lww(goal)));
  });
});

describe("session tombstones (append-only)", () => {
  const tomb = { deletedAt: "2026-11-05T10:00:00.000Z" };

  it("can be created once and never changed", async () => {
    const db = env.authenticatedContext("alice").firestore();
    await assertSucceeds(
      setDoc(doc(db, "users/alice/sessionTombstones/s1"), {
        ...tomb,
        updatedAt: serverTimestamp(),
      }),
    );
    await assertFails(
      setDoc(doc(db, "users/alice/sessionTombstones/s1"), {
        deletedAt: "2027-01-01T00:00:00.000Z",
        updatedAt: serverTimestamp(),
      }),
    );
    await assertFails(deleteDoc(doc(db, "users/alice/sessionTombstones/s1")));
  });

  it("rejects extra fields and other users", async () => {
    const db = env.authenticatedContext("alice").firestore();
    await assertFails(
      setDoc(doc(db, "users/alice/sessionTombstones/s2"), {
        ...tomb,
        why: "x",
        updatedAt: serverTimestamp(),
      }),
    );
    const bob = env.authenticatedContext("bob").firestore();
    await assertFails(
      setDoc(doc(bob, "users/alice/sessionTombstones/s3"), {
        ...tomb,
        updatedAt: serverTimestamp(),
      }),
    );
  });
});

describe("catalog", () => {
  it("signed-in users can read but never write", async () => {
    const db = env.authenticatedContext("alice").firestore();
    await assertSucceeds(getDoc(doc(db, "catalog_works/w1")));
    await assertFails(setDoc(doc(db, "catalog_works/w1"), { title: "Forged" }));
  });

  it("signed-out clients cannot read", async () => {
    const anon = env.unauthenticatedContext().firestore();
    await assertFails(getDoc(doc(anon, "catalog_works/w1")));
  });

  it("server-only collections are closed to clients", async () => {
    const db = env.authenticatedContext("alice").firestore();
    await assertFails(getDoc(doc(db, "catalog_searchCache/q")));
    await assertFails(getDoc(doc(db, "ops_rateLimits/alice")));
  });
});

// Phase 8 rules audit: the same closed-door checks across every collection, so a
// new collection can't quietly be weaker. See the table in docs/05 §1.7.
describe("audit: every user collection", () => {
  const collections = [
    "library",
    "readThroughs",
    "userEditions",
    "progressEvents",
    "sessions",
    "sessionTombstones",
    "notes",
    "goals",
  ];

  beforeEach(async () => {
    await env.withSecurityRulesDisabled(async (context) => {
      const db = context.firestore();
      await setDoc(doc(db, "users/alice"), { displayName: "Alice" });
      for (const c of collections) {
        await setDoc(doc(db, `users/alice/${c}/a`), { value: 1 });
      }
    });
  });

  it.each(collections)("%s: only the owner reads", async (c) => {
    const alice = env.authenticatedContext("alice").firestore();
    await assertSucceeds(getDoc(doc(alice, `users/alice/${c}/a`)));
    await assertSucceeds(getDocs(collection(alice, `users/alice/${c}`)));

    const bob = env.authenticatedContext("bob").firestore();
    await assertFails(getDoc(doc(bob, `users/alice/${c}/a`)));
    await assertFails(getDocs(collection(bob, `users/alice/${c}`)));

    const anon = env.unauthenticatedContext().firestore();
    await assertFails(getDoc(doc(anon, `users/alice/${c}/a`)));
    await assertFails(getDocs(collection(anon, `users/alice/${c}`)));
  });

  it.each(collections)(
    "%s: nobody can hard-delete or write as someone else",
    async (c) => {
      const alice = env.authenticatedContext("alice").firestore();
      await assertFails(deleteDoc(doc(alice, `users/alice/${c}/a`)));

      const bob = env.authenticatedContext("bob").firestore();
      await assertFails(deleteDoc(doc(bob, `users/alice/${c}/a`)));
      await assertFails(setDoc(doc(bob, `users/alice/${c}/b`), { value: 1 }));

      const anon = env.unauthenticatedContext().firestore();
      await assertFails(setDoc(doc(anon, `users/alice/${c}/b`), { value: 1 }));
    },
  );

  it.each(collections)(
    "%s: a document without the required shape is refused",
    async (c) => {
      const alice = env.authenticatedContext("alice").firestore();
      await assertFails(
        setDoc(doc(alice, `users/alice/${c}/junk`), { unexpected: true }),
      );
    },
  );

  it("nobody can list all users", async () => {
    const alice = env.authenticatedContext("alice").firestore();
    await assertFails(getDocs(collection(alice, "users")));
    const anon = env.unauthenticatedContext().firestore();
    await assertFails(getDocs(collection(anon, "users")));
  });

  it("an unknown sub-collection and an unknown top-level collection are closed", async () => {
    const alice = env.authenticatedContext("alice").firestore();
    await assertFails(getDoc(doc(alice, "users/alice/somethingNew/a")));
    await assertFails(
      setDoc(doc(alice, "users/alice/somethingNew/a"), { value: 1 }),
    );
    await assertFails(getDoc(doc(alice, "anything/a")));
    await assertFails(setDoc(doc(alice, "anything/a"), { value: 1 }));
  });

  it("private_integrations is server-only, even for its owner", async () => {
    const alice = env.authenticatedContext("alice").firestore();
    await assertFails(getDoc(doc(alice, "deleted_accounts/alice")));
    await assertFails(getDoc(doc(alice, "private_integrations/alice")));
    await assertFails(
      setDoc(doc(alice, "private_integrations/alice"), { token: "x" }),
    );
  });

  it.each([
    "catalog_works",
    "catalog_editions",
    "catalog_authors",
    "catalog_series",
    "catalog_isbn",
  ])("%s: readable when signed in, never writable", async (c) => {
    const alice = env.authenticatedContext("alice").firestore();
    await assertSucceeds(getDoc(doc(alice, `${c}/x`)));
    await assertFails(setDoc(doc(alice, `${c}/x`), { value: 1 }));
    await assertFails(deleteDoc(doc(alice, `${c}/x`)));
    const anon = env.unauthenticatedContext().firestore();
    await assertFails(getDoc(doc(anon, `${c}/x`)));
  });
});
