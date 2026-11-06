import { describe, expect, it } from "vitest";

import {
  cleanIsbn,
  isbn10To13,
  isbn13To10,
  isValidIsbn10,
  isValidIsbn13,
  normalizeIsbn,
} from "./isbn";

describe("ISBN", () => {
  it("validates ISBN-13 checksums", () => {
    expect(isValidIsbn13("9780349440842")).toBe(true);
    expect(isValidIsbn13("978-0-349-44084-2")).toBe(true);
    expect(isValidIsbn13("9780349440843")).toBe(false);
    expect(isValidIsbn13("1234567890123")).toBe(false); // not 978/979
  });

  it("validates ISBN-10 checksums including X", () => {
    expect(isValidIsbn10("0349440840")).toBe(true);
    expect(isValidIsbn10("080442957X")).toBe(true);
    expect(isValidIsbn10("080442957x")).toBe(true);
    expect(isValidIsbn10("0349440841")).toBe(false);
  });

  it("converts between ISBN-10 and ISBN-13", () => {
    expect(isbn10To13("0349440840")).toBe("9780349440842");
    expect(isbn10To13("080442957X")).toBe("9780804429573");
    expect(isbn13To10("9780349440842")).toBe("0349440840");
    expect(isbn13To10("9791032305690")).toBeNull(); // 979 has no ISBN-10
  });

  it("normalizes any valid ISBN to ISBN-13 and rejects junk", () => {
    expect(normalizeIsbn(" 0-349-44084-0 ")).toBe("9780349440842");
    expect(normalizeIsbn("9780349440842")).toBe("9780349440842");
    expect(normalizeIsbn("the deal")).toBeNull();
    expect(normalizeIsbn("0349440841")).toBeNull();
    expect(cleanIsbn("978 0 349")).toBe("9780349");
  });
});
