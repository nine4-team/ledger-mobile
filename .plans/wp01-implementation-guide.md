# Implementation Guide — Architecture Critique (001)

## Current State (as of 2026-02-09 cleanup)

- `main` has the full app codebase (67 commits) plus 4 spec-kitty planning commits on top
- WP01 worktree already exists and is ready to go
- `useEditForm` hook is already scaffolded in the worktree at `src/hooks/useEditForm.ts`
- WP01 status is **"doing"** in tasks.md
- Stash (`stash@{0}`) has unrelated in-progress work (transaction screen, .gitignore) — leave it alone

## 1. Enter the WP01 Worktree — CRITICAL

```bash
cd /Users/benjaminmackenzie/Dev/ledger_mobile/.worktrees/001-architecture-critique-implementation-WP01/
```

**ALL WORK MUST HAPPEN IN THIS DIRECTORY, NOT THE MAIN REPO!**

Verify you're in the right place:
```bash
git branch --show-current
# Should show: 001-architecture-critique-implementation-WP01

ls src/hooks/useEditForm.ts
# Should exist — already scaffolded
```

## 2. Get Implementation Instructions

```bash
~/.local/bin/spec-kitty agent workflow implement WP01 --agent <your-name>
```

**IMPORTANT:**
- MUST provide `--agent <your-name>` to track who's implementing
- Output will be LONG (~1000+ lines)
- **SCROLL TO THE BOTTOM** to see the completion command
- The scaffolded `useEditForm.ts` is a starting point — the prompt will tell you what screens to migrate

## 3. Implement the Work Package

Follow the detailed instructions from the prompt. Key points:
- WP01 migrates 3 simple edit screens (project, 2 spaces) to use `useEditForm`
- The hook tracks changed fields and does partial Firestore writes
- Test as you go

## 4. Commit Your Changes — REQUIRED BEFORE REVIEW

```bash
# Still in worktree directory
git add -A
git commit -m "feat(WP01): migrate simple edit screens to useEditForm"
```

**Why this matters:**
- `move-task` validates commits exist beyond the main branch
- Uncommitted changes will BLOCK the move to `for_review`

## 5. Move to Review

```bash
~/.local/bin/spec-kitty agent tasks move-task WP01 --to for_review --note "Ready for review: migrated 3 screens with change tracking"
```

## 6. Check Status (Optional)

```bash
~/.local/bin/spec-kitty status
```

---

## Recommended Work Order

| Order | WP | Description | Notes |
|-------|-----|-------------|-------|
| 1 | **WP01** | Simple screens (MVP, easiest) | **START HERE — already set up** |
| 2 | WP02 | Settings modal (independent) | |
| 3 | WP03 | Item edit (9 fields) | |
| 4 | WP04 | Transaction edit (13 fields) | Most complex |
| 5 | WP05 | Defensive rendering | Can run in parallel with WP01-04 |
| 6 | WP06 | Documentation | Do LAST after WP01-04 complete |

**Parallelization:** WP01-WP04 + WP05 can all run in parallel if multiple devs. Solo: sequential order above.

## Starting a New WP (WP02+)

```bash
# From main repo root (NOT a worktree)
cd /Users/benjaminmackenzie/Dev/ledger_mobile
~/.local/bin/spec-kitty implement WP##
# Then cd into the worktree path shown in output
```

## Quick Reference

```bash
# Start a new WP
~/.local/bin/spec-kitty implement WP##

# Get implementation prompt
~/.local/bin/spec-kitty agent workflow implement WP## --agent <name>

# Check status
~/.local/bin/spec-kitty status

# Move to review (after committing!)
~/.local/bin/spec-kitty agent tasks move-task WP## --to for_review --note "<summary>"
```

## Key Reminders

- Always work in the worktree directory, never main repo
- Always provide `--agent <your-name>` flag
- Always commit before moving to `for_review`
- Scroll to bottom of workflow prompt for completion command
- `stash@{0}` exists with unrelated work — don't pop it
