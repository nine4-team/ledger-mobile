import type { Firestore } from "firebase-admin/firestore";
import { getAccountId } from "../context.js";

/** Base path for the current account. */
export function accountPath(): string {
  return `accounts/${getAccountId()}`;
}

/** Get a collection reference scoped to the current account. */
export function accountCollection(db: Firestore, collection: string) {
  return db.collection(`${accountPath()}/${collection}`);
}

/** Get a subcollection under a specific document. */
export function subcollection(
  db: Firestore,
  parentCollection: string,
  parentId: string,
  childCollection: string
) {
  return db.collection(
    `${accountPath()}/${parentCollection}/${parentId}/${childCollection}`
  );
}

/** Read all docs from a query and attach document IDs. */
export async function queryDocs<T>(
  query: FirebaseFirestore.Query
): Promise<(T & { id: string })[]> {
  const snapshot = await query.get();
  return snapshot.docs.map((doc) => ({
    id: doc.id,
    ...(doc.data() as T),
  }));
}

/** Read a single document by ID. Returns null if not found. */
export async function getDoc<T>(
  db: Firestore,
  collection: string,
  docId: string
): Promise<(T & { id: string }) | null> {
  const ref = db.doc(`${accountPath()}/${collection}/${docId}`);
  const snap = await ref.get();
  if (!snap.exists) return null;
  return { id: snap.id, ...(snap.data() as T) };
}

/**
 * Read many docs by ID in a single round-trip using Firestore `getAll()`.
 * Returns `{ found, missing }` in request order. Input must be non-empty.
 */
export async function getDocs<T>(
  db: Firestore,
  collection: string,
  ids: string[]
): Promise<{ found: (T & { id: string })[]; missing: string[] }> {
  if (ids.length === 0) return { found: [], missing: [] };
  const refs = ids.map((id) => db.doc(`${accountPath()}/${collection}/${id}`));
  const snaps = await db.getAll(...refs);
  const found: (T & { id: string })[] = [];
  const missing: string[] = [];
  for (let i = 0; i < snaps.length; i++) {
    const snap = snaps[i];
    if (snap.exists) {
      found.push({ id: snap.id, ...(snap.data() as T) });
    } else {
      missing.push(ids[i]);
    }
  }
  return { found, missing };
}
