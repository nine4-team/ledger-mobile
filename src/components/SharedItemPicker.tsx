import { useMemo, useState } from 'react';
import { StyleSheet, TextInput, View } from 'react-native';
import { AppText } from './AppText';
import { AppButton } from './AppButton';
import { ItemCard } from './ItemCard';
import { GroupedItemCard } from './GroupedItemCard';
import { SegmentedControl } from './SegmentedControl';
import { useTheme, useUIKitTheme } from '../theme/ThemeProvider';
import { getTextInputStyle } from '../ui/styles/forms';
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
   * Label for the "Add Selected" button (default: "Add Selected").
   */
  addButtonLabel?: string;
  /**
   * Whether to show the "Select all visible" button (default: true).
   */
  showSelectAll?: boolean;
};

function getItemLabel(item: ScopedItem | Item) {
  return item.name?.trim() || item.description?.trim() || 'Item';
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
  addButtonLabel = 'Add Selected',
  showSelectAll = true,
}: SharedItemPickerProps) {
  const theme = useTheme();
  const uiKitTheme = useUIKitTheme();
  const [searchQuery, setSearchQuery] = useState('');

  // Filter items by search query
  const filteredItems = useMemo(() => {
    const needle = searchQuery.trim().toLowerCase();
    if (!needle) return items;
    return items.filter((item) => {
      const label = item.name?.toLowerCase() ?? item.description?.toLowerCase() ?? '';
      return label.includes(needle);
    });
  }, [items, searchQuery]);

  // Group items by name/description (for duplicate grouping)
  const pickerGroups = useMemo(() => {
    const groups = new Map<string, Array<ScopedItem | Item>>();
    filteredItems.forEach((item) => {
      const label = item.name?.trim() || item.description?.trim() || 'Item';
      const key = label.toLowerCase();
      const list = groups.get(key) ?? [];
      list.push(item);
      groups.set(key, list);
    });
    return Array.from(groups.entries());
  }, [filteredItems]);

  // Get eligible item IDs for "select all visible"
  const eligibleIds = useMemo(() => {
    return filteredItems.filter((item) => eligibilityCheck.isEligible(item)).map((item) => item.id);
  }, [filteredItems, eligibilityCheck]);

  const handleSelectAll = () => {
    onSelectionChange(Array.from(new Set([...selectedIds, ...eligibleIds])));
  };

  const handleItemToggle = (itemId: string) => {
    onSelectionChange(
      selectedIds.includes(itemId) ? selectedIds.filter((id) => id !== itemId) : [...selectedIds, itemId]
    );
  };

  const handleGroupToggle = (groupItemIds: string[]) => {
    const allSelected = groupItemIds.length > 0 && groupItemIds.every((id) => selectedIds.includes(id));
    if (allSelected) {
      const remove = new Set(groupItemIds);
      onSelectionChange(selectedIds.filter((id) => !remove.has(id)));
    } else {
      onSelectionChange(Array.from(new Set([...selectedIds, ...groupItemIds])));
    }
  };

  return (
    <View style={styles.container}>
      <SegmentedControl
        value={selectedTab}
        options={tabs}
        onChange={(next) => {
          onTabChange(next);
          onSelectionChange([]); // Clear selection when switching tabs
        }}
        accessibilityLabel="Item picker tabs"
      />
      <TextInput
        value={searchQuery}
        onChangeText={setSearchQuery}
        placeholder={searchPlaceholder}
        placeholderTextColor={theme.colors.textSecondary}
        style={getTextInputStyle(uiKitTheme, { padding: 10, radius: 8 })}
      />
      <View style={styles.actions}>
        {showSelectAll ? (
          <AppButton title="Select all visible" variant="secondary" onPress={handleSelectAll} />
        ) : null}
        <AppButton
          title={`${addButtonLabel} (${selectedIds.length})`}
          onPress={onAddSelected}
          disabled={selectedIds.length === 0}
        />
      </View>
      <View style={styles.list}>
        {pickerGroups.map(([label, groupItems]) => {
          const groupEligibleIds = groupItems.filter((item) => eligibilityCheck.isEligible(item)).map((item) => item.id);
          const groupAllSelected = groupEligibleIds.length > 0 && groupEligibleIds.every((id) => selectedIds.includes(id));
          const summaryItem = groupItems.find((item) => Boolean(getPrimaryImage(item))) ?? groupItems[0];
          const summaryThumbnailUri = summaryItem ? getPrimaryImage(summaryItem) : undefined;

          if (groupItems.length > 1) {
            return (
              <GroupedItemCard
                key={label}
                summary={{
                  description: label,
                  sku: summaryItem?.sku ?? undefined,
                  sourceLabel: summaryItem?.source ?? undefined,
                  locationLabel: summaryItem?.spaceId ?? undefined,
                  notes: summaryItem?.notes ?? undefined,
                  thumbnailUri: summaryThumbnailUri,
                }}
                countLabel={`×${groupItems.length}`}
                items={groupItems.map((item) => {
                  const description = getItemLabel(item);
                  const locked = !eligibilityCheck.isEligible(item);
                  const statusLabel = eligibilityCheck.getStatusLabel?.(item);
                  const selected = selectedIds.includes(item.id);
                  const thumbnailUri = getPrimaryImage(item);

                  return {
                    description,
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
                        handleGroupToggle(groupEligibleIds);
                      }
                }
              />
            );
          }

          const [only] = groupItems;
          const description = getItemLabel(only);
          const locked = !eligibilityCheck.isEligible(only);
          const selected = selectedIds.includes(only.id);
          const statusLabel = eligibilityCheck.getStatusLabel?.(only);

          return (
            <ItemCard
              key={only.id}
              description={description}
              sku={only.sku ?? undefined}
              sourceLabel={only.source ?? undefined}
              locationLabel={only.spaceId ?? undefined}
              notes={only.notes ?? undefined}
              thumbnailUri={getPrimaryImage(only)}
              selected={selected}
              onSelectedChange={locked ? undefined : (next) => handleItemToggle(only.id)}
              onPress={locked ? undefined : () => handleItemToggle(only.id)}
              statusLabel={statusLabel}
              style={locked ? styles.lockedItem : undefined}
            />
          );
        })}
        {pickerGroups.length === 0 ? (
          <AppText variant="body" style={getTextSecondaryStyle(uiKitTheme)}>
            No items available.
          </AppText>
        ) : null}
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
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    gap: 12,
  },
  lockedItem: {
    opacity: 0.6,
  },
  actions: {
    flexDirection: 'row',
    gap: 12,
    alignItems: 'center',
  },
  list: {
    gap: 8,
  },
});
