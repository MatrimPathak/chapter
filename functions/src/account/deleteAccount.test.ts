import { describe, expect, it } from "vitest";

import {
  deleteAccount,
  RECENT_SIGN_IN_REQUIRED,
  RECENT_SIGN_IN_SECONDS,
  requireRecentSignIn,
  withOneRetry,
} from "./deleteAccount";

const now = 1_800_000_000;

describe("requireRecentSignIn", () => {
  it("accepts a sign-in inside the window, including its edge", () => {
    expect(() => requireRecentSignIn(now - 10, now)).not.toThrow();
    expect(() =>
      requireRecentSignIn(now - RECENT_SIGN_IN_SECONDS, now),
    ).not.toThrow();
  });

  it.each([
    ["too old", now - RECENT_SIGN_IN_SECONDS - 1],
    ["far in the future", now + 3600],
    ["missing", undefined],
    ["not a number", String(now)],
  ])("rejects a sign-in time that is %s", (_, authTime) => {
    expect(() => requireRecentSignIn(authTime, now)).toThrow(
      RECENT_SIGN_IN_REQUIRED,
    );
  });
});

describe("deleteAccount callable", () => {
  it("rejects a caller who is not signed in", async () => {
    const request = { auth: undefined, data: {} } as unknown as Parameters<
      typeof deleteAccount.run
    >[0];
    await expect(deleteAccount.run(request)).rejects.toMatchObject({
      code: "unauthenticated",
    });
  });

  it("rejects a stale sign-in before touching any data", async () => {
    const request = {
      auth: { uid: "u1", token: { auth_time: 1000 } },
      data: {},
    } as unknown as Parameters<typeof deleteAccount.run>[0];
    await expect(deleteAccount.run(request)).rejects.toMatchObject({
      code: "failed-precondition",
      message: RECENT_SIGN_IN_REQUIRED,
    });
  });
});

describe("withOneRetry", () => {
  const noWait = () => Promise.resolve();

  it("tries once when that works", async () => {
    let calls = 0;
    await withOneRetry(async () => {
      calls++;
    }, noWait);
    expect(calls).toBe(1);
  });

  it("recovers from one failure", async () => {
    let calls = 0;
    await withOneRetry(async () => {
      if (++calls === 1) throw new Error("cancelled");
    }, noWait);
    expect(calls).toBe(2);
  });

  it("reports a second failure", async () => {
    let calls = 0;
    await expect(
      withOneRetry(async () => {
        calls++;
        throw new Error("down");
      }, noWait),
    ).rejects.toThrow("down");
    expect(calls).toBe(2);
  });
});
