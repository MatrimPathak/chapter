import type {
  Page,
  ProviderId,
  ProviderResult,
  RawAuthor,
  RawEdition,
  RawSeries,
  RawWork,
  RawWorkHit,
  SearchField,
  SearchQuery,
} from "../types";

export type ProviderCapability =
  "search" | "lookupIsbn" | "work" | "author" | "series" | "trending";

/**
 * One external metadata source (docs/04 §1.1). Implementations map provider
 * JSON into `Raw*` types; the orchestrator never sees provider-specific data.
 * Every method resolves (never throws) and must honour the abort signal.
 */
export interface BookMetadataProvider {
  readonly id: ProviderId;
  readonly capabilities: ReadonlySet<ProviderCapability>;
  /** Search fields this provider can answer meaningfully. */
  readonly searchFields: ReadonlySet<SearchField>;
  /** False when the provider is not configured (e.g. missing secret). */
  isEnabled(): boolean;

  search(
    query: SearchQuery,
    page: Page,
    signal: AbortSignal,
  ): Promise<ProviderResult<RawWorkHit[]>>;
  lookupIsbn(
    isbn13: string,
    signal: AbortSignal,
  ): Promise<ProviderResult<RawEdition & { work: RawWork }>>;
  getWork(
    externalId: string,
    signal: AbortSignal,
  ): Promise<ProviderResult<RawWork>>;
  getAuthor(
    externalId: string,
    signal: AbortSignal,
  ): Promise<ProviderResult<RawAuthor>>;
  getSeries(
    externalId: string,
    signal: AbortSignal,
  ): Promise<ProviderResult<RawSeries>>;
  trending(
    limit: number,
    signal: AbortSignal,
  ): Promise<ProviderResult<RawWorkHit[]>>;
}

export const unsupported = <T>(): Promise<ProviderResult<T>> =>
  Promise.resolve({ ok: false, error: "unsupported" });

/** Re-export for provider modules. */
export type { RawEdition, RawWork };
