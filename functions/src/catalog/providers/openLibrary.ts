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
import { cleanDescription as cleanText } from "../merge";
import type {
  EditionFormat,
  Page,
  ProviderResult,
  RawAuthor,
  RawAuthorRef,
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

const BASE = "https://openlibrary.org";
const COVERS = "https://covers.openlibrary.org";
const SEARCH_FIELDS =
  "key,title,subtitle,author_name,author_key,first_publish_year,isbn,cover_i,number_of_pages_median";

/** `/works/OL1W` → `OL1W`. */
const olId = (key: string | undefined): string | undefined =>
  key?.split("/").filter(Boolean).pop();

/** Cover by cover id (not by ISBN — that endpoint is IP rate-limited, docs/04 §1.5). */
const coverUrl = (id: number | undefined, size: "M" | "L" = "L") =>
  id !== undefined && id > 0 ? `${COVERS}/b/id/${id}-${size}.jpg` : undefined;

/** Open Library text fields are either a string or `{type, value}`. */
const textValue = (v: unknown): string | undefined =>
  asString(v) ?? asString(asRecord(v)?.value);

const languageCode = (v: unknown): string | undefined =>
  olId(asString(asRecord(asArray(v)[0])?.key));

function formatFrom(physical: string | undefined): EditionFormat | undefined {
  if (!physical) return undefined;
  const p = physical.toLowerCase();
  if (p.includes("mass market")) return "massMarket";
  if (p.includes("paper")) return "paperback";
  if (p.includes("hard")) return "hardcover";
  if (p.includes("audio")) return "audiobook";
  if (p.includes("ebook") || p.includes("electronic")) return "ebook";
  return "other";
}

export class OpenLibraryProvider implements BookMetadataProvider {
  readonly id = "openLibrary" as const;
  readonly capabilities: ReadonlySet<ProviderCapability> = new Set([
    "search",
    "lookupIsbn",
    "work",
    "author",
    "trending",
  ]);
  readonly searchFields: ReadonlySet<SearchField> = new Set([
    "all",
    "title",
    "author",
    "isbn",
    "publisher",
  ]);

  constructor(private readonly fetchJson: FetchJson) {}

  isEnabled(): boolean {
    return true;
  }

  search(
    query: SearchQuery,
    page: Page,
    signal: AbortSignal,
  ): Promise<ProviderResult<RawWorkHit[]>> {
    return guard(async () => {
      const param =
        query.field === "all" || query.field === "series" ? "q" : query.field;
      const url =
        `${BASE}/search.json?${param}=${encodeURIComponent(query.text)}` +
        `&fields=${SEARCH_FIELDS}&page=${page.page}&limit=${page.pageSize}`;
      const res = await this.fetchJson(url, { signal });
      if (res.status !== 200) return fail(statusToError(res.status));
      return ok(
        asArray(asRecord(res.json)?.docs).map(searchDocToHit).filter(isHit),
      );
    });
  }

  lookupIsbn(
    isbn13: string,
    signal: AbortSignal,
  ): Promise<ProviderResult<RawEdition & { work: RawWork }>> {
    return guard(async () => {
      const res = await this.fetchJson(`${BASE}/isbn/${isbn13}.json`, {
        signal,
      });
      if (res.status !== 200) return fail(statusToError(res.status));
      const edition = editionFromJson(asRecord(res.json) ?? {});
      if (!edition || !edition.workRef) return fail("notFound");
      const work = await this.getWork(edition.workRef.externalId, signal);
      if (!work.ok) return work;
      return ok({ ...edition, work: work.data });
    });
  }

  getWork(
    externalId: string,
    signal: AbortSignal,
  ): Promise<ProviderResult<RawWork>> {
    return guard(async () => {
      const res = await this.fetchJson(`${BASE}/works/${externalId}.json`, {
        signal,
      });
      if (res.status !== 200) return fail(statusToError(res.status));
      const json = asRecord(res.json) ?? {};
      const title = asString(json.title);
      if (!title) return fail("invalid", "work without title");

      const authorKeys = asArray(json.authors)
        .map((a) => olId(asString(asRecord(asRecord(a)?.author)?.key)))
        .filter((k): k is string => k !== undefined)
        .slice(0, 5);
      const [authorNames, editionsRes] = await Promise.all([
        Promise.all(authorKeys.map((k) => this.authorName(k, signal))),
        this.fetchJson(`${BASE}/works/${externalId}/editions.json?limit=25`, {
          signal,
        }),
      ]);
      const authors: RawAuthorRef[] = authorKeys.map((k, i) => ({
        name: authorNames[i] ?? "Unknown author",
        ref: { provider: "openLibrary", externalId: k },
      }));
      const editions =
        editionsRes.status === 200
          ? asArray(asRecord(editionsRes.json)?.entries)
              .map((e) => editionFromJson(asRecord(e) ?? {}))
              .filter((e): e is RawEdition => e !== undefined)
          : [];
      // Open Library only knows series *names* (on editions), never ids or positions.
      const seriesName =
        editionsRes.status === 200
          ? asArray(asRecord(editionsRes.json)?.entries).flatMap((e) =>
              asStrings(asRecord(e)?.series),
            )[0]
          : undefined;

      const work: RawWork = {
        ref: { provider: "openLibrary", externalId },
        title,
        subtitle: asString(json.subtitle),
        authors,
        description: textValue(json.description),
        firstPublishedDate: asString(json.first_publish_date),
        genres: asStrings(json.subjects).slice(0, 8),
        series: seriesName
          ? [{ name: cleanSeriesName(seriesName) }]
          : undefined,
        coverUrl: coverUrl(asNumber(asArray(json.covers)[0])),
        editions,
        isbns: editions
          .flatMap((e) => [e.isbn13, e.isbn10])
          .filter((i): i is string => !!i),
      };
      return ok(work);
    });
  }

  getAuthor(
    externalId: string,
    signal: AbortSignal,
  ): Promise<ProviderResult<RawAuthor>> {
    return guard(async () => {
      // Works via search sorted by edition count: /authors/{id}/works.json is
      // ordered by recency and returns translations without covers first.
      const [authorRes, worksRes] = await Promise.all([
        this.fetchJson(`${BASE}/authors/${externalId}.json`, { signal }),
        this.fetchJson(
          `${BASE}/search.json?q=${encodeURIComponent(`author_key:${externalId}`)}` +
            `&sort=editions&limit=30&fields=${SEARCH_FIELDS}`,
          { signal },
        ),
      ]);
      if (authorRes.status !== 200)
        return fail(statusToError(authorRes.status));
      const json = asRecord(authorRes.json) ?? {};
      const name = asString(json.name);
      if (!name) return fail("invalid", "author without name");
      const photoId = asNumber(asArray(json.photos)[0]);
      const works =
        worksRes.status === 200
          ? asArray(asRecord(worksRes.json)?.docs)
              .map(searchDocToHit)
              .filter(isHit)
          : [];
      return ok({
        ref: { provider: "openLibrary", externalId },
        name,
        bio: cleanText(textValue(json.bio)),
        photoUrl:
          photoId && photoId > 0
            ? `${COVERS}/a/id/${photoId}-M.jpg`
            : undefined,
        photoCredit: photoId && photoId > 0 ? "Open Library" : undefined,
        birthDate: asString(json.birth_date),
        deathDate: asString(json.death_date),
        works,
      });
    });
  }

  getSeries(): Promise<ProviderResult<RawSeries>> {
    // Open Library has series names on editions but no series entity or positions.
    return unsupported();
  }

  trending(
    limit: number,
    signal: AbortSignal,
  ): Promise<ProviderResult<RawWorkHit[]>> {
    return guard(async () => {
      const res = await this.fetchJson(
        `${BASE}/trending/weekly.json?limit=${limit}`,
        { signal },
      );
      if (res.status !== 200) return fail(statusToError(res.status));
      return ok(
        asArray(asRecord(res.json)?.works).map(searchDocToHit).filter(isHit),
      );
    });
  }

  private async authorName(
    key: string,
    signal: AbortSignal,
  ): Promise<string | undefined> {
    try {
      const res = await this.fetchJson(`${BASE}/authors/${key}.json`, {
        signal,
      });
      return res.status === 200
        ? asString(asRecord(res.json)?.name)
        : undefined;
    } catch {
      return undefined;
    }
  }
}

const isHit = (h: RawWorkHit | undefined): h is RawWorkHit => h !== undefined;

/** "Off-Campus ; 1" or "Off-Campus #1" → "Off-Campus". */
function cleanSeriesName(raw: string): string {
  return raw.replace(/\s*[;#(].*$/, "").trim() || raw.trim();
}

function searchDocToHit(doc: unknown): RawWorkHit | undefined {
  const d = asRecord(doc);
  if (!d) return undefined;
  const id = olId(asString(d.key));
  const title = asString(d.title);
  if (!id || !title) return undefined;
  const names = asStrings(d.author_name);
  const keys = asStrings(d.author_key);
  return {
    ref: { provider: "openLibrary", externalId: id },
    title,
    subtitle: asString(d.subtitle),
    authors: names.map((name, i) => ({
      name,
      ref: keys[i]
        ? { provider: "openLibrary" as const, externalId: keys[i]! }
        : undefined,
    })),
    coverUrl: coverUrl(asNumber(d.cover_i), "M"),
    firstPublishedYear: asNumber(d.first_publish_year),
    pageCount: asNumber(d.number_of_pages_median),
    isbns: asStrings(d.isbn).slice(0, 20),
  };
}

function editionFromJson(e: Record<string, unknown>): RawEdition | undefined {
  const id = olId(asString(e.key));
  if (!id) return undefined;
  const isbn13 = asStrings(e.isbn_13).map(cleanIsbn).find(isValidIsbn13);
  const isbn10 = asStrings(e.isbn_10).map(cleanIsbn).find(isValidIsbn10);
  const workId = olId(asString(asRecord(asArray(e.works)[0])?.key));
  const pages =
    asNumber(e.number_of_pages) ??
    asNumber(asString(e.pagination)?.match(/\d+/)?.[0]);
  return {
    ref: { provider: "openLibrary", externalId: id },
    workRef: workId
      ? { provider: "openLibrary", externalId: workId }
      : undefined,
    title: asString(e.title),
    format: formatFrom(asString(e.physical_format)),
    isbn10,
    isbn13,
    publisher: asStrings(e.publishers)[0],
    publishedDate: asString(e.publish_date),
    pageCount: pages,
    language: languageCode(e.languages),
    coverUrl: coverUrl(asNumber(asArray(e.covers)[0])),
  };
}
