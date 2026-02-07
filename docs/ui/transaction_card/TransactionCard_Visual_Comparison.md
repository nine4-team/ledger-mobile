# TransactionCard Visual Comparison

## Design Evolution

This document illustrates how the new TransactionCard combines design elements from both the ItemCard component and the legacy web application.

## Component Anatomy Comparison

### ItemCard Structure (Reference)

```
┌──────────────────────────────────────────────────────────┐
│ HEADER (with bottom border)                             │
│ [●] Selector  <spacer>  [1/2] [Status] [★] [⋮]         │
├──────────────────────────────────────────────────────────┤
│ CONTENT                                                  │
│                                                          │
│ Item Name / Description                                 │
│                                                          │
│ ┌────────┐  Price: $125.00                             │
│ │  IMG   │  Source: Amazon                             │
│ │ 108px  │  SKU: ABC-123                               │
│ │        │  Location: Living Room                      │
│ └────────┘                                              │
└──────────────────────────────────────────────────────────┘
```

### TransactionCard Structure (New Design)

```
┌──────────────────────────────────────────────────────────┐
│ HEADER (with bottom border)                             │
│ [●] Selector  <spacer>  [★] [⋮]                         │
├──────────────────────────────────────────────────────────┤
│ CONTENT                                                  │
│                                                          │
│ Source/Vendor Name                          $125.00     │
│ Client • Jan 15, 2024                                   │
│ Optional notes displayed here in italics...             │
│                                                          │
│ [Design Fee] [Purchase] [Needs Review] [Receipt]       │
└──────────────────────────────────────────────────────────┘
```

### Legacy Web App Transaction Display

```
┌──────────────────────────────────────────────────────────┐
│ Wayfair                                                  │
│ ─────────────────────────────────────────────────────── │
│ $125.00 • Client • Jan 15, 2024                         │
│                                                          │
│ Optional notes shown here...                            │
│                                                          │
│ [Design Fee] [Purchase] [Needs Review]                 │
└──────────────────────────────────────────────────────────┘
```

## Shared Design Patterns

### 1. Header Section
Both ItemCard and TransactionCard share:
- Selector circle on the left
- Flexible spacer in the middle
- Action buttons on the right (bookmark, menu)
- Bottom border separating header from content
- 12px vertical padding
- Same gap spacing (12px)

### 2. Card Container
Both use identical:
- Border radius: 16px
- Border width: 1px (from `CARD_BORDER_WIDTH`)
- Padding: from `CARD_PADDING` constant
- Shadow: opacity 0.05, radius 6
- Elevation: 2 (Android)
- Border color logic (primary when selected, border.primary otherwise)

### 3. Theming
Both leverage `useUIKitTheme` for:
- Background colors
- Text colors (primary, secondary)
- Border colors
- Shadow colors
- Button icon colors
- Primary accent color

### 4. Interaction States
Both implement:
- Pressed state (opacity: 0.92)
- Selected state (border color change)
- Disabled states where applicable
- Proper accessibility roles and labels

## Key Differences

### ItemCard Unique Features
1. **Thumbnail Image**: 108x108px image/placeholder with camera icon
2. **Index Label**: Shows item position in grouped sets (e.g., "1/2")
3. **Status Label**: Generic status pill in header
4. **Metadata Format**: Labeled metadata (Source:, SKU:, Location:)
5. **Price in Metadata**: Price shown alongside other metadata

### TransactionCard Unique Features
1. **Amount in Top Row**: Prominently displayed, right-aligned
2. **Date Formatting**: Formatted transaction date in metadata row
3. **Multiple Badge Types**: Type, status, reimbursement, receipt badges
4. **Notes Display**: Italicized notes below details
5. **No Thumbnail**: Transactions don't have images
6. **Purchased By**: Shows who made the purchase (Client/Business)

## Layout Comparison

### Top Section (Name/Source + Key Info)

**ItemCard:**
```
┌────────────────────────────────┐
│ Item Name                      │
│ (3 lines max)                  │
└────────────────────────────────┘
```

**TransactionCard:**
```
┌──────────────────────────────────┐
│ Source Name         $125.00      │
│ (2 lines max)  (right-aligned)   │
└──────────────────────────────────┘
```

**Legacy Web:**
```
┌────────────────────────────────┐
│ Wayfair                        │
│ ──────────────────────────────│
│ $125.00 • Client • Jan 15      │
└────────────────────────────────┘
```

### Metadata Section

**ItemCard:**
```
Price: $125.00
Source: Amazon
SKU: ABC-123
Location: Living Room
```

**TransactionCard:**
```
Client • Jan 15, 2024
Optional notes in italics...
```

**Legacy Web:**
```
$125.00 • Client • Jan 15, 2024
Optional notes...
```

### Badges Section

**ItemCard:**
```
Header: [1/2] [Status]
```

**TransactionCard:**
```
Content bottom:
[Design Fee] [Purchase] [Needs Review] [Receipt]
```

**Legacy Web:**
```
Bottom:
[Design Fee] [Purchase] [Needs Review]
```

## Color Scheme Alignment

### Badge Colors (TransactionCard follows Legacy Web)

| Badge Type | Color | Hex |
|------------|-------|-----|
| Purchase | Green | `#10b981` |
| Sale | Blue | `#3b82f6` |
| Return | Red | `#ef4444` |
| To Inventory | Primary | Theme |
| Needs Review | Red | `#dc2626` |
| Reimbursement | Orange | `#d97706` |
| Design Fee | Amber | `#f59e0b` |
| Receipt | Primary | Theme |

### ItemCard Badge Colors

| Badge Type | Color | Hex |
|------------|-------|-----|
| Index Label | Primary | Theme + opacity |
| Status Label | Primary | Theme + opacity |

## Typography Alignment

### ItemCard
- **Name**: 15px, weight 600, line height 20
- **Price**: 13px, weight 600 (in styled pill)
- **Meta Labels**: 13px, weight 700 (Source:, SKU:)
- **Meta Values**: 13px, weight 500, line height 18

### TransactionCard
- **Source**: 16px, weight 600, line height 22
- **Amount**: 16px, weight 700, line height 22
- **Metadata**: 13px, weight 500, line height 18
- **Notes**: 13px, weight 400, line height 18, italic
- **Badges**: 12px, weight 600

### Alignment Notes
- TransactionCard uses slightly larger text (16px vs 15px) for source/amount to match their importance
- Both use 13px for metadata
- Badge text is consistent at 12px
- Line heights maintain proper readability

## Spacing Consistency

Both components use:
- **Card Padding**: `CARD_PADDING` constant (16px)
- **Header Padding**: 12px vertical, CARD_PADDING horizontal
- **Content Gap**: 12px between sections
- **Badge Gap**: 8px between badges
- **Icon Button Hit Slop**: 8px
- **Selector Hit Slop**: 13px

## Responsive Behavior

### Text Truncation
**ItemCard:**
- Name: 3 lines max
- Meta text: 1-2 lines max
- Badge text: 1 line max

**TransactionCard:**
- Source: 2 lines max
- Notes: 2 lines max
- Badge text: 1 line max
- Amount: 1 line max (flexShrink: 0)

### Badge Wrapping
Both components allow badges to wrap to multiple lines if needed, using `flexWrap: 'wrap'`.

## Accessibility Parity

Both components provide:
- ✅ Proper `accessibilityRole` for all interactive elements
- ✅ Descriptive `accessibilityLabel` values
- ✅ `accessibilityState` for checkboxes
- ✅ Adequate `hitSlop` for touch targets
- ✅ Support for screen readers
- ✅ Semantic structure

## Summary of Design Decisions

### What We Kept from ItemCard
1. Header structure with selector and actions
2. Card styling (borders, shadows, radius)
3. Theming system integration
4. Interaction patterns (selection, menu, press)
5. Spacing constants and layout principles

### What We Adapted from Legacy Web
1. Transaction-specific badge types and colors
2. Amount display prominence (top-right position)
3. Date and payment method metadata
4. Notes display format
5. Status indicators (needs review, reimbursement)

### What We Improved
1. **Better Visual Hierarchy**: Amount is more prominent than in legacy
2. **Consistent Card Design**: Matches app's modern design language
3. **Flexible Badge System**: Can show multiple status indicators
4. **Theme Support**: Fully integrated with app theming
5. **Accessibility**: Comprehensive accessibility features
6. **Touch Optimization**: Proper hit targets and press states

## Implementation Checklist

When implementing TransactionCard in your app:

- [x] Component created with full prop interface
- [x] Visual styling aligned with ItemCard
- [x] All legacy web features included
- [x] Theming fully integrated
- [x] Accessibility implemented
- [ ] Integrate into SharedTransactionsList
- [ ] Add budget category color mapping
- [ ] Test with real transaction data
- [ ] Test selection behavior
- [ ] Test menu interactions
- [ ] Verify theming in light/dark modes
- [ ] Test badge wrapping with many badges
- [ ] Update unit tests
- [ ] Update integration tests
- [ ] Document any edge cases found
