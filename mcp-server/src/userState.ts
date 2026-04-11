import type { Firestore } from "firebase-admin/firestore";

/**
 * Per-uid MCP session state stored in Firestore so `switch_account`
 * persists across stateless Cloud Run requests and multiple instances.
 *
 * Path: mcpUserState/{uid}
 */

export async function getActiveAccountForUid(
  db: Firestore,
  uid: string,
): Promise<string | null> {
  const snap = await db.doc(`mcpUserState/${uid}`).get();
  if (!snap.exists) return null;
  const data = snap.data();
  return (data?.activeAccountId as string | undefined) ?? null;
}

export async function setActiveAccountForUid(
  db: Firestore,
  uid: string,
  accountId: string,
): Promise<void> {
  await db.doc(`mcpUserState/${uid}`).set(
    { activeAccountId: accountId, updatedAt: new Date() },
    { merge: true },
  );
}
