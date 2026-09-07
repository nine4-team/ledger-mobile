# Workflow Records

This directory stores one durable JSON record per implemented user workflow.
Each record preserves exact authority, affected layers, risk-specific acceptance
checks, source and target pages, inventoried source-surface IDs, every visible
control and option, transitions, loading/empty/error/offline states, blockers,
review, local test commands, and exact-commit CI evidence.
Every UI journey also carries its own exact spec/decision-heading references, so
the source behavior and its preserve/redesign/retire decision stay traceable.

`affectedComponents` names repository-relative files or directories. Validation
derives minimum layers and risks from those paths and from the active target diff;
the record cannot hide a database, RLS, offline, accounting, auth, media,
deletion, migration, UI, or MCP change behind a low-risk declaration.

The active record is named by `current-execution-state.json`. Completed records
remain here and are linked from the implementation tracker, so selecting the next
workflow never overwrites prior UI/control-flow coverage. Method-v3 validation is
implemented by `scripts/check-conversion-current-state.mjs`.

Do not create comment-only source scaffolds, per-component dossiers, standalone
evidence essays, READY commits, or promotion commits around these records.
