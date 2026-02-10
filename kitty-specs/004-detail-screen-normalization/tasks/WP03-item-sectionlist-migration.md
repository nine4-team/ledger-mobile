---
work_package_id: WP03
title: Migrate Item Detail to SectionList
lane: "doing"
dependencies: []
base_branch: main
base_commit: 72f192438270bcb412e923660c2f3bf573c6428e
created_at: '2026-02-10T03:41:08.653027+00:00'
subtasks:
- T012
- T013
- T014
- T015
- T016
phase: Phase 1 - Space Consolidation + SectionList Migration
assignee: ''
agent: ''
shell_pid: "39334"
review_status: ''
reviewed_by: ''
history:
- timestamp: '2026-02-10T02:25:42Z'
  lane: planned
  agent: system
  shell_pid: ''
  action: Prompt generated via /spec-kitty.tasks
---

# Work Package Prompt: WP03 – Migrate Item Detail to SectionList

## Important: Review Feedback Status

- **Has review feedback?**: Check the `review_status` field above.
- **Mark as acknowledged** when you begin addressing feedback.

---

## Review Feedback

*[This section is empty initially.]*

---

## Implementation Command

```bash
spec-kitty implement WP03
```

No dependencies — item detail is independent of space detail work. Can run in parallel with WP01/WP02.

---

## Objectives & Success Criteria

- **Objective**: Convert the item detail screen (`app/items/[id]/index.tsx`, 694 lines) from `AppScrollView` to `SectionList` with collapsible sections.
- Completes **User Story 1** (consistent collapsible sections) for item detail.
- Completes **FR-001** and **FR-002** for item detail.

**Success Criteria**:
1. Item detail uses `SectionList` as its scroll container
2. Sections (Images, Notes, Details) have `CollapsibleSectionHeader` with collapse/expand
3. Hero section (item name + transaction link) is always visible, not collapsible
4. Same chevron icon, touch target, and visual treatment as transaction detail
5. All existing functionality preserved: media gallery, notes, detail rows, menus, navigation
6. Default collapsed states: Images=expanded, Notes=collapsed, Details=collapsed

## Context & Constraints

**Source file**: `app/items/[id]/index.tsx` (694 lines)

**Current structure**: Uses `AppScrollView` with sections rendered inline:
1. Hero card (name, transaction link) — always visible
2. Error banner (conditional)
3. `MediaGallerySection` — images
4. `NotesSection` — expandable notes
5. `TitledCard` with inline detail rows — Source, SKU, prices, space, budget category
6. Move Item `TitledCard` (conditional, scope !== 'inventory')
7. `BottomSheetMenuList` — item actions menu

**Key difference from transaction/space**: Item detail has no items list, no bulk operations, no sticky sections. This is a simpler migration — `stickySectionHeadersEnabled` can be `false`.

**Reference pattern**: Same SECTION_HEADER_MARKER pattern as transaction detail. Copy the approach.

---

## Subtasks & Detailed Guidance

### Subtask T012 – Define section structure for item detail

**Purpose**: Create the sections array that maps item detail's current inline content to SectionList sections.

**Steps**:
1. Define section types:
   ```typescript
   type ItemSectionKey = 'hero' | 'media' | 'notes' | 'details';

   type ItemSection = {
     key: ItemSectionKey;
     title?: string;  // hero has no title
     data: any[];
     badge?: string;
   };

   const SECTION_HEADER_MARKER = '__sectionHeader__';
   ```

2. Create sections array in `useMemo`:
   ```typescript
   const sections: ItemSection[] = useMemo(() => {
     if (isLoading || !item) return [];

     const result: ItemSection[] = [];

     // Hero section — always visible, no header, no collapse
     result.push({
       key: 'hero',
       data: ['hero-content'],
     });

     // Media section (non-sticky, collapsible)
     result.push({
       key: 'media',
       title: 'IMAGES',
       data: collapsedSections.media
         ? [SECTION_HEADER_MARKER]
         : [SECTION_HEADER_MARKER, 'media-content'],
     });

     // Notes section (non-sticky, collapsible)
     result.push({
       key: 'notes',
       title: 'NOTES',
       data: collapsedSections.notes
         ? [SECTION_HEADER_MARKER]
         : [SECTION_HEADER_MARKER, 'notes-content'],
     });

     // Details section (non-sticky, collapsible)
     result.push({
       key: 'details',
       title: 'DETAILS',
       data: collapsedSections.details
         ? [SECTION_HEADER_MARKER]
         : [SECTION_HEADER_MARKER, 'details-content'],
     });

     return result;
   }, [isLoading, item, collapsedSections]);
   ```

3. Note: hero section has no title and no SECTION_HEADER_MARKER. It always renders its single content item.

**Files**:
- `app/items/[id]/index.tsx` (modify)

---

### Subtask T013 – Add collapsed state management

**Purpose**: Track which sections are collapsed/expanded with item-specific defaults.

**Steps**:
1. Add collapsed state:
   ```typescript
   const [collapsedSections, setCollapsedSections] = useState<Record<string, boolean>>({
     media: false,    // Default EXPANDED — images are important
     notes: true,     // Default collapsed
     details: true,   // Default collapsed — lots of rows
   });
   ```

2. Add toggle handler:
   ```typescript
   const handleToggleSection = useCallback((key: string) => {
     setCollapsedSections(prev => ({ ...prev, [key]: !prev[key] }));
   }, []);
   ```

**Files**:
- `app/items/[id]/index.tsx` (modify)

**Notes**: Hero is never in `collapsedSections` — it's always visible. The "Move Item" card at the bottom will be part of the details section (or a separate always-visible section after details).

---

### Subtask T014 – Replace AppScrollView with SectionList

**Purpose**: Swap the scroll container and set up SectionList rendering infrastructure.

**Steps**:
1. Remove `AppScrollView` import
2. Add `SectionList` import from `react-native`
3. Replace the main scroll container:

   **Before**:
   ```tsx
   <AppScrollView style={styles.scroll} contentContainerStyle={styles.content}>
     {isLoading ? (
       <AppText>Loading item…</AppText>
     ) : item ? (
       <>
         {/* hero card */}
         {/* error banner */}
         {/* MediaGallerySection */}
         {/* NotesSection */}
         {/* TitledCard Details */}
         {/* Move Item card */}
         {/* BottomSheetMenuList */}
       </>
     ) : (
       <AppText>Item not found.</AppText>
     )}
   </AppScrollView>
   ```

   **After**:
   ```tsx
   {isLoading ? (
     <View style={styles.loadingContainer}>
       <AppText variant="body">Loading item…</AppText>
     </View>
   ) : !item ? (
     <View style={styles.loadingContainer}>
       <AppText variant="body">Item not found.</AppText>
     </View>
   ) : (
     <SectionList
       sections={sections}
       renderItem={renderItem}
       renderSectionHeader={() => null}
       stickySectionHeadersEnabled={false}
       keyExtractor={(item, index) =>
         item === SECTION_HEADER_MARKER ? `header-${index}` : `item-${index}`
       }
       contentContainerStyle={styles.content}
       showsVerticalScrollIndicator={false}
       ListFooterComponent={listFooter}
     />
   )}
   ```

4. Set `stickySectionHeadersEnabled={false}` — item detail has no sticky sections
5. Use `renderSectionHeader={() => null}` — all headers use inline SECTION_HEADER_MARKER
6. Move loading and not-found states outside SectionList
7. Move `BottomSheetMenuList` outside SectionList (it's a modal, not scroll content)

**Files**:
- `app/items/[id]/index.tsx` (modify)

---

### Subtask T015 – Implement renderItem for item detail sections

**Purpose**: Route each section's content to the appropriate rendering based on section key.

**Steps**:
1. Implement `renderItem`:
   ```typescript
   const renderItem = useCallback(({ item: dataItem, section }: { item: any; section: ItemSection }) => {
     if (!item) return null;

     // Non-sticky section headers
     if (dataItem === SECTION_HEADER_MARKER) {
       if (!section.title) return null; // hero has no header
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
       case 'hero':
         return (
           <>
             {/* Hero card — name + transaction link */}
             <View style={[styles.card, getCardStyle(uiKitTheme, { padding: CARD_PADDING })]}>
               <View style={styles.heroHeader}>
                 <AppText variant="h2" style={styles.heroTitle}>
                   {item.name?.trim() || 'Untitled item'}
                 </AppText>
                 <View style={styles.heroSubtitle}>
                   {/* Transaction link or "None" */}
                 </View>
               </View>
             </View>
             {/* Error banner (conditional) */}
             {error ? (
               <View style={[styles.card, getCardStyle(uiKitTheme, { padding: CARD_PADDING })]}>
                 <AppText variant="caption" style={[styles.errorText, getTextSecondaryStyle(uiKitTheme)]}>
                   {error}
                 </AppText>
               </View>
             ) : null}
           </>
         );

       case 'media':
         return (
           <MediaGallerySection
             title="Images"
             hideTitle={true}
             attachments={item.images ?? []}
             maxAttachments={5}
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
         return <NotesSection notes={item.notes} expandable={true} />;

       case 'details':
         return (
           <TitledCard title="Details">
             <View style={styles.detailRows}>
               {/* Existing detail rows — Source, SKU, prices, space, budget category */}
               {/* Keep the same inline pattern for now — DetailRow component comes in WP06 */}
             </View>
           </TitledCard>
         );

       default:
         return null;
     }
   }, [item, error, collapsedSections, handleToggleSection, uiKitTheme,
       handleAddImage, handleRemoveImage, handleSetPrimaryImage]);
   ```

2. **Hero section**: Combine the hero card and error banner into one renderItem call. The error banner renders conditionally after the hero.

3. **Media section**: Use `hideTitle={true}` since `CollapsibleSectionHeader` already shows "IMAGES"

4. **Details section**: Keep the existing inline detail row pattern from `TitledCard`. The `DetailRow` component will replace these in WP06.

5. **Move Item card**: Add as a `ListFooterComponent` (it's not a collapsible section — it's a form that appears only for non-inventory scope):
   ```typescript
   const listFooter = useMemo(() => {
     if (scope === 'inventory') return null;
     return (
       <TitledCard title="Move item">
         <View style={styles.moveForm}>
           {/* TextInput fields for targetProjectId, targetCategoryId */}
         </View>
       </TitledCard>
     );
   }, [scope, targetProjectId, targetCategoryId, /* ... */]);
   ```

**Files**:
- `app/items/[id]/index.tsx` (modify)

---

### Subtask T016 – Preserve existing functionality and clean up

**Purpose**: Ensure all existing features work correctly in the new SectionList structure and clean up unused code.

**Steps**:
1. **Verify BottomSheetMenuList**: Ensure the item actions menu (`menuItems`) renders correctly outside the SectionList:
   ```tsx
   <Screen ...>
     <SectionList ... />
     <BottomSheetMenuList
       visible={menuVisible}
       onRequestClose={() => setMenuVisible(false)}
       items={menuItems}
       title="Item actions"
       showLeadingIcons={true}
     />
   </Screen>
   ```

2. **Verify header actions**: The bookmark button and status pill in `Screen.headerRight` remain unchanged — they're in the Screen header, not the scroll content.

3. **Clean up unused styles**:
   - Remove `scroll` style (no longer using AppScrollView)
   - Add `loadingContainer` style for loading/not-found states
   - Keep `content` style for SectionList contentContainerStyle
   - Verify padding and gap values match the original

4. **Verify imports**: Remove `AppScrollView` import, add `SectionList` import, add `CollapsibleSectionHeader` import

5. **Test scenarios**:
   - Navigate to item from inventory scope → all sections render
   - Navigate to item from project scope → "Move item" form visible
   - Collapse/expand Images section → MediaGallerySection hides/shows
   - Collapse/expand Details section → detail rows hide/show
   - Menu button → item actions menu opens
   - Bookmark toggle → works
   - Back navigation → correct target

**Files**:
- `app/items/[id]/index.tsx` (modify)

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Low risk overall | Low | Low | Item detail is the simplest screen (694 lines, no bulk ops, no sticky headers) |
| Error banner rendering | Low | Medium | Combine with hero in same renderItem call for correct layout |
| Move form loses functionality | Low | Low | Use ListFooterComponent to keep it outside collapsible sections |

## Review Guidance

1. Navigate to item detail from both inventory and project contexts
2. Collapse/expand each section — verify chevron behavior matches transaction detail
3. Default states: Images expanded, Notes collapsed, Details collapsed
4. MediaGallerySection: add/remove/set-primary images work
5. Menu: all actions work (edit, link/unlink transaction, move, delete)
6. Error states: loading, not found, error banner all render correctly
7. "Move item" form only visible for non-inventory scope

---

## Activity Log

- 2026-02-10T02:25:42Z – system – lane=planned – Prompt created.
