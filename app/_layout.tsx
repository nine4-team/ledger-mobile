import { useEffect } from 'react';
import { Stack, useRouter, useSegments } from 'expo-router';
import { View, StyleSheet } from 'react-native';
import { useAuthStore } from '../src/auth/authStore';
import { useAccountContextStore } from '../src/auth/accountContextStore';
import { useBillingStore } from '../src/billing/billingStore';
import { LoadingScreen } from '../src/components/LoadingScreen';
import { isAuthBypassEnabled } from '../src/auth/authConfig';
import { ThemeProvider } from '../src/theme/ThemeProvider';

export default function RootLayout() {
  const { user, isInitialized, initialize } = useAuthStore();
  const {
    accountId,
    isHydrated: isAccountHydrated,
    hydrate: hydrateAccountContext,
    revalidateMembership,
    clearAccountId,
  } = useAccountContextStore();
  const { isInitialized: billingInitialized, initialize: initializeBilling } = useBillingStore();
  const router = useRouter();
  const segments = useSegments();

  useEffect(() => {
    const unsubscribe = initialize();
    hydrateAccountContext();
    initializeBilling();
    return unsubscribe;
  }, []);

  useEffect(() => {
    // Prevent cross-user leakage: if auth user is cleared, clear account selection too.
    if (!isInitialized) return;
    if (!user) {
      clearAccountId();
    }
  }, [clearAccountId, isInitialized, user]);

  useEffect(() => {
    if (!isInitialized || !billingInitialized || !isAccountHydrated) {
      return;
    }
    if (!user || isAuthBypassEnabled) {
      return;
    }
    if (!accountId) {
      return;
    }
    // Best-effort: validate membership when we can reach server/cache.
    revalidateMembership();
  }, [accountId, billingInitialized, isAccountHydrated, isInitialized, revalidateMembership, user]);

  useEffect(() => {
    if (!isInitialized || !billingInitialized || !isAccountHydrated) {
      return;
    }

    const inAuthGroup = segments[0] === '(auth)';
    const isPaywall = segments[0] === 'paywall';
    const isAccountSelect = segments[0] === 'account-select';
    const isAllowed = Boolean(user) || isAuthBypassEnabled;
    const needsAccountSelection = Boolean(user) && !isAuthBypassEnabled && !accountId;

    if (needsAccountSelection && !isAccountSelect) {
      router.replace('/account-select');
      return;
    }

    if (user && inAuthGroup) {
      // User is signed in but in auth routes, redirect to tabs
      router.replace(accountId ? '/(tabs)' : '/account-select');
    } else if (!isAllowed && !inAuthGroup && !isPaywall) {
      // User is not signed in and not in auth routes or paywall, redirect to auth
      router.replace('/(auth)/sign-in');
    }
  }, [accountId, billingInitialized, isAccountHydrated, isInitialized, segments, user]);

  return (
    <ThemeProvider>
      <View style={styles.root}>
        <Stack screenOptions={{ headerShown: false }}>
          <Stack.Screen name="(auth)" />
          <Stack.Screen name="(tabs)" />
          <Stack.Screen name="paywall" />
        </Stack>

        {(!isInitialized || !billingInitialized || !isAccountHydrated) && (
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
