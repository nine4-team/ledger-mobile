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
- Preserve security, accounting, offline/replay, media, migration,
  reconciliation, and risk-specific evidence. Completion requires concrete
  implementation files and passed story-specific checks for every required
  layer/risk; compilation or prose is not proof.
- Use focused checks while building, then run `npm run conversion:check` and the
  applicable full local tests once at the integrated boundary. Use the automatic
  pull-request CI run for that exact commit; do not manually dispatch duplicate
  CI for the same commit.
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
