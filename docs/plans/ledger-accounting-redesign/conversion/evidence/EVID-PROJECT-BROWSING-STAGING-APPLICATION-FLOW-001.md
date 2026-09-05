# EVID-PROJECT-BROWSING-STAGING-APPLICATION-FLOW-001 — Project Browsing Staging Application Flow

- Status: verified
- Date: 2026-09-05
- Environment: isolated target worktree and synthetic local fixtures only
- Production/Firebase impact: none
- Slice: `project-browsing-staging-application-flow`

## Selected Outcome

Replace only the target staging app's inline Project directory projection,
stable-ID selection, and Project-detail observation with a tested Core-only
application model, a thin runtime adapter, and a SwiftUI view.

The model consumes the existing Account-bound local Project directory and exact
Project-detail streams. It reuses the verified directory-selection and detail-
header presentation contracts instead of interpreting provider rows, lifecycle,
readiness, completeness, or failures itself.

## Authority and Dependency Audit

Canonical Project requirements already require current lists/details to remain
usable from synchronized local data with explicit readiness. The Client/Project
identity spec fixes stable ProjectID/ClientID relationship authority. Existing
verified dependencies own all deeper meaning:

- `EVID-PROJECT-BROWSING-PRESENTATION-001` — active/archived projection,
  upstream order, false-empty truth, evidence-bound selection, exact request
  derivation, and every detail-header state;
- `EVID-PROJECT-CORE-DETAILS-001` — exact Project/Client core detail and local
  revision/readiness evidence;
- `EVID-CLIENT-PROJECT-DIRECTORY-PROVIDER-001` — Account/Principal-bound
  encrypted local Project directory/detail streams; and
- `EVID-ACCOUNT-WORKSPACE-PENDING-WORK-RUNTIME-001` — runtime lifecycle and
  non-destructive observation drainage.

The application flow may compose these meanings but may not recreate or extend
them. A feature-specific preflight returned GO for this narrow boundary and
retained the earlier NO-GO for a full Project shell, which would require open
route/workspace, media, budget-card, search/sort, and mutation decisions.

## Frozen Comment-Only Boundary

| Manifest identity | Exact path | READY preparation hash | Future responsibility |
| --- | --- | --- | --- |
| `SWIFT-CAB085E24751` | `LedgeriOS/LedgerTargetAppModel/ProjectBrowsingStagingExercise.swift` | `9c7b2afc8dafd69e7031624723db71494126b0f1abd628183cc65407664327c9` | Core-only reactive directory/selection/detail application state |
| `TEST-5C7E5E715EAE` | `LedgeriOS/LedgerTargetAppModelTests/ProjectBrowsingStagingExerciseTests.swift` | `86c0cb74b71bda036a6f1a954462f95d74426c97c1608b004225ee11b807a239` | deterministic directory/detail/cancellation/failure matrix |
| `SWIFT-AA91CE0C3FAB` | `LedgeriOS/LedgerTargetApp/ProjectBrowsingStagingRuntimeAdapter.swift` | `db5527878ea8c48fd3c8fa105a34a0dc1d6683168f6ace6f7b8ff086d87945a0` | thin Account-bound runtime adapter only |
| `SWIFT-07427FF0DA84` | `LedgeriOS/LedgerTargetApp/ProjectBrowsingStagingExerciseView.swift` | `579270f6918dd24f62f7a1fe5c7ec561d399abfa286381d1ae761e863d98efb0` | typed active/archived directory and detail-state presentation |

Permitted implementation touchpoints are narrowly frozen:

- `LedgeriOS/LedgerTargetApp/LedgerTargetStagingApp.swift`
  (`dd4f9cea4058e5af50c542d6f1de50093b677e679a0bfe12899f1827062cb240`):
  replace only inline Project browsing state/projection/selection/detail
  observation and lifecycle wiring;
- `scripts/check-target-environment.mjs`
  (`1b212c23faa4cc557d0812a42f50906b8caa8b056637db8435464b6b1d1cd599`):
  add exact AppModel/adapter containment and accessibility-source checks; and
- `LedgeriOS/LedgerTarget.xcodeproj/project.pbxproj`
  (`5310d0517d236df6361c4229254c7ff96ec1c0b82c9014930a40e9288dda0dac`):
  deterministic XcodeGen membership for the two new app files only.

The reciprocal frozen dependencies are exact, not implied:

| Manifest identity | Exact path | READY preparation hash | Owner and permitted rule |
| --- | --- | --- | --- |
| `CONFIG-031396750B85` | `LedgeriOS/Package.swift` | `fb9b93c681860bab95a6fc18fc2f1962aff9f99da2367d188082fc5569736c9c` | Platform control; recursive AppModel/AppModelTests membership is consumed as-is and this slice may not modify the file |
| `CONFIG-77D38BB6819B` | `LedgeriOS/LedgerTargetProject.yml` | `e74a2659e366d98f41181318a8e5ea1d259888b0e1f8555af797b0cdf02196c9` | Platform control; recursive app-source membership is consumed as-is and this slice may not modify the file |
| `SWIFT-401EBD892749` | `LedgeriOS/LedgerTargetCore/ClientProjectDirectory.swift` | `d6fcb4ae91d358433ef1f492d6df9a8f185b419c0741a7b400e53efe715a4cc5` | Client/Project directory contracts; consume the typed watch port only, with no modification |
| `SWIFT-6075C2D24BAD` | `LedgeriOS/LedgerTargetCore/ProjectDirectoryPresentation.swift` | `bc6545189e12322b35c98180b0f35b0fea275c2b7dc4ab616679569340b7083e` | Project browsing presentation contracts; consume projector, stable selection and request validation only, with no modification |
| `SWIFT-4C4690368BEC` | `LedgeriOS/LedgerTargetCore/ProjectCoreDetailsData.swift` | `a8dac7b7b351db6722d5ab4f9cd851d86f3d36439298539b83fa3e88d6696605` | Project core-detail contracts; consume the exact typed stream and update states only, with no modification |
| `SWIFT-B23F91245E50` | `LedgeriOS/LedgerTargetPowerSync/ClientProjectDirectoryPowerSyncQuery.swift` | `49af060c1b8c9a1fc499a5f6b6b2c8e7de5eed8a69e57d60f212d7431fb24944` | Client/Project provider slice; reachable only through the runtime facade, with no direct construction or modification |
| `SWIFT-56CB8BCDD85C` | `LedgeriOS/LedgerTargetPowerSync/ProjectCoreDetailsPowerSyncQuery.swift` | `983e5d79a903893f509e3ac2caf4add5b90c15be794faa200f232325d8a08b09` | Project provider slice; reachable only through the runtime facade, with no direct construction or modification |
| `SWIFT-548A8A928FAE` | `LedgeriOS/LedgerTargetPowerSync/LedgerOfflineClientRuntime.swift` | `efe7838b0b73e340da27891d21684704ca3ae1c1ac9f4e0a0dd21c16ac597fcc` | Account-workspace runtime; the app adapter may forward its two Project watches and the staging lifecycle may close it only after model drainage; no modification |

Schema/RLS/Sync, MCP, Firebase, migration, release, hosted and production paths
also remain outside the writable boundary. The implementation gate must rehash
every row above and reject any drift.

## Required Executable Proof

The real AppModel suite must cover exact active/archived order and lifecycle;
duplicate display names with stable identity; archived-Client relationships;
ready/partial/stale represented rows; incomplete/source-nonexhaustive versus
authoritative empty; cross-Account/malformed evidence; deterministic directory
and detail stream throw, spontaneous cancellation and unexpected normal
completion before and after first data; exact source-termination callbacks;
evidence-bound selection and exact request capture; every waiting, found,
incomplete, absence, unavailable, retryable and required-update detail state;
multiple reactive detail updates; rapid A-to-B selection; bounded cancellation
and drainage while both streams remain active; restart generation isolation;
and no post-stop mutation. Staging source checks must prove both normal and
failed-start cleanup await application-model drainage before runtime close.

The target environment control must prove AppModel imports only Core, the thin
app adapter alone imports PowerSync, the staging shell no longer owns inline
projection/detail behavior, and both staging destinations compile. Required
source-level accessibility identities are frozen as the following literals and
one stable row pattern:

- `target-project-directory-status`;
- `target-project-active-count` and `target-project-archived-count`;
- `target-project-row-active-<ProjectID.rawValue>` and
  `target-project-row-archived-<ProjectID.rawValue>`;
- `target-selected-project-name` and `target-selected-client-name`;
- `target-project-detail-state` and `target-project-detail-readiness`;
- `target-project-directory-diagnostic` and
  `target-project-detail-diagnostic`.

These checks prove exact source presence and builds only; they do not claim
interactive accessibility without an app UI-test target.

## Independent READY-Diff Review

The first actual-diff audit returned NO-GO with two P1 and two P2 findings: the
lifecycle matrix omitted detail-source termination and active-stream drainage;
the frozen shared dependency boundary was generic; stale versus newly captured
selection language and state enumeration were ambiguous; and architecture-
decision authority plus generated progress figures were inconsistent. This
revision makes each obligation explicit. Final correction re-review returned GO
with no remaining P0-P3 finding; the exact immutable READY result is recorded
below.

## Exact READY Gate

Exact comment-only READY commit
`9087403111d5a77f9577f9552347f86513e6b7a5` passed all three immutable jobs in
GitHub Actions run `33953298649`: conversion controls, disposable local
Supabase verification, and the isolated macOS target job. This authorized only
the frozen executable boundary above.

## Implemented Boundary

| Manifest identity | Exact path | Implementation hash | Implemented responsibility |
| --- | --- | --- | --- |
| `SWIFT-CAB085E24751` | `LedgeriOS/LedgerTargetAppModel/ProjectBrowsingStagingExercise.swift` | `b5f8a92f92ef3347086257d3951cd674d1367b9f10e7ba36f29b183ab61f4c7d` | Core-only atomic directory, evidence-bound selection, exact detail state, honest count labels, diagnostics, generation isolation and lifecycle drainage |
| `TEST-5C7E5E715EAE` | `LedgeriOS/LedgerTargetAppModelTests/ProjectBrowsingStagingExerciseTests.swift` | `ccf2b062c6e6c96f3c45aef2a3bfb2a873ca783c8f0a47f1c71c3c9519a7eb41` | thirteen deterministic tests covering the frozen matrix |
| `SWIFT-AA91CE0C3FAB` | `LedgeriOS/LedgerTargetApp/ProjectBrowsingStagingRuntimeAdapter.swift` | `f8b3ba21024d29ec5aa8da47a8f6e0db0f51817bca0ab42a6d33169d19de922f` | thin forwarding of the two typed runtime watches |
| `SWIFT-07427FF0DA84` | `LedgeriOS/LedgerTargetApp/ProjectBrowsingStagingExerciseView.swift` | `6e05906efccea572bbc772fe5efa9a82df06289b65ad4841d085fae3a5d6ffca` | typed active/archived rows, unknown-before-evidence counts, exact detail/readiness and bounded diagnostics |
| `SWIFT-061553E63650` | `LedgeriOS/LedgerTargetApp/LedgerTargetStagingApp.swift` | `fd18a09b2d45dd6114fc9fd5a0bdc1e155e66984f22a658e832d9dab34b6a31a` | model ownership and normal/failed cleanup drainage before runtime close |
| `CONFIG-81235587F306` / `FILE-A6E49E3815F4` | `scripts/check-target-environment.mjs` | `760337535add5769bc3f086103d0d42be71ec2210656bce08d07d44dfd92caf9` | exact import, adapter, inline-ownership, wiring, accessibility and cleanup-order controls |

The frozen Package, XcodeGen specification, Project directory/detail contracts,
PowerSync query implementations and Account runtime remain byte-unchanged.
There is no target schema, RLS, Sync Stream, MCP, migration or hosted change.

## Executable Review Corrections

Root review required deterministic active-detail drainage proof and corrected
selected names to prefer newer found/cached detail content while retaining the
captured directory row during waiting or uncached states.

Independent executable review then found one P1 presentation defect: loading,
blocked and stopped states rendered numeric zero counts even though no validated
directory presentation existed. The model/view now render `unknown` until
represented evidence exists. Review also found missing reciprocal proof for
ready+complete but source-nonexhaustive empty segments and missing deterministic
late old-detail evidence during restart. The tests now mirror both segments and
use a noncooperative old detail source. Final actual-diff re-review returned GO
with no P0-P3 findings.

## Local Implementation Verification

- `swift test --package-path LedgeriOS --no-parallel --filter ProjectBrowsingStagingExerciseTests`
  — 13 tests in one suite passed;
- `swift test --package-path LedgeriOS --no-parallel` — 441 tests in 76 suites
  passed;
- `npm run target:environment:check`, `npm run target:contracts:check`, and
  `npm run target:mcp:test` — passed;
- `npm run target:supabase:test:db` — 42 pgTAP assertions passed, and
  `npm run target:supabase:test:rpc` — Client/Project replay, RLS and direct-
  write protections passed against the disposable local stack;
- `npm run target:staging:build:macos` and
  `npm run target:staging:build:ios` — passed; and
- `git diff --check` — passed.

Exact synchronized implementation commit
`547af4d70f007c5bafabc1548084fd0e441a7270` passed all three immutable jobs in
GitHub Actions run `33954955566`: conversion control in 41 seconds, disposable
local Supabase in 1 minute 36 seconds, and the isolated target environment in
5 minutes 56 seconds. `PBROWSEAPP-TEST-010` passes and this evidence-only
promotion may mark the slice verified.

## Explicit Exclusions

Sorting/search, full cards, budgets/pins, media, tabs/children, navigation and
routes, retry commands, creation/edit/archive/restore, Client input, workspace
activation/switching, authorization, Postgres/schema/handler/Data API/RLS/Sync
changes, MCP, migration, hosted access, Firebase, production, release and
cutover are excluded. O-023/O-024/O-025/O-040/O-042/O-043 and A-003/A-004/
A-007/A-015/A-016 remain open and unadvanced.
