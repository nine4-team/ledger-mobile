# Ledger development defaults

- Normal app launches and manual QA must use the production Firebase backend.
- Build and run the plain `LedgeriOS` scheme for iOS Simulator or macOS testing.
- Do not set `USE_FIREBASE_EMULATORS=1` or run the `LedgeriOS (Emulator)` scheme unless the user explicitly requests Firebase-emulator testing or a focused integration test requires it.
- Before handing off a locally launched app, verify that the process environment does not enable Firebase emulators.

## Supabase/PowerSync redesign continuity

- For any Supabase/PowerSync redesign, conversion, migration, or cutover task,
  first read only
  `docs/plans/ledger-accounting-redesign/conversion/current-execution-state.json`,
  inspect `git status`, and run `npm run conversion:state:check`. After workflow
  selection, read its single `workflow-records/*.json` record and only the
  authority sections named there before editing. The large
  README, generated catalogs, historical dossiers, evidence files and execution
  history are reference material, not mandatory resume context.
- After a task start, resume, handoff, or context compaction, treat conversation
  history and summaries as advisory. Reconstruct the work from the repository
  current-state record, exact Git checkpoint and current diff. Do not run the
  complete conversion suite merely to recover context.
- Treat `docs/plans/ledger-accounting-redesign/conversion/conversion-manifest.json`
  as the conversion-coverage source of truth. Product specs and the redesign
  decision log remain product authority.
- Run `node scripts/supabase-conversion-ledger.mjs check` after changing
  conversion coverage and at the integrated workflow boundary. The surface
  catalog is a passive omission audit, not the unit of implementation progress.
- Keep `current-execution-state.json` under its enforced size limit and update
  its verified base, active workflow, next actions, progress and blockers when
  the workflow or integration checkpoint changes.
- For target implementation, read
  `docs/plans/ledger-accounting-redesign/conversion/vertical-slice-implementation-method.md`
  when the method version in current state changes, then work through the
  recorded active workflow. Do not create comment-only scaffolds, new slice
  dossiers, standalone evidence narratives, READY commits, or promotion-only
  commits for ordinary workflows.
- The normal execution unit is one coherent user workflow. Preserve exhaustive
  page/control/option/transition/state coverage inside that workflow while
  implementing its technical layers together. Use focused checks while
  developing and one complete local gate plus one immutable CI run on the
  integrated workflow. Use the automatic pull-request run; do not manually
  dispatch the same commit. Use a separate short design note and specialist
  review only for the high-risk boundaries listed by the implementation method.
- Before additional product UI implementation, complete the current-app UI
  baseline covering all 167 inventoried UI components/views. Keep every
  completed workflow record so control/option/transition/state coverage remains
  cumulative rather than being overwritten by current state.
- Use no more than two disjoint write-capable subagents concurrently. Delegate
  a complete independently testable outcome, give each worker only the current
  state, exact authority references and owned paths, and have workers
  run focused checks. The integration agent owns shared files, full gates, and
  the compact workflow/checkpoint update.
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
- Do not mark a workflow verified from compilation or prose alone, and do not
  authorize production migration from these files without explicit user approval.
