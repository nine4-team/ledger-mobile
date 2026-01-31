# Architecture (`10_architecture/`)

Architecture-level docs and invariants.

Notes:
- This repo’s offline-first direction is defined in [`OFFLINE_FIRST_V2_SPEC.md`](../../../../OFFLINE_FIRST_V2_SPEC.md).
- This directory should **not** describe a bespoke “sync engine” (outbox/cursors/meta sync docs). The baseline is **Firestore native offline persistence** + **scoped listeners**, with **optional SQLite** used only for a **derived search index**.

Put docs here like:
- `target_system_architecture.md`
- `security_model.md`
- `offline_first_principles.md`

