import { describe, expect, it } from "vitest";

import { TokenBucket } from "../rateLimiter";
import { fixtureFetch } from "../../../test/helpers/fixtures";
import { GoogleBooksProvider } from "./googleBooks";
import { HardcoverProvider } from "./hardcover";
import { OpenLibraryProvider } from "./openLibrary";

const signal = new AbortController().signal;
const page = { page: 1, pageSize: 20 };

describe("OpenLibraryProvider (live-recorded fixtures)", () => {
  const fetch = fixtureFetch([
    [/author_key%3AOL6761347A/, "openlibrary_author_search.json"],
    [/search\.json/, "openlibrary_search.json"],
    [/\/isbn\/9780349440842\.json/, "openlibrary_isbn.json"],
    [/\/works\/OL42430111W\/editions\.json/, "openlibrary_editions.json"],
    [/\/works\/OL42430111W\.json/, "openlibrary_work.json"],
    [/\/authors\/OL6761347A\.json/, "openlibrary_author.json"],
    [/trending\/weekly\.json/, "openlibrary_trending.json"],
  ]);
  const ol = new OpenLibraryProvider(fetch);

  it("maps search docs to hits with authors, covers and isbns", async () => {
    const res = await ol.search(
      { text: "the deal elle kennedy", field: "all" },
      page,
      signal,
    );
    expect(res.ok).toBe(true);
    if (!res.ok) return;
    const deal = res.data[0]!;
    expect(deal.ref).toEqual({
      provider: "openLibrary",
      externalId: "OL42430111W",
    });
    expect(deal.title).toBe("The Deal");
    expect(deal.authors[0]).toEqual({
      name: "Elle Kennedy",
      ref: { provider: "openLibrary", externalId: "OL6761347A" },
    });
    expect(deal.coverUrl).toMatch(
      /^https:\/\/covers\.openlibrary\.org\/b\/id\/\d+-M\.jpg$/,
    );
    expect(deal.isbns).toContain("9780349440842");
    expect(fetch.calls[0]).toContain("q=the%20deal%20elle%20kennedy");
  });

  it("uses field-specific search params", async () => {
    await ol.search({ text: "kennedy", field: "author" }, page, signal);
    expect(fetch.calls.at(-1)).toContain("author=kennedy");
  });

  it("looks up an ISBN and returns edition + full work", async () => {
    const res = await ol.lookupIsbn("9780349440842", signal);
    expect(res.ok).toBe(true);
    if (!res.ok) return;
    expect(res.data.isbn13).toBe("9780349440842");
    expect(res.data.pageCount).toBe(374);
    expect(res.data.format).toBe("paperback");
    expect(res.data.publisher).toBe("Little, Brown Book Group Limited");
    expect(res.data.work.title).toBe("The Deal");
    expect(res.data.work.authors[0]?.name).toBe("Elle Kennedy");
    expect(res.data.work.genres?.length).toBeGreaterThan(0);
    expect(res.data.work.series?.[0]?.name).toBe("Off-Campus");
    // Open Library has no series ids/positions.
    expect(res.data.work.series?.[0]?.ref).toBeUndefined();
  });

  it("maps an author with bio fallback and works", async () => {
    const res = await ol.getAuthor("OL6761347A", signal);
    expect(res.ok).toBe(true);
    if (!res.ok) return;
    expect(res.data.name).toBe("Elle Kennedy");
    // Most-edited works first, with covers (not recent translations).
    expect(res.data.works?.slice(0, 3).map((w) => w.title)).toEqual([
      "The Deal",
      "The Mistake",
      "Us",
    ]);
    expect(res.data.works?.[0]?.coverUrl).toMatch(/covers\.openlibrary\.org/);
    expect(res.data.bio ?? "").not.toMatch(/<a |\*Off-Campus\*/);
  });

  it("maps trending works", async () => {
    const res = await ol.trending(5, signal);
    expect(res.ok && res.data.length).toBeGreaterThan(0);
  });

  it("reports unknown ISBNs as notFound and has no series support", async () => {
    expect(await ol.lookupIsbn("9780000000002", signal)).toMatchObject({
      ok: false,
      error: "notFound",
    });
    expect(await ol.getSeries()).toMatchObject({
      ok: false,
      error: "unsupported",
    });
  });

  it("turns network errors into unavailable results instead of throwing", async () => {
    const broken = new OpenLibraryProvider(async () => {
      throw new Error("ECONNRESET");
    });
    expect(
      await broken.search({ text: "x", field: "all" }, page, signal),
    ).toMatchObject({ ok: false, error: "unavailable" });
  });
});

describe("GoogleBooksProvider (schema fixtures)", () => {
  const fetch = fixtureFetch([
    [/volumes\?q=isbn:9780349440842/, "googlebooks_isbn.json"],
  ]);

  it("is disabled without an API key", () => {
    expect(new GoogleBooksProvider(fetch, () => "").isEnabled()).toBe(false);
  });

  it("maps an exact ISBN hit, stripping HTML and upgrading cover URLs", async () => {
    const gb = new GoogleBooksProvider(fetch, () => "test-key");
    const res = await gb.lookupIsbn("9780349440842", signal);
    expect(res.ok).toBe(true);
    if (!res.ok) return;
    expect(res.data.isbn13).toBe("9780349440842");
    expect(res.data.pageCount).toBe(400);
    expect(res.data.work.description).not.toMatch(/<[^>]+>/);
    expect(res.data.work.coverUrl).toMatch(/^https:/);
    expect(res.data.work.coverUrl).not.toContain("edge=curl");
    expect(res.data.work.genres).toEqual([
      "Fiction",
      "Romance",
      "Contemporary",
    ]);
    expect(fetch.calls.at(-1)).toContain("key=test-key");
  });

  it("rejects near matches that do not contain the requested ISBN", async () => {
    const gb = new GoogleBooksProvider(
      fixtureFetch([[/volumes/, "googlebooks_isbn.json"]]),
      () => "k",
    );
    expect(await gb.lookupIsbn("9781522711858", signal)).toMatchObject({
      ok: false,
      error: "notFound",
    });
  });
});

describe("HardcoverProvider (schema fixtures)", () => {
  const routes = (file: string) =>
    fixtureFetch([[/api\.hardcover\.app/, file]]);

  it("is disabled without a token", () => {
    expect(
      new HardcoverProvider(
        routes("hardcover_search.json"),
        () => "",
        TokenBucket.perMinute(60),
      ).isEnabled(),
    ).toBe(false);
  });

  it("maps search hits including featured series position", async () => {
    const fetch = routes("hardcover_search.json");
    const hc = new HardcoverProvider(
      fetch,
      () => "tok",
      TokenBucket.perMinute(60),
    );
    const res = await hc.search(
      { text: "the deal", field: "series" },
      page,
      signal,
    );
    expect(res.ok).toBe(true);
    if (!res.ok) return;
    expect(res.data[0]).toMatchObject({
      title: "The Deal",
      seriesName: "Off-Campus",
      seriesPosition: 1,
      pageCount: 390,
    });
    const body = JSON.parse(fetch.bodies[0]!);
    expect(body.variables.fields).toBe("series_names");
  });

  it.each([
    ["title", "title,alternative_titles", "1,1", "5,5"],
    ["author", "author_names", "1", "5"],
    ["isbn", "isbns", "1", "0"],
    ["series", "series_names", "1", "5"],
  ] as const)(
    "sends one typos value per field when searching by %s",
    async (field, fields, weights, typos) => {
      let body = "";
      const hc = new HardcoverProvider(
        async (_url, init) => {
          body = String(init.body);
          return {
            status: 200,
            json: { data: { search: { results: { hits: [] } } } },
          };
        },
        () => "tok",
        TokenBucket.perMinute(60),
      );
      const res = await hc.search({ text: "x", field }, page, signal);
      expect(res.ok).toBe(true);
      const sent = JSON.parse(body);
      expect(sent.variables).toMatchObject({ fields, weights, typos });
      expect(sent.query).toContain("typos: $typos");
    },
  );

  it("treats a search with no hits list as failed, not as nothing found", async () => {
    // What Hardcover really returned when the typos count didn't match.
    const hc = new HardcoverProvider(
      async () => ({
        status: 200,
        json: { data: { search: { results: null } } },
      }),
      () => "tok",
      TokenBucket.perMinute(60),
    );
    const res = await hc.search({ text: "x", field: "series" }, page, signal);
    expect(res.ok).toBe(false);
    if (res.ok) return;
    // Not "notFound", which the circuit breaker counts as healthy.
    expect(res.error).toBe("invalid");
  });

  it("sends a Bearer token exactly once", async () => {
    let auth = "";
    const hc = new HardcoverProvider(
      async (_url, init) => {
        auth = init.headers?.Authorization ?? "";
        return {
          status: 200,
          json: { data: { search: { results: { hits: [] } } } },
        };
      },
      () => "Bearer abc",
      TokenBucket.perMinute(60),
    );
    await hc.search({ text: "x", field: "all" }, page, signal);
    expect(auth).toBe("Bearer abc");
  });

  it("maps an ISBN lookup with series id and position", async () => {
    const hc = new HardcoverProvider(
      routes("hardcover_isbn.json"),
      () => "tok",
      TokenBucket.perMinute(60),
    );
    const res = await hc.lookupIsbn("9780349440842", signal);
    expect(res.ok).toBe(true);
    if (!res.ok) return;
    expect(res.data.pageCount).toBe(374);
    expect(res.data.publisher).toBe("Piatkus");
    expect(res.data.work.series?.[0]).toEqual({
      name: "Off-Campus",
      ref: { provider: "hardcover", externalId: "9001" },
      position: 1,
      isPrimary: true,
    });
  });

  it("maps a series in reading order, marking novellas and unnumbered entries non-primary", async () => {
    const hc = new HardcoverProvider(
      routes("hardcover_series.json"),
      () => "tok",
      TokenBucket.perMinute(60),
    );
    const res = await hc.getSeries("9001", signal);
    expect(res.ok).toBe(true);
    if (!res.ok) return;
    expect(res.data.entries.map((e) => [e.work.title, e.isPrimary])).toEqual([
      ["The Deal", true],
      ["The Deal: Bonus Scenes", false],
      ["The Mistake", true],
      ["Off-Campus Box Set", false],
    ]);
  });

  it("asks for one book per position and lists companions last", async () => {
    const entry = (position: number, id: number, title: string) => ({
      position,
      book: { id, title },
    });
    const fetchSeries = fixtureFetch([
      [
        /hardcover/,
        {
          status: 200,
          json: {
            data: {
              series: [
                {
                  id: 1,
                  name: "Dune",
                  book_series: [
                    entry(0, 9, "The Road to Dune"),
                    entry(1, 1, "Dune"),
                    entry(1.5, 5, "A Novella"),
                    entry(2, 2, "Dune Messiah"),
                  ],
                },
              ],
            },
          },
        },
      ],
    ]);
    const hc = new HardcoverProvider(
      fetchSeries,
      () => "tok",
      TokenBucket.perMinute(60),
    );
    const res = await hc.getSeries("1", signal);
    expect(res.ok).toBe(true);
    if (!res.ok) return;
    expect(res.data.entries.map((e) => [e.work.title, e.isPrimary])).toEqual([
      ["Dune", true],
      ["A Novella", false],
      ["Dune Messiah", true],
      ["The Road to Dune", false],
    ]);
    for (const part of [
      "distinct_on: position",
      "canonical_id",
      "is_partial_book",
      "compilation",
    ])
      expect(fetchSeries.bodies[0]).toContain(part);
  });

  it("stops calling when the local budget is exhausted", async () => {
    const fetch = routes("hardcover_search.json");
    const hc = new HardcoverProvider(
      fetch,
      () => "tok",
      TokenBucket.perMinute(1, () => 0),
    );
    await hc.search({ text: "a", field: "all" }, page, signal);
    const second = await hc.search({ text: "b", field: "all" }, page, signal);
    expect(second).toMatchObject({ ok: false, error: "rateLimited" });
    expect(fetch.calls).toHaveLength(1);
  });

  it("surfaces GraphQL errors as invalid", async () => {
    const hc = new HardcoverProvider(
      async () => ({
        status: 200,
        json: { errors: [{ message: 'field "x" not found' }] },
      }),
      () => "tok",
      TokenBucket.perMinute(60),
    );
    expect(await hc.getWork("1", signal)).toMatchObject({
      ok: false,
      error: "invalid",
    });
  });
});
