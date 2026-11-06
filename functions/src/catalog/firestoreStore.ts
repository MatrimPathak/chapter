import {
  Timestamp,
  type DocumentReference,
  type Firestore,
  type Transaction,
} from "firebase-admin/firestore";

import type { CatalogStore, IsbnHit, Stub } from "./store";
import { refKeyToIds } from "./store";
import type { CatalogAuthor, CatalogSeries, CatalogWork } from "./types";

const C = {
  works: "catalog_works",
  authors: "catalog_authors",
  series: "catalog_series",
  isbn: "catalog_isbn",
  index: "catalog_providerIndex",
  cache: "catalog_searchCache",
  rate: "ops_rateLimits",
} as const;

/** Firestore doc ids may not contain '/'. Provider ids never should, but be safe. */
const safeId = (key: string) => key.replace(/\//g, "_");

/**
 * Firestore implementation of the catalog store (docs/03 §2.1).
 *
 * Editions are embedded in the work document (≤ 50), so a detail screen costs
 * one read; `catalog_isbn` indexes them for lookups. Every multi-document
 * write runs in a transaction.
 */
export class FirestoreCatalogStore implements CatalogStore {
  constructor(private readonly db: Firestore) {}

  async findIdsByRefKeys(keys: string[]): Promise<Map<string, string>> {
    const unique = [...new Set(keys)];
    const out = new Map<string, string>();
    for (let i = 0; i < unique.length; i += 100) {
      const chunk = unique.slice(i, i + 100);
      if (chunk.length === 0) continue;
      const snaps = await this.db.getAll(...chunk.map((k) => this.indexRef(k)));
      snaps.forEach((s, j) => {
        const id = s.get("internalId") as string | undefined;
        if (s.exists && id) out.set(chunk[j]!, id);
      });
    }
    return out;
  }

  async findByIsbn(isbn13s: string[]): Promise<IsbnHit | null> {
    if (isbn13s.length === 0) return null;
    const snaps = await this.db.getAll(
      ...isbn13s.slice(0, 100).map((i) => this.db.collection(C.isbn).doc(i)),
    );
    const hit = snaps.find((s) => s.exists);
    return hit
      ? {
          workId: hit.get("workId") as string,
          editionId: hit.get("editionId") as string,
        }
      : null;
  }

  async getWork(id: string): Promise<CatalogWork | null> {
    const snap = await this.db.collection(C.works).doc(id).get();
    return snap.exists ? (snap.data() as CatalogWork) : null;
  }

  async saveWork(
    work: CatalogWork,
    stubs: { authors: Stub[]; series: Stub[] },
  ): Promise<void> {
    const isbnRefs = work.editions
      .filter((e) => e.isbn13)
      .map((e) => [e, this.db.collection(C.isbn).doc(e.isbn13!)] as const);
    const authorRefs = stubs.authors.map(
      (s) => [s, this.db.collection(C.authors).doc(s.id)] as const,
    );
    const seriesRefs = stubs.series.map(
      (s) => [s, this.db.collection(C.series).doc(s.id)] as const,
    );

    await this.db.runTransaction(async (tx) => {
      // All reads before writes (Firestore transaction rule).
      const existingIsbn = isbnRefs.length
        ? await tx.getAll(...isbnRefs.map(([, r]) => r))
        : [];
      const existingAuthors = authorRefs.length
        ? await tx.getAll(...authorRefs.map(([, r]) => r))
        : [];
      const existingSeries = seriesRefs.length
        ? await tx.getAll(...seriesRefs.map(([, r]) => r))
        : [];

      tx.set(this.db.collection(C.works).doc(work.id), work);
      // Never re-point an ISBN that already belongs to another work.
      isbnRefs.forEach(([edition, ref], i) => {
        if (!existingIsbn[i]?.exists)
          tx.set(ref, { workId: work.id, editionId: edition.id });
      });
      for (const [provider, externalId] of Object.entries(work.providerIds)) {
        this.index(tx, `${provider}:${externalId}`, "work", work.id);
      }
      for (const edition of work.editions) {
        for (const [provider, externalId] of Object.entries(
          edition.providerIds,
        )) {
          this.index(
            tx,
            `edition:${provider}:${externalId}`,
            "edition",
            edition.id,
          );
        }
      }
      authorRefs.forEach(([stub, ref], i) => {
        this.index(tx, stub.refKey, "author", stub.id);
        if (!existingAuthors[i]?.exists) {
          const author: CatalogAuthor = {
            id: stub.id,
            name: stub.name,
            bio: null,
            photoUrl: null,
            photoCredit: null,
            birthDate: null,
            deathDate: null,
            works: [],
            providerIds: refKeyToIds(stub.refKey),
            refreshedAt: new Date(0).toISOString(),
          };
          tx.set(ref, author);
        }
      });
      seriesRefs.forEach(([stub, ref], i) => {
        this.index(tx, stub.refKey, "series", stub.id);
        if (!existingSeries[i]?.exists) {
          const series: CatalogSeries = {
            id: stub.id,
            name: stub.name,
            description: null,
            entries: [],
            primaryCount: 0,
            providerIds: refKeyToIds(stub.refKey),
            refreshedAt: new Date(0).toISOString(),
          };
          tx.set(ref, series);
        }
      });
    });
  }

  async getAuthor(id: string): Promise<CatalogAuthor | null> {
    const snap = await this.db.collection(C.authors).doc(id).get();
    return snap.exists ? (snap.data() as CatalogAuthor) : null;
  }

  async saveAuthor(author: CatalogAuthor): Promise<void> {
    const batch = this.db.batch();
    batch.set(this.db.collection(C.authors).doc(author.id), author);
    for (const [p, x] of Object.entries(author.providerIds)) {
      batch.set(this.indexRef(`author:${p}:${x}`), {
        kind: "author",
        internalId: author.id,
      });
    }
    await batch.commit();
  }

  async getSeries(id: string): Promise<CatalogSeries | null> {
    const snap = await this.db.collection(C.series).doc(id).get();
    return snap.exists ? (snap.data() as CatalogSeries) : null;
  }

  async saveSeries(series: CatalogSeries): Promise<void> {
    const batch = this.db.batch();
    batch.set(this.db.collection(C.series).doc(series.id), series);
    for (const [p, x] of Object.entries(series.providerIds)) {
      batch.set(this.indexRef(`series:${p}:${x}`), {
        kind: "series",
        internalId: series.id,
      });
    }
    await batch.commit();
  }

  async getCached<T>(key: string, now: Date): Promise<T | null> {
    const snap = await this.db.collection(C.cache).doc(key).get();
    if (!snap.exists) return null;
    const expiresAt = snap.get("expiresAt") as Timestamp | undefined;
    if (!expiresAt || expiresAt.toMillis() <= now.getTime()) return null;
    return JSON.parse(snap.get("value") as string) as T;
  }

  async putCached(key: string, value: unknown, expiresAt: Date): Promise<void> {
    // `expiresAt` drives a Firestore TTL policy on catalog_searchCache.
    await this.db
      .collection(C.cache)
      .doc(key)
      .set({
        value: JSON.stringify(value),
        expiresAt: Timestamp.fromDate(expiresAt),
      });
  }

  async consumeRate(
    uid: string,
    action: string,
    perMinute: number,
    now: Date,
  ): Promise<boolean> {
    const ref = this.db.collection(C.rate).doc(rateLimitDocId(uid, action));
    return this.db.runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      const t = now.getTime();
      const prevTokens = snap.exists
        ? (snap.get("tokens") as number)
        : perMinute;
      const prevAt = snap.exists ? (snap.get("at") as number) : t;
      const tokens = Math.min(
        perMinute,
        prevTokens + ((t - prevAt) * perMinute) / 60_000,
      );
      const allowed = tokens >= 1;
      tx.set(ref, {
        tokens: allowed ? tokens - 1 : tokens,
        at: t,
        expiresAt: Timestamp.fromMillis(t + 3_600_000),
      });
      return allowed;
    });
  }

  private indexRef(key: string): DocumentReference {
    return this.db.collection(C.index).doc(safeId(key));
  }

  private index(
    tx: Transaction,
    key: string,
    kind: string,
    internalId: string,
  ) {
    tx.set(this.indexRef(key), { kind, internalId });
  }
}

/** Rate-limit documents are per user, so deleting an account must find them. */
export function rateLimitDocId(uid: string, action: string): string {
  return safeId(`${uid}_${action}`);
}

export const RATE_LIMIT_COLLECTION = C.rate;
