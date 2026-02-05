import { collection, doc, onSnapshot } from '@react-native-firebase/firestore';
import { db, isFirebaseConfigured } from '../firebase/firebase';

export type AccountMember = {
  id: string;
  accountId: string;
  uid: string;
  role: 'owner' | 'admin' | 'user';
  email?: string | null;
  name?: string | null;
  createdAt?: unknown;
  updatedAt?: unknown;
};

type Unsubscribe = () => void;

export function subscribeToAccountMember(
  accountId: string,
  uid: string,
  onChange: (member: AccountMember | null) => void
): Unsubscribe {
  if (!isFirebaseConfigured || !db) {
    onChange(null);
    return () => {};
  }
  const ref = doc(db, `accounts/${accountId}/users/${uid}`);
  return onSnapshot(
    ref,
    (snapshot) => {
      if (!snapshot.exists) {
        onChange(null);
        return;
      }
      const data = snapshot.data() as AccountMember;
      onChange({ ...data, id: uid, uid, accountId });
    },
    (error) => {
      console.warn('[accountMembersService] member subscription failed', error);
      onChange(null);
    }
  );
}

export function subscribeToAccountMembers(
  accountId: string,
  onChange: (members: AccountMember[]) => void
): Unsubscribe {
  if (!isFirebaseConfigured || !db) {
    onChange([]);
    return () => {};
  }
  const collectionRef = collection(db, `accounts/${accountId}/users`);
  return onSnapshot(
    collectionRef,
    (snapshot) => {
      const members = snapshot.docs.map(
        (doc) => ({ ...(doc.data() as object), id: doc.id, uid: doc.id, accountId } as AccountMember)
      );
      onChange(members);
    },
    (error) => {
      console.warn('[accountMembersService] members subscription failed', error);
      onChange([]);
    }
  );
}
