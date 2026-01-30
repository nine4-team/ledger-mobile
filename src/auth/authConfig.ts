import { isFirebaseConfigured } from '../firebase/firebase';

/**
 * Dev-only convenience:
 * - If Firebase isn't configured, allow navigating the UI without signing in.
 * - You can also force this on with EXPO_PUBLIC_BYPASS_AUTH=true (useful for demos).
 */
export const isAuthBypassEnabled: boolean =
  process.env.EXPO_PUBLIC_BYPASS_AUTH === 'true' || (__DEV__ && !isFirebaseConfigured);

