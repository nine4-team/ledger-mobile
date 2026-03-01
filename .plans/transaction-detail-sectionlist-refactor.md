# Transaction Detail Screen: SectionList Refactor with Collapsible Sections

## Context

The transaction detail screen (`app/transactions/[id]/index.tsx`) currently uses an `AppScrollView` with a fragile manual sticky header implementation. We need to refactor it to use React Native's `SectionList` component, which:

1. Provides native sticky section headers (fixes the current sticky toolbar issues)
2. Enables collapsible sections (new UX requirement)
3. Eliminates dual control bar instance problems
4. Follows React Native best practices

## Current State

**File:** `app/transactions/[id]/index.tsx` (~1670 lines)

**Current Layout:**
```
<Screen>
  <AppScrollView>
    - Hero card (title, total, dates, status)
    - Media gallery section
    - Notes section
    - Details section (date, payment method, vendor, etc.)
    - Items section with ItemsListControlBar (sticky toolbar)
      - Item cards (mapped from filteredAndSortedItems)
    - Transaction audit card (created/modified timestamps)
  </AppScrollView>
</Screen>
```

**Current Sticky Implementation:** Manual `onScroll` + conditional floating clone (H10 in troubleshooting log)

**Issues:**
- Two control bar instances (fragile state sync)
- Manual scroll/layout tracking
- No section collapsibility
- ~1670 lines in one file

## Goals

### Primary
1. **Replace `AppScrollView` with `SectionList`** using `stickySectionHeadersEnabled`
2. **Make sections collapsible** with expand/collapse affordance
3. **Default collapsed sections:** Taxes, Itemization, Details, Notes, Other Images (any non-primary images)
4. **Single control bar instance** as a section header (no duplication)

### Secondary
1. **Improve maintainability** - extract section renderers to separate components
2. **Preserve all functionality** - search, filter, sort, bulk selection, media upload, etc.
3. **Match current visual design** - card styles, spacing, colors

## Proposed Architecture

### Section Structure

```typescript
type TransactionSection =
  | { key: 'hero',   data: [Transaction] }
  | { key: 'media',  data: [AttachmentRef[]], collapsible: boolean }
  | { key: 'notes',  data: [string | undefined], collapsible: boolean }
  | { key: 'details', data: [Transaction], collapsible: boolean }
  | { key: 'items',  data: ScopedItem[] }  // sticky header with control bar
  | { key: 'audit',  data: [Transaction] }
```

**Collapsible state:** `Record<string, boolean>` (e.g., `{ media: false, notes: true }`)

### Component Breakdown

```
src/components/
  CollapsibleSectionHeader.tsx   - Shared component: title + chevron + optional badge/count
                                   Used as renderSectionHeader for every collapsible section

app/transactions/[id]/
  index.tsx                      - Main screen with SectionList orchestration
  sections/
    HeroSection.tsx              - Transaction title, total, dates, status badge
    MediaSection.tsx             - Gallery with primary + other images
    NotesSection.tsx             - Notes display/edit
    DetailsSection.tsx           - Payment method, vendor, location
    ItemsSection.tsx             - Item cards (control bar is the section header)
    AuditSection.tsx             - Created/modified timestamps
```

`CollapsibleSectionHeader` lives in `src/components/` (not transaction-specific) so other detail screens can reuse it.

### Key APIs

**`SectionList` props:**
- `stickySectionHeadersEnabled={true}` - native sticky headers
- `renderSectionHeader` - control bar for items, collapse headers for others
- `sections` - computed from transaction data + collapsed state

**Collapsed sections logic:**
- Only render `data: []` for collapsed sections (don't render content)
- Section header shows collapse affordance (chevron icon)
- `onPress` toggles collapsed state

## Design Decisions (Resolved)

### Collapsible Sections
All sections are collapsible except Hero (top card). Use a shared `CollapsibleSectionHeader` component for every collapsible section — same expand/collapse affordance, same touch target, same animation.

**Not collapsible:** Hero (always visible)
**Default collapsed:** Media, Notes, Details, Taxes, Itemization, Items
**Default expanded:** Audit

Items section: when expanded, the control bar (section header) sticks via `stickySectionHeadersEnabled`. When collapsed, only the section header shows with item count.

### Section Header Design
Match the existing `TitledCard` component pattern (bold text + chevron icon). Touch target min 44pt.

### Collapsed State Persistence
Local state only (resets on navigation). Can add AsyncStorage persistence later if needed.

### Section Order
Fixed order: Hero → Media → Notes → Details → Items → Audit

## Implementation Plan (Suggested Phases)

### Phase 1: SectionList Foundation (no collapsibility yet)
- Extract current content into section components
- Replace AppScrollView with SectionList
- Implement sticky control bar as section header
- Verify all functionality works (search, filter, sort, bulk actions)
- Remove dual control bar implementation

### Phase 2: Add Collapsibility
- Implement CollapsibleSectionHeader component
- Add collapsed state management
- Wire up collapse/expand handlers
- Set default collapsed sections
- Test interaction with sticky headers

### Phase 3: Polish
- Extract shared section logic to hooks
- Add expand/collapse animations (optional)
- Add "Expand All" / "Collapse All" menu actions (optional)
- Persist collapsed state (optional)

## Files to Reference

**Current implementation:**
- `app/transactions/[id]/index.tsx` - main screen (1670 lines)
- `src/components/ItemsListControlBar.tsx` - sticky control bar
- `src/components/ItemCard.tsx` - item rendering
- `src/components/MediaGallerySection.tsx` - media gallery
- `src/components/NotesSection.tsx` - notes display/edit
- `.troubleshooting/transaction-items-sticky-toolbar-scroll.md` - current sticky header issues

**Similar patterns in codebase:**
- Check for existing `SectionList` usage (currently none found)
- Check for collapsible section patterns elsewhere in app

## Success Criteria

- [ ] SectionList renders all transaction sections correctly
- [ ] Items control bar sticks when scrolling (no dual instances)
- [ ] User can collapse/expand sections via header tap
- [ ] Shared `CollapsibleSectionHeader` component in `src/components/`
- [ ] All sections except Hero are collapsible
- [ ] Default collapsed: Media, Notes, Details, Taxes, Itemization, Items
- [ ] Default expanded: Audit
- [ ] All existing functionality preserved (search, filter, bulk, media upload)
- [ ] Scroll performance is smooth (no jank)
- [ ] Visual design matches current screen
- [ ] Code is more maintainable (~300 lines in index.tsx, rest in section components)

## Open Questions (for implementer to decide)

1. Should sections with no content (e.g., empty notes) be hidden entirely or shown as collapsed?
2. Expand/collapse animation style (LayoutAnimation vs Animated vs none)

## Risks & Mitigations

**Risk:** SectionList performance with many items
**Mitigation:** Use `getItemLayout` for fixed-height items, test with 50+ items

**Risk:** Search/filter state gets out of sync with SectionList data
**Mitigation:** Compute sections from filtered data in useMemo, single source of truth

**Risk:** Sticky header z-index conflicts with Screen header
**Mitigation:** Test thoroughly, adjust z-index if needed (Screen header is z:1)

**Risk:** Breaking existing deep links / navigation state
**Mitigation:** Keep same route structure, only change internal rendering

---

## Next Steps

1. **Review this plan** - does the architecture align with requirements?
2. **Answer open questions** - get clarity on UX decisions
3. **Create detailed task breakdown** - Phase 1, 2, 3 subtasks
4. **Implement Phase 1** - get SectionList working with current UX
5. **Implement Phase 2** - add collapsibility
6. **Test thoroughly** - especially sticky behavior + state management
