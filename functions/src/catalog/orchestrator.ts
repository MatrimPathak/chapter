import type {
  BookMetadataProvider,
  ProviderCapability,
} from "./providers/BookMetadataProvider";
import { CircuitBreaker } from "./rateLimiter";
import type {
  Page,
  ProviderId,
  ProviderRef,
  ProviderResult,
  RawAuthor,
  RawEdition,
  RawSeries,
  RawWork,
  RawWorkHit,
  SearchQuery,
} from "./types";

export interface OrchestratorOptions {
  /** Per-provider timeout for searches (docs/04 §1.2: 2.5 s). */
  searchTimeoutMs?: number;
  /** Detail calls fan out (Open Library: work + editions + authors), so allow more. */
  detailTimeoutMs?: number;
  now?: () => number;
}

export interface SearchOutcome {
  hits: RawWorkHit[];
  provider: ProviderId | null;
  /** Every eligible provider failed (not merely returned nothing). */
  degraded: boolean;
}

export interface Fetched<T> {
  data: T;
  fetchedAt: Date;
}

/**
 * Runs providers in priority order with timeouts and per-provider circuit
 * breakers so one failing source never takes discovery down (docs/04 §1.2).
 */
export class MetadataOrchestrator {
  private readonly breakers = new Map<ProviderId, CircuitBreaker>();
  private readonly searchTimeoutMs: number;
  private readonly detailTimeoutMs: number;

  constructor(
    private readonly providers: BookMetadataProvider[],
    options: OrchestratorOptions = {},
  ) {
    this.searchTimeoutMs = options.searchTimeoutMs ?? 2_500;
    this.detailTimeoutMs = options.detailTimeoutMs ?? 8_000;
    for (const p of providers)
      this.breakers.set(p.id, new CircuitBreaker(5, 60_000, options.now));
  }

  /** First provider (in priority order) that answers with results wins. */
  async search(query: SearchQuery, page: Page): Promise<SearchOutcome> {
    let anyAnswered = false;
    for (const provider of this.eligible("search")) {
      if (!provider.searchFields.has(query.field)) continue;
      const result = await this.call(provider, this.searchTimeoutMs, (signal) =>
        provider.search(query, page, signal),
      );
      if (result.ok) {
        anyAnswered = true;
        if (result.data.length > 0)
          return { hits: result.data, provider: provider.id, degraded: false };
      }
    }
    return { hits: [], provider: null, degraded: !anyAnswered };
  }

  /** ISBN lookups are exact and cheap: ask every provider in parallel. */
  async lookupIsbnAll(
    isbn13: string,
  ): Promise<Array<Fetched<RawEdition & { work: RawWork }>>> {
    const results = await Promise.all(
      this.eligible("lookupIsbn").map((p) =>
        this.call(p, this.detailTimeoutMs, (signal) =>
          p.lookupIsbn(isbn13, signal),
        ),
      ),
    );
    return results.flatMap((r) =>
      r.ok ? [{ data: r.data, fetchedAt: r.fetchedAt }] : [],
    );
  }

  getWork(ref: ProviderRef): Promise<ProviderResult<RawWork>> {
    return this.byRef(ref, "work", (p, signal) =>
      p.getWork(ref.externalId, signal),
    );
  }

  getAuthor(ref: ProviderRef): Promise<ProviderResult<RawAuthor>> {
    return this.byRef(ref, "author", (p, signal) =>
      p.getAuthor(ref.externalId, signal),
    );
  }

  getSeries(ref: ProviderRef): Promise<ProviderResult<RawSeries>> {
    return this.byRef(ref, "series", (p, signal) =>
      p.getSeries(ref.externalId, signal),
    );
  }

  async trending(limit: number): Promise<SearchOutcome> {
    for (const provider of this.eligible("trending")) {
      const result = await this.call(provider, this.searchTimeoutMs, (signal) =>
        provider.trending(limit, signal),
      );
      if (result.ok && result.data.length > 0)
        return { hits: result.data, provider: provider.id, degraded: false };
    }
    return { hits: [], provider: null, degraded: true };
  }

  isAvailable(id: ProviderId): boolean {
    const p = this.providers.find((x) => x.id === id);
    return (
      !!p && p.isEnabled() && (this.breakers.get(id)?.canAttempt() ?? false)
    );
  }

  private eligible(capability: ProviderCapability): BookMetadataProvider[] {
    return this.providers.filter(
      (p) => p.isEnabled() && p.capabilities.has(capability),
    );
  }

  private byRef<T>(
    ref: ProviderRef,
    capability: ProviderCapability,
    run: (
      p: BookMetadataProvider,
      signal: AbortSignal,
    ) => Promise<ProviderResult<T>>,
  ): Promise<ProviderResult<T>> {
    const provider = this.providers.find((p) => p.id === ref.provider);
    if (
      !provider ||
      !provider.isEnabled() ||
      !provider.capabilities.has(capability)
    ) {
      return Promise.resolve({ ok: false, error: "unsupported" });
    }
    return this.call(provider, this.detailTimeoutMs, (signal) =>
      run(provider, signal),
    );
  }

  private async call<T>(
    provider: BookMetadataProvider,
    timeoutMs: number,
    run: (signal: AbortSignal) => Promise<ProviderResult<T>>,
  ): Promise<ProviderResult<T>> {
    const breaker = this.breakers.get(provider.id)!;
    if (!breaker.canAttempt())
      return { ok: false, error: "unavailable", message: "circuit open" };
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), timeoutMs);
    try {
      const result = await Promise.race([
        run(controller.signal),
        new Promise<ProviderResult<T>>((resolve) =>
          controller.signal.addEventListener("abort", () =>
            resolve({ ok: false, error: "unavailable", message: "timeout" }),
          ),
        ),
      ]);
      // "Not found" / "unsupported" are answers, not outages.
      if (
        result.ok ||
        result.error === "notFound" ||
        result.error === "unsupported"
      )
        breaker.recordSuccess();
      else breaker.recordFailure();
      return result;
    } finally {
      clearTimeout(timer);
    }
  }
}
