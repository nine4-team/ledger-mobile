# EVID-CLIENT-BROWSING-STAGING-APPLICATION-FLOW-001 — Client Browsing Staging Application Flow

- Status: independently reviewed IMPLEMENTED candidate; exact synchronized implementation commit and immutable CI pending
- Date: 2026-09-05
- Environment: isolated target worktree and synthetic local fixtures only
- Production/Firebase impact: none
- Slice: `client-browsing-staging-application-flow`
- Baseline: exact READY `db89ef36339f48bff249b2973ea3bc9c5607bb61` / immutable run `33956835407`

## Selected Outcome

Add one standalone read-only Client directory and exact Client-detail section to
the isolated target staging app. The selected boundary is a pure Core
presentation contract and tests, a Core-only observable application model and
tests, a thin runtime adapter, and a SwiftUI view driven only by typed state.

The flow consumes only the existing Account-bound `watchClients` and exact
`watchClient` runtime streams. It does **not** replace the Client-creation flow's
post-create one-shot `watchClient` confirmation. It adds no Client input,
creation, rename, archive, restore, delete, merge, Project relationship or route.

## Authority and Dependency Audit

Canonical Client authority fixes one Account-scoped stable Client identity,
current display name and archive-preserving lifecycle. D-006 makes `ClientID`,
not name, identity. The reviewed Projects/Clients capability dossier adds the
backend-neutral observable contracts relevant here: stable IDs and explicit
freshness, Account scope, readiness and incomplete-detail truth. Offline-first
Rules 1 and 3 require represented local reads to be useful without waiting for
a network round-trip.

Existing verified dependencies own all deeper data meaning:

- `EVID-CLIENT-PROJECT-DIRECTORY-001` — unique Account-scoped Client summaries,
  stable identity, lifecycle, audit fields and typed readiness/completeness;
- `EVID-CLIENT-CORE-DETAILS-001` — exact Account/Client zero-or-one detail,
  lifecycle/audit/revision evidence and every waiting/snapshot/failure state;
- `EVID-CLIENT-PROJECT-DIRECTORY-PROVIDER-001` — Principal/Account-bound
  encrypted local directory/detail streams and independent completeness; and
- `EVID-ACCOUNT-WORKSPACE-PENDING-WORK-RUNTIME-001` — runtime lifecycle and
  non-destructive observation drainage.

The logical-authority crosswalk also freezes two exact query boundaries:
`TQUERY-2ACE415664D8` is the Account Client directory and explicitly leaves
canonical directory ordering unresolved, while `TQUERY-136644A3C02A` is the
exact Account/Client detail read with zero unresolved logical axes. This slice
therefore preserves provider order and invents no sorting comparator.

A fresh feature-specific read-only preflight returned GO for this narrow local
application boundary and retained NO-GO for a larger Client shell or any
mutation. O-042/O-043 remain open, so archived rename behavior, unchanged-save
semantics and raw display-name validation are excluded rather than guessed.

## Implemented Boundary

| Manifest identity | Exact path | Implementation hash | Implemented responsibility |
| --- | --- | --- | --- |
| `SWIFT-D8A992D1F8C1` | `LedgeriOS/LedgerTargetCore/ClientBrowsingPresentation.swift` | `89c7ce7ebadab4d15ea2870c54a286408acf6795229a8ef83673d537280df366` | pure atomic directory/selection/detail presentation |
| `TEST-B6AF2BB84195` | `LedgeriOS/LedgerTargetCoreTests/ClientBrowsingPresentationTests.swift` | `a83ee126bf318154e8766284cdd3668880bf5f739221e9219fa55cb19d5f8259` | deterministic Core presentation matrix |
| `SWIFT-EDBCE3C0BC96` | `LedgeriOS/LedgerTargetAppModel/ClientBrowsingStagingExercise.swift` | `5f14814fb7c7892eee8ae7fa515d6424ac112f4cec36238d5844e9f57b64ad67` | Core-only reactive directory/selection/detail application state |
| `TEST-5F23C8849E45` | `LedgeriOS/LedgerTargetAppModelTests/ClientBrowsingStagingExerciseTests.swift` | `1348abb5b309a410fcdf0af63748e3fc899ce1ef0419c4769d1be1a56740a114` | deterministic stream/cancellation/failure/restart matrix |
| `SWIFT-74AB5DDB20DB` | `LedgeriOS/LedgerTargetApp/ClientBrowsingStagingRuntimeAdapter.swift` | `f6303fe7299475655fae9fd9dbb246a9d5c3b5ff5957f94e2a76b23bafa3aa04` | thin Account-bound runtime adapter only |
| `SWIFT-438CDD8B6992` | `LedgeriOS/LedgerTargetApp/ClientBrowsingStagingExerciseView.swift` | `f13948872c11e0fc95d43e793a49e63da590532819c75598e60c81d604954d03` | typed standalone active/archived directory and detail presentation |

The exact READY commit `db89ef36339f48bff249b2973ea3bc9c5607bb61`
passed all three immutable jobs in run `33956835407`: conversion in 38 seconds,
disposable local Supabase in 1 minute 41 seconds, and isolated target in 6
minutes 40 seconds. That exact green result authorized executable work.

The READY actual-diff review first returned NO-GO with two P2 control
findings: two tracker summaries still used the preceding `459/643` denominator,
and the product-authority crosswalk omitted the existing Client-directory
semantic evidence declared by this package. Both summaries now read `465/649`,
`EVID-CLIENT-PROJECT-DIRECTORY-001` is an explicit conversion-control authority,
and the generated authority audits were refreshed. Final re-review returned GO
with no remaining P0-P3 finding before the exact READY commit was created.

## Implementation Review and Local Proof

The six leaves now implement one pure atomic Client directory/selection/detail
presenter, deterministic Core tests, a Core-only observable application model,
deterministic lifecycle tests, a thin runtime adapter, and a typed SwiftUI view.
The staging shell owns the standalone browser alongside the existing Client
creation and Project flows. The original post-create one-shot `watchClient`
confirmation remains present and independent.

Root review hardened the environment checker so it requires exact adapter
forwarding, rejects provider imports in the view and inline shell ownership,
requires standalone start/view wiring, checks both normal and failed-start
drain-before-close order, freezes every accessibility identity, and proves the
post-create confirmation remains present. Root review also strengthened the
initial test candidate in two places: rapid A-to-B reselection now holds a
noncooperative A open and proves B cannot start before A joins, and a dedicated
test proves stop waits for both active directory and detail observations before
returning. Independent executable review returned GO with no P0-P3 finding.

Fourteen focused Core/AppModel tests pass, including the two six-case
termination matrices. All 455 nonparallel Swift tests in 78 suites, target
environment, contract, MCP/query controls, repeatable generation and both
staging builds are green. Disposable local Supabase verification passes 42
pgTAP checks plus Client and Project RPC checks, and the stack stopped cleanly.
The exact synchronized implementation commit and immutable implementation CI
remain pending. This dossier and its six leaves are therefore `implemented`,
not `verified`.

## Frozen Shared Touchpoints and Dependencies

The implemented shared touchpoints remain narrowly frozen:

- `SWIFT-061553E63650`,
  `LedgeriOS/LedgerTargetApp/LedgerTargetStagingApp.swift`
  (`0efbb8fec335ce5ae6789bed11e3d6bdeaeecc9807cf3073295d99c7041aefb8`):
  adds only standalone Client-browser ownership, view, start and drain-before-
  runtime-close wiring while preserving the post-create one-shot Client
  confirmation, Project Setup and Project browsing behavior;
- `CONFIG-81235587F306` / `FILE-A6E49E3815F4`,
  `scripts/check-target-environment.mjs`
  (`13dbb0e3df7413d1e1d759aa15ad2796bc4551eb92d602f3da9e5fa9d83ded18`):
  adds exact Core/AppModel/adapter containment, standalone wiring, post-create
  preservation, accessibility-source and cleanup-order checks; and
- `CONFIG-2EBA890AF767`,
  `LedgeriOS/LedgerTarget.xcodeproj/project.pbxproj`
  (`af1a6f6c7039b10a9e6649918aa3a7096ea5f97978a284d47af59eaca5d17ae8`):
  post-XcodeGen deterministic membership for the two new app files. Repeated
  generation must remain byte-identical.

The reciprocal dependencies are exact and may not be modified by this slice:

| Manifest identity | Exact path | READY preparation hash | Owner and permitted rule |
| --- | --- | --- | --- |
| `CONFIG-031396750B85` | `LedgeriOS/Package.swift` | `fb9b93c681860bab95a6fc18fc2f1962aff9f99da2367d188082fc5569736c9c` | Platform control; recursive Core/CoreTests/AppModel/AppModelTests membership is consumed as-is |
| `CONFIG-77D38BB6819B` | `LedgeriOS/LedgerTargetProject.yml` | `e74a2659e366d98f41181318a8e5ea1d259888b0e1f8555af797b0cdf02196c9` | Platform control; recursive app-source membership is consumed as-is |
| `SWIFT-401EBD892749` | `LedgeriOS/LedgerTargetCore/ClientProjectDirectory.swift` | `d6fcb4ae91d358433ef1f492d6df9a8f185b419c0741a7b400e53efe715a4cc5` | Client/Project directory contracts; consume exact `watchClients` evidence only |
| `SWIFT-D7F3D08FA568` | `LedgeriOS/LedgerTargetCore/ClientCoreDetailsData.swift` | `32a0d3f76ec6a62194311c9e08fd06902aea163b05ea8fdc2f0597e13f49c1b0` | Client core-detail contracts; consume exact request/update/readiness/revision evidence only |
| `SWIFT-B23F91245E50` | `LedgeriOS/LedgerTargetPowerSync/ClientProjectDirectoryPowerSyncQuery.swift` | `49af060c1b8c9a1fc499a5f6b6b2c8e7de5eed8a69e57d60f212d7431fb24944` | directory provider; reachable only through the runtime facade |
| `SWIFT-2ADDF7B64EA0` | `LedgeriOS/LedgerTargetPowerSync/ClientCoreDetailsPowerSyncQuery.swift` | `23b7f779871cd613cc5a945449c3c24c167ea26260c2b9c37466234551a19745` | exact Client-detail provider; reachable only through the runtime facade |
| `SWIFT-548A8A928FAE` | `LedgeriOS/LedgerTargetPowerSync/LedgerOfflineClientRuntime.swift` | `efe7838b0b73e340da27891d21684704ca3ae1c1ac9f4e0a0dd21c16ac597fcc` | Account-workspace runtime; adapter may forward the two watches and staging closes only after model drainage |
| `SWIFT-75CFE285AF37` | `LedgeriOS/LedgerTargetPowerSync/AccountWorkspacePendingWorkRuntime.swift` | `aa0dfd77900dd4eb7c06f0940d362ad7bdd2958e3499fa04aa37e9192880d6da` | physical runtime lifecycle/observer ownership; consumed for drain-before-close behavior only, with no modification |

The app data-read checklist and logical-authority control inputs are frozen
independently (the first generated filename retains its existing repository
name):

- `docs/plans/ledger-accounting-redesign/conversion/target-query-port-inventory.generated.json`
  — `421812c0887d5ed4b0f0b8c58122d8f0de4372211df14ae33831021bea803326`;
- `docs/plans/ledger-accounting-redesign/conversion/target-query-logical-authority-registry.json`
  — `b67abf7dbdb78c9b89f1eb9e58852e319426f2497a9a9b376f25bc1c9a0416cb`; and
- `docs/plans/ledger-accounting-redesign/conversion/target-query-logical-authority-crosswalk.generated.json`
  — `4b2876c7627afcea6282c53f3cd17615dba6036412efec1500bd48afb411f7b2`.

Schema/RLS/Sync, providers, MCP, Auth, Firebase, migration, release, hosted and
production paths remain outside the writable boundary. The implementation gate
must rehash every path above and reject unexplained drift.

## Required Executable Proof

The pure Core and AppModel suites must prove:

1. atomic active/archived lifecycle segmentation, exact upstream order and
   duplicate display names with stable identity;
2. reciprocal ready/partial/stale/incomplete/source-nonexhaustive versus
   authoritative-empty truth for both segments, with unknown counts before
   represented evidence;
3. current-snapshot-bound stable selection, exact `ClientCoreDetailsRequest`
   capture, and refusal of missing, opposite-segment, cross-Account, malformed
   or stale-captured selection evidence;
4. every waiting, found, incomplete, authoritative-absence, unavailable,
   retryable and required-update detail state, cached and uncached where
   applicable, plus reactive newer name/lifecycle/audit/revision evidence;
5. directory throw, spontaneous cancellation and unexpected normal completion
   before/after first value, exactly-once termination and active-detail drainage;
6. the equivalent complete detail-termination matrix and no late mutation;
7. rapid A-to-B reselection with cancellation/join before B and no A rebound;
8. bounded stop/restart before and after evidence, exactly-once termination,
   post-stop silence and rejection of noncooperative late directory/detail
   values from the old generation;
9. Core/AppModel/PowerSync containment, exact source-level accessibility IDs,
   normal and failed cleanup drainage before runtime close, preserved post-create
   confirmation, and both staging builds; and
10. source-exhaustive TQUERY signature/authority checks that prove upstream
    ordering is preserved and no new provider or MCP query is introduced.

Required source-level accessibility identities are frozen as these literals
and one stable row pattern:

- `target-client-directory-status`;
- `target-client-active-count` and `target-client-archived-count`;
- `target-client-row-active-<ClientID.rawValue>` and
  `target-client-row-archived-<ClientID.rawValue>`;
- `target-client-browser-selected-name` (distinct from the Project browser's
  selected-Client identifier);
- `target-client-detail-state` and `target-client-detail-readiness`;
- `target-client-directory-diagnostic`; and
- `target-client-detail-diagnostic`.

Source checks and successful builds do not claim interactive accessibility; an
app UI-test target would be required for that stronger claim.

## Exact READY and Implementation Gates

Independent review returned GO for the exact comment-only READY diff, and exact
READY commit `db89ef36339f48bff249b2973ea3bc9c5607bb61` passed all three
immutable jobs in run `33956835407`. Executable work then remained within the
six leaves and three frozen shared touchpoints.

Root review and independent executable review cover the implementation and every
frozen proof obligation; final review returned GO with no P0-P3. The exact
synchronized implementation commit must still pass conversion/query controls,
focused and complete nonparallel Swift tests, disposable local Supabase
regressions, repeatable XcodeGen, both staging builds, clean artifacts and all
immutable CI jobs before the slice may advance to verified.

## Explicit Exclusions

Related Projects, Client sorting/search/cards, creation, rename, archive,
restore, delete, merge/reassignment, raw display-name validation or input,
routes/workspace activation, retry commands, media, authorization, Postgres/
schema/handler/Data API/RLS/Sync changes, provider changes, MCP, Auth, migration,
hosted access, Firebase, production, release and cutover are excluded. The
existing post-create one-shot `watchClient` confirmation remains unchanged.

O-023/O-024/O-025/O-040/O-042/O-043 and A-003/A-004/A-007/A-015/A-016 remain
open and unadvanced. The implemented candidate is not migration, production,
release, cutover, or verified-hosted authority.
