/**
 * Catalog types shared by providers, the merge and the callables.
 * See docs/03 §2.1 and docs/04 §1.
 */

export type ProviderId = "hardcover" | "openLibrary" | "googleBooks";

export const PROVIDER_PRIORITY: readonly ProviderId[] = [
  "hardcover",
  "openLibrary",
  "googleBooks",
];

export type EditionFormat =
  | "paperback"
  | "hardcover"
  | "massMarket"
  | "ebook"
  | "kindle"
  | "epub"
  | "audiobook"
  | "audible"
  | "other";

export interface ProviderRef {
  provider: ProviderId;
  /** Provider-native id (Open Library "OL123W", Google volume id, Hardcover numeric id as string). */
  externalId: string;
}

export interface RawAuthorRef {
  name: string;
  ref?: ProviderRef;
}

export interface RawSeriesRef {
  name: string;
  ref?: ProviderRef;
  /** Numeric position when known (1, 2, 2.5). */
  position?: number;
  isPrimary?: boolean;
}

export interface RawEdition {
  ref: ProviderRef;
  workRef?: ProviderRef;
  title?: string;
  format?: EditionFormat;
  isbn10?: string;
  isbn13?: string;
  publisher?: string;
  publishedDate?: string;
  pageCount?: number;
  audioDurationSec?: number;
  language?: string;
  coverUrl?: string;
}

/** A provider's view of a work, before merging. Every field is optional except ref/title. */
export interface RawWork {
  ref: ProviderRef;
  title: string;
  subtitle?: string;
  authors: RawAuthorRef[];
  description?: string;
  firstPublishedDate?: string;
  language?: string;
  genres?: string[];
  series?: RawSeriesRef[];
  coverUrl?: string;
  /** Page count of the provider's default/representative edition. */
  pageCount?: number;
  editions?: RawEdition[];
  isbns?: string[];
}

/** Lightweight search hit. */
export interface RawWorkHit {
  ref: ProviderRef;
  title: string;
  subtitle?: string;
  authors: RawAuthorRef[];
  coverUrl?: string;
  firstPublishedYear?: number;
  seriesName?: string;
  seriesPosition?: number;
  pageCount?: number;
  isbns?: string[];
}

export interface RawAuthor {
  ref: ProviderRef;
  name: string;
  bio?: string;
  photoUrl?: string;
  photoCredit?: string;
  birthDate?: string;
  deathDate?: string;
  works?: RawWorkHit[];
}

export interface RawSeries {
  ref: ProviderRef;
  name: string;
  description?: string;
  entries: Array<{
    work: RawWorkHit;
    position?: number;
    positionLabel?: string;
    isPrimary: boolean;
  }>;
}

export type ProviderErrorKind =
  "unavailable" | "rateLimited" | "notFound" | "unsupported" | "invalid";

export type ProviderResult<T> =
  | { ok: true; data: T; fetchedAt: Date }
  | { ok: false; error: ProviderErrorKind; message?: string };

export type SearchField =
  "all" | "title" | "author" | "isbn" | "series" | "publisher";

export interface SearchQuery {
  text: string;
  field: SearchField;
}

export interface Page {
  page: number;
  pageSize: number;
}

// ─── Normalized catalog records (persisted and returned to clients) ───

export interface FieldProvenance {
  provider: ProviderId;
  fetchedAt: string;
}

export interface CatalogAuthorRef {
  id: string | null;
  name: string;
}

export interface CatalogSeriesRef {
  seriesId: string | null;
  name: string;
  position: number | null;
  positionLabel: string | null;
  isPrimary: boolean;
}

export interface CatalogEdition {
  id: string;
  workId: string;
  format: EditionFormat;
  isbn10: string | null;
  isbn13: string | null;
  publisher: string | null;
  publishedDate: string | null;
  pageCount: number | null;
  audioDurationSec: number | null;
  language: string | null;
  coverUrl: string | null;
  providerIds: Partial<Record<ProviderId, string>>;
}

export interface CatalogWork {
  id: string;
  title: string;
  subtitle: string | null;
  authors: CatalogAuthorRef[];
  description: string | null;
  firstPublishedDate: string | null;
  language: string | null;
  genres: string[];
  series: CatalogSeriesRef[];
  coverUrl: string | null;
  pageCount: number | null;
  defaultEditionId: string | null;
  editions: CatalogEdition[];
  providerIds: Partial<Record<ProviderId, string>>;
  provenance: Record<string, FieldProvenance>;
  refreshedAt: string;
}

export interface WorkSummary {
  /** Internal id when the work is already in the catalog. */
  id: string | null;
  ref: ProviderRef;
  title: string;
  subtitle: string | null;
  authors: string[];
  coverUrl: string | null;
  firstPublishedYear: number | null;
  seriesName: string | null;
  seriesPosition: number | null;
  pageCount: number | null;
}

export interface CatalogAuthor {
  id: string;
  name: string;
  bio: string | null;
  photoUrl: string | null;
  photoCredit: string | null;
  birthDate: string | null;
  deathDate: string | null;
  works: WorkSummary[];
  providerIds: Partial<Record<ProviderId, string>>;
  refreshedAt: string;
}

export interface CatalogSeries {
  id: string;
  name: string;
  description: string | null;
  entries: Array<{
    work: WorkSummary;
    position: number | null;
    positionLabel: string | null;
    isPrimary: boolean;
  }>;
  primaryCount: number;
  providerIds: Partial<Record<ProviderId, string>>;
  refreshedAt: string;
}

export interface SearchResponse {
  results: WorkSummary[];
  page: number;
  hasMore: boolean;
  /** Provider that answered; null when served from an empty fallback. */
  provider: ProviderId | null;
  /** True when every provider failed. */
  degraded: boolean;
}

export function refKey(ref: ProviderRef): string {
  return `${ref.provider}:${ref.externalId}`;
}
