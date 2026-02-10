---
work_package_id: WP06
title: Architecture Documentation Updates
lane: "doing"
dependencies: []
base_branch: main
base_commit: eb8976f6437f8368e8c71026fe75a02ca5e18262
created_at: '2026-02-10T00:56:58.532489+00:00'
subtasks:
- T031
- T032
- T033
- T034
- T035
- T036
phase: Phase 5 - Documentation
assignee: ''
agent: ''
shell_pid: "54401"
review_status: ''
reviewed_by: ''
history:
- timestamp: '2026-02-09T08:45:00Z'
  lane: planned
  agent: system
  shell_pid: ''
  action: Prompt generated via /spec-kitty.tasks
---

# Work Package Prompt: WP06 - Architecture Documentation Updates

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
spec-kitty implement WP06
```

This creates an isolated worktree at `.worktrees/001-architecture-critique-implementation-WP06/` branched from `main`.

---

## Objectives & Success Criteria

**Goal**: Update architecture documentation to reflect implemented patterns, design decisions, and address all 4 findings (F2, F3, F9, F10) from the architecture critique.

**Success Criteria**:
- ARCHITECTURE.md addresses Finding 2 (silent security rule failures) with "Known Limitations" section
- ARCHITECTURE.md addresses Finding 3 (high-risk fields) with data model argument (not probability)
- ARCHITECTURE.md addresses Finding 9 (schema evolution) with documented pattern and stance
- ARCHITECTURE.md addresses Finding 10 (Do NOT Build) with full-form overwrite guidance and staleness check distinction
- All documentation sections flow logically and provide clear guidance for future developers
- TypeScript compilation passes (no code changes, documentation only)
- Documentation reflects actual implemented patterns from WP01-WP04

**Acceptance Test**:
1. Read ARCHITECTURE.md → verify all 4 findings have dedicated sections with clear explanations
2. Review "High-Risk Fields" section → verify data model argument (not probability)
3. Review "Do NOT Build" section → verify `getChangedFields()` guidance and staleness check distinction
4. Review "Known Limitations" section → verify silent security rule failure is documented
5. Review "Schema Evolution" section → verify pattern and MVP stance are clear

---

## Context & Constraints

**Prerequisites**:
- WP01-WP04 complete: Edit screen patterns are implemented and tested
- Phase 1 complete: `useEditForm` hook exists and is documented
- Refer to implementation plan: `.plans/architecture-critique-implementation-plan.md` Phase 5
- Refer to spec: `kitty-specs/001-architecture-critique-implementation/spec.md` (documentation goals)

**File to Modify**:
- `docs/specs/ARCHITECTURE.md` (moved from `.cursor/plans/firebase-mobile-migration/10_architecture/`)
- NOTE: If file doesn't exist at `docs/specs/`, check original location and move it first

**Key Constraints**:
- Documentation only - no code changes in this work package
- Must reflect ACTUAL implemented patterns (reference WP01-WP04 code)
- Must address critique findings with data/technical arguments (not hand-waving)
- Must provide actionable guidance for future developers

**Critique Findings to Address**:
- **Finding 2**: Silent security rule failures (optimistic writes, no server validation feedback)
- **Finding 3**: High-risk fields justification (budgetCents, priceCents - why no conflict detection?)
- **Finding 9**: Schema evolution stance (how to handle optional fields, breaking changes)
- **Finding 10**: Do NOT Build list update (full-form overwrites, staleness check vs compare-before-commit UX)

---

## Subtasks & Detailed Guidance

### Subtask T031 - Rewrite "high-risk fields" justification (Finding 3)

**Purpose**: Replace probability argument ("concurrent edits are rare") with technical data model argument explaining why conflict detection is unnecessary.

**Files**:
- Modify: `docs/specs/ARCHITECTURE.md`

**Steps**:
1. **Locate "High-Risk Fields" or "Conflict Detection" section** (may need to create if doesn't exist)

2. **Remove probability argument**:
   - Delete any text like: "Concurrent edits are rare in this app"
   - Delete any text like: "The probability of conflicts is low"
   - Delete any text like: "Users typically don't edit the same field simultaneously"

3. **Replace with data model argument**:
   ```markdown
   ## High-Risk Fields: Why Conflict Detection Is Not Required

   Fields like `budgetCents`, `purchasePriceCents`, `estimatedPriceCents`, and `salePriceCents` are **source/planning data, not derived totals**. They represent direct user input on a single document, and the correct value is whatever the user last entered.

   ### Key Distinctions

   **Source Data (no conflict detection needed)**:
   - `budgetCents`: User's planned budget allocation for a category (single source of truth per document)
   - `purchasePriceCents`: Actual price paid for an item (single transaction, single value)
   - `estimatedPriceCents`: User's estimate for an item (planning value, not aggregated)
   - `salePriceCents`: Actual sale price for an item (single transaction, single value)

   Each of these is:
   - **Direct user input** on a specific document (not computed from other sources)
   - **Single-owner data**: Only one user edits planning values for a project/item at a time
   - **Not aggregated**: These are not sums or totals that could accumulate incorrectly

   **Derived Totals (different story)**:
   - Actual spend totals are **computed at read time** from transaction documents via `buildBudgetProgress()`
   - Never stored as competing fields that could drift
   - Always reflect current transaction state (source of truth is transactions collection)

   ### Fallback: Security Rule Checks

   If concurrent edits become a concern (e.g., collaborative budget editing), Firestore security rules can enforce `updatedAt` timestamp checks:

   ```javascript
   // Security rule: Reject writes if document was modified since last read
   allow update: if request.resource.data.updatedAt == resource.data.updatedAt;
   ```

   This is a **one-line rule** that provides lightweight staleness detection without complex application logic or Cloud Functions.

   ### Why `getChangedFields()` Is Still Important

   Even without conflict detection, partial writes via `getChangedFields()` are critical:
   - **Reduces Firestore write costs** (only send modified fields)
   - **Improves offline performance** (smaller payloads)
   - **Prevents unintentional overwrites** (e.g., subscription updates during editing)
   - **Provides user feedback** (e.g., "No changes" message)

   The `useEditForm` hook (implemented in Phase 1) provides this functionality across all edit screens.
   ```

4. **Reference actual implementation**:
   - Mention `useEditForm` hook (from Phase 1)
   - Mention `buildBudgetProgress()` function (existing read-time computation)
   - Mention edit screens from WP01-WP04 that use `getChangedFields()`

**Validation**:
- [ ] Probability argument removed entirely
- [ ] Data model argument present with clear distinction (source vs derived)
- [ ] Security rule fallback documented (with code example)
- [ ] `getChangedFields()` importance explained (separate from conflict detection)
- [ ] References to actual implementation included

**Tone**: Technical and data-driven. Explain the "why" with architecture reasoning, not probability estimates.

---

### Subtask T032 - Add "Known Limitations" section (Finding 2)

**Purpose**: Document silent security rule failures as an accepted MVP limitation.

**Files**:
- Modify: `docs/specs/ARCHITECTURE.md`

**Steps**:
1. **Create "Known Limitations" section** (if doesn't exist):
   ```markdown
   ## Known Limitations (Accepted for MVP)

   These are architectural tradeoffs made consciously for the MVP. Future iterations may address them if they become pain points.
   ```

2. **Add silent security rule failure subsection**:
   ```markdown
   ### Silent Security Rule Failures

   **Behavior**: Firestore applies writes optimistically to the local cache even if the server later rejects them due to security rule violations. Users may see "phantom" values that never sync to the server.

   **Example**:
   - User edits a document they don't have permission to modify
   - Edit appears immediately in the app (offline-first, optimistic write)
   - Server rejects the write due to security rules
   - User sees the edited value locally, but other users never see it
   - No immediate error message to the user (only shows up in sync banner later)

   **Why This Happens**:
   - Firestore SDK applies writes to local cache before server validation (by design for offline support)
   - Security rules only run on the server (not in client SDK)
   - No synchronous feedback on security rule failures

   **Mitigation Strategies (Implemented)**:
   1. **Request-doc tracking**: All writes create request-docs that track sync status
   2. **Sync status banner**: Shows failed operations with error messages (see Phase 4 implementation)
   3. **Defensive permissions**: Security rules designed to be permissive for authenticated users (reduce failure scenarios)

   **Mitigation Strategies (Not Implemented for MVP)**:
   1. **Pre-write permission checks**: Client-side validation that mirrors security rules (complex, error-prone)
   2. **Rollback on failure**: Revert local cache when server rejects write (requires custom logic, breaks offline-first guarantees)
   3. **Blocking writes**: Await server acknowledgment before showing success (defeats offline-first, poor UX)

   **Accepted Tradeoff**: For MVP, we accept that users may occasionally see phantom values. The sync banner provides visibility when failures occur, and defensive security rules minimize the risk.

   **Future Improvement**: If this becomes a frequent issue, consider:
   - Pre-write permission validation (mirror rules in client)
   - More aggressive sync banner notifications (foreground alerts for failures)
   - Transaction-level rollback on server rejection (complex but possible)
   ```

3. **Link to related documentation**:
   - Reference sync status banner implementation (WP05)
   - Reference request-doc tracker (`src/sync/requestDocTracker.ts`)

**Validation**:
- [ ] Limitation clearly stated (silent failures exist)
- [ ] Behavior explained with example scenario
- [ ] Technical "why" explained (Firestore design, offline-first)
- [ ] Implemented mitigations documented (request-docs, sync banner)
- [ ] NOT implemented mitigations listed with rationale
- [ ] Accepted tradeoff explicitly stated
- [ ] Future improvement path suggested

**Tone**: Honest and transparent. Don't downplay the limitation, but explain the context and tradeoffs.

---

### Subtask T033 - Add schema evolution stance (Finding 9)

**Purpose**: Document the pattern for handling schema changes (optional fields, breaking changes) without a formal migration framework.

**Files**:
- Modify: `docs/specs/ARCHITECTURE.md`

**Steps**:
1. **Create "Schema Evolution" section** (if doesn't exist):
   ```markdown
   ## Schema Evolution Strategy

   This documents how the app handles schema changes over time as new fields are added or data structures change.
   ```

2. **Add MVP pattern subsection**:
   ```markdown
   ### MVP Pattern: Optional Fields + Merge Writes

   **Pattern**: All new fields are optional, and writes use `merge: true` to avoid overwriting existing data.

   **Example - Adding a new field**:
   ```typescript
   // New field: `estimatedCompletionDate` added to Project type
   interface Project {
     id: string;
     name: string;
     // ... existing fields
     estimatedCompletionDate?: Timestamp; // New optional field
   }

   // Write with merge: true
   await updateDoc(projectRef, {
     estimatedCompletionDate: newDate
   }, { merge: true });

   // Read with undefined handling
   const project = projectSnap.data() as Project;
   const completionDate = project.estimatedCompletionDate ?? null;
   ```

   **Key Principles**:
   1. **Always optional**: New fields use `?` in TypeScript types
   2. **Merge writes**: Use `{ merge: true }` or `setDoc` with merge to preserve existing fields
   3. **Undefined handling**: Read code handles `undefined` gracefully (use `??` operator for defaults)
   4. **No schema version**: No `schemaVersion` field or formal migration framework for MVP

   **Benefits**:
   - Simple: No migration code to maintain
   - Offline-friendly: No need to run migrations before offline writes
   - Backward compatible: Old clients can read new documents (ignore unknown fields)

   **Limitations**:
   - Cannot rename fields (old field remains forever, or requires manual cleanup)
   - Cannot change field types (e.g., string → number) without read-time conversion
   - Cannot remove required fields (would break old clients)

   ### Breaking Changes (When MVP Pattern Isn't Enough)

   If a breaking change is needed (e.g., rename field, change type, remove required field):

   **Option 1: Read-Time Normalization**
   ```typescript
   // Normalize old schema to new schema at read time
   const normalizeProject = (raw: any): Project => {
     return {
       id: raw.id,
       name: raw.name || raw.projectName, // Handle old field name
       estimatedBudgetCents: typeof raw.estimatedBudget === 'string'
         ? parseFloat(raw.estimatedBudget) * 100  // Convert old string format to cents
         : raw.estimatedBudgetCents ?? 0,
       // ... other fields
     };
   };
   ```

   **Option 2: Schema Version + Migration**
   ```typescript
   interface Project {
     schemaVersion: number; // 1, 2, 3...
     // ... fields
   }

   const migrateProject = (raw: any): Project => {
     const version = raw.schemaVersion ?? 1;
     if (version === 1) {
       // Migrate v1 → v2
       return { ...raw, schemaVersion: 2, newField: defaultValue };
     }
     return raw;
   };
   ```

   **When to use each**:
   - **Read-time normalization**: Preferred for one-off conversions, small changes
   - **Schema version + migration**: Required for complex multi-step migrations, data transformations

   **Not Implemented for MVP**: Both options above are documented patterns but not implemented. If needed, implement on a case-by-case basis.

   ### Current Schema Versions

   As of MVP, no documents have `schemaVersion` fields. All types are at implicit "version 1."

   If breaking changes are introduced in the future, add `schemaVersion` to affected types and implement migrations at read time.
   ```

3. **Reference existing code**:
   - Mention `useEditForm` hook uses partial writes (merge behavior)
   - Mention all edit screens from WP01-WP04 use merge writes

**Validation**:
- [ ] MVP pattern clearly documented (optional fields + merge writes)
- [ ] Code examples provided for adding new fields
- [ ] Benefits and limitations listed
- [ ] Breaking change strategies documented (read-time normalization, schema version)
- [ ] When to use each strategy explained
- [ ] Current state documented (no schema versions in MVP)
- [ ] Future path clear (add schema version if breaking changes needed)

**Tone**: Pragmatic. Explain the simple MVP approach and when to graduate to more complex patterns.

---

### Subtask T034 - Update "Do NOT Build" list (Finding 10)

**Purpose**: Add guidance against full-form overwrites and clarify the distinction between lightweight staleness checks and full compare-before-commit UX.

**Files**:
- Modify: `docs/specs/ARCHITECTURE.md`

**Steps**:
1. **Locate "Do NOT Build" or "Anti-Patterns" section** (may need to create if doesn't exist)

2. **Add full-form overwrite anti-pattern**:
   ```markdown
   ## Do NOT Build (Anti-Patterns)

   These are patterns we explicitly reject for this architecture. If you're considering building one of these, review the rationale first.

   ### ❌ Full-Form Overwrites on Edit Screens

   **Anti-Pattern**: Sending all form fields to Firestore on save, even if only one field changed.

   ```typescript
   // BAD: Overwrites all fields, even unchanged ones
   const handleSave = () => {
     await updateDoc(itemRef, {
       name: name,
       description: description,
       spaceId: spaceId,
       status: status,
       estimatedPriceCents: estimatedPriceCents,
       purchasePriceCents: purchasePriceCents,
       salePriceCents: salePriceCents,
       quantity: quantity,
       tags: tags
     });
   };
   ```

   **Why It's Bad**:
   - **Cost**: Firestore charges per field written (9 field writes vs 1 field write)
   - **Offline performance**: Larger payloads slow down sync queue
   - **Conflict risk**: Overwrites fields that may have changed via subscription
   - **No-change detection**: Can't skip write if user saved without edits

   **Correct Pattern**: Use `getChangedFields()` to send only modified fields

   ```typescript
   // GOOD: Only sends changed fields
   const handleSave = () => {
     if (!form.hasChanges) {
       router.back();
       return;
     }

     const changedFields = form.getChangedFields();
     updateItem(itemId, changedFields).catch(console.error);
     router.back();
   };
   ```

   **Implemented In**:
   - `src/hooks/useEditForm.ts`: Hook provides `getChangedFields()` and `hasChanges`
   - All edit screens (WP01-WP04): Project, spaces, budget categories, items, transactions

   ### ❌ Full Compare-Before-Commit UX (Too Heavy for MVP)

   **Anti-Pattern**: Blocking saves while fetching latest server data for comparison, showing diff UI, requiring user confirmation.

   ```typescript
   // BAD: Blocks save, fetches server data, shows diff modal
   const handleSave = async () => {
     setIsLoading(true);
     const latestItem = await fetchLatestFromServer(itemId); // Blocks on network
     const conflicts = compareFields(form.values, latestItem);
     if (conflicts.length > 0) {
       setShowConflictModal(true); // User must resolve conflicts
     } else {
       await updateDoc(itemRef, form.values);
     }
     setIsLoading(false);
   };
   ```

   **Why It's Bad for MVP**:
   - **Offline-hostile**: Requires network call before save (breaks offline-first)
   - **Slow UX**: Users wait for server round-trip on every save
   - **Complex UI**: Requires conflict resolution modal, diff viewer
   - **Overkill**: Only needed for high-conflict scenarios (collaborative real-time editing)

   **What We Build Instead**: Lightweight staleness check via `useEditForm`

   ```typescript
   // GOOD: Lightweight staleness check (no network call)
   const form = useEditForm<ItemFormValues>(item);
   // - Tracks which fields changed since form load
   // - Uses `shouldAcceptSubscriptionData` to prevent subscription overwrites
   // - No server fetch, no blocking, no modal
   ```

   **Distinction**:
   - **Lightweight staleness check** (what we built):
     - Detects changes at form level (local state only)
     - Prevents subscription overwrites during editing
     - No network call, no blocking, no diff UI
     - Implemented in `useEditForm` hook (Phase 1)
   - **Full compare-before-commit UX** (what we don't build):
     - Fetches latest server data before save (network call)
     - Shows diff UI for conflicts (modal, side-by-side view)
     - Requires user to resolve conflicts (choose version, merge manually)
     - Appropriate for high-conflict scenarios (e.g., Google Docs-style collaboration)

   **When to Reconsider**: If usage patterns show frequent concurrent edits with data loss, revisit this decision. For MVP, the lightweight approach is sufficient.

   ### ❌ [Other Anti-Patterns]

   *(Keep existing anti-patterns if present in original ARCHITECTURE.md)*
   ```

3. **Link to implementation**:
   - Reference `useEditForm` hook (`src/hooks/useEditForm.ts`)
   - Reference WP01-WP04 edit screens

**Validation**:
- [ ] Full-form overwrite anti-pattern documented with "bad" example
- [ ] Correct pattern documented with "good" example (getChangedFields)
- [ ] Cost and performance reasons explained
- [ ] References to actual implementation included
- [ ] Full compare-before-commit UX anti-pattern documented
- [ ] Distinction between lightweight check and full compare-before-commit explained
- [ ] When to reconsider guidance provided

**Tone**: Prescriptive. Clear "do this, not that" guidance with rationale.

---

### Subtask T035 - Add staleness check distinction

**Purpose**: Ensure the distinction between lightweight staleness check (what we built) and full compare-before-commit UX (what we don't build) is crystal clear.

**Files**:
- Modify: `docs/specs/ARCHITECTURE.md` (continuation of T034)

**This is covered in T034** - included as separate subtask for emphasis.

**Ensure the following is clear in documentation**:

1. **Lightweight Staleness Check (Implemented)**:
   - **What it does**: Tracks which fields user edited, prevents subscription overwrites during editing
   - **How it works**: `useEditForm` hook compares form state to initial snapshot (no network call)
   - **Cost**: Zero network overhead, zero latency
   - **Use case**: Prevent unintentional overwrites, skip no-change writes
   - **Does NOT do**: Detect concurrent edits from other users, show conflict UI

2. **Full Compare-Before-Commit UX (Not Implemented)**:
   - **What it does**: Fetches latest server data, compares with user edits, shows diff UI for conflicts
   - **How it works**: Network call to fetch latest before save, diff algorithm, conflict resolution modal
   - **Cost**: Network round-trip on every save, complex UI code, user friction
   - **Use case**: Collaborative real-time editing with high conflict probability (e.g., Google Docs, Notion)
   - **Does**: Detect concurrent edits, prevent overwrites, show merge UI

**Visual aid** (optional but helpful):
```markdown
### Staleness Check Comparison Table

| Feature | Lightweight Check (Implemented) | Full Compare-Before-Commit (Not Implemented) |
|---------|--------------------------------|---------------------------------------------|
| Network call on save | ❌ No | ✅ Yes (fetch latest) |
| Detects user edits | ✅ Yes | ✅ Yes |
| Detects concurrent edits | ❌ No | ✅ Yes |
| Shows diff UI | ❌ No | ✅ Yes |
| Blocks save on conflict | ❌ No | ✅ Yes |
| Offline-friendly | ✅ Yes | ❌ No |
| User friction | ✅ Low | ⚠️ High |
| Appropriate for | Single-user editing, low conflict | Real-time collaboration, high conflict |
```

**Validation**:
- [ ] Table or clear section comparing both approaches
- [ ] Key differences highlighted (network call, conflict detection, UI complexity)
- [ ] Use cases for each approach explained
- [ ] Implementation status clear (lightweight is built, full compare is not)

---

### Subtask T036 - Verify documentation flows logically

**Purpose**: Review the entire ARCHITECTURE.md file to ensure all sections flow logically and provide clear guidance for future developers.

**Files**:
- Read/review: `docs/specs/ARCHITECTURE.md`

**Steps**:
1. **Read the entire file from top to bottom**:
   - Does the structure make sense? (high-level concepts → implementation details)
   - Are sections in logical order?
   - Are there gaps or redundancies?

2. **Check for internal consistency**:
   - Do examples match the documented patterns?
   - Are file paths accurate? (verify against actual codebase)
   - Are function/hook names correct?
   - Are code examples syntactically valid?

3. **Verify all critique findings are addressed**:
   - [ ] Finding 2 (silent security failures): Documented in "Known Limitations"
   - [ ] Finding 3 (high-risk fields): Rewritten with data model argument
   - [ ] Finding 9 (schema evolution): Documented with MVP pattern and breaking change strategies
   - [ ] Finding 10 (Do NOT Build): Updated with full-form overwrite and compare-before-commit guidance

4. **Test code examples** (mentally or in scratch file):
   - Do TypeScript examples compile?
   - Are imports correct?
   - Are types consistent?

5. **Check for broken references**:
   - File paths mentioned in docs exist in codebase (e.g., `src/hooks/useEditForm.ts`)
   - Function/hook names match actual implementations
   - Work package references (WP01-WP04) are accurate

6. **Readability review**:
   - Is the tone consistent (technical but accessible)?
   - Are headings clear and descriptive?
   - Is jargon explained where necessary?
   - Are examples helpful and realistic?

7. **Make corrections** for any issues found above

**Validation**:
- [ ] No orphaned sections or incomplete thoughts
- [ ] All code examples are syntactically correct
- [ ] All file/function references are accurate
- [ ] All 4 critique findings have clear, comprehensive sections
- [ ] Documentation flows logically (high-level → details)
- [ ] Tone is consistent (technical but accessible)
- [ ] Future developers can follow guidance without confusion

**Debugging Tips**:
- Use table of contents to check section hierarchy
- Search for all file path mentions and verify they exist
- Search for all function/hook mentions and verify signatures match
- Read as if you're a new developer joining the project (what questions would you have?)

---

## Test Strategy

**No automated tests required for this work package.**

Documentation verification (T036) ensures quality and accuracy.

**Verification Approach**:
1. **Peer review**: Another developer reads the docs and confirms clarity
2. **Spot-check**: Verify file paths and function names against actual codebase
3. **Completeness check**: Ensure all 4 critique findings are addressed

---

## Risks & Mitigations

**Risk 1: Documentation doesn't reflect actual implementation**
- **Mitigation**: Complete WP06 AFTER WP01-WP04 are done. Reference actual code when writing docs.
- **Verification**: Spot-check file paths, function names, patterns against actual code

**Risk 2: Documentation is too technical or too vague**
- **Mitigation**: Balance technical accuracy with accessibility. Include examples.
- **Verification**: Have another developer (or reviewer) read docs and provide feedback

**Risk 3: Documentation becomes stale over time**
- **Mitigation**: Include "Last Updated" timestamp at top of file. Establish review cadence (e.g., quarterly).
- **Note**: Not in scope for MVP, but recommend for future

**Risk 4: Critique findings not addressed convincingly**
- **Mitigation**: Use data-driven arguments (data model, technical constraints), not probability estimates or hand-waving
- **Verification**: Each finding should have a dedicated section with clear rationale

---

## Review Guidance

**Key Checkpoints for `/spec-kitty.review`**:

1. **Content Review**:
   - [ ] Finding 2 (silent failures): "Known Limitations" section exists, explains behavior, lists mitigations
   - [ ] Finding 3 (high-risk fields): Probability argument removed, data model argument present, security rule fallback documented
   - [ ] Finding 9 (schema evolution): MVP pattern documented (optional fields + merge), breaking change strategies listed
   - [ ] Finding 10 (Do NOT Build): Full-form overwrite anti-pattern added, staleness check distinction clear
   - [ ] All code examples are syntactically correct
   - [ ] All file paths reference actual files in codebase
   - [ ] All function/hook names match actual implementations

2. **Structure Review**:
   - [ ] Documentation flows logically (high-level → details)
   - [ ] Sections are well-organized (clear headings, no orphans)
   - [ ] Table of contents accurate (if present)
   - [ ] No redundancies or contradictions

3. **Quality Review**:
   - [ ] Tone is consistent (technical but accessible)
   - [ ] Examples are helpful and realistic
   - [ ] Guidance is actionable (future developers can follow it)
   - [ ] Rationale is clear (explains "why," not just "what")

4. **Completeness Review**:
   - [ ] All 4 critique findings addressed comprehensively
   - [ ] No gaps or missing sections
   - [ ] References to WP01-WP04 implementations included
   - [ ] Future improvement paths suggested where appropriate

**Questions for Reviewer**:
- Are the critique findings addressed convincingly (data-driven arguments)?
- Is the distinction between lightweight check and full compare-before-commit clear?
- Are there any unclear sections that need expansion or examples?
- Does the documentation provide sufficient guidance for future developers?

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
