/**
 * Firebase initialization module (NATIVE ONLY).
 *
 * This skeleton is **native-first** and uses @react-native-firebase/* so that:
 * - Firestore offline persistence works as designed (native SDK "Magic Notebook")
 * - Auth persistence is native
 *
 * Expo Go is not supported for offline-ready mode.
 */

import firebaseApp from '@react-native-firebase/app';
import auth, { FirebaseAuthTypes } from '@react-native-firebase/auth';
import firestore, { FirebaseFirestoreTypes } from '@react-native-firebase/firestore';
import functions, { FirebaseFunctionsTypes } from '@react-native-firebase/functions';
import storage, { FirebaseStorageTypes } from '@react-native-firebase/storage';

let app: firebaseApp.FirebaseApp | null = null;
let authInstance: FirebaseAuthTypes.Module | null = null;
let db: FirebaseFirestoreTypes.Module | null = null;
let functionsInstance: FirebaseFunctionsTypes.Module | null = null;
let storageInstance: FirebaseStorageTypes.Module | null = null;

export let isFirebaseConfigured = false;

const useEmulators = process.env.EXPO_PUBLIC_USE_FIREBASE_EMULATORS === 'true';
// Dev-only convenience: if you're bypassing auth entirely, don't initialize Firebase.
// This avoids confusing errors (like auth/invalid-api-key) when demoing without real keys.
const bypassFirebase = process.env.EXPO_PUBLIC_BYPASS_AUTH === 'true';

if (!bypassFirebase) {
  try {
    // Native SDK auto-initializes from google-services.json / GoogleService-Info.plist.
    app = firebaseApp.app();
    isFirebaseConfigured = true;

    authInstance = auth();
    if (useEmulators && authInstance) {
      const authHost = process.env.EXPO_PUBLIC_FIREBASE_AUTH_EMULATOR_HOST || 'localhost';
      const authPort = process.env.EXPO_PUBLIC_FIREBASE_AUTH_EMULATOR_PORT || '9099';
      authInstance.useEmulator(`http://${authHost}:${authPort}`);
    }

    db = firestore();
    if (useEmulators && db) {
      const firestoreHost = process.env.EXPO_PUBLIC_FIRESTORE_EMULATOR_HOST || 'localhost';
      const firestorePort = process.env.EXPO_PUBLIC_FIRESTORE_EMULATOR_PORT || '8081';
      db.useEmulator(firestoreHost, parseInt(firestorePort, 10));
    }

    functionsInstance = functions();
    if (useEmulators && functionsInstance) {
      const functionsHost = process.env.EXPO_PUBLIC_FUNCTIONS_EMULATOR_HOST || 'localhost';
      const functionsPort = process.env.EXPO_PUBLIC_FUNCTIONS_EMULATOR_PORT || '5001';
      functionsInstance.useEmulator(functionsHost, parseInt(functionsPort, 10));
    }

    storageInstance = storage();
    if (useEmulators && storageInstance) {
      const storageHost = process.env.EXPO_PUBLIC_STORAGE_EMULATOR_HOST || 'localhost';
      const storagePort = process.env.EXPO_PUBLIC_STORAGE_EMULATOR_PORT || '9199';
      storageInstance.useEmulator(storageHost, parseInt(storagePort, 10));
    }
  } catch (error) {
    console.warn(
      '[firebase] Missing native Firebase config. ' +
        'Add google-services.json / GoogleService-Info.plist and rebuild the dev client.'
    );
    // Don't throw - let the app continue, but Firebase calls will fail.
    isFirebaseConfigured = false;
  }
}

export { authInstance as auth, db, functionsInstance as functions, storageInstance as storage };
