---
work_package_id: WP03
title: Item Detail Screen Polish
lane: planned
dependencies:
- WP01
subtasks:
- T009
- T010
- T011
- T012
- T013
- T014
phase: Phase 3 - Item Detail
history:
- timestamp: '2026-02-10T19:00:00Z'
  lane: planned
  agent: system
  shell_pid: ''
  action: Prompt generated via /spec-kitty.tasks
---

# Work Package Prompt: WP03 – Item Detail Screen Polish

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

**Goal**: Fix item detail hero card to display linked transaction as "Source - $Amount" with space info, move "Move Item" to kebab menu, normalize spacing to 4px, fix duplicate titles.

**Success Criteria**:
- Item detail hero card displays linked transaction as "Source - $Amount" (e.g., "Amazon - $149.99") with tappable navigation
- Hero card shows space name when item is assigned to a space
- Info row styling matches transaction detail pattern (caption labels, body values, pipe separator, baseline alignment)
- Edge cases handled: deleted transaction shows "[Deleted]", no transaction shows "None", no space omits space info
- "Move Item" accessible only from kebab menu (not inline section)
- Move form opens in bottom sheet when triggered
- Section spacing is 4px between collapsible headers
- No duplicate section titles

**Independent Test**: Navigate to item detail with linked transaction and assigned space. Verify hero card shows "Transaction: Amazon - $149.99 | Space: Kitchen" (both tappable/readable). Verify "Move Item" in kebab menu only. Verify section spacing is 4px, no duplicate titles.

---

## Context & Constraints

**User Stories Addressed**:
- **User Story 2** (P1): Item Detail Top Card and Sections - FR-006, FR-007, FR-008, FR-009
- **User Story 4** (P2): Consistent Section Spacing - FR-010
- **Duplicate titles fix**: FR-008 (implementation-level failure from 004)

**Reference Documents**:
- **Spec**: `kitty-specs/005-detail-screen-polish/spec.md` (User Story 2 acceptance scenarios)
- **Plan**: `kitty-specs/005-detail-screen-polish/plan.md` (§ Component Contracts → Item Detail Hero Card)
- **Research**: `kitty-specs/005-detail-screen-polish/research.md` (Q3: Section spacing, Q4: Item detail hero card current implementation, § Item Detail Top Card Pattern, § Move Item to Kebab Menu)
- **Quickstart**: `kitty-specs/005-detail-screen-polish/quickstart.md` (§3: Item Detail Hero Card pattern, §7: Moving inline sections to kebab menu)

**Constraints**:
- Preserve offline-first patterns (cache-first reads, no awaited writes)
- Preserve existing navigation and deep links
- Theme-aware colors only (no hardcoded values)
- Handle edge cases gracefully (deleted data, missing data)

**Current File Location**:
- `app/items/[id]/index.tsx` - Main item detail screen (Expo Router)

---

## Subtasks & Detailed Guidance

### Subtask T009 – Update item detail hero card with linked transaction display

**Purpose**: Replace the current truncated transaction ID display ("abc12345...") with meaningful transaction info formatted as "Source - $Amount" (e.g., "Amazon - $149.99") that's tappable and navigates to the transaction detail screen.

**Current Implementation** (from research.md):
```typescript
<Card>
  <AppText variant="h2">{item.name || "Untitled item"}</AppText>
  <AppText variant="caption">
    Transaction:
    {item.transactionId ? (
      <AppText
        variant="body"
        style={{color: theme.colors.primary}}
        onPress={() => router.push(`/transactions/${item.transactionId}`)}
      >
        {item.transactionId.slice(0, 8)}...  {/* ← Shows truncated ID */}
      </AppText>
    ) : (
      <AppText variant="body" style={{color: theme.colors.textSecondary}}>
        None
      </AppText>
    )}
  </AppText>
</Card>
```

**Target Implementation**:
```typescript
import { useTransactionById } from '@/src/hooks/useTransactionById';
import { formatCurrency } from '@/src/utils/currency';
import { useTheme } from '@/src/theme/theme';
import { useRouter } from 'expo-router';

// Load transaction data (cache-first mode for offline-first)
const transactionData = item.transactionId
  ? useTransactionById(item.transactionId, { mode: 'offline' })
  : null;

const theme = useTheme();
const router = useRouter();

<Card>
  <AppText variant="h2">{item.name || "Untitled item"}</AppText>

  <View style={{ flexDirection: 'row', alignItems: 'baseline', flexWrap: 'wrap' }}>
    <AppText variant="caption">Transaction: </AppText>
    {transactionData ? (
      <AppText
        variant="body"
        style={{ color: theme.colors.primary }}
        onPress={() => router.push(`/transactions/${item.transactionId}`)}
      >
        {transactionData.source} - {formatCurrency(transactionData.amount)}
      </AppText>
    ) : item.transactionId ? (
      <AppText variant="body" style={{ color: theme.colors.textSecondary }}>
        [Deleted]
      </AppText>
    ) : (
      <AppText variant="body" style={{ color: theme.colors.textSecondary }}>
        None
      </AppText>
    )}
  </View>
</Card>
```

**Steps**:
1. Import or create `useTransactionById` hook (loads transaction from Firestore cache-first)
2. Load transaction data when `item.transactionId` exists
3. Format transaction display as `"{source} - {amount}"` (e.g., "Amazon - $149.99")
4. Render as tappable text with `onPress` handler navigating to transaction detail
5. Apply `color: theme.colors.primary` for link styling (brand color)
6. Handle edge case: transaction deleted/not loadable → show "[Deleted]" (not hide row)
7. Handle edge case: no transaction linked → show "None" (or omit row entirely)

**Files**:
- `app/items/[id]/index.tsx` (~20 lines modified in hero card section)
- Possibly create `src/hooks/useTransactionById.ts` if it doesn't exist (~30 lines)

**Validation**:
- Item with linked transaction: Shows "Transaction: Amazon - $149.99" (actual source and amount)
- Tapping transaction text navigates to `/transactions/:id`
- Link text has brand color (`theme.colors.primary`)
- Item with deleted transaction: Shows "Transaction: [Deleted]"
- Item with no transaction: Shows "Transaction: None"
- Loading state: Shows skeleton or fallback gracefully (not blank)

**Notes**:
- Use cache-first mode (`mode: 'offline'`) for transaction query (offline-first pattern)
- `formatCurrency` should handle negative amounts and currency symbols correctly
- Label "Transaction: " uses `variant="caption"` (secondary color, smaller)
- Value uses `variant="body"` (primary color, larger)
- Layout: `flexDirection: 'row'`, `alignItems: 'baseline'`, `flexWrap: 'wrap'`
- This satisfies FR-006 (part 1) and User Story 2 acceptance scenario 1

---

### Subtask T010 – Add space info row to item detail hero card

**Purpose**: Add space information to the hero card when the item is assigned to a space, using the same info row pattern with pipe separator.

**Target Implementation**:
```typescript
import { useSpaceById } from '@/src/hooks/useSpaceById';

// Load space data (cache-first mode)
const spaceData = item.spaceId
  ? useSpaceById(item.spaceId, { mode: 'offline' })
  : null;

<Card>
  <AppText variant="h2">{item.name || "Untitled item"}</AppText>

  <View style={{ flexDirection: 'row', alignItems: 'baseline', flexWrap: 'wrap' }}>
    {/* Transaction info (from T009) */}
    <AppText variant="caption">Transaction: </AppText>
    {/* ... transaction display logic ... */}

    {/* Space info (new in T010) */}
    {item.spaceId && spaceData && (
      <>
        <AppText variant="caption"> | </AppText>  {/* Pipe separator */}
        <AppText variant="caption">Space: </AppText>
        <AppText variant="body">{spaceData.name}</AppText>
      </>
    )}
  </View>
</Card>
```

**Steps**:
1. Import or create `useSpaceById` hook (loads space from Firestore cache-first)
2. Load space data when `item.spaceId` exists
3. Add space info row with pipe separator: ` | ` (literal pipe with spaces)
4. Format as: "Space: " (caption) + space name (body)
5. Only render when both `item.spaceId` exists AND `spaceData` is loaded
6. If no space assigned: omit space info entirely (not "Space: None")

**Files**:
- `app/items/[id]/index.tsx` (~10 lines added in hero card section)
- Possibly create `src/hooks/useSpaceById.ts` if it doesn't exist (~30 lines)

**Validation**:
- Item with assigned space: Shows "Transaction: ... | Space: Kitchen"
- Pipe separator has spaces on both sides (` | `)
- Space name uses body variant (matches value styling)
- "Space: " label uses caption variant (matches label styling)
- Item with no space: Space info absent (transaction info still shows, no trailing pipe)
- Loading state: Waits for spaceData before rendering (or shows skeleton)

**Notes**:
- Use cache-first mode for space query (offline-first)
- Pipe separator should be caption variant (secondary color)
- Labels and values follow pattern: label (caption) + value (body)
- flexWrap: 'wrap' ensures long text wraps gracefully
- This satisfies FR-006 (part 2) and User Story 2 acceptance scenario 1

---

### Subtask T011 – Handle edge cases in item detail hero card

**Purpose**: Ensure all edge cases are handled gracefully in the hero card: deleted transactions, missing data, items without names, and various data loading states.

**Edge Cases to Handle**:

1. **Transaction exists and is loadable**:
   - Show: "Transaction: Source - $Amount" (tappable)
   - Example: "Transaction: Amazon - $149.99"

2. **Transaction deleted or unavailable** (`transactionId` exists but data not loadable):
   - Show: "Transaction: [Deleted]" (not tappable, not hidden)
   - Color: `theme.colors.textSecondary` (dimmed)

3. **No transaction linked** (`transactionId` is null/undefined):
   - Option A: Show "Transaction: None"
   - Option B: Omit transaction row entirely
   - **Decision**: Show "None" for consistency (spec says show "None")

4. **Space exists and is loadable**:
   - Show: " | Space: Name"
   - Example: " | Space: Kitchen"

5. **Space assigned but deleted** (`spaceId` exists but data not loadable):
   - Omit space info (don't show "[Deleted]" for spaces)
   - Rationale: Less critical than transactions, cleaner to omit

6. **No space assigned** (`spaceId` is null/undefined):
   - Omit space info entirely (no " | Space: None")

7. **Item has no name/description**:
   - Show fallback: "Untitled item" as h2 title
   - Already implemented: `{item.name || "Untitled item"}`

8. **Loading states**:
   - While transaction/space data loading: show skeleton or wait to render
   - Avoid showing blank values or flickering content

**Implementation**:
```typescript
// Transaction display logic
const renderTransactionInfo = () => {
  if (!item.transactionId) {
    // No transaction linked
    return (
      <AppText variant="body" style={{ color: theme.colors.textSecondary }}>
        None
      </AppText>
    );
  }

  if (!transactionData) {
    // Transaction deleted or not loaded yet
    if (transactionLoading) {
      return <AppText variant="body">Loading...</AppText>;
    }
    return (
      <AppText variant="body" style={{ color: theme.colors.textSecondary }}>
        [Deleted]
      </AppText>
    );
  }

  // Transaction exists - show as link
  return (
    <AppText
      variant="body"
      style={{ color: theme.colors.primary }}
      onPress={() => router.push(`/transactions/${item.transactionId}`)}
    >
      {transactionData.source} - {formatCurrency(transactionData.amount)}
    </AppText>
  );
};

// Space display logic (only render if space exists and is loaded)
const renderSpaceInfo = () => {
  if (!item.spaceId || !spaceData) {
    return null;  // Omit space info if not assigned or not loadable
  }

  return (
    <>
      <AppText variant="caption"> | </AppText>
      <AppText variant="caption">Space: </AppText>
      <AppText variant="body">{spaceData.name}</AppText>
    </>
  );
};

// Combined info row
<View style={{ flexDirection: 'row', alignItems: 'baseline', flexWrap: 'wrap' }}>
  <AppText variant="caption">Transaction: </AppText>
  {renderTransactionInfo()}
  {renderSpaceInfo()}
</View>
```

**Steps**:
1. Extract transaction info rendering into helper function or inline logic
2. Add conditional checks for each case: exists, deleted, none, loading
3. Extract space info rendering into helper function
4. Return null for space if not assigned or not loaded (don't show deleted state)
5. Ensure item name fallback: `item.name || "Untitled item"`
6. Test all edge cases explicitly

**Files**:
- `app/items/[id]/index.tsx` (~30 lines for edge case handling logic)

**Validation**:
Test each edge case:
- [ ] Transaction exists: Shows "Source - $Amount" (tappable)
- [ ] Transaction deleted: Shows "[Deleted]" (dimmed, not tappable)
- [ ] No transaction: Shows "None" (dimmed)
- [ ] Space exists: Shows " | Space: Name"
- [ ] Space deleted: Space info absent
- [ ] No space: Space info absent
- [ ] No item name: Shows "Untitled item"
- [ ] Loading states: Graceful (no blank flicker)

**Notes**:
- Use hook's loading state if available: `const { data: transactionData, loading: transactionLoading } = useTransactionById(...)`
- Deleted transaction detection: `transactionId` exists but `transactionData` is null after loading completes
- This satisfies FR-006, FR-007 and User Story 2 acceptance scenarios 1-3

---

### Subtask T012 – Move "Move Item" to kebab menu with bottom sheet

**Purpose**: Remove the inline "Move Item" section from the main screen body and add it as an action in the kebab (more options) menu, rendering the form in a bottom sheet when triggered.

**Current Implementation** (from research.md):
```typescript
{scope === 'project' && (
  <View style={styles.moveSection}>
    <AppText variant="h2">Move Item</AppText>
    <MoveItemForm itemId={id} />
  </View>
)}
```

**Target Implementation**:
```typescript
import { useState } from 'react';
import { FormBottomSheet } from '@/src/components/FormBottomSheet';
import { MoveItemForm } from '@/src/components/MoveItemForm';

// State for bottom sheet visibility
const [moveSheetVisible, setMoveSheetVisible] = useState(false);

// Add to kebab menu items
const menuItems: AnchoredMenuItem[] = [
  { label: 'Edit', onPress: () => router.push(`/items/${id}/edit`) },
  { label: 'Bookmark', onPress: handleBookmark },
  { label: 'Move Item', onPress: () => setMoveSheetVisible(true) },  // ← New
  { label: 'Delete', onPress: handleDelete, destructive: true },
];

// Render bottom sheet (at end of component)
<FormBottomSheet
  visible={moveSheetVisible}
  onClose={() => setMoveSheetVisible(false)}
  title="Move Item"
>
  <MoveItemForm
    itemId={id}
    onSuccess={() => {
      setMoveSheetVisible(false);
      // Optionally refresh item data or navigate
    }}
    onCancel={() => setMoveSheetVisible(false)}
  />
</FormBottomSheet>
```

**Steps**:
1. Remove inline "Move Item" section from main screen body (the `{scope === 'project' && ...}` block)
2. Add state: `const [moveSheetVisible, setMoveSheetVisible] = useState(false)`
3. Add "Move Item" to kebab menu items array
4. Render FormBottomSheet at end of component with MoveItemForm inside
5. Handle onSuccess callback to close sheet (and optionally refresh)
6. Verify existing MoveItemForm component accepts required props (itemId, onSuccess, onCancel)

**Files**:
- `app/items/[id]/index.tsx` (~25 lines: remove inline section, add menu item, add bottom sheet)
- `src/components/MoveItemForm.tsx` (verify props, may need minor updates)

**Validation**:
- Inline "Move Item" section no longer visible on item detail screen
- Kebab menu (three dots icon) includes "Move Item" action
- Tapping "Move Item" opens bottom sheet with form
- Form allows moving item to different transaction or space
- "Save" in form: closes sheet, updates item (fire-and-forget)
- "Cancel" in form: closes sheet, no changes
- Bottom sheet has proper title "Move Item"
- Form functionality preserved from inline version

**Notes**:
- Use fire-and-forget pattern for form submission (offline-first)
- FormBottomSheet component should already exist (used elsewhere in app)
- MoveItemForm may need onSuccess/onCancel callback props added
- This satisfies FR-009 and User Story 2 acceptance scenarios 5-6

---

### Subtask T013 – Normalize section spacing in item detail

**Purpose**: Update section spacing from current 18px to target 4px between collapsible section headers, using the wrapper View pattern.

**Current Spacing** (from research.md):
```typescript
contentContainerStyle: {
  paddingTop: layout.screenBodyTopMd.paddingTop,
  paddingBottom: 24,
  gap: 18,  // ← Too wide, inconsistent with other screens
}
```

**Target Spacing** (using wrapper pattern from quickstart.md):
```typescript
// Wrap each section's header + content in View with internal gap
function renderSection(section: Section) {
  const collapsed = collapsedSections[section.key];

  return (
    <View style={{ gap: 12 }}>  {/* Internal header-to-content spacing */}
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

// Update contentContainerStyle gap
<SectionList
  sections={sections}
  renderItem={renderItem}
  contentContainerStyle={{
    gap: 4,  // ← Tight section-to-section spacing
    paddingTop: layout.screenBodyTopMd.paddingTop,
    paddingBottom: 24,
  }}
/>
```

**Steps**:
1. Locate item detail SectionList or ScrollView content container
2. Wrap each section's CollapsibleSectionHeader + Card content in a View with `style={{ gap: 12 }}`
3. Update contentContainerStyle.gap from 18 to 4
4. Apply to all sections: hero (if collapsible), media, notes, details, and any others
5. Test collapse/expand transitions

**Files**:
- `app/items/[id]/index.tsx` (~15 lines modified, wrappers added, gap updated)

**Validation**:
- Section-to-section spacing (header-to-header) is 4px (tight)
- Header-to-content spacing (CollapsibleSectionHeader to Card) is 12px (comfortable)
- All sections collapse/expand smoothly
- Content unmounts when collapsed (not just hidden)
- Spacing matches transaction detail (should feel identical)

**Notes**:
- Same pattern as WP02 T007 (transaction detail spacing)
- This ensures consistency across all three detail screens
- Satisfies FR-010 and User Story 4 (P2)

---

### Subtask T014 – Fix duplicate section titles in item detail

**Purpose**: Eliminate duplicate titles where CollapsibleSectionHeader renders "DETAILS" and inner TitledCard renders "Details" again.

**Solution**: Replace `TitledCard` with `Card` inside collapsible sections.

**Before**:
```typescript
<CollapsibleSectionHeader title="DETAILS" collapsed={...} onToggle={...} />
{!collapsed && (
  <TitledCard title="Details">  {/* ← Duplicate */}
    {content}
  </TitledCard>
)}
```

**After**:
```typescript
<CollapsibleSectionHeader title="DETAILS" collapsed={...} onToggle={...} />
{!collapsed && (
  <Card>  {/* ← No title */}
    {content}
  </Card>
)}
```

**Steps**:
1. Audit all collapsible sections in item detail for TitledCard usage
2. Replace `<TitledCard title="...">` with `<Card>`
3. Verify Card content renders correctly (padding, borders, background)
4. Apply to all sections: Media, Notes, Details
5. Test that section headers still display correctly

**Files**:
- `app/items/[id]/index.tsx` (~5-10 lines modified, TitledCard → Card)

**Validation**:
- Each collapsible section has exactly ONE title (CollapsibleSectionHeader)
- No duplicate "DETAILS", "MEDIA", "NOTES" titles visible
- Card content renders correctly without title prop
- Collapsible behavior unchanged

**Notes**:
- Same fix as WP02 T008 (transaction detail)
- Satisfies FR-008 and SC-005 (zero duplicate titles)

---

## Test Strategy

**Visual QA** (manual verification):

1. **Hero card transaction link verification**:
   - Item with transaction: Shows "Transaction: Amazon - $149.99" (actual values)
   - Tap transaction text → navigates to transaction detail
   - Transaction link has brand color (primary)

2. **Hero card space info verification**:
   - Item with space: Shows " | Space: Kitchen" (actual space name)
   - Item without space: Space info absent (no trailing pipe)

3. **Hero card edge cases verification**:
   - Item with deleted transaction: Shows "Transaction: [Deleted]"
   - Item with no transaction: Shows "Transaction: None"
   - Item with no name: Title shows "Untitled item"

4. **Move Item menu verification**:
   - Inline "Move Item" section absent from screen body
   - Kebab menu includes "Move Item" action
   - Tap "Move Item" → bottom sheet opens with form
   - Form allows moving to transaction/space
   - Save closes sheet and updates item (fire-and-forget)

5. **Section spacing verification**:
   - With all sections collapsed, gap between headers is 4px (tight)
   - Expand a section → gap between header and content is ~12px (comfortable)
   - Compare to transaction detail → should feel identical

6. **Duplicate titles verification**:
   - Expand each collapsible section
   - Verify: ONE title per section (CollapsibleSectionHeader only)
   - Verify: No inner titles inside cards

**Acceptance Checklist**:
- [ ] Hero card shows "Transaction: Source - $Amount" (tappable)
- [ ] Hero card shows space when assigned
- [ ] Info row styling matches transaction detail (caption labels, body values, pipe)
- [ ] Edge cases handled: deleted transaction, no transaction, no space, no name
- [ ] "Move Item" in kebab menu only (not inline)
- [ ] Move form opens in bottom sheet
- [ ] Section spacing is 4px (tight)
- [ ] Zero duplicate section titles

**No automated tests required** (per feature specification).

---

## Risks & Mitigations

**Risk 1**: Transaction/space data not loaded (blank display)
- **Severity**: Medium (confusing to users)
- **Mitigation**: Use cache-first mode, handle loading states gracefully
- **Detection**: Test with slow network or airplane mode

**Risk 2**: Edge case handling incomplete
- **Severity**: Medium (app crashes or shows wrong info)
- **Mitigation**: Test all edge cases explicitly (see T011 validation checklist)
- **Detection**: Create test items with deleted transactions, no transactions, etc.

**Risk 3**: MoveItemForm doesn't support bottom sheet usage
- **Severity**: Medium (form doesn't work in sheet)
- **Mitigation**: Verify form component props, update if needed
- **Detection**: Test move functionality in bottom sheet

**Risk 4**: Section spacing wrapper breaks collapse transitions
- **Severity**: Low (visual glitch)
- **Mitigation**: Ensure content conditionally renders (not visibility hidden)
- **Detection**: Test collapse/expand of all sections

---

## Review Guidance

**Key Acceptance Checkpoints**:
1. ✅ Hero card shows meaningful transaction info (not ID)
2. ✅ Hero card shows space info when assigned
3. ✅ Info row styling matches pattern (caption/body, pipe separator)
4. ✅ All edge cases handled gracefully
5. ✅ "Move Item" in kebab menu with bottom sheet
6. ✅ Section spacing is 4px (matches transaction detail)
7. ✅ No duplicate section titles
8. ✅ No TypeScript errors
9. ✅ Theme-aware colors throughout

**Review Questions**:
- Does the hero card display transaction and space info clearly?
- Are edge cases handled correctly (deleted data, missing data)?
- Is the "Move Item" feature accessible and functional from kebab menu?
- Is section spacing consistent with transaction detail?
- Are duplicate titles eliminated?

**Testing Checklist**:
- [ ] Hero card: transaction link, space info, all edge cases
- [ ] Move Item: kebab menu action, bottom sheet, form works
- [ ] Section spacing: 4px tight, 12px header-to-content
- [ ] Duplicate titles: none visible
- [ ] Offline mode: app responsive, data loads from cache

---

## Activity Log

> **CRITICAL**: Activity log entries MUST be in chronological order (oldest first, newest last).

**Valid lanes**: `planned`, `doing`, `for_review`, `done`

**Initial entry**:
- 2026-02-10T19:00:00Z – system – lane=planned – Prompt generated via /spec-kitty.tasks
