/**
 * Chapter Cloud Functions entry point.
 *
 * Phase 3: catalog callables (search, ISBN lookup, work/author/series details,
 * trending). Phase 8: deleteAccount.
 */
import { initializeApp } from "firebase-admin/app";

initializeApp();

export {
  catalogGetAuthor,
  catalogGetSeries,
  catalogGetWork,
  catalogLookupIsbn,
  catalogSearch,
  catalogTrending,
} from "./catalog/callables";
export { deleteAccount, sweepDeletedAccounts } from "./account/deleteAccount";
