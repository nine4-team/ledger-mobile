# Issue: Transaction Audit Shows Wrong Progress Format

**Status:** Resolved
**Opened:** 2026-02-10
**Resolved:** 2026-02-10

## Context
- **Symptom:** Transaction audit progress display shows percentage-based status message ("85% — Nearly Complete") instead of the proper format used in the web app: "$x/$y" on the right side of status line, "N items" on left below bar, "$x remaining" on right below bar
- **Affected area:** [app/transactions/[id]/sections/AuditSection.tsx](app/transactions/[id]/sections/AuditSection.tsx)
- **Severity:** Cosmetic - functionality works but UX doesn't match web app design
- **Reference:** Screenshot shows web app format with proper labels
- **Environment:** React Native mobile app

## Research

### Web App Implementation (Reference)
**File:** `/Users/benjaminmackenzie/Dev/ledger/src/components/ui/TransactionCompletenessPanel.tsx`

The web app displays transaction audit progress with this structure (lines 77-101):

```tsx
{/* Status line with icon + label on left, $x/$y on right */}
<div className="flex items-center justify-between mb-2">
  <div className="flex items-center gap-2">
    {getStatusIcon(completeness.completenessStatus)}  // CheckCircle2 | AlertTriangle | XCircle
    <span className="text-base font-medium text-gray-900">
      {getStatusLabel(completeness.completenessStatus)}  // "Complete" | "Needs Review" | "Incomplete"
    </span>
  </div>
  <span className="text-sm text-gray-500">
    {formatCurrency(completeness.itemsNetTotal.toString())} /{' '}
    {formatCurrency(completeness.transactionSubtotal.toString())}  // "$0.00 / $25.00"
  </span>
</div>

{/* Progress bar */}
<div className="w-full bg-gray-200 rounded-full h-3 mb-1">
  <div className={`h-3 rounded-full ${getStatusColor()}`} style={{ width: `${progressPercentage}%` }} />
</div>

{/* Info below bar: "N items" on left, "$x remaining" on right */}
<div className="flex items-center justify-between text-xs text-gray-500 mt-1">
  <span>{completeness.itemsCount} items</span>
  <span>{remainingLabel}</span>  // "$25.00 remaining" or "Over by $5.00"
</div>
```

**Key Format Rules:**
1. **Above bar (right side):** `$x / $y` showing items total vs transaction subtotal
2. **Below bar (left):** `N items` count
3. **Below bar (right):** `$x remaining` or `Over by $x`
4. **NO percentage shown anywhere** - just status label ("Complete", "Needs Review", "Incomplete")

### Mobile App Current Implementation
**File:** [app/transactions/[id]/sections/AuditSection.tsx](app/transactions/[id]/sections/AuditSection.tsx)

Current structure (lines 73-117):

```tsx
{/* Status icon + label - CORRECT ✓ */}
<View style={{ flexDirection: 'row', alignItems: 'center', marginBottom: 8 }}>
  {StatusIcon && <StatusIcon size={20} color={progressColors.text} />}
  <AppText variant="title" style={{ color: progressColors.text, marginLeft: 8 }}>
    {statusLabel}  // "Complete" | "Nearly Complete" | "Incomplete" | "Over"
  </AppText>
</View>

{/* Progress bar - CORRECT ✓ */}
<ProgressBar
  percentage={percentage}
  color={progressColors.bar}
  overflowPercentage={overflowPercentage}
  overflowColor={overflowColors?.bar}
</ProgressBar>

{/* WRONG: Shows two-column totals comparison instead of "$x/$y" on right */}
<View style={{ flexDirection: 'row', justifyContent: 'space-between', marginTop: 8 }}>
  <View style={{ flex: 1 }}>
    <AppText variant="caption" style={{ color: theme.colors.textSecondary }}>Items Total</AppText>
    <AppText variant="body" style={{ color: theme.colors.text }}>
      {formatCurrency(completeness.itemsNetTotalCents / 100)}
    </AppText>
  </View>
  <View style={{ flex: 1, alignItems: 'flex-end' }}>
    <AppText variant="caption" style={{ color: theme.colors.textSecondary }}>Transaction Subtotal</AppText>
    <AppText variant="body" style={{ color: theme.colors.text }}>
      {formatCurrency(completeness.transactionSubtotalCents / 100)}
    </AppText>
  </View>
</View>

{/* WRONG: Status message with percentage instead of "N items" / "$x remaining" */}
<AppText variant="body" style={{ color: progressColors.text, marginTop: 12 }}>
  {statusMessage}  // "85% — Nearly Complete"
</AppText>

{/* Missing price warning - CORRECT ✓ */}
{completeness.itemsMissingPriceCount > 0 && (
  <AppText variant="caption" style={{ color: theme.colors.textSecondary, marginTop: 8 }}>
    ⚠ {completeness.itemsMissingPriceCount} item(s) missing purchase price
  </AppText>
)}
```

### Data Available from `TransactionCompleteness`
**File:** [src/utils/transactionCompleteness.ts](src/utils/transactionCompleteness.ts)

The completeness calculation provides all needed values:
- `itemsNetTotalCents`: Sum of item prices (numerator)
- `transactionSubtotalCents`: Transaction subtotal (denominator)
- `itemsCount`: Number of linked items
- `status`: 'complete' | 'near' | 'incomplete' | 'over'
- `itemsMissingPriceCount`: Items without prices

Missing from current data: "remaining" amount calculation. Web app computes it as:
```typescript
const remainingDollars = transactionSubtotal - itemsNetTotal
const remainingLabel = remainingDollars >= 0
  ? `${formatCurrency(remainingDollars)} remaining`
  : `Over by ${formatCurrency(Math.abs(remainingDollars))}`
```

## Investigation Log

### H1: Mobile implementation was built before web app format was finalized
- **Rationale:** The mobile app shows a more verbose two-column totals comparison and percentage-based status message, suggesting it was implemented with a different design spec than the final web app
- **Experiment:** Review git history for AuditSection.tsx and TransactionCompletenessPanel.tsx to see which was implemented first and if the designs diverged
- **Evidence:**
  - Web app (reference implementation) uses compact `$x/$y` format on status line, `N items` / `$x remaining` below bar
  - Mobile app uses expanded two-column layout + percentage message
  - Both use same status labels ("Complete", "Incomplete", etc.) suggesting shared design intent
- **Verdict:** Confirmed - implementations diverged. Mobile needs to adopt web app's finalized format.

### H2: Missing "$x remaining" calculation in mobile completeness utils
- **Rationale:** The `TransactionCompleteness` type provides raw totals but not the computed "remaining" amount shown in web app
- **Experiment:** Check if mobile version of transactionCompleteness.ts includes remaining calculation
- **Evidence:**
  - Web app calculates: `remainingDollars = transactionSubtotal - itemsNetTotal` (line 64)
  - Mobile `TransactionCompleteness` interface has `itemsNetTotalCents` and `transactionSubtotalCents` but no `remainingCents` field
  - Mobile would need to compute this in the component or add to the completeness calculation
- **Verdict:** Confirmed - mobile must calculate remaining amount locally or add it to the completeness util

### H3: Status message generation produces percentage text that shouldn't be shown
- **Rationale:** The `statusMessage` variable at [AuditSection.tsx:46-56](app/transactions/[id]/sections/AuditSection.tsx#L46-L56) generates percentage-based text like "85% — Nearly Complete"
- **Experiment:** Review how statusMessage is computed and where it's used
- **Evidence:**
  ```typescript
  const statusMessage =
    percentage > 100
      ? `Over by ${Math.round(percentage - 100)}%`
      : percentage === 100
      ? 'Transaction fully itemized'
      : percentage >= 90
      ? `${Math.round(percentage)}% — Nearly Complete`
      : `${Math.round(percentage)}% itemized`
  ```
  This entire message format is wrong for the target design. Web app doesn't show percentage anywhere.
- **Verdict:** Confirmed - statusMessage variable should be removed or repurposed

## Conclusion

The mobile transaction audit display was implemented with a different design than the final web app format. Three specific changes are needed:

1. **Remove two-column totals comparison** (lines 87-105) and replace with compact `$x/$y` format on the right side of the status line (above the progress bar)

2. **Remove percentage status message** (lines 108-110) and replace with two-line layout below the bar:
   - Left: `{itemsCount} items`
   - Right: `${remaining} remaining` or `Over by ${Math.abs(remaining)}`

3. **Calculate remaining amount** either in the component or in the completeness util:
   ```typescript
   const remainingCents = completeness.transactionSubtotalCents - completeness.itemsNetTotalCents
   const remainingLabel = remainingCents >= 0
     ? `${formatCurrency(remainingCents / 100)} remaining`
     : `Over by ${formatCurrency(Math.abs(remainingCents) / 100)}`
   ```

The status icon/label, progress bar, and missing price warning are already correct and match the web app.

## Resolution
- **Fix:** Implemented (2026-02-10)
- **Files changed:**
  - [app/transactions/[id]/sections/AuditSection.tsx](app/transactions/[id]/sections/AuditSection.tsx) - Updated layout to match web format
- **Changes made:**
  1. Added status label + icon row above progress bar with "$x/$y" format on the right
  2. Removed two-column totals comparison (lines 87-105)
  3. Replaced percentage status message with below-bar layout showing "N items" on left and "$x remaining" on right
  4. Added `remainingCents` calculation to compute the remaining amount
  5. Added status icons using `MaterialIcons` from `@expo/vector-icons`:
     - `check-circle` for complete/nearly-complete
     - `error-outline` for incomplete
     - `cancel` for over-itemized
- **Commit:** _pending user verification_
- **Verified by user:** Pending

## Lessons Learned
- Mobile and web implementations can diverge when designs are finalized at different times — always cross-reference the latest web app implementation for UI consistency
- The web app's compact format ($x/$y, N items, $x remaining) is more space-efficient and clearer than the verbose two-column layout
- Status icons provide visual clarity: CheckCircle for complete/near-complete, AlertCircle for incomplete, XCircle for over-itemized
