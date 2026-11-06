import { describe, expect, it } from "vitest";

import { MetadataOrchestrator } from "./orchestrator";
import type { BookMetadataProvider } from "./providers/BookMetadataProvider";
import type { ProviderId, ProviderResult, RawWorkHit } from "./types";

type Behaviour = "ok" | "empty" | "error" | "hang";

function fakeProvider(
  id: ProviderId,
  behaviour: () => Behaviour,
  enabled = true,
): BookMetadataProvider & { calls: number } {
  const hit: RawWorkHit = {
    ref: { provider: id, externalId: "1" },
    title: `from ${id}`,
    authors: [],
  };
  const respond = async <T>(
    data: T,
    signal: AbortSignal,
  ): Promise<ProviderResult<T>> => {
    const b = behaviour();
    if (b === "hang") {
      await new Promise((resolve) => signal.addEventListener("abort", resolve));
      return { ok: false, error: "unavailable", message: "aborted" };
    }
    if (b === "error") return { ok: false, error: "unavailable" };
    return {
      ok: true,
      data: b === "empty" ? ([] as T) : data,
      fetchedAt: new Date(),
    };
  };
  const provider = {
    id,
    calls: 0,
    capabilities: new Set([
      "search",
      "lookupIsbn",
      "work",
      "trending",
    ] as const),
    searchFields: new Set([
      "all",
      "title",
      "author",
      "isbn",
      "series",
      "publisher",
    ] as const),
    isEnabled: () => enabled,
    search: (_q: unknown, _p: unknown, signal: AbortSignal) => {
      provider.calls++;
      return respond([hit], signal);
    },
    lookupIsbn: (_i: string, signal: AbortSignal) => {
      provider.calls++;
      return respond({ ref: hit.ref, work: { ...hit } }, signal) as never;
    },
    getWork: () => Promise.resolve({ ok: false, error: "unsupported" }),
    getAuthor: () => Promise.resolve({ ok: false, error: "unsupported" }),
    getSeries: () => Promise.resolve({ ok: false, error: "unsupported" }),
    trending: (_n: number, signal: AbortSignal) => {
      provider.calls++;
      return respond([hit], signal);
    },
  } as unknown as BookMetadataProvider & { calls: number };
  return provider;
}

const q = { text: "deal", field: "all" as const };
const page = { page: 1, pageSize: 10 };

describe("MetadataOrchestrator", () => {
  it("uses the highest-priority provider that answers", async () => {
    const o = new MetadataOrchestrator([
      fakeProvider("hardcover", () => "ok"),
      fakeProvider("openLibrary", () => "ok"),
    ]);
    const r = await o.search(q, page);
    expect(r.provider).toBe("hardcover");
  });

  it("falls back when Hardcover is disabled (no token)", async () => {
    const hc = fakeProvider("hardcover", () => "ok", false);
    const o = new MetadataOrchestrator([
      hc,
      fakeProvider("openLibrary", () => "ok"),
    ]);
    expect((await o.search(q, page)).provider).toBe("openLibrary");
    expect(hc.calls).toBe(0);
  });

  it("falls back when a provider errors or returns nothing", async () => {
    const o = new MetadataOrchestrator([
      fakeProvider("hardcover", () => "error"),
      fakeProvider("openLibrary", () => "empty"),
      fakeProvider("googleBooks", () => "ok"),
    ]);
    expect((await o.search(q, page)).provider).toBe("googleBooks");
  });

  it("times out a hanging provider and moves on", async () => {
    const o = new MetadataOrchestrator(
      [
        fakeProvider("hardcover", () => "hang"),
        fakeProvider("openLibrary", () => "ok"),
      ],
      {
        searchTimeoutMs: 30,
      },
    );
    const started = Date.now();
    const r = await o.search(q, page);
    expect(r.provider).toBe("openLibrary");
    expect(Date.now() - started).toBeLessThan(1000);
  });

  it("reports degraded only when every provider failed", async () => {
    const all = new MetadataOrchestrator([
      fakeProvider("hardcover", () => "error"),
      fakeProvider("openLibrary", () => "error"),
    ]);
    expect(await all.search(q, page)).toEqual({
      hits: [],
      provider: null,
      degraded: true,
    });
    const empty = new MetadataOrchestrator([
      fakeProvider("openLibrary", () => "empty"),
    ]);
    expect(await empty.search(q, page)).toEqual({
      hits: [],
      provider: null,
      degraded: false,
    });
  });

  it("opens the circuit after 5 failures and retries after the cooldown", async () => {
    let now = 0;
    const hc = fakeProvider("hardcover", () => "error");
    const o = new MetadataOrchestrator(
      [hc, fakeProvider("openLibrary", () => "ok")],
      { now: () => now },
    );
    for (let i = 0; i < 5; i++) await o.search(q, page);
    expect(hc.calls).toBe(5);
    expect(o.isAvailable("hardcover")).toBe(false);
    await o.search(q, page);
    expect(hc.calls).toBe(5); // skipped while open
    now = 60_001;
    await o.search(q, page);
    expect(hc.calls).toBe(6); // half-open trial
  });

  it("queries every provider in parallel for ISBN lookups", async () => {
    const providers = [
      fakeProvider("hardcover", () => "ok"),
      fakeProvider("openLibrary", () => "error"),
      fakeProvider("googleBooks", () => "ok"),
    ];
    const o = new MetadataOrchestrator(providers);
    const hits = await o.lookupIsbnAll("9780349440842");
    expect(hits.map((h) => h.data.ref.provider).sort()).toEqual([
      "googleBooks",
      "hardcover",
    ]);
    expect(providers.every((p) => p.calls === 1)).toBe(true);
  });
});
