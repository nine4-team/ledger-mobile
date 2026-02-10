---
work_package_id: WP06
title: Create DetailRow Component
lane: "doing"
dependencies: []
base_branch: main
base_commit: 1a15fd7b3fb801a7c4650f0e390183fed6dda4bb
created_at: '2026-02-10T03:45:43.914971+00:00'
subtasks:
- T026
- T027
- T028
- T029
phase: Phase 3 - Detail Row Extraction
assignee: ''
agent: "claude-sonnet"
shell_pid: "45302"
review_status: ''
reviewed_by: ''
history:
- timestamp: '2026-02-10T02:25:42Z'
  lane: planned
  agent: system
  shell_pid: ''
  action: Prompt generated via /spec-kitty.tasks
---

# Work Package Prompt: WP06 – Create DetailRow Component

## Important: Review Feedback Status

- **Has review feedback?**: Check the `review_status` field above.

---

## Review Feedback

*[This section is empty initially.]*

---

## Implementation Command

```bash
spec-kitty implement WP06
```

No dependencies — can run in parallel with WP04/WP05 since it touches different code (detail rows vs items management).

---

## Objectives & Success Criteria

- **Objective**: Extract the inline detail row rendering pattern (label-value pairs with dividers) into a shared `DetailRow` component and adopt it in transaction detail and item detail screens.
- Completes **User Story 5** (shared detail rows component).
- Completes **FR-006** (shared detail row component) and **SC-005** (composable shared components).

**Success Criteria**:
1. `src/components/DetailRow.tsx` renders a consistent key-value row with label, value, optional divider, and optional tap action
2. Transaction detail's DetailsSection uses `DetailRow` for all its detail rows
3. Item detail's Details card uses `DetailRow` for all its detail rows
4. Visual output is pixel-identical to current inline rendering
5. Duplicate `detailRow`, `valueText`, `divider` styles removed from adopting screens

## Context & Constraints

**Current inline pattern** (identical in both screens):
```tsx
<View style={styles.detailRow}>
  <AppText variant="caption" style={getTextSecondaryStyle(uiKitTheme)}>
    {label}
  </AppText>
  <AppText variant="body" style={[styles.valueText, textEmphasis.value]}>
    {value}
  </AppText>
</View>
<View style={[styles.divider, { borderTopColor: uiKitTheme.border.secondary }]} />
```

**Style definitions** (same in both):
```typescript
detailRow: {
  flexDirection: 'row',
  justifyContent: 'space-between',
  alignItems: 'flex-start',
  gap: 12,
},
valueText: {
  flexShrink: 1,
  textAlign: 'right',
},
divider: {
  borderTopWidth: 1,
},
```

**Reference: data-model.md** — Section 5 defines `DetailRowProps`.

---

## Subtasks & Detailed Guidance

### Subtask T026 – Create DetailRow component

**Purpose**: Build the shared presentational component that replaces inline detail row rendering.

**Steps**:
1. Create `src/components/DetailRow.tsx`:
   ```typescript
   import React from 'react';
   import { Pressable, View, StyleSheet } from 'react-native';
   import { AppText } from './AppText';
   import { useUIKitTheme } from '../theme/ThemeProvider';
   import { getTextSecondaryStyle, textEmphasis } from '../ui';

   export type DetailRowProps = {
     label: string;
     value: string | React.ReactNode;
     showDivider?: boolean;  // default: true
     onPress?: () => void;   // optional tap action (copy, navigate)
   };

   export function DetailRow({
     label,
     value,
     showDivider = true,
     onPress,
   }: DetailRowProps) {
     const uiKitTheme = useUIKitTheme();

     const content = (
       <>
         <View style={styles.row}>
           <AppText variant="caption" style={getTextSecondaryStyle(uiKitTheme)}>
             {label}
           </AppText>
           {typeof value === 'string' ? (
             <AppText variant="body" style={[styles.valueText, textEmphasis.value]}>
               {value}
             </AppText>
           ) : (
             <View style={styles.valueContainer}>{value}</View>
           )}
         </View>
         {showDivider && (
           <View style={[styles.divider, { borderTopColor: uiKitTheme.border.secondary }]} />
         )}
       </>
     );

     if (onPress) {
       return (
         <Pressable onPress={onPress} accessibilityRole="button">
           {content}
         </Pressable>
       );
     }

     return content;
   }

   const styles = StyleSheet.create({
     row: {
       flexDirection: 'row',
       justifyContent: 'space-between',
       alignItems: 'flex-start',
       gap: 12,
     },
     valueText: {
       flexShrink: 1,
       textAlign: 'right',
     },
     valueContainer: {
       flexShrink: 1,
       alignItems: 'flex-end',
     },
     divider: {
       borderTopWidth: 1,
     },
   });
   ```

2. **Key design choices**:
   - `value` accepts `string | React.ReactNode` for flexibility (some values may be colored, linked, or multi-line)
   - `showDivider` defaults to `true` — set to `false` on the last row in a group
   - `onPress` wraps the entire row in a `Pressable` for tap-to-copy or navigation use cases
   - Component is self-contained — it imports its own theme hook and styles
   - Uses the exact same styles as the current inline pattern for pixel-identical output

3. Export the component and type from the file

**Files**:
- `src/components/DetailRow.tsx` (new, ~65 lines)

**Notes**:
- The `textEmphasis.value` import provides the emphasis styling on value text. Verify this import path matches existing usage in item detail and transaction detail.
- If `textEmphasis` is defined locally in some screens, check if it can be imported from a shared location. If not, add a `valueStyle` prop as an escape hatch.

---

### Subtask T027 – Adopt DetailRow in transaction detail DetailsSection

**Purpose**: Replace the inline detail rows in transaction detail's DetailsSection with the shared component.

**Steps**:
1. Locate the DetailsSection component. It's likely in:
   - `app/transactions/[id]/sections/DetailsSection.tsx` (extracted section component)
   - Or inline in `app/transactions/[id]/index.tsx`

2. Import DetailRow:
   ```typescript
   import { DetailRow } from '../../../../src/components/DetailRow';
   // or adjust path based on file location
   ```

3. Replace inline rows. **Before**:
   ```tsx
   <View style={styles.detailRows}>
     <View style={styles.detailRow}>
       <AppText variant="caption" style={getTextSecondaryStyle(uiKitTheme)}>Source</AppText>
       <AppText variant="body" style={[styles.valueText, textEmphasis.value]}>
         {transaction.source?.trim() || '—'}
       </AppText>
     </View>
     <View style={[styles.divider, { borderTopColor: uiKitTheme.border.secondary }]} />
     <View style={styles.detailRow}>
       <AppText variant="caption" style={getTextSecondaryStyle(uiKitTheme)}>Date</AppText>
       <AppText variant="body" style={[styles.valueText, textEmphasis.value]}>
         {formatDate(transaction.transactionDate)}
       </AppText>
     </View>
     <View style={[styles.divider, { borderTopColor: uiKitTheme.border.secondary }]} />
     {/* ... more rows ... */}
   </View>
   ```

   **After**:
   ```tsx
   <View style={styles.detailRows}>
     <DetailRow label="Source" value={transaction.source?.trim() || '—'} />
     <DetailRow label="Date" value={formatDate(transaction.transactionDate)} />
     <DetailRow label="Amount" value={formatMoney(transaction.amountCents)} />
     <DetailRow label="Status" value={transaction.status?.trim() || '—'} />
     <DetailRow label="Budget category" value={budgetCategoryLabel} />
     <DetailRow label="Has receipt" value={hasReceiptLabel} />
     <DetailRow label="Vendor" value={transaction.vendor?.trim() || '—'} />
     <DetailRow label="Notes" value={transaction.notes?.trim() || '—'} showDivider={false} />
   </View>
   ```

4. The last row sets `showDivider={false}` to avoid a trailing divider

5. Verify the transaction detail DetailsSection has the exact same fields. Read the actual file to confirm the rows. The research mentions: source, date, amount, status, budget category, has receipt, vendor.

**Files**:
- `app/transactions/[id]/sections/DetailsSection.tsx` (or wherever the DetailsSection is defined) (modify)

**Notes**:
- Transaction detail may also have a TaxesSection with similar inline rows. If so, adopt DetailRow there too.
- Preserve the `detailRows` container style (`gap: 12`) — DetailRow only handles individual rows.

---

### Subtask T028 – Adopt DetailRow in item detail Details card

**Purpose**: Replace the inline detail rows in item detail's TitledCard with the shared component.

**Steps**:
1. Open `app/items/[id]/index.tsx`
2. Import DetailRow:
   ```typescript
   import { DetailRow } from '../../../src/components/DetailRow';
   ```
3. Replace inline rows in the Details `TitledCard`. **Before** (lines 482-547):
   ```tsx
   <TitledCard title="Details">
     <View style={styles.detailRows}>
       <View style={styles.detailRow}>
         <AppText variant="caption" style={getTextSecondaryStyle(uiKitTheme)}>Source</AppText>
         <AppText variant="body" style={[styles.valueText, textEmphasis.value]}>
           {item.source?.trim() || '—'}
         </AppText>
       </View>
       <View style={[styles.divider, { borderTopColor: uiKitTheme.border.secondary }]} />
       {/* ... 6 more rows ... */}
     </View>
   </TitledCard>
   ```

   **After**:
   ```tsx
   <TitledCard title="Details">
     <View style={styles.detailRows}>
       <DetailRow label="Source" value={item.source?.trim() || '—'} />
       <DetailRow label="SKU" value={item.sku?.trim() || '—'} />
       <DetailRow label="Purchase price" value={formatMoney(item.purchasePriceCents)} />
       <DetailRow label="Project price" value={formatMoney(item.projectPriceCents)} />
       <DetailRow label="Market value" value={formatMoney(item.marketValueCents)} />
       <DetailRow label="Space" value={spaceLabel} />
       <DetailRow label="Budget category" value={budgetCategoryLabel} showDivider={false} />
     </View>
   </TitledCard>
   ```

4. Item detail has 7 rows: Source, SKU, Purchase price, Project price, Market value, Space, Budget category

**Files**:
- `app/items/[id]/index.tsx` (modify)

**Notes**:
- After WP03, this file uses SectionList. The Details section renders inside `renderItem` case `'details'`. The `TitledCard` wrapper may or may not be present depending on WP03's implementation. Adapt accordingly.
- If WP03 hasn't been completed yet (WP06 can run in parallel), the file still uses `AppScrollView` with inline `TitledCard`. The DetailRow adoption works either way.

---

### Subtask T029 – Clean up duplicate detail row styles

**Purpose**: Remove the now-unused inline detail row styles from screens that adopted DetailRow.

**Steps**:
1. In transaction detail DetailsSection: remove `detailRow`, `valueText`, `divider` from its local `StyleSheet.create`
2. In item detail: remove `detailRow`, `valueText`, `divider` from its `StyleSheet.create` (lines 649-660)
3. Keep `detailRows` container style (`gap: 12`) — this wraps the DetailRow components
4. Remove unused imports if any (e.g., `getTextSecondaryStyle`, `textEmphasis` if only used for detail rows)
5. Verify no other code in these files references the removed styles

**Files**:
- `app/transactions/[id]/sections/DetailsSection.tsx` (or equivalent) (modify)
- `app/items/[id]/index.tsx` (modify)

**Notes**:
- Only remove styles that are fully unused after DetailRow adoption. Some screens may use `divider` elsewhere — check before deleting.
- The `textEmphasis` import may be used by other parts of the screen (hero section, etc.) — only remove if truly unused.

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Visual differences | Low | Low | Pixel-identical styles from existing pattern |
| textEmphasis import path | Low | Low | Verify import path matches existing usage in both screens |
| Parallel WP conflict | Low | Low | WP06 touches detail rows, WP05 touches items — different code sections |

## Review Guidance

1. Compare detail rows on transaction detail before/after — should be visually identical
2. Compare detail rows on item detail before/after — should be visually identical
3. Verify last row in each group has no divider
4. Check dark mode — divider color and text colors are theme-aware
5. No duplicate style definitions remain in adopting screens
6. New DetailRow component is self-contained (no external style dependencies)

---

## Activity Log

- 2026-02-10T02:25:42Z – system – lane=planned – Prompt created.
- 2026-02-10T03:45:44Z – claude-sonnet – shell_pid=45302 – lane=doing – Assigned agent via workflow command
