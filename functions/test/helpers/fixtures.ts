/** Test helpers: replay recorded provider fixtures through an injected FetchJson. */
import { readFileSync } from "node:fs";
import { resolve } from "node:path";

import type { FetchJson } from "../../src/catalog/http";

export const fixture = (name: string): unknown =>
  JSON.parse(readFileSync(resolve(__dirname, "../fixtures", name), "utf8"));

export type Route = [RegExp, { status: number; json: unknown } | string];

/** Replays fixtures by URL pattern; records every request for assertions. */
export function fixtureFetch(
  routes: Route[],
): FetchJson & { calls: string[]; bodies: string[] } {
  const calls: string[] = [];
  const bodies: string[] = [];
  const fn = (async (
    url: string,
    init: { body?: string; signal: AbortSignal },
  ) => {
    calls.push(url);
    if (init.body) bodies.push(init.body);
    if (init.signal.aborted)
      throw Object.assign(new Error("aborted"), { name: "AbortError" });
    const route = routes.find(([re]) => re.test(url));
    if (!route) return { status: 404, json: null };
    const target = route[1];
    return typeof target === "string"
      ? { status: 200, json: fixture(target) }
      : target;
  }) as FetchJson & { calls: string[]; bodies: string[] };
  fn.calls = calls;
  fn.bodies = bodies;
  return fn;
}
