import { create } from 'zustand';
import { FirebaseAuthTypes } from '@react-native-firebase/auth';
import { auth, isFirebaseConfigured } from '../firebase/firebase';

interface AuthState {
  user: FirebaseAuthTypes.User | null;
  isInitialized: boolean;
  setUser: (user: FirebaseAuthTypes.User | null) => void;
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
  signOut: async () => {
    if (!isFirebaseConfigured || !auth) {
      set({ user: null });
      return;
    }
    await auth.signOut();
    set({ user: null });
  },
  initialize: () => {
    if (!isFirebaseConfigured || !auth) {
      set({ user: null, isInitialized: true });
      return () => {};
    }
    const unsubscribe = auth.onAuthStateChanged((user) => {
      set({ user, isInitialized: true });
    });
    return unsubscribe;
  },
}));
