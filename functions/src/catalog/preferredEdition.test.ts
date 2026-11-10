import { describe, expect, it } from "vitest";

import { preferredEditionId } from "./merge";

describe("preferredEditionId", () => {
  it("prefers an English edition with a page count", () => {
    expect(
      preferredEditionId([
        { id: "es", language: "spa", pageCount: 400 },
        { id: "en-no-pages", language: "eng" },
        { id: "en", language: "eng", pageCount: 420 },
      ]),
    ).toBe("en");
  });

  it("takes an English edition without pages over another language", () => {
    expect(
      preferredEditionId([
        { id: "es", language: "spa", pageCount: 400 },
        { id: "en", language: "en" },
      ]),
    ).toBe("en");
  });

  it("falls back to any edition when none is English", () => {
    expect(
      preferredEditionId([
        { id: "fr", language: "fre" },
        { id: "es", language: "spa", pageCount: 400 },
      ]),
    ).toBe("es");
  });

  it("returns null with no editions", () => {
    expect(preferredEditionId([])).toBeNull();
  });
});
