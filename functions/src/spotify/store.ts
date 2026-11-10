import type { Firestore } from "firebase-admin/firestore";

export interface SpotifyLink {
  status: "linked" | "reconnect";
  accessToken: string;
  /** Epoch milliseconds. */
  accessTokenExpiresAt: number;
  refreshToken: string;
  displayName: string | null;
}

export interface SpotifyLinkState {
  nonceHash: string;
  /** Epoch milliseconds. */
  expiresAt: number;
}

export interface SpotifyStore {
  /** One pending login per user: a new one replaces the last. */
  saveState(uid: string, state: SpotifyLinkState): Promise<void>;
  /** True once only, for a matching login that hasn't expired. */
  consumeState(uid: string, nonceHash: string, now: number): Promise<boolean>;
  loadLink(uid: string): Promise<SpotifyLink | null>;
  saveLink(uid: string, link: SpotifyLink): Promise<void>;
  deleteLink(uid: string): Promise<void>;
}

/**
 * Under `private_integrations/{uid}`: closed to clients by the rules' default
 * deny, and removed by account deletion (docs/05).
 */
export const spotifyLinkPath = (uid: string): string =>
  `private_integrations/${uid}/services/spotify`;
export const spotifyStatePath = (uid: string): string =>
  `private_integrations/${uid}/services/spotifyLinkState`;

export class FirestoreSpotifyStore implements SpotifyStore {
  constructor(private readonly db: Firestore) {}

  async saveState(uid: string, state: SpotifyLinkState): Promise<void> {
    await this.db.doc(spotifyStatePath(uid)).set(state);
  }

  consumeState(uid: string, nonceHash: string, now: number): Promise<boolean> {
    const ref = this.db.doc(spotifyStatePath(uid));
    return this.db.runTransaction(async (tx) => {
      const snapshot = await tx.get(ref);
      const state = snapshot.data() as SpotifyLinkState | undefined;
      if (!state || state.nonceHash !== nonceHash) return false;
      tx.delete(ref);
      return now < state.expiresAt;
    });
  }

  async loadLink(uid: string): Promise<SpotifyLink | null> {
    const snapshot = await this.db.doc(spotifyLinkPath(uid)).get();
    return (snapshot.data() as SpotifyLink | undefined) ?? null;
  }

  async saveLink(uid: string, link: SpotifyLink): Promise<void> {
    await this.db.doc(spotifyLinkPath(uid)).set(link);
  }

  async deleteLink(uid: string): Promise<void> {
    const batch = this.db.batch();
    batch.delete(this.db.doc(spotifyLinkPath(uid)));
    batch.delete(this.db.doc(spotifyStatePath(uid)));
    await batch.commit();
  }
}
