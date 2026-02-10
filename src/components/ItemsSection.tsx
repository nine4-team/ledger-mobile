import { View, StyleSheet, Pressable } from 'react-native';
import { UseItemsManagerReturn } from '../hooks/useItemsManager';
import { ScopedItem } from '../data/scopedListData';
import { AnchoredMenuItem } from './AnchoredMenuList';
import { useUIKitTheme } from '../theme/ThemeProvider';
import { AppText } from './AppText';
import { ItemCard } from './ItemCard';
import { AppButton } from './AppButton';

export type BulkAction = {
  id: string;
  label: string;
  variant: 'primary' | 'secondary' | 'destructive';
  icon?: string;
};

export type ItemsSectionProps<S extends string = string, F extends string = string> = {
  // State from useItemsManager
  manager: UseItemsManagerReturn<S, F>;

  // Item rendering
  items: ScopedItem[];
  onItemPress: (id: string) => void;
  getItemMenuItems: (item: ScopedItem) => AnchoredMenuItem[];
  onBookmarkPress?: (item: ScopedItem) => void;

  // Bulk actions (screen-specific)
  bulkActions?: BulkAction[];
  onBulkAction?: (actionId: string, selectedIds: string[]) => void;

  // Display
  emptyMessage?: string;
};

/**
 * @deprecated Use SharedItemsList with embedded={true} instead.
 *
 * This component was created in feature 004-detail-screen-normalization but lacks
 * key features present in SharedItemsList:
 * - No grouped cards (uses plain ItemCard instead of GroupedItemCard)
 * - No selector circles on item cards
 * - No status badges
 * - Broken bulk selection toggle (doesn't deselect when all selected)
 * - Inline bulk panel instead of bottom bar + bottom sheet pattern
 *
 * Migration guide: See kitty-specs/005-detail-screen-polish/quickstart.md §1
 * for how to use SharedItemsList in embedded mode.
 *
 * Replaced by SharedItemsList in:
 * - Transaction detail (WP02)
 * - Space detail (WP04)
 *
 * This component will be removed in a future cleanup feature once all usages
 * are migrated and verified stable.
 */
export function ItemsSection<S extends string = string, F extends string = string>({
  manager,
  items,
  onItemPress,
  getItemMenuItems,
  onBookmarkPress,
  bulkActions,
  onBulkAction,
  emptyMessage = 'No items.',
}: ItemsSectionProps<S, F>) {
  const { selectedIds, toggleSelection, hasSelection } = manager;
  const uiKitTheme = useUIKitTheme();

  // Helper to get primary image URI
  const getPrimaryImageUri = (item: ScopedItem): string | undefined => {
    const primary = item.images?.find(img => img.isPrimary);
    return primary?.url ?? item.images?.[0]?.url;
  };

  // Helper to get display price
  const getDisplayPrice = (item: ScopedItem): string | undefined => {
    if (typeof item.purchasePriceCents === 'number') {
      return `$${(item.purchasePriceCents / 100).toFixed(2)}`;
    }
    return undefined;
  };

  return (
    <View>
      {/* Bulk panel */}
      {hasSelection && bulkActions && onBulkAction && (
        <View style={styles.bulkPanel}>
          <View style={styles.bulkHeader}>
            <AppText variant="body">
              {manager.selectionCount} selected
            </AppText>
            <View style={styles.bulkActions}>
              <Pressable onPress={manager.selectAll}>
                <AppText variant="caption" style={{ color: uiKitTheme.primary.main }}>
                  {manager.allSelected ? 'Deselect All' : 'Select All'}
                </AppText>
              </Pressable>
              <Pressable onPress={manager.clearSelection}>
                <AppText variant="caption" style={{ color: uiKitTheme.text.secondary }}>
                  Clear
                </AppText>
              </Pressable>
            </View>
          </View>

          <View style={styles.bulkButtonRow}>
            {bulkActions.map(action => (
              <AppButton
                key={action.id}
                title={action.label}
                variant={action.variant === 'destructive' ? 'secondary' : action.variant}
                onPress={() => onBulkAction(action.id, [...manager.selectedIds])}
                icon={action.icon}
              />
            ))}
          </View>
        </View>
      )}

      {/* Items list */}
      {items.length === 0 ? (
        <View style={styles.emptyState}>
          <AppText variant="body" style={{ color: uiKitTheme.text.secondary }}>
            {emptyMessage}
          </AppText>
        </View>
      ) : (
        <View style={styles.list}>
          {items.map(item => (
            <ItemCard
              key={item.id}
              name={item.name?.trim() || 'Untitled item'}
              sku={item.sku ?? undefined}
              priceLabel={getDisplayPrice(item)}
              thumbnailUri={getPrimaryImageUri(item)}
              bookmarked={item.bookmark ?? undefined}
              selected={hasSelection ? selectedIds.has(item.id) : undefined}
              onSelectedChange={hasSelection
                ? () => toggleSelection(item.id)
                : undefined}
              onBookmarkPress={onBookmarkPress
                ? () => onBookmarkPress(item)
                : undefined}
              onPress={() => onItemPress(item.id)}
              menuItems={getItemMenuItems(item)}
            />
          ))}
        </View>
      )}
    </View>
  );
}

const styles = StyleSheet.create({
  list: { gap: 10 },
  emptyState: { alignItems: 'center', paddingVertical: 16 },
  bulkPanel: { gap: 10, marginBottom: 12 },
  bulkHeader: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center' },
  bulkActions: { flexDirection: 'row', gap: 12, alignItems: 'center' },
  bulkButtonRow: { flexDirection: 'row', gap: 10, flexWrap: 'wrap' },
});
