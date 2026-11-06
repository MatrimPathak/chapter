import { beforeEach, describe, expect, it } from "vitest";

import { fixtureFetch } from "../../test/helpers/fixtures";
import { MetadataOrchestrator } from "./orchestrator";
import { GoogleBooksProvider } from "./providers/googleBooks";
import { HardcoverProvider } from "./providers/hardcover";
import { OpenLibraryProvider } from "./providers/openLibrary";
import { TokenBucket } from "./rateLimiter";
import { CatalogError, CatalogService, RATE_LIMITS } from "./service";
import { MemoryCatalogStore } from "./store";

const OL_ROUTES = [
  [/author_key%3AOL6761347A/, "openlibrary_author_search.json"],
  [/search\.json/, "openlibrary_search.json"],
  [/\/isbn\/9780349440842\.json/, "openlibrary_isbn.json"],
  [/\/works\/OL42430111W\/editions\.json/, "openlibrary_editions.json"],
  [/\/works\/OL42430111W\.json/, "openlibrary_work.json"],
  [/\/authors\/OL6761347A\.json/, "openlibrary_author.json"],
  [/trending\/weekly\.json/, "openlibrary_trending.json"],
] as const;

function build({ hardcover = false, google = false } = {}) {
  let clock = new Date("2026-11-04T10:00:00Z");
  const fetch = fixtureFetch([
    ...OL_ROUTES.map(([re, f]) => [re, f] as [RegExp, string]),
    [/googleapis.*isbn:9780349440842/, "googlebooks_isbn.json"],
    [/api\.hardcover\.app/, "hardcover_isbn.json"],
  ]);
  const store = new MemoryCatalogStore();
  const orchestrator = new MetadataOrchestrator([
    new HardcoverProvider(
      fetch,
      () => (hardcover ? "tok" : ""),
      TokenBucket.perMinute(60),
    ),
    new OpenLibraryProvider(fetch),
    new GoogleBooksProvider(fetch, () => (google ? "key" : "")),
  ]);
  const service = new CatalogService(orchestrator, store, () => clock);
  return {
    service,
    store,
    fetch,
    advance: (ms: number) => (clock = new Date(clock.getTime() + ms)),
  };
}

describe("CatalogService", () => {
  let env: ReturnType<typeof build>;
  beforeEach(() => {
    env = build();
  });

  it("searches with Hardcover disabled and caches the response", async () => {
    const first = await env.service.search(
      "u1",
      { text: "the deal elle kennedy", field: "all" },
      { page: 1, pageSize: 20 },
    );
    expect(first.provider).toBe("openLibrary");
    expect(first.results[0]?.title).toBe("The Deal");
    const calls = env.fetch.calls.length;
    await env.service.search(
      "u2",
      { text: "The Deal  Elle Kennedy", field: "all" },
      { page: 1, pageSize: 20 },
    );
    expect(env.fetch.calls.length).toBe(calls); // normalized query hit the cache
  });

  it("treats an ISBN typed into search as an exact lookup", async () => {
    const res = await env.service.search(
      "u1",
      { text: "0-349-44084-0", field: "all" },
      { page: 1, pageSize: 20 },
    );
    expect(res.results).toHaveLength(1);
    expect(res.results[0]?.id).toBeTruthy();
  });

  it("looks up an ISBN, persists the work and reuses it on the next lookup", async () => {
    const a = await env.service.lookupIsbn("u1", "9780349440842");
    expect(a.work.title).toBe("The Deal");
    expect(a.editionId).toBeTruthy();
    expect(a.work.pageCount).toBe(374); // ISBN-matched edition
    expect(env.store.isbnIndex.get("9780349440842")?.workId).toBe(a.work.id);
    const calls = env.fetch.calls.length;
    const b = await env.service.lookupIsbn("u1", "0349440840");
    expect(b.work.id).toBe(a.work.id);
    expect(env.fetch.calls.length).toBe(calls); // fresh catalog hit, no provider calls
  });

  it("merges Hardcover series data with Open Library fields when Hardcover is enabled", async () => {
    env = build({ hardcover: true, google: true });
    const { work } = await env.service.lookupIsbn("u1", "9780349440842");
    expect(work.series[0]).toMatchObject({
      name: "Off-Campus",
      position: 1,
      isPrimary: true,
    });
    expect(work.series[0]?.seriesId).toBeTruthy();
    expect(work.provenance.series?.provider).toBe("hardcover");
    expect(Object.keys(work.providerIds).sort()).toEqual([
      "googleBooks",
      "hardcover",
      "openLibrary",
    ]);
    // Author and series stubs were created for later detail screens.
    expect(env.store.series.get(work.series[0]!.seriesId!)?.name).toBe(
      "Off-Campus",
    );
  });

  it("resolves the same work from a search ref and an ISBN (hard identifiers only)", async () => {
    const fromIsbn = await env.service.lookupIsbn("u1", "9780349440842");
    const fromRef = await env.service.getWork("u1", {
      ref: { provider: "openLibrary", externalId: "OL42430111W" },
    });
    expect(fromRef.work.id).toBe(fromIsbn.work.id);
    expect(env.store.works.size).toBe(1);
  });

  it("never merges works by fuzzy title match", async () => {
    await env.service.lookupIsbn("u1", "9780349440842");
    // A different work with the same title but no shared identifiers.
    env.store.refIndex.delete("openLibrary:OL42430111W");
    env.store.isbnIndex.clear();
    const other = await env.service.getWork("u1", {
      ref: { provider: "openLibrary", externalId: "OL42430111W" },
    });
    expect(env.store.works.size).toBe(2);
    expect(other.work.title).toBe("The Deal");
  });

  it("serves stale catalog data when every provider is down", async () => {
    const { work } = await env.service.lookupIsbn("u1", "9780349440842");
    env.advance(31 * 86_400_000);
    env.fetch.calls.length = 0;
    const broken = new CatalogService(
      new MetadataOrchestrator([]),
      env.store,
      () => new Date("2027-01-01"),
    );
    const again = await broken.getWork("u1", { workId: work.id });
    expect(again.work.id).toBe(work.id);
  });

  it("rejects invalid input and unknown ISBNs with typed errors", async () => {
    await expect(env.service.lookupIsbn("u1", "123")).rejects.toMatchObject({
      code: "invalid-argument",
    });
    await expect(
      env.service.lookupIsbn("u1", "9780000000002"),
    ).rejects.toBeInstanceOf(CatalogError);
    await expect(
      env.service.search(
        "u1",
        { text: "a", field: "all" },
        { page: 1, pageSize: 10 },
      ),
    ).rejects.toMatchObject({
      code: "invalid-argument",
    });
  });

  it("rate-limits per user and action", async () => {
    for (let i = 0; i < RATE_LIMITS.isbn; i++)
      await env.service.lookupIsbn("u1", "9780349440842");
    await expect(
      env.service.lookupIsbn("u1", "9780349440842"),
    ).rejects.toMatchObject({ code: "resource-exhausted" });
    await expect(
      env.service.lookupIsbn("u2", "9780349440842"),
    ).resolves.toBeTruthy();
    env.advance(60_000);
    await expect(
      env.service.lookupIsbn("u1", "9780349440842"),
    ).resolves.toBeTruthy();
  });

  it("loads an author with works and caches it", async () => {
    const author = await env.service.getAuthor("u1", {
      ref: { provider: "openLibrary", externalId: "OL6761347A" },
    });
    expect(author.name).toBe("Elle Kennedy");
    expect(author.works.length).toBeGreaterThan(0);
    const again = await env.service.getAuthor("u1", { authorId: author.id });
    expect(again.id).toBe(author.id);
  });

  it("returns not-found for series when no provider supports series (Hardcover off)", async () => {
    await expect(
      env.service.getSeries("u1", {
        ref: { provider: "openLibrary", externalId: "x" },
      }),
    ).rejects.toMatchObject({
      code: "not-found",
    });
  });

  it("returns trending works from Open Library", async () => {
    const res = await env.service.trending("u1", 5);
    expect(res.provider).toBe("openLibrary");
    expect(res.results.length).toBeGreaterThan(0);
  });
});
