# EVID-PROJECT-SETUP-APPLICATION-FLOW-001 — Existing-Client Project Setup Application Flow

- Status: READY candidate; executable implementation prohibited until exact
  immutable READY CI passes
- Date: 2026-09-05
- Environment: isolated target worktree and synthetic local fixtures only
- Production/Firebase impact: none
- Slice: `project-setup-existing-client-application-flow`

## Selected Outcome

Replace the target staging app's provisional hardcoded Project form with one
tested backend-neutral application model, a thin PowerSync runtime adapter, and
a SwiftUI form that creates a Project for a represented existing Client.

The form consumes the verified Client-selection and budget-category snapshots,
builds the verified `ProjectSetupFormPreparation`, and submits only through the
verified `ProjectSetupUseCase`. It does not construct a Project command itself.
Zero categories is valid; no Client or category is auto-selected; selected
categories carry `nil` allocation in this bounded slice.

## Authority and Dependency Audit

Canonical Project and Client specs authorize stable existing-Client identity,
required Project name, optional description, zero categories, and exact nullable
category intent. Existing verified dependencies own all deeper meaning:

- `EVID-PROJECT-EXISTING-CLIENT-SELECTION-001` — represented active Client
  selection and readiness;
- `EVID-BUDGET-CATEGORY-REFERENCE-001` and
  `EVID-BUDGET-CATEGORY-REFERENCE-POWERSYNC-PROVIDER-001` — category identity,
  eligibility, canonical order, exact fields, local completeness and readiness;
- `EVID-PROJECT-SETUP-FORM-PRESENTATION-001` — preparation, selection,
  fingerprints, description and nullable allocations;
- `EVID-PROJECT-SETUP-001` and `EVID-PROJECT-SETUP-USE-CASE-001` — command and
  single-dispatch receipt validation;
- `EVID-PROJECT-SETUP-PROVIDER-001` — isolated local Project acceptance and
  readback mechanics;
- `EVID-CLIENT-PROJECT-DIRECTORY-PROVIDER-001` and
  `EVID-ACCOUNT-WORKSPACE-PENDING-WORK-RUNTIME-001` — Account-bound local Client
  rows and close-aware runtime streams; and
- `EVID-OPERATION-CORE-001` — queued/applied/rejected local operation semantics.

The application flow may consume these meanings but may not recreate or extend
them.

## Frozen READY Boundary

Primary comment-only leaves:

| Manifest identity | Exact path | READY source hash | Future responsibility |
| --- | --- | --- | --- |
| `SWIFT-64E1171C47C5` | `LedgeriOS/LedgerTargetAppModel/ProjectSetupStagingExercise.swift` | `f2d249166c21a21024cc6a396b7e79ed96c41db5fcd264498c689c222c9d01d4` | backend-neutral two-stream application model and submission state |
| `TEST-E92B32DB7642` | `LedgeriOS/LedgerTargetAppModelTests/ProjectSetupStagingExerciseTests.swift` | `63a6f3e7062e3e41ea49245c977df74b1d1f34a95781b20552769d82dc170fe6` | executable controlled-stream and setup-port matrix |
| `SWIFT-99B1B3CFBB7A` | `LedgeriOS/LedgerTargetApp/ProjectSetupStagingRuntimeAdapter.swift` | `249f00dd85ce93c9f59a34959c589378ff1c405ce82a4cfdd3c24453628ad85b` | thin runtime-to-application-model adapter only |
| `SWIFT-1F2F5FE68160` | `LedgeriOS/LedgerTargetApp/ProjectSetupStagingExerciseView.swift` | `bb3c57f63de05946926c7d0523423a0bc8885219efe9dc65a4a99f2afd2380ee` | existing-Client/category form and bounded receipt/readiness presentation |

Shared touchpoints retain their primary owners and may change only as follows:

| Manifest identity | Exact path | READY source hash | Permitted change |
| --- | --- | --- | --- |
| `CONFIG-031396750B85` | `LedgeriOS/Package.swift` | `dade86ebb76053a86801818138c4b31e2a831d1abc22ca5037098b0cced18d13` | add AppModel product/target and AppModel test target, depending only on Core |
| `CONFIG-77D38BB6819B` | `LedgeriOS/LedgerTargetProject.yml` | `a5db07061d0dce3604c389a6665f47423e397f50dc27db4eb70386cbc1112ef8` | link the AppModel product only |
| `CONFIG-2EBA890AF767` | `LedgeriOS/LedgerTarget.xcodeproj/project.pbxproj` | `32d8f2f3de271894567930a0731eb1ca6d874168d34cd30c8420fc771bb64d8c` | generated consequence of the reviewed target-project spec only |
| `SWIFT-061553E63650` | `LedgeriOS/LedgerTargetApp/LedgerTargetStagingApp.swift` | `ed81e5d9171f89deafe255fcbfcd5d2f59c7ef152fece0c4f25762403b3fd839` | replace only inline Project Setup form/model logic; preserve bootstrap, banner, Client creation, browser and runtime lifecycle |
| `CONFIG-81235587F306`, `FILE-A6E49E3815F4` | `scripts/check-target-environment.mjs` | `17daa2f8e12237f60d0ce8f090ec6397faad5dd9b833a9cfd73bff9728ea190e` | exact module graph, import/API, direct-command and accessibility-source assertions only |
| `FILE-208B7E9D7F47` | `scripts/supabase-conversion-ledger.mjs` | `a0fd62a93119370cc0c2e5fb83fa946aad690b5248971b43e18e62fc9bd4b2b4` | already-reviewed discovery of AppModel source/test roots only |

`LedgerOfflineClientRuntime.swift`, `AccountWorkspacePendingWorkRuntime.swift`,
all Core Project Setup/Client/category leaves, Postgres, RLS, Sync configuration,
MCP, Firebase, migration, release and production paths remain byte-unchanged.

## Required Executable Proof

The real AppModel suite must cover both stream arrival orders; subsequent
partial/stale/ready and incomplete/authoritative-empty changes; no default
selection; selection pruning; zero categories; selected-null category intent;
valid and invalid submission; simultaneous-submit single dispatch; stable
Project and Operation IDs across an ambiguous failure and explicit retry; exact
queued/applying/applied/rejected/superseded/resolved receipt presentation; typed
and bounded failures; cancellation; retained input; stream
drainage; and no post-stop mutation.

The target environment control must prove the AppModel package imports only
Core, the thin app adapter alone imports PowerSync, the app constructs no
`CreateProjectCommand`, and both iOS/macOS staging builds include the new form.
Exact stable accessibility identifiers or labels/status values are required for
Project name, the existing-Client picker, every category control keyed by stable
category identity, submit, both readiness states, diagnostics and receipts.

## Independent READY Review

The first independent package audit returned NO-GO because the four new leaves
were not yet classified and the conversion discoverer had intentional but
unacknowledged source drift. It also required explicit dependencies, frozen
shared IDs/hashes, no Client/category auto-selection, stable ambiguous-retry
identity, exact receipt-state wording, accessibility/source checks, and byte-
unchanged runtime/Core/provider dependencies. This corrected READY candidate
adds those controls. The second review confirmed those findings closed but
returned NO-GO because simultaneous submission, ambiguous retry, all six local
receipt states and the promised accessibility surface were not explicit in the
test matrix. Those exact cases are now frozen. A final exact-package re-review
is still required before the READY commit.

## Explicit Exclusions

O-043 new-Client input; O-040 pins/defaults/cards and full production form
design; O-026 category administration/final download visibility; O-023 media;
O-024 Project deletion; O-025 Client reassignment/merge; A-003/A-004 hosted
PowerSync; A-007/A-016 Auth/current authorization; schema, handlers, Data API,
RLS, Sync, MCP, migration, hosted access, Firebase, production, release and
cutover remain open and unadvanced.
