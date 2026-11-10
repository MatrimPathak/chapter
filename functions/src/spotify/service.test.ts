import { beforeEach, describe, expect, it, vi } from "vitest";

import type { FetchJson } from "../catalog/http";
import { SPOTIFY_SCOPES } from "./api";
import {
  callbackPage,
  redirectUri,
  spotifyNowPlaying,
  spotifyOAuthCallback,
  spotifyPlay,
} from "./callables";
import { SpotifyService, type LinkOutcome } from "./service";
import type { SpotifyLink, SpotifyLinkState, SpotifyStore } from "./store";

class MemoryStore implements SpotifyStore {
  links = new Map<string, SpotifyLink>();
  states = new Map<string, SpotifyLinkState>();

  saveState(uid: string, state: SpotifyLinkState): Promise<void> {
    this.states.set(uid, state);
    return Promise.resolve();
  }

  consumeState(uid: string, nonceHash: string, now: number): Promise<boolean> {
    const state = this.states.get(uid);
    if (!state || state.nonceHash !== nonceHash) return Promise.resolve(false);
    this.states.delete(uid);
    return Promise.resolve(now < state.expiresAt);
  }

  loadLink(uid: string): Promise<SpotifyLink | null> {
    return Promise.resolve(this.links.get(uid) ?? null);
  }

  saveLink(uid: string, link: SpotifyLink): Promise<void> {
    this.links.set(uid, link);
    return Promise.resolve();
  }

  deleteLink(uid: string): Promise<void> {
    this.links.delete(uid);
    this.states.delete(uid);
    return Promise.resolve();
  }
}

interface Sent {
  url: string;
  method?: string;
  headers?: Record<string, string>;
  body?: string;
}

const TOKEN_URL = "https://accounts.spotify.com/api/token";
const CREDENTIALS = { clientId: "client-id", clientSecret: "client-secret" };
const REDIRECT = "https://example.test/callback";
const START = 1_800_000_000_000;

let store: MemoryStore;
let sent: Sent[];
let responses: Array<{ status: number; json: unknown }>;
let now: number;
let credentials: typeof CREDENTIALS | null;
let service: SpotifyService;

const fetchJson: FetchJson = (url, init) => {
  sent.push({ url, ...init });
  const next = responses.shift();
  if (!next) return Promise.reject(new Error(`Unexpected request: ${url}`));
  return Promise.resolve(next);
};

const tokenResponse = (extra: Record<string, unknown> = {}) => ({
  status: 200,
  json: { access_token: "new-access", expires_in: 3600, ...extra },
});

const link = (extra: Partial<SpotifyLink> = {}): SpotifyLink => ({
  status: "linked",
  accessToken: "stored-access",
  accessTokenExpiresAt: START + 3_600_000,
  refreshToken: "stored-refresh",
  displayName: "Ada",
  ...extra,
});

function stateFrom(url: string): string {
  return new URL(url).searchParams.get("state") ?? "";
}

beforeEach(() => {
  store = new MemoryStore();
  sent = [];
  responses = [];
  now = START;
  credentials = CREDENTIALS;
  service = new SpotifyService({
    fetchJson,
    store,
    credentials: () => credentials,
    redirectUri: () => REDIRECT,
    now: () => now,
    nonce: () => "fixed-nonce",
  });
});

describe("status", () => {
  it("reports unavailable when the credentials aren't set", async () => {
    credentials = null;
    expect(await service.status("u1")).toEqual({
      available: false,
      state: "unlinked",
      displayName: null,
    });
  });

  it("never includes tokens", async () => {
    store.links.set("u1", link());
    const status = JSON.stringify(await service.status("u1"));
    expect(status).toContain("Ada");
    expect(status).not.toContain("stored-access");
    expect(status).not.toContain("stored-refresh");
  });

  it("reports an expired login as reconnect", async () => {
    store.links.set("u1", link({ status: "reconnect" }));
    expect((await service.status("u1")).state).toBe("reconnect");
  });
});

describe("beginLink", () => {
  it("asks only for the needed scopes and never exposes the secret", async () => {
    const url = new URL(await service.beginLink("u1"));
    expect(url.origin + url.pathname).toBe(
      "https://accounts.spotify.com/authorize",
    );
    expect(url.searchParams.get("client_id")).toBe("client-id");
    expect(url.searchParams.get("redirect_uri")).toBe(REDIRECT);
    expect(url.searchParams.get("scope")).toBe(SPOTIFY_SCOPES.join(" "));
    expect(url.toString()).not.toContain("client-secret");
  });

  it("stores only a hash of the nonce", async () => {
    await service.beginLink("u1");
    expect(store.states.get("u1")?.nonceHash).not.toContain("fixed-nonce");
  });

  it("fails clearly when the credentials aren't set", async () => {
    credentials = null;
    await expect(service.beginLink("u1")).rejects.toMatchObject({
      reason: "not-configured",
    });
  });
});

describe("completeLink", () => {
  async function begin(): Promise<string> {
    return stateFrom(await service.beginLink("u1"));
  }

  it("exchanges the code on the server and stores the link", async () => {
    const state = await begin();
    responses = [
      tokenResponse({ refresh_token: "new-refresh" }),
      { status: 200, json: { display_name: "Ada" } },
    ];

    expect(await service.completeLink({ code: "abc", state })).toBe("linked");

    const basic = Buffer.from("client-id:client-secret").toString("base64");
    expect(sent[0]?.url).toBe(TOKEN_URL);
    expect(sent[0]?.headers?.Authorization).toBe(`Basic ${basic}`);
    expect(sent[0]?.body).toContain("grant_type=authorization_code");
    expect(store.links.get("u1")).toMatchObject({
      status: "linked",
      accessToken: "new-access",
      refreshToken: "new-refresh",
      displayName: "Ada",
      accessTokenExpiresAt: START + 3_600_000,
    });
  });

  it("uses a login attempt only once", async () => {
    const state = await begin();
    responses = [
      tokenResponse({ refresh_token: "r" }),
      { status: 200, json: { display_name: "Ada" } },
    ];
    await service.completeLink({ code: "abc", state });
    expect(await service.completeLink({ code: "abc", state })).toBe("expired");
  });

  it("rejects an expired login attempt without contacting Spotify", async () => {
    const state = await begin();
    now += 10 * 60 * 1000;
    expect(await service.completeLink({ code: "abc", state })).toBe("expired");
    expect(sent).toHaveLength(0);
  });

  it.each([
    ["a slash", "a/b"],
    ["a dot segment", ".."],
    ["too many characters", "x".repeat(129)],
  ])("never looks up a uid with %s", async (_, uid) => {
    const lookup = vi.spyOn(store, "consumeState");
    const state = `${Buffer.from(uid).toString("base64url")}.nonce`;
    expect(await service.completeLink({ code: "abc", state })).toBe("expired");
    expect(lookup).not.toHaveBeenCalled();
  });

  it.each([
    ["missing", undefined],
    ["malformed", "nodot"],
    ["forged", `${Buffer.from("u1").toString("base64url")}.wrong-nonce`],
  ])("rejects a %s state", async (_, state) => {
    await begin();
    expect(await service.completeLink({ code: "abc", state })).toBe("expired");
    expect(sent).toHaveLength(0);
    expect(store.links.size).toBe(0);
  });

  it("reports when the user declines", async () => {
    const state = await begin();
    expect(await service.completeLink({ error: "access_denied", state })).toBe(
      "denied",
    );
    expect(sent).toHaveLength(0);
  });

  it("keeps no tokens for an account missing from Spotify's allow-list", async () => {
    const state = await begin();
    responses = [
      tokenResponse({ refresh_token: "r" }),
      { status: 403, json: { error: { status: 403, message: "not listed" } } },
    ];
    expect(await service.completeLink({ code: "abc", state })).toBe(
      "not-allowlisted",
    );
    expect(store.links.size).toBe(0);
  });

  it("keeps nothing when the exchange fails", async () => {
    const state = await begin();
    responses = [{ status: 500, json: null }];
    expect(await service.completeLink({ code: "abc", state })).toBe("failed");
    expect(store.links.size).toBe(0);
  });
});

describe("tokens", () => {
  const playing = {
    status: 200,
    json: { is_playing: true, item: { name: "Song" } },
  };

  it("uses a valid stored token without refreshing", async () => {
    store.links.set("u1", link());
    responses = [playing];
    await service.nowPlaying("u1");
    expect(sent).toHaveLength(1);
    expect(sent[0]?.headers?.Authorization).toBe("Bearer stored-access");
  });

  it("refreshes an expiring token and keeps the refresh token when none is returned", async () => {
    store.links.set("u1", link({ accessTokenExpiresAt: START + 1000 }));
    responses = [tokenResponse(), playing];
    await service.nowPlaying("u1");
    expect(sent[0]?.url).toBe(TOKEN_URL);
    expect(sent[1]?.headers?.Authorization).toBe("Bearer new-access");
    expect(store.links.get("u1")?.refreshToken).toBe("stored-refresh");
  });

  it("stores a replacement refresh token", async () => {
    store.links.set("u1", link({ accessTokenExpiresAt: 0 }));
    responses = [tokenResponse({ refresh_token: "rotated" }), playing];
    await service.nowPlaying("u1");
    expect(store.links.get("u1")?.refreshToken).toBe("rotated");
  });

  it("marks an expired login for reconnect and clears its tokens", async () => {
    store.links.set("u1", link({ accessTokenExpiresAt: 0 }));
    responses = [{ status: 400, json: { error: "invalid_grant" } }];
    await expect(service.nowPlaying("u1")).rejects.toMatchObject({
      reason: "reconnect",
    });
    expect(store.links.get("u1")).toMatchObject({
      status: "reconnect",
      accessToken: "",
      refreshToken: "",
      displayName: "Ada",
    });
  });

  it("retries once with a new token after a 401", async () => {
    store.links.set("u1", link());
    responses = [{ status: 401, json: null }, tokenResponse(), playing];
    const track = await service.nowPlaying("u1");
    expect(track?.title).toBe("Song");
    expect(sent).toHaveLength(3);
  });

  it("asks for reconnect when a new token is refused too", async () => {
    store.links.set("u1", link());
    responses = [
      { status: 401, json: null },
      tokenResponse(),
      { status: 401, json: null },
    ];
    await expect(service.nowPlaying("u1")).rejects.toMatchObject({
      reason: "reconnect",
    });
    expect(store.links.get("u1")?.status).toBe("reconnect");
  });

  it("uses no stored token after an expired login", async () => {
    store.links.set("u1", link({ status: "reconnect" }));
    await expect(service.nowPlaying("u1")).rejects.toMatchObject({
      reason: "reconnect",
    });
    expect(sent).toHaveLength(0);
  });

  it("reports an unlinked user without contacting Spotify", async () => {
    await expect(service.nowPlaying("u1")).rejects.toMatchObject({
      reason: "not-linked",
    });
    expect(sent).toHaveLength(0);
  });

  it("reports a network failure as unavailable", async () => {
    store.links.set("u1", link());
    await expect(service.nowPlaying("u1")).rejects.toMatchObject({
      reason: "unavailable",
    });
  });

  it("doesn't overwrite a token another request just replaced", async () => {
    store.links.set("u1", link({ accessTokenExpiresAt: 0 }));
    const original = store.loadLink.bind(store);
    let loads = 0;
    store.loadLink = async (uid) => {
      loads += 1;
      if (loads === 2)
        store.links.set(
          uid,
          link({ refreshToken: "rotated", accessToken: "fresh" }),
        );
      return original(uid);
    };
    responses = [{ status: 400, json: { error: "invalid_grant" } }, playing];
    await service.nowPlaying("u1");
    expect(store.links.get("u1")?.status).toBe("linked");
    expect(sent[1]?.headers?.Authorization).toBe("Bearer fresh");
  });
});

describe("now playing", () => {
  beforeEach(() => store.links.set("u1", link()));

  it("maps a track and picks the largest image", async () => {
    responses = [
      {
        status: 200,
        json: {
          is_playing: false,
          item: {
            name: "Song",
            artists: [{ name: "A" }, { name: "B" }],
            album: {
              name: "Album",
              images: [
                { url: "https://i.test/small", width: 64 },
                { url: "https://i.test/large", width: 640 },
              ],
            },
            external_urls: { spotify: "https://open.spotify.com/track/1" },
          },
        },
      },
    ];
    expect(await service.nowPlaying("u1")).toEqual({
      title: "Song",
      artists: ["A", "B"],
      album: "Album",
      imageUrl: "https://i.test/large",
      url: "https://open.spotify.com/track/1",
      isPlaying: false,
    });
  });

  it("treats nothing playing as no track", async () => {
    responses = [{ status: 204, json: null }];
    expect(await service.nowPlaying("u1")).toBeNull();
  });

  it("treats content with no track item as no track", async () => {
    responses = [{ status: 200, json: { is_playing: true, item: null } }];
    expect(await service.nowPlaying("u1")).toBeNull();
  });

  it("drops links that aren't Spotify's", async () => {
    responses = [
      {
        status: 200,
        json: {
          item: {
            name: "Song",
            external_urls: { spotify: "https://evil.test/" },
          },
        },
      },
    ];
    expect((await service.nowPlaying("u1"))?.url).toBeNull();
  });

  it("reports the shared quota running out", async () => {
    responses = [
      {
        status: 429,
        json: { error: { status: 429, reason: "QUOTA_EXCEEDED" } },
      },
    ];
    await expect(service.nowPlaying("u1")).rejects.toMatchObject({
      reason: "rate-limited",
    });
  });
});

describe("playback", () => {
  beforeEach(() => store.links.set("u1", link()));

  it("starts a playlist by its Spotify URI", async () => {
    responses = [{ status: 204, json: null }];
    await service.play("u1", "37i9dQZF1DX");
    expect(sent[0]?.method).toBe("PUT");
    expect(sent[0]?.url).toBe("https://api.spotify.com/v1/me/player/play");
    expect(sent[0]?.body).toBe(
      JSON.stringify({ context_uri: "spotify:playlist:37i9dQZF1DX" }),
    );
  });

  it("resumes with no body when no playlist is given", async () => {
    responses = [{ status: 204, json: null }];
    await service.play("u1", null);
    expect(sent[0]?.body).toBeUndefined();
  });

  it.each([
    [404, "NO_ACTIVE_DEVICE", "no-device"],
    [403, "PREMIUM_REQUIRED", "premium-required"],
    [403, "UNKNOWN", "unavailable"],
    [500, undefined, "unavailable"],
  ])("maps %s %s to %s", async (status, reason, expected) => {
    responses = [{ status, json: { error: { status, reason } } }];
    await expect(service.play("u1", null)).rejects.toMatchObject({
      reason: expected,
    });
  });

  it("treats pausing something already paused as done", async () => {
    responses = [
      { status: 403, json: { error: { reason: "ALREADY_PAUSED" } } },
    ];
    await expect(service.pause("u1")).resolves.toBeUndefined();
  });

  it("follows Spotify's pages until there are no more", async () => {
    responses = [
      {
        status: 200,
        json: {
          items: [{ id: "a", name: "First" }],
          next: "https://api.spotify.com/v1/me/playlists?offset=50",
        },
      },
      {
        status: 200,
        json: { items: [{ id: "b", name: "Second" }], next: null },
      },
    ];
    const playlists = await service.playlists("u1");
    expect(playlists.map((p) => p.id)).toEqual(["a", "b"]);
    expect(sent.map((r) => r.url)).toEqual([
      expect.stringContaining("offset=0"),
      expect.stringContaining("offset=50"),
    ]);
  });

  it("lists playlists without unusable entries", async () => {
    responses = [
      {
        status: 200,
        json: {
          items: [
            { id: "abc", name: "Focus", images: null },
            { id: "", name: "Broken" },
            null,
          ],
        },
      },
    ];
    expect(await service.playlists("u1")).toEqual([
      { id: "abc", name: "Focus", imageUrl: null },
    ]);
  });
});

describe("disconnect", () => {
  it("deletes the tokens and any pending login", async () => {
    store.links.set("u1", link());
    await service.beginLink("u1");
    await service.disconnect("u1");
    expect(store.links.size).toBe(0);
    expect(store.states.size).toBe(0);
  });
});

describe("callables", () => {
  type NowRequest = Parameters<typeof spotifyNowPlaying.run>[0];
  type PlayRequest = Parameters<typeof spotifyPlay.run>[0];

  it("rejects a caller who is not signed in", async () => {
    const request = { auth: undefined, data: {} } as unknown as NowRequest;
    await expect(spotifyNowPlaying.run(request)).rejects.toMatchObject({
      code: "unauthenticated",
    });
  });

  it("rejects an invalid playlist id before doing anything", async () => {
    const request = {
      auth: { uid: "u1" },
      data: { playlistId: "../../me" },
    } as unknown as PlayRequest;
    await expect(spotifyPlay.run(request)).rejects.toMatchObject({
      code: "invalid-argument",
    });
  });

  it("exports the OAuth callback", () => {
    expect(spotifyOAuthCallback).toBeTypeOf("function");
  });
});

describe("redirectUri", () => {
  it("uses the explicit loopback address in the emulator", () => {
    expect(redirectUri("demo-chapter", true)).toBe(
      "http://127.0.0.1:5001/demo-chapter/asia-south1/spotifyOAuthCallback",
    );
  });

  it("uses HTTPS in production", () => {
    expect(redirectUri("chapter-reads-prod", false)).toBe(
      "https://asia-south1-chapter-reads-prod.cloudfunctions.net/spotifyOAuthCallback",
    );
  });
});

describe("callbackPage", () => {
  it.each<LinkOutcome>([
    "linked",
    "denied",
    "not-allowlisted",
    "expired",
    "failed",
  ])("renders fixed text with no script for %s", (outcome) => {
    const page = callbackPage(outcome);
    expect(page).toContain("<h1>");
    expect(page).not.toContain("<script");
  });
});
