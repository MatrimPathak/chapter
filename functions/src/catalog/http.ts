import type { ProviderErrorKind, ProviderResult } from "./types";

/** Identifies Chapter to public APIs (Open Library asks clients to do so). */
export const USER_AGENT =
  "Chapter/0.1 (+https://github.com/chapterreads; book tracking app)";

export type FetchJson = (
  url: string,
  init: {
    method?: "GET" | "POST" | "PUT";
    headers?: Record<string, string>;
    body?: string;
    signal: AbortSignal;
  },
) => Promise<{ status: number; json: unknown }>;

/** Production fetch: Node 22 global fetch with JSON decoding. */
export const nodeFetchJson: FetchJson = async (url, init) => {
  const response = await fetch(url, {
    method: init.method ?? "GET",
    headers: {
      "User-Agent": USER_AGENT,
      Accept: "application/json",
      ...init.headers,
    },
    body: init.body,
    signal: init.signal,
    redirect: "follow",
  });
  const text = await response.text();
  let json: unknown = null;
  try {
    json = text.length > 0 ? JSON.parse(text) : null;
  } catch {
    json = null;
  }
  return { status: response.status, json };
};

export function statusToError(status: number): ProviderErrorKind {
  if (status === 404) return "notFound";
  if (status === 429) return "rateLimited";
  if (status === 400 || status === 422) return "invalid";
  return "unavailable";
}

/** Wraps a provider call so thrown errors (network, abort, parse) become results. */
export async function guard<T>(
  fn: () => Promise<ProviderResult<T>>,
): Promise<ProviderResult<T>> {
  try {
    return await fn();
  } catch (error) {
    const aborted = error instanceof Error && error.name === "AbortError";
    return {
      ok: false,
      error: "unavailable",
      message: aborted
        ? "timeout"
        : error instanceof Error
          ? error.message
          : String(error),
    };
  }
}

export function ok<T>(
  data: T,
  now: () => Date = () => new Date(),
): ProviderResult<T> {
  return { ok: true, data, fetchedAt: now() };
}

export function fail<T>(
  error: ProviderErrorKind,
  message?: string,
): ProviderResult<T> {
  return { ok: false, error, message };
}

/** Narrowing helpers for untyped JSON. */
export const asRecord = (v: unknown): Record<string, unknown> | undefined =>
  v !== null && typeof v === "object" && !Array.isArray(v)
    ? (v as Record<string, unknown>)
    : undefined;
export const asArray = (v: unknown): unknown[] => (Array.isArray(v) ? v : []);
export const asString = (v: unknown): string | undefined =>
  typeof v === "string" && v.trim().length > 0 ? v.trim() : undefined;
export const asNumber = (v: unknown): number | undefined => {
  if (typeof v === "number" && Number.isFinite(v)) return v;
  if (typeof v === "string" && v.trim() !== "" && Number.isFinite(Number(v)))
    return Number(v);
  return undefined;
};
export const asStrings = (v: unknown): string[] =>
  asArray(v)
    .map(asString)
    .filter((s): s is string => s !== undefined);
