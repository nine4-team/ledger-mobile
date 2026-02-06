# TransactionCard Integration Guide

## Overview

This guide provides step-by-step instructions for integrating the new `TransactionCard` component into `SharedTransactionsList`.

## Step 1: Import the Component and Utility

At the top of `SharedTransactionsList.tsx`, add these imports:

```typescript
import { TransactionCard } from './TransactionCard';
import { getBudgetCategoryColor } from '../utils/budgetCategoryColors';
```

## Step 2: Replace the Row Rendering

### Current Implementation (Lines 1088-1138)

```tsx
renderItem={({ item }) => (
  <Pressable
    onPress={() => {
      setRestoreHint({ anchorId: item.id, scrollOffset: lastScrollOffsetRef.current });
      const backTarget =
        scopeConfig.scope === 'inventory'
          ? '/(tabs)/screen-two?tab=transactions'
          : scopeConfig.projectId
            ? `/project/${scopeConfig.projectId}?tab=transactions`
            : '/(tabs)/index';
      router.push({
        pathname: '/transactions/[id]',
        params: {
          id: item.id,
          listStateKey,
          backTarget,
          scope: scopeConfig.scope,
          projectId: scopeConfig.projectId ?? '',
        },
      });
    }}
    style={({ pressed }) => [
      styles.row,
      rowSurfaceStyle,
      selectedIds.includes(item.id) ? { borderColor: uiKitTheme.primary.main } : null,
      pressed && styles.rowPressed,
    ]}
  >
    <Pressable
      onPress={(e) => {
        e.stopPropagation();
        toggleSelection(item.id);
      }}
      accessibilityRole="checkbox"
      accessibilityLabel={`Select ${item.label}`}
      accessibilityState={{ checked: selectedIds.includes(item.id) }}
      hitSlop={13}
      style={styles.selectorContainer}
    >
      <SelectorCircle selected={selectedIds.includes(item.id)} indicator="dot" />
    </Pressable>
    <View style={styles.rowContent}>
      <AppText variant="body">{item.label}</AppText>
      {item.subtitle ? <AppText variant="caption">{item.subtitle}</AppText> : null}
      {item.transaction.budgetCategoryId ? (
        <AppText variant="caption">
          {budgetCategories[item.transaction.budgetCategoryId]?.name ?? item.transaction.budgetCategoryId}
        </AppText>
      ) : null}
    </View>
  </Pressable>
)}
```

### New Implementation (With TransactionCard)

```tsx
renderItem={({ item }) => {
  const handlePress = () => {
    setRestoreHint({ anchorId: item.id, scrollOffset: lastScrollOffsetRef.current });
    const backTarget =
      scopeConfig.scope === 'inventory'
        ? '/(tabs)/screen-two?tab=transactions'
        : scopeConfig.projectId
          ? `/project/${scopeConfig.projectId}?tab=transactions`
          : '/(tabs)/index';
    router.push({
      pathname: '/transactions/[id]',
      params: {
        id: item.id,
        listStateKey,
        backTarget,
        scope: scopeConfig.scope,
        projectId: scopeConfig.projectId ?? '',
      },
    });
  };

  return (
    <TransactionCard
      id={item.transaction.id}
      source={item.transaction.source ?? ''}
      amountCents={item.transaction.amountCents ?? null}
      transactionDate={item.transaction.transactionDate}
      notes={item.transaction.notes}
      budgetCategoryName={
        item.transaction.budgetCategoryId
          ? budgetCategories[item.transaction.budgetCategoryId]?.name
          : undefined
      }
      budgetCategoryColor={getBudgetCategoryColor(
        item.transaction.budgetCategoryId,
        budgetCategories
      )}
      transactionType={item.transaction.type as any}
      needsReview={item.transaction.needsReview}
      reimbursementType={item.transaction.reimbursementType as any}
      purchasedBy={item.transaction.purchasedBy}
      hasEmailReceipt={item.transaction.hasEmailReceipt}
      status={item.transaction.status as any}
      selected={selectedIds.includes(item.id)}
      onSelectedChange={() => toggleSelection(item.id)}
      onPress={handlePress}
      // Optional: Add menu items for quick actions
      menuItems={[
        {
          key: 'edit',
          label: 'Edit Transaction',
          onPress: () => {
            router.push({
              pathname: '/transactions/[id]/edit',
              params: { id: item.id },
            });
          },
        },
        {
          key: 'duplicate',
          label: 'Duplicate',
          onPress: () => {
            // Handle duplicate
          },
        },
        {
          key: 'delete',
          label: 'Delete',
          destructive: true,
          onPress: () => {
            // Handle delete
          },
        },
      ]}
    />
  );
}}
```

## Step 3: Update Styles

Remove or comment out these unused styles from the StyleSheet:

```typescript
// BEFORE: These styles are no longer needed
const styles = StyleSheet.create({
  // ... keep these:
  container: { ... },
  controlSection: { ... },
  selectButton: { ... },
  list: { ... },
  emptyState: { ... },
  bulkBar: { ... },
  // etc.

  // REMOVE/COMMENT OUT these:
  // row: { ... },                  // Replaced by TransactionCard styles
  // rowPressed: { ... },           // Replaced by TransactionCard styles
  // selectorContainer: { ... },    // Replaced by TransactionCard styles
  // rowContent: { ... },           // Replaced by TransactionCard styles
});
```

## Step 4: Remove Unused Theme Styles

Remove or comment out these memo-ized theme styles:

```typescript
// BEFORE: These are no longer needed
const rowSurfaceStyle = useMemo(
  () => ({ borderColor: uiKitTheme.border.primary, backgroundColor: uiKitTheme.background.surface }),
  [uiKitTheme]
);
```

The TransactionCard handles its own theming internally.

## Step 5: Update List Container Styles

The FlatList `contentContainerStyle` can be simplified:

```typescript
// BEFORE
contentContainerStyle={[styles.list, selectedIds.length > 0 ? styles.listWithBulkBar : null]}

// AFTER (same, but now uses gap instead of card margins)
contentContainerStyle={[styles.list, selectedIds.length > 0 ? styles.listWithBulkBar : null]}
```

Update the list style to use gap:

```typescript
list: {
  paddingBottom: layout.screenBodyTopMd.paddingTop,
  gap: 10, // Keep this - space between TransactionCards
},
```

## Step 6: Optional - Add Bookmark Support

If you want to add bookmark functionality to transactions:

### 6.1: Add State

```typescript
const [bookmarkedIds, setBookmarkedIds] = useState<Set<string>>(new Set());
```

### 6.2: Add Toggle Handler

```typescript
const toggleBookmark = useCallback((id: string) => {
  setBookmarkedIds((prev) => {
    const next = new Set(prev);
    if (next.has(id)) {
      next.delete(id);
    } else {
      next.add(id);
    }
    return next;
  });
}, []);
```

### 6.3: Pass to TransactionCard

```typescript
<TransactionCard
  // ... other props
  bookmarked={bookmarkedIds.has(item.id)}
  onBookmarkPress={() => toggleBookmark(item.id)}
/>
```

## Step 7: Optional - Enhance with Menu Actions

Add contextual menu items based on transaction state:

```typescript
const getMenuItems = useCallback((transaction: ScopedTransaction): AnchoredMenuItem[] => {
  const items: AnchoredMenuItem[] = [
    {
      key: 'edit',
      label: 'Edit Transaction',
      icon: 'edit',
      onPress: () => {
        router.push({
          pathname: '/transactions/[id]/edit',
          params: { id: transaction.id },
        });
      },
    },
    {
      key: 'duplicate',
      label: 'Duplicate',
      icon: 'content-copy',
      onPress: () => {
        // Handle duplicate
      },
    },
  ];

  // Add conditional menu items
  if (transaction.needsReview) {
    items.push({
      key: 'mark-reviewed',
      label: 'Mark as Reviewed',
      icon: 'check-circle',
      onPress: () => {
        // Handle marking as reviewed
      },
    });
  }

  if (scopeConfig.capabilities?.canDelete) {
    items.push({
      key: 'delete',
      label: 'Delete',
      icon: 'delete',
      destructive: true,
      onPress: () => {
        // Handle delete
      },
    });
  }

  return items;
}, [router, scopeConfig.capabilities]);
```

Then use it in the renderItem:

```typescript
<TransactionCard
  // ... other props
  menuItems={getMenuItems(item.transaction)}
/>
```

## Complete Example

Here's a complete example of the updated renderItem function:

```typescript
renderItem={({ item }) => {
  const tx = item.transaction;

  const handlePress = () => {
    setRestoreHint({
      anchorId: item.id,
      scrollOffset: lastScrollOffsetRef.current
    });

    const backTarget =
      scopeConfig.scope === 'inventory'
        ? '/(tabs)/screen-two?tab=transactions'
        : scopeConfig.projectId
          ? `/project/${scopeConfig.projectId}?tab=transactions`
          : '/(tabs)/index';

    router.push({
      pathname: '/transactions/[id]',
      params: {
        id: item.id,
        listStateKey,
        backTarget,
        scope: scopeConfig.scope,
        projectId: scopeConfig.projectId ?? '',
      },
    });
  };

  return (
    <TransactionCard
      // Core data
      id={tx.id}
      source={tx.source ?? ''}
      amountCents={tx.amountCents ?? null}
      transactionDate={tx.transactionDate}
      notes={tx.notes}

      // Categorization
      budgetCategoryName={
        tx.budgetCategoryId
          ? budgetCategories[tx.budgetCategoryId]?.name
          : undefined
      }
      budgetCategoryColor={getBudgetCategoryColor(
        tx.budgetCategoryId,
        budgetCategories
      )}
      transactionType={tx.type as any}

      // Status
      needsReview={tx.needsReview}
      reimbursementType={tx.reimbursementType as any}
      purchasedBy={tx.purchasedBy}
      hasEmailReceipt={tx.hasEmailReceipt}
      status={tx.status as any}

      // Interaction
      selected={selectedIds.includes(item.id)}
      onSelectedChange={() => toggleSelection(item.id)}
      onPress={handlePress}

      // Optional features
      bookmarked={bookmarkedIds.has(item.id)}
      onBookmarkPress={() => toggleBookmark(item.id)}
      menuItems={getMenuItems(tx)}
    />
  );
}}
```

## Testing Checklist

After integration, test the following:

### Visual Testing
- [ ] Cards render correctly with all data
- [ ] Badges display with correct colors
- [ ] Long source names truncate properly
- [ ] Notes wrap and truncate at 2 lines
- [ ] Amounts display correctly (positive, negative, zero)
- [ ] Dates format correctly
- [ ] Badge wrapping works with many badges

### Interaction Testing
- [ ] Card press navigates to detail view
- [ ] Selection toggle works correctly
- [ ] Menu opens and closes properly
- [ ] Menu actions execute correctly
- [ ] Bookmark toggle works (if implemented)
- [ ] Bulk selection still works
- [ ] Filter and sort still work

### Theming Testing
- [ ] Cards display correctly in light mode
- [ ] Cards display correctly in dark mode
- [ ] Selected state shows primary color border
- [ ] All text colors follow theme

### Accessibility Testing
- [ ] Screen reader announces cards correctly
- [ ] Selection checkbox is accessible
- [ ] Menu button is accessible
- [ ] Touch targets are adequate size
- [ ] Focus order is logical

### Performance Testing
- [ ] List scrolls smoothly with many transactions
- [ ] No performance degradation vs. old implementation
- [ ] Memoization works correctly

## Common Issues and Solutions

### Issue: Budget category colors not showing

**Solution**: Make sure you've imported and are using the `getBudgetCategoryColor` utility:

```typescript
import { getBudgetCategoryColor } from '../utils/budgetCategoryColors';

// In renderItem:
budgetCategoryColor={getBudgetCategoryColor(
  tx.budgetCategoryId,
  budgetCategories
)}
```

### Issue: Cards not filling list width

**Solution**: The TransactionCard doesn't have a width style by default. The FlatList should handle this automatically, but if needed, you can wrap it:

```typescript
<View style={{ width: '100%' }}>
  <TransactionCard ... />
</View>
```

### Issue: Selection not working

**Solution**: Make sure you're passing both `selected` and `onSelectedChange`:

```typescript
selected={selectedIds.includes(item.id)}
onSelectedChange={() => toggleSelection(item.id)}
```

### Issue: Amounts showing as "No amount"

**Solution**: Ensure you're passing `amountCents` as a number, not undefined:

```typescript
amountCents={tx.amountCents ?? null}
```

### Issue: Type errors on transactionType or reimbursementType

**Solution**: Use type assertion for now (can be fixed with proper typing later):

```typescript
transactionType={tx.type as any}
reimbursementType={tx.reimbursementType as any}
```

## Migration Timeline

Recommended migration approach:

1. **Phase 1**: Create the component and utilities (✅ Complete)
2. **Phase 2**: Add TransactionCard to one screen for testing
3. **Phase 3**: Verify all functionality works correctly
4. **Phase 4**: Migrate SharedTransactionsList
5. **Phase 5**: Clean up old styles and code
6. **Phase 6**: Update tests and documentation

## Rollback Plan

If issues arise, you can easily rollback:

1. Keep the old renderItem code commented above the new version
2. Simply uncomment the old code and comment out the TransactionCard usage
3. Restore the removed styles

```typescript
// OLD IMPLEMENTATION (keep commented for easy rollback)
// renderItem={({ item }) => (
//   <Pressable ... >
//     ...
//   </Pressable>
// )}

// NEW IMPLEMENTATION
renderItem={({ item }) => (
  <TransactionCard ... />
)}
```

## Next Steps

After successful integration:

1. Gather user feedback on the new design
2. Monitor for any performance issues
3. Consider adding additional features:
   - Swipe actions for quick edit/delete
   - Long-press for multi-select
   - Attachment indicators
   - Item count badges for transactions with items
4. Update any screenshots in documentation
5. Update any video demos or tutorials
