import {
  asArray,
  asNumber,
  asRecord,
  asString,
  asStrings,
  fail,
  guard,
  ok,
  statusToError,
  type FetchJson,
} from "../http";
import { cleanIsbn, isValidIsbn10, isValidIsbn13 } from "../isbn";
import type {
  Page,
  ProviderResult,
  RawAuthor,
  RawEdition,
  RawSeries,
  RawWork,
  RawWorkHit,
  SearchField,
  SearchQuery,
} from "../types";
import {
  unsupported,
  type BookMetadataProvider,
  type ProviderCapability,
} from "./BookMetadataProvider";

const BASE = "https://www.googleapis.com/books/v1";

/**
 * Google Books (docs/04 §1.5). Requires an API key held in Secret Manager:
 * keyless requests share a project quota that is frequently exhausted (we
 * observed `quota_limit_value: 0` on 2026-11-04), so the provider is disabled
 * until a key is configured.
 */
export class GoogleBooksProvider implements BookMetadataProvider {
  readonly id = "googleBooks" as const;
  readonly capabilities: ReadonlySet<ProviderCapability> = new Set([
    "search",
    "lookupIsbn",
    "work",
  ]);
  readonly searchFields: ReadonlySet<SearchField> = new Set([
    "all",
    "title",
    "author",
    "isbn",
    "publisher",
  ]);

  constructor(
    private readonly fetchJson: FetchJson,
    private readonly apiKey: () => string,
  ) {}

  isEnabled(): boolean {
    return this.apiKey().length > 0;
  }

  search(
    query: SearchQuery,
    page: Page,
    signal: AbortSignal,
  ): Promise<ProviderResult<RawWorkHit[]>> {
    return guard(async () => {
      const prefix = {
        all: "",
        title: "intitle:",
        author: "inauthor:",
        isbn: "isbn:",
        publisher: "inpublisher:",
        series: "",
      }[query.field];
      const start = (page.page - 1) * page.pageSize;
      const res = await this.fetchJson(
        `${BASE}/volumes?q=${encodeURIComponent(prefix + query.text)}` +
          `&startIndex=${start}&maxResults=${Math.min(page.pageSize, 40)}&printType=books${this.keyParam()}`,
        { signal },
      );
      if (res.status !== 200) return fail(statusToError(res.status));
      return ok(
        asArray(asRecord(res.json)?.items)
          .map(volumeToHit)
          .filter((h): h is RawWorkHit => !!h),
      );
    });
  }

  lookupIsbn(
    isbn13: string,
    signal: AbortSignal,
  ): Promise<ProviderResult<RawEdition & { work: RawWork }>> {
    return guard(async () => {
      const res = await this.fetchJson(
        `${BASE}/volumes?q=isbn:${isbn13}${this.keyParam()}`,
        { signal },
      );
      if (res.status !== 200) return fail(statusToError(res.status));
      const volume = asRecord(asArray(asRecord(res.json)?.items)[0]);
      const work = volume ? volumeToWork(volume) : undefined;
      // Google sometimes returns near matches; only accept an exact ISBN hit.
      if (!work || !work.isbns?.includes(isbn13)) return fail("notFound");
      const edition = work.editions![0]!;
      return ok({ ...edition, work });
    });
  }

  getWork(
    externalId: string,
    signal: AbortSignal,
  ): Promise<ProviderResult<RawWork>> {
    return guard(async () => {
      const res = await this.fetchJson(
        `${BASE}/volumes/${encodeURIComponent(externalId)}?${this.keyParam().slice(1)}`,
        { signal },
      );
      if (res.status !== 200) return fail(statusToError(res.status));
      const work = volumeToWork(asRecord(res.json) ?? {});
      return work ? ok(work) : fail("invalid");
    });
  }

  getAuthor(): Promise<ProviderResult<RawAuthor>> {
    return unsupported();
  }

  getSeries(): Promise<ProviderResult<RawSeries>> {
    return unsupported();
  }

  trending(): Promise<ProviderResult<RawWorkHit[]>> {
    return unsupported();
  }

  private keyParam(): string {
    const key = this.apiKey();
    return key ? `&key=${encodeURIComponent(key)}` : "";
  }
}

/** Google thumbnails are tiny and http; request https and a larger zoom. */
function cover(info: Record<string, unknown>): string | undefined {
  const links = asRecord(info.imageLinks);
  const url = asString(links?.thumbnail) ?? asString(links?.smallThumbnail);
  return url
    ?.replace(/^http:/, "https:")
    .replace(/&edge=curl/, "")
    .replace(/zoom=\d/, "zoom=1");
}

function identifiers(info: Record<string, unknown>): {
  isbn10?: string;
  isbn13?: string;
} {
  const ids = asArray(info.industryIdentifiers).map((i) => asRecord(i) ?? {});
  const find = (type: string) =>
    asString(ids.find((i) => i.type === type)?.identifier);
  const isbn13 = find("ISBN_13");
  const isbn10 = find("ISBN_10");
  return {
    isbn13: isbn13 && isValidIsbn13(isbn13) ? cleanIsbn(isbn13) : undefined,
    isbn10: isbn10 && isValidIsbn10(isbn10) ? cleanIsbn(isbn10) : undefined,
  };
}

/** Google descriptions contain HTML. */
function stripHtml(s: string | undefined): string | undefined {
  return s
    ?.replace(/<br\s*\/?>/gi, "\n")
    .replace(/<[^>]+>/g, "")
    .replace(/&amp;/g, "&")
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, "'")
    .trim();
}

function volumeToHit(v: unknown): RawWorkHit | undefined {
  const volume = asRecord(v);
  const id = asString(volume?.id);
  const info = asRecord(volume?.volumeInfo);
  const title = asString(info?.title);
  if (!id || !info || !title) return undefined;
  const { isbn10, isbn13 } = identifiers(info);
  return {
    ref: { provider: "googleBooks", externalId: id },
    title,
    subtitle: asString(info.subtitle),
    authors: asStrings(info.authors).map((name) => ({ name })),
    coverUrl: cover(info),
    firstPublishedYear: asNumber(asString(info.publishedDate)?.slice(0, 4)),
    pageCount: asNumber(info.pageCount),
    isbns: [isbn13, isbn10].filter((i): i is string => !!i),
  };
}

function volumeToWork(volume: Record<string, unknown>): RawWork | undefined {
  const hit = volumeToHit(volume);
  const info = asRecord(volume.volumeInfo);
  if (!hit || !info) return undefined;
  const { isbn10, isbn13 } = identifiers(info);
  const edition: RawEdition = {
    ref: hit.ref,
    title: hit.title,
    format:
      asString(asRecord(volume.saleInfo)?.isEbook) === "true"
        ? "ebook"
        : undefined,
    isbn10,
    isbn13,
    publisher: asString(info.publisher),
    publishedDate: asString(info.publishedDate),
    pageCount: asNumber(info.pageCount),
    language: asString(info.language),
    coverUrl: hit.coverUrl,
  };
  return {
    ref: hit.ref,
    title: hit.title,
    subtitle: hit.subtitle,
    authors: hit.authors,
    description: stripHtml(asString(info.description)),
    firstPublishedDate: asString(info.publishedDate),
    language: asString(info.language),
    genres: asStrings(info.categories)
      .flatMap((c) => c.split("/").map((p) => p.trim()))
      .slice(0, 8),
    coverUrl: hit.coverUrl,
    pageCount: asNumber(info.pageCount),
    editions: [edition],
    isbns: hit.isbns,
  };
}
