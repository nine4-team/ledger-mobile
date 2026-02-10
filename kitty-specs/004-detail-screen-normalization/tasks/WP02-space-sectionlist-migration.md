---
work_package_id: WP02
title: Migrate Space Detail to SectionList
lane: "done"
dependencies: [WP01]
base_branch: 004-detail-screen-normalization-WP01
base_commit: be6447c068f602cfaa250b6646665d352df13237
created_at: '2026-02-10T03:32:01.457437+00:00'
subtasks:
- T007
- T008
- T009
- T010
- T011
phase: Phase 1 - Space Consolidation + SectionList Migration
assignee: ''
agent: "claude-sonnet"
shell_pid: "35455"
review_status: "approved"
reviewed_by: "nine4-team"
history:
- timestamp: '2026-02-10T02:25:42Z'
  lane: planned
  agent: system
  shell_pid: ''
  action: Prompt generated via /spec-kitty.tasks
---

# Work Package Prompt: WP02 – Migrate Space Detail to SectionList

## Important: Review Feedback Status

**Read this first if you are implementing this task!**

- **Has review feedback?**: Check the `review_status` field above. If it says `has_feedback`, scroll to the **Review Feedback** section immediately.
- **You must address all feedback** before your work is complete.

---

## Review Feedback

> **Populated by `/spec-kitty.review`**

*[This section is empty initially.]*

---

## Implementation Command

```bash
spec-kitty implement WP02 --base WP01
```

Depends on WP01 (SpaceDetailContent must exist).

---

## Objectives & Success Criteria

- **Objective**: Convert `SpaceDetailContent` from `AppScrollView` to `SectionList` with collapsible sections using `CollapsibleSectionHeader`. Replace the manual `StickyHeader` component with native SectionList sticky behavior for the items control bar.
- Completes **User Story 1** (consistent collapsible sections) for space detail screens.
- Completes **FR-001** (SectionList scroll container) and **FR-010** (replace manual StickyHeader) for spaces.

**Success Criteria**:
1. SpaceDetailContent uses `SectionList` as its scroll container
2. All sections (Images, Notes, Items, Checklists) have `CollapsibleSectionHeader` with collapse/expand
3. Items control bar is sticky via native SectionList behavior (no `StickyHeader` component)
4. Default collapsed states: Images=expanded, Notes=collapsed, Items=expanded, Checklists=collapsed
5. Same chevron icon, touch target, and visual treatment as transaction detail

## Context & Constraints

**Reference implementation**: `app/transactions/[id]/index.tsx` — the transaction detail screen already uses this exact pattern. Copy the approach, not invent a new one.

**Key pattern: SECTION_HEADER_MARKER**
Non-sticky sections embed a sentinel marker `'__sectionHeader__'` as the first data item. The `renderItem` callback checks for this marker and renders a `CollapsibleSectionHeader` inline. This prevents the header from sticking when scrolling. Only sections that need sticky behavior (items) use `renderSectionHeader`.

**Reference from research.md**:
```typescript
// Section structure
type SpaceSection = {
  key: 'media' | 'notes' | 'items' | 'checklists';
  title: string;
  data: any[];
  badge?: string;
};

const SECTION_HEADER_MARKER = '__sectionHeader__';
```

---

## Subtasks & Detailed Guidance

### Subtask T007 – Define section structure for SpaceDetailContent

**Purpose**: Create the sections array that drives the SectionList, following the proven transaction detail pattern.

**Steps**:
1. Define the section type:
   ```typescript
   type SpaceSectionKey = 'media' | 'notes' | 'items' | 'checklists';

   type SpaceSection = {
     key: SpaceSectionKey;
     title: string;
     data: any[];
     badge?: string;
   };

   const SECTION_HEADER_MARKER = '__sectionHeader__';
   ```

2. Create the sections array in a `useMemo`:
   ```typescript
   const sections: SpaceSection[] = useMemo(() => {
     const result: SpaceSection[] = [];

     // Media section (non-sticky header)
     const mediaCollapsed = collapsedSections.media;
     result.push({
       key: 'media',
       title: 'IMAGES',
       data: mediaCollapsed ? [SECTION_HEADER_MARKER] : [SECTION_HEADER_MARKER, 'media-content'],
     });

     // Notes section (non-sticky header)
     const notesCollapsed = collapsedSections.notes;
     result.push({
       key: 'notes',
       title: 'NOTES',
       data: notesCollapsed ? [SECTION_HEADER_MARKER] : [SECTION_HEADER_MARKER, 'notes-content'],
     });

     // Items section (STICKY header — uses renderSectionHeader)
     const itemsCollapsed = collapsedSections.items;
     const itemCount = filteredSpaceItems.length;
     result.push({
       key: 'items',
       title: 'ITEMS',
       data: itemsCollapsed ? [] : filteredSpaceItems,
       badge: itemCount > 0 ? String(itemCount) : undefined,
     });

     // Checklists section (non-sticky header)
     const checklistsCollapsed = collapsedSections.checklists;
     result.push({
       key: 'checklists',
       title: 'CHECKLISTS',
       data: checklistsCollapsed ? [SECTION_HEADER_MARKER] : [SECTION_HEADER_MARKER, 'checklists-content'],
     });

     return result;
   }, [collapsedSections, filteredSpaceItems]);
   ```

3. Note the key difference: items section does NOT use SECTION_HEADER_MARKER. Its header is rendered by `renderSectionHeader` (which makes it sticky). Other sections use the marker pattern for non-sticky headers.

**Files**:
- `src/components/SpaceDetailContent.tsx` (modify)

---

### Subtask T008 – Add collapsed state management

**Purpose**: Track which sections are collapsed/expanded and provide a toggle handler.

**Steps**:
1. Add collapsed state with space-specific defaults:
   ```typescript
   const [collapsedSections, setCollapsedSections] = useState<Record<SpaceSectionKey, boolean>>({
     media: false,       // Default EXPANDED — users want to see images
     notes: true,        // Default collapsed
     items: false,       // Default EXPANDED — items are primary content
     checklists: true,   // Default collapsed
   });
   ```

2. Add toggle handler:
   ```typescript
   const handleToggleSection = useCallback((key: SpaceSectionKey) => {
     setCollapsedSections(prev => ({ ...prev, [key]: !prev[key] }));
   }, []);
   ```

**Files**:
- `src/components/SpaceDetailContent.tsx` (modify)

**Notes**: These defaults differ from transaction detail (where receipts is expanded, others collapsed). Per-screen defaults are configurable per FR-008.

---

### Subtask T009 – Replace AppScrollView with SectionList

**Purpose**: Swap the scroll container from `AppScrollView` to `SectionList` and remove the `StickyHeader` component.

**Steps**:
1. Remove `AppScrollView` and `StickyHeader` imports
2. Add `SectionList` import from `react-native`
3. Replace the main scroll container JSX:

   **Before**:
   ```tsx
   <AppScrollView contentContainerStyle={styles.scrollContent}>
     {/* Images section */}
     <View style={styles.section}>
       <AppText variant="caption" style={styles.sectionHeader}>IMAGES</AppText>
       <MediaGallerySection ... />
     </View>
     {/* Notes section */}
     <NotesSection ... />
     {/* Items section with StickyHeader */}
     <StickyHeader>
       <ItemsListControlBar ... />
     </StickyHeader>
     {/* Items list */}
     {filteredSpaceItems.map(item => <ItemCard ... />)}
     {/* Checklists */}
     ...
   </AppScrollView>
   ```

   **After**:
   ```tsx
   <SectionList
     sections={sections}
     renderSectionHeader={renderSectionHeader}
     renderItem={renderItem}
     stickySectionHeadersEnabled={true}
     keyExtractor={(item, index) => {
       if (item === SECTION_HEADER_MARKER) return `header-${index}`;
       if (typeof item === 'string') return item;
       return item.id ?? `item-${index}`;
     }}
     contentContainerStyle={styles.content}
     showsVerticalScrollIndicator={false}
     ItemSeparatorComponent={({ section }) =>
       section.key === 'items' ? <View style={styles.itemSeparator} /> : null
     }
   />
   ```

4. Remove all manual section header `<AppText>` elements (now handled by CollapsibleSectionHeader)
5. Remove `StickyHeader` wrapper around items control bar
6. Update styles: remove `scrollContent`, add `content` with appropriate padding, add `itemSeparator`

**Files**:
- `src/components/SpaceDetailContent.tsx` (modify)

**Notes**:
- `stickySectionHeadersEnabled={true}` makes renderSectionHeader output sticky. Since only items section returns non-null from renderSectionHeader, only the items header sticks.
- The existing `StickyHeader` component import can be removed entirely.

---

### Subtask T010 – Implement renderSectionHeader for items section

**Purpose**: Render the sticky items section header with `CollapsibleSectionHeader` + `ItemsListControlBar`.

**Steps**:
1. Implement `renderSectionHeader`:
   ```typescript
   const renderSectionHeader = useCallback(({ section }: { section: SpaceSection }) => {
     // Only items section gets a real (sticky) section header
     if (section.key !== 'items') return null;

     const collapsed = collapsedSections.items;

     return (
       <View style={{ backgroundColor: theme.colors.background }}>
         <CollapsibleSectionHeader
           title={section.title}
           collapsed={collapsed}
           onToggle={() => handleToggleSection('items')}
           badge={section.badge}
         />
         {!collapsed && (
           <View style={{
             paddingBottom: 12,
             borderBottomWidth: 1,
             borderBottomColor: uiKitTheme.border.secondary,
           }}>
             <ItemsListControlBar
               search={searchQuery}
               onChangeSearch={setSearchQuery}
               showSearch={showSearch}
               onToggleSearch={() => setShowSearch(!showSearch)}
               onSort={() => setSortMenuVisible(true)}
               isSortActive={sortMode !== 'created-desc'}
               onFilter={() => setFilterMenuVisible(true)}
               isFilterActive={filterMode !== 'all'}
               onAdd={bulkSelectedIds.length > 0
                 ? () => { /* open bulk menu */ }
                 : () => setAddMenuVisible(true)}
             />
           </View>
         )}
       </View>
     );
   }, [collapsedSections, handleToggleSection, searchQuery, showSearch,
       sortMode, filterMode, bulkSelectedIds, theme.colors.background,
       uiKitTheme.border.secondary]);
   ```

2. The `backgroundColor: theme.colors.background` on the wrapper is critical — it ensures the sticky header has an opaque background when scrolling content beneath it.

3. Preserve the existing control bar configuration (search, sort, filter, add button logic)

**Files**:
- `src/components/SpaceDetailContent.tsx` (modify)

**Notes**:
- This exactly mirrors the transaction detail pattern in `renderSectionHeader`
- The "add" button behavior: if items are selected (bulk mode) → show bulk menu; else → show add menu

---

### Subtask T011 – Implement renderItem for all sections

**Purpose**: Route each section's items to the appropriate rendering component, handling the SECTION_HEADER_MARKER pattern.

**Steps**:
1. Implement `renderItem`:
   ```typescript
   const renderItem = useCallback(({ item, section }: { item: any; section: SpaceSection }) => {
     // Handle section header markers (non-sticky sections)
     if (item === SECTION_HEADER_MARKER) {
       return (
         <CollapsibleSectionHeader
           title={section.title}
           collapsed={collapsedSections[section.key] ?? false}
           onToggle={() => handleToggleSection(section.key)}
           badge={section.badge}
         />
       );
     }

     switch (section.key) {
       case 'media':
         return (
           <MediaGallerySection
             title="Images"
             hideTitle={true}
             attachments={space?.images ?? []}
             maxAttachments={100}
             allowedKinds={['image']}
             onAddAttachment={handleAddImage}
             onRemoveAttachment={handleRemoveImage}
             onSetPrimary={handleSetPrimaryImage}
             emptyStateMessage="No images yet."
             pickerLabel="Add image"
             size="md"
             tileScale={1.5}
           />
         );

       case 'notes':
         return <NotesSection notes={space?.notes} expandable={true} />;

       case 'items':
         // Render individual ItemCard
         return (
           <ItemCard
             key={item.id}
             name={item.name?.trim() || 'Untitled item'}
             sku={item.sku ?? undefined}
             priceLabel={getDisplayPrice(item)}
             thumbnailUri={getPrimaryImageUri(item)}
             bookmarked={item.bookmark ?? undefined}
             selected={bulkMode && bulkSelectedIds.includes(item.id)}
             onSelectedChange={bulkMode ? (selected) => { /* toggle bulk selection */ } : undefined}
             onPress={() => { /* navigate to item detail */ }}
             menuItems={/* item menu items */}
           />
         );

       case 'checklists':
         return (
           <View style={styles.checklistsContainer}>
             {/* Render checklist cards — move existing checklist JSX here */}
             {/* "Add checklist" button + checklist card rendering */}
           </View>
         );

       default:
         return null;
     }
   }, [space, collapsedSections, handleToggleSection, filteredSpaceItems,
       bulkMode, bulkSelectedIds, /* ... other deps */]);
   ```

2. **Media section**: Use `hideTitle={true}` on MediaGallerySection since the CollapsibleSectionHeader already shows "IMAGES"

3. **Checklists section**: Move the entire checklist rendering block (Add checklist button, checklist cards with TextInput items, checkbox toggles) into the checklists case. Since checklists section uses a single 'checklists-content' data marker, all checklist cards render in one renderItem call.

4. **Bulk mode toggle**: Render the "Select multiple items..." toggle as part of the items section (after the last item) or as a ListFooterComponent

5. Keep all bottom sheet modals (sort, filter, add, picker, kebab menu) outside the SectionList at the component root level — they're portals and don't belong in the scroll content

**Files**:
- `src/components/SpaceDetailContent.tsx` (modify)

**Edge Cases**:
- Empty items list: when `filteredSpaceItems` is empty and items section is expanded, show empty state
- Bulk panel: when items are selected, show bulk action panel (select all, clear, move, remove). This can render above the items list in the items section header or as a separate element
- Checklists with many items: ensure TextInput focus works correctly inside SectionList (may need `keyboardShouldPersistTaps="handled"`)

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| SectionList scroll performance with many items | Low | Medium | Transaction detail validates this approach; same pattern |
| Checklist TextInput focus issues in SectionList | Medium | Low | Add `keyboardShouldPersistTaps="handled"` to SectionList |
| Bulk panel placement in SectionList | Low | Medium | Use renderSectionHeader to include bulk UI with control bar |

## Review Guidance

1. Collapse/expand each section — verify chevron rotation, smooth collapse, consistent touch targets
2. Scroll down with items expanded — verify items control bar sticks at top
3. Search/sort/filter items — all work with sticky header
4. Verify no `StickyHeader` component usage remains
5. Checklists: add/edit/delete checklist items work inside SectionList
6. Default states: Images expanded, Notes collapsed, Items expanded, Checklists collapsed

---

## Activity Log

- 2026-02-10T02:25:42Z – system – lane=planned – Prompt created.
- 2026-02-10T03:32:01Z – claude-sonnet – shell_pid=28470 – lane=doing – Assigned agent via workflow command
- 2026-02-10T03:37:07Z – claude-sonnet – shell_pid=28470 – lane=for_review – Ready for review: Migrated space detail to SectionList with collapsible sections, sticky items control bar, following transaction detail pattern
- 2026-02-10T03:38:01Z – claude-sonnet – shell_pid=35455 – lane=doing – Started review via workflow command
- 2026-02-10T03:40:14Z – claude-sonnet – shell_pid=35455 – lane=done – Review passed: Clean SectionList migration with collapsible sections. All success criteria met - sticky items header, proper default states, complete removal of AppScrollView/StickyHeader, follows transaction detail pattern exactly. No TypeScript errors. Ready for merge.
