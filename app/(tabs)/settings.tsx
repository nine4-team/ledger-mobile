import React, { useMemo, useState } from 'react';
import { View, StyleSheet, Alert, ScrollView } from 'react-native';
import { useRouter } from 'expo-router';
import MaterialIcons from '@expo/vector-icons/MaterialIcons';
import { Screen } from '../../src/components/Screen';
import { AppText } from '../../src/components/AppText';
import { AppButton } from '../../src/components/AppButton';
import { SegmentedControl } from '../../src/components/SegmentedControl';
import { ScreenTabItem, ScreenTabs, useScreenTabs } from '../../src/components/ScreenTabs';
import { useAuthStore } from '../../src/auth/authStore';
import { useBillingStore } from '../../src/billing/billingStore';
import { usePro } from '../../src/billing/billingStore';
import { isAuthBypassEnabled } from '../../src/auth/authConfig';
import { useAppearance, useTheme, useUIKitTheme } from '../../src/theme/ThemeProvider';
import { getCardStyle, getTextAccentStyle, getTextSecondaryStyle, layout, surface, textEmphasis } from '../../src/ui';

const SECONDARY_TABS: ScreenTabItem[] = [
  { key: 'subtab-one', label: 'Subtab One', accessibilityLabel: 'Subtab One' },
  { key: 'subtab-two', label: 'Subtab Two', accessibilityLabel: 'Subtab Two' },
  { key: 'subtab-three', label: 'Subtab Three', accessibilityLabel: 'Subtab Three' },
];

type SettingsContentProps = {
  selectedSubTabKey: string;
};

function SettingsContent({ selectedSubTabKey }: SettingsContentProps) {
  const router = useRouter();
  const { user, signOut } = useAuthStore();
  const { restorePurchases } = useBillingStore();
  const isPro = usePro();
  const theme = useTheme();
  const uiKitTheme = useUIKitTheme();
  const { appearanceMode, setAppearanceMode } = useAppearance();
  const screenTabs = useScreenTabs();
  const primaryTabKey = screenTabs?.selectedKey ?? 'tab-one';

  const subtabLabel = useMemo(() => {
    return SECONDARY_TABS.find((t) => t.key === selectedSubTabKey)?.label ?? 'Subtab One';
  }, [selectedSubTabKey]);

  const handleSignOut = async () => {
    if (isAuthBypassEnabled) {
      router.replace('/(auth)/sign-in?preview=1');
      return;
    }
    Alert.alert('Sign Out', 'Are you sure you want to sign out?', [
      { text: 'Cancel', style: 'cancel' },
      {
        text: 'Sign Out',
        style: 'destructive',
        onPress: async () => {
          try {
            await signOut();
            router.replace('/(auth)/sign-in');
          } catch (error: any) {
            Alert.alert('Error', error.message || 'Failed to sign out');
          }
        },
      },
    ]);
  };

  const handleRestorePurchases = async () => {
    try {
      await restorePurchases();
      Alert.alert('Success', 'Purchases restored');
    } catch (error: any) {
      Alert.alert('Error', error.message || 'Failed to restore purchases');
    }
  };

  if (primaryTabKey === 'tab-two') {
    return (
      <ScrollView style={styles.scroll} contentContainerStyle={styles.scrollContent} showsVerticalScrollIndicator={false}>
        <AppText variant="body">Settings Tab Two content goes here.</AppText>
      </ScrollView>
    );
  }

  if (primaryTabKey === 'tab-three') {
    return (
      <ScrollView style={styles.scroll} contentContainerStyle={styles.scrollContent} showsVerticalScrollIndicator={false}>
        <AppText variant="body">{subtabLabel} content goes here.</AppText>
      </ScrollView>
    );
  }

  return (
    <ScrollView style={styles.scroll} contentContainerStyle={styles.scrollContent} showsVerticalScrollIndicator={false}>
      <View style={styles.section}>
        <AppText
          variant="caption"
          style={[styles.sectionTitle, textEmphasis.sectionLabel, getTextSecondaryStyle(uiKitTheme)]}
        >
          Account
        </AppText>
        <View style={[surface.overflowHidden, getCardStyle(uiKitTheme, { radius: 12, padding: theme.spacing.lg })]}>
          <View style={[layout.rowBetween, styles.rowGap]}>
            <AppText variant="body" style={getTextSecondaryStyle(uiKitTheme)}>
              Email
            </AppText>
            <AppText variant="body" style={[styles.value, textEmphasis.value]}>
              {user?.email}
            </AppText>
          </View>
        </View>
      </View>

      <View style={styles.section}>
        <AppText
          variant="caption"
          style={[styles.sectionTitle, textEmphasis.sectionLabel, getTextSecondaryStyle(uiKitTheme)]}
        >
          Subscription
        </AppText>
        <View style={[surface.overflowHidden, getCardStyle(uiKitTheme, { radius: 12, padding: theme.spacing.lg })]}>
          <View style={[layout.rowBetween, styles.rowGap]}>
            <AppText variant="body" style={getTextSecondaryStyle(uiKitTheme)}>
              Plan
            </AppText>
            <AppText
              variant="body"
              style={[styles.value, textEmphasis.value, isPro && getTextAccentStyle(uiKitTheme)]}
            >
              {isPro ? 'Pro' : 'Free'}
            </AppText>
          </View>
        </View>
      </View>

      <View style={styles.section}>
        <AppText
          variant="caption"
          style={[styles.sectionTitle, textEmphasis.sectionLabel, getTextSecondaryStyle(uiKitTheme)]}
        >
          Appearance
        </AppText>
        <View style={[surface.overflowHidden, getCardStyle(uiKitTheme, { radius: 12, padding: theme.spacing.lg })]}>
          <SegmentedControl
            accessibilityLabel="Appearance"
            value={appearanceMode}
            onChange={setAppearanceMode}
            options={[
              {
                value: 'system',
                label: 'Auto',
                icon: (
                  <MaterialIcons
                    name="brightness-auto"
                    size={18}
                    color={appearanceMode === 'system' ? theme.colors.primary : theme.colors.textSecondary}
                  />
                ),
              },
              {
                value: 'light',
                label: 'Light',
                icon: (
                  <MaterialIcons
                    name="light-mode"
                    size={18}
                    color={appearanceMode === 'light' ? theme.colors.primary : theme.colors.textSecondary}
                  />
                ),
              },
              {
                value: 'dark',
                label: 'Dark',
                icon: (
                  <MaterialIcons
                    name="dark-mode"
                    size={18}
                    color={appearanceMode === 'dark' ? theme.colors.primary : theme.colors.textSecondary}
                  />
                ),
              },
            ]}
          />
        </View>
      </View>

      {!isPro && <AppButton title="Upgrade to Pro" onPress={() => router.push('/paywall')} style={styles.button} />}

      <AppButton title="Restore Purchases" variant="secondary" onPress={handleRestorePurchases} style={styles.button} />

      <AppButton
        title={isAuthBypassEnabled ? 'Sign In' : 'Sign Out'}
        variant="secondary"
        onPress={handleSignOut}
        style={[styles.button, styles.signOutButton]}
      />
    </ScrollView>
  );
}

export default function SettingsScreen() {
  const [selectedSubTabKey, setSelectedSubTabKey] = useState<string>(SECONDARY_TABS[0]?.key ?? 'subtab-one');

  return (
    <Screen
      title="Settings"
      renderBelowTabs={({ selectedKey }) =>
        selectedKey === 'tab-three' ? (
          <ScreenTabs tabs={SECONDARY_TABS} value={selectedSubTabKey} onChange={setSelectedSubTabKey} />
        ) : null
      }
    >
      <SettingsContent selectedSubTabKey={selectedSubTabKey} />
    </Screen>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
  },
  scroll: {
    flex: 1,
  },
  scrollContent: {
    paddingTop: layout.screenBodyTopMd.paddingTop,
  },
  section: {
    marginBottom: 18,
  },
  sectionTitle: {
    marginBottom: 8,
  },
  rowGap: {
    gap: 12,
  },
  value: {
  },
  button: {
    marginTop: 12,
  },
  signOutButton: {
    marginTop: 20,
  },
});
