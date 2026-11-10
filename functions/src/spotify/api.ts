import {
  asArray,
  asRecord,
  asString,
  asNumber,
  type FetchJson,
} from "../catalog/http";

/** Only what the features use (Developer Policy: request only what's needed). */
export const SPOTIFY_SCOPES = [
  "user-read-currently-playing",
  "user-modify-playback-state",
  "playlist-read-private",
  "playlist-read-collaborative",
];

const ACCOUNTS = "https://accounts.spotify.com";
const API = "https://api.spotify.com/v1";
const TIMEOUT_MS = 8000;
const PLAYLIST_PAGE = 50;
const PLAYLIST_MAX_PAGES = 10; // 500 playlists is plenty for a picker

export type SpotifyReason =
  | "not-configured"
  | "not-linked"
  | "reconnect"
  | "not-allowlisted"
  | "no-device"
  | "premium-required"
  | "rate-limited"
  | "unavailable"
  /** Internal: the access token was refused, so refresh it once. */
  | "token-rejected";

export class SpotifyError extends Error {
  constructor(readonly reason: SpotifyReason) {
    super(reason);
    this.name = "SpotifyError";
  }
}

export interface SpotifyCredentials {
  clientId: string;
  clientSecret: string;
}

export interface SpotifyTokens {
  accessToken: string;
  expiresInSeconds: number;
  /** Spotify may leave this out on refresh: keep the existing one then. */
  refreshToken?: string;
}

export interface SpotifyTrack {
  title: string;
  artists: string[];
  album: string | null;
  imageUrl: string | null;
  url: string | null;
  isPlaying: boolean;
}

export interface SpotifyPlaylist {
  id: string;
  name: string;
  imageUrl: string | null;
}

function largestImage(images: unknown): string | null {
  const best = asArray(images)
    .map(asRecord)
    .filter((i) => i !== undefined)
    .sort((a, b) => (asNumber(b.width) ?? 0) - (asNumber(a.width) ?? 0))[0];
  return https(best?.url);
}

function https(value: unknown): string | null {
  const url = asString(value);
  return url?.startsWith("https://") ? url : null;
}

function errorReason(json: unknown): string | undefined {
  return asString(asRecord(asRecord(json)?.error)?.reason);
}

function failureFor(status: number, json: unknown): SpotifyError {
  const reason = errorReason(json);
  if (status === 401) return new SpotifyError("token-rejected");
  if (status === 429) return new SpotifyError("rate-limited");
  if (status === 404 && (reason === "NO_ACTIVE_DEVICE" || reason === undefined))
    return new SpotifyError("no-device");
  if (status === 403) {
    if (reason === "PREMIUM_REQUIRED")
      return new SpotifyError("premium-required");
    // Accounts missing from the app's allow-list get a 403 with no reason.
    if (reason === undefined) return new SpotifyError("not-allowlisted");
  }
  return new SpotifyError("unavailable");
}

export class SpotifyApi {
  constructor(
    private readonly fetchJson: FetchJson,
    private readonly credentials: SpotifyCredentials,
  ) {}

  authorizeUrl(redirectUri: string, state: string): string {
    const query = new URLSearchParams({
      client_id: this.credentials.clientId,
      response_type: "code",
      redirect_uri: redirectUri,
      state,
      scope: SPOTIFY_SCOPES.join(" "),
      show_dialog: "true",
    });
    return `${ACCOUNTS}/authorize?${query.toString()}`;
  }

  exchangeCode(code: string, redirectUri: string): Promise<SpotifyTokens> {
    return this.token({
      grant_type: "authorization_code",
      code,
      redirect_uri: redirectUri,
    });
  }

  refresh(refreshToken: string): Promise<SpotifyTokens> {
    return this.token({
      grant_type: "refresh_token",
      refresh_token: refreshToken,
    });
  }

  private async token(form: Record<string, string>): Promise<SpotifyTokens> {
    const { clientId, clientSecret } = this.credentials;
    const basic = Buffer.from(`${clientId}:${clientSecret}`).toString("base64");
    const { status, json } = await this.send(`${ACCOUNTS}/api/token`, {
      method: "POST",
      headers: {
        Authorization: `Basic ${basic}`,
        "Content-Type": "application/x-www-form-urlencoded",
      },
      body: new URLSearchParams(form).toString(),
    });
    const body = asRecord(json);
    if (status === 400 && body?.error === "invalid_grant")
      throw new SpotifyError("reconnect");
    if (status === 429) throw new SpotifyError("rate-limited");
    const accessToken = asString(body?.access_token);
    const expiresInSeconds = asNumber(body?.expires_in);
    if (status !== 200 || !accessToken || expiresInSeconds === undefined)
      throw new SpotifyError("unavailable");
    return {
      accessToken,
      expiresInSeconds,
      refreshToken: asString(body?.refresh_token),
    };
  }

  async displayName(accessToken: string): Promise<string | null> {
    const { status, json } = await this.call(accessToken, "GET", "/me");
    if (status !== 200) throw failureFor(status, json);
    return asString(asRecord(json)?.display_name) ?? null;
  }

  async nowPlaying(accessToken: string): Promise<SpotifyTrack | null> {
    const { status, json } = await this.call(
      accessToken,
      "GET",
      "/me/player/currently-playing?additional_types=track",
    );
    if (status === 204) return null;
    if (status !== 200) throw failureFor(status, json);
    const body = asRecord(json);
    const item = asRecord(body?.item);
    const title = asString(item?.name);
    if (!item || !title) return null;
    const album = asRecord(item.album);
    const link = https(asRecord(item.external_urls)?.spotify);
    return {
      title,
      artists: asArray(item.artists)
        .map((a) => asString(asRecord(a)?.name))
        .filter((a): a is string => a !== undefined),
      album: asString(album?.name) ?? null,
      imageUrl: largestImage(album?.images),
      url: link?.startsWith("https://open.spotify.com/") ? link : null,
      isPlaying: body?.is_playing === true,
    };
  }

  async playlists(accessToken: string): Promise<SpotifyPlaylist[]> {
    const all: SpotifyPlaylist[] = [];
    for (let page = 0; page < PLAYLIST_MAX_PAGES; page++) {
      const { status, json } = await this.call(
        accessToken,
        "GET",
        `/me/playlists?limit=${PLAYLIST_PAGE}&offset=${page * PLAYLIST_PAGE}`,
      );
      if (status !== 200) throw failureFor(status, json);
      const body = asRecord(json);
      for (const raw of asArray(body?.items)) {
        const playlist = asRecord(raw);
        const id = asString(playlist?.id);
        const name = asString(playlist?.name);
        if (id && name) {
          all.push({ id, name, imageUrl: largestImage(playlist?.images) });
        }
      }
      if (!asString(body?.next)) break;
    }
    return all;
  }

  /** Starts [playlistId], or resumes what was playing when there is none. */
  async play(accessToken: string, playlistId: string | null): Promise<void> {
    const { status, json } = await this.call(
      accessToken,
      "PUT",
      "/me/player/play",
      playlistId
        ? JSON.stringify({ context_uri: `spotify:playlist:${playlistId}` })
        : undefined,
    );
    if (status >= 200 && status < 300) return;
    if (errorReason(json) === "ALREADY_PLAYING") return;
    throw failureFor(status, json);
  }

  async pause(accessToken: string): Promise<void> {
    const { status, json } = await this.call(
      accessToken,
      "PUT",
      "/me/player/pause",
    );
    if (status >= 200 && status < 300) return;
    if (errorReason(json) === "ALREADY_PAUSED") return;
    throw failureFor(status, json);
  }

  private call(
    accessToken: string,
    method: "GET" | "PUT",
    path: string,
    body?: string,
  ): Promise<{ status: number; json: unknown }> {
    return this.send(`${API}${path}`, {
      method,
      headers: {
        Authorization: `Bearer ${accessToken}`,
        ...(body === undefined ? {} : { "Content-Type": "application/json" }),
      },
      body,
    });
  }

  private async send(
    url: string,
    init: {
      method: "GET" | "POST" | "PUT";
      headers: Record<string, string>;
      body?: string;
    },
  ): Promise<{ status: number; json: unknown }> {
    try {
      return await this.fetchJson(url, {
        ...init,
        signal: AbortSignal.timeout(TIMEOUT_MS),
      });
    } catch {
      // Network failures and timeouts. Nothing from the request is kept.
      throw new SpotifyError("unavailable");
    }
  }
}
