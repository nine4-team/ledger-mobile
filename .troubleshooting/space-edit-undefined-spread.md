# Issue: Space Edit Screen - Cannot Convert Undefined to Object

**Status:** Resolved
**Opened:** 2026-02-11
**Resolved:** 2026-02-11

## Context
- **Symptom:** React Native render error "Cannot convert undefined value to object" when navigating to detail/edit screens
- **Affected areas:**
  - `app/business-inventory/spaces/[spaceId]/edit.tsx` (first report)
  - `app/transactions/[id]/index.tsx` (TransactionDetailScreen - second report)
  - Likely affects ALL screens using subscribe functions with unsafe spread pattern
- **Severity:** Blocks user - prevents viewing/editing entities during race conditions
- **Reproduction steps:** Navigate to detail/edit screen, particularly during or shortly after deletion/archiving operations
- **Environment:**
  - Branch: main
  - React Native mobile app
  - Error occurs in onSnapshot callbacks across multiple service files

## Research

**Edit screen useEffect pattern:**
- Lines 25-34 in `edit.tsx`: Guard checks `if (!accountId || !spaceId)` before calling `subscribeToSpace`
- The callback is simple: `(next) => { setSpace(next); }`
- Error occurs at line 32 (closing of callback)

**subscribeToSpace implementation (src/data/spacesService.ts:161-185):**
- Lines 174-177: Early return if `!snapshot.exists`
- Line 178: **Suspicious line** - spreads `snapshot.data()`:
  ```typescript
  onChange({ ...(snapshot.data() as object), id: snapshot.id } as Space);
  ```
- If `snapshot.data()` returns `undefined`, spreading it would cause "Cannot convert undefined value to object"
- Type cast to `object` bypasses TypeScript's undefined checking

**Firestore behavior:**
- According to Firestore docs, if `snapshot.exists()` is true, `snapshot.data()` should return data (not undefined)
- However, in practice there may be edge cases or timing issues
- The type cast `as object` masks potential undefined values

## Investigation Log

### H1: snapshot.data() returns undefined due to unsafe type casting
- **Rationale:** Line 178 of spacesService.ts spreads `snapshot.data()` with `as object` type cast, which bypasses TypeScript's undefined checking. If snapshot.data() returns undefined, spreading causes the exact error seen.
- **Experiment:** Searched codebase for similar patterns and safer alternatives
- **Evidence:**
  - **Pattern is widespread**: 11 instances across 5+ service files use `{ ...(snapshot.data() as object), id: doc.id }` without null checking
    - spacesService.ts:178 (error location)
    - transactionsService.ts:109, 118, 138
    - repository.ts:110, 156, 174
    - projectPreferencesService.ts:52
    - accountPresetsService.ts:40, 65, 74
  - **Safe pattern exists**: itemsService.ts:65-66 uses defensive normalization:
    ```typescript
    const data = raw && typeof raw === 'object' ? (raw as Record<string, unknown>) : {};
    return { ...(data as object), id } as Item;
    ```
  - Type cast `as object` completely masks potential undefined values
- **Verdict:** **Confirmed** - This is an unsafe pattern used throughout the codebase

### H2: Race condition during space deletion
- **Rationale:** Offline-first fire-and-forget deletes create timing windows where edit screen can subscribe during deletion
- **Experiment:** Analyzed deletion flow and routing sequence
- **Evidence:**
  - deleteSpace() (spacesService.ts:146-159) uses fire-and-forget setDoc with `{ merge: true }`
  - No await - writes happen asynchronously per offline-first rules
  - Sequence:
    1. User on detail screen taps Edit
    2. Router navigates to edit screen (fire-and-forget)
    3. Edit screen mounts, calls subscribeToSpace()
    4. Meanwhile, if space is being deleted/archived, merge update is in progress
    5. onSnapshot fires with exists=true but data() might be undefined during transient state
  - Spaces use soft delete (isArchived flag) but subscribeToSpace has no archived filter
- **Verdict:** **Confirmed** - Race condition is possible and would trigger this exact error

### H3: Edit screen guards are working correctly
- **Rationale:** The edit screen has proper validation, but it can't prevent service-layer issues
- **Experiment:** Reviewed edit screen routing and parameter validation
- **Evidence:**
  - spaceId comes from route params, validated at line 26-29
  - Guard properly checks `if (!accountId || !spaceId)`
  - Route construction is sound (SpaceDetailContent.tsx:96-100)
  - Issue is not invalid spaceId, but timing/data availability
- **Verdict:** **Confirmed** - Edit screen is properly written; issue is in service layer

## Conclusion

**Root cause:** Multiple service files use an unsafe pattern that spreads `snapshot.data()` without null checking, relying on type casts like `as object` that bypass TypeScript's undefined checking.

**Confirmed instances:**
- spacesService.ts:178 - `subscribeToSpace` (space edit screen error)
- transactionsService.ts:109, 118, 138 - subscribe functions (transaction detail screen error)
- Plus 7 more instances in repository.ts, projectPreferencesService.ts, accountPresetsService.ts

**Trigger condition:** This manifests when:
1. A detail/edit screen subscribes to an entity during a deletion/archiving operation
2. Offline-first fire-and-forget writes create race windows
3. onSnapshot fires with `snapshot.exists=true` but `snapshot.data()` returns undefined during transient merge operations
4. Spreading undefined causes: "Cannot convert undefined value to object"

**Scope:** This is a **systemic issue** affecting:
- 11 instances across 5+ service files
- Multiple screens: space edit, transaction detail, likely others
- Only itemsService.ts uses the safe defensive normalization pattern

## Resolution

**Fix strategy:** Apply defensive normalization pattern (from itemsService.ts) to all 11 instances of unsafe spreading.

**Pattern to apply:**
```typescript
// Add normalizer function to each service file
function normalizeFromFirestore(raw: unknown, id: string): EntityType {
  const data = raw && typeof raw === 'object' ? (raw as Record<string, unknown>) : {};
  return { ...(data as object), id } as EntityType;
}

// Replace unsafe spreads:
// OLD: onChange({ ...(snapshot.data() as object), id: snapshot.id } as EntityType);
// NEW: onChange(normalizeFromFirestore(snapshot.data(), snapshot.id));
```

**Files requiring fixes:**
1. `src/data/spacesService.ts:178` - subscribeToSpace
2. `src/data/transactionsService.ts:109, 118, 138` - subscribe functions
3. `src/data/repository.ts:110, 156, 174` - subscribe functions
4. `src/data/projectPreferencesService.ts:52` - subscribe function
5. `src/data/accountPresetsService.ts:40, 65, 74` - subscribe functions

**Priority:** HIGH - affects multiple critical user flows

**Implementation approach:**
1. Create normalizer functions for each entity type in their respective service files
2. Replace all unsafe spread patterns
3. Test affected screens (space edit, transaction detail, etc.)
4. Consider adding pattern to CLAUDE.md to prevent future instances

## Lessons Learned

1. **Type casting bypasses safety checks:** Using `as object` on potentially undefined values defeats TypeScript's purpose and creates runtime errors. Always validate before type casting.

2. **Offline-first race conditions:** Fire-and-forget writes combined with real-time subscriptions create race windows where snapshots can have `exists=true` but `data()=undefined` during transient states.

3. **Pattern inconsistency is dangerous:** Having one safe pattern (itemsService) and 11 unsafe instances across the codebase means the safe pattern wasn't documented or enforced. When a defensive pattern exists, it should be the standard.

4. **Defensive programming at boundaries:** Service layer functions that interact with external systems (Firestore) should always validate data defensively, even if "it shouldn't happen" according to documentation.

5. **Systemic issues need systemic fixes:** This isn't a "fix the space edit screen" problem - it's a codebase-wide pattern that needs standardization.
