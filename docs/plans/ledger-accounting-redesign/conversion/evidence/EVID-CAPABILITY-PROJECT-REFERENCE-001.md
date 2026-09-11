# EVID-CAPABILITY-PROJECT-REFERENCE-001 — Projects, Clients, Settings, and Reference Data

- Timestamp: 2026-08-31
- Class: static source/spec characterization and capability synthesis
- Repository baseline: `d83c64724fe4e92be27c62f425979bd30fcfc9bb`
  on `dev`; shared worktree was already dirty
- Production reads or mutations: none
- Target implementation/schema/RLS/Sync Stream changes: none
- Operator: Codex
- Primary artifact:
  `capability-dossiers/projects-clients-settings-and-reference-data.md`

## Sources Reviewed

- Project service/protocol/model, ProjectContext, create/edit/list/detail/card/
  picker/note flows, form/list calculations and tests;
- budget category, Project allocation, Project preference, vendor suggestion,
  Space-template and settings services/models/UI/protocols;
- the New Space template stub and Space-detail no-op Save as Template caller;
- MCP Project, Project-note and budget/category modules and granular tools;
- current Project/preset/preference Firestore rules, callable Project creation,
  generated query catalog and prior backend characterization;
- historical Supabase-to-Firebase reader/types/transformer and current category
  audit/repair tooling as migration-shape evidence only;
- `projects.md`, `client-identity-and-project-transfers.md`,
  `budget-management.md`, `spaces.md`, `financial-access-controls.md`, D-003
  through D-006 and architecture/cutover guardrails; and
- the prior identity and media dossiers for account-session, operation-receipt,
  logout and Project hero attachment boundaries.

## Method and Result

Static source and call-site searches were reconciled with models, existing
tests, specs, architecture decisions, rules, Functions, MCP tools, generated
queries and migration utilities. The dossier separates current mechanics from
the intended outcome, classifies behavior, defines target-neutral commands/read
ports, names security/sync/migration requirements, and owns acceptance tests
without choosing final target tables.

The stale guidance was corrected where authority is sufficient: `projects.md`
now marks free-text Client identity, partial Project setup and orphaning delete
as current Firebase behavior; `budget-management.md` no longer treats blanket
last-write-wins and cached summaries as acceptable target behavior; and
`spaces.md` records the incomplete template callers and unchecked-state defect.
O-024–O-026 record the product/security choices that cannot be silently made.

## Material Findings

- There is no current Client entity. Project creation/editing, cards, search,
  reports and MCP use editable `clientName` text.
- App Project setup and edit dismiss before independent Project, per-category
  and media work completes. Errors are suppressed, so the current UX can report
  success for partial configuration.
- Current hard delete removes only the Project document and intentionally
  leaves dependent data orphaned.
- App and callable Function Project creation have different side effects; the
  callable seeds categories/pins while the app directly writes and separately
  configures categories.
- Project detail readiness is the incidental sum of nine independent listeners;
  no complete-history/partial state is represented.
- Current preference rules permit any account member to access any member's
  Project preferences.
- Category/system/type/dependency validation is not enforced at the current
  direct-write boundary, and Project/category/template reorder operations can
  apply partially.
- Vendor suggestions are a race-prone whole-array write and are correctly only
  suggestions, not Vendor identity.
- Template management persistence exists, but creation does not load/apply
  templates, Save as Template performs no write while reporting success, and
  create-from-Space copies checked state contrary to the spec.
- Settings contains another direct signout path that bypasses pending-work
  protection; the identity contract applies to it.
- Historical reverse-direction migration code contains useful variants but is
  not the Firebase-to-target importer or target schema.

## Limitations

Production Project/Client-name distributions, orphan counts, Project child
variants, preferences, presets, category null/zero variants and note timestamp/
author variants remain unconfirmed until the fail-closed read-only profile runs.
This evidence supports target-independent port/command/test mapping and a
synthetic Client+Project offline/security spike. It does not authorize a
Supabase schema, RLS policy, PowerSync Stream, Firebase adapter/refactor,
production read/mutation, or migration.
