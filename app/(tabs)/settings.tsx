import React, { useMemo, useState } from 'react';
import { View, StyleSheet, Alert, ScrollView } from 'react-native';
import { useRouter } from 'expo-router';
import MaterialIcons from '@expo/vector-icons/MaterialIcons';
import { Screen } from '../../src/components/Screen';
import { AppText } from '../../src/components/AppText';
import { AppButton } from '../../src/components/AppButton';
import { ExpandableCard } from '../../src/components/ExpandableCard';
import { ItemCard } from '../../src/components/ItemPreviewCard';
import { GroupedItemCard } from '../../src/components';
import { TemplateToggleListCard } from '../../src/components/TemplateToggleListCard';
import type { TemplateToggleListItem } from '../../src/components/TemplateToggleListCard';
import { SegmentedControl } from '../../src/components/SegmentedControl';
import { ScreenTabItem, ScreenTabs, useScreenTabs } from '../../src/components/ScreenTabs';
import { useAuthStore } from '../../src/auth/authStore';
import { useBillingStore } from '../../src/billing/billingStore';
import { usePro } from '../../src/billing/billingStore';
import { isAuthBypassEnabled } from '../../src/auth/authConfig';
import { useAppearance, useTheme, useUIKitTheme } from '../../src/theme/ThemeProvider';
import { CARD_LIST_GAP, getCardStyle, getTextAccentStyle, getTextSecondaryStyle, layout, surface, textEmphasis } from '../../src/ui';

const PRIMARY_TABS: ScreenTabItem[] = [
  { key: 'tab-one', label: 'Settings', accessibilityLabel: 'Settings tab' },
  { key: 'tab-two', label: 'More', accessibilityLabel: 'More tab' },
  { key: 'tab-three', label: 'Components', accessibilityLabel: 'Components tab' },
];

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
  const [componentsScrollEnabled, setComponentsScrollEnabled] = useState(true);
  const [activeCategories, setActiveCategories] = useState<TemplateToggleListItem[]>([
    { id: 'cat-1', name: 'Additional Requests', itemize: true },
    { id: 'cat-2', name: 'Design Fee', itemize: false },
    { id: 'cat-3', name: 'Fuel', itemize: false },
    { id: 'cat-4', name: 'Furnishings', itemize: true },
    { id: 'cat-5', name: 'Install', itemize: false },
    { id: 'cat-6', name: 'Kitchen', itemize: true },
  ]);

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

  if (primaryTabKey === 'tab-three') {
    return (
      <ScrollView
        style={styles.scroll}
        contentContainerStyle={styles.componentsScrollContent}
        showsVerticalScrollIndicator={false}
        scrollEnabled={componentsScrollEnabled}
      >
        <TemplateToggleListCard
          title="Active Categories"
          rightHeaderLabel="ITEMIZE"
          items={activeCategories}
          onToggleItemize={(id, next) => {
            setActiveCategories((prev) => prev.map((it) => (it.id === id ? { ...it, itemize: next } : it)));
          }}
          onReorderItems={setActiveCategories}
          onDragActiveChange={(isDragging) => setComponentsScrollEnabled(!isDragging)}
          getInfoContent={(item) => ({
            title: `Category: ${item.name}`,
            message:
              'When itemize is enabled, transactions mapped to this category can be split into multiple categorized line items. Use this for categories that often include multiple sub-purchases.',
          })}
          onPressMenu={(id) => Alert.alert('Menu', `Menu pressed for ${id}`)}
          onPressCreate={() => Alert.alert('Create', 'Create pressed')}
          createPlaceholderLabel="Click to create new category"
        />

        <ExpandableCard
          title="Expandable Card"
          expandableRow1={{ label: 'Expandable Field 1', value: 'Expandable Field 3' }}
          expandableRow2={{ label: 'Expandable Field 2', value: 'Expandable Field 4' }}
          alwaysShowRow1={{ label: 'Always Show 1', value: 'Always Show Value 1' }}
          alwaysShowRow2={{ label: 'Always Show 2', value: 'Always Show Value 2' }}
          menuBadgeEnabled
          menuBadgeLabel="Badge"
          menuItems={[
            {
              key: 'action-with-subactions',
              label: 'Action 1',
              defaultSelectedSubactionKey: 'subaction-1',
              subactions: [
                { key: 'subaction-1', label: 'Subaction 1', onPress: () => console.log('Subaction 1 pressed') },
                { key: 'subaction-2', label: 'Subaction 2', onPress: () => console.log('Subaction 2 pressed') },
              ],
            },
            { key: 'edit', label: 'Edit', onPress: () => console.log('Edit pressed') },
            { key: 'delete', label: 'Delete', onPress: () => console.log('Delete pressed') },
          ]}
        />

        <ItemCard
          description="CB2 — Pebble Side Table (white oak), sculpted profile with a softly rounded edge and a compact footprint for tight living spaces"
          sku="CB2-PS-001"
          sourceLabel="Wayfair"
          priceLabel="$249.00"
          statusLabel="In project"
          locationLabel="Living room North wall"
          defaultSelected={false}
          onSelectedChange={(next) => console.log('Selected changed', next)}
          bookmarked={true}
          onBookmarkPress={() => console.log('Bookmark pressed')}
          onAddImagePress={() => console.log('Add image pressed')}
          onMenuPress={() => console.log('Menu pressed')}
          onPress={() => console.log('Item card pressed')}
        />

        <GroupedItemCard
          summary={{
            description: 'Wayfair — Pillow Insert (Down alternative)',
            sku: 'WF-PI-STD-001',
            sourceLabel: 'Wayfair',
            locationLabel: 'Guest room Closet',
            thumbnailUri:
              'https://images.unsplash.com/photo-1582719478250-c89cae4dc85b?auto=format&fit=crop&w=240&q=80',
          }}
          countLabel="×2"
          totalLabel="$59.98"
          defaultSelected={false}
          onSelectedChange={(next: boolean) => console.log('Group selected', next)}
          items={[
            {
              description: 'Wayfair — Pillow Insert (Down alternative)',
              sku: 'WF-PI-STD-001',
              sourceLabel: 'Wayfair',
              priceLabel: '$29.99',
              statusLabel: 'In project',
              locationLabel: 'Guest room Closet',
              thumbnailUri:
                'https://images.unsplash.com/photo-1582719478250-c89cae4dc85b?auto=format&fit=crop&w=240&q=80',
              defaultSelected: true,
              onSelectedChange: (next: boolean) => console.log('Child item 1 selected', next),
              bookmarked: false,
              onBookmarkPress: () => console.log('Child item 1 bookmark pressed'),
              onAddImagePress: () => console.log('Child item 1 add image pressed'),
              onMenuPress: () => console.log('Child item 1 menu pressed'),
              onPress: () => console.log('Child item 1 pressed'),
            },
            {
              description: 'Wayfair — Pillow Insert (Down alternative)',
              sku: 'WF-PI-STD-001',
              sourceLabel: 'Wayfair',
              priceLabel: '$29.99',
              statusLabel: 'In project',
              locationLabel: 'Guest room Closet',
              thumbnailUri:
                'https://images.unsplash.com/photo-1582719478250-c89cae4dc85b?auto=format&fit=crop&w=240&q=80',
              defaultSelected: false,
              onSelectedChange: (next: boolean) => console.log('Child item 2 selected', next),
              bookmarked: true,
              onBookmarkPress: () => console.log('Child item 2 bookmark pressed'),
              onAddImagePress: () => console.log('Child item 2 add image pressed'),
              onMenuPress: () => console.log('Child item 2 menu pressed'),
              onPress: () => console.log('Child item 2 pressed'),
            },
          ]}
          defaultExpanded={false}
        />
      </ScrollView>
    );
  }

  if (primaryTabKey === 'tab-two') {
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
      tabs={PRIMARY_TABS}
      renderBelowTabs={({ selectedKey }) =>
        selectedKey === 'tab-two' ? (
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
  componentsScrollContent: {
    paddingTop: layout.screenBodyTopMd.paddingTop,
    gap: CARD_LIST_GAP,
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
