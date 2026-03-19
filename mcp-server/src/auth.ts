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
    .collectionGroup("users")
    .where("uid", "==", uid)
    .limit(1)
    .get();

  if (snapshot.empty) {
    throw new Error(`No account membership found for UID ${uid}`);
  }

  // Path: accounts/{accountId}/users/{userId}
  const memberDoc = snapshot.docs[0];
  const parts = memberDoc.ref.path.split("/");
  return parts[1]; // accountId
}

export interface AccountMembership {
  accountId: string;
  accountName?: string;
  role?: string;
}

/**
 * Look up ALL account memberships for a given user UID.
 * Returns account IDs with names (fetched from account docs).
 */
export async function resolveAllAccounts(
  db: Firestore,
  uid: string
): Promise<AccountMembership[]> {
  const snapshot = await db
    .collectionGroup("users")
    .where("uid", "==", uid)
    .get();

  if (snapshot.empty) {
    throw new Error(`No account membership found for UID ${uid}`);
  }

  const accounts: AccountMembership[] = [];
  for (const doc of snapshot.docs) {
    // Path: accounts/{accountId}/users/{userId}
    const parts = doc.ref.path.split("/");
    const accountId = parts[1];
    const memberData = doc.data();

    // Fetch account name
    const accountDoc = await db.doc(`accounts/${accountId}`).get();
    const accountData = accountDoc.exists ? accountDoc.data() : undefined;

    accounts.push({
      accountId,
      accountName: accountData?.name ?? accountData?.companyName ?? accountId,
      role: memberData?.role,
    });
  }

  return accounts;
}
