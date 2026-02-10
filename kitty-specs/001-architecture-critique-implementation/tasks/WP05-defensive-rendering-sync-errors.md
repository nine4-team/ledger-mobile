---
work_package_id: "WP05"
subtasks:
  - "T024"
  - "T025"
  - "T026"
  - "T027"
  - "T028"
  - "T029"
  - "T030"
title: "Defensive Rendering & Sync Errors"
phase: "Phase 3 & 4 - Defensive Rendering + Sync Error Visibility"
lane: "doing"
assignee: ""
agent: "claude-implementer"
shell_pid: "25534"
review_status: ""
reviewed_by: ""
dependencies: []
history:
  - timestamp: "2026-02-09T08:45:00Z"
    lane: "planned"
    agent: "system"
    shell_pid: ""
    action: "Prompt generated via /spec-kitty.tasks"
---

# Work Package Prompt: WP05 - Defensive Rendering & Sync Errors

## ⚠️ IMPORTANT: Review Feedback Status

**Read this first if you are implementing this task!**

- **Has review feedback?**: Check the `review_status` field above. If it says `has_feedback`, scroll to the **Review Feedback** section immediately (right below this notice).
- **You must address all feedback** before your work is complete. Feedback items are your implementation TODO list.
- **Mark as acknowledged**: When you understand the feedback and begin addressing it, update `review_status: acknowledged` in the frontmatter.
- **Report progress**: As you address each feedback item, update the Activity Log explaining what you changed.

---

## Review Feedback

> **Populated by `/spec-kitty.review`** - Reviewers add detailed feedback here when work needs changes. Implementation must address every item listed below before returning for re-review.

*[This section is empty initially. Reviewers will populate it if the work is returned from review. If you see feedback here, treat each item as a must-do before completion.]*

---

## Markdown Formatting
Wrap HTML/XML tags in backticks: `` `<div>` ``, `` `<script>` ``
Use language identifiers in code blocks: ````typescript`, ````bash`

---

## How to Implement This Work Package

**Run this command to begin**:
```bash
spec-kitty implement WP05
```

This creates an isolated worktree at `.worktrees/001-architecture-critique-implementation-WP05/` branched from `main`.

---

## Objectives & Success Criteria

**Goal**: Implement defensive rendering for missing space references and improve sync error visibility with specific error messages.

**Success Criteria**:
- Item detail screen shows "Unknown space" instead of raw document ID when space is missing
- Report data service handles missing spaces gracefully (returns null)
- SyncStatusBanner displays specific error messages when sync failures occur
- Single failure shows the specific error message
- Multiple failures show count: "N operations failed. Tap Retry or Dismiss."
- TypeScript compilation passes with no new errors
- Manual testing confirms space label fallback and sync error display work correctly

**Acceptance Test**:
1. Archive a space, view item referencing that space → verify "Unknown space" label displayed
2. Trigger request-doc failure → verify SyncStatusBanner shows specific error message (not generic text)
3. Trigger multiple failures → verify banner shows "N operations failed..." with count

---

## Context & Constraints

**Prerequisites**:
- Phase 1 complete (foundation infrastructure)
- Refer to implementation plan: `.plans/architecture-critique-implementation-plan.md` Phase 3 & 4
- Refer to spec: `kitty-specs/001-architecture-critique-implementation/spec.md` User Stories 4, 7

**Key Constraints**:
- **Phase 3 (Defensive Rendering)**: Small string changes, no complex logic
- **Phase 4 (Sync Errors)**: Use existing `getTrackedRequestsSnapshot()` from `requestDocTracker.ts`
- All subtasks T024-T028 are parallelizable (different files/concerns)
- No breaking changes to existing UI/UX patterns

**Architecture Patterns**:
- Defensive rendering: Always provide user-friendly fallbacks for missing data
- Sync errors: Give users actionable information, not technical jargon

---

## Subtasks & Detailed Guidance

### Subtask T024 - Update item detail space label fallback

**Purpose**: Change space label fallback from raw document ID to user-friendly "Unknown space" text.

**Files**:
- Modify: `app/items/[id]/index.tsx`

**Steps**:
1. **Locate the space label** (around line 298):
   ```tsx
   // Before (shows raw ID if space missing):
   {spaces[item.spaceId]?.name?.trim() || item.spaceId}
   ```

2. **Change to user-friendly fallback**:
   ```tsx
   // After (shows "Unknown space" if space missing):
   {spaces[item.spaceId]?.name?.trim() || 'Unknown space'}
   ```

3. **That's it!** Simple string change, no other logic needed.

**Validation**:
- [ ] Line 298 (or nearby) updated with new fallback
- [ ] TypeScript compiles without errors
- [ ] No other space label references need updating (verify with search)

**Testing**:
- Archive a space (or manually set item.spaceId to invalid ID)
- View item detail
- Verify "Unknown space" displayed instead of UUID

**Parallel**: Can proceed in parallel with T025-T028 (different file)

---

### Subtask T025 - Verify resolveSpaceName handles missing spaces gracefully

**Purpose**: Confirm that `resolveSpaceName` in report data service handles missing spaces correctly (returns null).

**Files**:
- Read/verify: `src/data/reportDataService.ts`

**Steps**:
1. **Locate `resolveSpaceName` function** in the file

2. **Check implementation**:
   ```typescript
   const resolveSpaceName = (spaceId: string, spaces: Record<string, Space>): string | null => {
     const space = spaces[spaceId];
     return space?.name ?? null; // Returns null if space missing
   };
   ```

3. **If implementation matches above**: No changes needed, document in verification notes

4. **If implementation returns spaceId as fallback**: Change to return `null`:
   ```typescript
   // Before:
   return space?.name ?? spaceId;

   // After:
   return space?.name ?? null;
   ```

5. **If null is unacceptable**: Check callers of `resolveSpaceName` - they should handle null gracefully (omit label or show placeholder)

**Validation**:
- [ ] `resolveSpaceName` returns `null` when space is missing (not undefined, not ID)
- [ ] Callers of `resolveSpaceName` handle null correctly (checked in code review)
- [ ] TypeScript compiles without errors

**Testing**:
- Run report queries with items referencing missing spaces
- Verify report data doesn't crash or show raw IDs
- Verify null space names are handled gracefully in UI

**Parallel**: Can proceed in parallel with T024, T026-T028 (different file)

---

### Subtask T026 - Update SyncStatusBanner for specific error messages

**Purpose**: Modify SyncStatusBanner to display specific error messages instead of generic "Some changes could not sync."

**Files**:
- Modify: `src/components/SyncStatusBanner.tsx`

**Steps**:
1. **Import `getTrackedRequestsSnapshot`**:
   ```typescript
   import { getTrackedRequestsSnapshot } from '@/src/sync/requestDocTracker';
   ```

2. **Get failed request data** when `failedRequestDocs > 0`:
   ```typescript
   // Inside component or hook
   const snapshot = getTrackedRequestsSnapshot();
   const failedRequests = snapshot.failedRequests; // Array of failed request objects
   ```

3. **Build error message based on failure count**:
   ```typescript
   let errorMessage = '';

   if (snapshot.failedRequestDocs === 1) {
     // Single failure: show specific error
     const failedRequest = failedRequests[0];
     errorMessage = failedRequest.errorMessage || 'An operation failed to sync.';
   } else if (snapshot.failedRequestDocs > 1) {
     // Multiple failures: show count
     errorMessage = `${snapshot.failedRequestDocs} operations failed. Tap Retry or Dismiss.`;
   }
   ```

4. **Display error message in banner**:
   ```tsx
   <AppText style={styles.errorText}>
     {errorMessage}
   </AppText>
   ```

5. **Preserve existing Retry/Dismiss buttons**: No changes to banner actions

**Validation**:
- [ ] Single failure shows specific error message from `errorMessage` field
- [ ] Multiple failures show count: "N operations failed..."
- [ ] Error message updates when failure count changes
- [ ] Retry/Dismiss buttons still work correctly
- [ ] TypeScript compiles without errors

**Implementation Notes**:
- `getTrackedRequestsSnapshot()` returns:
  ```typescript
  {
    pendingRequestDocs: number,
    failedRequestDocs: number,
    failedRequests: Array<{
      id: string,
      errorMessage: string,
      operation: string,
      // ... other fields
    }>
  }
  ```
- Use `errorMessage` field for display (already formatted for users)
- If `errorMessage` is missing/empty, use generic fallback

**Parallel**: Can proceed in parallel with T024-T025, T027-T028 (conceptually related to T027-T028 but can be implemented independently)

---

### Subtask T027 - Implement error display logic

**Purpose**: Ensure error message display logic is correct and handles all edge cases.

**Files**:
- Modify: `src/components/SyncStatusBanner.tsx` (continuation of T026)

**This is part of T026 implementation** - included as separate subtask for clarity.

**Steps**:
1. **Handle edge cases**:
   ```typescript
   let errorMessage = '';

   if (snapshot.failedRequestDocs === 0) {
     // No failures - show pending message or hide banner
     errorMessage = ''; // Banner hidden or shows pending state
   } else if (snapshot.failedRequestDocs === 1) {
     // Single failure
     const failedRequest = failedRequests[0];
     errorMessage = failedRequest?.errorMessage?.trim() || 'An operation failed to sync.';
   } else {
     // Multiple failures
     errorMessage = `${snapshot.failedRequestDocs} operations failed. Tap Retry or Dismiss.`;
   }
   ```

2. **Ensure reactivity**: Update error message when snapshot changes
   ```typescript
   // Use useEffect or derive in render to stay reactive
   useEffect(() => {
     const snapshot = getTrackedRequestsSnapshot();
     // Build error message...
   }, [/* dependencies that trigger snapshot updates */]);
   ```

3. **Fallback for missing errorMessage**:
   - If `errorMessage` is empty/undefined: Use "An operation failed to sync."
   - If `errorMessage` is too long (>100 chars): Truncate with "..." (optional)

**Validation**:
- [ ] Zero failures: Banner shows pending state or hidden
- [ ] One failure with errorMessage: Shows specific message
- [ ] One failure without errorMessage: Shows generic fallback
- [ ] Multiple failures: Shows count message
- [ ] Error message updates when failures are retried/dismissed

**Edge Cases**:
- `failedRequests` array is empty but `failedRequestDocs > 0`: Use generic message
- `errorMessage` contains newlines or special characters: Display as-is (React handles escaping)
- Very long error messages: Consider truncating with tooltip (optional for MVP)

---

### Subtask T028 - Use getTrackedRequestsSnapshot for error data

**Purpose**: Verify integration with `getTrackedRequestsSnapshot` API from `requestDocTracker.ts`.

**Files**:
- Modify: `src/components/SyncStatusBanner.tsx` (continuation of T026-T027)

**This is part of T026-T027 implementation** - included as separate subtask for verification.

**Steps**:
1. **Verify import**:
   ```typescript
   import { getTrackedRequestsSnapshot } from '@/src/sync/requestDocTracker';
   ```

2. **Verify snapshot structure**:
   - Check `src/sync/requestDocTracker.ts` line 172 for export
   - Confirm return type includes `failedRequests` array
   - Confirm each failed request has `errorMessage` field

3. **Verify reactivity**: SyncStatusBanner should re-render when request tracker state changes
   - If using global state: Subscribe to changes
   - If polling: Use interval to re-read snapshot
   - Verify banner updates when failures occur or are dismissed

**Validation**:
- [ ] `getTrackedRequestsSnapshot()` imported and called correctly
- [ ] Snapshot data structure matches expectations (failedRequestDocs, failedRequests)
- [ ] Banner updates when sync state changes (not stale)
- [ ] No runtime errors when accessing snapshot fields

**Integration Notes**:
- `getTrackedRequestsSnapshot()` is already exported (line 172 of `requestDocTracker.ts`)
- This is existing infrastructure - no changes to tracker needed
- Banner just reads from tracker, doesn't modify state

**Parallel**: Can proceed in parallel with T024-T025 (different concerns)

---

### Subtask T029 - Verify TypeScript compilation passes

**Purpose**: Ensure no new TypeScript errors were introduced by the changes.

**Steps**:
1. Run TypeScript compiler:
   ```bash
   npx tsc --noEmit
   ```

2. **Expected output**: All errors should be pre-existing (documented in MEMORY.md)

3. **If new errors appear**:
   - Review the error messages
   - Common issues:
     - `getTrackedRequestsSnapshot` import path incorrect
     - `failedRequests` array type mismatches
     - String/null type errors in fallback expressions
     - Missing properties on snapshot object

4. **Pre-existing errors are OK** (do not fix):
   - `__tests__/` files: missing `@types/jest`
   - `SharedItemsList.tsx`, `SharedTransactionsList.tsx`: icon type mismatches
   - `resolveItemMove.ts`: variable shadowing
   - `settings.tsx`: `BudgetCategoryType` union mismatch
   - `accountContextStore.ts`: null handling

**Validation**:
- [ ] `tsc --noEmit` completes without new errors
- [ ] All new code passes type checking
- [ ] Pre-existing errors remain unchanged

---

### Subtask T030 - Manual verification of defensive rendering and sync errors

**Purpose**: Manually test space label fallback and sync error message display.

**Test Script**:

**Setup**:
1. Open the app
2. Ensure you have at least one item with a valid space reference

---

**PHASE 3 TESTING: Defensive Rendering**

**Test Case 1: Item detail space label with valid space**
1. Navigate to any item detail screen
2. Verify space label shows space name (e.g., "Warehouse A")
3. **Baseline confirmation**: [ ] Valid spaces display correctly

**Test Case 2: Item detail space label with missing space**
1. **Setup**: Archive a space or manually set item's spaceId to invalid ID (via Firestore console)
2. Navigate to that item's detail screen
3. **Verify**:
   - [ ] Space label shows "Unknown space" (not UUID or raw ID)
   - [ ] Rest of item detail renders normally (no crash)
   - [ ] UI looks reasonable with fallback text

**Test Case 3: Report data with missing spaces**
1. **Setup**: Run a report query that includes items with missing space references
2. View report results
3. **Verify**:
   - [ ] Report renders without crashing
   - [ ] Items with missing spaces show no space label or placeholder (not raw IDs)
   - [ ] Items with valid spaces show space names correctly

---

**PHASE 4 TESTING: Sync Error Messages**

**Test Case 4: No sync failures (baseline)**
1. Ensure all sync operations are successful (no failures)
2. Check SyncStatusBanner
3. **Verify**:
   - [ ] Banner hidden or shows "Syncing..." / "All synced"
   - [ ] No error messages displayed

**Test Case 5: Single sync failure (specific error message)**
1. **Setup**: Trigger a single request-doc failure
   - Option A: Disable network, create item, re-enable network (causes timeout)
   - Option B: Modify Firestore security rules to reject write
   - Option C: Manually set request-doc status to failed in Firestore console
2. View SyncStatusBanner
3. **Verify**:
   - [ ] Banner displays specific error message (e.g., "Permission denied" or "Network timeout")
   - [ ] Message is NOT generic "Some changes could not sync"
   - [ ] Retry and Dismiss buttons present and functional

**Test Case 6: Multiple sync failures (count message)**
1. **Setup**: Trigger multiple request-doc failures
   - Create 3+ items/transactions while offline or with restricted permissions
2. View SyncStatusBanner
3. **Verify**:
   - [ ] Banner displays "N operations failed. Tap Retry or Dismiss." (N = actual count)
   - [ ] Does NOT show individual error messages (too cluttered)
   - [ ] Retry button attempts to sync all failed operations

**Test Case 7: Retry single failure**
1. With single failure from Test Case 5
2. Tap Retry button
3. **Verify**:
   - [ ] Retry attempt occurs (network activity)
   - [ ] If successful: Banner updates to show success or hides
   - [ ] If still failing: Error message updates or remains

**Test Case 8: Dismiss failures**
1. With failures from Test Case 5 or 6
2. Tap Dismiss button
3. **Verify**:
   - [ ] Banner dismisses/hides
   - [ ] Failed operations are cleared from tracker (or marked dismissed)
   - [ ] No errors in console

**Test Case 9: Error message fallback**
1. **Setup**: Create a failure with no `errorMessage` field (via manual edit in Firestore)
2. View SyncStatusBanner
3. **Verify**:
   - [ ] Banner shows generic fallback: "An operation failed to sync."
   - [ ] No blank/undefined messages displayed

**Test Case 10: Reactivity**
1. Start with no failures
2. Trigger a failure (create item offline)
3. **Verify**:
   - [ ] Banner appears/updates with error message (not stale)
4. Retry the failure successfully
5. **Verify**:
   - [ ] Banner updates to reflect success or hides

---

**Debugging Tips**:
- Add `console.log('Space ID:', item.spaceId, 'Space:', spaces[item.spaceId])` to debug space lookups
- Add `console.log('Snapshot:', getTrackedRequestsSnapshot())` to inspect sync state
- Check `failedRequests` array in console: `console.log('Failed:', snapshot.failedRequests)`
- Manually set request-doc fields in Firestore to test edge cases

**Validation Checklist**:
- [ ] All 10 test cases pass (3 defensive rendering, 7 sync errors)
- [ ] No TypeScript errors in console
- [ ] No runtime errors during testing
- [ ] Space label fallback is user-friendly
- [ ] Sync error messages are specific and actionable
- [ ] Banner UI/UX is smooth (no layout jumps or flickers)

---

## Test Strategy

**No automated tests required for this work package.**

Manual testing (T030) provides comprehensive verification for defensive rendering and sync error display.

---

## Risks & Mitigations

**Risk 1: Breaking space label display for valid spaces**
- **Mitigation**: Simple string change in fallback only. Valid space lookups unchanged.
- **Verification**: Test with valid spaces first (baseline), then test with missing spaces

**Risk 2: Report service change breaks queries**
- **Mitigation**: Only verify existing behavior (T025). Make no changes if already correct.
- **Verification**: Run existing report queries, ensure no regressions

**Risk 3: SyncStatusBanner reactivity issues (stale error messages)**
- **Mitigation**: Ensure banner subscribes to sync state changes or polls `getTrackedRequestsSnapshot()`
- **Verification**: Test reactivity (Test Case 10) - trigger failure and verify banner updates

**Risk 4: Error messages too technical or unhelpful**
- **Mitigation**: Use `errorMessage` field from tracker (should be user-friendly). Add generic fallback for missing messages.
- **Verification**: Review actual error messages during testing, ensure clarity

**Risk 5: Banner UI breaks with long error messages**
- **Mitigation**: Test with various error message lengths. Truncate if needed (optional for MVP).
- **Verification**: Trigger failures with verbose error messages, check layout

---

## Review Guidance

**Key Checkpoints for `/spec-kitty.review`**:

1. **Code Review**:
   - [ ] Item detail space label fallback changed from `item.spaceId` to `'Unknown space'`
   - [ ] `resolveSpaceName` returns `null` for missing spaces (or existing behavior documented)
   - [ ] SyncStatusBanner imports `getTrackedRequestsSnapshot` correctly
   - [ ] Error message logic handles 0, 1, and N failures correctly
   - [ ] Single failure shows `errorMessage` field from failed request
   - [ ] Multiple failures show count message
   - [ ] Fallback exists for missing `errorMessage`
   - [ ] Banner reactivity ensured (updates when sync state changes)

2. **Testing Evidence**:
   - [ ] T030 manual testing checklist fully completed (all 10 test cases)
   - [ ] Screenshots of "Unknown space" label (optional but helpful)
   - [ ] Screenshots of sync error messages (single and multiple failures)
   - [ ] Confirmation that TypeScript compilation passes

3. **Pattern Consistency**:
   - [ ] Defensive rendering follows established pattern (user-friendly fallbacks)
   - [ ] Sync errors use existing infrastructure (`getTrackedRequestsSnapshot`)
   - [ ] No breaking changes to banner UI/UX
   - [ ] Error messages are actionable and clear

**Questions for Reviewer**:
- Are error messages clear and actionable for end users?
- Does the "Unknown space" fallback provide sufficient context?
- Should we add more defensive rendering elsewhere (other entity references)?
- Are there other sync failure scenarios we should test?

---

## Activity Log

> **CRITICAL**: Activity log entries MUST be in chronological order (oldest first, newest last).

### How to Add Activity Log Entries

**When adding an entry**:
1. Scroll to the bottom of this file (Activity Log section below "Valid lanes")
2. **APPEND the new entry at the END** (do NOT prepend or insert in middle)
3. Use exact format: `- YYYY-MM-DDTHH:MM:SSZ - agent_id - lane=<lane> - <action>`
4. Timestamp MUST be current time in UTC (check with `date -u "+%Y-%m-%dT%H:%M:%SZ"`)
5. Lane MUST match the frontmatter `lane:` field exactly
6. Agent ID should identify who made the change (claude-sonnet-4-5, codex, etc.)

**Format**:
```
- YYYY-MM-DDTHH:MM:SSZ - <agent_id> - lane=<lane> - <brief action description>
```

**Valid lanes**: `planned`, `doing`, `for_review`, `done`

**Initial entry**:
- 2026-02-09T08:45:00Z - system - lane=planned - Prompt created via /spec-kitty.tasks
- 2026-02-10T00:30:31Z – claude-implementer – shell_pid=25534 – lane=doing – Started implementation via workflow command
