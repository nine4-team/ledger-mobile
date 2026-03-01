# Implementation Guide — Architecture Critique (001)

## Current State (as of 2026-02-09 cleanup)

- `main` has the full app codebase (67 commits) plus 4 spec-kitty planning commits on top
- WP01 worktree already exists at `.worktrees/001-architecture-critique-implementation-WP01/`
- `useEditForm` hook is already scaffolded in the worktree at `src/hooks/useEditForm.ts`
- WP01 status is **"doing"** in tasks.md (already claimed by claude-sonnet agent)
- Stash is cleared — no uncommitted work blocking

## 1. Enter the WP01 Worktree ⚠️ CRITICAL

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

**What this does:**
- Displays the full WP01 prompt (~1000+ lines of detailed instructions)
- Auto-moves WP01 from "planned" → "doing" in tasks.md (if not already doing)
- Records the agent name in the task metadata

**IMPORTANT:**
- MUST provide `--agent <your-name>` to track who's implementing
- Output will be LONG — **SCROLL TO THE BOTTOM** for the completion command
- The scaffolded `useEditForm.ts` is a starting point — the prompt will tell you what screens to migrate

## 3. Implement the Work Package

Follow the detailed instructions from the prompt. Key points:
- WP01 migrates 3 simple edit screens to use `useEditForm`:
  - `app/projects/[id]/edit.tsx` (project edit)
  - `app/shared-spaces/[id]/edit.tsx` (shared space edit)
  - `app/personal-spaces/[id]/edit.tsx` (personal space edit)
- The hook tracks changed fields and does partial Firestore writes
- Test each screen as you go

## 4. Commit Your Changes ⚠️ REQUIRED BEFORE REVIEW

```bash
# Still in worktree directory
git add -A
git commit -m "feat(WP01): migrate simple edit screens to useEditForm"
```

**Why this matters:**
- `move-task` validates commits exist beyond the base branch
- Uncommitted changes will BLOCK the move to `for_review`
- Prevents lost work

## 5. Move to Review

```bash
~/.local/bin/spec-kitty agent tasks move-task WP01 --to for_review --note "Ready for review: migrated 3 screens with change tracking"
```

**What this does:**
- Validates you have commits in the worktree
- Updates tasks.md automatically (no manual editing needed!)
- Marks WP01 as "for_review" in the kanban
- Records your note in the activity log

## 6. Check Status (Optional)

```bash
~/.local/bin/spec-kitty status
# or
~/.local/bin/spec-kitty agent tasks status
```

Shows the kanban board with all WPs across lanes.

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

---

## Starting a New WP (WP02+)

```bash
# From main repo root (NOT a worktree)
cd /Users/benjaminmackenzie/Dev/ledger_mobile

# Create worktree and get implementation prompt
~/.local/bin/spec-kitty implement WP02
# This creates .worktrees/001-architecture-critique-implementation-WP02/
# and outputs the path to cd into

# Enter the worktree
cd .worktrees/001-architecture-critique-implementation-WP02/

# Get the implementation prompt
~/.local/bin/spec-kitty agent workflow implement WP02 --agent <your-name>

# Follow steps 3-5 above
```

**Alternative:** If you want to branch WP02 from WP01's changes (dependency):
```bash
~/.local/bin/spec-kitty agent workflow implement WP02 --agent <your-name> --base WP01
# This creates a worktree branching from WP01's feature branch
```

---

## Quick Reference

```bash
# Create worktree for a WP (from main repo root)
~/.local/bin/spec-kitty implement WP##

# Get implementation prompt (from worktree)
~/.local/bin/spec-kitty agent workflow implement WP## --agent <name>

# Check kanban status
~/.local/bin/spec-kitty status

# Move to review (after committing!)
~/.local/bin/spec-kitty agent tasks move-task WP## --to for_review --note "<summary>"

# List all tasks
~/.local/bin/spec-kitty agent tasks list-tasks

# Add activity log entry
~/.local/bin/spec-kitty agent tasks add-history WP## --note "<what you did>"
```

---

## Key Reminders

- ✅ Always work in the worktree directory, never main repo
- ✅ Always provide `--agent <your-name>` flag when using workflow commands
- ✅ Always commit before moving to `for_review`
- ✅ Scroll to bottom of workflow prompt for completion command
- ✅ The Python script updates tasks.md automatically — no manual editing needed
- ✅ WP01 is already in "doing" lane — just cd into the worktree and get the prompt

---

## Troubleshooting

**"Command not found: spec-kitty"**
```bash
~/.local/bin/spec-kitty --version
# If that works, spec-kitty is installed but not in PATH
# Use full path: ~/.local/bin/spec-kitty
```

**"Work package already in doing lane"**
- This is expected for WP01 — just proceed with implementation
- The command is idempotent

**"No commits found beyond base"**
- You forgot to commit your changes
- Run `git add -A && git commit -m "..."` first
