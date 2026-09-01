# Ledger development defaults

- Normal app launches and manual QA must use the production Firebase backend.
- Build and run the plain `LedgeriOS` scheme for iOS Simulator or macOS testing.
- Do not set `USE_FIREBASE_EMULATORS=1` or run the `LedgeriOS (Emulator)` scheme unless the user explicitly requests Firebase-emulator testing or a focused integration test requires it.
- Before handing off a locally launched app, verify that the process environment does not enable Firebase emulators.

## Supabase/PowerSync redesign continuity

- For any Supabase/PowerSync redesign, conversion, migration, or cutover task,
  read `docs/plans/ledger-accounting-redesign/conversion/README.md` and
  `docs/plans/ledger-accounting-redesign/conversion/execution-state.md` before
  acting.
- After a task start, resume, handoff, or context compaction, treat conversation
  history and summaries as advisory. Reconstruct the work from the repository
  control files, inspect the current diff, and rerun the required conversion
  check before editing or advancing status.
- Treat `docs/plans/ledger-accounting-redesign/conversion/conversion-manifest.json`
  as the conversion-coverage source of truth. Product specs and the redesign
  decision log remain product authority.
- Run `node scripts/supabase-conversion-ledger.mjs check` before resuming work and
  after updating conversion coverage. Resolve discovery drift before target
  implementation.
- Update the manifest, evidence index, generated coverage, and execution-state
  next action at every bounded checkpoint so work survives context compaction,
  task handoff, and restart.
- For target implementation, read
  `docs/plans/ledger-accounting-redesign/conversion/vertical-slice-implementation-method.md`
  in full, work through exactly one active slice dossier, and keep the dossier's
  requirements, contracts, verification, evidence, and status current as the
  code changes. Do not rely on a later recap to reconstruct unrecorded work.
- Continue autonomously from one bounded checkpoint to the next. Pause only for
  an explicit product/architecture decision, permission or external resource
  named by the control plane, a production-impacting action, or a blocker that
  cannot be resolved safely from repository authority.
- Do not implement redesigned v2 behavior in Firebase. Firebase work is limited
  to read-only discovery/export, backups, final source freeze/rejected-write
  recovery, and retained rollback evidence.
- Do not mark a surface verified from compilation or prose alone, and do not
  authorize production migration from these files without explicit user approval.
