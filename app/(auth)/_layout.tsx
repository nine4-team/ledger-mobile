import { Redirect, Stack, useLocalSearchParams } from 'expo-router';
import { isAuthBypassEnabled } from '../../src/auth/authConfig';

export default function AuthLayout() {
  const params = useLocalSearchParams<{ preview?: string }>();
  const preview = params?.preview === '1' || params?.preview === 'true';

  // In guest/bypass mode we default to the app UI, unless explicitly previewing auth.
  if (isAuthBypassEnabled && !preview) {
    return <Redirect href="/(tabs)" />;
  }

  return (
    <Stack screenOptions={{ headerShown: false }}>
      <Stack.Screen name="sign-in" />
      <Stack.Screen name="sign-up" />
    </Stack>
  );
}
