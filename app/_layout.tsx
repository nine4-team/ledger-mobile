import { useEffect } from 'react';
import { Stack, useRouter, useSegments } from 'expo-router';
import { View, StyleSheet } from 'react-native';
import { useAuthStore } from '../src/auth/authStore';
import { useBillingStore } from '../src/billing/billingStore';
import { LoadingScreen } from '../src/components/LoadingScreen';
import { isAuthBypassEnabled } from '../src/auth/authConfig';
import { ThemeProvider } from '../src/theme/ThemeProvider';

export default function RootLayout() {
  const { user, isInitialized, initialize } = useAuthStore();
  const { isInitialized: billingInitialized, initialize: initializeBilling } = useBillingStore();
  const router = useRouter();
  const segments = useSegments();

  useEffect(() => {
    const unsubscribe = initialize();
    initializeBilling();
    return unsubscribe;
  }, []);

  useEffect(() => {
    if (!isInitialized || !billingInitialized) {
      return;
    }

    const inAuthGroup = segments[0] === '(auth)';
    const isPaywall = segments[0] === 'paywall';
    const isAllowed = Boolean(user) || isAuthBypassEnabled;

    if (user && inAuthGroup) {
      // User is signed in but in auth routes, redirect to tabs
      router.replace('/(tabs)');
    } else if (!isAllowed && !inAuthGroup && !isPaywall) {
      // User is not signed in and not in auth routes or paywall, redirect to auth
      router.replace('/(auth)/sign-in');
    }
  }, [user, isInitialized, billingInitialized, segments]);

  return (
    <ThemeProvider>
      <View style={styles.root}>
        <Stack screenOptions={{ headerShown: false }}>
          <Stack.Screen name="(auth)" />
          <Stack.Screen name="(tabs)" />
          <Stack.Screen name="paywall" />
        </Stack>

        {(!isInitialized || !billingInitialized) && (
          <View style={styles.loadingOverlay} pointerEvents="auto">
            <LoadingScreen />
          </View>
        )}
      </View>
    </ThemeProvider>
  );
}

const styles = StyleSheet.create({
  root: {
    flex: 1,
  },
  loadingOverlay: {
    ...StyleSheet.absoluteFillObject,
  },
});
