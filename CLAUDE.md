# Ledger Mobile

## Code Conventions

### Offline-First Coding Rules

Architecture spec: `.cursor/plans/firebase-mobile-migration/10_architecture/offline_first_principles.md`

These rules are non-negotiable. Violating them causes the app to hang when connectivity is poor.

1. **Never `await` Firestore write operations in UI code.** Use fire-and-forget with `.catch()` for error logging. Navigation and UI state updates happen immediately.
2. **All `create*` service functions must return document IDs synchronously** using pre-generated IDs via `doc(collection(...))`, not `addDoc`.
3. **Read operations in save/submit handlers must use cache-first mode** (`mode: 'offline'`). Server-first reads (`mode: 'online'`) are only for explicit pull-to-refresh.
4. **No "spinners of doom"** — never show loading states that block on server acknowledgment. If local data exists, show it immediately.
5. **Only actual byte uploads (Firebase Storage) and Firebase Auth operations may require connectivity.** All Firestore writes (including request-doc creation) must work offline.
6. **All Firestore write service functions must call `trackPendingWrite()`** after the write for sync status visibility.

## Detail Screen Patterns

Guide: `kitty-specs/005-detail-screen-polish/quickstart.md`

### Item List Components

- **SharedItemsList**: Full-featured item list with grouping, bulk selection (bottom bar + sheet), search/sort/filter
  - Supports `embedded={true}` mode for use in detail screens (hides top controls)
  - Pass `manager` from `useItemsManager` for external state control
  - Configure context-specific bulk actions via `bulkActions` prop
- **ItemsSection**: Deprecated - replace with `SharedItemsList` in embedded mode

### Section Spacing

All detail screens (transaction, item, space) must use consistent spacing:
- **Section gap** (between collapsible headers): `4px`
- **Item list gap** (between item cards): `10px`
- **Card padding**: `16px` (`CARD_PADDING`)

### Collapsible Section Titles

Use `Card` (not `TitledCard`) inside `CollapsibleSectionHeader` to avoid duplicate titles:
```typescript
<CollapsibleSectionHeader title="DETAILS">
  <Card>{/* content */}</Card>  {/* ✓ No duplicate title */}
</CollapsibleSectionHeader>
```

### Info Row Styling

Transaction and item detail hero cards use consistent info row pattern:
- Label: `<AppText variant="caption">` (secondary color)
- Value: `<AppText variant="body">` (primary color)
- Links: `style={{ color: theme.colors.primary }}` + `onPress`
- Separator: ` | ` (literal pipe with spaces, caption variant)
- Layout: `flexDirection: 'row'`, `alignItems: 'baseline'`
