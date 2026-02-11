import React, { useCallback, useMemo } from 'react';
import { Pressable, Text } from 'react-native';
import MaterialIcons from '@expo/vector-icons/MaterialIcons';
import type { ScopedItem } from '../data/scopedListData';
import type { Item } from '../data/itemsService';
import type { ItemCardProps } from '../components/ItemCard';
import { useUIKitTheme } from '../theme/ThemeProvider';

/**
 * Eligibility check for picker mode.
 */
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

/**
 * Configuration for usePickerMode hook.
 */
export type UsePickerModeConfig = {
  /**
   * Whether picker mode is enabled.
   */
  enabled: boolean;
  /**
   * All items being displayed.
   */
  items: Array<ScopedItem | Item>;
  /**
   * Eligibility check function (optional, defaults to all eligible).
   */
  eligibilityCheck?: ItemEligibilityCheck;
  /**
   * Callback for single-item quick-add (renders "Add" button on eligible items).
   */
  onAddSingle?: (item: ScopedItem | Item) => void | Promise<void>;
  /**
   * Set of item IDs that have already been added (shows "Added" badge).
   */
  addedIds?: Set<string>;
  /**
   * Currently selected item IDs (string array).
   */
  selectedIds: string[];
  /**
   * Callback to set item selection state.
   */
  setItemSelected: (id: string, selected: boolean) => void;
  /**
   * Callback to set group selection state.
   */
  setGroupSelection: (ids: string[], selected: boolean) => void;
};

/**
 * Return value from usePickerMode hook.
 */
export type UsePickerModeReturn = {
  /**
   * IDs of eligible items (for select-all behavior).
   */
  eligibleIds: string[];
  /**
   * Whether all eligible items are selected.
   */
  allEligibleSelected: boolean;
  /**
   * Handler for select-all button.
   */
  handleSelectAll: () => void;
  /**
   * Factory function that returns picker-specific props for an item card.
   */
  getPickerItemProps: (item: ScopedItem | Item, isSelected: boolean) => Partial<ItemCardProps>;
  /**
   * Factory function that returns picker-specific props for a group card.
   */
  getPickerGroupProps: (
    groupItems: Array<ScopedItem | Item>,
    groupIds: string[]
  ) => {
    selected?: boolean;
    onSelectedChange?: (selected: boolean) => void;
    onPress?: () => void;
  };
  /**
   * Render function for the "Add" button on individual items.
   */
  renderAddButton: (item: ScopedItem | Item, locked: boolean) => React.ReactNode;
};

/**
 * Hook that provides picker mode behavior for SharedItemsList.
 * Returns no-op functions when picker mode is disabled.
 */
export function usePickerMode(config: UsePickerModeConfig): UsePickerModeReturn {
  const {
    enabled,
    items,
    eligibilityCheck,
    onAddSingle,
    addedIds,
    selectedIds,
    setItemSelected,
    setGroupSelection,
  } = config;

  // Default eligibility check: all items are eligible
  const defaultEligibilityCheck: ItemEligibilityCheck = useMemo(
    () => ({
      isEligible: () => true,
    }),
    []
  );

  const actualEligibilityCheck = eligibilityCheck ?? defaultEligibilityCheck;
  const uiKitTheme = useUIKitTheme();

  // Compute eligible item IDs (excluding already-added items)
  const eligibleIds = useMemo(() => {
    if (!enabled) return [];
    return items
      .filter((item) => {
        if (!actualEligibilityCheck.isEligible(item)) return false;
        return !addedIds?.has(item.id);
      })
      .map((item) => item.id);
  }, [enabled, items, actualEligibilityCheck, addedIds]);

  // Check if all eligible items are selected
  const allEligibleSelected = useMemo(() => {
    if (!enabled) return false;
    return eligibleIds.length > 0 && eligibleIds.every((id) => selectedIds.includes(id));
  }, [enabled, eligibleIds, selectedIds]);

  // Handle select-all: toggle all eligible items
  const handleSelectAll = useCallback(() => {
    if (!enabled) return;
    if (allEligibleSelected) {
      // Deselect all eligible
      eligibleIds.forEach((id) => setItemSelected(id, false));
    } else {
      // Select all eligible (additive, don't clear other selections)
      eligibleIds.forEach((id) => setItemSelected(id, true));
    }
  }, [enabled, allEligibleSelected, eligibleIds, setItemSelected]);

  // Factory function: get picker-specific props for an item card
  const getPickerItemProps = useCallback(
    (item: ScopedItem | Item, isSelected: boolean): Partial<ItemCardProps> => {
      if (!enabled) return {};

      const locked = !actualEligibilityCheck.isEligible(item);
      const alreadyAdded = addedIds?.has(item.id) ?? false;
      const eligible = !locked;
      const canInteract = eligible && !alreadyAdded;
      const statusLabel = actualEligibilityCheck.getStatusLabel?.(item);

      return {
        selected: isSelected,
        onSelectedChange: !canInteract
          ? undefined
          : (next) => {
              setItemSelected(item.id, next);
            },
        onPress: !canInteract
          ? undefined
          : () => {
              setItemSelected(item.id, !isSelected);
            },
        onBookmarkPress: undefined,
        onStatusPress: undefined,
        menuItems: undefined,
        statusLabel: statusLabel || undefined,
        headerAction: renderAddButton(item, !eligible || alreadyAdded),
        style: locked ? { opacity: 0.6 } : undefined,
      };
    },
    [enabled, actualEligibilityCheck, setItemSelected, addedIds]
  );

  // Factory function: get picker-specific props for a group card
  const getPickerGroupProps = useCallback(
    (groupItems: Array<ScopedItem | Item>, groupIds: string[]) => {
      if (!enabled) {
        return {
          selected: false,
          onSelectedChange: undefined,
          onPress: undefined,
        };
      }

      const groupEligibleIds = groupItems
        .filter((item) => actualEligibilityCheck.isEligible(item) && !addedIds?.has(item.id))
        .map((item) => item.id);

      // No eligible items → hide selector entirely
      if (groupEligibleIds.length === 0) {
        return {
          selected: undefined,
          onSelectedChange: undefined,
          onPress: undefined,
        };
      }

      const groupAllSelected = groupEligibleIds.every((id) => selectedIds.includes(id));

      return {
        selected: groupAllSelected,
        onSelectedChange: (next: boolean) => {
          setGroupSelection(groupEligibleIds, next);
        },
        // Body tap toggles group selection (FR-2.2)
        onPress: () => {
          setGroupSelection(groupEligibleIds, !groupAllSelected);
        },
      };
    },
    [enabled, actualEligibilityCheck, selectedIds, setGroupSelection, addedIds]
  );

  // Render function for "Add" button on individual items
  const renderAddButton = useCallback(
    (item: ScopedItem | Item, locked: boolean): React.ReactNode => {
      if (!enabled || !onAddSingle) return undefined;

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
    [enabled, onAddSingle, addedIds, uiKitTheme]
  );

  return {
    eligibleIds,
    allEligibleSelected,
    handleSelectAll,
    getPickerItemProps,
    getPickerGroupProps,
    renderAddButton,
  };
}

const styles = {
  addButton: {
    flexDirection: 'row' as const,
    alignItems: 'center' as const,
    gap: 2,
    paddingHorizontal: 8,
    paddingVertical: 4,
    borderRadius: 6,
  },
  addButtonText: {
    fontSize: 12,
    fontWeight: '600' as const,
  },
};
