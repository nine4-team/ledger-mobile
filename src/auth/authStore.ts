import { create } from 'zustand';
import { User, onAuthStateChanged, signInWithEmailAndPassword, createUserWithEmailAndPassword, signOut as firebaseSignOut } from 'firebase/auth';
import { auth, isFirebaseConfigured } from '../firebase/firebase';

interface AuthState {
  user: User | null;
  isInitialized: boolean;
  setUser: (user: User | null) => void;
  setInitialized: (isInitialized: boolean) => void;
  signIn: (email: string, password: string) => Promise<void>;
  signUp: (email: string, password: string) => Promise<void>;
  signOut: () => Promise<void>;
  initialize: () => () => void; // Returns cleanup function
}

export const useAuthStore = create<AuthState>((set) => ({
  user: null,
  isInitialized: false,
  setUser: (user) => set({ user }),
  setInitialized: (isInitialized) => set({ isInitialized }),
  signIn: async (email: string, password: string) => {
    if (!isFirebaseConfigured || !auth) {
      throw new Error(
        'Firebase is not configured. Add native config files and/or EXPO_PUBLIC_FIREBASE_* values to .env.'
      );
    }
    await signInWithEmailAndPassword(auth, email, password);
  },
  signUp: async (email: string, password: string) => {
    if (!isFirebaseConfigured || !auth) {
      throw new Error(
        'Firebase is not configured. Add native config files and/or EXPO_PUBLIC_FIREBASE_* values to .env.'
      );
    }
    await createUserWithEmailAndPassword(auth, email, password);
  },
  signOut: async () => {
    if (!isFirebaseConfigured || !auth) {
      set({ user: null });
      return;
    }
    await firebaseSignOut(auth);
    set({ user: null });
  },
  initialize: () => {
    if (!isFirebaseConfigured || !auth) {
      set({ user: null, isInitialized: true });
      return () => {};
    }
    const unsubscribe = onAuthStateChanged(auth, (user) => {
      set({ user, isInitialized: true });
    });
    return unsubscribe;
  },
}));
