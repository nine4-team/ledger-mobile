/**
 * Repository interface for data access
 * Apps can implement online-first (Firestore) or offline-ready (native Firestore offline)
 */
export interface Repository<T> {
  list(): Promise<T[]>;
  get(id: string): Promise<T | null>;
  upsert(id: string, data: Partial<T>): Promise<void>;
  delete(id: string): Promise<void>;
}

/**
 * Online-first implementation: direct Firestore access
 */
import { collection, doc, getDoc, getDocs, setDoc, deleteDoc, query, where } from 'firebase/firestore';
import { db, isFirebaseConfigured } from '../firebase/firebase';

export class FirestoreRepository<T extends { id: string }> implements Repository<T> {
  constructor(private collectionPath: string) {}

  async list(): Promise<T[]> {
    if (!isFirebaseConfigured || !db) {
      return [];
    }
    const snapshot = await getDocs(collection(db, this.collectionPath));
    return snapshot.docs.map((doc) => ({ ...doc.data(), id: doc.id } as T));
  }

  async get(id: string): Promise<T | null> {
    if (!isFirebaseConfigured || !db) {
      return null;
    }
    const docRef = doc(db, this.collectionPath, id);
    const snapshot = await getDoc(docRef);
    if (!snapshot.exists()) {
      return null;
    }
    return { ...snapshot.data(), id: snapshot.id } as T;
  }

  async upsert(id: string, data: Partial<T>): Promise<void> {
    if (!isFirebaseConfigured || !db) {
      return;
    }
    const docRef = doc(db, this.collectionPath, id);
    await setDoc(docRef, data, { merge: true });
  }

  async delete(id: string): Promise<void> {
    if (!isFirebaseConfigured || !db) {
      return;
    }
    const docRef = doc(db, this.collectionPath, id);
    await deleteDoc(docRef);
  }

  async listByUser(uid: string): Promise<T[]> {
    if (!isFirebaseConfigured || !db) {
      return [];
    }
    const q = query(collection(db, this.collectionPath), where('uid', '==', uid));
    const snapshot = await getDocs(q);
    return snapshot.docs.map((doc) => ({ ...doc.data(), id: doc.id } as T));
  }
}

/**
 * Factory function to create a repository
 * In the future, this can be extended to return offline-ready implementations
 */
export function createRepository<T extends { id: string }>(
  collectionPath: string,
  mode: 'online' | 'offline' = 'online'
): Repository<T> {
  if (mode === 'offline') {
    // TODO: Return offline-ready implementation when implemented
    throw new Error('Offline-ready mode not yet implemented');
  }
  return new FirestoreRepository<T>(collectionPath);
}
