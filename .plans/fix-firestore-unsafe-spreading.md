# Fix Systemic Firestore Data Spreading Safety Issue

## Context

**Problem:** "Cannot convert undefined value to object" errors are occurring in space edit and transaction detail screens, blocking users from viewing/editing entities.

**Root Cause:** 39 instances across 12 service files use unsafe spreading of `snapshot.data()` with type casts that bypass TypeScript's undefined checking:
```typescript
// UNSAFE PATTERN (used everywhere):
{ ...(snapshot.data() as object), id: snapshot.id } as EntityType
```

When offline-first fire-and-forget writes create race conditions, `onSnapshot` can fire with `exists=true` but `data()=undefined` during transient merge operations. Spreading undefined causes the runtime error.

**Safe Pattern:** `itemsService.ts` already implements the correct defensive normalization:
```typescript
function normalizeItemFromFirestore(raw: unknown, id: string): Item {
  const data = raw && typeof raw === 'object' ? (raw as Record<string, unknown>) : {};
  return { ...(data as object), id } as Item;
}
```

This validates data before spreading, preventing the error.

**Why This Matters Now:** Recent offline-first improvements made race conditions more likely by eliminating blocking awaits, causing a pre-existing bug to surface frequently.

---

## Implementation Strategy: Phased Approach

Fix 39 instances across 12 files in 3 phases to minimize risk and enable incremental testing.

### Phase 1: Critical User Paths (Priority: HIGH)
**Files:** `spacesService.ts` (4 instances), `transactionsService.ts` (3 instances)
**Impact:** Fixes confirmed bugs in space edit and transaction detail screens
**Time:** 30 minutes

### Phase 2: Generic Repository (Priority: HIGH)
**Files:** `repository.ts` (7 instances)
**Impact:** Fixes all repository-based services (unknown scope but potentially wide)
**Requires:** Architectural solution for generic `<T>` type
**Time:** 45 minutes

### Phase 3: Remaining Services (Priority: MEDIUM)
**Files:** 9 additional service files (25 instances total)
**Impact:** Prevents future race condition errors across all entities
**Time:** 2 hours

---

## Phase 1: Fix Critical User Paths

### File: `src/data/spacesService.ts`

**1. Add normalizer function** after type definitions (after line 40):
```typescript
function normalizeSpaceFromFirestore(raw: unknown, id: string): Space {
  const data = raw && typeof raw === 'object' ? (raw as Record<string, unknown>) : {};
  return { ...(data as object), id } as Space;
}
```

**2. Replace 4 unsafe instances:**
- **Line ~62** in `subscribeToSpaces`:
  ```typescript
  // OLD:
  const next = snapshot.docs.map((doc) => ({ ...(doc.data() as object), id: doc.id } as Space));
  // NEW:
  const next = snapshot.docs.map((doc) => normalizeSpaceFromFirestore(doc.data(), doc.id));
  ```

- **Line ~91** in `refreshSpaces` (cache/server path):
  ```typescript
  // OLD:
  return snapshot.docs.map((doc: any) => ({ ...(doc.data() as object), id: doc.id } as Space));
  // NEW:
  return snapshot.docs.map((doc: any) => normalizeSpaceFromFirestore(doc.data(), doc.id));
  ```

- **Line ~97** in `refreshSpaces` (fallback path):
  ```typescript
  // OLD:
  return snapshot.docs.map((doc: any) => ({ ...(doc.data() as object), id: doc.id } as Space));
  // NEW:
  return snapshot.docs.map((doc: any) => normalizeSpaceFromFirestore(doc.data(), doc.id));
  ```

- **Line ~178** in `subscribeToSpace`:
  ```typescript
  // OLD:
  onChange({ ...(snapshot.data() as object), id: snapshot.id } as Space);
  // NEW:
  onChange(normalizeSpaceFromFirestore(snapshot.data(), snapshot.id));
  ```

### File: `src/data/transactionsService.ts`

**1. Add normalizer function** after type definitions (after line 43):
```typescript
function normalizeTransactionFromFirestore(raw: unknown, id: string): Transaction {
  const data = raw && typeof raw === 'object' ? (raw as Record<string, unknown>) : {};
  return { ...(data as object), id } as Transaction;
}
```

**2. Replace 3 unsafe instances:**
- **Line ~109** in `getTransaction` (cache/server return)
- **Line ~118** in `getTransaction` (fallback return)
- **Line ~138** in `subscribeToTransaction` (onSnapshot callback)

Pattern: `normalizeTransactionFromFirestore(snapshot.data(), snapshot.id)`

---

## Phase 2: Fix Generic Repository

### File: `src/data/repository.ts`

**Challenge:** Uses `<T extends { id: string }>` - can't know entity type at compile time.

**Solution:** Add optional normalizer parameter with safe default.

**1. Update constructor** (around line 21):
```typescript
constructor(
  private collectionPath: string,
  private mode: RepositoryMode = 'online',
  private normalizer?: (raw: unknown, id: string) => T
) {}
```

**2. Add private normalizeDoc method** (after constructor):
```typescript
private normalizeDoc(raw: unknown, id: string): T {
  if (this.normalizer) {
    return this.normalizer(raw, id);
  }
  // Default: safe defensive spreading
  const data = raw && typeof raw === 'object' ? (raw as Record<string, unknown>) : {};
  return { ...(data as object), id } as T;
}
```

**3. Replace 7 unsafe instances** with `this.normalizeDoc(data, id)`:
- **Line ~99**: `list()` map callback
- **Line ~110**: `get()` return statement
- **Line ~135**: `listByUser()` map callback
- **Line ~156**: `subscribe()` cache onChange callback
- **Line ~174**: `subscribe()` onSnapshot onChange callback
- **Line ~200**: `subscribeList()` cache map callback
- **Line ~212**: `subscribeList()` onSnapshot map callback

**4. Update factory function signature** (around line 227):
```typescript
export function createRepository<T extends { id: string }>(
  collectionPath: string,
  mode: RepositoryMode = 'online',
  normalizer?: (raw: unknown, id: string) => T
): Repository<T> {
  return new FirestoreRepository<T>(collectionPath, mode, normalizer);
}
```

**Benefits:**
- Backward compatible (normalizer optional, safe default)
- Allows callers to inject entity-specific normalization when needed
- All 7 instances fixed with single pattern

---

## Phase 3: Remaining Services

Apply same pattern to 9 additional files (25 instances total):

| Service File | Entity Type | Instances | Special Handling |
|--------------|-------------|-----------|------------------|
| `budgetCategoriesService.ts` | BudgetCategory | 4 | None |
| `projectBudgetCategoriesService.ts` | ProjectBudgetCategory | 4 | None |
| `projectPreferencesService.ts` | ProjectPreferences | 2 | Validate `pinnedBudgetCategoryIds` array |
| `accountPresetsService.ts` | AccountPresets | 3 | Validate `budgetCategoryOrder` array |
| `spaceTemplatesService.ts` | SpaceTemplate | 3 | None |
| `scopedListData.ts` | Generic | 3 | None |
| `invitesService.ts` | Invite | 3 | None |
| `accountMembersService.ts` | AccountMember | 1 | None |
| `budgetProgressService.ts` | BudgetProgress | 2 | None |

**Pattern for each:**
1. Add `normalize<Entity>FromFirestore(raw: unknown, id: string)` function after type definitions
2. Replace all unsafe spreads with normalizer calls
3. Add entity-specific transformations where noted (array validation)

**Array Validation Examples:**

For `ProjectPreferences` (ensure array default):
```typescript
function normalizeProjectPreferencesFromFirestore(raw: unknown, id: string): ProjectPreferences {
  const data = raw && typeof raw === 'object' ? (raw as Record<string, unknown>) : {};
  const pinnedIds = Array.isArray(data.pinnedBudgetCategoryIds)
    ? data.pinnedBudgetCategoryIds
    : [];
  return { ...(data as object), id, pinnedBudgetCategoryIds: pinnedIds } as ProjectPreferences;
}
```

For `AccountPresets` (preserve null):
```typescript
function normalizeAccountPresetsFromFirestore(raw: unknown, id: string): AccountPresets {
  const data = raw && typeof raw === 'object' ? (raw as Record<string, unknown>) : {};
  const order = Array.isArray(data.budgetCategoryOrder)
    ? data.budgetCategoryOrder
    : (data.budgetCategoryOrder === null ? null : []);
  return { ...(data as object), id, budgetCategoryOrder: order } as AccountPresets;
}
```

---

## Verification

### 1. Unit Tests

Create `src/data/__tests__/normalizerSafety.test.ts`:
```typescript
describe('normalizeFromFirestore safety', () => {
  it('handles undefined data without throwing', () => {
    const result = normalizeSpaceFromFirestore(undefined, 'test-id');
    expect(result.id).toBe('test-id');
    expect(result).toBeDefined();
  });

  it('handles null data', () => {
    const result = normalizeSpaceFromFirestore(null, 'test-id');
    expect(result.id).toBe('test-id');
  });

  it('handles valid data', () => {
    const input = { name: 'Test', accountId: 'acc1', projectId: null };
    const result = normalizeSpaceFromFirestore(input, 'test-id');
    expect(result.id).toBe('test-id');
    expect(result.name).toBe('Test');
  });

  it('handles non-object primitives', () => {
    expect(() => normalizeSpaceFromFirestore(42, 'id')).not.toThrow();
    expect(() => normalizeSpaceFromFirestore('string', 'id')).not.toThrow();
  });
});
```

Run tests with: `npm test src/data/__tests__/normalizerSafety.test.ts`

### 2. Manual Testing - Race Condition Reproduction

**Before fix (should crash):**
1. Open space detail screen (`/business-inventory/spaces/[spaceId]`)
2. Tap "Edit" button
3. While edit screen loads, have another user archive the space
4. Expected: "Cannot convert undefined value to object" error

**After fix (should handle gracefully):**
1. Same steps as above
2. Expected: Edit screen handles null/undefined gracefully, no crash

### 3. Regression Testing

Verify all detail/edit screens still work:
- ✓ Space edit screen: `/app/business-inventory/spaces/[spaceId]/edit.tsx`
- ✓ Transaction detail: `/app/transactions/[id]/index.tsx`
- ✓ Item detail (already safe, no regression): `/app/items/[id]/index.tsx`
- ✓ All subscription updates work correctly
- ✓ Cache-first prelude + onSnapshot pattern still works

Test in both online and offline modes, with slow network throttling (3G).

---

## CLAUDE.md Documentation Update

Add new section after "Offline-First Coding Rules":

```markdown
### Firestore Data Normalization Rules

**All `snapshot.data()` calls must use defensive normalization** to prevent race condition errors.

**Problem:** Type casting `snapshot.data() as object` bypasses TypeScript's undefined checking. During offline-first race conditions, `onSnapshot` can fire with `exists=true` but `data()=undefined`, causing "Cannot convert undefined to object" runtime errors.

**Required Pattern:**

Every service file must define entity-specific normalizer functions:

```typescript
function normalizeEntityFromFirestore(raw: unknown, id: string): EntityType {
  const data = raw && typeof raw === 'object' ? (raw as Record<string, unknown>) : {};
  // Add entity-specific transformations here (e.g., legacy field migrations, array validation)
  return { ...(data as object), id } as EntityType;
}
```

**Replace all unsafe patterns:**
```typescript
// UNSAFE - DO NOT USE:
{ ...(snapshot.data() as object), id: snapshot.id } as EntityType

// SAFE - REQUIRED:
normalizeEntityFromFirestore(snapshot.data(), snapshot.id)
```

**Reference:** `src/data/itemsService.ts` lines 65-79 (includes legacy field migration example)

**Generic repository:** Use parameterized normalizer in `createRepository<T>(path, mode, normalizer)` third argument.
```

---

## Critical Files

**Phase 1 (immediate user impact):**
- `src/data/spacesService.ts` - 4 instances
- `src/data/transactionsService.ts` - 3 instances
- `src/data/itemsService.ts` - Reference for safe pattern (read-only)

**Phase 2 (architectural):**
- `src/data/repository.ts` - 7 instances

**Phase 3 (comprehensive):**
- `src/data/budgetCategoriesService.ts` - 4 instances
- `src/data/projectBudgetCategoriesService.ts` - 4 instances
- `src/data/projectPreferencesService.ts` - 2 instances (+ array validation)
- `src/data/accountPresetsService.ts` - 3 instances (+ array validation)
- `src/data/spaceTemplatesService.ts` - 3 instances
- `src/data/scopedListData.ts` - 3 instances
- `src/data/invitesService.ts` - 3 instances
- `src/data/accountMembersService.ts` - 1 instance
- `src/data/budgetProgressService.ts` - 2 instances

**Documentation:**
- `CLAUDE.md` - Add normalization rules section
- `.troubleshooting/space-edit-undefined-spread.md` - Mark resolved when complete

---

## Summary

**Scope:** 39 unsafe spreads across 12 service files
**Time:** ~3.5 hours total (phased over multiple sessions)
**Risk:** Low - pattern is proven safe in itemsService, backward compatible
**Impact:** Eliminates "Cannot convert undefined value to object" errors across all entities
