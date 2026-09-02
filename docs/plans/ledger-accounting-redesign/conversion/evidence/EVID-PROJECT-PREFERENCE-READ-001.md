# EVID-PROJECT-PREFERENCE-READ-001 — Project Preference Read Contracts

- Timestamp: 2026-09-02
- Class: implementation planning / provider-free current-Principal preference read
- Source baseline: `fe018501d67cc84b6f140b2645b8a8149ea5c4f6` on
  `firebase`; the source worktree and shipped app remain unchanged
- Claimed target surfaces: `SWIFT-C6AE96622805`, `TEST-96AAFA22224B`
- Slice dossier:
  `conversion/implementation-slices/project-preference-read-contracts.json`
- Verification state: ready; all executable obligations remain planned
- Ready scaffold hashes:
  - `ProjectPreferenceData.swift`:
    `dcf06d2a71a083a4025bad3d92a658f83c6a2d265ce4f10ccbbd654f4bb49bc3`
  - `ProjectPreferenceDataTests.swift`:
    `e5e274a833492de9cc8fd4974b0ac40ea1863312fbbceaf40ea59222fe0878d4`

## Selection and Scope

After verifying Project-note creation, the remaining Phase 1 Project/Client/
reference dependency audit excluded Project-note edit/removal because their
explicit role policy is not settled. It selected the current-Principal Project
preference read as the next smallest complete dependency. This read is needed
by Project list/detail presentation and can be defined without deciding a
preference writer, Auth provider, schema, Sync implementation or budget
calculation.

Exactly two target-only comment scaffolds are claimed in the provider-free core
and test roots. The slice covers ordered pinned category identities, revision,
exact Account/Principal/Project scope, deterministic local evidence and the
distinction between authoritative absence and a row that is merely unavailable
offline. Existing Firebase preference mechanics, all app UI, writes, target
provider work, migration and production remain unadvanced.

## Authority and Product Boundary

- Canonical Project budget authority remains the paid-plus-unpaid contribution
  model. A personal pin may affect presentation order but cannot supply or
  modify a budget amount, allocation or contribution.
- The reviewed Project/Client/reference dossier preserves per-Principal,
  per-Project pins and requires that only the authenticated Principal's
  revisioned preferences synchronize inside the exact Account/environment.
- AccountID and PrincipalID in a provider-free request are expected scope, not
  proof of identity. A later trusted session/RLS/Sync boundary must derive and
  enforce the authenticated Principal.
- Ordered stable category IDs are preference evidence. Category names,
  lifecycle and visibility resolve from the separate verified category read;
  archived or presently unresolved IDs are not silently deleted here.
- A complete local directory with no Project row means no preference was
  stored. The same absence in partial/stale evidence means not available, not
  an empty stored preference.

This boundary improves the current service, which can collapse listener failure
or missing local data to nil/empty and accepts caller-selected user paths.

## Why Open Decisions Do Not Block This Slice

- O-026 controls shared reference-data mutation, not reading a Principal's own
  preference identities. No shared category writer or preference writer is
  created.
- A-007 and A-016 control concrete authentication correlation and offline
  authorization lease behavior. This contract carries expected scope and
  already-authorized local evidence but performs no authentication or access
  decision.
- A-003/A-004 and physical verification control provider schema, Sync and
  durable local implementation. All are excluded from this provider-free
  contract.
- First-use default pins, category visibility composition and optional list/grid
  preferences are presentation behavior and are not invented by this bounded
  stored-preference read.

## Ready-Gate Contract

The dossier freezes seven exact requirements and requires:

- one ProjectPreferenceSnapshot per stable Account/Principal/Project identity,
  with ordered unique BudgetCategoryIDs, valid empty pins and one revision;
- an exact Account/Principal directory request whose query fingerprint is
  derived and revalidated rather than caller-authored;
- one canonical directory snapshot that preserves Project row order,
  per-row pin order, already-authorized visible count, completeness, quality,
  LocalDataVersion and finite as-of time;
- stored, notStored and notAvailable lookup states so missing local evidence
  never masquerades as an authoritative empty/default preference;
- atomic refusal of cross-scope rows, duplicate Projects/pins, fingerprint/
  count/request mismatch and malformed serialized values;
- one narrow provider-free read port; and
- negative assertions excluding category labels/amounts, user paths,
  authorization claims, credentials and backend types.

Postgres, handlers, Data API grants, RLS, Sync Streams, physical persistence,
preference writes, category resolution, budget projection, app/MCP wiring,
migration, observability and feature activation are explicit
nonapplicabilities.

## Ready-Gate Verification

The two comment-only surfaces are acknowledged through the reviewed Project/
Client/reference batch and are `target_mapped`. The dossier has no blocker;
every requirement is reciprocally covered by domain, offline-restart, offline-
rejection, exact-port and exact-commit operational obligations.

The complete ready gate passed from the dedicated Supabase worktree with:

- conversion sync/check/report plus capability/query/residual controls;
- M0, with M1/M2 retaining their expected prerequisite blockers;
- the complete existing target test suite while both scaffolds remain
  comment-only;
- target environment and generated app/MCP contract checks;
- macOS and generic iOS Simulator staging builds;
- XcodeGen/source-project stability; and
- `git diff --check`.

The synchronized ledger records 765 surfaces, including 750 currently
discovered. It reports 339 of 503 target-relevant surfaces mapped or later, 164
residual surfaces and 43 validated blockers. M0 passes; M1 and M2 retain exactly
their expected 2 and 164 blockers. Only the three documented retired-path
warnings remain. All 128 existing target tests in 29 suites pass while the two
new scaffolds contain no executable Project-preference behavior.

Passing this local ready gate authorizes only the bounded provider-free
implementation named in the dossier. Exact ready-commit CI and later exact-
implementation-commit CI remain required.

## Permanent Limits

This ready plan cannot:

- authenticate or authorize the supplied Principal or expose another
  Principal's preferences;
- persist, synchronize, display or mutate preference rows;
- synthesize first-use/default pins or decide list/grid presentation;
- resolve category names, lifecycle or visibility, or delete archived/stale
  category identities;
- calculate or modify Project budget allocations, contributions or totals;
- define a Postgres table/index, handler, grant, RLS policy, Sync Stream or
  local database adapter;
- wire Project UI, MCP tools, transport or capability registration;
- decode, deduplicate, repair, quarantine or reconcile Firebase preference
  documents; or
- authorize hosted resources, deployment, production migration, release or
  cutover.

No production read or mutation, shipped-app implementation, provider
connection, hosted resource, migration, deployment or cutover occurred.
