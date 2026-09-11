# Ledger development defaults

- Normal app launches and manual QA must use the production Firebase backend.
- Build and run the plain `LedgeriOS` scheme for iOS Simulator or macOS testing.
- Do not set `USE_FIREBASE_EMULATORS=1` or run the `LedgeriOS (Emulator)` scheme unless the user explicitly requests Firebase-emulator testing or a focused integration test requires it.
- Before handing off a locally launched app, verify that the process environment does not enable Firebase emulators.

## Supabase/PowerSync redesign continuity

- Resume from
  `docs/plans/ledger-accounting-redesign/conversion/current-execution-state.json`,
  `git status`, and the current diff. Treat conversation summaries as advisory
  and do not run a full suite merely to recover context.
- `docs/plans/ledger-accounting-redesign/conversion/product-behavior-checklist.json`
  is the only active conversion checklist. It owns current UI
  controls/options/transitions/states, background and MCP behavior, target
  outcomes, direct authority/decision/delivery-profile links, review gaps,
  workflow acceptance, and implementation/test/CI evidence. Specs and confirmed
  decisions remain product authority.
- `current-execution-state.json` is only a compact resume pointer: checkpoint,
  active workflow, next actions, blockers, and exclusions. Do not turn it into a
  second tracker.
- Set `activeWorkflow.baseCommit` to the exact starting commit of the current
  batch and keep it fixed during that batch. It is not a verification claim:
  preserve the last green `verifiedCheckpoint` independently. Never expand the
  active record merely to cover earlier batches since that green checkpoint.
  The active outcome must match its checklist record. Before adding acceptance
  checks or closing a batch, inspect the changed outcome/checks/exclusions
  together; put unrelated work under its owning record. If scope truly changes,
  reconcile those fields explicitly instead of appending to an old catch-all.
- Existing target catalogs, workflow records, implementation trackers, surface
  classifications, crosswalks, dossiers, and generated audits are historical
  evidence. Preserve their exact commits and CI references, but do not keep them
  synchronized, promote individual surfaces, or create replacement tracking
  documents.
- Finish the finite product audit before expanding implementation: review every
  inventoried UI and background/MCP surface plus every redesign/spec/decision
  area; disposition every known behavior; and link every unresolved decision to
  the affected outcomes. An unresolved decision blocks only those outcomes, not
  audit completion. Audit completion does not require premature per-heading
  commands, schema, or test designs.
- Implement one coherent user workflow at a time with the simplest architecture
  that satisfies its approved behavior. Reuse existing capabilities; add an
  abstraction only for a concrete shared problem. Do not create comment-only
  scaffolds, slice dossiers, evidence essays, READY commits, or promotion-only
  commits for ordinary work.
- Conversion boundary: preserve existing UI and backend-independent utilities;
  adapt/extract their backend dependencies inside this worktree, not the Firebase
  checkout. Follow reuse choices and justified replacement exceptions in the
  approved plan; a Supabase target or separate build is not a reason to rebuild.
  For an unplanned replacement, pause that replacement, explain the concrete
  reason and reuse alternative, and obtain user approval before proceeding.
  Continue independent authorized work. Normal diff review must check new
  counterparts against approved exceptions; do not add a recurring reuse audit.
- Record significant technical design changes in
  `docs/architecture/redesign/architecture-decisions.md`: what changed, why,
  preserved behavior/history, tradeoffs, and verification evidence or gaps.
  Link existing specs/checklist evidence; do not duplicate progress tracking.
  Routine edits need no entry. Engineers may improve legacy structures; changes
  to product behavior, information retention or business policy require authority.
- Preserve security, accounting, offline/replay, media, migration,
  reconciliation, and risk-specific evidence. Completion requires concrete
  implementation files and passed story-specific checks for every required
  layer/risk; compilation or prose is not proof.
- Use the method's "Verification execution" commands: focused local checks while
  building, then `npm run conversion:check` and appropriate broader verification
  at the integrated batch boundary. Before pushing, run cheap affected-consumer
  checks: shared SQL grants/schema warrant the full local SQL suite; changed sync
  projections warrant their existing MCP/native parity consumers. Let normal exact-commit CI supply its required
  broad checks; do not automatically duplicate them locally or dispatch duplicate
  CI. A local broad run needs a concrete reason (for example unavailable CI or
  native failure diagnosis), not a new approval or tracking document.
- Push coherent batches, not each tiny edit. While CI runs, continue independent
  authorized work; pending checks block accepting affected work as verified, not
  all progress. Keep evidence tied to its tested commit, and do not mix a new
  batch into the pending batch's acceptance record.
- CI keeps native unit/integration tests, both platform builds, fresh migrations
  and security checks required. UI automation is selected from changes since
  `lastFullUIVerification`, not just the latest push. Advance that existing resume
  pointer only after both full platform UI suites pass at the named commit/run;
  backend-only success must not advance it. Unknown or presentation/build changes
  run UI conservatively. Explicit full verification runs all UI tests. Semantic
  UI-to-data behavior changes require targeted UI evidence even with no view diff.
- Use the method's "Quiet CI waiting" protocol for long test runs. Do not burn
  model turns polling unchanged status or repeatedly reviewing logs. Save the
  exact run/attempt and next action in the existing resume pointer. Prefer existing
  process completion/watcher tools; inexpensive non-AI polling is allowed. A
  watcher process is not proof of an agent wake-up. If a scheduled return is needed,
  base it on that suite's observed runtime, never a blanket hour. Review concise
  results before accepting the batch; retire its watcher. After compaction, reuse
  saved results rather than repeating discovery, testing, or historical log reads.
- M3-M5 are cumulative product gates, not surface-stage gates. M3 requires the
  audited checklist and verified target behavior; M4 adds migration/rehearsal;
  M5 adds explicit cutover readiness. Mapped code surfaces never prove product
  completion.
- Continue autonomously between bounded checkpoints. Pause only for an affected
  unresolved decision, unavailable authority/resource, production-impacting
  action, or a blocker that cannot be resolved safely from repository evidence.
- Do not implement redesigned behavior in Firebase or touch the Firebase
  checkout. Production/hosted access, source freeze, migration, release, and
  cutover require explicit user authorization.
