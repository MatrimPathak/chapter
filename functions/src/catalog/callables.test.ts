import { HttpsError } from "firebase-functions/v2/https";
import { describe, expect, it } from "vitest";

import { parseInput, schemas } from "./callables";

const reject = (schema: Parameters<typeof parseInput>[0], data: unknown) => {
  try {
    parseInput(schema, data);
    return null;
  } catch (e) {
    return e as HttpsError;
  }
};

describe("catalog callable input validation", () => {
  it("applies defaults and trims search text", () => {
    expect(parseInput(schemas.SearchInput, { text: "  the deal " })).toEqual({
      text: "the deal",
      field: "all",
      page: 1,
      pageSize: 20,
    });
  });

  it("rejects short, oversized or malformed search requests", () => {
    expect(reject(schemas.SearchInput, { text: "a" })?.code).toBe(
      "invalid-argument",
    );
    expect(reject(schemas.SearchInput, { text: "x".repeat(201) })?.code).toBe(
      "invalid-argument",
    );
    expect(
      reject(schemas.SearchInput, { text: "deal", field: "sql" })?.code,
    ).toBe("invalid-argument");
    expect(
      reject(schemas.SearchInput, { text: "deal", pageSize: 500 })?.code,
    ).toBe("invalid-argument");
    expect(reject(schemas.SearchInput, undefined)?.code).toBe(
      "invalid-argument",
    );
  });

  it("accepts either an internal id or a provider ref for details", () => {
    expect(
      parseInput(schemas.WorkInput, {
        workId: "01a1a6b8-e8a9-70f9-a0f6-1f80859af715",
      }),
    ).toBeTruthy();
    expect(
      parseInput(schemas.WorkInput, {
        ref: { provider: "openLibrary", externalId: "OL42430111W" },
      }),
    ).toBeTruthy();
  });

  it("rejects path-like or unknown provider refs", () => {
    expect(
      reject(schemas.WorkInput, {
        ref: { provider: "openLibrary", externalId: "../works/x" },
      })?.code,
    ).toBe("invalid-argument");
    expect(
      reject(schemas.WorkInput, {
        ref: { provider: "amazon", externalId: "B00" },
      })?.code,
    ).toBe("invalid-argument");
    expect(reject(schemas.WorkInput, { workId: "not-a-uuid" })?.code).toBe(
      "invalid-argument",
    );
  });

  it("bounds ISBN and trending inputs", () => {
    expect(reject(schemas.IsbnInput, { isbn: "123" })?.code).toBe(
      "invalid-argument",
    );
    expect(parseInput(schemas.TrendingInput, {})).toEqual({ limit: 12 });
    expect(reject(schemas.TrendingInput, { limit: 1000 })?.code).toBe(
      "invalid-argument",
    );
  });
});
