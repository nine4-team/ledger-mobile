# TransactionCard Component - Complete Documentation

## Quick Links

- **Component File**: `/src/components/TransactionCard.tsx`
- **Utility File**: `/src/utils/budgetCategoryColors.ts`
- **Design Spec**: `./TransactionCard_Design.md`
- **Visual Comparison**: `./TransactionCard_Visual_Comparison.md`
- **Integration Guide**: `./TransactionCard_Integration_Guide.md`

## Overview

The `TransactionCard` component is a new shared component designed to replace the inline transaction rendering in `SharedTransactionsList`. It provides a consistent, feature-rich UI for displaying transaction information that:

1. ✅ Aligns visually with the `ItemCard` component (modern mobile app design)
2. ✅ Maintains functional parity with the legacy web application
3. ✅ Supports all transaction states, badges, and indicators
4. ✅ Follows the app's theming and accessibility standards

## What's Included

### 1. TransactionCard Component
**Location**: `/src/components/TransactionCard.tsx`

A fully-featured card component with:
- Header section with selector, bookmark, and menu
- Source/vendor name and amount display
- Transaction details (date, purchased by)
- Notes display (italicized, 2-line truncation)
- Badge system for categories, types, and statuses
- Full theming support
- Accessibility features
- Menu integration

### 2. Budget Category Color Utility
**Location**: `/src/utils/budgetCategoryColors.ts`

Helper functions for:
- Mapping category names to colors
- Generating consistent colors for unknown categories
- Managing custom color schemes
- Matching legacy web app color palette

### 3. Documentation

#### Design Specification
**File**: `TransactionCard_Design.md`

Covers:
- Design principles and patterns
- Component structure and layout
- Props interface and usage
- Badge color schemes
- Accessibility features
- Future enhancement ideas

#### Visual Comparison
**File**: `TransactionCard_Visual_Comparison.md`

Includes:
- Side-by-side component comparisons
- ItemCard vs TransactionCard anatomy
- Legacy web vs new mobile design
- Typography and spacing alignment
- Color scheme mapping
- Shared vs unique features

#### Integration Guide
**File**: `TransactionCard_Integration_Guide.md`

Provides:
- Step-by-step integration instructions
- Before/after code examples
- Complete usage examples
- Testing checklist
- Common issues and solutions
- Rollback plan

## Quick Start

### Basic Usage

```tsx
import { TransactionCard } from '../components/TransactionCard';
import { getBudgetCategoryColor } from '../utils/budgetCategoryColors';

<TransactionCard
  id={transaction.id}
  source={transaction.source ?? ''}
  amountCents={transaction.amountCents ?? null}
  transactionDate={transaction.transactionDate}
  notes={transaction.notes}
  budgetCategoryName={categoryName}
  budgetCategoryColor={getBudgetCategoryColor(categoryId, categories)}
  transactionType={transaction.type}
  needsReview={transaction.needsReview}
  selected={isSelected}
  onSelectedChange={handleSelection}
  onPress={handlePress}
/>
```

### Integration into SharedTransactionsList

Replace the current inline Pressable rendering with:

```tsx
renderItem={({ item }) => (
  <TransactionCard
    id={item.transaction.id}
    source={item.transaction.source ?? ''}
    amountCents={item.transaction.amountCents ?? null}
    // ... other props
    selected={selectedIds.includes(item.id)}
    onSelectedChange={() => toggleSelection(item.id)}
    onPress={() => {/* navigate to detail */}}
  />
)}
```

See the Integration Guide for complete details.

## Key Features

### Visual Design
- ✅ Matches ItemCard structure and styling
- ✅ 16px border radius, consistent padding
- ✅ Theme-aware colors and shadows
- ✅ Responsive text truncation
- ✅ Proper spacing and alignment

### Functional Features
- ✅ All legacy web app features preserved
- ✅ Multiple badge types (category, type, status, reimbursement)
- ✅ Selection support with visual feedback
- ✅ Menu integration for quick actions
- ✅ Optional bookmark support
- ✅ Notes display
- ✅ Proper date and currency formatting

### Interaction
- ✅ Press state feedback
- ✅ Selection toggle
- ✅ Menu actions
- ✅ Bookmark toggle
- ✅ Proper touch targets
- ✅ Stop propagation where needed

### Accessibility
- ✅ Proper accessibility roles
- ✅ Descriptive labels
- ✅ Checkbox state announcements
- ✅ Adequate hit slop
- ✅ Screen reader support

### Theming
- ✅ Full UIKit theme integration
- ✅ Light and dark mode support
- ✅ Semantic colors for badges
- ✅ Theme-aware text and borders

## Badge System

The component supports multiple badge types:

### Transaction Type Badges
- **Purchase**: Green (`#10b981`)
- **Sale**: Blue (`#3b82f6`)
- **Return**: Red (`#ef4444`)
- **To Inventory**: Primary theme color

### Status Badges
- **Needs Review**: Red (`#dc2626`)
- **Reimbursement (Client)**: Orange (`#d97706`)
- **Reimbursement (Business)**: Orange (`#d97706`)
- **Email Receipt**: Primary theme color

### Budget Category Badges
- Uses predefined colors from legacy web app
- Falls back to generated colors for unknown categories
- Supports custom color mapping

## Props Reference

### Required Props
- `id: string` - Transaction ID
- `source: string` - Vendor/source name
- `amountCents: number | null` - Transaction amount in cents

### Optional Props
- `transactionDate?: string` - ISO date string
- `notes?: string` - Transaction notes
- `budgetCategoryName?: string` - Category display name
- `budgetCategoryColor?: string` - Category color (hex)
- `transactionType?: 'purchase' | 'return' | 'sale' | 'to-inventory'`
- `needsReview?: boolean` - Show "Needs Review" badge
- `reimbursementType?: 'owed-to-client' | 'owed-to-company'`
- `purchasedBy?: string` - Who made the purchase
- `hasEmailReceipt?: boolean` - Show receipt badge
- `status?: 'pending' | 'completed' | 'canceled'`

### Interaction Props
- `selected?: boolean` - Selection state
- `defaultSelected?: boolean` - Default selection state
- `onSelectedChange?: (selected: boolean) => void` - Selection callback
- `bookmarked?: boolean` - Bookmark state
- `onBookmarkPress?: () => void` - Bookmark callback
- `onMenuPress?: () => void` - Menu button callback
- `menuItems?: AnchoredMenuItem[]` - Menu items array
- `onPress?: () => void` - Card press callback
- `style?: StyleProp<ViewStyle>` - Additional styles

## Testing

### What to Test
1. **Visual**: All data displays correctly, badges render properly
2. **Interaction**: Selection, navigation, menu actions work
3. **Theming**: Light and dark modes display correctly
4. **Accessibility**: Screen readers work, touch targets adequate
5. **Performance**: List scrolls smoothly

### Test Data Scenarios
- Transactions with all badges
- Transactions with no badges
- Long source names
- Long notes
- Zero, negative, and large amounts
- Missing dates
- Canonical inventory transactions

See the Integration Guide for a complete testing checklist.

## Design Rationale

### Why This Design?

1. **Consistency**: Matches ItemCard structure users are familiar with
2. **Feature Parity**: Includes all legacy web app features
3. **Extensibility**: Easy to add new badges or features
4. **Maintainability**: Centralized component vs. inline rendering
5. **Accessibility**: Proper semantic structure and labels
6. **Theming**: Fully integrated with app theme system

### Design Trade-offs

**Kept from ItemCard:**
- Header structure (selector, spacer, actions)
- Card styling (borders, shadows, radius)
- Theming integration
- Interaction patterns

**Adapted from Legacy Web:**
- Transaction-specific badges
- Amount prominence
- Date/payment metadata
- Notes display

**Improved:**
- Better visual hierarchy
- More consistent design
- Enhanced accessibility
- Touch-optimized

## Future Enhancements

Potential improvements identified:

1. **Attachment Indicators**: Show icon for transactions with attachments
2. **Item Count Badge**: Show number of linked items
3. **Swipe Actions**: Swipe to edit/delete
4. **Compact Mode**: Denser variant for large lists
5. **Custom Badge Colors**: More flexibility in badge styling
6. **Canonical Transaction Indicator**: Special badge for system transactions
7. **Quick Actions**: Long-press for bulk operations
8. **Inline Editing**: Edit notes or categories inline

## Support and Questions

### Common Questions

**Q: Why not just update the inline rendering?**
A: A dedicated component provides better maintainability, reusability, and testing capabilities.

**Q: Does this break existing functionality?**
A: No, it's a drop-in replacement that preserves all existing features.

**Q: What about performance?**
A: The component is optimized with proper memoization and should perform as well or better than inline rendering.

**Q: Can I customize the colors?**
A: Yes, use the `updateCategoryColorMap` utility to add custom colors.

### Need Help?

1. Check the Integration Guide for step-by-step instructions
2. Review the Visual Comparison for design clarifications
3. See the Design Spec for detailed prop documentation
4. Check Common Issues section in Integration Guide

## File Locations Summary

```
/src/
  components/
    TransactionCard.tsx          ← Main component
  utils/
    budgetCategoryColors.ts      ← Color utilities

/docs/specs/
  TransactionCard_README.md                  ← This file
  TransactionCard_Design.md                  ← Design specification
  TransactionCard_Visual_Comparison.md       ← Visual alignment guide
  TransactionCard_Integration_Guide.md       ← Integration instructions
```

## Version History

### v1.0.0 - Initial Release
- Complete TransactionCard component
- Budget category color utilities
- Full documentation suite
- Ready for integration into SharedTransactionsList

## License and Credits

- **Design Inspiration**: Legacy web app at `/Users/benjaminmackenzie/Dev/ledger`
- **Visual Alignment**: ItemCard component
- **Created**: 2026-02-06
- **Status**: Ready for integration

---

**Ready to integrate?** Start with the [Integration Guide](./TransactionCard_Integration_Guide.md)!
