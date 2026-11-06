import { describe, expect, it } from "vitest";

import {
  cleanDescription,
  mergeWork,
  type MergeCandidate,
  type MergeContext,
} from "./merge";
import type { RawWork } from "./types";

const fetchedAt = new Date("2026-11-04T10:00:00Z");
let n = 0;
const ctx = (over: Partial<MergeContext> = {}): MergeContext => ({
  workId: "w1",
  now: fetchedAt,
  editionIdFor: () => `e${++n}`,
  authorIdFor: (ref) => (ref ? `a:${ref.externalId}` : null),
  seriesIdFor: (ref) => (ref ? `s:${ref.externalId}` : null),
  ...over,
});
const cand = (work: RawWork): MergeCandidate => ({ work, fetchedAt });

const hardcover: RawWork = {
  ref: { provider: "hardcover", externalId: "125001" },
  title: "The Deal",
  authors: [
    {
      name: "Elle Kennedy",
      ref: { provider: "hardcover", externalId: "4401" },
    },
  ],
  description: "Short.",
  series: [
    {
      name: "Off-Campus",
      ref: { provider: "hardcover", externalId: "9001" },
      position: 1,
      isPrimary: true,
    },
  ],
  pageCount: 390,
  firstPublishedDate: "2015-02-24",
  coverUrl: "https://hc/cover.jpg",
  editions: [
    {
      ref: { provider: "hardcover", externalId: "777001" },
      isbn13: "9780349440842",
      pageCount: 374,
      format: "paperback",
    },
  ],
};

const openLibrary: RawWork = {
  ref: { provider: "openLibrary", externalId: "OL42430111W" },
  title: "The Deal",
  authors: [
    {
      name: "Elle Kennedy",
      ref: { provider: "openLibrary", externalId: "OL6761347A" },
    },
  ],
  description:
    "The international bestseller! A standalone novel from New York Times bestselling author Elle Kennedy, about a deal.",
  series: [{ name: "Off-Campus" }],
  genres: ["romance", "Sports Romance", "Romance"],
  firstPublishedDate: "2000",
  editions: [
    {
      ref: { provider: "openLibrary", externalId: "OL49507353M" },
      isbn13: "9780349440842",
      pageCount: 400,
      publisher: "Little, Brown",
      language: "eng",
    },
    {
      ref: { provider: "openLibrary", externalId: "OL1M" },
      isbn13: "9789062223824",
      pageCount: 5,
    },
  ],
};

describe("mergeWork", () => {
  it("takes series (with id and position) from Hardcover and records provenance", () => {
    const work = mergeWork([cand(openLibrary), cand(hardcover)], ctx());
    expect(work.series).toEqual([
      {
        seriesId: "s:9001",
        name: "Off-Campus",
        position: 1,
        positionLabel: "1",
        isPrimary: true,
      },
    ]);
    expect(work.provenance.series?.provider).toBe("hardcover");
    expect(work.provenance.title?.provider).toBe("hardcover");
  });

  it("uses the ISBN-matched edition for page count over work-level values", () => {
    const work = mergeWork(
      [cand(hardcover), cand(openLibrary)],
      ctx({ matchedIsbn13: "9780349440842" }),
    );
    expect(work.pageCount).toBe(374); // Hardcover edition (higher priority) for that ISBN
    const defaultEdition = work.editions.find(
      (e) => e.id === work.defaultEditionId,
    );
    expect(defaultEdition?.isbn13).toBe("9780349440842");
  });

  it("falls back to provider priority for page count and ignores implausible values", () => {
    const work = mergeWork(
      [
        cand({ ...openLibrary, pageCount: 5 }),
        cand({ ...hardcover, pageCount: undefined }),
      ],
      ctx(),
    );
    // The implausible work-level 5 is ignored; a print edition's count is used.
    expect(work.pageCount).toBe(374);
    const work2 = mergeWork([cand(hardcover)], ctx());
    expect(work2.pageCount).toBe(390);
  });

  it("prefers a substantial description and strips HTML", () => {
    const work = mergeWork([cand(hardcover), cand(openLibrary)], ctx());
    expect(work.provenance.description?.provider).toBe("openLibrary");
    expect(cleanDescription("<p>Hello<br>world</p>")).toBe("Hello\nworld");
    expect(cleanDescription("No description available.")).toBeUndefined();
  });

  it("strips markdown and trailing source links from Open Library text", () => {
    const bio =
      "Her work includes the *Off-Campus* series and [her site](https://x.example).\n\n" +
      '(<a href="https://x.example/about" target="_blank">Source</a>)';
    expect(cleanDescription(bio)).toBe(
      "Her work includes the Off-Campus series and her site.",
    );
  });

  it("falls back to a print edition page count when no work-level count exists", () => {
    const work = mergeWork(
      [cand({ ...openLibrary, pageCount: undefined })],
      ctx(),
    );
    expect(work.pageCount).toBe(400);
    expect(work.provenance.pageCount?.provider).toBe("openLibrary");
  });

  it("merges editions by ISBN, filling gaps without overriding priority values", () => {
    const work = mergeWork([cand(openLibrary), cand(hardcover)], ctx());
    const deal = work.editions.filter((e) => e.isbn13 === "9780349440842");
    expect(deal).toHaveLength(1);
    expect(deal[0]).toMatchObject({
      pageCount: 374,
      publisher: "Little, Brown",
      language: "eng",
    });
    expect(deal[0]?.providerIds).toEqual({
      hardcover: "777001",
      openLibrary: "OL49507353M",
    });
    expect(
      work.editions.find((e) => e.isbn13 === "9789062223824")?.pageCount,
    ).toBeNull();
  });

  it("dedupes and normalizes genres, uses the earliest publication year", () => {
    const work = mergeWork([cand(hardcover), cand(openLibrary)], ctx());
    expect(work.genres).toEqual(["Romance", "Sports Romance"]);
    expect(work.firstPublishedDate).toBe("2000");
  });

  it("keeps every provider id", () => {
    const work = mergeWork([cand(hardcover), cand(openLibrary)], ctx());
    expect(work.providerIds).toEqual({
      hardcover: "125001",
      openLibrary: "OL42430111W",
    });
  });

  it("falls back to name-only series when no provider has ids", () => {
    const work = mergeWork([cand(openLibrary)], ctx());
    expect(work.series).toEqual([
      {
        seriesId: null,
        name: "Off-Campus",
        position: null,
        positionLabel: null,
        isPrimary: false,
      },
    ]);
  });
});
