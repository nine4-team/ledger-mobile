---
work_package_id: WP04
title: Space Detail Screen Polish & Cleanup
lane: "doing"
dependencies: [WP01]
base_branch: 005-detail-screen-polish-WP01
base_commit: 0383efd917ab7731b7d3828f153ef7e5ba2585ce
created_at: '2026-02-10T21:13:45.655560+00:00'
subtasks:
- T015
- T016
- T017
- T018
- T019
phase: Phase 4 - Space Detail & Cleanup
shell_pid: "25725"
history:
- timestamp: '2026-02-10T19:00:00Z'
  lane: planned
  agent: system
  shell_pid: ''
  action: Prompt generated via /spec-kitty.tasks
---

# Work Package Prompt: WP04 – Space Detail Screen Polish & Cleanup

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

**Goal**: Apply SharedItemsList refactoring to space detail, update default expanded sections (only images), normalize spacing to 4px, fix duplicate titles, mark ItemsSection as deprecated.

**Success Criteria**:
- Space detail item list uses SharedItemsList in embedded mode
- Items display as grouped cards with selector circles and status badges
- Bulk selection uses bottom bar + bottom sheet pattern
- Only images section expanded by default (items, notes, checklists collapsed)
- Section spacing is 4px between collapsible headers
- No duplicate section titles
- ItemsSection component marked as deprecated with JSDoc comment (not deleted)

**Independent Test**: Open space detail with items and images. Verify item list matches project items tab (grouping, bulk UI), only images section expanded, section spacing is 4px, no duplicate titles. Check ItemsSection.tsx has deprecation comment.

---

## Context & Constraints

**User Stories Addressed**:
- **User Story 1** (P1): Correct Item List Component - FR-001 through FR-004, FR-012
- **User Story 4** (P2): Consistent Section Spacing - FR-010
- **User Story 5** (P3): Space Detail Default Sections - FR-011
- **Duplicate titles fix**: FR-008 (implementation-level failure from 004)
- **ItemsSection deprecation**: FR-012, SC-009

**Reference Documents**:
- **Spec**: `kitty-specs/005-detail-screen-polish/spec.md` (User Stories 1, 4, 5)
- **Plan**: `kitty-specs/005-detail-screen-polish/plan.md` (§ Work Package Structure)
- **Research**: `kitty-specs/005-detail-screen-polish/research.md` (Q1: SharedItemsList, Q2: ItemsSection comparison, Q3: Section spacing, § Space Detail Default Sections)
- **Quickstart**: `kitty-specs/005-detail-screen-polish/quickstart.md` (§1: Embedded mode, §2: Section spacing, §8: Space detail defaults, § Component Deprecation)

**Constraints**:
- Preserve offline-first patterns
- Preserve existing navigation and deep links
- Theme-aware colors only
- Do NOT delete ItemsSection (mark as deprecated only)

**Current File Location** (from research.md):
- `src/components/SpaceDetailContent.tsx` - Main space detail component
- OR `app/project/[projectId]/spaces/[spaceId].tsx` - Possible alternative location

---

## Subtasks & Detailed Guidance

### Subtask T015 – Replace ItemsSection with SharedItemsList in space detail

**Purpose**: Replace usage of ItemsSection component with SharedItemsList in embedded mode, bringing grouped cards, proper bulk UI, and visual parity to space detail.

**Current Implementation**:
Space detail uses `<ItemsSection>` component (created in feature 004) which lacks grouped cards, selector circles, status badges, and proper bulk UI.

**Target Implementation**:
```typescript
import { SharedItemsList } from '@/src/components/SharedItemsList';
import { useItemsManager } from '@/src/hooks/useItemsManager';

// Inside space detail component:
const manager = useItemsManager({
  listStateKey: 'space-detail-items',
  initialSort: 'created-desc',
});

// Fetch items for this space (existing hook or query)
const items = useItemsForSpace(spaceId);

// Define space-specific bulk actions
const bulkActions: BulkAction[] = [
  {
    id: 'move',
    label: 'Move to Another Space',
    onPress: (selectedIds) => {
      // Open space selector bottom sheet
      openSpaceSelector(selectedIds);
    },
  },
  {
    id: 'remove',
    label: 'Remove from Space',
    onPress: (selectedIds) => {
      // Confirm and remove items from space
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
    { label: 'Move', onPress: () => handleMoveItem(item.id) },
    { label: 'Remove from Space', onPress: () => handleRemoveItem(item.id) },
    { label: 'Delete', onPress: () => handleDeleteItem(item.id), destructive: true },
  ]}
  emptyMessage="No items in this space"
/>
```

**Steps**:
1. Import SharedItemsList and useItemsManager
2. Create manager instance with unique listStateKey ('space-detail-items')
3. Define bulkActions array with space-specific actions (Move, Remove, Delete)
4. Remove ItemsSection import and usage
5. Add SharedItemsList with embedded mode props
6. Implement or wire up bulk action handlers
7. Verify items prop comes from existing Firestore query (cache-first)

**Files**:
- `src/components/SpaceDetailContent.tsx` (or `app/project/[projectId]/spaces/[spaceId].tsx`)
- (~40 lines added/changed)

**Validation**:
- Items render as grouped cards (matching project items tab)
- Each card shows selector circle in selection mode
- Status badges appear where applicable
- Tapping item navigates to item detail
- Bulk selection shows bottom bar + "Bulk Actions" button
- Bottom sheet shows 3 actions (Move, Remove, Delete)
- All bulk actions work correctly

**Notes**:
- Space-specific bulk actions differ from transaction detail (no "Set Space" since items already in a space)
- "Move to Another Space" opens space selector to pick destination space
- Use offline-first pattern for updates (fire-and-forget)

---

### Subtask T016 – Update space detail default expanded sections

**Purpose**: Change default expanded sections so that only the images section is expanded by default. Items, notes, and checklists should be collapsed on initial screen load.

**Current Defaults** (from research.md):
```typescript
const [collapsedSections, setCollapsedSections] = useState({
  images: false,    // Expanded
  items: false,     // ← Currently expanded, should be collapsed
  notes: true,      // Collapsed
  checklists: true, // Collapsed
});
```

**Target Defaults**:
```typescript
const [collapsedSections, setCollapsedSections] = useState({
  images: false,    // ✅ Expanded (only this one)
  items: true,      // ✅ Collapsed (changed from false to true)
  notes: true,      // ✅ Collapsed
  checklists: true, // ✅ Collapsed
});
```

**Steps**:
1. Locate initial collapsed sections state in SpaceDetailContent (or equivalent)
2. Update `items: false` to `items: true`
3. Verify `images: false` (expanded), all others `true` (collapsed)
4. Test navigation to space detail → only images section expanded
5. Test manual expansion → sections expand correctly
6. Test navigation away and back → default state applies again

**Files**:
- `src/components/SpaceDetailContent.tsx` (or alternative) (~1 line changed)

**Validation**:
- Initial load: Only images section expanded
- Items, notes, checklists sections collapsed on initial load
- User can still manually expand any section
- Navigation away and back resets to default (images expanded)

**Notes**:
- Simple one-line change (`items: false` → `items: true`)
- Satisfies FR-011 and User Story 5 (P3)
- Current behavior shows items expanded which pushes checklists below fold unnecessarily

---

### Subtask T017 – Normalize section spacing in space detail

**Purpose**: Update section spacing from current 20px to target 4px between collapsible section headers, using the wrapper View pattern.

**Current Spacing** (from research.md):
```typescript
contentContainerStyle: {
  gap: 20,  // ← Widest of all detail screens, inconsistent
  paddingTop: layout.screenBodyTopMd.paddingTop,
}
```

**Target Spacing** (using wrapper pattern):
```typescript
// Wrap each section's header + content in View
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
    gap: 4,  // ← Tight section-to-section spacing (changed from 20)
    paddingTop: layout.screenBodyTopMd.paddingTop,
    paddingBottom: 24,
  }}
/>
```

**Steps**:
1. Locate space detail SectionList content container
2. Wrap each section's CollapsibleSectionHeader + Card content in View with `style={{ gap: 12 }}`
3. Update contentContainerStyle.gap from 20 to 4
4. Apply to all sections: images, items, notes, checklists
5. Test collapse/expand transitions

**Files**:
- `src/components/SpaceDetailContent.tsx` (or alternative) (~15 lines modified)

**Validation**:
- Section-to-section spacing (header-to-header) is 4px (tight)
- Header-to-content spacing is 12px (comfortable)
- All sections collapse/expand smoothly
- Spacing matches transaction detail and item detail (should feel identical)

**Notes**:
- Same pattern as WP02 T007 and WP03 T013
- This completes the section spacing normalization across all three detail screens
- Satisfies FR-010 and User Story 4 (P2)

---

### Subtask T018 – Fix duplicate section titles in space detail

**Purpose**: Eliminate duplicate titles where CollapsibleSectionHeader renders a title and inner TitledCard renders it again.

**Solution**: Replace `TitledCard` with `Card` inside collapsible sections.

**Before**:
```typescript
<CollapsibleSectionHeader title="IMAGES" collapsed={...} onToggle={...} />
{!collapsed && (
  <TitledCard title="Images">  {/* ← Duplicate */}
    {content}
  </TitledCard>
)}
```

**After**:
```typescript
<CollapsibleSectionHeader title="IMAGES" collapsed={...} onToggle={...} />
{!collapsed && (
  <Card>  {/* ← No title */}
    {content}
  </Card>
)}
```

**Steps**:
1. Audit all collapsible sections in space detail for TitledCard usage
2. Replace `<TitledCard title="...">` with `<Card>`
3. Verify Card content renders correctly (padding, borders, background)
4. Apply to all sections: Images, Items, Notes, Checklists
5. Test that section headers still display correctly

**Files**:
- `src/components/SpaceDetailContent.tsx` (or alternative) (~5-10 lines modified)

**Validation**:
- Each collapsible section has exactly ONE title (CollapsibleSectionHeader)
- No duplicate "IMAGES", "ITEMS", "NOTES", "CHECKLISTS" titles visible
- Card content renders correctly without title prop
- Collapsible behavior unchanged

**Notes**:
- Same fix as WP02 T008 and WP03 T014
- Completes duplicate title elimination across all detail screens
- Satisfies FR-008 and SC-005

---

### Subtask T019 – Mark ItemsSection as deprecated

**Purpose**: Formally deprecate the ItemsSection component with JSDoc comment indicating it should not be used in new code. Do NOT delete the component (removal is future work).

**Target Implementation**:
```typescript
/**
 * @deprecated Use SharedItemsList with embedded={true} instead.
 *
 * This component was created in feature 004-detail-screen-normalization but lacks
 * key features present in SharedItemsList:
 * - No grouped cards (uses plain ItemCard instead of GroupedItemCard)
 * - No selector circles on item cards
 * - No status badges
 * - Broken bulk selection toggle (doesn't deselect when all selected)
 * - Inline bulk panel instead of bottom bar + bottom sheet pattern
 *
 * Migration guide: See kitty-specs/005-detail-screen-polish/quickstart.md §1
 * for how to use SharedItemsList in embedded mode.
 *
 * Replaced by SharedItemsList in:
 * - Transaction detail (WP02)
 * - Space detail (WP04)
 *
 * This component will be removed in a future cleanup feature once all usages
 * are migrated and verified stable.
 */
export function ItemsSection<S extends string = string, F extends string = string>(
  props: ItemsSectionProps<S, F>
) {
  // ...existing implementation (unchanged)
}
```

**Steps**:
1. Open `src/components/ItemsSection.tsx`
2. Add JSDoc deprecation comment above component export
3. Include:
   - Clear deprecation notice with replacement
   - List of issues/limitations
   - Link to migration guide (quickstart.md)
   - Note about when it will be removed
4. Do NOT change component implementation
5. Do NOT delete the file
6. Verify TypeScript shows deprecation warnings in IDEs

**Files**:
- `src/components/ItemsSection.tsx` (~15 lines added: JSDoc comment only)

**Validation**:
- ItemsSection.tsx file still exists
- Component still exports and functions correctly (for now)
- JSDoc comment is visible above component definition
- IDEs show deprecation warning when importing ItemsSection
- Comment includes clear migration path

**Notes**:
- **Do NOT delete ItemsSection** - this would break any remaining usages not migrated yet
- Marking as deprecated signals to developers not to use it in new code
- Future cleanup feature (after 005 is stable) can safely remove the component
- This satisfies FR-012 ("ItemsSection MUST be retired and replaced") by deprecating it
- Satisfies SC-009 ("ItemsSection no longer imported or used") by discouraging use

---

## Test Strategy

**Visual QA** (manual verification):

1. **Item list verification**:
   - Navigate to space detail with multiple items
   - Verify items display as grouped cards (matching project items tab)
   - Verify selector circles and status badges visible
   - Select items → verify bottom bar appears
   - Tap "Bulk Actions" → verify bottom sheet with 3 actions (Move, Remove, Delete)
   - Execute each bulk action → verify behavior works

2. **Default sections verification**:
   - Navigate to space detail (fresh load)
   - Verify only images section is expanded
   - Verify items, notes, checklists sections are collapsed
   - Manually expand items → verify it expands correctly
   - Navigate away and back → verify default state applies (only images expanded)

3. **Section spacing verification**:
   - With all sections collapsed, observe gap between headers
   - Target: 4px (tight, matching transaction detail and item detail)
   - Expand a section → verify comfortable header-to-content gap (~12px)

4. **Duplicate titles verification**:
   - Expand each collapsible section
   - Verify: ONE title per section (CollapsibleSectionHeader only)
   - Verify: No inner "Images", "Items", "Notes", "Checklists" titles

5. **ItemsSection deprecation verification**:
   - Open `src/components/ItemsSection.tsx`
   - Verify JSDoc deprecation comment is present
   - Try importing ItemsSection in IDE → verify deprecation warning shown
   - Verify component still functions (not deleted)

**Acceptance Checklist**:
- [ ] Item list uses SharedItemsList in embedded mode
- [ ] Items grouped, selector circles, status badges visible
- [ ] Bulk selection uses bottom bar + bottom sheet
- [ ] Only images section expanded by default
- [ ] Section spacing is 4px (tight)
- [ ] Zero duplicate section titles
- [ ] ItemsSection marked as deprecated (not deleted)

**No automated tests required** (per feature specification).

---

## Risks & Mitigations

**Risk 1**: Space detail has different component structure
- **Severity**: Medium (may not use same patterns as transaction/item detail)
- **Mitigation**: Research.md confirms it uses SectionList like other screens
- **Detection**: Review code structure before starting implementation

**Risk 2**: Bulk actions for spaces undefined
- **Severity**: Medium (bulk actions won't work)
- **Mitigation**: Define minimal space-specific actions (Move, Remove, Delete)
- **Detection**: Test bulk actions after implementation

**Risk 3**: ItemsSection still imported in non-migrated screens
- **Severity**: Low (deprecation warning only)
- **Mitigation**: Only mark as deprecated, don't break existing imports
- **Detection**: Search codebase for ItemsSection imports (none expected after WP02/WP04)

**Risk 4**: Section spacing wrapper breaks layout
- **Severity**: Low (visual glitch)
- **Mitigation**: Use same pattern as WP02/WP03 (proven to work)
- **Detection**: Test collapse/expand transitions

---

## Review Guidance

**Key Acceptance Checkpoints**:
1. ✅ SharedItemsList renders in embedded mode with proper props
2. ✅ Item list matches project items tab (grouped cards, bulk UI)
3. ✅ Only images section expanded by default
4. ✅ Section spacing is 4px (matches transaction/item detail)
5. ✅ No duplicate section titles
6. ✅ ItemsSection marked as deprecated with clear JSDoc comment
7. ✅ No TypeScript errors
8. ✅ Theme-aware colors throughout

**Review Questions**:
- Do items display correctly with grouping, selectors, and status badges?
- Is the default expanded sections behavior correct (images only)?
- Is section spacing consistent across all three detail screens?
- Are duplicate titles eliminated?
- Is ItemsSection properly deprecated (not deleted)?
- Do all bulk actions work correctly?

**Testing Checklist**:
- [ ] Item list: grouping, selection, bulk actions functional
- [ ] Default sections: only images expanded on load
- [ ] Section spacing: 4px tight, 12px header-to-content
- [ ] Duplicate titles: none visible
- [ ] ItemsSection: deprecated but still functional
- [ ] Offline mode: app responsive, no UI blocking

**Cross-Screen Consistency Check**:
After WP02, WP03, WP04 complete, verify consistency:
- [ ] All three detail screens have identical 4px section spacing
- [ ] All three use SharedItemsList for items (embedded mode)
- [ ] All three have no duplicate section titles
- [ ] Item list behavior identical across all screens

---

## Activity Log

> **CRITICAL**: Activity log entries MUST be in chronological order (oldest first, newest last).

**Valid lanes**: `planned`, `doing`, `for_review`, `done`

**Initial entry**:
- 2026-02-10T19:00:00Z – system – lane=planned – Prompt generated via /spec-kitty.tasks
