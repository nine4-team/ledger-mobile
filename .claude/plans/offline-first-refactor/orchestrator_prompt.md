# Orchestrator Prompt — Offline-First Architecture Refactor

Copy-paste this entire file into a new Claude Code session to execute the refactor.

---

## Your Role

You are an orchestrator. You will **not** write code yourself. You will delegate all implementation to sub-agents (Task tool with `subagent_type: "general-purpose"`), coordinate their execution order, and verify the results.

## Context

The app has 65+ awaited Firestore writes that cause the UI to hang offline. The full plan is at `.claude/plans/offline-first-refactor/plan.md`. Each sub-task has a self-contained prompt pack at `.claude/plans/offline-first-refactor/prompt_packs/chat_*.md`.

## Execution Plan

### Phase 1: Service Layer (blocking — must complete before Phase 2)

1. Read `.claude/plans/offline-first-refactor/prompt_packs/chat_a_service_layer.md`
2. Launch **one** sub-agent with the full contents of that prompt pack as its instructions. Tell the agent to implement all the changes described, then run `npx tsc --noEmit` to verify no type errors.
3. **Wait for it to complete.** Review its output. If `tsc` fails, resume the agent to fix errors before proceeding.
4. Once clean, move to Phase 2.

### Phase 2: UI Screens (all in parallel)

Launch **six** sub-agents simultaneously, one for each prompt pack. For each agent:
- Read the corresponding prompt pack file
- Pass its full contents as the agent's instructions
- Tell the agent to implement all changes described, then run `npx tsc --noEmit`

The six agents (launch all at once):

| Agent | Prompt Pack File |
|-------|-----------------|
| Items | `.claude/plans/offline-first-refactor/prompt_packs/chat_b_item_screens.md` |
| Transactions | `.claude/plans/offline-first-refactor/prompt_packs/chat_c_transaction_screens.md` |
| Spaces | `.claude/plans/offline-first-refactor/prompt_packs/chat_d_space_screens.md` |
| Projects | `.claude/plans/offline-first-refactor/prompt_packs/chat_e_project_screens.md` |
| Settings & Budget | `.claude/plans/offline-first-refactor/prompt_packs/chat_f_settings_and_budget.md` |
| Shared & Request-Docs | `.claude/plans/offline-first-refactor/prompt_packs/chat_g_shared_and_request_docs.md` |

### Phase 3: Final Verification

After all six Phase 2 agents complete:

1. Run `npx tsc --noEmit` yourself to catch any cross-agent conflicts (e.g., two agents editing the same file).
2. If there are errors, launch a fix agent with the error output and the relevant files.
3. Run a final grep to confirm no violations remain:
   - `grep -rn "await addDoc" src/data/` — should return nothing.
   - `grep -rn "await createItem\|await createTransaction\|await createSpace\|await createProject\|await createBudgetCategory\|await createSpaceTemplate\|await createRequestDoc" app/ src/` — should return nothing (these are now synchronous).
4. Summarize what was changed: files modified, patterns applied, any exceptions encountered.

## Rules for Sub-agents

Include these rules in every sub-agent prompt:

- Follow `CLAUDE.md` § Offline-First Coding Rules strictly.
- **Never `await` Firestore write operations in UI code.** Fire-and-forget with `.catch()`.
- **Keep `await` on:** `saveLocalMedia`, `deleteLocalMediaByUrl` (local SQLite), Firebase Storage uploads, Firebase Auth operations, and reads that drive subsequent logic (must use `'offline'` mode).
- **Remove `isSubmitting` / `isSaving` / `isCreating` state** where it only gates on Firestore write completion.
- **Navigate immediately** after firing writes.
- Run `npx tsc --noEmit` after making changes and fix any errors before finishing.

## Error Handling

- If a Phase 2 agent reports `tsc` errors caused by Phase 1 signature changes not being present, it means Phase 1 didn't complete properly. Stop, fix Phase 1, then re-launch the failing agent.
- If two Phase 2 agents edit the same file (e.g., space screens are touched by both Chat D and Chat G), the second write may conflict. The Phase 3 `tsc` check will catch this — fix with a targeted agent.
- If an agent is unsure whether something is a true exception (should stay awaited), it should keep it awaited and flag it in its output for your review.
