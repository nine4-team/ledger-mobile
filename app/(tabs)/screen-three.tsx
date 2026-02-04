import { StyleSheet, View, Alert, RefreshControl, ScrollView } from 'react-native';
import { Screen } from '../../src/components/Screen';
import { AppText } from '../../src/components/AppText';
import { useScreenTabs } from '../../src/components/ScreenTabs';
import { useScreenRefresh } from '../../src/components/Screen';
import { TemplateToggleListCard } from '../../src/components/TemplateToggleListCard';
import { layout } from '../../src/ui';
import React, { useCallback, useMemo, useState } from 'react';

export default function ScreenThree() {
  const [isRefreshing, setIsRefreshing] = useState(false);
  const handleRefresh = useCallback(async () => {
    setIsRefreshing(true);
    setIsRefreshing(false);
  }, []);

  return (
    <Screen
      title="Templates"
      refreshing={isRefreshing}
      onRefresh={handleRefresh}
      tabs={[
        { key: 'spaces', label: 'Spaces', accessibilityLabel: 'Spaces tab' },
        { key: 'vendors', label: 'Vendors', accessibilityLabel: 'Vendors tab' },
        {
          key: 'budget-categories',
          label: 'Budget Categories',
          accessibilityLabel: 'Budget Categories tab',
        },
      ]}
      initialTabKey="spaces"
    >
      <TemplatesScreenContent />
    </Screen>
  );
}

function TemplatesScreenContent() {
  const screenTabs = useScreenTabs();
  const screenRefresh = useScreenRefresh();
  const selectedKey = screenTabs?.selectedKey ?? 'spaces';
  const refreshControl = screenRefresh ? (
    <RefreshControl refreshing={screenRefresh.refreshing} onRefresh={screenRefresh.onRefresh} />
  ) : undefined;

  const [vendorTemplates, setVendorTemplates] = useState(() => [
    { id: 'vendor-1', name: 'Wayfair', itemize: true },
    { id: 'vendor-2', name: 'Home Depot', itemize: false },
    { id: 'vendor-3', name: 'Sherwin-Williams', itemize: false },
  ]);

  const [budgetCategoryTemplates, setBudgetCategoryTemplates] = useState(() => [
    { id: 'cat-1', name: 'Additional Requests', itemize: true },
    { id: 'cat-2', name: 'Design Fee', itemize: false },
    { id: 'cat-3', name: 'Fuel', itemize: false },
    { id: 'cat-4', name: 'Furnishings', itemize: true },
    { id: 'cat-5', name: 'Install', itemize: false },
    { id: 'cat-6', name: 'Kitchen', itemize: true },
  ]);

  const commonCardProps = useMemo(
    () => ({
      rightHeaderLabel: 'ITEMIZE',
      onPressMenu: (id: string) => Alert.alert('Menu', `Menu pressed for ${id}`),
      onPressCreate: () => Alert.alert('Create', 'Create pressed'),
    }),
    []
  );

  if (selectedKey === 'spaces') {
    return (
      <ScrollView
        style={styles.scroll}
        contentContainerStyle={styles.placeholder}
        refreshControl={refreshControl}
      >
        <AppText variant="body">Spaces templates go here.</AppText>
      </ScrollView>
    );
  }

  if (selectedKey === 'vendors') {
    return (
      <ScrollView
        style={styles.scroll}
        contentContainerStyle={styles.placeholder}
        refreshControl={refreshControl}
      >
        <TemplateToggleListCard
          title="Vendors"
          items={vendorTemplates}
          onToggleItemize={(id, next) =>
            setVendorTemplates((prev) => prev.map((v) => (v.id === id ? { ...v, itemize: next } : v)))
          }
          getInfoContent={(item) => ({
            title: `Vendor template: ${item.name}`,
            message:
              'This toggle controls whether imports from this vendor should be auto-itemized into line items. Turn it off if you want a single total amount per transaction.',
          })}
          createPlaceholderLabel="Click to create new vendor"
          {...commonCardProps}
        />
      </ScrollView>
    );
  }

  return (
    <ScrollView
      style={styles.scroll}
      contentContainerStyle={styles.placeholder}
      refreshControl={refreshControl}
    >
      <TemplateToggleListCard
        title="Active Categories"
        items={budgetCategoryTemplates}
        onToggleItemize={(id, next) =>
          setBudgetCategoryTemplates((prev) => prev.map((c) => (c.id === id ? { ...c, itemize: next } : c)))
        }
        getInfoContent={(item) => ({
          title: `Category: ${item.name}`,
          message:
            'When itemize is enabled, transactions mapped to this category can be split into multiple categorized line items. Use this for categories that often include multiple sub-purchases.',
        })}
        createPlaceholderLabel="Click to create new category"
        {...commonCardProps}
      />
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  scroll: {
    flex: 1,
  },
  placeholder: {
    paddingTop: layout.screenBodyTopMd.paddingTop,
  },
});
