import { doc, onSnapshot, serverTimestamp, setDoc } from '@react-native-firebase/firestore';
import { db, isFirebaseConfigured } from '../firebase/firebase';
import { trackPendingWrite } from '../sync/pendingWrites';

export type VendorDefaults = {
  vendors: string[];
  createdAt?: unknown;
  updatedAt?: unknown;
};

type Unsubscribe = () => void;

const DEFAULT_SLOTS = 10;

function normalizeSlots(vendors: string[] | undefined | null): string[] {
  const slots = Array.isArray(vendors) ? vendors.slice(0, DEFAULT_SLOTS) : [];
  while (slots.length < DEFAULT_SLOTS) {
    slots.push('');
  }
  return slots;
}

export function subscribeToVendorDefaults(
  accountId: string,
  onChange: (vendors: string[]) => void
): Unsubscribe {
  if (!isFirebaseConfigured || !db) {
    onChange(normalizeSlots([]));
    return () => {};
  }
  const ref = doc(db, `accounts/${accountId}/presets/default/vendors/default`);
  return onSnapshot(
    ref,
    (snapshot) => {
      if (!snapshot.exists) {
        onChange(normalizeSlots([]));
        return;
      }
      const data = snapshot.data() as VendorDefaults | undefined;
      onChange(normalizeSlots(data?.vendors));
    },
    (error) => {
      console.warn('[vendorDefaultsService] subscription failed', error);
      onChange(normalizeSlots([]));
    }
  );
}

export function saveVendorDefaults(accountId: string, vendors: string[]): void {
  if (!isFirebaseConfigured || !db) {
    throw new Error('Firebase is not configured.');
  }
  const now = serverTimestamp();
  setDoc(
    doc(db, `accounts/${accountId}/presets/default/vendors/default`),
    {
      vendors,
      updatedAt: now,
    },
    { merge: true }
  ).catch(err => console.error('[vendorDefaults] saveVendorDefaults failed:', err));
  trackPendingWrite();
}

export function replaceVendorSlots(accountId: string, vendors: string[]): void {
  saveVendorDefaults(accountId, normalizeSlots(vendors));
}
