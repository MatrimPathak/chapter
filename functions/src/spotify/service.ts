import { createHash, randomBytes } from "node:crypto";

import type { FetchJson } from "../catalog/http";
import {
  SpotifyApi,
  SpotifyError,
  type SpotifyCredentials,
  type SpotifyPlaylist,
  type SpotifyTokens,
  type SpotifyTrack,
} from "./api";
import type { SpotifyLink, SpotifyStore } from "./store";

const STATE_LIFETIME_MS = 10 * 60 * 1000;
/** Refresh a little early so a token can't expire mid-request. */
const EXPIRY_MARGIN_MS = 60 * 1000;

export type LinkState = "unlinked" | "linked" | "reconnect";

/** All the app ever learns about a link. Never includes tokens. */
export interface SpotifyStatus {
  available: boolean;
  state: LinkState;
  displayName: string | null;
}

export type LinkOutcome =
  "linked" | "denied" | "not-allowlisted" | "expired" | "failed";

export interface SpotifyServiceDeps {
  fetchJson: FetchJson;
  store: SpotifyStore;
  credentials: () => SpotifyCredentials | null;
  redirectUri: () => string;
  now?: () => number;
  nonce?: () => string;
}

const sha256 = (value: string): string =>
  createHash("sha256").update(value).digest("hex");

const encodeUid = (uid: string): string =>
  Buffer.from(uid, "utf8").toString("base64url");

function parseState(state: string): { uid: string; nonce: string } | null {
  const dot = state.indexOf(".");
  if (dot <= 0 || dot === state.length - 1) return null;
  const uid = Buffer.from(state.slice(0, dot), "base64url").toString("utf8");
  return uid.length > 0 ? { uid, nonce: state.slice(dot + 1) } : null;
}

export class SpotifyService {
  private readonly now: () => number;
  private readonly nonce: () => string;

  constructor(private readonly deps: SpotifyServiceDeps) {
    this.now = deps.now ?? Date.now;
    this.nonce = deps.nonce ?? (() => randomBytes(32).toString("base64url"));
  }

  private api(): SpotifyApi {
    const credentials = this.deps.credentials();
    if (!credentials) throw new SpotifyError("not-configured");
    return new SpotifyApi(this.deps.fetchJson, credentials);
  }

  async status(uid: string): Promise<SpotifyStatus> {
    if (!this.deps.credentials())
      return { available: false, state: "unlinked", displayName: null };
    const link = await this.deps.store.loadLink(uid);
    if (!link) return { available: true, state: "unlinked", displayName: null };
    return {
      available: true,
      state: link.status,
      displayName: link.displayName,
    };
  }

  /** The URL of Spotify's login page for this user. */
  async beginLink(uid: string): Promise<string> {
    const api = this.api();
    const nonce = this.nonce();
    await this.deps.store.saveState(uid, {
      nonceHash: sha256(nonce),
      expiresAt: this.now() + STATE_LIFETIME_MS,
    });
    return api.authorizeUrl(
      this.deps.redirectUri(),
      `${encodeUid(uid)}.${nonce}`,
    );
  }

  /** Handles Spotify's redirect. Every path ends in a fixed outcome. */
  async completeLink(query: {
    code?: string;
    state?: string;
    error?: string;
  }): Promise<LinkOutcome> {
    const parsed = query.state ? parseState(query.state) : null;
    if (!parsed) return "expired";
    const fresh = await this.deps.store.consumeState(
      parsed.uid,
      sha256(parsed.nonce),
      this.now(),
    );
    if (!fresh) return "expired";
    if (query.error) return "denied";
    if (!query.code) return "failed";

    try {
      const api = this.api();
      const tokens = await api.exchangeCode(
        query.code,
        this.deps.redirectUri(),
      );
      if (!tokens.refreshToken) return "failed";
      // Proves the account may use this app before anything is stored.
      const displayName = await api.displayName(tokens.accessToken);
      await this.deps.store.saveLink(
        parsed.uid,
        this.linkFrom(tokens, tokens.refreshToken, displayName),
      );
      return "linked";
    } catch (error) {
      if (error instanceof SpotifyError && error.reason === "not-allowlisted")
        return "not-allowlisted";
      if (error instanceof SpotifyError) return "failed";
      throw error;
    }
  }

  /** Deletes everything held for this user's link. */
  disconnect(uid: string): Promise<void> {
    return this.deps.store.deleteLink(uid);
  }

  nowPlaying(uid: string): Promise<SpotifyTrack | null> {
    return this.withToken(uid, (api, token) => api.nowPlaying(token));
  }

  playlists(uid: string): Promise<SpotifyPlaylist[]> {
    return this.withToken(uid, (api, token) => api.playlists(token));
  }

  play(uid: string, playlistId: string | null): Promise<void> {
    return this.withToken(uid, (api, token) => api.play(token, playlistId));
  }

  pause(uid: string): Promise<void> {
    return this.withToken(uid, (api, token) => api.pause(token));
  }

  private linkFrom(
    tokens: SpotifyTokens,
    refreshToken: string,
    displayName: string | null,
  ): SpotifyLink {
    return {
      status: "linked",
      accessToken: tokens.accessToken,
      accessTokenExpiresAt: this.now() + tokens.expiresInSeconds * 1000,
      refreshToken,
      displayName,
    };
  }

  private async withToken<T>(
    uid: string,
    run: (api: SpotifyApi, token: string) => Promise<T>,
  ): Promise<T> {
    const api = this.api();
    const link = await this.deps.store.loadLink(uid);
    if (!link) throw new SpotifyError("not-linked");
    if (link.status === "reconnect") throw new SpotifyError("reconnect");

    const expired = link.accessTokenExpiresAt - this.now() <= EXPIRY_MARGIN_MS;
    const current = expired ? await this.refresh(api, uid, link) : link;
    try {
      return await run(api, current.accessToken);
    } catch (error) {
      if (!(error instanceof SpotifyError)) throw error;
      if (error.reason !== "token-rejected") throw error;
    }
    const renewed = await this.refresh(api, uid, current);
    try {
      return await run(api, renewed.accessToken);
    } catch (error) {
      if (error instanceof SpotifyError && error.reason === "token-rejected") {
        await this.markReconnect(uid, renewed);
        throw new SpotifyError("reconnect");
      }
      throw error;
    }
  }

  private async refresh(
    api: SpotifyApi,
    uid: string,
    link: SpotifyLink,
  ): Promise<SpotifyLink> {
    try {
      const tokens = await api.refresh(link.refreshToken);
      const next = this.linkFrom(
        tokens,
        tokens.refreshToken ?? link.refreshToken,
        link.displayName,
      );
      await this.deps.store.saveLink(uid, next);
      return next;
    } catch (error) {
      if (!(error instanceof SpotifyError) || error.reason !== "reconnect")
        throw error;
      // A concurrent request may have just replaced the token we used.
      const stored = await this.deps.store.loadLink(uid);
      if (
        stored?.status === "linked" &&
        stored.refreshToken !== link.refreshToken
      )
        return stored;
      await this.markReconnect(uid, link);
      throw error;
    }
  }

  /** Keeps only the name for the Reconnect row; the tokens no longer work. */
  private markReconnect(uid: string, link: SpotifyLink): Promise<void> {
    return this.deps.store.saveLink(uid, {
      status: "reconnect",
      accessToken: "",
      accessTokenExpiresAt: 0,
      refreshToken: "",
      displayName: link.displayName,
    });
  }
}
