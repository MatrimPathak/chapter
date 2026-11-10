import { describe, expect, it } from "vitest";

import { isBundleTitle } from "./hardcover";

describe("isBundleTitle", () => {
  it.each([
    "Throne of Glass: Books 0.1-7",
    "Throne of Glass, Books 0.1-4",
    "A Court of Thorns and Roses: Books 1-5",
    "Sarah J. Maas Starter Bundle",
    "The DC Icons Series Graphic Novel Box Set",
    "The Complete Throne of Glass Collection Full Series",
    "The DC Icons Series: Catwoman; Batman; Wonder Woman",
  ])("hides %s", (title) => {
    expect(isBundleTitle(title)).toBe(true);
  });

  it.each([
    "The Assassin's Blade",
    "A Court of Thorns and Roses",
    "World of Throne of Glass",
    "A Court of Mist and Fury (Dramatized Adaptation), Part 2 of 2",
    "The Book Thief",
  ])("keeps %s", (title) => {
    expect(isBundleTitle(title)).toBe(false);
  });
});
