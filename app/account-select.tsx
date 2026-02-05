import { useEffect, useMemo, useState } from 'react';
import { Alert, Pressable, StyleSheet, View } from 'react-native';
import { useRouter } from 'expo-router';
import { Screen } from '../src/components/Screen';
import { AppText } from '../src/components/AppText';
import { AppButton } from '../src/components/AppButton';
import { useAuthStore } from '../src/auth/authStore';
import { useAccountContextStore } from '../src/auth/accountContextStore';
import { useTheme, useUIKitTheme } from '../src/theme/ThemeProvider';
import { getCardStyle } from '../src/ui';
import { functions, isFirebaseConfigured } from '../src/firebase/firebase';

function getCallableErrorMessage(error: unknown): string {
  const e = error as any;
  const code = typeof e?.code === 'string' ? e.code : '';
  const message = typeof e?.message === 'string' ? e.message : '';

  // Common Firebase callable error codes:
  // https://firebase.google.com/docs/reference/functions/errors
  if (code.includes('not-found')) {
    return 'Backend is not deployed yet. Start emulators or deploy Cloud Functions, then try again.';
  }
  if (code.includes('unimplemented')) {
    return 'Backend is not implemented or deployed yet. Start emulators or deploy Cloud Functions, then try again.';
  }
  if (code.includes('unavailable')) {
    return 'Backend is not reachable. If you are using emulators, make sure they are running.';
  }
  if (code.includes('failed-precondition')) {
    return 'Firestore is not enabled for this Firebase project yet. Create the Firestore database in the Firebase console.';
  }
  if (code.includes('permission-denied')) {
    return 'Permission denied by Firestore rules. Double-check rules + that you are signed in.';
  }
  if (message.toLowerCase().includes('not implemented')) {
    return 'Backend is not implemented or deployed yet. Start emulators or deploy Cloud Functions, then try again.';
  }
  if (message) {
    return message;
  }
  return 'Please try again.';
}

export default function AccountSelectScreen() {
  const router = useRouter();
  const { user, signOut } = useAuthStore();
  const { setAccountId, listAccountsForCurrentUser, noAccess } = useAccountContextStore();
  const [loading, setLoading] = useState(true);
  const [creating, setCreating] = useState(false);
  const [selectingAccountId, setSelectingAccountId] = useState<string | null>(null);
  const [accounts, setAccounts] = useState<Array<{ accountId: string; name?: string }>>([]);
  const theme = useTheme();
  const uiKitTheme = useUIKitTheme();

  const styles = useMemo(
    () =>
      StyleSheet.create({
        container: {
          flex: 1,
          justifyContent: 'center',
        },
        card: {
          ...getCardStyle(uiKitTheme, { radius: 12, padding: theme.spacing.lg }),
          gap: theme.spacing.md,
        },
        actions: {
          gap: theme.spacing.sm,
        },
        list: {
          gap: theme.spacing.sm,
        },
        row: {
          borderWidth: 1,
          borderColor: uiKitTheme.border.primary,
          borderRadius: 12,
          paddingVertical: theme.spacing.md,
          paddingHorizontal: theme.spacing.md,
          backgroundColor: uiKitTheme.background.surface,
        },
        rowPressed: {
          opacity: 0.8,
        },
        rowTitle: {
          fontWeight: '600',
        },
        rowSub: {
          marginTop: theme.spacing.xs,
          color: theme.colors.textSecondary,
        },
        secondaryText: {
          color: theme.colors.textSecondary,
        },
        errorBanner: {
          borderWidth: 1,
          borderColor: theme.colors.error,
          borderRadius: 12,
          padding: theme.spacing.md,
        },
        errorText: {
          color: theme.colors.error,
        },
      }),
    [theme, uiKitTheme]
  );

  useEffect(() => {
    let cancelled = false;

    (async () => {
      if (!user) {
        setLoading(false);
        return;
      }

      setLoading(true);
      try {
        const list = await listAccountsForCurrentUser();
        if (cancelled) return;

        console.log('[account-select] loaded accounts', { count: list.length });
        if (list.length === 1) {
          // 1 account: auto-select and skip account-select UI entirely.
          await setAccountId(list[0].accountId);
          router.replace('/(tabs)');
          return;
        }

        setAccounts(list);
      } catch {
        if (cancelled) return;
        setAccounts([]);
      } finally {
        if (!cancelled) setLoading(false);
      }
    })();

    return () => {
      cancelled = true;
    };
  }, [listAccountsForCurrentUser, router, setAccountId, user]);

  const onPickAccount = async (accountId: string) => {
    if (!user) {
      Alert.alert('Not signed in', 'Sign in first, then select an account.');
      router.replace('/(auth)/sign-in');
      return;
    }

    setSelectingAccountId(accountId);
    try {
      await setAccountId(accountId);
      router.replace('/(tabs)');
    } finally {
      setSelectingAccountId(null);
    }
  };

  const onCreateAccount = async () => {
    if (!user) {
      Alert.alert('Not signed in', 'Sign in first, then create an account.');
      router.replace('/(auth)/sign-in');
      return;
    }

    if (!isFirebaseConfigured || !functions) {
      Alert.alert(
        'Unavailable',
        'Firebase is not configured on this build. Add native Firebase config and rebuild the dev client.'
      );
      return;
    }

    setCreating(true);
    try {
      const createAccount = functions.httpsCallable('createAccount');
      const result = await createAccount({ name: 'My account' });
      const accountId = (result?.data as any)?.accountId as string | undefined;

      if (!accountId) {
        throw new Error('Missing accountId from createAccount response.');
      }

      console.log('[account-select] created account (server-owned)', { accountId });
      await setAccountId(accountId);
      router.replace('/(tabs)');
    } catch (error) {
      const e = error as any;
      console.warn('[account-select] create account failed', {
        code: e?.code,
        message: e?.message,
      });
      Alert.alert('Could not create account', getCallableErrorMessage(error));
    } finally {
      setCreating(false);
    }
  };

  const onReload = async () => {
    setLoading(true);
    try {
      const list = await listAccountsForCurrentUser();
      console.log('[account-select] reloaded accounts', { count: list.length });
      if (list.length === 1) {
        await setAccountId(list[0].accountId);
        router.replace('/(tabs)');
        return;
      }
      setAccounts(list);
    } catch {
      setAccounts([]);
    } finally {
      setLoading(false);
    }
  };

  const title = loading ? 'Loading accounts' : accounts.length === 0 ? 'Create your first account' : 'Choose an account';
  const subtitle = loading
    ? 'Checking which accounts you have access to…'
    : accounts.length === 0
      ? 'Accounts are used to keep your data organized. Create one to get started.'
      : 'Select an account to continue.';

  return (
    <Screen>
      <View style={styles.container}>
        <View style={styles.card}>
          <AppText variant="title">{title}</AppText>
          <AppText variant="body" style={styles.secondaryText}>
            {subtitle}
          </AppText>

          {noAccess && (
            <View style={styles.errorBanner}>
              <AppText variant="body" style={styles.errorText}>
                You no longer have access to the previous account. Choose another account or create a new one.
              </AppText>
            </View>
          )}

          {loading ? (
            <AppText variant="body" style={styles.secondaryText}>
              Loading accounts…
            </AppText>
          ) : accounts.length === 0 ? (
            <View style={styles.actions}>
              <AppButton title="Create account" onPress={onCreateAccount} loading={creating} />
              <AppButton title="Reload" variant="secondary" onPress={onReload} />
            </View>
          ) : (
            <View style={styles.list}>
              {accounts.map((a) => {
                const isSelecting = selectingAccountId === a.accountId;
                return (
                  <Pressable
                    key={a.accountId}
                    onPress={() => onPickAccount(a.accountId)}
                    disabled={Boolean(selectingAccountId) || creating}
                    style={({ pressed }) => [
                      styles.row,
                      (pressed || isSelecting) ? styles.rowPressed : null,
                    ]}
                  >
                    <AppText variant="body" style={styles.rowTitle}>
                      {a.name?.trim() ? a.name.trim() : 'Account'}
                    </AppText>
                    <AppText variant="caption" style={styles.rowSub}>
                      {a.accountId}
                      {isSelecting ? ' • Selecting…' : ''}
                    </AppText>
                  </Pressable>
                );
              })}
            </View>
          )}

          <View style={styles.actions}>
            <AppButton
              title="Sign out"
              variant="secondary"
              onPress={async () => {
                await signOut();
                router.replace('/(auth)/sign-in');
              }}
            />
          </View>
        </View>
      </View>
    </Screen>
  );
}

