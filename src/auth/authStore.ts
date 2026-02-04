import { Platform } from 'react-native';
import { create } from 'zustand';
import firebaseAuth, { FirebaseAuthTypes } from '@react-native-firebase/auth';
import { GoogleSignin } from '@react-native-google-signin/google-signin';
import { auth, isFirebaseConfigured } from '../firebase/firebase';

interface AuthState {
  user: FirebaseAuthTypes.User | null;
  isInitialized: boolean;
  timedOutWithoutAuth: boolean;
  setUser: (user: FirebaseAuthTypes.User | null) => void;
  setInitialized: (isInitialized: boolean) => void;
  setTimedOutWithoutAuth: (timedOut: boolean) => void;
  signIn: (email: string, password: string) => Promise<void>;
  signUp: (email: string, password: string) => Promise<void>;
  signInWithGoogle: () => Promise<void>;
  signOut: () => Promise<void>;
  initialize: () => () => void; // Returns cleanup function
  retryInitialize: () => void;
}

const AUTH_INIT_TIMEOUT_MS = 7000; // 7 seconds safety timeout
let authUnsubscribe: (() => void) | null = null;
let authTimeoutId: ReturnType<typeof setTimeout> | null = null;
let googleConfigured = false;

const googleWebClientId = process.env.EXPO_PUBLIC_GOOGLE_WEB_CLIENT_ID;
const googleIosClientId = process.env.EXPO_PUBLIC_GOOGLE_IOS_CLIENT_ID;

const ensureGoogleConfigured = () => {
  if (googleConfigured) return;
  if (!googleWebClientId) {
    throw new Error('Google sign-in requires EXPO_PUBLIC_GOOGLE_WEB_CLIENT_ID to be set.');
  }
  GoogleSignin.configure({
    webClientId: googleWebClientId,
    iosClientId: googleIosClientId,
  });
  googleConfigured = true;
};

const clearAuthSubscription = () => {
  if (authTimeoutId) {
    clearTimeout(authTimeoutId);
    authTimeoutId = null;
  }
  if (authUnsubscribe) {
    authUnsubscribe();
    authUnsubscribe = null;
  }
};

const startAuthSubscription = (set: (partial: Partial<AuthState>) => void, get: () => AuthState) => {
  if (!isFirebaseConfigured || !auth) {
    clearAuthSubscription();
    set({ user: null, isInitialized: true, timedOutWithoutAuth: false });
    return () => {};
  }

  clearAuthSubscription();
  set({ timedOutWithoutAuth: false });

  authTimeoutId = setTimeout(() => {
    const state = get();
    if (!state.isInitialized) {
      set({ timedOutWithoutAuth: true, isInitialized: true });
    }
  }, AUTH_INIT_TIMEOUT_MS);

  authUnsubscribe = auth.onAuthStateChanged((user) => {
    if (authTimeoutId) {
      clearTimeout(authTimeoutId);
      authTimeoutId = null;
    }
    console.log('[auth] onAuthStateChanged', { email: user?.email, uid: user?.uid });
    set({ user, isInitialized: true, timedOutWithoutAuth: false });
  });

  return () => {
    clearAuthSubscription();
  };
};

export const useAuthStore = create<AuthState>((set, get) => ({
  user: null,
  isInitialized: false,
  timedOutWithoutAuth: false,
  setUser: (user) => set({ user }),
  setInitialized: (isInitialized) => set({ isInitialized }),
  setTimedOutWithoutAuth: (timedOut) => set({ timedOutWithoutAuth: timedOut }),
  signIn: async (email: string, password: string) => {
    if (!isFirebaseConfigured || !auth) {
      throw new Error(
        'Firebase is not configured. Add native config files and rebuild the dev client.'
      );
    }
    await auth.signInWithEmailAndPassword(email, password);
  },
  signUp: async (email: string, password: string) => {
    if (!isFirebaseConfigured || !auth) {
      throw new Error(
        'Firebase is not configured. Add native config files and rebuild the dev client.'
      );
    }
    await auth.createUserWithEmailAndPassword(email, password);
  },
  signInWithGoogle: async () => {
    if (!isFirebaseConfigured || !auth) {
      throw new Error(
        'Firebase is not configured. Add native config files and rebuild the dev client.'
      );
    }

    ensureGoogleConfigured();

    // Android-only check (kept for later re-enable)
    // if (Platform.OS === 'android') {
    //   await GoogleSignin.hasPlayServices({ showPlayServicesUpdateDialog: true });
    // }

    const signInResult = await GoogleSignin.signIn();
    console.log('[auth][google] signIn result', JSON.stringify(signInResult, null, 2));
    let idToken = signInResult.data?.idToken;
    if (!idToken) {
      const tokens = await GoogleSignin.getTokens();
      console.log('[auth][google] tokens', { hasIdToken: Boolean(tokens?.idToken) });
      idToken = tokens?.idToken;
    }
    if (!idToken) {
      throw new Error('Google sign-in did not return an ID token.');
    }

    const credential = firebaseAuth.GoogleAuthProvider.credential(idToken);
    try {
      console.log('[auth][google] calling signInWithCredential');
      await auth.signInWithCredential(credential);
      console.log('[auth][google] signInWithCredential success');
    } catch (error: any) {
      console.warn('[auth][google] firebase signInWithCredential failed', {
        code: error?.code,
        message: error?.message,
      });
      throw error;
    }
  },
  signOut: async () => {
    if (!isFirebaseConfigured || !auth) {
      set({ user: null });
      return;
    }
    await auth.signOut();
    set({ user: null });
  },
  initialize: () => startAuthSubscription(set, get),
  retryInitialize: () => {
    set({ isInitialized: false, timedOutWithoutAuth: false });
    startAuthSubscription(set, get);
  },
}));
