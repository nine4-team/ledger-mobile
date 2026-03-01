# Work Package Orchestration Plan
## Architecture Critique Implementation (Feature 001)

**Created**: 2026-02-09
**Orchestrator**: claude-orchestrator
**Feature**: Architecture Critique Implementation
**Total WPs**: 6

---

## Execution Strategy

**Approach**: Sequential implementation with manager-agent pattern
**Rationale**: Solo development, each WP builds on patterns from previous ones

### Recommended Sequence

1. **WP01** (Simple Edit Screens) - CURRENT
   - Status: Doing
   - Establishes `useEditForm` pattern
   - Simplest screens (3-2 fields each)
   - Foundation for WP03-WP04

2. **WP02** (Settings Budget Category)
   - Status: Planned
   - Independent of WP01
   - Uses inline comparison (simpler)
   - Can start immediately after WP01

3. **WP03** (Item Edit Screen)
   - Status: Planned
   - Depends on WP01 pattern
   - 9 fields with price handling
   - Medium complexity

4. **WP04** (Transaction Edit Screen)
   - Status: Planned
   - Most complex (13 fields)
   - Computed fields + propagation
   - Should be last before docs

5. **WP05** (Defensive Rendering)
   - Status: Planned
   - Independent (can run in parallel)
   - Small changes, different concerns
   - Can start anytime

6. **WP06** (Documentation)
   - Status: Planned
   - Must run AFTER WP01-WP04
   - Documents implemented patterns

---

## Current State

**Date**: 2026-02-09 19:45 UTC

| WP | Title | Lane | Agent | Notes |
|----|-------|------|-------|-------|
| WP01 | Simple Edit Screens | doing | claude-orchestrator (pending sub-agent) | Worktree exists, useEditForm scaffolded |
| WP02 | Settings Budget Category | planned | - | Ready to start after WP01 |
| WP03 | Item Edit Screen | planned | - | Depends on WP01 pattern |
| WP04 | Transaction Edit Screen | planned | - | Most complex, do after WP03 |
| WP05 | Defensive Rendering | planned | - | Can run in parallel |
| WP06 | Documentation | planned | - | Do LAST after WP01-WP04 |

---

## WP01 Implementation (In Progress)

**Worktree**: `/Users/benjaminmackenzie/Dev/ledger_mobile/.worktrees/001-architecture-critique-implementation-WP01/`
**Branch**: `001-architecture-critique-implementation-WP01`
**Base**: `main` @ `c969f7b`

### Scope
- **T001**: Migrate project edit (3 fields: name, clientName, description)
- **T002**: Migrate business inventory space edit (2 fields: name, notes) - inline comparison
- **T003**: Migrate project space edit (2 fields: name, notes) - inline comparison
- **T004**: Verify TypeScript compilation
- **T005**: Manual verification

### Success Criteria
- All 3 screens use `useEditForm` or inline change detection
- Saves with no changes skip writes
- Single-field edits send only changed fields
- Subscription protection via `shouldAcceptSubscriptionData`
- TypeScript compiles with no NEW errors

### Delegation Strategy
- Launch single sub-agent with full WP01 prompt
- Sub-agent works in WP01 worktree
- Implements all 5 subtasks
- Commits and moves to `for_review`

---

## Next Steps

1. ✅ Read WP01 full prompt - DONE
2. ⏳ Launch WP01 implementation sub-agent - IN PROGRESS
3. ⏳ Monitor sub-agent completion
4. ⏳ Verify WP01 moved to `for_review`
5. ⏳ Start WP02 implementation

---

## Completion Tracking

### WP01 Checklist
- [ ] Sub-agent launched
- [ ] T001 completed (project edit)
- [ ] T002 completed (business space edit)
- [ ] T003 completed (project space edit)
- [ ] T004 completed (TypeScript check)
- [ ] T005 completed (manual verification)
- [ ] Implementation committed
- [ ] Moved to `for_review`

### WP02 Checklist
- [ ] Not started

---

## Risk Management

**Risk 1**: Sub-agent fails to complete WP01
- **Mitigation**: Monitor progress, intervene if blocked
- **Fallback**: Implement directly if sub-agent fails

**Risk 2**: WP01 breaks existing functionality
- **Mitigation**: Careful code review, manual testing
- **Fallback**: Revert commits, investigate

**Risk 3**: TypeScript errors block progress
- **Mitigation**: Sub-agent instructed to fix only NEW errors
- **Pre-existing errors**: Documented in MEMORY.md, ignore

---

## Notes

- All worktrees share `kitty-specs/` via sparse-checkout (status tracking)
- Each WP has isolated workspace (no conflicts)
- Commits in one worktree don't affect others
- Status updates happen in main repo (visible to all agents)
