import { getFirestore } from "firebase-admin/firestore";
import { logger } from "firebase-functions";
import { defineSecret } from "firebase-functions/params";
import {
  HttpsError,
  onCall,
  onRequest,
  type CallableRequest,
  type FunctionsErrorCode,
} from "firebase-functions/v2/https";
import { z } from "zod";

import { parseInput } from "../catalog/callables";
import { nodeFetchJson } from "../catalog/http";
import { requireUid } from "../shared/auth";
import { REGION } from "../shared/region";
import { SpotifyError, type SpotifyReason } from "./api";
import { SpotifyService, type LinkOutcome } from "./service";
import { FirestoreSpotifyStore } from "./store";

const SPOTIFY_CLIENT_ID = defineSecret("SPOTIFY_CLIENT_ID");
const SPOTIFY_CLIENT_SECRET = defineSecret("SPOTIFY_CLIENT_SECRET");

const isEmulator = process.env.FUNCTIONS_EMULATOR === "true";
const EMULATOR_PORT = 5001; // firebase.json
const CALLBACK_NAME = "spotifyOAuthCallback";

const secrets = [SPOTIFY_CLIENT_ID, SPOTIFY_CLIENT_SECRET];
const options = {
  region: REGION,
  secrets,
  enforceAppCheck: !isEmulator,
  maxInstances: 10,
  memory: "256MiB" as const,
  timeoutSeconds: 30,
};

/** Must be registered, character for character, in the Spotify app. */
export function redirectUri(
  project: string | undefined,
  emulator: boolean,
): string {
  return emulator
    ? `http://127.0.0.1:${EMULATOR_PORT}/${project}/${REGION}/${CALLBACK_NAME}`
    : `https://${REGION}-${project}.cloudfunctions.net/${CALLBACK_NAME}`;
}

function secretValue(secret: typeof SPOTIFY_CLIENT_ID): string {
  try {
    return secret.value().trim();
  } catch {
    return "";
  }
}

let cached: SpotifyService | undefined;
function spotify(): SpotifyService {
  cached ??= new SpotifyService({
    fetchJson: nodeFetchJson,
    store: new FirestoreSpotifyStore(getFirestore()),
    credentials: () => {
      const clientId = secretValue(SPOTIFY_CLIENT_ID);
      const clientSecret = secretValue(SPOTIFY_CLIENT_SECRET);
      return clientId && clientSecret ? { clientId, clientSecret } : null;
    },
    redirectUri: () => redirectUri(process.env.GCLOUD_PROJECT, isEmulator),
  });
  return cached;
}

const CODES: Record<SpotifyReason, FunctionsErrorCode> = {
  "not-configured": "failed-precondition",
  "not-linked": "failed-precondition",
  reconnect: "failed-precondition",
  "not-allowlisted": "permission-denied",
  "no-device": "failed-precondition",
  "premium-required": "permission-denied",
  "rate-limited": "resource-exhausted",
  unavailable: "unavailable",
  "token-rejected": "unavailable",
};

/** The app reads the reason from the error message. */
async function handle<T>(
  request: CallableRequest,
  run: (uid: string) => Promise<T>,
): Promise<T> {
  const uid = requireUid(request);
  try {
    return await run(uid);
  } catch (error) {
    if (error instanceof HttpsError) throw error;
    if (error instanceof SpotifyError)
      throw new HttpsError(CODES[error.reason], error.reason);
    logger.error("spotify callable failed", {
      name: error instanceof Error ? error.name : "unknown",
    });
    throw new HttpsError("internal", "Something went wrong");
  }
}

const PlayInput = z.object({
  playlistId: z
    .string()
    .regex(/^[A-Za-z0-9]{10,64}$/)
    .optional(),
});

export const spotifyStatus = onCall(options, (request) =>
  handle(request, (uid) => spotify().status(uid)),
);

export const spotifyBeginLink = onCall(options, (request) =>
  handle(request, async (uid) => ({ url: await spotify().beginLink(uid) })),
);

export const spotifyDisconnect = onCall(options, (request) =>
  handle(request, async (uid) => {
    await spotify().disconnect(uid);
    return { unlinked: true };
  }),
);

export const spotifyNowPlaying = onCall(options, (request) =>
  handle(request, async (uid) => ({ track: await spotify().nowPlaying(uid) })),
);

export const spotifyListPlaylists = onCall(options, (request) =>
  handle(request, async (uid) => ({
    playlists: await spotify().playlists(uid),
  })),
);

export const spotifyPlay = onCall(options, (request) =>
  handle(request, async (uid) => {
    const { playlistId } = parseInput(PlayInput, request.data);
    await spotify().play(uid, playlistId ?? null);
    return { ok: true };
  }),
);

export const spotifyPause = onCall(options, (request) =>
  handle(request, async (uid) => {
    await spotify().pause(uid);
    return { ok: true };
  }),
);

const MESSAGES: Record<LinkOutcome, { title: string; body: string }> = {
  linked: {
    title: "Spotify is linked",
    body: "You can close this page and return to Chapter.",
  },
  denied: {
    title: "Spotify wasn't linked",
    body: "You chose not to give access. You can close this page and return to Chapter.",
  },
  "not-allowlisted": {
    title: "This Spotify account can't be linked yet",
    body: "Spotify limits this app to a small list of accounts, and yours isn't on it. Nothing was saved. You can keep using Chapter as usual.",
  },
  expired: {
    title: "That link has expired",
    body: "Return to Chapter and tap Link Spotify again.",
  },
  failed: {
    title: "Something went wrong",
    body: "Spotify wasn't linked. Return to Chapter and try again.",
  },
};

/** Fixed text only: nothing from the request is ever echoed into the page. */
export function callbackPage(outcome: LinkOutcome): string {
  const { title, body } = MESSAGES[outcome];
  return `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Chapter</title><style>body{font-family:-apple-system,system-ui,sans-serif;margin:0;padding:64px 24px;text-align:center;color:#1c1c1a;background:#fbf8f6}h1{font-size:24px;font-weight:600}p{font-size:17px;line-height:1.5}</style></head><body><h1>${title}</h1><p>${body}</p></body></html>`;
}

const text = (value: unknown): string | undefined =>
  typeof value === "string" && value.length <= 2048 ? value : undefined;

/** Spotify's redirect target. Public, so its only protection is `state`. */
export const spotifyOAuthCallback = onRequest(
  {
    region: REGION,
    secrets,
    invoker: "public",
    maxInstances: 5,
    memory: "256MiB",
    timeoutSeconds: 30,
  },
  async (request, response) => {
    if (request.method !== "GET") {
      response.status(405).send("");
      return;
    }
    let outcome: LinkOutcome = "failed";
    try {
      outcome = await spotify().completeLink({
        code: text(request.query.code),
        state: text(request.query.state),
        error: text(request.query.error),
      });
    } catch (error) {
      logger.error("spotify callback failed", {
        name: error instanceof Error ? error.name : "unknown",
      });
    }
    response
      .set("Cache-Control", "no-store")
      .set("Referrer-Policy", "no-referrer")
      .set(
        "Content-Security-Policy",
        "default-src 'none'; style-src 'unsafe-inline'",
      )
      .status(200)
      .type("html")
      .send(callbackPage(outcome));
  },
);
