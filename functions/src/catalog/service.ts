import { createHash } from "node:crypto";

import { uuidv7 } from "./ids";
import { normalizeIsbn } from "./isbn";
import { mergeWork, type MergeCandidate } from "./merge";
import type { MetadataOrchestrator } from "./orchestrator";
import type { CatalogStore, Stub } from "./store";
import {
  refKey,
  type CatalogAuthor,
  type CatalogSeries,
  type CatalogWork,
  type Page,
  type ProviderId,
  type ProviderRef,
  type RawEdition,
  type RawWork,
  type RawWorkHit,
  type SearchQuery,
  type SearchResponse,
  type WorkSummary,
} from "./types";

const DAY = 86_400_000;
const WORK_TTL = 30 * DAY;
/** How soon to retry linking a work whose series has only a name. */
const SERIES_LINK_RETRY = DAY;
const AUTHOR_TTL = 30 * DAY;
const SERIES_TTL = 14 * DAY;
const SEARCH_TTL = DAY;
const TRENDING_TTL = 6 * 3_600_000;

/** Per-user limits per minute (docs/05 §1.2). */
export const RATE_LIMITS = { search: 30, isbn: 30, detail: 60 } as const;

export class CatalogError extends Error {
  constructor(
    readonly code:
      "not-found" | "invalid-argument" | "resource-exhausted" | "unavailable",
    message: string,
  ) {
    super(message);
  }
}

export interface WorkResult {
  work: CatalogWork;
  /** Edition matching the looked-up ISBN, when there was one. */
  editionId: string | null;
}

/**
 * Application service behind the catalog callables: identity resolution,
 * freshness, merging, persistence, caching and per-user rate limits.
 */
export class CatalogService {
  constructor(
    private readonly orchestrator: MetadataOrchestrator,
    private readonly store: CatalogStore,
    private readonly now: () => Date = () => new Date(),
  ) {}

  async search(
    uid: string,
    query: SearchQuery,
    page: Page,
  ): Promise<SearchResponse> {
    await this.limit(uid, "search", RATE_LIMITS.search);
    const text = query.text.trim().replace(/\s+/g, " ");
    if (text.length < 2)
      throw new CatalogError("invalid-argument", "Query too short");

    // An ISBN typed into search is an exact lookup.
    const asIsbn =
      query.field === "all" || query.field === "isbn"
        ? normalizeIsbn(text)
        : null;
    if (asIsbn) {
      const found = await this.lookupIsbn(uid, asIsbn).catch((e: unknown) => {
        if (e instanceof CatalogError && e.code === "not-found") return null;
        throw e;
      });
      return {
        results: found ? [summaryOf(found.work)] : [],
        page: 1,
        hasMore: false,
        provider: null,
        degraded: false,
      };
    }

    const key = cacheKey(
      "search",
      query.field,
      text.toLowerCase(),
      page.page,
      page.pageSize,
    );
    const cached = await this.store.getCached<SearchResponse>(key, this.now());
    if (cached) return this.annotate(cached);

    const outcome = await this.orchestrator.search({ ...query, text }, page);
    const response: SearchResponse = {
      results: rankedForQuery(dedupeHits(outcome.hits), query.field, text).map(
        summaryOfHit,
      ),
      page: page.page,
      hasMore: outcome.hits.length >= page.pageSize,
      provider: outcome.provider,
      degraded: outcome.degraded,
    };
    if (!outcome.degraded)
      await this.store.putCached(
        key,
        response,
        new Date(this.now().getTime() + SEARCH_TTL),
      );
    return this.annotate(response);
  }

  async trending(uid: string, limit: number): Promise<SearchResponse> {
    await this.limit(uid, "search", RATE_LIMITS.search);
    const key = cacheKey("trending", limit);
    const cached = await this.store.getCached<SearchResponse>(key, this.now());
    if (cached) return this.annotate(cached);
    const outcome = await this.orchestrator.trending(limit);
    const response: SearchResponse = {
      results: dedupeHits(outcome.hits).map(summaryOfHit),
      page: 1,
      hasMore: false,
      provider: outcome.provider,
      degraded: outcome.degraded,
    };
    if (!outcome.degraded)
      await this.store.putCached(
        key,
        response,
        new Date(this.now().getTime() + TRENDING_TTL),
      );
    return this.annotate(response);
  }

  async lookupIsbn(uid: string, rawIsbn: string): Promise<WorkResult> {
    await this.limit(uid, "isbn", RATE_LIMITS.isbn);
    const isbn13 = normalizeIsbn(rawIsbn);
    if (!isbn13) throw new CatalogError("invalid-argument", "Not a valid ISBN");

    const known = await this.store.findByIsbn([isbn13]);
    if (known) {
      const work = await this.store.getWork(known.workId);
      if (work && this.isFresh(work.refreshedAt, WORK_TTL))
        return { work, editionId: known.editionId };
    }

    const hits = await this.orchestrator.lookupIsbnAll(isbn13);
    if (hits.length === 0) {
      if (known) {
        const stale = await this.store.getWork(known.workId);
        if (stale) return { work: stale, editionId: known.editionId };
      }
      throw new CatalogError("not-found", "No provider knows this ISBN");
    }
    const candidates: MergeCandidate[] = hits.map((h) => ({
      work: withEdition(h.data.work, h.data),
      fetchedAt: h.fetchedAt,
    }));
    const work = await this.resolveAndSave(candidates, isbn13, known?.workId);
    const edition = work.editions.find((e) => e.isbn13 === isbn13);
    return { work, editionId: edition?.id ?? null };
  }

  async getWork(
    uid: string,
    target: { workId?: string; ref?: ProviderRef },
  ): Promise<WorkResult> {
    await this.limit(uid, "detail", RATE_LIMITS.detail);
    let workId = target.workId ?? null;
    if (!workId && target.ref)
      workId =
        (await this.store.findIdsByRefKeys([refKey(target.ref)])).get(
          refKey(target.ref),
        ) ?? null;

    const existing = workId ? await this.store.getWork(workId) : null;
    const relink = existing !== null && lacksSeriesLink(existing);
    if (
      existing &&
      this.isFresh(existing.refreshedAt, relink ? SERIES_LINK_RETRY : WORK_TTL)
    )
      return { work: existing, editionId: existing.defaultEditionId };
    if (!existing && !target.ref)
      throw new CatalogError("not-found", "Unknown work");

    // Fetch every provider we know an id for (refresh) or the requested ref (first view).
    const refs: ProviderRef[] = existing
      ? Object.entries(existing.providerIds).map(([provider, externalId]) => ({
          provider: provider as ProviderId,
          externalId: externalId!,
        }))
      : [target.ref!];
    const fetched = await Promise.all(
      refs.map((r) => this.orchestrator.getWork(r)),
    );
    const candidates: MergeCandidate[] = fetched.flatMap((r) =>
      r.ok ? [{ work: r.data, fetchedAt: r.fetchedAt }] : [],
    );
    if (candidates.length === 0) {
      if (existing)
        return { work: existing, editionId: existing.defaultEditionId }; // serve stale over nothing
      throw new CatalogError("unavailable", "Metadata providers unavailable");
    }

    // Enrich from the other providers through a hard identifier (ISBN).
    if (!existing || relink) await this.enrichViaIsbn(candidates);

    const work = await this.resolveAndSave(candidates, undefined, existing?.id);
    return { work, editionId: work.defaultEditionId };
  }

  async getAuthor(
    uid: string,
    target: { authorId?: string; ref?: ProviderRef },
  ): Promise<CatalogAuthor> {
    await this.limit(uid, "detail", RATE_LIMITS.detail);
    const authorId =
      target.authorId ??
      (target.ref
        ? (
            await this.store.findIdsByRefKeys([`author:${refKey(target.ref)}`])
          ).get(`author:${refKey(target.ref)}`)
        : undefined);
    const existing = authorId ? await this.store.getAuthor(authorId) : null;
    if (existing && this.isFresh(existing.refreshedAt, AUTHOR_TTL))
      return existing;

    const ref = target.ref ?? firstRef(existing?.providerIds);
    if (!ref) throw new CatalogError("not-found", "Unknown author");
    const result = await this.orchestrator.getAuthor(ref);
    if (!result.ok) {
      if (existing) return existing;
      throw new CatalogError(
        result.error === "notFound" ? "not-found" : "unavailable",
        "Author unavailable",
      );
    }
    const a = result.data;
    const author: CatalogAuthor = {
      id: existing?.id ?? authorId ?? uuidv7(this.now().getTime()),
      name: a.name,
      bio: a.bio ?? null,
      photoUrl: a.photoUrl ?? null,
      photoCredit: a.photoCredit ?? null,
      birthDate: a.birthDate ?? null,
      deathDate: a.deathDate ?? null,
      works: dedupeHits(a.works ?? [])
        .slice(0, 50)
        .map(summaryOfHit),
      providerIds: { ...existing?.providerIds, [ref.provider]: ref.externalId },
      refreshedAt: this.now().toISOString(),
    };
    await this.store.saveAuthor(author);
    return {
      ...author,
      works: (
        await this.annotate({
          results: author.works,
          page: 1,
          hasMore: false,
          provider: null,
          degraded: false,
        })
      ).results,
    };
  }

  async getSeries(
    uid: string,
    target: { seriesId?: string; ref?: ProviderRef },
  ): Promise<CatalogSeries> {
    await this.limit(uid, "detail", RATE_LIMITS.detail);
    const seriesId =
      target.seriesId ??
      (target.ref
        ? (
            await this.store.findIdsByRefKeys([`series:${refKey(target.ref)}`])
          ).get(`series:${refKey(target.ref)}`)
        : undefined);
    const existing = seriesId ? await this.store.getSeries(seriesId) : null;
    if (existing && this.isFresh(existing.refreshedAt, SERIES_TTL))
      return existing;

    const ref = target.ref ?? firstRef(existing?.providerIds);
    if (!ref) throw new CatalogError("not-found", "Unknown series");
    const result = await this.orchestrator.getSeries(ref);
    if (!result.ok) {
      if (existing && existing.entries.length > 0) return existing;
      throw new CatalogError(
        result.error === "notFound" || result.error === "unsupported"
          ? "not-found"
          : "unavailable",
        "Series unavailable",
      );
    }
    const s = result.data;
    const entries = s.entries.map((e) => ({
      work: summaryOfHit(e.work),
      position: e.position ?? null,
      positionLabel: e.positionLabel ?? null,
      isPrimary: e.isPrimary,
    }));
    const annotated = await this.annotate({
      results: entries.map((e) => e.work),
      page: 1,
      hasMore: false,
      provider: null,
      degraded: false,
    });
    const series: CatalogSeries = {
      id: existing?.id ?? seriesId ?? uuidv7(this.now().getTime()),
      name: s.name,
      description: s.description ?? null,
      // Reading order is the provider's position order, not publication order.
      entries: entries.map((e, i) => ({ ...e, work: annotated.results[i]! })),
      primaryCount: entries.filter((e) => e.isPrimary).length,
      providerIds: { ...existing?.providerIds, [ref.provider]: ref.externalId },
      refreshedAt: this.now().toISOString(),
    };
    await this.store.saveSeries(series);
    return series;
  }

  // ─── internals ───

  private async limit(
    uid: string,
    action: keyof typeof RATE_LIMITS,
    perMinute: number,
  ) {
    if (!(await this.store.consumeRate(uid, action, perMinute, this.now()))) {
      throw new CatalogError(
        "resource-exhausted",
        "Too many requests, slow down",
      );
    }
  }

  private isFresh(iso: string, ttl: number) {
    return this.now().getTime() - Date.parse(iso) < ttl;
  }

  /** Adds catalog ids to summaries whose provider ref is already known. */
  private async annotate(response: SearchResponse): Promise<SearchResponse> {
    const ids = await this.store.findIdsByRefKeys(
      response.results.map((r) => refKey(r.ref)),
    );
    return {
      ...response,
      results: response.results.map((r) => ({
        ...r,
        id: ids.get(refKey(r.ref)) ?? r.id,
      })),
    };
  }

  /** Looks the work's first ISBN up at the other providers to merge their fields. */
  private async enrichViaIsbn(candidates: MergeCandidate[]) {
    const have = new Set(candidates.map((c) => c.work.ref.provider));
    const isbn = candidates
      .flatMap((c) => [
        ...(c.work.isbns ?? []),
        ...(c.work.editions ?? []).flatMap((e) => [e.isbn13, e.isbn10]),
      ])
      .map((i) => (i ? normalizeIsbn(i) : null))
      .find((i): i is string => !!i);
    if (!isbn) return;
    const extra = await this.orchestrator.lookupIsbnAll(isbn);
    for (const hit of extra) {
      if (!have.has(hit.data.work.ref.provider)) {
        candidates.push({
          work: withEdition(hit.data.work, hit.data),
          fetchedAt: hit.fetchedAt,
        });
        have.add(hit.data.work.ref.provider);
      }
    }
  }

  /**
   * Resolves the internal work id using hard identifiers only (provider ids,
   * then ISBNs), merges, mints ids for new editions/authors/series and saves.
   */
  private async resolveAndSave(
    candidates: MergeCandidate[],
    matchedIsbn13: string | undefined,
    knownWorkId?: string,
  ): Promise<CatalogWork> {
    const workRefKeys = candidates.map((c) => refKey(c.work.ref));
    const editions = candidates.flatMap((c) => c.work.editions ?? []);
    const authorRefs = candidates.flatMap((c) =>
      c.work.authors.flatMap((a) => (a.ref ? [`author:${refKey(a.ref)}`] : [])),
    );
    const seriesRefs = candidates.flatMap((c) =>
      (c.work.series ?? []).flatMap((s) =>
        s.ref ? [`series:${refKey(s.ref)}`] : [],
      ),
    );
    const editionRefKeys = editions.map((e) => `edition:${refKey(e.ref)}`);
    const known = await this.store.findIdsByRefKeys([
      ...workRefKeys,
      ...authorRefs,
      ...seriesRefs,
      ...editionRefKeys,
    ]);

    const isbns = editions
      .map((e) => normalizeIsbn(e.isbn13 ?? e.isbn10 ?? ""))
      .filter((i): i is string => !!i);
    const workId =
      knownWorkId ??
      workRefKeys.map((k) => known.get(k)).find((id): id is string => !!id) ??
      (await this.store.findByIsbn(isbns))?.workId ??
      uuidv7(this.now().getTime());

    const existing = await this.store.getWork(workId);
    const editionIdByIsbn = new Map(
      existing?.editions.flatMap((e) =>
        e.isbn13 ? [[e.isbn13, e.id] as const] : [],
      ) ?? [],
    );
    const minted = new Map<string, string>();
    const mint = (key: string) => {
      if (!minted.has(key))
        minted.set(key, known.get(key) ?? uuidv7(this.now().getTime()));
      return minted.get(key)!;
    };

    const work = mergeWork(candidates, {
      workId,
      matchedIsbn13,
      now: this.now(),
      editionIdFor: (e: RawEdition) => {
        const isbn = normalizeIsbn(e.isbn13 ?? e.isbn10 ?? "");
        return (
          (isbn && editionIdByIsbn.get(isbn)) ||
          mint(`edition:${refKey(e.ref)}`)
        );
      },
      authorIdFor: (ref) => (ref ? mint(`author:${refKey(ref)}`) : null),
      seriesIdFor: (ref) => (ref ? mint(`series:${refKey(ref)}`) : null),
    });
    // Keep provider ids learned on earlier merges.
    work.providerIds = { ...existing?.providerIds, ...work.providerIds };

    const stubs = (prefix: string, names: Map<string, string>): Stub[] =>
      [...minted.entries()]
        .filter(([k]) => k.startsWith(prefix))
        .map(([refKeyValue, id]) => ({
          id,
          refKey: refKeyValue,
          name: names.get(refKeyValue) ?? "",
        }));
    const authorNames = new Map(
      candidates.flatMap((c) =>
        c.work.authors.flatMap((a) =>
          a.ref ? [[`author:${refKey(a.ref)}`, a.name] as const] : [],
        ),
      ),
    );
    const seriesNames = new Map(
      candidates.flatMap((c) =>
        (c.work.series ?? []).flatMap((s) =>
          s.ref ? [[`series:${refKey(s.ref)}`, s.name] as const] : [],
        ),
      ),
    );
    await this.store.saveWork(work, {
      authors: stubs("author:", authorNames),
      series: stubs("series:", seriesNames),
    });
    return work;
  }
}

/** Puts the looked-up edition into the work's edition list. */
function withEdition(work: RawWork, edition: RawEdition): RawWork {
  const editions = work.editions ?? [];
  const has = editions.some(
    (e) =>
      e.ref.provider === edition.ref.provider &&
      e.ref.externalId === edition.ref.externalId,
  );
  const { work: _ignored, ...plain } = edition as RawEdition & {
    work?: unknown;
  };
  void _ignored;
  return { ...work, editions: has ? editions : [plain, ...editions] };
}

function dedupeHits(hits: RawWorkHit[]): RawWorkHit[] {
  const seen = new Set<string>();
  return hits.filter((h) => {
    const key = refKey(h.ref);
    if (seen.has(key)) return false;
    seen.add(key);
    return true;
  });
}

/** A series known only by name, which Hardcover could still give an id to. */
function lacksSeriesLink(work: CatalogWork): boolean {
  return !work.providerIds.hardcover && work.series.some((s) => !s.seriesId);
}

function comparableTitle(title: string): string {
  return title
    .normalize("NFKD")
    .replace(/\p{M}/gu, "")
    .toLowerCase()
    .replace(/[^\p{L}\p{N}]+/gu, " ")
    .trim()
    .replace(/^(the|a|an) /, "");
}

/**
 * Puts exact title matches first, then titles starting with the query. Other
 * results keep the provider's order, as does everything for non-title searches.
 */
export function rankedForQuery(
  hits: RawWorkHit[],
  field: SearchQuery["field"],
  text: string,
): RawWorkHit[] {
  const query = comparableTitle(text);
  if (!query || (field !== "all" && field !== "title")) return hits;
  const tier = (hit: RawWorkHit) => {
    const title = comparableTitle(hit.title);
    if (title === query) return 0;
    return title.startsWith(`${query} `) ? 1 : 2;
  };
  return [...hits].sort((a, b) => tier(a) - tier(b));
}

function summaryOfHit(h: RawWorkHit): WorkSummary {
  return {
    id: null,
    ref: h.ref,
    title: h.title,
    subtitle: h.subtitle ?? null,
    authors: h.authors.map((a) => a.name),
    coverUrl: h.coverUrl ?? null,
    firstPublishedYear: h.firstPublishedYear ?? null,
    seriesName: h.seriesName ?? null,
    seriesPosition: h.seriesPosition ?? null,
    pageCount: h.pageCount ?? null,
  };
}

export function summaryOf(work: CatalogWork): WorkSummary {
  const [provider, externalId] = Object.entries(work.providerIds)[0] ?? [
    "openLibrary",
    work.id,
  ];
  const year = work.firstPublishedDate?.match(/\d{4}/)?.[0];
  return {
    id: work.id,
    ref: { provider: provider as ProviderId, externalId: externalId! },
    title: work.title,
    subtitle: work.subtitle,
    authors: work.authors.map((a) => a.name),
    coverUrl: work.coverUrl,
    firstPublishedYear: year ? Number(year) : null,
    seriesName: work.series[0]?.name ?? null,
    seriesPosition: work.series[0]?.position ?? null,
    pageCount: work.pageCount,
  };
}

function firstRef(
  ids: Partial<Record<ProviderId, string>> | undefined,
): ProviderRef | undefined {
  const entry = Object.entries(ids ?? {})[0];
  return entry
    ? { provider: entry[0] as ProviderId, externalId: entry[1]! }
    : undefined;
}

function cacheKey(...parts: Array<string | number>): string {
  return createHash("sha256").update(parts.join("\u0000")).digest("hex");
}
