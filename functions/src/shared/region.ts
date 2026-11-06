/**
 * Where every function runs: next to the Firestore database, which can't move.
 * The app's `functionsRegion` (app_config.dart) must match, and a Flutter test
 * checks that it does.
 */
export const REGION = "asia-south1";
