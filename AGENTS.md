# Ledger development defaults

- Normal app launches and manual QA must use the production Firebase backend.
- Build and run the plain `LedgeriOS` scheme for iOS Simulator or macOS testing.
- Do not set `USE_FIREBASE_EMULATORS=1` or run the `LedgeriOS (Emulator)` scheme unless the user explicitly requests Firebase-emulator testing or a focused integration test requires it.
- Before handing off a locally launched app, verify that the process environment does not enable Firebase emulators.

## Supabase/PowerSync redesign continuity

- For any Supabase/PowerSync redesign, conversion, migration, or cutover task,
  first read only
  `docs/plans/ledger-accounting-redesign/conversion/current-execution-state.json`,
  inspect `git status`, and run `npm run conversion:state:check`. Read the active
  batch dossier and only the authority sections named by that state file before
  editing. The large README and execution history are reference material, not
  mandatory resume context.
- After a task start, resume, handoff, or context compaction, treat conversation
  history and summaries as advisory. Reconstruct the work from the repository
  current-state record, active dossier, exact Git checkpoint and current diff.
  Run the complete conversion check before changing control-plane status or at
  the integrated batch boundary; do not rerun it merely to recover context.
- Treat `docs/plans/ledger-accounting-redesign/conversion/conversion-manifest.json`
  as the conversion-coverage source of truth. Product specs and the redesign
  decision log remain product authority.
- Run `node scripts/supabase-conversion-ledger.mjs check` after updating
  conversion coverage and at the integrated batch boundary. Resolve discovery
  drift before status advancement.
- Keep `current-execution-state.json` under its enforced size limit and update
  its verified base, active batch, next actions, progress and blockers whenever
  the integration checkpoint changes. Append detailed history to
  `execution-state.md` only at a meaningful batch/status boundary.
- For target implementation, read
  `docs/plans/ledger-accounting-redesign/conversion/vertical-slice-implementation-method.md`
  when the method version in current state changes, then work through the
  recorded active delivery batch. Keep each constituent slice's requirements,
  contracts, verification, evidence and status current. Do not rely on a later
  recap to reconstruct unrecorded work.
- The normal execution unit is one coherent user workflow containing two to
  four tightly related slices. Use focused checks while developing and one
  complete local gate plus one immutable CI run on the integrated normal batch.
  A separate READY commit/full CI is reserved for the high-risk boundaries
  listed by the implementation method.
- Use no more than two disjoint write-capable subagents concurrently. Delegate
  a complete independently testable outcome, give each worker only the current
  state, exact dossier/authority references and owned paths, and have workers
  run focused checks. The integration agent owns shared files, full gates,
  tracker synchronization and promotion.
- Optimize for elapsed time and tokens per verified end-to-end workflow. Do not
  optimize for commit count, surface count, document count or agent utilization,
  and never relax correctness, tenant security, accounting, offline/replay,
  migration/reconciliation or evidence gates to improve the metric.
- Continue autonomously from one bounded checkpoint to the next. Pause only for
  an explicit product/architecture decision, permission or external resource
  named by the control plane, a production-impacting action, or a blocker that
  cannot be resolved safely from repository authority.
- Do not implement redesigned v2 behavior in Firebase. Firebase work is limited
  to read-only discovery/export, backups, final source freeze/rejected-write
  recovery, and retained rollback evidence.
- Do not mark a surface verified from compilation or prose alone, and do not
  authorize production migration from these files without explicit user approval.
