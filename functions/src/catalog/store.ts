import type { CatalogAuthor, CatalogSeries, CatalogWork } from "./types";

export interface IsbnHit {
  workId: string;
  editionId: string;
}

/** Minimal author/series document created when a work references it. */
export interface Stub {
  id: string;
  refKey: string;
  name: string;
}

/**
 * Persistence for the global catalog (docs/03 §2.1). Implemented by
 * Firestore in production and in memory for tests.
 */
export interface CatalogStore {
  /** Maps provider ref keys (`provider:externalId`) to internal ids. */
  findIdsByRefKeys(keys: string[]): Promise<Map<string, string>>;
  /** First catalog edition matching any of the ISBN-13s. */
  findByIsbn(isbn13s: string[]): Promise<IsbnHit | null>;

  getWork(id: string): Promise<CatalogWork | null>;
  /**
   * Atomically writes the work, its editions, the ISBN index (never
   * re-pointing an ISBN that already belongs to another work), provider
   * indexes and author/series stubs.
   */
  saveWork(
    work: CatalogWork,
    stubs: { authors: Stub[]; series: Stub[] },
  ): Promise<void>;

  /**
   * Sets only `refreshedAt`, and only if it still equals [expected], so it
   * can never overwrite a refresh that landed in the meantime.
   */
  touchWorkIfUnchanged(
    id: string,
    expected: string,
    refreshedAt: string,
  ): Promise<void>;

  getAuthor(id: string): Promise<CatalogAuthor | null>;
  saveAuthor(author: CatalogAuthor): Promise<void>;
  getSeries(id: string): Promise<CatalogSeries | null>;
  saveSeries(series: CatalogSeries): Promise<void>;

  getCached<T>(key: string, now: Date): Promise<T | null>;
  putCached(key: string, value: unknown, expiresAt: Date): Promise<void>;

  /** Token-bucket rate limit per user and action; false when exhausted. */
  consumeRate(
    uid: string,
    action: string,
    perMinute: number,
    now: Date,
  ): Promise<boolean>;
}

/** In-memory store for tests and local reasoning. Same semantics as Firestore. */
export class MemoryCatalogStore implements CatalogStore {
  readonly works = new Map<string, CatalogWork>();
  readonly authors = new Map<string, CatalogAuthor>();
  readonly series = new Map<string, CatalogSeries>();
  readonly refIndex = new Map<string, string>();
  readonly isbnIndex = new Map<string, IsbnHit>();
  readonly cache = new Map<string, { value: unknown; expiresAt: Date }>();
  readonly buckets = new Map<string, { tokens: number; at: number }>();

  async findIdsByRefKeys(keys: string[]) {
    return new Map(
      keys.flatMap((k) =>
        this.refIndex.has(k) ? [[k, this.refIndex.get(k)!] as const] : [],
      ),
    );
  }

  async findByIsbn(isbn13s: string[]) {
    for (const isbn of isbn13s) {
      const hit = this.isbnIndex.get(isbn);
      if (hit) return hit;
    }
    return null;
  }

  async getWork(id: string) {
    return structuredClone(this.works.get(id) ?? null);
  }

  async saveWork(
    work: CatalogWork,
    stubs: { authors: Stub[]; series: Stub[] },
  ) {
    this.works.set(work.id, structuredClone(work));
    for (const [provider, id] of Object.entries(work.providerIds))
      this.refIndex.set(`${provider}:${id}`, work.id);
    for (const e of work.editions) {
      if (e.isbn13 && !this.isbnIndex.has(e.isbn13))
        this.isbnIndex.set(e.isbn13, { workId: work.id, editionId: e.id });
      for (const [provider, id] of Object.entries(e.providerIds)) {
        if (!this.refIndex.has(`edition:${provider}:${id}`))
          this.refIndex.set(`edition:${provider}:${id}`, e.id);
      }
    }
    for (const s of stubs.authors) {
      this.refIndex.set(s.refKey, s.id);
      if (!this.authors.has(s.id)) {
        this.authors.set(s.id, {
          id: s.id,
          name: s.name,
          bio: null,
          photoUrl: null,
          photoCredit: null,
          birthDate: null,
          deathDate: null,
          works: [],
          providerIds: refKeyToIds(s.refKey),
          refreshedAt: new Date(0).toISOString(),
        });
      }
    }
    for (const s of stubs.series) {
      this.refIndex.set(s.refKey, s.id);
      if (!this.series.has(s.id)) {
        this.series.set(s.id, {
          id: s.id,
          name: s.name,
          description: null,
          entries: [],
          primaryCount: 0,
          providerIds: refKeyToIds(s.refKey),
          refreshedAt: new Date(0).toISOString(),
        });
      }
    }
  }

  async touchWorkIfUnchanged(
    id: string,
    expected: string,
    refreshedAt: string,
  ) {
    const work = this.works.get(id);
    if (work?.refreshedAt === expected) work.refreshedAt = refreshedAt;
  }

  async getAuthor(id: string) {
    return structuredClone(this.authors.get(id) ?? null);
  }

  async saveAuthor(author: CatalogAuthor) {
    this.authors.set(author.id, structuredClone(author));
    for (const [p, x] of Object.entries(author.providerIds))
      this.refIndex.set(`author:${p}:${x}`, author.id);
  }

  async getSeries(id: string) {
    return structuredClone(this.series.get(id) ?? null);
  }

  async saveSeries(series: CatalogSeries) {
    this.series.set(series.id, structuredClone(series));
    for (const [p, x] of Object.entries(series.providerIds))
      this.refIndex.set(`series:${p}:${x}`, series.id);
  }

  async getCached<T>(key: string, now: Date) {
    const entry = this.cache.get(key);
    return entry && entry.expiresAt > now
      ? (structuredClone(entry.value) as T)
      : null;
  }

  async putCached(key: string, value: unknown, expiresAt: Date) {
    this.cache.set(key, { value: structuredClone(value), expiresAt });
  }

  async consumeRate(uid: string, action: string, perMinute: number, now: Date) {
    const key = `${uid}:${action}`;
    const t = now.getTime();
    const bucket = this.buckets.get(key) ?? { tokens: perMinute, at: t };
    const tokens = Math.min(
      perMinute,
      bucket.tokens + ((t - bucket.at) * perMinute) / 60_000,
    );
    if (tokens < 1) {
      this.buckets.set(key, { tokens, at: t });
      return false;
    }
    this.buckets.set(key, { tokens: tokens - 1, at: t });
    return true;
  }
}

/** `author:hardcover:12` → `{ hardcover: '12' }`. */
export function refKeyToIds(refKey: string): Record<string, string> {
  const [, provider, ...rest] = refKey.split(":");
  return provider ? { [provider]: rest.join(":") } : {};
}
