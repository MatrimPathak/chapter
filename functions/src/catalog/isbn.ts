/**
 * ISBN validation and normalization. Mirrors app/lib/features/scanner/domain/isbn.dart;
 * keep both in sync (both have tests).
 */

/** Removes spaces and hyphens and upper-cases a trailing x. */
export function cleanIsbn(input: string): string {
  return input.replace(/[\s-]/g, "").toUpperCase();
}

export function isValidIsbn10(input: string): boolean {
  const isbn = cleanIsbn(input);
  if (!/^\d{9}[\dX]$/.test(isbn)) return false;
  let sum = 0;
  for (let i = 0; i < 10; i++) {
    const ch = isbn[i]!;
    const value = ch === "X" ? 10 : Number(ch);
    sum += value * (10 - i);
  }
  return sum % 11 === 0;
}

export function isValidIsbn13(input: string): boolean {
  const isbn = cleanIsbn(input);
  if (!/^97[89]\d{10}$/.test(isbn)) return false;
  let sum = 0;
  for (let i = 0; i < 13; i++) {
    sum += Number(isbn[i]) * (i % 2 === 0 ? 1 : 3);
  }
  return sum % 10 === 0;
}

/** Converts a valid ISBN-10 to ISBN-13 (978 prefix). */
export function isbn10To13(input: string): string {
  const core = "978" + cleanIsbn(input).slice(0, 9);
  let sum = 0;
  for (let i = 0; i < 12; i++) {
    sum += Number(core[i]) * (i % 2 === 0 ? 1 : 3);
  }
  const check = (10 - (sum % 10)) % 10;
  return core + String(check);
}

/** Converts a 978-prefixed ISBN-13 to ISBN-10, or null when not possible. */
export function isbn13To10(input: string): string | null {
  const isbn = cleanIsbn(input);
  if (!isbn.startsWith("978") || !isValidIsbn13(isbn)) return null;
  const core = isbn.slice(3, 12);
  let sum = 0;
  for (let i = 0; i < 9; i++) sum += Number(core[i]) * (10 - i);
  const check = (11 - (sum % 11)) % 11;
  return core + (check === 10 ? "X" : String(check));
}

/**
 * Returns the canonical ISBN-13 for any valid ISBN-10/13 input, or null when
 * the input is not a valid ISBN. All catalog ISBN keys use this form.
 */
export function normalizeIsbn(input: string): string | null {
  const isbn = cleanIsbn(input);
  if (isValidIsbn13(isbn)) return isbn;
  if (isValidIsbn10(isbn)) return isbn10To13(isbn);
  return null;
}
