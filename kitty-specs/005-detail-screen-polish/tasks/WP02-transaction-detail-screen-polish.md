---
work_package_id: WP02
title: Transaction Detail Screen Polish
lane: "doing"
dependencies: [WP01]
base_branch: 005-detail-screen-polish-WP01
base_commit: 0383efd917ab7731b7d3828f153ef7e5ba2585ce
created_at: '2026-02-10T21:13:24.205964+00:00'
subtasks:
- T005
- T006
- T007
- T008
phase: Phase 2 - Transaction Detail
shell_pid: "24895"
agent: "claude-sonnet-4.5"
history:
- timestamp: '2026-02-10T19:00:00Z'
  lane: planned
  agent: system
  shell_pid: ''
  action: Prompt generated via /spec-kitty.tasks
---

# Work Package Prompt: WP02 – Transaction Detail Screen Polish

## ⚠️ IMPORTANT: Review Feedback Status

**Read this first if you are implementing this task!**

- **Has review feedback?**: Check the `review_status` field above. If it says `has_feedback`, scroll to the **Review Feedback** section immediately (right below this notice).
- **You must address all feedback** before your work is complete. Feedback items are your implementation TODO list.
- **Mark as acknowledged**: When you understand the feedback and begin addressing it, update `review_status: acknowledged` in the frontmatter.
- **Report progress**: As you address each feedback item, update the Activity Log explaining what you changed.

---

## Review Feedback

> **Populated by `/spec-kitty.review`** – Reviewers add detailed feedback here when work needs changes. Implementation must address every item listed below before returning for re-review.

*[This section is empty initially. Reviewers will populate it if the work is returned from review. If you see feedback here, treat each item as a must-do before completion.]*

---

## Markdown Formatting
Wrap HTML/XML tags in backticks: `` `<div>` ``, `` `<script>` ``
Use language identifiers in code blocks: ````typescript`, ````bash`

---

## Objectives & Success Criteria

**Goal**: Apply SharedItemsList refactoring to transaction detail screen, merge tax into details section, normalize spacing to 4px, fix duplicate titles.

**Success Criteria**:
- Transaction detail item list uses SharedItemsList in embedded mode
- Items display as grouped cards with selector circles and status badges
- Bulk selection uses bottom bar + bottom sheet pattern (not inline buttons)
- Single "DETAILS" collapsible section contains all detail rows including tax (when applicable)
- No separate "TAX & ITEMIZATION" section header
- Section spacing is 4px between collapsible headers
- No duplicate section titles (CollapsibleSectionHeader + Card, not TitledCard)

**Independent Test**: Open transaction detail screen with items and tax data. Verify item list matches project items tab (grouping, bulk UI), Details section includes tax rows, section spacing is tight (4px), no duplicate titles.

---

## Context & Constraints

**User Stories Addressed**:
- **User Story 1** (P1): Correct Item List Component - FR-001 through FR-004, FR-012
- **User Story 3** (P2): Merge Tax into Details - FR-005
- **User Story 4** (P2): Consistent Section Spacing - FR-010
- **Duplicate titles fix**: FR-008 (implementation-level failure from 004)

**Reference Documents**:
- **Spec**: `kitty-specs/005-detail-screen-polish/spec.md`
- **Plan**: `kitty-specs/005-detail-screen-polish/plan.md` (§ Planning Decisions → Section Spacing Strategy)
- **Research**: `kitty-specs/005-detail-screen-polish/research.md` (Q3: Section spacing values, Q4: Tax section merge)
- **Quickstart**: `kitty-specs/005-detail-screen-polish/quickstart.md` (§2: Section spacing pattern, §4: Tax merge pattern)

**Constraints**:
- Preserve offline-first patterns (no awaited Firestore writes, fire-and-forget with `.catch()`)
- Preserve existing navigation and deep links
- Maintain theme-aware colors (no hardcoded values)
- No visual regressions in other screens

**Current File Location** (from research.md):
- `app/transactions/[id]/index.tsx` - Main transaction detail screen (Expo Router)
- Possibly split into `app/transactions/[id]/sections/` - Detail row sections

---

## Subtasks & Detailed Guidance

### Subtask T005 – Replace ItemsSection with SharedItemsList in transaction detail

**Purpose**: Replace usage of ItemsSection component with SharedItemsList in embedded mode, bringing grouped cards, proper bulk UI, selector circles, and status badges to transaction detail.

**Current Implementation** (identified in research.md):
Transaction detail uses `<ItemsSection>` component which lacks:
- Grouped cards (uses plain ItemCard)
- Selector circles (prop not passed)
- Status badges (prop not passed)
- Proper bulk UI (has inline panel instead of bottom bar + sheet)

**Target Implementation**:
```typescript
import { SharedItemsList } from '@/src/components/SharedItemsList';
import { useItemsManager } from '@/src/hooks/useItemsManager';

// Inside transaction detail component:
const manager = useItemsManager({
  listStateKey: 'transaction-detail-items',
  initialSort: 'created-desc',
});

// Fetch items for this transaction (existing hook or query)
const items = useItemsForTransaction(transactionId);

// Define transaction-specific bulk actions
const bulkActions: BulkAction[] = [
  {
    id: 'set-space',
    label: 'Set Space',
    onPress: (selectedIds) => {
      // Open space selector bottom sheet
      // Call updateItemsSpace(selectedIds, spaceId) on selection
      openSpaceSelector(selectedIds);
    },
  },
  {
    id: 'set-status',
    label: 'Set Status',
    onPress: (selectedIds) => {
      // Open status selector bottom sheet
      openStatusSelector(selectedIds);
    },
  },
  {
    id: 'set-sku',
    label: 'Set SKU',
    onPress: (selectedIds) => {
      // Open SKU input bottom sheet
      openSKUInput(selectedIds);
    },
  },
  {
    id: 'remove',
    label: 'Remove from Transaction',
    onPress: (selectedIds) => {
      // Confirm and remove items from transaction
      handleRemoveItems(selectedIds);
    },
  },
  {
    id: 'delete',
    label: 'Delete Items',
    destructive: true,
    onPress: (selectedIds) => {
      // Confirm and delete items permanently
      handleDeleteItems(selectedIds);
    },
  },
];

// Replace ItemsSection with SharedItemsList
<SharedItemsList
  embedded={true}
  manager={manager}
  items={items}
  bulkActions={bulkActions}
  onItemPress={(id) => router.push(`/items/${id}`)}
  getItemMenuItems={(item) => [
    { label: 'Open', onPress: () => router.push(`/items/${item.id}`) },
    { label: 'Edit', onPress: () => router.push(`/items/${item.id}/edit`) },
    { label: 'Remove from Transaction', onPress: () => handleRemoveItem(item.id) },
    { label: 'Delete', onPress: () => handleDeleteItem(item.id), destructive: true },
  ]}
  emptyMessage="No items in this transaction"
/>
```

**Steps**:
1. Import SharedItemsList and useItemsManager
2. Create manager instance with unique listStateKey
3. Define bulkActions array with transaction-specific actions (Set Space, Set Status, Set SKU, Remove, Delete)
4. Remove ItemsSection import and usage
5. Add SharedItemsList with embedded mode props
6. Implement or wire up bulk action handlers (openSpaceSelector, etc.)
7. Verify items prop comes from existing Firestore query (cache-first mode)

**Files**:
- `app/transactions/[id]/index.tsx` (modified, ~40 lines added/changed)

**Validation**:
- Items render as grouped cards (matching project items tab)
- Each card shows selector circle when in selection mode
- Status badges appear on cards where applicable
- Tapping item navigates to item detail
- Bulk selection shows sticky bottom bar with "{N} selected" + "Bulk Actions" button
- Tapping "Bulk Actions" opens bottom sheet with 5 actions
- All bulk actions work correctly (space, status, SKU, remove, delete)

**Notes**:
- Bulk action handlers may already exist (reuse them)
- Use offline-first pattern for updates: fire-and-forget with `.catch()`
- Grouping happens automatically in SharedItemsList (by name/SKU/source)

---

### Subtask T006 – Merge tax/itemization rows into Details section

**Purpose**: Combine the separate "TAX & ITEMIZATION" collapsible section into the "DETAILS" section, creating a single unified details section with conditional tax rows.

**Current Structure** (identified in research.md):
Two separate collapsible sections:
1. "DETAILS" - Source, Date, Amount, Status, Purchased by, Reimbursement type, Budget category, Email receipt
2. "TAX & ITEMIZATION" - Subtotal, Tax rate, Tax amount

**Target Structure**:
Single "DETAILS" section containing all rows:
```typescript
const detailRows = [
  // Core transaction details (always shown)
  { label: 'Source', value: transaction.source },
  { label: 'Date', value: formatDate(transaction.date) },
  { label: 'Amount', value: formatCurrency(transaction.amount) },
  { label: 'Status', value: transaction.status },
  { label: 'Purchased by', value: transaction.purchasedBy || 'N/A' },
  { label: 'Reimbursement', value: transaction.reimbursementType || 'None' },
  { label: 'Budget category', value: transaction.budgetCategory || 'Uncategorized' },
  { label: 'Email receipt', value: transaction.emailReceipt ? 'Yes' : 'No' },

  // Tax rows (conditionally included)
  ...(transaction.itemizationEnabled ? [
    { label: 'Subtotal', value: formatCurrency(transaction.subtotal) },
    { label: 'Tax rate', value: `${transaction.taxRate}%` },
    { label: 'Tax amount', value: formatCurrency(transaction.taxAmount) },
  ] : []),
];

// Single collapsible section
<CollapsibleSectionHeader
  title="DETAILS"
  collapsed={collapsedSections.details}
  onToggle={() => toggleSection('details')}
/>
{!collapsedSections.details && (
  <Card>
    {detailRows.map((row, index) => (
      <DetailRow
        key={row.label}
        label={row.label}
        value={row.value}
        showBorder={index < detailRows.length - 1}
      />
    ))}
  </Card>
)}
```

**Steps**:
1. Locate the "DETAILS" and "TAX & ITEMIZATION" section definitions in transaction detail
2. Combine detail row data into single array with conditional tax rows (use spread operator)
3. Remove "TAX & ITEMIZATION" CollapsibleSectionHeader
4. Update "DETAILS" section to render combined row array
5. Remove tax section key from collapsedSections state
6. Verify tax rows only appear when `transaction.itemizationEnabled === true`

**Files**:
- `app/transactions/[id]/index.tsx` (or `app/transactions/[id]/sections/details.tsx` if split)
- (~20 lines modified, section header removed, rows combined)

**Validation**:
- Transaction with tax data: Details section shows all rows including Subtotal, Tax rate, Tax amount
- Transaction without tax data: Details section shows only non-tax rows (tax rows absent, not empty)
- No "TAX & ITEMIZATION" section header visible
- Section expands/collapses correctly with all rows
- Rows display correctly with DetailRow component (labels, values, borders)

**Notes**:
- Use conditional spread `...()` to include tax rows only when applicable
- Ensure transaction data includes `itemizationEnabled` boolean flag
- Tax rows should appear at the end of the details list (after email receipt)
- This satisfies FR-005 and User Story 3 (P2)

---

### Subtask T007 – Normalize section spacing in transaction detail

**Purpose**: Update section spacing from current 10px to target 4px between collapsible section headers, using the wrapper View pattern to maintain proper header-to-content spacing.

**Current Spacing** (from research.md):
```typescript
contentContainerStyle: {
  paddingTop: layout.screenBodyTopMd.paddingTop,
  paddingBottom: 24,
  gap: 10,  // ← Between all direct children (sections AND header-content pairs)
}
```

**Problem**: The `gap` property applies to ALL direct children of contentContainer. Setting `gap: 4` would make header-to-content spacing too tight (should be ~12px).

**Solution** (from quickstart.md §2):
Wrap each section's CollapsibleSectionHeader + content Card in a View with internal `gap: 12`:

```typescript
// For each section using SECTION_HEADER_MARKER or similar pattern:
function renderSection(section: Section) {
  const collapsed = collapsedSections[section.key];

  return (
    <View style={{ gap: 12 }}>  {/* ← Internal header-to-content spacing */}
      <CollapsibleSectionHeader
        title={section.title}
        collapsed={collapsed}
        onToggle={() => toggleSection(section.key)}
      />
      {!collapsed && (
        <Card>
          {/* Section content */}
        </Card>
      )}
    </View>
  );
}

// Then set contentContainerStyle gap to 4:
<SectionList
  sections={sections}
  renderItem={renderItem}
  contentContainerStyle={{
    gap: 4,  // ← Section-to-section spacing (tight)
    paddingTop: layout.screenBodyTopMd.paddingTop,
    paddingBottom: 24,
  }}
/>
```

**Steps**:
1. Locate transaction detail SectionList or ScrollView content container
2. Wrap each section's CollapsibleSectionHeader + Card content in a View with `style={{ gap: 12 }}`
3. Update contentContainerStyle.gap from 10 to 4
4. Apply to all sections: hero (if collapsible), media, items, notes, details
5. Test collapse/expand transitions to ensure wrapper View doesn't interfere

**Files**:
- `app/transactions/[id]/index.tsx` (~15 lines modified, wrappers added, gap updated)

**Validation**:
- Section-to-section spacing (header-to-header) is 4px (tight, compact)
- Header-to-content spacing (CollapsibleSectionHeader to Card) is 12px (comfortable)
- All sections can collapse/expand smoothly
- Content still unmounts when collapsed (not just hidden)
- Spacing feels consistent and compact across all sections

**Notes**:
- Wrapper View combines header + content into single SectionList child
- When collapsed, only header renders inside wrapper (content conditionally rendered)
- This pattern maintains semantic grouping (section as single entity)
- Satisfies FR-010 and User Story 4 (P2)

---

### Subtask T008 – Fix duplicate section titles in transaction detail

**Purpose**: Eliminate duplicate titles where CollapsibleSectionHeader renders "DETAILS" and inner TitledCard renders "Details" again.

**Problem** (from research.md):
```
DETAILS                    ← CollapsibleSectionHeader
┌─────────────────────┐
│ Details             │    ← TitledCard title (duplicate!)
│ Source: Amazon      │
│ Date: 2026-01-15    │
└─────────────────────┘
```

**Solution**: Use `Card` (no title) instead of `TitledCard` inside collapsible sections:

**Before**:
```typescript
<CollapsibleSectionHeader title="DETAILS" collapsed={...} onToggle={...} />
{!collapsed && (
  <TitledCard title="Details">  {/* ← Duplicate title */}
    {detailRows.map(...)}
  </TitledCard>
)}
```

**After**:
```typescript
<CollapsibleSectionHeader title="DETAILS" collapsed={...} onToggle={...} />
{!collapsed && (
  <Card>  {/* ← No title prop, section header provides it */}
    {detailRows.map(...)}
  </Card>
)}
```

**Steps**:
1. Audit all collapsible sections in transaction detail for TitledCard usage
2. Replace `<TitledCard title="...">` with `<Card>`
3. Verify Card content still renders correctly (padding, borders, background)
4. Apply to all sections: Media, Items, Notes, Details
5. Test that section headers still display correctly (uppercase titles)

**Files**:
- `app/transactions/[id]/index.tsx` (~5-10 lines modified, TitledCard → Card)

**Validation**:
- Each collapsible section has exactly ONE title (the CollapsibleSectionHeader)
- No duplicate "DETAILS", "MEDIA", "NOTES", "ITEMS" titles visible
- Card content renders correctly without title prop (padding, background, borders intact)
- Collapsible behavior unchanged (sections still expand/collapse)

**Notes**:
- Card component already exists and has no title prop
- TitledCard is a variant that adds a title - not needed when section header provides it
- This fix applies to all detail screens (will repeat in WP03 and WP04)
- Satisfies FR-008 and SC-005 (zero duplicate titles)

---

## Test Strategy

**Visual QA** (manual verification):

1. **Item list verification**:
   - Navigate to transaction detail with multiple items
   - Verify items display as grouped cards (matching project items tab)
   - Verify each card has selector circle
   - Verify status badges appear where applicable
   - Select items → verify bottom bar appears with "{N} selected" + "Bulk Actions" button
   - Tap "Bulk Actions" → verify bottom sheet with 5 actions (Set Space, Set Status, Set SKU, Remove, Delete)
   - Execute each bulk action → verify behavior works

2. **Details section merge verification**:
   - Navigate to transaction with tax data (`itemizationEnabled: true`)
   - Expand "DETAILS" section
   - Verify rows: Source, Date, Amount, Status, Purchased by, Reimbursement, Budget category, Email receipt, Subtotal, Tax rate, Tax amount
   - Verify no "TAX & ITEMIZATION" section header
   - Navigate to transaction without tax data
   - Verify "DETAILS" section shows only non-tax rows (tax rows absent)

3. **Section spacing verification**:
   - With all sections collapsed, measure/observe gap between section headers
   - Target: 4px (tight, compact stacking)
   - Expand a section → verify gap between header and content is comfortable (~12px)
   - Compare to item detail and space detail (should feel identical after WP03/WP04)

4. **Duplicate titles verification**:
   - Expand each collapsible section
   - Verify: ONE title per section (CollapsibleSectionHeader only)
   - Verify: No inner "Details", "Media", "Notes", "Items" titles inside cards

**Acceptance Checklist**:
- [ ] Item list uses SharedItemsList in embedded mode
- [ ] Items grouped by name/SKU/source (matches project items tab)
- [ ] Selector circles and status badges visible
- [ ] Bulk selection uses bottom bar + bottom sheet (not inline buttons)
- [ ] Single "DETAILS" section includes tax rows when applicable
- [ ] No "TAX & ITEMIZATION" section header
- [ ] Section spacing is 4px (tight)
- [ ] Header-to-content spacing is comfortable (~12px)
- [ ] Zero duplicate section titles

**No automated tests required** (per feature specification).

---

## Risks & Mitigations

**Risk 1**: Bulk action handlers don't exist or are broken
- **Severity**: Medium (bulk actions won't work)
- **Mitigation**: Reuse existing handlers if available, implement minimal versions if needed
- **Detection**: Test each bulk action (Set Space, Set Status, etc.)

**Risk 2**: Tax rows shown when itemizationEnabled is false
- **Severity**: Medium (confusing to users)
- **Mitigation**: Use strict conditional check `transaction.itemizationEnabled === true`
- **Detection**: Test with both tax-enabled and non-tax transactions

**Risk 3**: Section spacing wrapper breaks collapse transitions
- **Severity**: Low (visual glitch)
- **Mitigation**: Ensure content conditionally renders (not just visibility: hidden)
- **Detection**: Test collapse/expand of all sections

**Risk 4**: Offline-first patterns violated during refactoring
- **Severity**: High (app hangs when offline)
- **Mitigation**: Never await Firestore writes, use fire-and-forget with `.catch()`
- **Detection**: Test in airplane mode (app should remain responsive)

---

## Review Guidance

**Key Acceptance Checkpoints**:
1. ✅ SharedItemsList renders in embedded mode with proper props
2. ✅ Item list matches project items tab (grouped cards, bulk UI)
3. ✅ Single "DETAILS" section contains all rows including tax
4. ✅ Section spacing is 4px between headers
5. ✅ No duplicate section titles anywhere
6. ✅ All existing functionality preserved (navigation, bulk actions, collapse/expand)
7. ✅ No TypeScript errors
8. ✅ Theme-aware colors used throughout

**Review Questions**:
- Do items display correctly with grouping, selectors, and status badges?
- Is the Details section merge clean (tax rows conditional)?
- Is section spacing consistent and visually compact?
- Are duplicate titles eliminated?
- Do all bulk actions work correctly?

**Testing Checklist**:
- [ ] Item list: grouping, selection, bulk actions all functional
- [ ] Details section: includes tax rows when applicable, excludes when not
- [ ] Section spacing: 4px tight between headers, 12px comfortable header-to-content
- [ ] Duplicate titles: none visible in any section
- [ ] Offline mode: app remains responsive, no UI blocking

---

## Activity Log

> **CRITICAL**: Activity log entries MUST be in chronological order (oldest first, newest last).

**Valid lanes**: `planned`, `doing`, `for_review`, `done`

**Initial entry**:
- 2026-02-10T19:00:00Z – system – lane=planned – Prompt generated via /spec-kitty.tasks
- 2026-02-10T21:13:24Z – claude-sonnet-4.5 – shell_pid=24895 – lane=doing – Assigned agent via workflow command
