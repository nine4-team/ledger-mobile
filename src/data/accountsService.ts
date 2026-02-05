import { addDoc, collection, doc, serverTimestamp, setDoc } from '@react-native-firebase/firestore';
import { auth, db, isFirebaseConfigured } from '../firebase/firebase';

export type AccountSummary = {
  id: string;
  name: string;
  ownerUid?: string | null;
  createdAt?: unknown;
  updatedAt?: unknown;
};

export async function createAccountWithOwner(params: {
  name: string;
  ownerUid?: string | null;
  ownerEmail?: string | null;
  ownerName?: string | null;
}): Promise<AccountSummary> {
  if (!isFirebaseConfigured || !db) {
    throw new Error('Firebase is not configured.');
  }
  const ownerUid = params.ownerUid ?? auth?.currentUser?.uid ?? null;
  if (!ownerUid) {
    throw new Error('Must be signed in to create an account.');
  }
  const now = serverTimestamp();
  const accountRef = await addDoc(collection(db, 'accounts'), {
    name: params.name.trim(),
    ownerUid,
    createdAt: now,
    updatedAt: now,
  });
  await setDoc(
    doc(db, `accounts/${accountRef.id}/users/${ownerUid}`),
    {
      uid: ownerUid,
      role: 'owner',
      email: params.ownerEmail ?? null,
      name: params.ownerName ?? null,
      createdAt: now,
      updatedAt: now,
    },
    { merge: true }
  );
  return { id: accountRef.id, name: params.name.trim(), ownerUid };
}
