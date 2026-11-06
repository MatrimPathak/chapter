import { getFirestore } from "firebase-admin/firestore";
import { logger } from "firebase-functions";
import { defineSecret } from "firebase-functions/params";
import {
  HttpsError,
  onCall,
  type CallableRequest,
} from "firebase-functions/v2/https";
import { z } from "zod";

import { requireUid } from "../shared/auth";
import { FirestoreCatalogStore } from "./firestoreStore";
import { nodeFetchJson } from "./http";
import { MetadataOrchestrator } from "./orchestrator";
import { GoogleBooksProvider } from "./providers/googleBooks";
import { HardcoverProvider } from "./providers/hardcover";
import { OpenLibraryProvider } from "./providers/openLibrary";
import { TokenBucket } from "./rateLimiter";
import { CatalogError, CatalogService } from "./service";

const HARDCOVER_TOKEN = defineSecret("HARDCOVER_TOKEN");
const GOOGLE_BOOKS_KEY = defineSecret("GOOGLE_BOOKS_KEY");

const MAX_INSTANCES = 10;
const isEmulator = process.env.FUNCTIONS_EMULATOR === "true";

const options = {
  secrets: [HARDCOVER_TOKEN, GOOGLE_BOOKS_KEY],
  // App Check protects provider quotas (D7). The emulator has no attestation.
  enforceAppCheck: !isEmulator,
  maxInstances: MAX_INSTANCES,
  memory: "256MiB" as const,
  timeoutSeconds: 30,
};

let service: CatalogService | undefined;
function catalog(): CatalogService {
  if (!service) {
    const secret = (s: typeof HARDCOVER_TOKEN) => () => {
      try {
        return s.value().trim();
      } catch {
        return "";
      }
    };
    const orchestrator = new MetadataOrchestrator([
      // Each instance gets its share of Hardcover's 60 requests/minute.
      new HardcoverProvider(
        nodeFetchJson,
        secret(HARDCOVER_TOKEN),
        TokenBucket.perMinute(Math.floor(60 / MAX_INSTANCES)),
      ),
      new OpenLibraryProvider(nodeFetchJson),
      new GoogleBooksProvider(nodeFetchJson, secret(GOOGLE_BOOKS_KEY)),
    ]);
    service = new CatalogService(
      orchestrator,
      new FirestoreCatalogStore(getFirestore()),
    );
  }
  return service;
}

// ─── Input schemas ───

const providerRef = z.object({
  provider: z.enum(["hardcover", "openLibrary", "googleBooks"]),
  externalId: z
    .string()
    .min(1)
    .max(64)
    .regex(/^[A-Za-z0-9_-]+$/),
});
const internalId = z.string().uuid();

const SearchInput = z.object({
  text: z.string().trim().min(2).max(200),
  field: z
    .enum(["all", "title", "author", "isbn", "series", "publisher"])
    .default("all"),
  page: z.number().int().min(1).max(20).default(1),
  pageSize: z.number().int().min(5).max(40).default(20),
});
const IsbnInput = z.object({ isbn: z.string().trim().min(10).max(20) });
const WorkInput = z.union([
  z.object({ workId: internalId }),
  z.object({ ref: providerRef }),
]);
const AuthorInput = z.union([
  z.object({ authorId: internalId }),
  z.object({ ref: providerRef }),
]);
const SeriesInput = z.union([
  z.object({ seriesId: internalId }),
  z.object({ ref: providerRef }),
]);
const TrendingInput = z.object({
  limit: z.number().int().min(1).max(30).default(12),
});

export function parseInput<T extends z.ZodType>(
  schema: T,
  data: unknown,
): z.infer<T> {
  const result = schema.safeParse(data ?? {});
  if (!result.success) {
    throw new HttpsError(
      "invalid-argument",
      "Invalid request",
      result.error.issues.slice(0, 3),
    );
  }
  return result.data;
}

/** Maps domain errors to callable error codes; hides unexpected internals. */
async function handle<T>(
  request: CallableRequest,
  run: (uid: string) => Promise<T>,
): Promise<T> {
  const uid = requireUid(request);
  try {
    return await run(uid);
  } catch (error) {
    if (error instanceof HttpsError) throw error;
    if (error instanceof CatalogError)
      throw new HttpsError(error.code, error.message);
    logger.error("catalog callable failed", {
      error: error instanceof Error ? error.stack : String(error),
    });
    throw new HttpsError("internal", "Something went wrong");
  }
}

export const catalogSearch = onCall(options, (request) =>
  handle(request, (uid) => {
    const input = parseInput(SearchInput, request.data);
    return catalog().search(
      uid,
      { text: input.text, field: input.field },
      { page: input.page, pageSize: input.pageSize },
    );
  }),
);

export const catalogLookupIsbn = onCall(options, (request) =>
  handle(request, (uid) =>
    catalog().lookupIsbn(uid, parseInput(IsbnInput, request.data).isbn),
  ),
);

export const catalogGetWork = onCall(options, (request) =>
  handle(request, (uid) =>
    catalog().getWork(uid, parseInput(WorkInput, request.data)),
  ),
);

export const catalogGetAuthor = onCall(options, (request) =>
  handle(request, (uid) =>
    catalog().getAuthor(uid, parseInput(AuthorInput, request.data)),
  ),
);

export const catalogGetSeries = onCall(options, (request) =>
  handle(request, (uid) =>
    catalog().getSeries(uid, parseInput(SeriesInput, request.data)),
  ),
);

export const catalogTrending = onCall(options, (request) =>
  handle(request, (uid) =>
    catalog().trending(uid, parseInput(TrendingInput, request.data).limit),
  ),
);

/** Exposed for tests. */
export const schemas = {
  SearchInput,
  IsbnInput,
  WorkInput,
  AuthorInput,
  SeriesInput,
  TrendingInput,
};
