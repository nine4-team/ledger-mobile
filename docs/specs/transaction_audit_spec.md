# Transaction Audit Specification

## Overview
The Transaction Audit section provides completeness tracking and variance analysis for transactions with itemization enabled. This feature helps users understand how well their itemized transaction items account for the total transaction amount.

## Reference Implementation
- **Legacy web app**: `/Users/benjaminmackenzie/Dev/ledger/src/components/ui/TransactionAudit.tsx`
- **Legacy usage**: `/Users/benjaminmackenzie/Dev/ledger/src/pages/TransactionDetail.tsx` (line 41)
- **Legacy completeness panel**: `/Users/benjaminmackenzie/Dev/ledger/src/components/ui/TransactionCompletenessPanel.tsx`
- **Legacy missing price list**: `/Users/benjaminmackenzie/Dev/ledger/src/components/ui/MissingPriceList.tsx`

## Requirements

### 1. Completeness Tracking
**Display Conditions**: Only show when itemization is enabled for the transaction's budget category.

**Metrics to Calculate and Display**:
- **Items Subtotal**: Sum of all linked item purchase prices (`sum(item.purchasePriceCents)`)
- **Transaction Subtotal**: From `transaction.subtotalCents`
- **Variance Amount**: `transaction.subtotalCents - itemsSubtotal`
- **Variance Percentage**: `(variance / transaction.subtotalCents) * 100`
- **Completeness Percentage**: `(itemsSubtotal / transaction.subtotalCents) * 100`

**Formulas**:
```typescript
const itemsSubtotal = linkedItems.reduce((sum, item) => {
  return sum + (item.purchasePriceCents ?? 0);
}, 0);

const transactionSubtotal = transaction.subtotalCents ?? 0;
const variance = transactionSubtotal - itemsSubtotal;
const variancePct = transactionSubtotal !== 0
  ? (variance / transactionSubtotal) * 100
  : 0;
const completenessPct = transactionSubtotal !== 0
  ? (itemsSubtotal / transactionSubtotal) * 100
  : 0;
```

### 2. Progress Indicators

**Visual Progress Bar**:
- Show horizontal progress bar representing completeness percentage
- Fill color based on completeness tier (see below)
- Display percentage text overlay

**Completeness Tiers & Color Coding**:
- **Complete** (95-100%): Green color (`theme.colors.success` or `#10B981`)
  - Message: "✓ Transaction is complete"
- **Near Complete** (80-94%): Yellow/Amber color (`theme.colors.warning` or `#F59E0B`)
  - Message: "⚠ Almost complete"
- **Incomplete** (<80%): Red color (`theme.colors.error` or `#EF4444`)
  - Message: "✗ Needs more items"
- **Over Budget** (>100%): Red color with special icon
  - Message: "⚠ Items exceed transaction total"

**Display Format**:
```
Progress Bar: [████████░░] 85%
Status: ⚠ Almost complete
Items: $850.00 / $1,000.00 (Transaction total)
Remaining: $150.00
```

### 3. Missing Price List

**Purpose**: Identify items that don't have purchase prices set, preventing accurate completeness calculation.

**Display**:
- Collapsible section: "Missing Prices (X items)"
- Table format:
  - Column 1: Item name
  - Column 2: SKU (if available)
  - Column 3: Action button ("Edit item")
- Each item links to item detail page for editing
- Show warning icon if any items have missing prices

**Empty State**: Hide section if all items have prices.

### 4. Tax Warnings

**Show warnings for**:
- **No tax rate set**: When `transaction.taxRatePct` is null/undefined and no subtotal provided
  - Message: "Set tax rate for accurate calculations"
- **Tax variance**: When calculated tax differs significantly from recorded tax
  - Formula: `calculatedTax = subtotal * (taxRatePct / 100)`
  - Show warning if `|calculatedTax - (amountCents - subtotalCents)| > 1` cent
  - Message: "Tax amount doesn't match tax rate (Expected: $X.XX, Actual: $Y.YY)"
- **Items missing tax info**: When items don't have `taxAmountPurchasePrice` set
  - Count and display: "X items missing tax information"

### 5. Variance Details (Expandable Section)

**Display When**: Variance exists (completeness ≠ 100%)

**Contents**:
- **Under Budget**: Show missing amount and suggest adding more items
- **Over Budget**: Show excess amount and list items that may need price adjustment
- **Per-Item Contribution**: Optional advanced view showing each item's contribution to variance
- **Average Item Price**: Useful for identifying outliers
  - Formula: `avgPrice = itemsSubtotal / linkedItems.length`
  - Highlight items significantly above or below average

### 6. Collapsible Sections

**Collapsed State** (Default):
- Show completeness percentage
- Show status indicator (✓ / ⚠ / ✗)
- Show items total vs transaction total
- Show "View details" button

**Expanded State**:
- All metrics visible
- Progress bar
- Missing price list
- Tax warnings
- Variance details

## Data Requirements

### Transaction Fields
```typescript
type TransactionAuditData = {
  subtotalCents: number;           // Pre-tax transaction total
  taxRatePct?: number;             // Tax rate percentage
  amountCents: number;             // Total including tax
  budgetCategoryId: string;        // Links to budget category for itemization check
};
```

### Item Fields Required
```typescript
type ItemAuditData = {
  id: string;
  name?: string;
  sku?: string;
  purchasePriceCents?: number;     // Required for completeness calculation
  taxAmountPurchasePrice?: number; // Optional for tax accuracy
};
```

### Budget Category Metadata
```typescript
type BudgetCategoryMetadata = {
  itemizationEnabled?: boolean;    // Controls whether audit is shown
};
```

## UI Components

### Main Component Structure
```tsx
<TitledCard title="Transaction Audit">
  {itemizationEnabled ? (
    <>
      <AuditSummary
        completenessPct={completenessPct}
        itemsTotal={itemsSubtotal}
        transactionTotal={transactionSubtotal}
        status={status}
      />

      {expanded && (
        <>
          <ProgressBar
            percentage={completenessPct}
            color={statusColor}
          />

          {missingPriceItems.length > 0 && (
            <MissingPriceList items={missingPriceItems} />
          )}

          {taxWarnings.length > 0 && (
            <TaxWarnings warnings={taxWarnings} />
          )}

          {variance !== 0 && (
            <VarianceDetails
              variance={variance}
              variancePct={variancePct}
              items={linkedItems}
            />
          )}
        </>
      )}
    </>
  ) : (
    <AppText variant="caption">
      Itemization is not enabled for this transaction's category.
    </AppText>
  )}
</TitledCard>
```

### Reusable Sub-Components
1. **AuditSummary**: Compact summary view
2. **ProgressBar**: Visual progress indicator
3. **MissingPriceList**: Table of items without prices
4. **TaxWarnings**: Warning messages for tax issues
5. **VarianceDetails**: Detailed variance analysis

## Implementation Priority

**Phase 1** (MVP):
- Completeness calculation
- Basic progress indicator
- Status message (Complete/Incomplete)
- Items total vs transaction total display

**Phase 2** (Enhanced):
- Progress bar with color coding
- Missing price list
- Collapsible sections
- Link to item detail for editing

**Phase 3** (Advanced):
- Tax warnings
- Variance details
- Per-item contribution analysis
- Average price calculations

## Edge Cases & Validation

### Handle These Scenarios:
1. **Zero transaction subtotal**: Avoid division by zero, show "N/A" for percentages
2. **No items linked**: Show "0%" completeness, suggest adding items
3. **Negative prices**: Flag as data error, exclude from calculations
4. **Over 100% completeness**: Show as "Over budget" with different styling
5. **Offline mode**: Calculate from cached data, show sync indicator
6. **Large item count**: Consider pagination or virtualization for missing price list

### Data Validation:
- Ensure `subtotalCents` is a positive number
- Validate `taxRatePct` is between 0 and 100
- Check `purchasePriceCents` is non-negative
- Handle null/undefined gracefully

## Testing Requirements

### Test Scenarios:
1. **Zero items linked**: Completeness = 0%
2. **Partial coverage (50%)**: Yellow status, variance shown
3. **Complete coverage (100%)**: Green status, no variance
4. **Over-coverage (>100%)**: Red status, over budget warning
5. **Items without prices**: Missing price list appears
6. **Tax rate mismatch**: Tax warning shown
7. **Itemization disabled**: Component not shown or shows disabled message
8. **Negative variance**: Correctly identifies as over budget
9. **Very small variance (<$0.05)**: Rounds and treats as complete
10. **Empty transaction subtotal**: Graceful handling, show N/A

### Performance Testing:
- Test with 0, 1, 10, 50, 100+ linked items
- Measure render time for expanded view
- Ensure calculations don't block UI thread

## Accessibility

- Progress bar has proper ARIA labels
- Status icons have text alternatives
- Color is not the only indicator (use icons + text)
- Focus management for collapsible sections
- Screen reader announces status changes

## Related Files

### Implementation Files (New):
- `src/components/TransactionAudit.tsx` - Main audit component
- `src/components/AuditSummary.tsx` - Summary view
- `src/components/MissingPriceList.tsx` - Missing prices table

### Modified Files:
- `app/transactions/[id].tsx` - Integration point
- Replace placeholder with actual component

### Reference Files (Legacy):
- `/Users/benjaminmackenzie/Dev/ledger/src/components/ui/TransactionAudit.tsx`
- `/Users/benjaminmackenzie/Dev/ledger/src/components/ui/TransactionCompletenessPanel.tsx`
- `/Users/benjaminmackenzie/Dev/ledger/src/components/ui/MissingPriceList.tsx`

### Data Services:
- `src/data/transactionsService.ts` - Transaction data
- `src/data/itemsService.ts` - Item data
- `src/data/budgetCategoriesService.ts` - Itemization check

## Design Notes

### Mobile Optimization:
- Compact summary view by default
- Expandable for details
- Touch-friendly buttons (min 44px)
- Readable on small screens

### Theme Support:
- Use theme colors for status indicators
- Support both light and dark modes
- Maintain sufficient contrast ratios

### Performance:
- Memoize calculations
- Avoid re-calculating on every render
- Consider useMemo for complex computations
- Cache results based on transaction and items data

## Future Enhancements (Out of Scope)

1. **Historical tracking**: Show completeness over time
2. **Bulk price assignment**: Set prices for multiple items at once
3. **Price suggestions**: Suggest prices based on similar items or transaction average
4. **Export audit report**: PDF or CSV export of audit details
5. **Notifications**: Alert when completeness drops below threshold
6. **Comparison**: Compare with similar past transactions
7. **Auto-reconciliation**: Automatically distribute remaining amount across items

## Notes

- Only display when itemization is enabled for the transaction's budget category
- Support offline mode - calculate from cached data
- Consider caching calculations for performance
- Respect user preferences for default expanded/collapsed state
- Integrate with existing theme and UI kit components
- Follow mobile-first design principles
- Maintain consistency with item detail and transaction list patterns
