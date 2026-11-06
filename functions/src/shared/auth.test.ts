import { describe, expect, it } from "vitest";
import { HttpsError } from "firebase-functions/v2/https";

import { requireUid } from "./auth";

describe("requireUid", () => {
  it("returns the uid of an authenticated caller", () => {
    expect(requireUid({ auth: { uid: "u1" } })).toBe("u1");
  });

  it("rejects anonymous callers with unauthenticated", () => {
    for (const request of [{}, { auth: null }, { auth: { uid: "" } }]) {
      try {
        requireUid(request);
        expect.unreachable();
      } catch (e) {
        expect(e).toBeInstanceOf(HttpsError);
        expect((e as HttpsError).code).toBe("unauthenticated");
      }
    }
  });
});
