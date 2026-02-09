# Git Repository Cleanup & Main Branch Restoration

## Context — What Happened

The user's Ledger Mobile repo (`/Users/benjaminmackenzie/Dev/ledger_mobile`) has a broken `main` branch. On **Jan 30**, commit `4fbdd03` "Replace app with firebase skeleton" was pushed to `origin/main`, wiping out the full app and replacing it with a bare Firebase skeleton (3 files in `app/`). All subsequent development (67 commits of real app work) happened on feature branches that were **never merged back to main**.

The user wants main restored to reflect the current state of their app, and all the orphaned worktrees cleaned up.

---

## Current Git State (as of Feb 9, 2026)

### Remotes

- `origin` → `git@github.com:nine4-team/ledger-mobile.git`
- `skeleton` → `/Users/benjaminmackenzie/Dev/firebase_skeleton` (local, irrelevant)
- **`origin/HEAD` points to `chore/replace-with-firebase-skeleton`**, NOT main

### Branch Lineage (ALL LINEAR — no divergence)

All branches share a single linear history. Each is just a point-in-time snapshot:

```
515827b Preserve firebase migration docs
    ↓
4fbdd03 Replace app with firebase skeleton  ← origin/main stuck here
    ↓  (13 commits: "lost track", "spec changes", "UI changes"...)
a4f7b2b many ui changes  ← chore/replace-with-firebase-skeleton, origin/chore/replace-with-firebase-skeleton
    ↓  (5 commits)
bf1f138 docs: add spaces feature implementation plan  ← funny-jang worktree
    ↓  (15 commits: budget system, Phase 5, item edit, spaces, etc.)
a88aef5 refactor: redesign transaction items section  ← intelligent-panini worktree
    ↓  (2 commits)
b16311d feat: add sticky control bar  ← inspiring-haslett worktree
    ↓  (5 commits: architecture doc, Phase 1 critique foundation)
408bc67 feat: implement Phase 1 architecture critique foundation  ← origin/docs/update-budget-category-terminology
    ↓  (2 commits: spec-kitty feature setup, spec addition)
eb3c806 feat: add spec-kitty feature  ← docs/update-budget-category-terminology (LOCAL, not pushed)
```

**`main` diverged at `4fbdd03`** and only has 4 spec-kitty planning commits on top (task generation, WP01 setup). These planning commits touched only `kitty-specs/` files.

### 5 Cursor Worktrees (all detached at `3467bf4`)

All 5 cursor worktrees (`dwr`, `eha`, `kdf`, `ooc`, `ymk`) at `~/.cursor/worktrees/ledger_mobile/` are detached at commit `3467bf4` (within `chore/replace-with-firebase-skeleton` history). Each has experimental ItemCard prototype files — likely throwaway UI experiments. Each has the same 4 modified tracked files + 2-3 untracked prototype files.

### 3 Claude Worktrees

| Worktree | Branch | Commit | Uncommitted Changes |
|---|---|---|---|
| `~/.claude-worktrees/ledger_mobile/funny-jang` | funny-jang | `bf1f138` | `?? CLAUDE.md` (untracked only) |
| `~/.claude-worktrees/ledger_mobile/inspiring-haslett` | inspiring-haslett | `b16311d` | `M .gitignore`, `M CLAUDE.md` |
| `~/.claude-worktrees/ledger_mobile/intelligent-panini` | intelligent-panini | `a88aef5` | Clean |

### 1 Spec-Kitty WP01 Worktree

- Path: `/Users/benjaminmackenzie/Dev/ledger_mobile/.worktrees/001-architecture-critique-implementation-WP01`
- Branch: `001-architecture-critique-implementation-WP01` at `c969f7b`
- **Problem**: Based on skeleton main, not the real app. Has `?? src/hooks/` (a `useEditForm.ts` file we created but should be discarded — the real one exists at `408bc67`)
- Also has `M .gitignore`

### 1 Stash

```
stash@{0}: WIP on docs/update-budget-category-terminology: eb3c806 feat: add spec-kitty feature for architecture critique implementation
```

### Main Worktree Uncommitted Changes

```
 M kitty-specs/001-architecture-critique-implementation/meta.json  (modified by spec-kitty)
?? .claude/
?? .claudeignore
?? .kittify/
?? .plans/
?? .troubleshooting/
?? docs/
```

---

## What Needs to Happen

### Goal

1. **`main` should point to the latest real app code** (commit `eb3c806` from `docs/update-budget-category-terminology`, or its equivalent after merging the spec-kitty planning commits)
2. **All worktrees should be cleaned up** (the claude worktrees and cursor worktrees are stale snapshots of commits already in the linear history)
3. **The WP01 worktree needs to be recreated** from the correct base (the real app, not the skeleton)
4. **`origin/main` should be updated** to reflect the restored main

### Key Decisions for the User

1. **The stash** on `docs/update-budget-category-terminology` — does the user want to keep it? Check what's in it with `git stash show -p stash@{0}`.

2. **The 4 spec-kitty commits on main** (`4eb96da`, `c969f7b`, `874aa1f`, `e7603d5`) — these only touch `kitty-specs/` files. They need to be preserved, either by cherry-picking onto the restored main or rebasing.

3. **The `spec.md` and `meta.json`** created during the failed WP01 attempt — the `meta.json` is tracked (modified in main worktree), the `spec.md` was created. Both are in `kitty-specs/001-architecture-critique-implementation/`. These should be reviewed — the `spec.md` was generated as a placeholder and may need to be replaced with the real one from `ad04d7c`.

4. **Cursor worktrees with prototype files** — the user should decide if any of the experimental ItemCard prototypes (`ItemCardExperimental.tsx`, `ItemCardComposerPrototype.tsx`, `ItemCardOpusPrototype.tsx`, `ItemCardGPT52PrototypeDesign.tsx`, `itemCard/` directory) are worth saving before cleanup.

5. **Claude worktrees** — `inspiring-haslett` has modified `.gitignore` and `CLAUDE.md`. Check if those changes matter before removing.

### Suggested Plan

**Phase 1: Preserve anything at risk**
- Check the stash contents
- Check the inspiring-haslett `.gitignore` and `CLAUDE.md` changes
- Ask user about cursor worktree prototype files
- Back up the spec-kitty planning commits (note their SHAs)

**Phase 2: Reset main to the real app**
- Option A (cleanest): Reset local main to `docs/update-budget-category-terminology` (`eb3c806`), then cherry-pick the 4 spec-kitty commits that only touch `kitty-specs/`
- Option B: Merge `docs/update-budget-category-terminology` into main (creates a merge commit, messier history since main has the skeleton)
- **Recommend Option A** since main's skeleton commits have no value

**Phase 3: Push to origin**
- Force-push main to origin (required since we're rewriting history)
- Confirm with user before force-pushing
- Update origin/HEAD to point to main instead of chore/replace-with-firebase-skeleton

**Phase 4: Clean up worktrees**
- Remove ALL old worktrees (funny-jang, inspiring-haslett, intelligent-panini are all just snapshots of commits already in the linear history — no unique work)
- Remove cursor worktrees (all detached at old commit)
- Remove the broken WP01 worktree
- Remove stale local branches: `chore/replace-with-firebase-skeleton`, `funny-jang`, `inspiring-haslett`, `intelligent-panini`, `001-architecture-critique-implementation-WP01`
- Optionally delete `fix/bottom-sheet-expanded-bg` (commit `3c1ed4c`, already in the linear history via `a158f6f`'s parent)

**Phase 5: Recreate WP01 properly**
- With main now pointing to the real app (including Phase 1's useEditForm hook at `408bc67`), re-run `spec-kitty implement WP01` to create a correct worktree
- The WP01 implementation can then proceed normally

### Important Commits to Know

| SHA | Description | Why It Matters |
|---|---|---|
| `eb3c806` | Latest on docs/update-budget-category-terminology | Most recent real app code (local only, not pushed) |
| `408bc67` | Phase 1 architecture critique foundation | Has the `useEditForm` hook that WP01 depends on |
| `4fbdd03` | Replace app with firebase skeleton | The commit that broke main |
| `4eb96da` | Add tasks for feature 001-architecture-critique-implementation | First spec-kitty commit to preserve |
| `c969f7b` | Planning artifacts for 001-architecture-critique-implementation | Has spec.md and meta.json |

### Verification After Cleanup

1. `git log main --oneline | wc -l` should show ~69+ commits (67 real app + spec-kitty commits)
2. `ls app/` should show project/, items/, transactions/, business-inventory/, settings/, etc.
3. `cat src/hooks/useEditForm.ts` should exist and have the Phase 1 implementation
4. `git worktree list` should show only main (and a fresh WP01 worktree if recreated)
5. `origin/main` should match local main after push
