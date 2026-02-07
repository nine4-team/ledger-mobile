# TransactionCard Component Design

## Overview

The new `TransactionCard` component has been designed to align with both the modern mobile app design (exemplified by `ItemCard`) and the functional requirements from the legacy web application.

## Design Principles

### 1. Visual Alignment with ItemCard

The TransactionCard follows the same structural pattern as ItemCard:

- **Header Section**: Contains selector, spacer, and action buttons (bookmark, menu)
- **Content Section**: Contains main transaction information
- **Card Styling**: Uses identical border radius (16px), padding, shadows, and theming
- **Themed Colors**: Leverages `useUIKitTheme` for consistent theming
- **Selection State**: Border color changes to primary when selected
- **Pressable States**: Opacity changes on press for tactile feedback

### 2. Functional Parity with Legacy Web App

All features from the legacy transaction display are preserved:

| Legacy Feature | TransactionCard Implementation |
|----------------|-------------------------------|
| Transaction Title/Source | `source` prop, displayed prominently at top |
| Amount | `amountCents` prop, formatted as currency, right-aligned |
| Payment Method | `purchasedBy` prop, displayed as "Client" or "Design Business" |
| Transaction Date | `transactionDate` prop, formatted as "Jan 15, 2024" |
| Notes/Description | `notes` prop, line-clamped to 2 lines, italicized |
| Budget Category Badge | `budgetCategoryName` + `budgetCategoryColor` props |
| Transaction Type Badge | `transactionType` prop (purchase/sale/return/to-inventory) |
| "Needs Review" Indicator | `needsReview` prop, shown as red badge |
| Reimbursement Status | `reimbursementType` prop, shown as orange badge |
| Email Receipt | `hasEmailReceipt` prop, shown as badge |

## Component Structure

```
┌────────────────────────────────────────────────────────┐
│ Header (border bottom)                                 │
│ [●] Selector    <spacer>    [Bookmark] [Menu ⋮]       │
├────────────────────────────────────────────────────────┤
│ Content                                                │
│                                                        │
│ Source/Vendor Name                         $125.00    │
│ Client • Jan 15, 2024                                 │
│ Optional notes displayed here...                      │
│                                                        │
│ [Design Fee] [Purchase] [Needs Review] [Receipt]     │
└────────────────────────────────────────────────────────┘
```

## Badge Color Scheme

The component uses semantic colors for different badge types:

### Transaction Type Badges
- **Purchase**: Green (`#10b981` with opacity variants)
- **Sale**: Blue (`#3b82f6` with opacity variants)
- **Return**: Red (`#ef4444` with opacity variants)
- **To Inventory**: Primary theme color

### Status Badges
- **Needs Review**: Soft red (`#fee2e2` bg, `#991b1b` text, `#fecaca` border) — matches legacy `bg-red-100 text-red-800`
- **Reimbursement (Owed to Client)**: Orange (`#d97706`)
- **Reimbursement (Owed to Business)**: Orange (`#d97706`)
- **Email Receipt**: Primary theme color

### Budget Category Badge
- Uses `budgetCategoryColor` prop (a `CategoryBadgeColors` object with `bg`, `text`, `border`)
- Predefined categories use solid colors matching the legacy web app's Tailwind scheme
- Falls back to primary theme color with opacity if no color provided

## Props Interface

```typescript
export type TransactionCardProps = {
  // Core transaction data
  id: string;
  source: string;
  amountCents: number | null;
  transactionDate?: string;
  notes?: string;

  // Status and categorization
  budgetCategoryName?: string;
  budgetCategoryColor?: string; // Hex color for category badge
  transactionType?: 'purchase' | 'return' | 'sale' | 'to-inventory';
  needsReview?: boolean;
  reimbursementType?: 'owed-to-client' | 'owed-to-company';
  purchasedBy?: string; // 'client-card' | 'design-business' | etc.

  // Receipt and status
  hasEmailReceipt?: boolean;
  status?: 'pending' | 'completed' | 'canceled';

  // Interaction
  selected?: boolean;
  defaultSelected?: boolean;
  onSelectedChange?: (selected: boolean) => void;

  bookmarked?: boolean;
  onBookmarkPress?: () => void;

  onMenuPress?: () => void;
  menuItems?: AnchoredMenuItem[];
  onPress?: () => void;

  style?: StyleProp<ViewStyle>;
};
```

## Integration Example

Here's how to integrate TransactionCard into `SharedTransactionsList`:

### Before (Current Implementation)
```tsx
<Pressable ...>
  <Pressable ... (selector)>
    <SelectorCircle selected={...} />
  </Pressable>
  <View style={styles.rowContent}>
    <AppText variant="body">{item.label}</AppText>
    {item.subtitle ? <AppText variant="caption">{item.subtitle}</AppText> : null}
    {item.transaction.budgetCategoryId ? (
      <AppText variant="caption">
        {budgetCategories[item.transaction.budgetCategoryId]?.name}
      </AppText>
    ) : null}
  </View>
</Pressable>
```

### After (With TransactionCard)
```tsx
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
  budgetCategoryColor={getBudgetCategoryColor(item.transaction.budgetCategoryId)}
  transactionType={item.transaction.type as any}
  needsReview={item.transaction.needsReview}
  reimbursementType={item.transaction.reimbursementType as any}
  purchasedBy={item.transaction.purchasedBy}
  hasEmailReceipt={item.transaction.hasEmailReceipt}
  status={item.transaction.status as any}
  selected={selectedIds.includes(item.id)}
  onSelectedChange={() => toggleSelection(item.id)}
  onPress={() => {
    // Navigate to transaction detail
  }}
  menuItems={[
    { key: 'edit', label: 'Edit', onPress: () => {} },
    { key: 'delete', label: 'Delete', onPress: () => {} },
  ]}
/>
```

## Key Differences from ItemCard

While structurally similar, TransactionCard has these key differences:

1. **No Thumbnail**: Transactions don't have images like items do
2. **Amount Placement**: Amount is displayed prominently in the top row (right-aligned) rather than in metadata
3. **More Badge Types**: Supports transaction-specific badges (type, reimbursement, review status)
4. **Date Formatting**: Custom date formatter for transaction dates
5. **Notes Display**: Italicized notes vs. regular metadata in ItemCard
6. **No Index Label**: Transactions don't have grouped index labels

## Accessibility

The component includes proper accessibility features:

- `accessibilityRole` for buttons and checkbox
- `accessibilityLabel` for all interactive elements
- `accessibilityState` for checkbox selection
- Proper `hitSlop` for touch targets
- Support for screen readers

## Theme Support

The component fully supports theming through `useUIKitTheme`:

- Card background adapts to theme
- Text colors follow theme tokens
- Border colors respond to theme
- Shadow colors are theme-aware
- Button icons use theme colors
- Selection state uses primary color

## Future Enhancements

Potential future improvements:

1. **Attachment Indicators**: Show icon if transaction has attachments
2. **Item Count Badge**: Show number of linked items for transactions
3. **Swipe Actions**: Add swipe-to-delete or swipe-to-edit gestures
4. **Compact Mode**: Optional compact variant for dense lists
5. **Custom Badge Colors**: Allow passing custom colors for status badges
6. **Canonical Transaction Indicator**: Special badge for system-generated inventory transactions

## Testing Recommendations

When testing the TransactionCard component:

1. Test with all badge combinations to ensure proper wrapping
2. Verify long source names are properly truncated
3. Test selection state changes
4. Verify bookmark toggle functionality
5. Test menu interactions
6. Verify proper theming in light and dark modes
7. Test accessibility with screen readers
8. Verify touch targets meet minimum size requirements
9. Test with various transaction amounts (negative, zero, large numbers)
10. Verify proper date formatting for edge cases

## Migration Path

To migrate SharedTransactionsList to use TransactionCard:

1. Import TransactionCard component
2. Create budget category color mapping function
3. Replace the current row rendering with TransactionCard
4. Remove old row styles from StyleSheet
5. Test all interaction patterns (selection, navigation, menu)
6. Verify filter and sort still work correctly
7. Update any integration tests
