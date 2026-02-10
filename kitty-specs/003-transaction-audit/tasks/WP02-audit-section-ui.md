---
work_package_id: WP02
title: Audit Section UI Component
lane: "doing"
dependencies: []
base_branch: main
base_commit: 8108d9ed73c948313f6a88efe2e36b109680862c
created_at: '2026-02-10T01:34:15.659254+00:00'
subtasks:
- T004
- T005
- T006
phase: Phase 1 - MVP
assignee: ''
agent: "claude-sonnet"
shell_pid: "98440"
review_status: ''
reviewed_by: ''
history:
- timestamp: '2026-02-09T15:00:00Z'
  lane: planned
  agent: system
  shell_pid: ''
  action: Prompt generated via /spec-kitty.tasks
---

# Work Package Prompt: WP02 – Audit Section UI Component

## ⚠️ IMPORTANT: Review Feedback Status

**Read this first if you are implementing this task!**

- **Has review feedback?**: Check the `review_status` field above. If it says `has_feedback`, scroll to the **Review Feedback** section immediately.
- **You must address all feedback** before your work is complete.
- **Mark as acknowledged**: When you understand the feedback and begin addressing it, update `review_status: acknowledged` in the frontmatter.

---

## Review Feedback

*[This section is empty initially. Reviewers will populate it if the work is returned from review.]*

---

## Objectives & Success Criteria

Replace the AuditSection placeholder with a fully functional UI component that displays transaction completeness metrics. Gate the section behind itemized budget categories and wire up the data flow from the parent page.

**Success criteria**:
- AuditSection shows completeness progress bar, totals comparison, status message, and missing price count
- Section only appears for transactions with `categoryType === 'itemized'` budget categories
- N/A state displayed when subtotal resolves to zero
- Colors are theme-aware (light and dark mode) using existing budget color system
- No additional data fetching — items passed as props from parent
- ProgressBar correctly shows overflow when items total exceeds subtotal by >100%

## Context & Constraints

**Reference documents**:
- Spec: `kitty-specs/003-transaction-audit/spec.md` (FR-001, FR-005, FR-006, FR-007, FR-008, FR-009, FR-010, FR-011, FR-012)
- Plan: `kitty-specs/003-transaction-audit/plan.md` (Key Implementation Details section)
- Research: `kitty-specs/002-transaction-audit/research.md` (D1, D3, D7, D8, D9)

**Dependencies**:
- **WP01 must be complete**: This WP imports `computeTransactionCompleteness` and `TransactionCompleteness` type from `src/utils/transactionCompleteness.ts`
- **Implementation command**: `spec-kitty implement WP02 --base WP01`

**Existing components to reuse**:

`ProgressBar` (`src/components/ProgressBar.tsx`):
```typescript
type ProgressBarProps = {
  percentage: number;        // 0-100
  color: string;             // fill color
  trackColor?: string;       // background track color
  height?: number;           // default 8
  overflowPercentage?: number; // beyond 100%
  overflowColor?: string;    // overflow segment color
  style?: ViewStyle;
};
```

`getBudgetProgressColor` (`src/utils/budgetColors.ts`):
```typescript
function getBudgetProgressColor(
  percentage: number,         // 0-100+
  isFeeCategory: boolean,    // true = inverted (green at high %)
  isDark?: boolean,           // default false
): { bar: string; text: string };

function getOverflowColor(isDark?: boolean): { bar: string; text: string };
```

**Critical color mapping note**: `getBudgetProgressColor` for standard categories maps high % → red (bad for budgets). For audit, high completeness = good. Pass `isFeeCategory = true` to get inverted semantics: high % → green, low % → red.

**Existing AuditSection placeholder** (`app/transactions/[id]/sections/AuditSection.tsx`):
```typescript
type AuditSectionProps = {
  transaction: Transaction;
};
export function AuditSection({ transaction }: AuditSectionProps)
```
Currently shows placeholder text in a Card. Replace entirely.

**Parent page integration points** (`app/transactions/[id]/index.tsx`):
- Line ~122: `collapsedSections` state has `audit: true` (default collapsed) — no changes needed
- Line ~191: `const linkedItems = useMemo(() => items.filter((item) => item.transactionId === id), [id, items]);`
- Line ~239: `const itemizationEnabled = selectedCategory?.metadata?.categoryType === 'itemized';`
- Lines ~264-278: `sections` memo — audit section is currently always pushed. Needs to be gated with `if (itemizationEnabled)`.
- Line ~1257: `case 'audit': return <AuditSection transaction={item} />;` — needs `items` prop added.

**Theme hooks** (from MEMORY.md):
- `useTheme()` → `theme.colors.text`, `theme.colors.textSecondary`, `theme.colors.background`, etc.
- `useThemeContext()` → `{ theme, uiKitTheme, resolvedColorScheme }` — use `resolvedColorScheme === 'dark'` for dark mode check
- `AppText` handles theme colors automatically via variant prop (`h1`, `h2`/`title`, `body`, `caption`)

## Subtasks & Detailed Guidance

### Subtask T004 – Replace AuditSection placeholder with real component

**Purpose**: Build the main audit UI. This is the largest subtask — it replaces the placeholder with a fully functional component displaying all Phase 1 MVP metrics.

**Steps**:

1. **Update the props interface**:
   ```typescript
   type AuditSectionProps = {
     transaction: Transaction;
     items: Pick<Item, 'purchasePriceCents'>[];
   };
   ```

2. **Add imports**:
   - `computeTransactionCompleteness`, `TransactionCompleteness` from `src/utils/transactionCompleteness`
   - `ProgressBar` from `src/components/ProgressBar`
   - `getBudgetProgressColor`, `getOverflowColor` from `src/utils/budgetColors`
   - `useThemeContext` from theme (for dark mode detection)
   - `useTheme` from theme (for color tokens)
   - `useMemo` from React
   - `Card`, `AppText` — already imported in placeholder

3. **Compute completeness with memoization**:
   ```typescript
   const { resolvedColorScheme } = useThemeContext();
   const isDark = resolvedColorScheme === 'dark';
   const theme = useTheme();

   const completeness = useMemo(
     () => computeTransactionCompleteness(transaction, items),
     [transaction, items],
   );
   ```

4. **Handle N/A state** (FR-009 — when `completeness` is `null`):
   Render a Card with a simple message like "Audit data unavailable" or "Unable to calculate completeness — transaction has no subtotal." Use `AppText` with `caption` variant and `textSecondary` color. Return early from the component after this render.

5. **Calculate ProgressBar props**:
   ```typescript
   const percentage = Math.min(completeness.completenessRatio * 100, 100);
   const overflowPercentage = completeness.completenessRatio > 1
     ? (completeness.completenessRatio - 1) * 100
     : undefined;

   const progressColors = getBudgetProgressColor(
     completeness.completenessRatio * 100,
     true,  // isFeeCategory = true → inverted: high % = green (good)
     isDark,
   );
   const overflowColors = overflowPercentage ? getOverflowColor(isDark) : undefined;
   ```

6. **Render the component layout** inside a `Card`:

   **a. ProgressBar** (FR-005):
   ```jsx
   <ProgressBar
     percentage={percentage}
     color={progressColors.bar}
     overflowPercentage={overflowPercentage}
     overflowColor={overflowColors?.bar}
   />
   ```

   **b. Totals comparison row** (FR-008):
   Show items total and transaction subtotal side by side. Format cents as dollars (e.g., `(cents / 100).toFixed(2)`). Use a row layout with `flexDirection: 'row'`, `justifyContent: 'space-between'`.
   ```
   Items Total              Transaction Subtotal
   $4,250.00                $5,000.00
   ```
   Use `AppText` with `body` variant for values, `caption` variant for labels. Consider a helper like:
   ```typescript
   const formatCents = (cents: number): string =>
     `$${(cents / 100).toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;
   ```

   **c. Status message** (FR-006):
   Display a human-readable status with the completeness percentage. Use `progressColors.text` for the status text color.
   - `complete`: "100% — Complete"
   - `near`: "{pct}% — Nearly Complete"
   - `incomplete`: "{pct}% — Incomplete"
   - `over`: "{pct}% — Over-itemized"

   Where `pct = Math.round(completeness.completenessRatio * 100)`.

   **d. Missing price count** (FR-007):
   Only show when `completeness.itemsMissingPriceCount > 0`:
   ```
   ⚠ {count} item(s) missing purchase price
   ```
   Use `AppText` with `caption` variant. Use the yellow/warning color from theme or budget colors.

7. **Styling**:
   - Use `StyleSheet.create` for styles
   - Vertical spacing between sections: `marginTop: 12` or similar
   - Card already provides padding — don't double-pad
   - No hardcoded colors — all from theme or budget color system

**Files**:
- `app/transactions/[id]/sections/AuditSection.tsx` (replace placeholder entirely)

**Notes**:
- Keep the existing `Card` wrapper pattern from the placeholder
- The `getTextSecondaryStyle` import from the placeholder can be removed if using `AppText` variants instead
- The component should be concise — the heavy lifting is in `computeTransactionCompleteness()`

---

### Subtask T005 – Gate audit section behind `itemizationEnabled`

**Purpose**: FR-001 requires the audit section only appears for itemized budget categories. Currently the `sections` memo always includes the audit entry. Gate it the same way the taxes section is gated.

**Steps**:

1. Open `app/transactions/[id]/index.tsx`
2. Find the `sections` memo (around line 264-278)
3. The audit section is currently pushed unconditionally at the end of the array:
   ```typescript
   result.push(
     {
       key: 'items',
       title: 'TRANSACTION ITEMS',
       data: collapsedSections.items ? [] : filteredAndSortedItems,
       badge: `${filteredAndSortedItems.length}`,
     },
     {
       key: 'audit',
       title: 'TRANSACTION AUDIT',
       data: [SECTION_HEADER_MARKER, ...(collapsedSections.audit ? [] : [transaction])],
     }
   );
   ```
4. Split the push so audit is conditional:
   ```typescript
   result.push({
     key: 'items',
     title: 'TRANSACTION ITEMS',
     data: collapsedSections.items ? [] : filteredAndSortedItems,
     badge: `${filteredAndSortedItems.length}`,
   });

   if (itemizationEnabled) {
     result.push({
       key: 'audit',
       title: 'TRANSACTION AUDIT',
       data: [SECTION_HEADER_MARKER, ...(collapsedSections.audit ? [] : [transaction])],
     });
   }
   ```
5. Verify that `itemizationEnabled` is already in the `useMemo` dependency array for `sections`. It should be — it's used for the taxes section gate. Confirm this.

**Files**: `app/transactions/[id]/index.tsx` (modify sections memo only)
**Parallel?**: Yes — modifies a different section of `index.tsx` than T006.

---

### Subtask T006 – Pass `linkedItems` to AuditSection

**Purpose**: The AuditSection needs item data to compute completeness. The parent page already has `linkedItems` available. Wire it through as a prop.

**Steps**:

1. Open `app/transactions/[id]/index.tsx`
2. Find the render switch case for audit (around line 1257):
   ```typescript
   case 'audit':
     return <AuditSection transaction={item} />;
   ```
3. Update to pass items:
   ```typescript
   case 'audit':
     return <AuditSection transaction={item} items={linkedItems} />;
   ```
4. Verify that `linkedItems` is accessible in the scope of the render function. It's defined as a `useMemo` at line ~191, so it should be available. If the render function is a `renderItem` callback, confirm `linkedItems` is in its closure.

**Files**: `app/transactions/[id]/index.tsx` (modify render switch only)
**Parallel?**: Yes — modifies a different section of `index.tsx` than T005.

**Notes**:
- `linkedItems` is typed as `Item[]` from `useMemo`. The AuditSection prop expects `Pick<Item, 'purchasePriceCents'>[]`. Since `Item` includes `purchasePriceCents`, this is type-compatible — no cast needed.

## Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| Color inversion confusion | Wrong colors (red = complete) | Pass `isFeeCategory = true` to `getBudgetProgressColor` — verify visually in light + dark mode |
| ProgressBar overflow rendering | Visual glitch when ratio > 2.0 | Cap `overflowPercentage` at a reasonable max (e.g., 100) if needed |
| `linkedItems` scope not accessible in render callback | Build error | Verify the render function's closure includes `linkedItems` memo |
| Missing `itemizationEnabled` in sections memo deps | Stale section list | Confirm it's already a dependency (used for taxes gate) |
| Currency formatting locale issues | Wrong format on non-US devices | Use explicit `'en-US'` locale in `toLocaleString` |

## Review Guidance

**Key checkpoints for reviewers**:
1. **Color mapping**: Verify `isFeeCategory = true` is passed to `getBudgetProgressColor` (inverted semantics: high % = green)
2. **N/A state**: When `computeTransactionCompleteness` returns `null`, a graceful message is shown (not a crash or blank)
3. **Conditional section**: Audit section only in `sections` array when `itemizationEnabled === true`
4. **Props wiring**: `linkedItems` passed to `AuditSection` in the render switch
5. **No extra fetching**: No `useEffect`, no Firestore calls, no `subscribeToX` in AuditSection (FR-011)
6. **Theme awareness**: Check in both light and dark mode — colors should be legible
7. **Cents formatting**: Dollar display uses `/100` with 2 decimal places — no off-by-one cent errors
8. **Missing price count**: Only shown when > 0, uses warning styling

## Activity Log

- 2026-02-09T15:00:00Z – system – lane=planned – Prompt created.
- 2026-02-10T01:34:15Z – claude-sonnet – shell_pid=98440 – lane=doing – Assigned agent via workflow command
