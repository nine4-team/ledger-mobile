# Feature Spec: Architecture Critique Implementation

## Overview

Implement improvements to the Ledger Mobile app based on architecture critique findings. Focus on adding change tracking to edit screens to prevent unnecessary Firestore writes and improve offline-first reliability.

## User Stories

### User Story 1: Efficient Edit Screen Updates (WP01-WP04)

**As a** designer using the app offline
**I want** edit screens to only write changed fields to Firestore
**So that** my edits are efficient, reliable, and don't create unnecessary sync conflicts

**Acceptance Criteria**:
- Edit screens use `useEditForm` hook for state management with change tracking
- Save operations only include modified fields in update payloads
- Saves with no changes skip database writes entirely
- Subscription updates don't overwrite user edits during active editing
- Works correctly offline (partial writes apply locally, sync when online)

### User Story 2: Defensive Rendering (WP05)

**As a** user of the app
**I want** screens to handle partial/stale data gracefully
**So that** I don't see crashes or broken UI during sync operations

**Acceptance Criteria**:
- Components handle null/undefined data gracefully
- Missing related entities don't cause crashes
- UI shows appropriate loading states or fallbacks
- Sync errors are handled without breaking the UI

### User Story 3: Clear Documentation (WP06)

**As a** developer working on this codebase
**I want** architecture patterns clearly documented
**So that** I can maintain consistency and understand the offline-first approach

**Acceptance Criteria**:
- ARCHITECTURE.md updated with edit screen patterns
- Change tracking patterns documented with examples
- Migration guide for future edit screens

## Technical Approach

### Phase 1: Foundation (Completed)
- ✅ `useEditForm` hook created with change tracking API
- ✅ Basic utilities and helpers in place

### Phase 2: Edit Screen Migrations (WP01-WP04)
- Migrate 3 simple edit screens (project, 2 spaces)
- Migrate settings budget category modal
- Migrate item edit screen (9 fields, including price handling)
- Migrate transaction edit screen (13 fields, most complex)

### Phase 3: Defensive Patterns (WP05)
- Add null checks and defensive rendering
- Handle missing related entities
- Graceful degradation during sync

### Phase 4: Documentation (WP06)
- Update ARCHITECTURE.md with patterns
- Create migration guide
- Document testing approaches

## Constraints

- Must maintain offline-first behavior (fire-and-forget writes)
- Cannot break existing functionality
- TypeScript compilation must pass
- Must work with React Native Firebase SDK (not web SDK)

## Success Metrics

- All edit screens use partial writes
- Zero unnecessary Firestore writes (verified via logging)
- No new TypeScript errors
- Manual testing passes for all edit screens
- Documentation updated and reviewed

## Out of Scope

- Changing the underlying Firestore architecture
- Adding optimistic UI updates beyond what's already there
- Implementing compare-before-commit dialogs
- Fine-grained conflict resolution (last-write-wins is acceptable)
