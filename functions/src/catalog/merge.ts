import { normalizeIsbn } from "./isbn";
import type {
  CatalogAuthorRef,
  CatalogEdition,
  CatalogSeriesRef,
  CatalogWork,
  FieldProvenance,
  ProviderId,
  ProviderRef,
  RawEdition,
  RawWork,
} from "./types";

export interface MergeCandidate {
  work: RawWork;
  fetchedAt: Date;
}

export interface MergeContext {
  workId: string;
  /** ISBN the user scanned/looked up; its edition wins page count (docs/04 §1.3). */
  matchedIsbn13?: string;
  editionIdFor(edition: RawEdition): string;
  authorIdFor(ref: ProviderRef | undefined): string | null;
  seriesIdFor(ref: ProviderRef | undefined): string | null;
  now: Date;
}

/** Field priority lists (docs/04 §1.3). */
const PRIORITY: Record<string, ProviderId[]> = {
  identity: ["hardcover", "openLibrary", "googleBooks"],
  description: ["hardcover", "googleBooks", "openLibrary"],
  series: ["hardcover", "openLibrary"],
  pageCount: ["hardcover", "openLibrary", "googleBooks"],
  cover: ["hardcover", "openLibrary", "googleBooks"],
};

const MIN_PAGES = 10;
const MAX_PAGES = 10_000;
const MIN_DESCRIPTION = 80;

const validPages = (n: number | undefined): n is number =>
  n !== undefined && Number.isFinite(n) && n >= MIN_PAGES && n <= MAX_PAGES;

function ordered(
  candidates: MergeCandidate[],
  priority: ProviderId[],
): MergeCandidate[] {
  return [...candidates].sort(
    (a, b) =>
      priority.indexOf(a.work.ref.provider) -
      priority.indexOf(b.work.ref.provider),
  );
}

/**
 * Field-level merge of provider records into one catalog work.
 *
 * Each field is taken from the best provider for that field, and its source
 * is recorded in `provenance`. Only catalog documents are produced: user data
 * lives in a separate namespace and can never be touched by a refresh (D6).
 */
export function mergeWork(
  candidates: MergeCandidate[],
  ctx: MergeContext,
): CatalogWork {
  if (candidates.length === 0)
    throw new Error("mergeWork needs at least one candidate");
  const provenance: Record<string, FieldProvenance> = {};
  const mark = (field: string, c: MergeCandidate) => {
    provenance[field] = {
      provider: c.work.ref.provider,
      fetchedAt: c.fetchedAt.toISOString(),
    };
  };

  function pick<T>(
    field: string,
    priority: ProviderId[],
    get: (w: RawWork) => T | undefined,
    valid: (v: T) => boolean = () => true,
  ): T | undefined {
    for (const c of ordered(candidates, priority)) {
      const value = get(c.work);
      if (value !== undefined && valid(value)) {
        mark(field, c);
        return value;
      }
    }
    return undefined;
  }

  const title = pick("title", PRIORITY.identity!, (w) => w.title)!;
  const subtitle = pick("subtitle", PRIORITY.identity!, (w) => w.subtitle);
  const rawAuthors =
    pick(
      "authors",
      PRIORITY.identity!,
      (w) => w.authors,
      (a) => a.length > 0,
    ) ?? [];
  const authors: CatalogAuthorRef[] = rawAuthors.map((a) => ({
    id: ctx.authorIdFor(a.ref),
    name: a.name,
  }));

  const description =
    pick(
      "description",
      PRIORITY.description!,
      (w) => cleanDescription(w.description),
      (d) => d.length >= MIN_DESCRIPTION,
    ) ??
    pick("description", PRIORITY.description!, (w) =>
      cleanDescription(w.description),
    );

  // Series: prefer entries with an id and a position; fall back to names only.
  const rawSeries =
    pick(
      "series",
      PRIORITY.series!,
      (w) => w.series,
      (s) => s.some((x) => x.ref && x.position !== undefined),
    ) ??
    pick(
      "series",
      PRIORITY.series!,
      (w) => w.series,
      (s) => s.length > 0,
    ) ??
    [];
  const series: CatalogSeriesRef[] = rawSeries.map((s) => ({
    seriesId: ctx.seriesIdFor(s.ref),
    name: s.name,
    position: s.position ?? null,
    positionLabel: s.position === undefined ? null : formatPosition(s.position),
    isPrimary:
      s.isPrimary ?? (s.position !== undefined && Number.isInteger(s.position)),
  }));

  const editions = mergeEditions(candidates, ctx);
  const matched = ctx.matchedIsbn13
    ? editions.find((e) => e.isbn13 === ctx.matchedIsbn13)
    : undefined;

  // Page count: the ISBN-matched edition wins, then the priority list.
  let pageCount: number | null = null;
  if (matched && validPages(matched.pageCount ?? undefined)) {
    pageCount = matched.pageCount;
    const source = candidates.find((c) =>
      (c.work.editions ?? []).some(
        (e) =>
          normalizeIsbn(e.isbn13 ?? e.isbn10 ?? "") === ctx.matchedIsbn13 &&
          validPages(e.pageCount),
      ),
    );
    if (source) mark("pageCount", source);
  } else {
    pageCount =
      pick("pageCount", PRIORITY.pageCount!, (w) => w.pageCount, validPages) ??
      null;
  }
  // Open Library works carry no page count; fall back to a representative
  // edition (provenance is that edition's provider).
  if (pageCount === null) {
    const edition = editions.find(
      (e) =>
        validPages(e.pageCount ?? undefined) &&
        e.format !== "audiobook" &&
        e.format !== "audible",
    );
    if (edition) {
      pageCount = edition.pageCount;
      const provider = Object.keys(edition.providerIds)[0];
      const source = candidates.find((c) => c.work.ref.provider === provider);
      if (source) mark("pageCount", source);
    }
  }

  const coverUrl =
    matched?.coverUrl ??
    pick("coverUrl", PRIORITY.cover!, (w) => w.coverUrl) ??
    null;

  const genres = mergeGenres(candidates);
  if (genres.length > 0) {
    const first = candidates.find((c) => (c.work.genres ?? []).length > 0);
    if (first) mark("genres", first);
  }

  const firstPublishedDate = earliestDate(candidates, mark);
  const language =
    pick("language", PRIORITY.identity!, (w) => w.language) ?? null;

  const providerIds: Partial<Record<ProviderId, string>> = {};
  for (const c of candidates)
    providerIds[c.work.ref.provider] ??= c.work.ref.externalId;

  return {
    id: ctx.workId,
    title,
    subtitle: subtitle ?? null,
    authors,
    description: description ?? null,
    firstPublishedDate,
    language,
    genres,
    series,
    coverUrl,
    pageCount,
    defaultEditionId:
      matched?.id ??
      editions.find((e) => validPages(e.pageCount ?? undefined))?.id ??
      editions[0]?.id ??
      null,
    editions,
    providerIds,
    provenance,
    refreshedAt: ctx.now.toISOString(),
  };
}

/** Union of editions across providers, deduplicated by ISBN-13 (hard identifier). */
function mergeEditions(
  candidates: MergeCandidate[],
  ctx: MergeContext,
): CatalogEdition[] {
  const byKey = new Map<string, CatalogEdition>();
  for (const c of ordered(candidates, PRIORITY.identity!)) {
    for (const e of c.work.editions ?? []) {
      const isbn13 = normalizeIsbn(e.isbn13 ?? e.isbn10 ?? "");
      const key = isbn13 ?? `${e.ref.provider}:${e.ref.externalId}`;
      const existing = byKey.get(key);
      if (existing) {
        // Fill gaps only; the higher-priority provider's values stay.
        existing.publisher ??= e.publisher ?? null;
        existing.publishedDate ??= e.publishedDate ?? null;
        existing.pageCount ??= validPages(e.pageCount) ? e.pageCount : null;
        existing.audioDurationSec ??= e.audioDurationSec ?? null;
        existing.language ??= e.language ?? null;
        existing.coverUrl ??= e.coverUrl ?? null;
        existing.isbn10 ??= e.isbn10 ?? null;
        existing.providerIds[e.ref.provider] ??= e.ref.externalId;
        if (existing.format === "other" && e.format) existing.format = e.format;
        continue;
      }
      byKey.set(key, {
        id: ctx.editionIdFor(e),
        workId: ctx.workId,
        format: e.format ?? "other",
        isbn10: e.isbn10 ?? null,
        isbn13,
        publisher: e.publisher ?? null,
        publishedDate: e.publishedDate ?? null,
        pageCount: validPages(e.pageCount) ? e.pageCount : null,
        audioDurationSec: e.audioDurationSec ?? null,
        language: e.language ?? null,
        coverUrl: e.coverUrl ?? null,
        providerIds: { [e.ref.provider]: e.ref.externalId },
      });
    }
  }
  return [...byKey.values()].slice(0, 50);
}

function mergeGenres(candidates: MergeCandidate[]): string[] {
  const seen = new Map<string, string>();
  for (const c of ordered(candidates, PRIORITY.identity!)) {
    for (const g of c.work.genres ?? []) {
      const name = normalizeGenre(g);
      if (name && !seen.has(name.toLowerCase()))
        seen.set(name.toLowerCase(), name);
    }
  }
  return [...seen.values()].slice(0, 8);
}

function normalizeGenre(raw: string): string | undefined {
  const g = raw.trim().replace(/\s+/g, " ");
  if (g.length < 2 || g.length > 40) return undefined;
  if (
    /^(fiction|general|nyt:|award:)/i.test(g) &&
    g.toLowerCase() !== "fiction"
  )
    return undefined;
  return g
    .split(" ")
    .map((w) => (w.length > 2 ? w[0]!.toUpperCase() + w.slice(1) : w))
    .join(" ");
}

/** Earliest year wins: providers often list a later edition's date. */
function earliestDate(
  candidates: MergeCandidate[],
  mark: (f: string, c: MergeCandidate) => void,
): string | null {
  let best: { date: string; year: number; c: MergeCandidate } | undefined;
  for (const c of candidates) {
    const date = c.work.firstPublishedDate;
    const year = date ? Number(date.match(/\d{4}/)?.[0]) : NaN;
    if (date && Number.isFinite(year) && (!best || year < best.year))
      best = { date, year, c };
  }
  if (!best) return null;
  mark("firstPublishedDate", best.c);
  return best.date;
}

export function cleanDescription(raw: string | undefined): string | undefined {
  if (!raw) return undefined;
  const text = raw
    .replace(/<br\s*\/?>/gi, "\n")
    .replace(/<[^>]+>/g, "")
    // Markdown links and emphasis, as used in Open Library bios/descriptions.
    .replace(/\[([^\]]+)\]\([^)]+\)/g, "$1")
    .replace(/(\*\*|\*|__)([^*_\n]+)\1/g, "$2")
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, "'")
    .replace(/&amp;/g, "&")
    .replace(/\r/g, "")
    // A source link reduced to "(Source)" carries no information.
    .replace(/\(\s*Source\s*\)\s*$/i, "")
    .replace(/\n{3,}/g, "\n\n")
    .trim();
  if (!text || /^no description( available)?\.?$/i.test(text)) return undefined;
  return text;
}

function formatPosition(p: number): string {
  return Number.isInteger(p) ? String(p) : String(Number(p.toFixed(2)));
}
