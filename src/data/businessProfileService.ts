import { doc, onSnapshot, serverTimestamp, setDoc } from '@react-native-firebase/firestore';
import storage from '@react-native-firebase/storage';
import { db, isFirebaseConfigured } from '../firebase/firebase';

export type BusinessProfile = {
  id: 'default';
  accountId: string;
  businessName: string;
  logo?: {
    url?: string | null;
    kind?: 'image';
    storagePath?: string | null;
  } | null;
  createdAt?: unknown;
  updatedAt?: unknown;
  updatedBy?: string | null;
};

type Unsubscribe = () => void;

export function subscribeToBusinessProfile(
  accountId: string,
  onChange: (profile: BusinessProfile | null) => void
): Unsubscribe {
  if (!isFirebaseConfigured || !db) {
    onChange(null);
    return () => {};
  }
  const ref = doc(db, `accounts/${accountId}/profile/default`);
  return onSnapshot(
    ref,
    (snapshot) => {
      if (!snapshot.exists) {
        onChange(null);
        return;
      }
      const data = snapshot.data() as BusinessProfile;
      onChange({ ...data, id: 'default', accountId });
    },
    (error) => {
      console.warn('[businessProfileService] subscription failed', error);
      onChange(null);
    }
  );
}

export async function saveBusinessProfile(
  accountId: string,
  updates: Pick<BusinessProfile, 'businessName' | 'logo'>,
  updatedBy?: string | null
): Promise<void> {
  if (!isFirebaseConfigured || !db) {
    throw new Error('Firebase is not configured.');
  }
  const now = serverTimestamp();
  await setDoc(
    doc(db, `accounts/${accountId}/profile/default`),
    {
      accountId,
      businessName: updates.businessName.trim(),
      logo: updates.logo ?? null,
      updatedBy: updatedBy ?? null,
      updatedAt: now,
    },
    { merge: true }
  );
}

export async function uploadBusinessLogo(params: {
  accountId: string;
  localUri: string;
  contentType?: string | null;
  fileName?: string | null;
}): Promise<{ url: string; storagePath: string }> {
  if (!isFirebaseConfigured) {
    throw new Error('Firebase is not configured.');
  }
  const safeName = params.fileName?.trim() || 'logo';
  const timestamp = Date.now();
  const storagePath = `accounts/${params.accountId}/profile/logo/${timestamp}_${safeName}`;
  const ref = storage().ref(storagePath);
  await ref.putFile(params.localUri, params.contentType ? { contentType: params.contentType } : undefined);
  const url = await ref.getDownloadURL();
  return { url, storagePath };
}
