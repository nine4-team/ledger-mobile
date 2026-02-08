import React, { useCallback, useMemo, useState } from 'react';
import { FlatList, Pressable, StyleSheet, Text, TouchableOpacity, View } from 'react-native';
import MaterialIcons from '@expo/vector-icons/MaterialIcons';
import { AppText } from './AppText';
import { ItemCard } from './ItemCard';
import { GroupedItemCard } from './GroupedItemCard';
import { ItemPickerControlBar } from './ItemPickerControlBar';
import { useTheme, useUIKitTheme } from '../theme/ThemeProvider';
import { getTextSecondaryStyle } from '../ui/styles/typography';
import type { ScopedItem } from '../data/scopedListData';
import type { Item } from '../data/itemsService';
import { resolveAttachmentUri } from '../offline/media';

export type ItemPickerTab = string;

export type ItemPickerTabOption = {
  value: ItemPickerTab;
  label: string;
  accessibilityLabel?: string;
};

export type ItemEligibilityCheck = {
  /**
   * Whether the item is eligible for selection (not locked).
   */
  isEligible: (item: ScopedItem | Item) => boolean;
  /**
   * Status label to show for ineligible items (e.g., "Already linked", "Linked elsewhere").
   */
  getStatusLabel?: (item: ScopedItem | Item) => string | undefined;
  /**
   * Whether the item is already in the target (e.g., already linked to this transaction).
   */
  isAlreadyInTarget?: (item: ScopedItem | Item) => boolean;
};

export type SharedItemPickerProps = {
  /**
   * Available tabs for the picker.
   */
  tabs: ItemPickerTabOption[];
  /**
   * Currently selected tab.
   */
  selectedTab: ItemPickerTab;
  /**
   * Callback when tab changes.
   */
  onTabChange: (tab: ItemPickerTab) => void;
  /**
   * Items to display for the current tab.
   */
  items: Array<ScopedItem | Item>;
  /**
   * Currently selected item IDs.
   */
  selectedIds: string[];
  /**
   * Callback when selection changes.
   */
  onSelectionChange: (ids: string[]) => void;
  /**
   * Eligibility check function to determine which items can be selected.
   */
  eligibilityCheck: ItemEligibilityCheck;
  /**
   * Callback when "Add Selected" is pressed.
   */
  onAddSelected: () => void | Promise<void>;
  /**
   * Loading state for outside items (shown when tab is "outside").
   */
  outsideLoading?: boolean;
  /**
   * Error state for outside items.
   */
  outsideError?: string | null;
  /**
   * Placeholder text for search input.
   */
  searchPlaceholder?: string;
  /**
   * Label for the "Add Selected" button (default: "Add").
   */
  addButtonLabel?: string;
  /**
   * Callback for individual item quick-add. When provided, each eligible item
   * gets an "Add" button for single-item adds (in addition to bulk selection).
   */
  onAddSingle?: (item: ScopedItem | Item) => void | Promise<void>;
  /**
   * Set of item IDs that have already been added (shows "Added" badge, disables add button).
   */
  addedIds?: Set<string>;
  /**
   * Item counts per tab, keyed by tab value. Shown as a badge next to the tab label.
   */
  tabCounts?: Record<string, number>;
};

function getItemLabel(item: ScopedItem | Item) {
  return item.name?.trim() || 'Item';
}

function getPrimaryImage(item: ScopedItem | Item) {
  const images = item.images ?? [];
  const primary = images.find((image) => image.isPrimary) ?? images[0];
  if (!primary) return undefined;
  return resolveAttachmentUri(primary) ?? primary.url;
}

/**
 * Shared component for picking items to add to transactions or spaces.
 * Handles tabs, search, selection, grouping, and add actions.
 */
export function SharedItemPicker({
  tabs,
  selectedTab,
  onTabChange,
  items,
  selectedIds,
  onSelectionChange,
  eligibilityCheck,
  onAddSelected,
  outsideLoading = false,
  outsideError = null,
  searchPlaceholder = 'Search items',
  addButtonLabel = 'Add',
  onAddSingle,
  addedIds,
  tabCounts,
}: SharedItemPickerProps) {
  const theme = useTheme();
  const uiKitTheme = useUIKitTheme();
  const [searchQuery, setSearchQuery] = useState('');

  // Filter items by search query
  const filteredItems = useMemo(() => {
    const needle = searchQuery.trim().toLowerCase();
    if (!needle) return items;
    return items.filter((item) => {
      const label = item.name?.toLowerCase() ?? '';
      return label.includes(needle);
    });
  }, [items, searchQuery]);

  // Group items by name/description (for duplicate grouping)
  // Flatten for FlatList rendering
  type PickerGroupItem = {
    key: string;
    label: string;
    groupItems: Array<ScopedItem | Item>;
  };

  const pickerGroups = useMemo(() => {
    const groups = new Map<string, Array<ScopedItem | Item>>();
    filteredItems.forEach((item) => {
      const label = item.name?.trim() || 'Item';
      const key = label.toLowerCase();
      const list = groups.get(key) ?? [];
      list.push(item);
      groups.set(key, list);
    });

    return Array.from(groups.entries()).map(([label, groupItems], index) => ({
      key: `group-${index}-${label}`,
      label,
      groupItems,
    }));
  }, [filteredItems]);

  // Get eligible item IDs for "select all visible"
  const eligibleIds = useMemo(() => {
    return filteredItems.filter((item) => eligibilityCheck.isEligible(item)).map((item) => item.id);
  }, [filteredItems, eligibilityCheck]);

  const allVisibleSelected = useMemo(() => {
    return eligibleIds.length > 0 && eligibleIds.every((id) => selectedIds.includes(id));
  }, [eligibleIds, selectedIds]);

  const handleSelectAll = () => {
    if (allVisibleSelected) {
      // Deselect all eligible items
      const eligibleSet = new Set(eligibleIds);
      onSelectionChange(selectedIds.filter((id) => !eligibleSet.has(id)));
    } else {
      // Select all eligible items
      onSelectionChange(Array.from(new Set([...selectedIds, ...eligibleIds])));
    }
  };

  const handleItemToggle = (itemId: string) => {
    onSelectionChange(
      selectedIds.includes(itemId) ? selectedIds.filter((id) => id !== itemId) : [...selectedIds, itemId]
    );
  };

  const handleGroupToggle = (groupItemIds: string[], next: boolean) => {
    if (next) {
      onSelectionChange(Array.from(new Set([...selectedIds, ...groupItemIds])));
    } else {
      const remove = new Set(groupItemIds);
      onSelectionChange(selectedIds.filter((id) => !remove.has(id)));
    }
  };

  const renderAddButton = useCallback(
    (item: ScopedItem | Item, locked: boolean) => {
      if (!onAddSingle) return undefined;
      const alreadyAdded = addedIds?.has(item.id) ?? false;
      return (
        <Pressable
          onPress={(e) => {
            e.stopPropagation();
            if (!locked && !alreadyAdded) void onAddSingle(item);
          }}
          disabled={locked || alreadyAdded}
          hitSlop={6}
          accessibilityRole="button"
          accessibilityLabel={alreadyAdded ? 'Already added' : `Add ${item.name ?? 'item'}`}
          style={[
            styles.addButton,
            {
              backgroundColor: alreadyAdded
                ? uiKitTheme.background.tertiary
                : uiKitTheme.button.primary.background,
              opacity: locked ? 0.4 : 1,
            },
          ]}
        >
          <MaterialIcons
            name={alreadyAdded ? 'check' : 'add'}
            size={14}
            color={alreadyAdded ? uiKitTheme.text.secondary : uiKitTheme.button.primary.text}
          />
          <Text
            style={[
              styles.addButtonText,
              {
                color: alreadyAdded ? uiKitTheme.text.secondary : uiKitTheme.button.primary.text,
              },
            ]}
          >
            {alreadyAdded ? 'Added' : 'Add'}
          </Text>
        </Pressable>
      );
    },
    [addedIds, onAddSingle, uiKitTheme]
  );

  return (
    <View style={styles.container}>
      <View
        style={[styles.tabBar, { borderBottomColor: uiKitTheme.border.secondary }]}
        accessibilityRole="tablist"
        accessibilityLabel="Item picker tabs"
      >
        {tabs.map((tab) => {
          const isSelected = tab.value === selectedTab;
          const count = tabCounts?.[tab.value];
          return (
            <TouchableOpacity
              key={tab.value}
              style={[
                styles.tab,
                isSelected && { borderBottomColor: theme.tabBar.activeTint },
              ]}
              onPress={() => {
                onTabChange(tab.value);
                onSelectionChange([]);
              }}
              activeOpacity={0.7}
              accessibilityRole="tab"
              accessibilityState={{ selected: isSelected }}
              accessibilityLabel={tab.accessibilityLabel ?? tab.label}
            >
              <Text
                style={[
                  styles.tabText,
                  theme.typography.body,
                  isSelected
                    ? { color: theme.tabBar.activeTint, fontWeight: '700' }
                    : { color: theme.colors.textSecondary },
                ]}
              >
                {tab.label}
              </Text>
              {count != null ? (
                <View
                  style={[
                    styles.tabCount,
                    {
                      backgroundColor: isSelected
                        ? theme.tabBar.activeTint + '1A'
                        : uiKitTheme.background.tertiary,
                    },
                  ]}
                >
                  <Text
                    style={[
                      styles.tabCountText,
                      {
                        color: isSelected
                          ? theme.tabBar.activeTint
                          : theme.colors.textSecondary,
                      },
                    ]}
                  >
                    {count}
                  </Text>
                </View>
              ) : null}
            </TouchableOpacity>
          );
        })}
      </View>
      <ItemPickerControlBar
        search={searchQuery}
        onChangeSearch={setSearchQuery}
        searchPlaceholder={searchPlaceholder}
        onSelectAll={handleSelectAll}
        allSelected={allVisibleSelected}
        hasItems={eligibleIds.length > 0}
        onAddSelected={onAddSelected}
        selectedCount={selectedIds.length}
        addButtonLabel={addButtonLabel}
      />
      <FlatList
        data={pickerGroups}
        extraData={selectedIds}
        keyExtractor={(item) => item.key}
        renderItem={({ item: group }) => {
          const { label, groupItems } = group;
          const groupEligibleIds = groupItems.filter((item) => eligibilityCheck.isEligible(item)).map((item) => item.id);
          const groupAllSelected = groupEligibleIds.length > 0 && groupEligibleIds.every((id) => selectedIds.includes(id));
          const summaryItem = groupItems.find((item) => Boolean(getPrimaryImage(item))) ?? groupItems[0];
          const summaryThumbnailUri = summaryItem ? getPrimaryImage(summaryItem) : undefined;

          if (groupItems.length > 1) {
            return (
              <GroupedItemCard
                summary={{
                  name: label,
                  sku: summaryItem?.sku ?? undefined,
                  sourceLabel: summaryItem?.source ?? undefined,
                  locationLabel: summaryItem?.spaceId ?? undefined,
                  notes: summaryItem?.notes ?? undefined,
                  thumbnailUri: summaryThumbnailUri,
                }}
                countLabel={`×${groupItems.length}`}
                items={groupItems.map((item) => {
                  const name = getItemLabel(item);
                  const locked = !eligibilityCheck.isEligible(item);
                  const statusLabel = eligibilityCheck.getStatusLabel?.(item);
                  const selected = selectedIds.includes(item.id);
                  const thumbnailUri = getPrimaryImage(item);

                  return {
                    name,
                    sku: item.sku ?? undefined,
                    sourceLabel: item.source ?? undefined,
                    locationLabel: item.spaceId ?? undefined,
                    notes: item.notes ?? undefined,
                    thumbnailUri,
                    selected,
                    onSelectedChange: locked
                      ? undefined
                      : (next) => {
                          handleItemToggle(item.id);
                        },
                    onPress: locked
                      ? undefined
                      : () => {
                          handleItemToggle(item.id);
                        },
                    statusLabel,
                    style: locked ? styles.lockedItem : undefined,
                  };
                })}
                selected={groupAllSelected}
                onSelectedChange={
                  groupEligibleIds.length === 0
                    ? undefined
                    : (next) => {
                        handleGroupToggle(groupEligibleIds, next);
                      }
                }
              />
            );
          }

          const [only] = groupItems;
          const name = getItemLabel(only);
          const locked = !eligibilityCheck.isEligible(only);
          const selected = selectedIds.includes(only.id);
          const statusLabel = eligibilityCheck.getStatusLabel?.(only);

          return (
            <ItemCard
              name={name}
              sku={only.sku ?? undefined}
              sourceLabel={only.source ?? undefined}
              locationLabel={only.spaceId ?? undefined}
              notes={only.notes ?? undefined}
              thumbnailUri={getPrimaryImage(only)}
              selected={selected}
              onSelectedChange={locked ? undefined : (next) => handleItemToggle(only.id)}
              onPress={locked ? undefined : () => handleItemToggle(only.id)}
              statusLabel={statusLabel}
              headerAction={renderAddButton(only, locked)}
              style={locked ? styles.lockedItem : undefined}
            />
          );
        }}
        contentContainerStyle={styles.list}
        style={styles.listScroll}
        ListEmptyComponent={
          <AppText variant="body" style={getTextSecondaryStyle(uiKitTheme)}>
            No items available.
          </AppText>
        }
        ListFooterComponent={
          <>
            {selectedTab === 'outside' && outsideLoading ? (
              <AppText variant="caption" style={getTextSecondaryStyle(uiKitTheme)}>
                Loading outside items…
              </AppText>
            ) : null}
            {selectedTab === 'outside' && outsideError ? (
              <AppText variant="caption" style={getTextSecondaryStyle(uiKitTheme)}>
                {outsideError}
              </AppText>
            ) : null}
          </>
        }
        initialNumToRender={10}
        maxToRenderPerBatch={10}
        windowSize={5}
        removeClippedSubviews={true}
      />
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    gap: 12,
  },
  tabBar: {
    flexDirection: 'row',
    borderBottomWidth: 1,
  },
  tab: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 6,
    paddingHorizontal: 10,
    paddingTop: 8,
    paddingBottom: 10,
    marginBottom: -1,
    borderBottomColor: 'transparent',
    borderBottomWidth: 3,
  },
  tabText: {
  },
  tabCount: {
    paddingHorizontal: 6,
    paddingVertical: 1,
    borderRadius: 999,
    minWidth: 22,
    alignItems: 'center',
  },
  tabCountText: {
    fontSize: 11,
    fontWeight: '700',
  },
  lockedItem: {
    opacity: 0.6,
  },
  listScroll: {
    flex: 1,
  },
  list: {
    gap: 8,
  },
  addButton: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 2,
    paddingHorizontal: 8,
    paddingVertical: 4,
    borderRadius: 6,
  },
  addButtonText: {
    fontSize: 12,
    fontWeight: '600',
  },
});
