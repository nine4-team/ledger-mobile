import { Redirect } from 'expo-router';
import { useAuthStore } from '../src/auth/authStore';
import { isAuthBypassEnabled } from '../src/auth/authConfig';
import { LoadingScreen } from '../src/components/LoadingScreen';

export default function Index() {
  const { user, isInitialized } = useAuthStore();

  if (!isInitialized) {
    return <LoadingScreen />;
  }

  return <Redirect href={user || isAuthBypassEnabled ? '/(tabs)' : '/(auth)/sign-in'} />;
}

