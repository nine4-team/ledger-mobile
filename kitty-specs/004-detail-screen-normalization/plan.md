# Implementation Plan: Detail Screen Normalization

**Branch**: `004-detail-screen-normalization` | **Date**: 2026-02-09 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `kitty-specs/004-detail-screen-normalization/spec.md`

## Summary

Extract shared patterns from the transaction detail SectionList refactor (already complete) and apply them across all 4 detail screens. The work consolidates the two near-identical space detail screens into one shared component, migrates remaining screens to SectionList with collapsible sections, extracts a `useItemsManager` hook + `ItemsSection` component for shared items management, normalizes media handling to `MediaGallerySection` everywhere, and introduces a `DetailRow` component for consistent key-value rendering.

**Approach**: Top-down migration. Consolidate space screens first (highest LOC win), then normalize remaining screens using the two reference implementations (transaction detail + consolidated space detail).

## Technical Context

**Language/Version**: TypeScript 5.x, React Native (Expo)
**Primary Dependencies**: React Native SectionList, Expo Router, Firebase/Firestore
**Storage**: Firebase Firestore (offline-first, fire-and-forget writes)
**Testing**: Manual testing (no automated test suite for UI screens)
**Target Platform**: iOS + Android (Expo managed workflow)
**Project Type**: Mobile
**Performance Goals**: 60fps scrolling, instant navigation (no loading gates on Firestore writes)
**Constraints**: Offline-capable, all Firestore writes fire-and-forget, cache-first reads in handlers
**Scale/Scope**: 4 detail screens, ~4,408 LOC → target ~3,000 LOC (30%+ reduction)

## Constitution Check

*No constitution file found. Skipped.*

## Project Structure

### Documentation (this feature)

```
kitty-specs/004-detail-screen-normalization/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output (component interfaces)
└── tasks.md             # Phase 2 output (/spec-kitty.tasks)
```

### Source Code (repository root)

```
src/
├── components/
│   ├── CollapsibleSectionHeader.tsx  # Existing (no changes)
│   ├── MediaGallerySection.tsx       # Existing (no changes)
│   ├── ItemsListControlBar.tsx       # Existing (no changes)
│   ├── ItemCard.tsx                  # Existing (no changes)
│   ├── SharedItemPicker.tsx          # Existing (no changes)
│   ├── NotesSection.tsx              # Existing (no changes)
│   ├── DetailRow.tsx                 # NEW - shared detail row component
│   ├── ItemsSection.tsx              # NEW - shared items section component
│   └── SpaceDetailContent.tsx        # NEW - consolidated space detail
├── hooks/
│   └── useItemsManager.ts           # NEW - shared items state hook
└── ...

app/
├── transactions/[id]/
│   └── index.tsx                     # MODIFY - adopt DetailRow, adopt ItemsSection
├── items/[id]/
│   └── index.tsx                     # MODIFY - migrate to SectionList, adopt DetailRow
├── business-inventory/spaces/
│   └── [spaceId].tsx                 # MODIFY - thin wrapper importing SpaceDetailContent
└── project/[projectId]/spaces/
    └── [spaceId].tsx                 # MODIFY - thin wrapper importing SpaceDetailContent
```

**Structure Decision**: Existing mobile project structure. New shared components go in `src/components/` and `src/hooks/`. Route files in `app/` remain in place but become thin wrappers where consolidation applies.

## Engineering Alignment

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Migration strategy | Top-down: consolidate spaces first | Highest LOC reduction (~1,000 lines), lowest risk |
| Space consolidation | Thin route wrappers + shared `SpaceDetailContent` | Preserves URL structure, minimal routing risk |
| Items management | `useItemsManager` hook + `ItemsSection` component | Clean state/presentation separation, composable for future screens |
| Media normalization | Adopt existing `MediaGallerySection` for spaces | Already feature-complete, no internal image cap |
| Space image limit | Set `maxAttachments` high (100+) | Spaces need many images; component supports arbitrary limits |
| SectionList stickiness | Only items control bar sticks (others use SECTION_HEADER_MARKER) | Matches transaction detail pattern, avoids visual clutter |
| Detail rows | New `DetailRow` component | Simple presentational extraction, ensures visual consistency |

## Implementation Phases

### Phase 1: Space Consolidation + SectionList Migration (P1)

**Goal**: Eliminate space duplication, establish collapsible sections on all screens.

#### WP-01: Consolidate Space Detail Screens
1. Create `src/components/SpaceDetailContent.tsx` accepting `{ projectId: string | null, spaceId: string }`
2. Extract shared logic from `app/business-inventory/spaces/[spaceId].tsx` (reference copy)
3. Parameterize scope config: `projectId ? createProjectScopeConfig(projectId) : createInventoryScopeConfig()`
4. Parameterize navigation routes via helper functions
5. Parameterize picker tab labels based on projectId
6. Replace space media (ThumbnailGrid/ImageGallery/ImagePickerButton) with `MediaGallerySection`
7. Reduce both route files to thin wrappers (~20 lines each)
8. Normalize style inconsistencies (margins, unused styles)

#### WP-02: Migrate Space Detail to SectionList
1. Migrate `SpaceDetailContent` from AppScrollView to SectionList
   - Define sections: media, notes, items, checklists
   - Add CollapsibleSectionHeader to each section
   - Items section uses `renderSectionHeader` (sticky), others use SECTION_HEADER_MARKER pattern
   - Replace StickyHeader with native SectionList sticky behavior

#### WP-03: Migrate Item Detail to SectionList
1. Migrate `app/items/[id]/index.tsx` from AppScrollView to SectionList
   - Define sections: hero (non-collapsible), media, notes, details
   - Add CollapsibleSectionHeader to collapsible sections
   - Configure per-screen default collapsed states

### Phase 2: Shared Items Management (P2)

**Goal**: Extract duplicated items management logic into reusable hook + component.

#### WP-04: Extract useItemsManager Hook
1. Create `src/hooks/useItemsManager.ts`
2. Move common state: search, sort, filter, selection
3. Move common logic: filtered+sorted items computation, selection handlers
4. Parameterize: sort modes, filter modes, search fields, custom filter function

#### WP-05: Create ItemsSection Component
1. Create `src/components/ItemsSection.tsx`
2. Render: CollapsibleSectionHeader, ItemsListControlBar, item list, bulk action panel
3. Accept screen-specific bulk actions as config
4. Integrate with useItemsManager hook
5. Refactor space detail + transaction detail to use ItemsSection

### Phase 3: Detail Row Extraction (P3)

#### WP-06: Create DetailRow Component + Normalize Media
1. Create `src/components/DetailRow.tsx`
2. Refactor transaction detail DetailsSection to use DetailRow
3. Refactor item detail Details card to use DetailRow
4. Verify MediaGallerySection integration on consolidated space screen (no cap issues)

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Space consolidation breaks navigation | Low | High | Both route files remain; only content component changes |
| SectionList scroll performance with many items | Low | Medium | Transaction detail already validated; same approach |
| Items hook API doesn't fit all screens | Medium | Medium | Design API from research on all 3 consumers; keep escape hatches |
| Media handler signature mismatch | Low | Low | MediaGallerySection handlers already fire-and-forget compatible |
| Collapsible state lost on re-render | Low | Medium | Use same useState pattern proven in transaction detail |

## File Impact Summary

| File | Action | Priority |
|------|--------|----------|
| `src/components/SpaceDetailContent.tsx` | CREATE | P1 |
| `src/components/DetailRow.tsx` | CREATE | P3 |
| `src/components/ItemsSection.tsx` | CREATE | P2 |
| `src/hooks/useItemsManager.ts` | CREATE | P2 |
| `app/business-inventory/spaces/[spaceId].tsx` | REDUCE to wrapper | P1 |
| `app/project/[projectId]/spaces/[spaceId].tsx` | REDUCE to wrapper | P1 |
| `app/items/[id]/index.tsx` | MODIFY (SectionList migration) | P1 |
| `app/transactions/[id]/index.tsx` | MODIFY (adopt shared components) | P2-P3 |
