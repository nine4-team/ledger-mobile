import MaterialIcons from '@expo/vector-icons/MaterialIcons';
import React, { useMemo, useState } from 'react';
import { Alert, Image, StyleSheet, View } from 'react-native';

import { AppScrollView } from '../../src/components/AppScrollView';
import { AppText } from '../../src/components/AppText';
import { ExpandableCard } from '../../src/components/ExpandableCard';
import { GroupedItemCard } from '../../src/components/GroupedItemCard';
import { ItemCard } from '../../src/components/ItemCard';
import { Screen } from '../../src/components/Screen';
import { ScreenTabItem, useScreenTabs } from '../../src/components/ScreenTabs';
import { TemplateToggleListCard, TemplateToggleListItem } from '../../src/components/TemplateToggleListCard';
import { ComponentsGallery } from '../../src/screens/ComponentsGallery';
import { useTheme, useUIKitTheme } from '@/theme/ThemeProvider';
import { getTextSecondaryStyle, textEmphasis } from '../../src/ui';

const COMPONENT_TABS: ScreenTabItem[] = [
  { key: 'library', label: 'Tab 2', accessibilityLabel: 'Tab 2' },
  { key: 'settings', label: 'Tab 1', accessibilityLabel: 'Tab 1' },
];

export default function ComponentsScreen() {
  return (
    <Screen
      title="Components"
      tabs={COMPONENT_TABS}
      initialTabKey={COMPONENT_TABS[0]?.key ?? 'library'}
      hideBackButton={true}
      includeBottomInset={false}
      infoContent={{
        title: 'Components',
        message: 'A grab-bag of reusable UI components and interaction patterns.',
      }}
    >
      <ComponentsTabContent />
    </Screen>
  );
}

function ComponentsTabContent() {
  const screenTabs = useScreenTabs();
  const selectedKey = screenTabs?.selectedKey ?? 'library';

  if (selectedKey === 'settings') {
    return <ComponentsGallery />;
  }

  return <ComponentsLibraryTab />;
}

function ComponentsLibraryTab() {
  const theme = useTheme();
  const uiKitTheme = useUIKitTheme();
  const [itemSelected, setItemSelected] = useState(false);
  const [groupSelected, setGroupSelected] = useState(false);
  const [groupItemSelections, setGroupItemSelections] = useState({
    bed: false,
    nightstand: false,
    dresser: false,
  });
  const logoUri = useMemo(() => Image.resolveAssetSource(require('../../ledger_logo.png')).uri, []);
  const [templateItems, setTemplateItems] = useState<TemplateToggleListItem[]>([
    { id: '1', name: 'Default template', disabled: false },
    { id: '2', name: 'Rental / staging', disabled: false },
    { id: '3', name: 'Insurance', disabled: true },
    { id: '4', name: 'Legacy (off)', disabled: true },
  ]);

  const itemMenu = useMemo(
    () => [
      { key: 'edit', label: 'Edit', onPress: () => Alert.alert('Item menu', 'Edit') },
      { key: 'move', label: 'Move', onPress: () => Alert.alert('Item menu', 'Move') },
      { key: 'delete', label: 'Delete', onPress: () => Alert.alert('Item menu', 'Delete') },
    ],
    []
  );

  const expandableMenu = useMemo(
    () => [
      { key: 'rename', label: 'Rename', onPress: () => Alert.alert('Card menu', 'Rename') },
      { key: 'archive', label: 'Archive', onPress: () => Alert.alert('Card menu', 'Archive') },
    ],
    []
  );

  const updateGroupItemSelection = (key: keyof typeof groupItemSelections) => (next: boolean) => {
    setGroupItemSelections((prev) => ({ ...prev, [key]: next }));
  };

  return (
    <AppScrollView style={styles.scroll} contentContainerStyle={styles.content}>
      <View style={styles.section}>
        <AppText
          variant="caption"
          style={[styles.sectionTitle, textEmphasis.sectionLabel, getTextSecondaryStyle(uiKitTheme)]}
        >
          Cards
        </AppText>

        <ItemCard
          description="Dining chair (set of 4)"
          sku="CHAIR-001"
          sourceLabel="Purchased"
          locationLabel="Warehouse"
          notes="Light scuffs on one leg."
          priceLabel="$480.00"
          statusLabel="In use"
          thumbnailUri={logoUri}
          selected={itemSelected}
          onSelectedChange={setItemSelected}
          bookmarked
          onBookmarkPress={() => Alert.alert('Bookmark', 'Toggled')}
          menuItems={itemMenu}
          onPress={() => Alert.alert('Item', 'Pressed')}
        />

        <GroupedItemCard
          summary={{
            description: 'Bedroom set',
            sku: 'SET-12',
            sourceLabel: 'Purchased',
            locationLabel: 'Unit B',
            notes: 'Grouped example',
            thumbnailUri: logoUri,
          }}
          countLabel="×3"
          totalLabel="$2,400.00"
          items={[
            {
              description: 'Bed frame',
              sku: 'BED-001',
              priceLabel: '$900.00',
              sourceLabel: 'Purchased',
              thumbnailUri: logoUri,
              selected: groupItemSelections.bed,
              onSelectedChange: updateGroupItemSelection('bed'),
              bookmarked: true,
              onBookmarkPress: () => Alert.alert('Bookmark', 'Toggled'),
              menuItems: itemMenu,
            },
            {
              description: 'Nightstand',
              sku: 'NS-002',
              priceLabel: '$300.00',
              sourceLabel: 'Purchased',
              thumbnailUri: logoUri,
              selected: groupItemSelections.nightstand,
              onSelectedChange: updateGroupItemSelection('nightstand'),
              bookmarked: false,
              onBookmarkPress: () => Alert.alert('Bookmark', 'Toggled'),
              menuItems: itemMenu,
            },
            {
              description: 'Dresser',
              sku: 'DR-003',
              priceLabel: '$1,200.00',
              sourceLabel: 'Purchased',
              thumbnailUri: logoUri,
              selected: groupItemSelections.dresser,
              onSelectedChange: updateGroupItemSelection('dresser'),
              bookmarked: true,
              onBookmarkPress: () => Alert.alert('Bookmark', 'Toggled'),
              menuItems: itemMenu,
            },
          ]}
          selected={groupSelected}
          onSelectedChange={setGroupSelected}
          defaultExpanded={false}
        />

        <ExpandableCard
          title="Project budget summary"
          expandableRow1={{ label: 'Pinned categories', value: '3' }}
          expandableRow2={{ label: 'Last update', value: '2 hours ago' }}
          alwaysShowRow1={{ label: 'Budget', value: '$12,000' }}
          alwaysShowRow2={{ label: 'Spent', value: '$4,580' }}
          menuItems={expandableMenu}
          menuBadgeLabel="New"
          menuBadgeEnabled={true}
        />
      </View>

      <View style={styles.section}>
        <AppText
          variant="caption"
          style={[styles.sectionTitle, textEmphasis.sectionLabel, getTextSecondaryStyle(uiKitTheme)]}
        >
          Draggable toggles
        </AppText>

        <TemplateToggleListCard
          title="Templates"
          rightHeaderLabel="Itemize"
          items={templateItems}
          onToggleDisabled={(id, next) => {
            setTemplateItems((prev) => prev.map((it) => (it.id === id ? { ...it, disabled: next } : it)));
          }}
          onReorderItems={(next) => setTemplateItems(next)}
          onDragActiveChange={(isDragging) => {
            if (isDragging) {
              // Quiet by default; helpful if you want to wire haptics later.
            }
          }}
        />

        <View style={styles.hintRow}>
          <MaterialIcons name="drag-handle" size={18} color={theme.colors.textSecondary} />
          <AppText variant="caption" style={getTextSecondaryStyle(uiKitTheme)}>
            Drag enabled items to reorder.
          </AppText>
        </View>
      </View>
    </AppScrollView>
  );
}

const styles = StyleSheet.create({
  scroll: {
    flex: 1,
  },
  content: {
    paddingTop: 12,
    paddingBottom: 24,
    gap: 18,
  },
  section: {
    gap: 12,
  },
  sectionTitle: {
    marginBottom: 4,
  },
  hintRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 6,
  },
});

