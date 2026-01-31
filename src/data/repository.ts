/**
 * Repository interface for data access
 * Apps can implement online-first (Firestore) or offline-ready (native Firestore offline)
 */
export interface Repository<T> {
  list(): Promise<T[]>;
  get(id: string): Promise<T | null>;
  upsert(id: string, data: Partial<T>): Promise<void>;
  delete(id: string): Promise<void>;
  
  /**
   * Subscribe to real-time updates for a single document.
   * Returns an unsubscribe function.
   */
  subscribe(id: string, onChange: (item: T | null) => void): () => void;
  
  /**
   * Subscribe to real-time updates for the collection (list).
   * Returns an unsubscribe function.
   */
  subscribeList(onChange: (items: T[]) => void): () => void;
}

export type RepositoryMode = 'online' | 'offline';

/**
 * Online-first implementation: direct Firestore access
 */
import { db, isFirebaseConfigured } from '../firebase/firebase';

export class FirestoreRepository<T extends { id: string }> implements Repository<T> {
  constructor(
    private collectionPath: string,
    private mode: RepositoryMode = 'online'
  ) {}

  private async getDocWithPreference(docPath: string) {
    if (!db) return null;
    const ref = db.doc(docPath);

    // Both modes use native Firestore. The difference is *read preference*:
    // - online: server-first, fallback to cache
    // - offline: cache-first, fallback to server
    const preference =
      this.mode === 'offline'
        ? (['cache', 'server'] as const)
        : (['server', 'cache'] as const);

    for (const source of preference) {
      try {
        return await (ref as any).get({ source });
      } catch {
        // try next source
      }
    }
    return await ref.get();
  }

  private async getQueryWithPreference(query: unknown) {
    // query: FirebaseFirestoreTypes.Query, but keep it loose to avoid over-coupling types here.
    const preference =
      this.mode === 'offline'
        ? (['cache', 'server'] as const)
        : (['server', 'cache'] as const);

    for (const source of preference) {
      try {
        return await (query as any).get({ source });
      } catch {
        // try next source
      }
    }
    return await (query as any).get();
  }

  async list(): Promise<T[]> {
    if (!isFirebaseConfigured || !db) {
      return [];
    }
    const q = db.collection(this.collectionPath);
    const snapshot = await this.getQueryWithPreference(q);
    return snapshot.docs.map((d) => ({ ...(d.data() as object), id: d.id } as T));
  }

  async get(id: string): Promise<T | null> {
    if (!isFirebaseConfigured || !db) {
      return null;
    }
    const snapshot = await this.getDocWithPreference(`${this.collectionPath}/${id}`);
    if (!snapshot.exists) {
      return null;
    }
    return { ...(snapshot.data() as object), id: snapshot.id } as T;
  }

  async upsert(id: string, data: Partial<T>): Promise<void> {
    if (!isFirebaseConfigured || !db) {
      return;
    }
    await db.collection(this.collectionPath).doc(id).set(data as object, { merge: true });
  }

  async delete(id: string): Promise<void> {
    if (!isFirebaseConfigured || !db) {
      return;
    }
    await db.collection(this.collectionPath).doc(id).delete();
  }

  async listByUser(uid: string): Promise<T[]> {
    if (!isFirebaseConfigured || !db) {
      return [];
    }
    const q = db.collection(this.collectionPath).where('uid', '==', uid);
    const snapshot = await this.getQueryWithPreference(q);
    return snapshot.docs.map((d) => ({ ...(d.data() as object), id: d.id } as T));
  }

  /**
   * Subscribe to real-time updates for a single document.
   * Uses native Firestore onSnapshot for offline-ready behavior.
   */
  subscribe(id: string, onChange: (item: T | null) => void): () => void {
    if (!isFirebaseConfigured || !db) {
      onChange(null);
      return () => {};
    }

    const docRef = db.doc(`${this.collectionPath}/${id}`);
    
    // onSnapshot works offline with native Firestore persistence
    // It will fire immediately with cached data if available, then with server updates
    return docRef.onSnapshot(
      (snapshot) => {
        if (!snapshot.exists) {
          onChange(null);
          return;
        }
        onChange({ ...(snapshot.data() as object), id: snapshot.id } as T);
      },
      (error) => {
        console.error(`[FirestoreRepository] Error subscribing to ${this.collectionPath}/${id}:`, error);
        onChange(null);
      }
    );
  }

  /**
   * Subscribe to real-time updates for the collection (list).
   * Uses native Firestore onSnapshot for offline-ready behavior.
   */
  subscribeList(onChange: (items: T[]) => void): () => void {
    if (!isFirebaseConfigured || !db) {
      onChange([]);
      return () => {};
    }

    const collectionRef = db.collection(this.collectionPath);
    
    // onSnapshot works offline with native Firestore persistence
    // It will fire immediately with cached data if available, then with server updates
    return collectionRef.onSnapshot(
      (snapshot) => {
        const items = snapshot.docs.map((d) => ({ ...(d.data() as object), id: d.id } as T));
        onChange(items);
      },
      (error) => {
        console.error(`[FirestoreRepository] Error subscribing to ${this.collectionPath}:`, error);
        onChange([]);
      }
    );
  }
}

/**
 * Factory function to create a repository
 * 
 * Both 'online' and 'offline' modes use the native Firestore SDK.
 * - 'online': server-first reads, fallback to cache
 * - 'offline': cache-first reads, fallback to server
 * 
 * Both modes support real-time listeners via subscribe/subscribeList methods.
 * Native Firestore offline persistence enables offline-ready behavior automatically.
 * 
 * @param collectionPath - Firestore collection path (e.g., 'users/{uid}/items')
 * @param mode - 'online' (default) or 'offline' (cache-first preference)
 * @returns Repository instance (never throws, even if Firebase is not configured)
 */
export function createRepository<T extends { id: string }>(
  collectionPath: string,
  mode: RepositoryMode = 'online'
): Repository<T> {
  // Native-only: both modes use @react-native-firebase/firestore.
  // Mode controls read preference and listener behavior, not SDK choice.
  // This never throws - if Firebase is not configured, repository methods will return empty/null gracefully.
  return new FirestoreRepository<T>(collectionPath, mode);
}
