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
import { cleanIsbn, isbn13To10, isValidIsbn10, isValidIsbn13 } from "../isbn";
import type { TokenBucket } from "../rateLimiter";
import type {
  EditionFormat,
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
import type {
  BookMetadataProvider,
  ProviderCapability,
} from "./BookMetadataProvider";

const ENDPOINT = "https://api.hardcover.app/v1/graphql";

/**
 * Hardcover GraphQL provider (docs/04 §1.5).
 *
 * Constraints: backend-only token, 60 requests/minute, tokens expire every
 * January 1st, API "heavily in flux". The provider is disabled when no token
 * is configured, and every call spends a token from [budget] so we never
 * exceed the shared rate limit.
 *
 * Query shapes follow the public docs (searching + getting book details,
 * checked 2026-11-04). They have NOT been verified against the live API yet
 * because no token is available (SPIKE-88083021); mappers are defensive.
 */
export class HardcoverProvider implements BookMetadataProvider {
  readonly id = "hardcover" as const;
  readonly capabilities: ReadonlySet<ProviderCapability> = new Set([
    "search",
    "lookupIsbn",
    "work",
    "author",
    "series",
  ]);
  readonly searchFields: ReadonlySet<SearchField> = new Set([
    "all",
    "title",
    "author",
    "isbn",
    "series",
  ]);

  constructor(
    private readonly fetchJson: FetchJson,
    private readonly token: () => string,
    private readonly budget: TokenBucket,
  ) {}

  isEnabled(): boolean {
    return this.token().length > 0;
  }

  async search(
    query: SearchQuery,
    page: Page,
    signal: AbortSignal,
  ): Promise<ProviderResult<RawWorkHit[]>> {
    // `typos` needs one value per field, or Hardcover answers 200 with no
    // results at all. It defaults to five, one for each of its default fields.
    const narrowed: Record<
      SearchField,
      { fields: string; typos: string } | undefined
    > = {
      all: undefined,
      title: { fields: "title,alternative_titles", typos: "5,5" },
      author: { fields: "author_names", typos: "5" },
      isbn: { fields: "isbns", typos: "0" },
      series: { fields: "series_names", typos: "5" },
      publisher: undefined,
    };
    const field = narrowed[query.field];
    const result = await this.graphql(
      `query Search($q: String!, $perPage: Int!, $page: Int!${field ? ", $fields: String!, $weights: String!, $typos: String!" : ""}) {
        search(query: $q, query_type: "Book", per_page: $perPage, page: $page${field ? ", fields: $fields, weights: $weights, typos: $typos" : ""}) { results }
      }`,
      {
        q: query.text,
        perPage: page.pageSize,
        page: page.page,
        ...(field
          ? {
              fields: field.fields,
              weights: field.fields
                .split(",")
                .map(() => "1")
                .join(","),
              typos: field.typos,
            }
          : {}),
      },
      signal,
      (data) => {
        const results = asRecord(asRecord(data.search)?.results);
        // No hits list means the search failed, which isn't "nothing found".
        if (!Array.isArray(results?.hits)) return undefined;
        return asArray(results.hits)
          .map((h) => searchDocToHit(asRecord(asRecord(h)?.document)))
          .filter((h): h is RawWorkHit => h !== undefined);
      },
    );
    // A search answers with a hits list, even an empty one. Without one it's an
    // outage for the circuit breaker, which treats "notFound" as healthy.
    return !result.ok && result.error === "notFound"
      ? fail("invalid", "search response had no hits list")
      : result;
  }

  lookupIsbn(
    isbn13: string,
    signal: AbortSignal,
  ): Promise<ProviderResult<RawEdition & { work: RawWork }>> {
    return this.graphql(
      `query ByIsbn($isbn13: String!, $isbn10: String!) {
        editions(where: {_or: [{isbn_13: {_eq: $isbn13}}, {isbn_10: {_eq: $isbn10}}]}, limit: 1) {
          ${EDITION_FIELDS}
          book { ${BOOK_FIELDS} }
        }
      }`,
      { isbn13, isbn10: isbn13To10(isbn13) ?? "" },
      signal,
      (data) => {
        const e = asRecord(asArray(data.editions)[0]);
        const edition = e ? editionFromJson(e) : undefined;
        const work = bookFromJson(asRecord(e?.book));
        return edition && work
          ? { ...edition, workRef: work.ref, work }
          : undefined;
      },
    );
  }

  getWork(
    externalId: string,
    signal: AbortSignal,
  ): Promise<ProviderResult<RawWork>> {
    const id = Number(externalId);
    if (!Number.isInteger(id)) return Promise.resolve(fail("invalid"));
    return this.graphql(
      `query Book($id: Int!) {
        books(where: {id: {_eq: $id}}, limit: 1) {
          ${BOOK_FIELDS}
          editions(order_by: {users_count: desc}, limit: 25) { ${EDITION_FIELDS} }
        }
      }`,
      { id },
      signal,
      (data) => bookFromJson(asRecord(asArray(data.books)[0])),
    );
  }

  getAuthor(
    externalId: string,
    signal: AbortSignal,
  ): Promise<ProviderResult<RawAuthor>> {
    const id = Number(externalId);
    if (!Number.isInteger(id)) return Promise.resolve(fail("invalid"));
    return this.graphql(
      `query Author($id: Int!) {
        authors(where: {id: {_eq: $id}}, limit: 1) {
          id name bio image { url }
          contributions(limit: 40) { book { id title release_year image { url } } }
        }
      }`,
      { id },
      signal,
      (data) => {
        const a = asRecord(asArray(data.authors)[0]);
        const name = asString(a?.name);
        if (!a || !name) return undefined;
        const ref = { provider: "hardcover" as const, externalId };
        return {
          ref,
          name,
          bio: asString(a.bio),
          photoUrl: asString(asRecord(a.image)?.url),
          photoCredit: asString(asRecord(a.image)?.url)
            ? "Hardcover"
            : undefined,
          works: asArray(a.contributions)
            .map((c) => {
              const b = asRecord(asRecord(c)?.book);
              const bid = asNumber(b?.id);
              const title = asString(b?.title);
              if (!b || bid === undefined || !title) return undefined;
              const hit: RawWorkHit = {
                ref: { provider: "hardcover", externalId: String(bid) },
                title,
                authors: [{ name, ref }],
                coverUrl: asString(asRecord(b.image)?.url),
                firstPublishedYear: asNumber(b.release_year),
              };
              return hit;
            })
            .filter((h): h is RawWorkHit => h !== undefined),
        } satisfies RawAuthor;
      },
    );
  }

  getSeries(
    externalId: string,
    signal: AbortSignal,
  ): Promise<ProviderResult<RawSeries>> {
    const id = Number(externalId);
    if (!Number.isInteger(id)) return Promise.resolve(fail("invalid"));
    return this.graphql(
      `query Series($id: Int!) {
        series(where: {id: {_eq: $id}}, limit: 1) {
          id name
          book_series(order_by: {position: asc_nulls_last}) {
            position
            book { id title release_year image { url } contributions(limit: 3) { author { id name } } }
          }
        }
      }`,
      { id },
      signal,
      (data) => {
        const s = asRecord(asArray(data.series)[0]);
        const name = asString(s?.name);
        if (!s || !name) return undefined;
        return {
          ref: { provider: "hardcover", externalId },
          name,
          entries: asArray(s.book_series)
            .map((bs) => {
              const rec = asRecord(bs);
              const b = asRecord(rec?.book);
              const bid = asNumber(b?.id);
              const title = asString(b?.title);
              if (!rec || !b || bid === undefined || !title) return undefined;
              const position = asNumber(rec.position);
              return {
                work: {
                  ref: {
                    provider: "hardcover" as const,
                    externalId: String(bid),
                  },
                  title,
                  authors: authorsFrom(b.contributions),
                  coverUrl: asString(asRecord(b.image)?.url),
                  firstPublishedYear: asNumber(b.release_year),
                },
                position,
                positionLabel:
                  position === undefined ? undefined : String(position),
                // Integer positions are main entries; 1.5 etc. are novellas.
                isPrimary: position !== undefined && Number.isInteger(position),
              };
            })
            .filter((e): e is NonNullable<typeof e> => e !== undefined),
        } satisfies RawSeries;
      },
    );
  }

  trending(): Promise<ProviderResult<RawWorkHit[]>> {
    return Promise.resolve(fail("unsupported"));
  }

  private graphql<T>(
    query: string,
    variables: Record<string, unknown>,
    signal: AbortSignal,
    map: (data: Record<string, unknown>) => T | undefined,
  ): Promise<ProviderResult<T>> {
    return guard(async () => {
      if (!this.isEnabled()) return fail("unsupported", "no token configured");
      if (!this.budget.tryTake())
        return fail("rateLimited", "local budget exhausted");
      const token = this.token();
      const res = await this.fetchJson(ENDPOINT, {
        method: "POST",
        signal,
        headers: {
          "Content-Type": "application/json",
          Authorization: token.startsWith("Bearer ")
            ? token
            : `Bearer ${token}`,
        },
        body: JSON.stringify({ query, variables }),
      });
      if (res.status !== 200) return fail(statusToError(res.status));
      const body = asRecord(res.json);
      if (asArray(body?.errors).length > 0) {
        return fail(
          "invalid",
          asString(asRecord(asArray(body?.errors)[0])?.message),
        );
      }
      const data = asRecord(body?.data);
      const mapped = data ? map(data) : undefined;
      return mapped === undefined ? fail("notFound") : ok(mapped);
    });
  }
}

const EDITION_FIELDS = `id isbn_10 isbn_13 pages audio_seconds release_date edition_format title
  publisher { name } image { url }`;

const BOOK_FIELDS = `id title subtitle description release_date pages
  image { url }
  contributions(limit: 5) { author { id name } }
  book_series { position series { id name } }`;

function formatFrom(
  raw: string | undefined,
  audioSeconds: number | undefined,
): EditionFormat | undefined {
  if (audioSeconds && audioSeconds > 0)
    return raw?.toLowerCase().includes("audible") ? "audible" : "audiobook";
  if (!raw) return undefined;
  const f = raw.toLowerCase();
  if (f.includes("kindle")) return "kindle";
  if (f.includes("epub")) return "epub";
  if (f.includes("ebook") || f.includes("e-book") || f.includes("digital"))
    return "ebook";
  if (f.includes("mass market")) return "massMarket";
  if (f.includes("paper")) return "paperback";
  if (f.includes("hard")) return "hardcover";
  if (f.includes("audio")) return "audiobook";
  return "other";
}

function authorsFrom(contributions: unknown) {
  return asArray(contributions)
    .map((c) => asRecord(asRecord(c)?.author))
    .map((a) => {
      const name = asString(a?.name);
      const id = asNumber(a?.id);
      return name
        ? {
            name,
            ref:
              id !== undefined
                ? { provider: "hardcover" as const, externalId: String(id) }
                : undefined,
          }
        : undefined;
    })
    .filter((a): a is NonNullable<typeof a> => a !== undefined);
}

function editionFromJson(e: Record<string, unknown>): RawEdition | undefined {
  const id = asNumber(e.id);
  if (id === undefined) return undefined;
  const isbn13 = asString(e.isbn_13);
  const isbn10 = asString(e.isbn_10);
  const audio = asNumber(e.audio_seconds);
  return {
    ref: { provider: "hardcover", externalId: String(id) },
    title: asString(e.title),
    format: formatFrom(asString(e.edition_format), audio),
    isbn13: isbn13 && isValidIsbn13(isbn13) ? cleanIsbn(isbn13) : undefined,
    isbn10: isbn10 && isValidIsbn10(isbn10) ? cleanIsbn(isbn10) : undefined,
    publisher: asString(asRecord(e.publisher)?.name),
    publishedDate: asString(e.release_date),
    pageCount: asNumber(e.pages),
    audioDurationSec: audio,
    coverUrl: asString(asRecord(e.image)?.url),
  };
}

function bookFromJson(
  b: Record<string, unknown> | undefined,
): RawWork | undefined {
  const id = asNumber(b?.id);
  const title = asString(b?.title);
  if (!b || id === undefined || !title) return undefined;
  const editions = asArray(b.editions)
    .map((e) => editionFromJson(asRecord(e) ?? {}))
    .filter((e): e is RawEdition => e !== undefined);
  return {
    ref: { provider: "hardcover", externalId: String(id) },
    title,
    subtitle: asString(b.subtitle),
    authors: authorsFrom(b.contributions),
    description: asString(b.description),
    firstPublishedDate: asString(b.release_date),
    coverUrl: asString(asRecord(b.image)?.url),
    pageCount: asNumber(b.pages),
    series: asArray(b.book_series)
      .map((bs) => {
        const rec = asRecord(bs);
        const series = asRecord(rec?.series);
        const name = asString(series?.name);
        const sid = asNumber(series?.id);
        const position = asNumber(rec?.position);
        return name
          ? {
              name,
              ref:
                sid !== undefined
                  ? { provider: "hardcover" as const, externalId: String(sid) }
                  : undefined,
              position,
              isPrimary: position !== undefined && Number.isInteger(position),
            }
          : undefined;
      })
      .filter((s): s is NonNullable<typeof s> => s !== undefined),
    editions,
    isbns: editions
      .flatMap((e) => [e.isbn13, e.isbn10])
      .filter((i): i is string => !!i),
  };
}

function searchDocToHit(
  doc: Record<string, unknown> | undefined,
): RawWorkHit | undefined {
  const id = asNumber(doc?.id);
  const title = asString(doc?.title);
  if (!doc || id === undefined || !title) return undefined;
  const featured = asRecord(doc.featured_series);
  const seriesName =
    asString(asRecord(featured?.series)?.name) ??
    asString(featured?.name) ??
    asStrings(doc.series_names)[0];
  return {
    ref: { provider: "hardcover", externalId: String(id) },
    title,
    subtitle: asString(doc.subtitle),
    authors: asStrings(doc.author_names).map((name) => ({ name })),
    coverUrl: asString(asRecord(doc.image)?.url),
    firstPublishedYear: asNumber(doc.release_year),
    seriesName,
    seriesPosition:
      asNumber(doc.featured_series_position) ?? asNumber(featured?.position),
    pageCount: asNumber(doc.pages),
    isbns: asStrings(doc.isbns).slice(0, 20),
  };
}
