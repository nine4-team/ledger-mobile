import { useEffect, useState } from 'react';
import { View, StyleSheet, KeyboardAvoidingView, Platform } from 'react-native';
import { useRouter, useLocalSearchParams } from 'expo-router';
import { Screen } from '../../../src/components/Screen';
import { AppText } from '../../../src/components/AppText';
import { AppButton } from '../../../src/components/AppButton';
import { useAuthStore } from '../../../src/auth/authStore';
import { useInviteTokenStore } from '../../../src/auth/inviteTokenStore';
import { useAccountContextStore } from '../../../src/auth/accountContextStore';
import { useNetworkStatus } from '../../../src/hooks/useNetworkStatus';
import { functions, isFirebaseConfigured } from '../../../src/firebase/firebase';
import { useTheme, useUIKitTheme } from '../../../src/theme/ThemeProvider';
import { getCardStyle } from '../../../src/ui';
import { LoadingScreen } from '../../../src/components/LoadingScreen';

const ACCEPT_INVITE_TIMEOUT_MS = 7000;

const withTimeout = async <T,>(promise: Promise<T>, timeoutMs: number): Promise<T> =>
  await new Promise<T>((resolve, reject) => {
    const timeoutId = setTimeout(() => reject(new Error('timeout')), timeoutMs);
    promise
      .then((result) => {
        clearTimeout(timeoutId);
        resolve(result);
      })
      .catch((error) => {
        clearTimeout(timeoutId);
        reject(error);
      });
  });

export default function InviteAcceptScreen() {
  const { token: rawToken } = useLocalSearchParams<{ token?: string | string[] }>();
  const router = useRouter();
  const { user, isInitialized } = useAuthStore();
  const { isOnline } = useNetworkStatus();
  const { setPendingToken, clearPendingToken, hydrate: hydrateToken } = useInviteTokenStore();
  const { setAccountId } = useAccountContextStore();
  const theme = useTheme();
  const uiKitTheme = useUIKitTheme();
  const token = Array.isArray(rawToken) ? rawToken[0] : rawToken;

  const [status, setStatus] = useState<'idle' | 'accepting' | 'success' | 'error'>('idle');
  const [errorMessage, setErrorMessage] = useState<string>('');

  const styles = StyleSheet.create({
    container: {
      flex: 1,
      justifyContent: 'center',
    },
    card: {
      width: '100%',
      maxWidth: 400,
      alignSelf: 'center',
      ...getCardStyle(uiKitTheme, { radius: 12, padding: theme.spacing.lg }),
    },
    title: {
      marginBottom: theme.spacing.md,
      textAlign: 'center',
    },
    message: {
      marginBottom: theme.spacing.lg,
      textAlign: 'center',
      color: theme.colors.textSecondary,
    },
    errorBanner: {
      borderWidth: 1,
      borderColor: theme.colors.error,
      borderRadius: 12,
      padding: theme.spacing.md,
      marginBottom: theme.spacing.md,
    },
    errorText: {
      color: theme.colors.error,
    },
    button: {
      marginTop: theme.spacing.sm,
    },
  });

  // Hydrate token store on mount
  useEffect(() => {
    hydrateToken();
  }, [hydrateToken]);

  // Persist token if present
  useEffect(() => {
    if (token && token.trim()) {
      setPendingToken(token);
    }
  }, [token, setPendingToken]);

  // Attempt acceptance when authenticated
  useEffect(() => {
    if (!isInitialized || !user || !token || status !== 'idle') {
      return;
    }

    // Only attempt if online
    if (!isOnline) {
      return;
    }

    // Call handleAcceptInvite when conditions are met
    handleAcceptInvite();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [isInitialized, user, token, isOnline, status]);

  const handleAcceptInvite = async () => {
    if (!token || !token.trim()) {
      setStatus('error');
      setErrorMessage('Invalid invitation link');
      return;
    }

    if (!isFirebaseConfigured || !functions) {
      setStatus('error');
      setErrorMessage('Firebase is not configured');
      return;
    }

    if (!user) {
      // Should not happen due to useEffect guard, but handle gracefully
      return;
    }

    setStatus('accepting');
    setErrorMessage('');

    try {
      const acceptInvite = functions.httpsCallable('acceptInvite');
      const result = await withTimeout(acceptInvite({ token }), ACCEPT_INVITE_TIMEOUT_MS);

      const data = result.data as { accountId: string; role: string } | undefined;

      if (data?.accountId) {
        // Set account context and clear pending token
        await setAccountId(data.accountId);
        await clearPendingToken();
        setStatus('success');

        // Navigate to tabs after a brief delay
        setTimeout(() => {
          router.replace('/(tabs)');
        }, 1000);
      } else {
        throw new Error('Invalid response from server');
      }
    } catch (error: any) {
      setStatus('error');
      const code = error?.code || '';
      const message = error?.message || 'Failed to accept invitation';

      // Map Firebase error codes to user-friendly messages
      if (message === 'timeout') {
        setErrorMessage('Accepting the invite is taking too long. Please try again.');
      } else if (code === 'invalid-argument' || code === 'not-found') {
        setErrorMessage('Invalid or expired invitation link');
      } else if (code === 'already-exists' || message.includes('already accepted')) {
        setErrorMessage('This invitation has already been accepted');
      } else if (code === 'resource-exhausted') {
        setErrorMessage('Account limit reached. Please upgrade your plan.');
      } else if (code === 'permission-denied' || code === 'unauthenticated') {
        setErrorMessage('You must be signed in to accept an invitation');
      } else {
        setErrorMessage(message);
      }
    }
  };

  // Show loading while auth initializes
  if (!isInitialized) {
    return (
      <Screen>
        <LoadingScreen />
      </Screen>
    );
  }

  // Invalid token
  if (!token || !token.trim()) {
    return (
      <Screen>
        <KeyboardAvoidingView
          behavior={Platform.OS === 'ios' ? 'padding' : 'height'}
          style={styles.container}
        >
          <View style={styles.card}>
            <AppText variant="h1" style={styles.title}>
              Invalid Invitation
            </AppText>
            <AppText variant="body" style={styles.message}>
              This invitation link is invalid or missing.
            </AppText>
            <AppButton
              title="Go to Sign In"
              onPress={() => router.replace('/(auth)/sign-in')}
              style={styles.button}
            />
          </View>
        </KeyboardAvoidingView>
      </Screen>
    );
  }

  // Not authenticated - show sign in/up options
  if (!user) {
    return (
      <Screen>
        <KeyboardAvoidingView
          behavior={Platform.OS === 'ios' ? 'padding' : 'height'}
          style={styles.container}
        >
          <View style={styles.card}>
            <AppText variant="h1" style={styles.title}>
              Accept Invitation
            </AppText>
            <AppText variant="body" style={styles.message}>
              Please sign in or create an account to accept this invitation.
            </AppText>
            <AppButton
              title="Sign In"
              onPress={() => router.push('/(auth)/sign-in')}
              style={styles.button}
            />
            <AppButton
              title="Sign Up"
              variant="secondary"
              onPress={() => router.push('/(auth)/sign-up')}
              style={styles.button}
            />
          </View>
        </KeyboardAvoidingView>
      </Screen>
    );
  }

  // Authenticated - show acceptance UI
  return (
    <Screen>
      <KeyboardAvoidingView
        behavior={Platform.OS === 'ios' ? 'padding' : 'height'}
        style={styles.container}
      >
        <View style={styles.card}>
          <AppText variant="h1" style={styles.title}>
            Accept Invitation
          </AppText>

          {status === 'accepting' && (
            <View style={styles.message}>
              <LoadingScreen />
              <AppText variant="body" style={styles.message}>
                Accepting invitation...
              </AppText>
            </View>
          )}

          {status === 'success' && (
            <AppText variant="body" style={styles.message}>
              Invitation accepted! Redirecting...
            </AppText>
          )}

          {status === 'error' && (
            <>
              <View style={styles.errorBanner}>
                <AppText variant="body" style={styles.errorText}>
                  {errorMessage}
                </AppText>
              </View>

              {!isOnline && (
                <View style={styles.errorBanner}>
                  <AppText variant="body" style={styles.errorText}>
                    Requires connection. Please check your internet connection and try again.
                  </AppText>
                </View>
              )}

              <AppButton
                title={isOnline ? 'Retry' : 'Retry When Online'}
                onPress={handleAcceptInvite}
                disabled={!isOnline}
                style={styles.button}
              />
            </>
          )}

          {status === 'idle' && !isOnline && (
            <>
              <View style={styles.errorBanner}>
                <AppText variant="body" style={styles.errorText}>
                  Requires connection. Please check your internet connection and try again.
                </AppText>
              </View>
              <AppButton
                title="Retry When Online"
                disabled={true}
                style={styles.button}
              />
            </>
          )}
        </View>
      </KeyboardAvoidingView>
    </Screen>
  );
}
