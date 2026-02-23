import 'react-native-gesture-handler';
import { useEffect, useRef, useState } from 'react';
import { Stack, useRouter, useSegments } from 'expo-router';
import { View, StyleSheet, AppState } from 'react-native';
import { GestureHandlerRootView } from 'react-native-gesture-handler';
import { useAuthStore } from '../src/auth/authStore';
import { useAccountContextStore } from '../src/auth/accountContextStore';
import { useBillingStore } from '../src/billing/billingStore';
import { LoadingScreen } from '../src/components/LoadingScreen';
import { isAuthBypassEnabled } from '../src/auth/authConfig';
import { ThemeProvider } from '@/theme/ThemeProvider';
import { startRequestDocTracking } from '../src/sync/requestDocTracker';
import { hydrateMediaStore, registerUploadHandler, processUploadQueue, cleanupStaleMedia } from '../src/offline/media/mediaStore';
import { uploadMediaToFirebaseStorage } from '../src/offline/media/uploadHandler';
import { useListStateStore } from '../src/data/listStateStore';
import { useProjectContextStore } from '../src/data/projectContextStore';
import { Toast } from '../src/components/Toast';

export default function RootLayout() {
  const { user, isInitialized, timedOutWithoutAuth, initialize } = useAuthStore();
  const {
    accountId,
    isHydrated: isAccountHydrated,
    hydrate: hydrateAccountContext,
    revalidateMembership,
    clearAccountId,
    setAccountId,
    listAccountsForCurrentUser,
  } = useAccountContextStore();
  const { isInitialized: billingInitialized, initialize: initializeBilling } = useBillingStore();
  const hydrateListStateStore = useListStateStore((state) => state.hydrate);
  const hydrateProjectContext = useProjectContextStore((state) => state.hydrate);
  const router = useRouter();
  const segments = useSegments();
  const [isResolvingAccountSelection, setIsResolvingAccountSelection] = useState(false);
  const isResolvingAccountSelectionRef = useRef(false);

  useEffect(() => {
    const unsubscribe = initialize();
    hydrateAccountContext();
    initializeBilling();
    startRequestDocTracking();
    hydrateMediaStore().then(() => {
      processUploadQueue().catch(console.error);
      cleanupStaleMedia().catch(console.error);
    });
    registerUploadHandler(uploadMediaToFirebaseStorage);
    hydrateListStateStore();
    hydrateProjectContext();
    return unsubscribe;
  }, []);

  useEffect(() => {
    // Auto-retry pending uploads when app returns to foreground
    const subscription = AppState.addEventListener('change', (nextAppState) => {
      if (nextAppState === 'active') {
        processUploadQueue().catch(console.error);
      }
    });

    return () => {
      subscription.remove();
    };
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
    let cancelled = false;

    if (!isInitialized || !billingInitialized || !isAccountHydrated) {
      return;
    }
    if (!user || isAuthBypassEnabled) {
      return;
    }
    if (accountId) {
      setIsResolvingAccountSelection(false);
      return;
    }

    // If the user only belongs to exactly 1 account, auto-select it here so we can
    // skip the /account-select UI entirely (no flicker).
    (async () => {
      isResolvingAccountSelectionRef.current = true;
      setIsResolvingAccountSelection(true);
      try {
        const accounts = await listAccountsForCurrentUser();
        if (cancelled) return;

        if (accounts.length === 1) {
          console.log('[root] auto-selected single account');
          await setAccountId(accounts[0].accountId);
          router.replace('/(tabs)');
        }
      } finally {
        isResolvingAccountSelectionRef.current = false;
        if (!cancelled) setIsResolvingAccountSelection(false);
      }
    })();

    return () => {
      cancelled = true;
    };
  }, [
    accountId,
    billingInitialized,
    isAccountHydrated,
    isInitialized,
    listAccountsForCurrentUser,
    router,
    setAccountId,
    user,
  ]);

  useEffect(() => {
    if (!isInitialized || !billingInitialized || !isAccountHydrated) {
      return;
    }

    const inAuthGroup = segments[0] === '(auth)';
    const isInviteRoute = segments[0] === '(auth)' && segments[1] === 'invite';
    const isPaywall = segments[0] === 'paywall';
    const isAccountSelect = segments[0] === 'account-select';
    const isAllowed = Boolean(user) || isAuthBypassEnabled;
    const needsAccountSelection = Boolean(user) && !isAuthBypassEnabled && !accountId;

    // Allow invite route for both authenticated and unauthenticated users
    if (isInviteRoute) {
      return;
    }

    if (needsAccountSelection && !isAccountSelect) {
      if (isResolvingAccountSelectionRef.current) {
        // Give auto-selection a chance to resolve before routing to /account-select.
        return;
      }
      router.replace('/account-select');
      return;
    }

    if (user && inAuthGroup) {
      // User is signed in but in auth routes (except invite), redirect to tabs
      router.replace(accountId ? '/(tabs)' : '/account-select');
    } else if (!isAllowed && !inAuthGroup && !isPaywall) {
      // User is not signed in and not in auth routes or paywall, redirect to auth
      router.replace('/(auth)/sign-in');
    }
  }, [
    accountId,
    billingInitialized,
    isAccountHydrated,
    isInitialized,
    isResolvingAccountSelection,
    segments,
    user,
  ]);

  return (
    <GestureHandlerRootView style={styles.root}>
      <ThemeProvider>
        <View style={styles.root}>
          <Stack screenOptions={{ headerShown: false }}>
            <Stack.Screen name="(auth)" />
            <Stack.Screen name="(tabs)" />
            <Stack.Screen name="paywall" />
          </Stack>

          {(!isInitialized || !billingInitialized || !isAccountHydrated || isResolvingAccountSelection) &&
            !timedOutWithoutAuth && (
            <View style={styles.loadingOverlay} pointerEvents="auto">
              <LoadingScreen />
            </View>
          )}
          <Toast />
        </View>
      </ThemeProvider>
    </GestureHandlerRootView>
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
