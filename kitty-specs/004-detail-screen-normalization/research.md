# Research: Detail Screen Normalization

**Feature**: 004-detail-screen-normalization
**Date**: 2026-02-09

## 1. Current Screen Inventory

| Screen | File | Lines | Scroll | Sections |
|--------|------|-------|--------|----------|
| Transaction detail | `app/transactions/[id]/index.tsx` | ~1,622 | SectionList | Hero, Receipts, Other Images, Notes, Details, Taxes, Items, Audit |
| Item detail | `app/items/[id]/index.tsx` | ~694 | AppScrollView | Hero, Error, Media, Notes, Details |
| BI space detail | `app/business-inventory/spaces/[spaceId].tsx` | ~1,042 | AppScrollView + StickyHeader | Images, Notes, Items, Checklists |
| Project space detail | `app/project/[projectId]/spaces/[spaceId].tsx` | ~1,050 | AppScrollView + StickyHeader | Images, Notes, Items, Checklists |

**Combined total**: ~4,408 lines

## 2. Space Detail Consolidation Analysis

### Differences Between BI and Project Space Screens

| Aspect | Business Inventory | Project |
|--------|-------------------|---------|
| Params | `{ spaceId }` | `{ projectId, spaceId }` |
| Scope config | `createInventoryScopeConfig()` | `createProjectScopeConfig(projectId)` |
| Outside items hook | `scope: 'inventory', includeInventory: false, currentProjectId: null` | `scope: 'project', includeInventory: true, currentProjectId: projectId` |
| SpaceSelector | `projectId={null}` | `projectId={projectId}` |
| Picker tab labels | "In Business Inventory" / "Outside" | "Project" / "Outside" |
| Navigation (item detail) | `scope: 'inventory'`, no projectId | `scope: 'project'`, with projectId |
| Navigation (back) | `/business-inventory/spaces` | `/project/${projectId}?tab=spaces` |
| Navigation (edit) | `/business-inventory/spaces/${spaceId}/edit` | `/project/${projectId}/spaces/${spaceId}/edit` |
| Navigation (delete) | `router.replace('/business-inventory/spaces')` | `router.replace(/project/${projectId}?tab=spaces)` |

### Accidental Divergence (should be normalized)
- Minor style margins differ (sectionHeader.marginTop, bulkPanel.marginBottom present in BI only)
- Unused `checklists` style in Project version
- Unicode ellipsis inconsistency ("…" vs "\u2026")

### Consolidation Approach
- Shared `SpaceDetailContent` component accepting `projectId: string | null`
- Scope config derived from projectId presence: `projectId ? createProjectScopeConfig(projectId) : createInventoryScopeConfig()`
- Route builder functions parameterized on projectId
- Both route files become thin wrappers (~20 lines each)

**Estimated reduction**: ~1,000 lines eliminated

## 3. SectionList Migration Pattern (Reference: Transaction Detail)

### Section Structure
```typescript
type TransactionSection = {
  key: SectionKey;
  title?: string;
  data: any[];
  badge?: string;
};
```

### Collapsed State Management
```typescript
const [collapsedSections, setCollapsedSections] = useState<Record<string, boolean>>({
  receipts: false,    // Default EXPANDED
  otherImages: true,  // Default collapsed
  notes: true,
  details: true,
  items: true,
  audit: true,
});
```

### Key Pattern: SECTION_HEADER_MARKER
Non-sticky sections use a sentinel marker `'__sectionHeader__'` as the first data item. The `renderItem` callback checks for this marker and renders a `CollapsibleSectionHeader` inline. Only sections that need sticky behavior (items) use `renderSectionHeader`.

This is important: most sections should NOT have sticky headers. Only the items control bar benefits from sticking.

### CollapsibleSectionHeader API
```typescript
type CollapsibleSectionHeaderProps = {
  title: string;
  collapsed: boolean;
  onToggle: () => void;
  badge?: string;
  style?: ViewStyle;
};
```
- 44pt min height touch target
- Chevron icon (right when collapsed, down when expanded)
- Uppercase title with letter spacing
- Optional badge (right-aligned)

## 4. Media Handling Analysis

### Current Patterns

**Transaction + Item detail**: Use `MediaGallerySection` component
```typescript
<MediaGallerySection
  title="Receipts"
  attachments={transaction.receiptImages ?? []}
  maxAttachments={10}  // or 5 for items
  allowedKinds={['image', 'pdf']}
  onAddAttachment={handlers.handlePickReceiptAttachment}
  onRemoveAttachment={handlers.handleRemoveReceiptAttachment}
  onSetPrimary={handlers.handleSetPrimaryReceiptAttachment}
  emptyStateMessage="No receipts yet."
  pickerLabel="Add receipt"
  size="md"
  tileScale={1.5}
/>
```

**Space detail**: Uses raw `ThumbnailGrid` + `ImageGallery` + `ImagePickerButton`
- `ThumbnailGrid`: renders image tiles with primary badge, delete, set-primary actions
- `ImageGallery`: full-screen lightbox modal
- `ImagePickerButton`: shown when `images.length < 50`
- Three separate handlers: `handleAddImage`, `handleRemoveImage`, `handleSetPrimaryImage`

### MediaGallerySection Capabilities
- **No hardcoded image cap** — `maxAttachments` prop defaults to 5 but is fully configurable
- Internally uses `ThumbnailGrid` + `ImageGallery`
- Supports `allowedKinds: ['image', 'pdf']`
- Handler signatures: `(localUri, kind) => void | Promise<void>` (fire-and-forget compatible)
- Can hide title via `hideTitle` prop

### Migration Plan
- Replace space detail's manual media rendering with `MediaGallerySection`
- Set `maxAttachments` to a high number (e.g., 100 or remove cap) for spaces
- Adapt space handlers to match `MediaGallerySection`'s handler signatures
- Space-specific: `handleAddImage` saves locally, updates space doc, enqueues upload — same pattern as transaction/item

## 5. Items Management Duplication Analysis

### Common State Across Screens

| State Variable | Transaction Detail | Space Detail | SharedItemsList |
|---------------|-------------------|--------------|-----------------|
| `searchQuery` | `string` | `string` | `string` (debounced) |
| `showSearch` | `boolean` | `boolean` | `boolean` |
| `sortMode` | 6 modes + price | 4 modes | 4 modes |
| `filterMode` | 6 modes | 4 modes | 10+ modes |
| `selectedIds` | `Set<string>` | `string[]` | `string[]` |
| `bulkMenuVisible` | `boolean` | N/A (inline) | `boolean` |
| `sortMenuVisible` | `boolean` | `boolean` | `boolean` |
| `filterMenuVisible` | `boolean` | `boolean` | `boolean` |

### Common Handlers
- Item selection toggle
- Select all / clear selection
- Search filtering (case-insensitive on name, sku, source, notes)
- Sort application
- Filter application
- Filtered + sorted items computation

### Screen-Specific
- **Transaction**: price sort, SKU bulk assign, status bulk assign, duplicate item, item conflict resolution
- **Space**: bulk move between spaces, bulk remove from space, item picker with scope tabs
- **SharedItemsList**: project allocation/sell, grouped items, persistent list state

### Extraction Boundary
The `useItemsManager` hook should own:
1. Selection state + handlers (toggle, select all, clear)
2. Search/sort/filter state + filtered items computation
3. Menu visibility state
4. Common sort/filter mode definitions

The `ItemsSection` component should render:
1. `CollapsibleSectionHeader` (for SectionList integration)
2. `ItemsListControlBar` (with search, sort, filter, add actions)
3. Item list (using `ItemCard` for each)
4. Bulk action panel (when items selected)

Screen-specific bulk actions are passed as config.

## 6. Detail Row Pattern Analysis

### Current Rendering (inline in each screen)
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

### Common Style
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

### Proposed DetailRow API
```typescript
type DetailRowProps = {
  label: string;
  value: string | React.ReactNode;
  showDivider?: boolean;  // default true
  onPress?: () => void;   // for tap-to-copy or navigation
};
```

## 7. Decisions

| Decision | Choice | Rationale | Alternatives Considered |
|----------|--------|-----------|------------------------|
| Migration order | Top-down: consolidate spaces first | Highest LOC reduction, lowest risk (near-identical screens) | Bottom-up: extract components first |
| Space consolidation | Thin route wrappers + shared `SpaceDetailContent` | Preserves URL structure, minimal routing changes | Single route with param differentiation |
| Items management API | `useItemsManager` hook + `ItemsSection` component | Clean separation of state and presentation, composable | Single compound component (less flexible) |
| Media normalization | Adopt existing `MediaGallerySection` as-is | Already feature-complete, no image cap in component | Build new unified component |
| SectionList sticky strategy | Only items control bar sticks; other sections use SECTION_HEADER_MARKER pattern | Matches transaction detail reference implementation | All headers sticky (visually cluttered) |
| Space image cap | Remove cap / set very high (100+) | User needs many images on spaces, component has no internal cap | Keep default 5 (too restrictive for spaces) |
