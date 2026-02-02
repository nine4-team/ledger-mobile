import { Redirect } from 'expo-router';
import { useAuthStore } from '../src/auth/authStore';
import { useAccountContextStore } from '../src/auth/accountContextStore';
import { isAuthBypassEnabled } from '../src/auth/authConfig';
import { LoadingScreen } from '../src/components/LoadingScreen';

export default function Index() {
  const { user, isInitialized } = useAuthStore();
  const { accountId, isHydrated } = useAccountContextStore();

  if (!isInitialized || !isHydrated) {
    return <LoadingScreen />;
  }

  if (!user && !isAuthBypassEnabled) {
    return <Redirect href="/(auth)/sign-in" />;
  }

  if (user && !isAuthBypassEnabled && !accountId) {
    return <Redirect href="/account-select" />;
  }

  return <Redirect href="/(tabs)" />;
}

