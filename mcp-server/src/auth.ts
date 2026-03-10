import admin from "firebase-admin";
import type { Firestore } from "firebase-admin/firestore";

/**
 * Verify a Firebase ID token and return the decoded UID.
 * Throws if the token is invalid or expired.
 */
export async function verifyToken(idToken: string): Promise<string> {
  const decoded = await admin.auth().verifyIdToken(idToken);
  return decoded.uid;
}

/**
 * Look up the account ID for a given user UID.
 * Queries the members subcollection across all accounts.
 */
export async function resolveAccountId(
  db: Firestore,
  uid: string
): Promise<string> {
  const snapshot = await db
    .collectionGroup("members")
    .where("uid", "==", uid)
    .limit(1)
    .get();

  if (snapshot.empty) {
    throw new Error(`No account membership found for UID ${uid}`);
  }

  // Path: accounts/{accountId}/members/{memberId}
  const memberDoc = snapshot.docs[0];
  const parts = memberDoc.ref.path.split("/");
  return parts[1]; // accountId
}
