/**
 * Native Firebase SDK initialization (React Native)
 *
 * This module uses @react-native-firebase/* packages which provide:
 * - Native Firestore offline persistence ("Magic Notebook" behavior)
 * - Native Auth persistence
 * - Proper offline-ready support for React Native apps
 *
 * This is the default backend mode for offline-ready apps.
 * Requires a dev client build (not Expo Go).
 */

import firebaseApp from '@react-native-firebase/app';
import auth, { FirebaseAuthTypes } from '@react-native-firebase/auth';
import firestore, { FirebaseFirestoreTypes } from '@react-native-firebase/firestore';
import functions, { FirebaseFunctionsTypes } from '@react-native-firebase/functions';

let app: firebaseApp.FirebaseApp | null = null;
let authInstance: FirebaseAuthTypes.Module | null = null;
let db: FirebaseFirestoreTypes.Module | null = null;
let functionsInstance: FirebaseFunctionsTypes.Module | null = null;
export let isFirebaseConfigured = false;

const useEmulators = process.env.EXPO_PUBLIC_USE_FIREBASE_EMULATORS === 'true';
// Dev-only convenience: if you're bypassing auth entirely, don't initialize Firebase.
// This avoids confusing errors (like auth/invalid-api-key) when demoing without real keys.
const bypassFirebase = process.env.EXPO_PUBLIC_BYPASS_AUTH === 'true';

if (!bypassFirebase) {
  try {
    // Initialize Firebase App (native SDK auto-initializes from google-services.json/GoogleService-Info.plist)
    // If you need to initialize manually, use: firebaseApp.initializeApp()
    app = firebaseApp.app();
    isFirebaseConfigured = true;

    // Initialize Auth (native SDK)
    authInstance = auth();

    // Configure Auth emulator if needed
    if (useEmulators && authInstance) {
      const authHost = process.env.EXPO_PUBLIC_FIREBASE_AUTH_EMULATOR_HOST || 'localhost';
      const authPort = process.env.EXPO_PUBLIC_FIREBASE_AUTH_EMULATOR_PORT || '9099';
      authInstance.useEmulator(`http://${authHost}:${authPort}`);
    }

    // Initialize Firestore (native SDK with offline persistence enabled by default)
    db = firestore();

    // Configure Firestore emulator if needed
    if (useEmulators && db) {
      const firestoreHost = process.env.EXPO_PUBLIC_FIRESTORE_EMULATOR_HOST || 'localhost';
      const firestorePort = process.env.EXPO_PUBLIC_FIRESTORE_EMULATOR_PORT || '8080';
      db.useEmulator(firestoreHost, parseInt(firestorePort, 10));
    }

    // Enable Firestore offline persistence (enabled by default in native SDK)
    // Native Firestore automatically persists data locally and syncs when online
    // Cache size is unlimited by default - this is the "Magic Notebook" behavior

    // Initialize Functions (native SDK)
    functionsInstance = functions();

    // Configure Functions emulator if needed
    if (useEmulators && functionsInstance) {
      const functionsHost = process.env.EXPO_PUBLIC_FUNCTIONS_EMULATOR_HOST || 'localhost';
      const functionsPort = process.env.EXPO_PUBLIC_FUNCTIONS_EMULATOR_PORT || '5001';
      functionsInstance.useEmulator(functionsHost, parseInt(functionsPort, 10));
    }
  } catch (error) {
    console.warn(
      '[firebase.native] Missing native Firebase config. ' +
        'Add google-services.json / GoogleService-Info.plist and rebuild the dev client.'
    );
    // Don't throw - let the app continue, but Firebase calls will fail.
  }
}

export { authInstance as auth, db, functionsInstance as functions };
