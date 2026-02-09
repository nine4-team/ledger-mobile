# Feature Specification: Architecture Critique Implementation

**Feature Branch**: `001-architecture-critique-implementation`
**Created**: 2026-02-09
**Status**: Draft
**Input**: User description: "Implement remaining phases (2-5) of architecture critique remediation plan to address 10 findings across the Ledger Mobile codebase"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Efficient Edit Form Updates (Priority: P1)

When users edit records (items, transactions, projects, spaces, budget categories), the system must track which fields were actually modified and only submit those changes, rather than overwriting the entire document. This prevents unnecessary data transfer, reduces potential for data loss from concurrent edits, and improves offline performance.

**Why this priority**: This is the core architectural improvement affecting 6 screens. Phase 1 foundation infrastructure is complete; this builds on it.

**Independent Test**: Can be tested by editing a record, changing only one field, and verifying that only that field is included in the update payload. Delivers immediate value: more efficient updates and better offline behavior.

**Acceptance Scenarios**:

1. **Given** a user opens an edit screen with no changes, **When** they save without modifying any fields, **Then** no database write occurs and the user navigates away immediately
2. **Given** a user opens an item edit screen, **When** they change only the name field, **Then** only the name field is included in the update payload
3. **Given** a user is editing a form and a subscription update arrives, **When** the user has already modified a field, **Then** the form values are not overwritten by the subscription data
4. **Given** a user edits a transaction with 13 fields, **When** they change only budgetCategoryId, **Then** only budgetCategoryId is sent in the update and linked items are updated accordingly

---

### User Story 2 - Clear Space References (Priority: P2)

When users view items that reference archived or deleted spaces, the system must display user-friendly text (e.g., "Unknown space") instead of raw document IDs. This improves user experience by providing meaningful information even when referenced data is missing.

**Why this priority**: Quick win that improves UX without dependencies on other work. Can be implemented in parallel with User Story 1.

**Independent Test**: Archive a space, then view an item that references it. Verify "Unknown space" is displayed instead of the raw space ID.

**Acceptance Scenarios**:

1. **Given** an item references a space that exists, **When** the user views the item detail, **Then** the space name is displayed
2. **Given** an item references a space that has been archived, **When** the user views the item detail, **Then** "Unknown space" is displayed instead of the raw document ID
3. **Given** an item references a space that has been deleted, **When** the user views the item detail, **Then** "Unknown space" is displayed instead of the raw document ID

---

### User Story 3 - Informative Sync Error Messages (Priority: P2)

When synchronization operations fail (request-doc failures), users must see specific error messages explaining what went wrong rather than generic "Some changes could not sync" messages. This helps users understand and resolve sync issues.

**Why this priority**: Improves debuggability and user trust. Can be implemented in parallel with User Story 1.

**Independent Test**: Trigger a failed request-doc operation and verify the sync status banner shows the specific error message.

**Acceptance Scenarios**:

1. **Given** one sync operation fails with a specific error, **When** the sync status banner is displayed, **Then** the specific error message from the failed operation is shown
2. **Given** multiple sync operations fail, **When** the sync status banner is displayed, **Then** "N operations failed. Tap Retry or Dismiss." is shown with the count
3. **Given** all sync operations succeed, **When** the user views the app, **Then** no sync error banner is displayed

---

### User Story 4 - Clear Architecture Documentation (Priority: P3)

The architecture documentation must accurately explain design decisions, known limitations, and rationale for key patterns (especially around optimistic writes and data model design). This helps future developers understand and maintain the system correctly.

**Why this priority**: Important for long-term maintainability but doesn't affect end-user functionality. Should be done last after all code changes are complete.

**Independent Test**: Review the architecture document and verify all findings (2, 3, 9, 10) are addressed with clear explanations and justifications.

**Acceptance Scenarios**:

1. **Given** a developer reads the "high-risk fields" section, **When** they review the justification, **Then** they understand why full-document overwrites are avoided based on data model arguments (not probability arguments)
2. **Given** a developer encounters silent security rule failures, **When** they consult the Known Limitations section, **Then** they understand this is expected behavior for MVP
3. **Given** a developer needs to add a new optional field, **When** they consult the schema evolution section, **Then** they understand the pattern: new optional fields + merge: true + undefined handling
4. **Given** a developer is implementing an edit screen, **When** they review the "Do NOT Build" list, **Then** they understand to use getChangedFields() instead of full-form overwrites

---

### Edge Cases

- What happens when all form fields are reverted to their original values? (Expected: hasChanges returns false, no write occurs)
- What happens when a subscription update arrives while a user is typing? (Expected: user's edits are preserved, subscription data is ignored)
- What happens when the same field is edited by two users concurrently? (Expected: last write wins, documented as accepted behavior for MVP)
- What happens when a user views an item whose space was deleted between the item query and space query? (Expected: "Unknown space" is displayed)
- What happens when all listener factories fail during scope attach? (Expected: scope.isAttached remains false, retry with exponential backoff)

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Edit forms MUST track which fields have been modified by the user relative to the initial snapshot
- **FR-002**: Save operations MUST submit only modified fields, not full document overwrites
- **FR-003**: Edit forms MUST ignore subscription updates after the user has made their first edit
- **FR-004**: Edit forms MUST provide a way to reset and re-accept subscription data
- **FR-005**: Save operations MUST skip database writes entirely when no fields have changed
- **FR-006**: Item detail screens MUST display "Unknown space" when a referenced space is not found
- **FR-007**: Report data services MUST handle missing space references gracefully (return null)
- **FR-008**: Sync status banner MUST display specific error messages for individual failed operations
- **FR-009**: Sync status banner MUST show operation count when multiple operations fail
- **FR-010**: Listener manager MUST only mark a scope as attached if at least one listener succeeds
- **FR-011**: Listener manager MUST retry failed scope attachments with exponential backoff (1s, 2s, 4s, max 3 attempts)
- **FR-012**: Listener manager MUST clear retry timeouts when scope is detached or cleaned up
- **FR-013**: Architecture documentation MUST explain the data model rationale for partial writes
- **FR-014**: Architecture documentation MUST document known limitations including silent security rule failures
- **FR-015**: Architecture documentation MUST document schema evolution patterns
- **FR-016**: Architecture documentation MUST include "Do NOT Build" guidance for full-form overwrites

### Key Entities

- **EditForm**: Represents form state with change tracking capabilities - tracks initial snapshot, current values, which fields have been modified, and whether user has made any edits
- **FormField**: Individual data field within an edit form that can be tracked for changes - identified by key, has initial and current value
- **ScopeListeners**: Represents a collection of active listeners for a data scope - tracks attachment status, retry attempts, and cleanup state
- **RequestDoc**: Represents a pending synchronization operation that may succeed or fail - contains operation details and error messages
- **Space**: A location or organizational unit that items can reference - may be active, archived, or deleted

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Edit form submissions include only modified fields, reducing payload size by 80-90% for typical single-field edits
- **SC-002**: Users experience no form data loss when subscription updates arrive during editing sessions
- **SC-003**: Edit forms with no changes complete save operation instantly without network round-trip
- **SC-004**: Users never see raw document IDs in the UI when viewing items with missing space references
- **SC-005**: Users see specific error messages for sync failures, not generic "could not sync" text
- **SC-006**: Listener manager successfully attaches scopes with at least one working factory, even if some factories fail
- **SC-007**: Failed scope attachments retry automatically up to 3 times with exponential backoff
- **SC-008**: Architecture documentation provides clear guidance that prevents future developers from introducing full-document overwrites
- **SC-009**: All 6 edit screens (items, transactions, projects, 2 space screens, settings) use consistent change-tracking patterns
- **SC-010**: TypeScript compilation passes with no new errors introduced

## Assumptions

- Phase 1 (foundation infrastructure) is complete and verified:
  - useEditForm hook exists and is tested
  - ScopedListenerManager.attachScope() handles partial failures correctly
  - Media foreground auto-retry is implemented
  - Media stale cache cleanup is implemented
- The existing plan verification steps are comprehensive and will be used for acceptance testing
- Budget handling in project edit screen remains separate (separate collection, separate writes) and only basic fields migrate to useEditForm
- Tax/subtotal computation in transaction edit stays in save handler - computed values go through getChangedFields()
- All pre-existing TypeScript errors are documented and not related to this work
- Target branch is "main" - can be changed to "2.x" if needed for dual-branch features

## Dependencies

- **Phase 2 depends on**: Phase 1 completion (useEditForm hook availability)
- **Phase 3 and 4**: Can run in parallel with Phase 2
- **Phase 5 depends on**: Phases 2-4 completion (documentation should reflect actual implemented patterns)

## Out of Scope

- Implementing formal schema migration framework (deferred beyond MVP)
- Adding full compare-before-commit UX with user prompts about conflicts (too heavyweight for MVP)
- Changing budget handling in project edit screen (stays as separate collection with separate writes)
- Fixing pre-existing TypeScript errors unrelated to this work
- Media upload queue processing improvements beyond Phase 1 work
- Optimistic write transaction reconciliation (accepted limitation for MVP)
