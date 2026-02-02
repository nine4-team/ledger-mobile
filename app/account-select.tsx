import { useEffect, useMemo, useState } from 'react';
import { Alert, StyleSheet, TextInput, View } from 'react-native';
import { useRouter } from 'expo-router';
import { Screen } from '../src/components/Screen';
import { AppText } from '../src/components/AppText';
import { AppButton } from '../src/components/AppButton';
import { useAuthStore } from '../src/auth/authStore';
import { useAccountContextStore } from '../src/auth/accountContextStore';
import { useTheme, useUIKitTheme } from '../src/theme/ThemeProvider';
import { getCardStyle, getTextInputStyle } from '../src/ui';

export default function AccountSelectScreen() {
  const router = useRouter();
  const { user, signOut } = useAuthStore();
  const { accountId, setAccountId, revalidateMembership } = useAccountContextStore();
  const [value, setValue] = useState(accountId ?? '');
  const [saving, setSaving] = useState(false);
  const theme = useTheme();
  const uiKitTheme = useUIKitTheme();

  useEffect(() => {
    setValue(accountId ?? '');
  }, [accountId]);

  const styles = useMemo(
    () =>
      StyleSheet.create({
        card: {
          ...getCardStyle(uiKitTheme, { radius: 12, padding: theme.spacing.lg }),
          gap: theme.spacing.md,
        },
        input: {
          ...getTextInputStyle(uiKitTheme, {
            radius: 8,
            paddingVertical: 10,
            paddingHorizontal: 12,
            fontSize: 16,
          }),
        },
        actions: {
          gap: theme.spacing.sm,
        },
      }),
    [theme, uiKitTheme]
  );

  const trimmed = value.trim();

  const onContinue = async () => {
    if (!user) {
      Alert.alert('Not signed in', 'Sign in first, then select an account.');
      router.replace('/(auth)/sign-in');
      return;
    }
    if (!trimmed) {
      Alert.alert('Account required', 'Enter an account id to continue.');
      return;
    }

    setSaving(true);
    try {
      await setAccountId(trimmed);
      // Best-effort membership validation (won't clear on network failures).
      await revalidateMembership();
      router.replace('/(tabs)');
    } finally {
      setSaving(false);
    }
  };

  return (
    <Screen>
      <View style={styles.card}>
        <AppText variant="title">Select account</AppText>
        <AppText variant="body" style={{ color: theme.colors.textSecondary }}>
          This device remembers your last-selected account. When online, we revalidate membership; if it’s no longer
          valid, you’ll be asked to pick again.
        </AppText>

        <TextInput
          style={styles.input}
          placeholder="Account ID"
          placeholderTextColor={uiKitTheme.input.placeholder}
          value={value}
          onChangeText={setValue}
          autoCapitalize="none"
          autoCorrect={false}
          returnKeyType="done"
          onSubmitEditing={onContinue}
        />

        <View style={styles.actions}>
          <AppButton title="Continue" onPress={onContinue} loading={saving} />
          <AppButton title="Revalidate now" variant="secondary" onPress={revalidateMembership} />
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
    </Screen>
  );
}

