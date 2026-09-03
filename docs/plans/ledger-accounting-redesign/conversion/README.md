# Supabase Conversion Control Plane

Status: M0 inventory classification complete; 393 of 567 target-relevant
surfaces are target-mapped or later and the remaining 174 are explicitly tied
to decisions/spikes/production evidence. Decision-independent target
foundations are in progress. M1 is blocked only by canonical production-profile
evidence and O-022 hard-cutover evidence; production migration is not authorized
by this directory. The Client/Project directory read-contract slice is verified
at exact implementation commit `3c0b58b6`; the provider-free Transaction
taxonomy/Transfer-identity slice is verified at exact implementation commit
`031a240a`. The provider-free exact same-Client Transfer destination-selection
slice is verified at exact implementation commit `6dc7d0c2`, including all 80
target tests and both staging builds. The provider-free non-item receipt-line/
exact-reconstruction slice is verified at exact implementation commit
`594aec1e`, including all 84 target tests and both staging builds, without
choosing billing, rounding, Item-tax-basis or Transaction-posting policy.
The provider-free Project Item relationship-derived accounting-section slice is
verified at exact implementation commit `92e0b565`, including all 88 target
tests and both staging builds. It chooses no Item/Link, occurrence persistence,
credit settlement, media, provider or migration behavior. Broader app/schema/
provider and migration surfaces remain unadvanced. The provider-free attachment
capture/local-durability receipt slice is verified at exact implementation
commit `1792a862`, including all 92 target tests and both staging builds. It
explicitly does not claim physical byte persistence, encryption, upload,
display, Storage, retention or provider behavior. The provider-free Client
creation operation slice is verified at exact implementation commit `3b837af3`,
including all 96 target tests and both staging builds. It defines no server row,
authorization, Auth/provider, schema, Sync, app/MCP, migration or production
behavior. The provider-free Project setup operation slice is verified at exact
implementation commit `8d8cd30f`, including all 100 target tests and both
staging builds, without introducing rows, authorization, media, providers or
production behavior. The provider-free Project archive operation slice is
verified at exact implementation commit `7b30bd25`, including all 104 target
tests and both staging builds, without introducing lifecycle storage,
authorization, providers, migration or production behavior. The provider-free
budget-category reference read slice is verified at exact implementation commit
`713dcf57`, including all 108 target tests and both staging builds. It defines
no hidden fee visibility, mutation, server authorization, provider, migration
or production behavior. The provider-free Project category configuration read
slice is verified at exact implementation commit `40d20efb`, including all 112
target tests and both staging builds. It defines no budget arithmetic, hidden
visibility, mutation, provider, migration or production behavior.
The provider-free Client rename command slice is verified at exact
implementation commit `3282f8e3`, including all 116 target tests and both
staging builds. It preserves stable Client identity, replacement display text,
expected revision and the shared operation lifecycle without deciding Client
archive/merge, Project reassignment, provider, migration or production
behavior.
The provider-free Project rename command slice is verified at exact
implementation commit `7f395bbe`, including all 120 target tests and both
staging builds. It preserves stable Project identity, replacement display text,
expected revision and Client-relationship separation without deciding Project
deletion, Client reassignment, provider, migration or production behavior.
The provider-free Project-note read slice is verified at exact implementation
commit `b421f419`, including all 124 target tests and both staging builds.
Exactly two target surfaces preserve stable Account/Project/note identity,
audit and tombstone evidence, deterministic bounded order and explicit offline-
history readiness without authorizing mutation, provider, migration or
production behavior.
The provider-free Project-note creation slice is verified at exact
implementation commit `15566c8d`, including all 128 target tests and both
staging builds. Exactly two target surfaces preallocate stable note identity, bind
exact Project/text/requested-source intent to the shared operation lifecycle,
exclude caller-authored authoritative creator/time/source evidence and reserve
non-enumerating parent preflight for a later trusted handler. No note row,
provider, app/MCP, migration or production behavior exists at this checkpoint.
The provider-free current-Principal Project preference read slice is verified at
exact implementation commit `59526ccc`, including all 132 target tests and both
staging builds. Exactly two target surfaces preserve ordered stable pin
identities, revision, exact Account/Principal/Project binding and authoritative
absence versus incomplete local evidence. Preference writes,
authentication, schema/RLS/Sync/provider behavior, category resolution, budget
calculation, app/MCP, migration and production remain excluded.
The provider-free current-Principal Project preference update slice is
verified. Exactly two target surfaces define a complete ordered pin replacement,
explicit not-stored versus exact-revision concurrency, canonical restart/refusal
and the shared operation lifecycle. Exact implementation commit `0e652548`
and immutable Actions run `33628801064` pass all 136 target tests, graph/
generated-contract checks, both staging builds and clean artifacts.
Authentication, category mutation/resolution, defaults, physical persistence,
schema/RLS/Sync/provider behavior, app/MCP, migration and production remain
excluded.
The provider-free vendor-suggestion reference read slice is verified. Exactly
two target surfaces define stable Account-scoped suggestion identity, bounded
preserved display spelling, normalized duplicate detection, lifecycle/revision/
order, canonical readiness/restart/refusal and source-text-only selection.
Exact implementation commit `519b4338` and immutable Actions run `33632364285`
pass all 140 target tests, graph/generated-contract checks, both staging builds
and clean artifacts. O-026 mutation authority, default seeding, physical
persistence, schema/RLS/Sync/provider behavior, app/MCP, migration and
production remain excluded.
The provider-free Space-template reference read slice is verified. Exactly two
target surfaces define stable Account/template/checklist/item identity, text,
lifecycle/revision/order, structure without checked state, readiness/restart/
refusal and one narrow query port. Exact implementation commit `f23afce3` and
immutable Actions run `33636359059` pass all 144 target tests, graph/generated-
contract checks, both staging builds and clean artifacts.
O-026 mutation authority, template apply/save, Space creation, physical
persistence, schema/RLS/Sync/provider behavior, app/MCP, migration and
production remain excluded.
The provider-free Client archive operation slice is verified.
Exactly two target surfaces define one stable Client archive intent, exact
expected-revision precondition, shared operation lifecycle and explicit no-
cascade/no-delete/no-merge/no-reassignment boundary. Exact ready commit
`9f3a03dd` and immutable Actions run `33638235220` pass all 144 then-existing
tests and both builds. Exact implementation commit `e10be9ec` and immutable
Actions run `33639210706` pass four focused/all 148 target tests, graph/
generated-contract checks, both staging builds and clean artifacts.
O-025, physical persistence, schema/RLS/Sync/Auth/provider behavior, app/MCP,
migration and production remain excluded.
The provider-free Project details update slice is verified. Exactly
two target surfaces define one canonical optional-description replacement,
stable Project identity, exact expected revision, shared operation lifecycle
and explicit separation from rename, Client/category/media/lifecycle/child/
accounting/history mutation. Exact ready commit `119e0455` and immutable
Actions run `33641244740` pass all 148 then-existing tests and both builds.
Exact implementation commit `a532ac9d` and immutable Actions run `33642777864`
pass four focused/all 152 target tests, graph/generated-contract checks, both
staging builds and clean artifacts. O-023/O-024/O-025, physical persistence,
schema/RLS/Sync/Auth/provider behavior, app/MCP, migration and production remain
excluded.
The provider-free direct Space creation slice is verified. Exactly two target
surfaces implement a stable
Space ID, exact Project-or-Business-Inventory scope, normalized required name
and optional notes, zero expected-revision preconditions, shared operation
lifecycle, canonical restart/refusal and a narrow port. Exact implementation
commit `03b545df` and immutable Actions run `33647113450` pass four focused/all
156 target tests, graph/generated-contract checks, both staging builds and clean
artifacts. Checklist/template/media/
Item/review/lifecycle/accounting mutation, authorization, physical persistence,
schema/RLS/Sync/provider behavior, app/MCP, migration and production remain
excluded. O-023/O-026/O-037 stay open; `EVID-SPACE-CREATION-001`.
The provider-free Space details update slice is verified. Exactly two target
surfaces implement one
complete normalized name/optional-notes replacement, stable Space identity,
exact same-Space expected revision, shared operation lifecycle, canonical
restart/refusal and a narrow port. Exact implementation commit `1c8c12b4` and
immutable Actions run `33654631876` pass four focused/all 160 target tests,
graph/generated-contract checks, both staging builds and clean artifacts.
Scope/checklist/template/media/Item/review/
lifecycle/accounting mutation, authorization, physical persistence, schema/RLS/
Sync/provider behavior, app/MCP, migration and production remain excluded.
O-023/O-026/O-037 stay open; `EVID-SPACE-DETAILS-UPDATE-001`.
The provider-free Space checklist revision slice is verified. Exactly two
target surfaces implement one complete canonical ordered
checklist hierarchy replacement, stable distinct nested identities, checked-
state progress, exact same-Space expected revision, shared operation lifecycle
and a narrow port. Exact implementation commit `8131e857` and immutable
Actions run `33659853864` pass four focused/all 164 target tests, graph/
generated-contract checks, both staging builds and clean artifacts.
Scope/details/template/media/Item/review/Space-completion/
lifecycle/accounting mutation, authorization, physical persistence, schema/RLS/
Sync/provider behavior, app/MCP, migration and production remain excluded.
O-023/O-026/O-032/O-037 stay open; `EVID-SPACE-CHECKLIST-REVISION-001`.
The provider-free session-ending pending-work slice is verified. Exactly two
target surfaces define one
environment/Principal/Account-scoped
summary with exact queued, applying, unresolved-rejected and unverified-
attachment counts, plus clean, sync-first and exact-confirmed destructive
dispositions, canonical fingerprint/restart/refusal, cancellation no-call and
one narrow port. Exact ready commit `caa9a900` / run `33662071456` and four
focused/all 168 target tests in 39 suites, graph/contracts, both staging builds,
and clean artifacts pass at exact implementation commit `bf9a00ca` in immutable
run `33663785835`. Auth provider and offline lease choices, final UI copy/policy,
physical synchronization/cleanup, O-023 media retention, schema/RLS/Sync,
app/MCP, migration, hosted resources and production remain excluded;
`EVID-SESSION-ENDING-POLICY-001`.
The provider-free Account discovery and explicit selection slice is verified.
Exact ready commit `ae16ed4e` passed immutable Actions run `33666363647`, and
exact implementation commit `e2972b9c` passed immutable Actions run
`33668715587`. Exactly two target surfaces define environment/Principal-scoped,
visibility-safe Account rows; ready/partial/stale/authoritative-empty/failure
distinction; deterministic remembered-first presentation with no automatic
selection; exact-snapshot-bound non-authorizing selection intent; canonical
restart/refusal; stable diagnostics; and one narrow query port. Four focused/
all 172 target tests in 40 suites, graph/contracts, both staging builds and
clean artifacts pass locally and at the immutable implementation checkpoint.
A-007/A-016/O-023,
current authorization, physical workspace activation/switching, membership/
Account writers, schema/RLS/Sync, app/MCP, migration, hosted resources and
production remain excluded; `EVID-ACCOUNT-DISCOVERY-SELECTION-001`.
The provider-free Item-to-Space assignment slice is verified after
exact ready commit `30f4ab88` passed immutable Actions run `33670383410`.
Exactly two target surfaces define one story-specific `AssignItemsToSpace`
intent: exact Account/actor/Operation scope, one stable Project-or-Business-
Inventory destination Space and revision, a canonical nonempty duplicate-free
Item/revision set, deterministic active/revision/scope preconditions, atomic
refusal, restart/replay, stable diagnostics and one narrow port. Four focused
and all 176 target tests in 41 suites, graph/contracts, both staging builds,
repeatable project generation and clean artifacts pass locally and at exact
implementation commit `c5fdf5c7` in immutable run `33672006836`. O-037 remains
open because archive is excluded; Item scope/
accounting, physical persistence, schema/RLS/Sync, app/MCP, migration, hosted
resources and production remain absent; `EVID-ITEM-SPACE-ASSIGNMENT-001`.
The provider-free Item Space-clearing slice is verified after exact
ready commit `2a201de4` passed immutable Actions run `33675190031`. Exactly two
target surfaces define one story-specific
`ClearItemSpaceAssignments` intent: exact Account/actor/Operation scope, one
immutable Project-or-Business-Inventory scope, a canonical nonempty duplicate-
free Item/revision/current-Space set that may span different source Spaces,
deterministic scope/current-placement preconditions, atomic refusal, restart/
replay, marker-relationship closure without media deletion and one narrow port.
Four focused and all 180 target tests in 42 suites, graph/contracts, both staging
builds, repeatable project generation and clean artifacts pass locally and at
exact implementation commit `f5a7ac75` in immutable run `33677087616`. O-037
remains open because archive is excluded; O-023 remains open because no
attachment reference or byte is removed; destination assignment, Item scope/
accounting, physical persistence, schema/RLS/Sync, app/MCP, migration, hosted
resources and production remain absent; `EVID-ITEM-SPACE-CLEARING-001`.
The provider-free Space assignment-destination directory slice is verified.
Exactly two target surfaces define one
exact Account and Project-or-Business-Inventory request, active stable Space
identity/name/revision rows, deterministic duplicate-name ordering, explicit
ready/authoritative-empty/partial/stale/failure truth, canonical restart,
bounded refusal and one narrow query port. The exact ready commit passed both
CI jobs. The first isolated worker candidate changed only the two allowlisted
files; the integration agent reviewed every line and reran four focused/all 184
tests, and an independent adversarial reviewer found no P0-P2 defect. One P3
documentation ambiguity was corrected so legitimate later revisions/readiness
are not described as tamper. The complete local integration gate and exact
checkpoint `b0ffef83` both pass all 184 tests in 43 suites, conversion/target
checks, repeatable generation, both staging builds and clean artifacts;
immutable Actions run `33682239349` records both CI jobs.
Authorization, physical persistence, schema/RLS/Sync,
assignment mutation, app/MCP, migration, hosted resources and production remain
excluded; `EVID-SPACE-ASSIGNMENT-DESTINATION-001`.
The provider-free Project budget paid/unpaid segment read slice is verified.
Exactly two target surfaces implement pre-existing Budget Progress/D-012
authority: exact
Account/Project/currency, signed client-paid and invoicing/unpaid Money, derived
recognized value, equal collection-segment exchange, category order, distinct
local and accounting-authority versions, readiness/restart/refusal and one
narrow query port. A strict rescout and independent adversarial preflight both
approved only this bounded foundation and rejected complete-budget,
contribution-resolution, visual, provider or migration claims. Exact ready
commit `43189f1a` passed immutable run `33687191592`; candidate `dc9f2601`
changed only the two allowlisted paths, was simplified after a precommit size
review, passed every-line integration review, and received an independent
adversarial review with no P0-P3 finding before integration as `ddbe7d7b`.
Exact checkpoint `8fce53b7` then passed immutable run `33689446640`, including
all 189 target tests in 44 suites, generated contracts, both staging builds and
clean artifacts. Both enhanced write-capable pilots have now passed;
`EVID-PROJECT-BUDGET-SEGMENT-001`.
The Project Item accounting-label and Link payer-choice presentation slice is
verified at exact implementation commit `d7f4286b` and immutable run
`33691932385`.
It is intentionally limited to exact section/action/question/choice vocabulary,
authoritative Unaccounted-only availability, fail-closed other states,
side-effect-free dismissal and restart re-projection. Actual Link routes,
commands, Purchase selection, acquisition handling, persistence, app/MCP and
provider behavior remain excluded. Four focused/all 193 tests, generated
contracts, both staging builds and clean artifacts pass; the one P3 test-
exhaustiveness finding was corrected and independently confirmed;
`EVID-PROJECT-ITEM-LINK-PRESENTATION-001`.
The provider-free single-Space core-details read slice is verified with
exactly two target surfaces, eight frozen requirements and six obligations.
Primary and independent adversarial preflight approved exact Account/Space
identity, immutable Project-or-Business-Inventory scope, normalized name/notes,
active-or-archived evidence, revision, finite exact timestamps, stable ordered
checklist state, derived counts and explicit local readiness/completeness/
failure truth. The review expressly withheld timestamp provenance/order,
authoritative counts from incomplete evidence, percentages, archive effects,
Items/media/review/templates/accounting, provider/schema/RLS/Sync, app/MCP,
migration and production behavior. Exact ready commit `8849344d` passed
immutable Actions run `33693232878`, authorizing only the frozen two-path
isolated worker candidate. Primary every-line and independent adversarial
review caught and corrected four test-quality gaps across request binding,
normalization refusal, port-side validation and stable diagnostics. Candidate
`1920389d` was integrated as `72b24afa`/`503b3839`/`05509124`; 6 focused and all
199 tests in 46 suites plus complete local gates passed with no remaining P0-P3
finding. Exact integration checkpoint `d5afa699` then passed immutable Actions
run `33695588031`, including both staging builds;
`EVID-SPACE-CORE-DETAILS-001`.
The provider-free single-Project core-details read slice is prepared as a ready
gate with exactly two comment-only target surfaces. Primary, scout and
independent adversarial preflight approved only exact Account/Project/Client
identity and current core display/lifecycle, canonical optional description,
the exact locally observed Project revision needed by verified conflict-aware
commands, and explicit local readiness/absence/failure truth. Local revision is
distinct from LocalDataVersion and never claims current server authority. The
slice expressly excludes the complete Project workspace, children, media,
accounting, mutations, authorization, provider/schema/RLS/Sync, app/MCP,
migration and production behavior. The complete local ready gate passes with
all 199 existing target tests in 46 suites, repeatable generation, both staging
builds and clean isolation. Exact ready commit `4fd81f47` passed immutable
Actions run `33697079580`. Candidate `c7719ce5` changed only the registered two
paths; primary every-line review found four test-exhaustiveness gaps despite a
green suite, and test-only correction `62d59f1d` covered distinct multiple rows,
negative count, stale completeness and every waiting state. Primary and
independent re-review plus 6 focused and all 205 tests in 47 suites pass with no
remaining P0-P3 finding. Integrated as `bd576c52`/`01fc6a0f`; complete local
integration gates pass with conversion/M0 controls, isolation/contracts, 205
tests, repeatable generation, both builds and clean artifacts. Exact integration
checkpoint `d460b021` passed immutable Actions run `33698741756`: traceability
in 9 seconds and isolated target verification in 3 minutes 21 seconds. The
slice and exactly its two surfaces are verified;
`EVID-PROJECT-CORE-DETAILS-001`.
The provider-free single-Client core-details read slice is prepared as a ready
gate with exactly two comment-only target surfaces. Scout and independent
adversarial preflight approved exact Account/Client identity, the verified
ClientSummary core fields, exact locally observed Client revision and explicit
offline readiness/absence/failure truth. Nonblank padded names remain byte-
exact, equal audit timestamps remain valid, audit provenance is not claimed,
and local revision never becomes server-current authority. The slice excludes
Projects/counts, Transfer eligibility, CRM/contact/financial/history/media,
mutation/archive effects/restore/delete/merge/reassignment, authorization,
physical persistence, provider/schema/RLS/Sync/Auth, app/MCP, migration and
production. Complete local and immutable exact-ready-SHA CI gates remain
required before delegation. The complete local ready gate now passes with all
205 target tests in 47 suites, conversion/capability/query/residual controls,
M0, target isolation/generated contracts, repeatable project generation, both
staging builds and clean diff formatting. Exact ready commit `e925a7a0` passed
immutable Actions run `33700564469`: traceability in 7 seconds and isolated
target verification in 2 minutes 22 seconds. Registered isolated assignment
`SUBAGENT-WORK-005` owns only the two Client core-details paths and requires
primary every-line plus independent adversarial review before integration;
`EVID-CLIENT-CORE-DETAILS-001`.
Candidate `549ecfa6` changed only those paths. Primary every-line review found
no implementation defect, while independent review caught a P3 false-positive
waiting-state test despite the green suite. Correction `cd433de2` now requires
direct success for valid states and exact failures for invalid states; primary
and independent re-review found no remaining P0-P3 issue. Integrated as
`b96377d7`/`de85667c`. The complete local integration gate passes with 6 focused
and all 211 tests in 48 suites, conversion/M0 controls, target isolation and
generated contracts, repeatable project generation, both staging builds and
clean artifacts. Exact integration checkpoint `6cea8459` passed immutable
Actions run `33702499992`: traceability in 13 seconds and isolated target
verification in 3 minutes 39 seconds. The slice and exactly its two surfaces
are verified.

The active isolated implementation boundary is
`project-existing-client-selection-read-contracts`. Independent adversarial
preflight rejected both a duplicate Account-only Client query port and an
unsupported final UI no-auto-selection rule before freeze. The corrected
boundary is a pure projection over the verified `ClientListSnapshot`: it keeps
only active Clients in exact upstream order, carries no selected/default value,
requires an explicit projected ClientID to produce the verified
`ProjectClientSelectionInput.existing` input, preserves incomplete/offline
truth, and binds ordered active rows, source fingerprint, visible count and all
other readiness evidence in a canonical evidence fingerprint. Independent
review rejected the first worker candidate for a P1 false-authoritative-empty
case: a visible count larger than represented source rows could hide an active
Client. The corrected frozen contract adds evidence-bound
`sourceDirectoryRowCount` and permits `noActiveClient` only when the ready,
complete source is exhaustive. Corrected candidate `d206f542` changed only the
two registered paths; final root and independent re-review found no remaining
P0-P3 issue. The complete central integration gate passes with 7 focused/all
218 tests, conversion/M0 and target isolation/generated-contract controls,
repeatable project generation and both staging builds. Exact ready commit `e6d80563` passed
immutable Actions run `33704608811`, including all 211 existing tests,
generated contracts and both staging builds. Registered `SUBAGENT-WORK-006`
owned only those two paths in its isolated worktree. Exact integration checkpoint
`9ff65407` passed immutable Actions run `33707305340`, including all 218 tests,
generated contracts, both staging builds and clean tracked artifacts; the slice
is verified.
`EVID-PROJECT-EXISTING-CLIENT-SELECTION-001`.

The next disjoint ready boundary is
`transaction-type-choice-presentation-contracts`. Independent adversarial
preflight prevented a duplicate Transaction classification aggregate,
noncanonical Business-owner vocabulary and accidental UI/filter ordering. The
corrected provider-free leaf exposes only literal unordered type membership by
scope owner plus exact Purchase/Return/Transfer, Client/1584 and existing
economic-meaning presentation derived from the verified
`TransactionClassification`. Final candidate `c22fac22` changed only the two
registered target paths. Primary and independent implementation review found no
code P0-P3 issue after rejecting one P3 missing malformed-JSON case; final
review also corrected an evidence overclaim by distinguishing raw
`DecodingError` from test-consumer normalization. Exact checkpoint `fcff5b85`
passed immutable Actions run `33717396519`: conversion traceability completed
in 14 seconds and the isolated target job completed in 3 minutes 8 seconds with
all 224 tests, generated contracts, repeatable project generation, both staging
builds and clean artifacts. The slice is verified.
`EVID-TRANSACTION-TYPE-CHOICE-PRESENTATION-001`.

The next coherent ready boundary is
`project-browsing-presentation-contracts`: Project directory core rows,
content-bound selection, exact `ProjectCoreDetailsRequest` derivation and local
detail-header truth across four leaf paths. Independent preflight rejected
noncanonical target sorting, fixed tabs, full-card naming and direct route
construction, then required Project-only lifecycle filtering, active-Project/
archived-Client visibility, ready-complete-source-exhaustive absence and a
fingerprint over all source/projected evidence. Actual-diff review then caught
and corrected an unrelated D-023 citation, missing exact Client-lifecycle
authority and stale-selection request-derivation ambiguity. The corrected
boundary preserves exact upstream order, validates the current presentation
snapshot before deriving a detail request, and adds no query port, full Project
card, workspace, route, mutation or provider behavior. Four comment scaffolds
now contain the provider-free implementation. A green initial candidate was
rejected for a valid-sibling selection-rebind defect and manifest/API naming
drift; corrected candidate `73f94525` fingerprints the exact selection row,
adds direct regression coverage and matches
`ProjectDirectoryPresentationSnapshot`. Primary and independent review report
no remaining P0-P3; seven focused and all 231 tests, deterministic target
generation and both staging builds pass. Exact integration checkpoint
`717a0eb89099676bd4c09d6b0665dd83ab9739d8` passed both jobs in immutable
Actions run `33723154735`; the slice and its four surfaces are verified.
`EVID-PROJECT-BROWSING-PRESENTATION-001`.

The next frozen boundary at that historical checkpoint was
`project-setup-form-presentation-contracts`:
provider-free preparation of one Project setup from the verified active-Client
selection, budget-category reference and Project setup operation contracts.
It preserves exact Client/category order and local readiness, supports explicit
existing or preallocated-new Client identity, permits zero selected categories,
preserves null/zero/positive allocation intent and revalidates current evidence
before deriving the verified `CreateProjectCommand`. It deliberately excludes
SwiftUI layout/copy/steps, defaults, on-the-fly category creation, hero media,
port invocation, authorization, persistence, providers, app/MCP, migration and
production behavior. Its READY package used two comment-only leaf scaffolds;
the complete READY gate passed with all 231 tests, repeatable target generation
and both staging builds. Independent actual-diff review rejected an unsupported
same-currency rule and ambiguous creation-description handling; the corrected
boundary invents no Project currency, reuses verified description normalization
and adds allocation-order/new-ID-collision hardening. Independent correction
re-review returned GO with no remaining P0-P3 issue. Exact ready commit
`a4dd7cbdca3dcf7b31c386e4f451ad320b7c8e62` passed both jobs in immutable
Actions run `33726485780`. A temporary two-path worker worktree was registered;
assignment-control commit `10913c5761561ad9fdd0713627ae82396e9f3ff8`
passed both jobs in immutable Actions run `33726899284`. Primary review rejected
the worker's first green candidate because its restart tests did not yet mutate
every field promised by the frozen manifest. Corrected worker tip `37145ae3`
adds the exhaustive field matrix; primary and independent review return GO with
no remaining P0-P3. All 237 tests, warnings-as-errors, repeatable generation and
both staging builds pass locally. Exact integration checkpoint
`147d22de801b15794d8ebb4786eaea86e4346940` passed both jobs in immutable
Actions run `33729967356`; the slice and both surfaces are verified. Promotion
commit `5322adfca32ce5fd90f790f70ed584090ab5eee1` passed immutable Actions run
`33730394704`. The clean temporary worker worktree was removed; its branch and
reviewed candidate history remain recoverable.
`EVID-PROJECT-SETUP-FORM-PRESENTATION-001`.

The verified `space-checklist-editing-presentation-contracts` boundary is a
provider-free projection
from exact Space-core update evidence into current/stale/noneditable truth, a
raw restart-safe checklist editor, and semantic-base-validated derivation of
the verified complete-replacement command. Independent preflight rejected
unsafe partial-cache admission, refresh-metadata overbinding, unsupported
checklist reorder/cross-list movement and canonical-only intermediate text.
The corrected ready package admits only ready-complete current or retryable-
ready-complete cached evidence, preserves blank intermediate form text and
exact nested IDs/order tokens, supports checklist fields plus within-checklist
item editing, and lets harmless refresh metadata advance without hiding a real
revision/hierarchy conflict. Final corrected-diff review found no remaining
P0-P3. Exact ready commit `5c2a185be15189bc8aa1606f838eee5a362780fc`
passed immutable Actions run `33732917130`. A temporary two-path worker
worktree is registered. Assignment-control commit
`cc6faddf707694e0c4a7af00a770d8a2672b8151` passed immutable Actions run
`33733387021`. Primary and independent review rejected the first green worker
candidate for incomplete proof, then the expanded matrix exposed and corrected
a strict-restart defect involving absent versus explicit-null cached evidence.
Corrected worker tip `272b705e` has no remaining P0-P3. All 243 tests,
warnings-as-errors, repeatable generation and both staging builds pass locally.
Exact integration commit `5a5c67b1319e3fcc41290469f7f39db9d515b284`
passed both jobs in immutable Actions run `33739849778`; the slice and both
surfaces are verified. Promotion commit
`fd54f8c5db700af6ab8833e195da04256836ea58` passed immutable Actions run
`33740343879`. The clean temporary worker worktree was removed; its branch and
reviewed candidate history remain recoverable.
`EVID-SPACE-CHECKLIST-EDITING-PRESENTATION-001`.

The active bounded boundary is
`direct-space-creation-use-case-contracts`. Independent preflight rejected its
first presentation-owned draft for layer inversion, unsupported initial-field
and cancellation policy, redundant fingerprints/restart claims, an unclosed
source-validator responsibility and O-026 overreach. The corrected package
keeps caller-supplied raw form input transient, converts it only through the
verified canonical Space name/notes values, and gives operation metadata,
command assembly, one `SpaceCreating` call and receipt validation to a separate
application use case. It claims four conversion surfaces but permits code
changes only in two target-only leaves; the two current Firebase validation
surfaces remain untouched and are replaced in the target by the canonical
validator/tests. The complete local ready gate passes with 815 recorded / 800
discovered surfaces, zero errors and three established warnings; 388 mapped /
167 residual / 44 blockers; M0; all 243 tests in 54 suites; warnings-as-errors;
target isolation/contracts; repeatable project hashes `0657194a` / `388303af`;
both staging builds and clean formatting. Two independent corrected-diff
reviews return GO with no remaining P0-P3 issue. Exact ready commit
`b8869ac2a0b3cfc48c4c197cc39baa8ceec60cfe` passed immutable Actions run
`33744781549`. The corrected implementation changes only the two target leaves.
The first green candidate exposed test-exhaustiveness gaps, and the two reviewers
initially disagreed about cancellation/error taxonomy. Architecture rules 7/8
resolved the distinction: the correction preserves Swift task cancellation
separately from form-cancel UX and transport failures, asserts exact reciprocal field
forwarding, and covers same-scope duplicate names plus empty/nil/whitespace/
padded/long inputs. Two independent final reviews return GO. Six focused and
all 249 tests in 55 suites, conversion/target controls, repeatable generation
and both staging builds pass locally. Exact implementation commit
`c35f1cefc88d964035976d537c2f829b4db62a8a` passed immutable Actions run
`33746648677`; all four claimed conversion responsibilities and the slice are
verified. Promotion commit `880727f74355699e10466e68d29e1265d5f95fe1`
passed immutable Actions run `33747118216`.
`EVID-DIRECT-SPACE-CREATION-USE-CASE-001`.

A fresh post-verification scout ranked a provider-free Space-details update use
case as the strongest next candidate. Independent preflight confirmed the
application boundary is decision-complete but rejected two overclaims: it may
replace only the source modal's save-intent responsibility, not the whole
SwiftUI surface, and it may not consume Space-core read/readiness evidence or
choose lifecycle eligibility. The corrected ready package claims exactly two
comment-only target leaves, leaves `SWIFT-9F4789704808` target-mapped, fixes the
current newline-only-name validation hole through canonical values, and still
rejects the removed direct-create form presentation and complete Set/Clear
picker. Two independent actual-diff reviewers caught and drove correction of
contract overclaims plus one missing conversion-control crosswalk authority;
both now return GO with no remaining P0-P3 finding. The complete local ready
gate passes with all 249 target tests in 55 suites, repeatable generation and
both staging builds. Exact ready commit `b6a98ca0` passed immutable Actions run
`33749431949`. Implementation now changes only the two frozen target leaves.
Independent review found and drove correction of an imprecise no-base-detail
claim, missing exact long-raw assertions and incomplete diagnostic-leakage
coverage; both final reviewers return GO. Six focused and all 255 target tests
in 56 suites, warnings-as-errors, conversion/target controls, repeatable
generation and both staging builds pass. Exact implementation commit
`f0d7c3fa` passed immutable Actions run `33750834849`; the slice and its two
target leaves are verified. The source modal remains `target_mapped` because
its remaining UI/composition responsibilities are unconverted.
`EVID-SPACE-DETAILS-UPDATE-USE-CASE-001`.

Verification-promotion commit `d74efb4424a559b007a032baa29d5a31af227754`
passed immutable Actions run `33751486795`, leaving the verified Space-details
slice frozen. Fresh authority preflight then selected a strict archive-only
Project application slice above the existing verified archive operation. The
ready package claims exactly two new comment-only target leaves: a non-Codable
intent with exact Account/Project/expected revision and a use case that adds
caller operation metadata, assembles the existing command, makes one post-
construction port call, validates the receipt, preserves cancellation and
normalized failures, and bounds raw errors. Source `ProjectDetailView` remains
characterized under O-024, while `MCPTOOL-921DA05B3330` remains target-mapped;
the app UI/readiness/lifecycle and the MCP tool's archive-false restore, wiring,
authorization and result responsibilities do not advance. No physical history,
provider, migration or production behavior is claimed.
Two independent initial actual-diff reviews caught the omitted MCP accounting
and an incorrect product-spec attribution for exact revision mechanics;
corrected-diff review then caught that an archive-only command did not completely
map the source MCP Boolean. The next review caught missing restore migration
reconciliation and stale future-command wording. All five are corrected: the verified archive-
operation evidence owns implemented archive mechanics, while the source MCP
Boolean maps to the existing `ArchiveProjectCommand` and separate future
`RestoreProjectCommand` responsibilities. This slice still advances only archive.
Final review then caught and corrected that the first reconciliation edit had
landed on the broad MCP module rather than this exact tool. All six findings are
preserved in the evidence.
The complete corrected local ready gate
passes 255 tests in 56 suites with warnings as errors, all conversion/
target controls, repeatable project generation and both staging builds.
Final corrected-diff re-review returned GO, and exact ready commit `bf429472`
passed immutable run `33755885978`. Implementation now changes only the two
frozen target leaves: exact transient intent, existing archive-command assembly,
one port call, receipt validation, structured cancellation, normalized failure
preservation and bounded raw errors. Review rejected weak schema-exclusion tests
and a physical-durability wording overclaim; both were corrected, and two final
implementation reviewers return GO. Six focused and all 261 target tests in 57
suites pass with warnings as errors; conversion/target controls, repeatable
generation, both staging builds and clean formatting also pass. Exact
implementation commit `232acf922b6c1ab1016017c3ebc3b926b164466c`
passed immutable Actions run `33758116150`, so the two target surfaces and slice
are verified.
`EVID-PROJECT-ARCHIVE-USE-CASE-001`.

Verification-promotion commit `97cf6156ce4e93a29ded7465d4b1d083fab5c4ef`
passed immutable Actions run `33759414349`, freezing the archive use case. The
next chosen-Project note-submission candidate was rejected before READY or
implementation. Independent review found that app trimming, the MCP helper's
three-character minimum and the target representation's lossless accepted text
leave a user-visible normalization/minimum choice without canonical authority.
Its speculative scaffolds and dossier were removed, O-039 now blocks the eight
affected source/integration surfaces, and a proposed decision packet records
the options. A separate strict-authority scout selected Client archive dispatch
as the next decision-independent candidate. Exact READY commit `a4bc1daa` passed
immutable run `33765054735`. Exactly two target leaves now implement six
authority-bound requirements and eight reciprocal verification obligations over
the already verified
Client archive operation without advancing reads, lifecycle eligibility, UI,
physical persistence, authorization, provider, migration or production behavior.
One bounded writer changed only those leaves. Authority review caught and
corrected a missing compile-time conformance proof; both final reviewers returned
GO. Root line review, six focused/all 267 target tests, complete controls,
repeatable generation and both staging builds passed. Exact implementation commit
`a5ba0ae31d7d2547398d4b63be1f0f4bc866148f` passed immutable Actions run
`33767120461` (traceability 12 seconds; isolated target 3 minutes 3 seconds), so
the two leaves and dossier are verified. No Firebase, provider, hosted, migration
or production behavior changed.

Verification-promotion commit `b0fcd6cbba8c7312fc4f4f8ae3d8c1c74f4a4b47`
passed immutable Actions run `33768000016`, freezing the Client archive use case.
A bounded strict-authority scout then ranked Space checklist revision submission
first; root independently confirmed the canonical Spaces authority, verified
editing-presentation and revision-operation dependencies, and absence of an open
decision blocker. Exact READY commit `6534da33` passed immutable Actions run
`33785649411`. Exactly two target leaves now implement deriving one complete
replacement from existing restart-safe draft/current evidence, one post-
derivation port call, receipt validation and bounded failures. Root line review,
six focused/all 273 target tests in 59 suites, complete controls, repeatable
generation at `0657194a` / `388303af` and both staging builds pass. Independent
reviewers found only test-proof gaps for readiness, scope/lifecycle transparency,
boundary/long-text coverage and reciprocal field isolation; corrected tests
close them and both reviewers return GO. EditChecklistModal, physical
persistence, authorization, provider, migration and production behavior remain
unadvanced. Exact implementation commit `99574328` passed immutable Actions run
`33788214259` (traceability 10 seconds; isolated target 3 minutes 4 seconds), so
the two leaves and dossier are verified.

A root scout and separate strict-authority preflight selected the Project setup
selection-to-application boundary above the verified form-presentation and
setup-operation contracts. Exact READY commit `863f6fce` passed immutable run
`33791245215`. A bounded writer then changed exactly the two frozen target
leaves: existing `ProjectSetupFormSelection` plus current
`ProjectSetupFormPreparation` derives one command before one
`ProjectSetupOperating.create` call, validates the exact receipt, preserves
both typed failure families and cancellation, and bounds unknown errors.
Matching represented ready, partial and stale evidence remains admissible; no
ready-only gate or preparation evidence enters the command. Root every-line
review and six focused/all 279 target tests in 60 suites pass with warnings as
errors. Independent reviewers found three P2 proof gaps—nil-description
omission, same-identity existing-to-new Client discrimination and allocation-
order equivalence. Corrected tests close all three and both final reviewers
return GO. Target controls, repeatable Xcode hashes `0657194a` / `388303af` and
both staging builds pass locally. Exact implementation commit `d624c2e0`
passed immutable run `33793469069`; the dossier and both target leaves are now
verified.
O-023/O-024/O-025/O-026, source UI/defaults/category mutation/media, physical
persistence, authorization, provider, migration and production remain outside;
`EVID-PROJECT-SETUP-USE-CASE-001`.

The description-only Project details form-to-application boundary is verified.
Root and two read-only preflights rejected the
legacy broad Edit Project surface as authority and selected only the canonical
`UpdateProjectDetails` set/clear behavior above the verified operation. Exactly
two leaves (`SWIFT-B95AD78B8CEC`, `TEST-315066B94566`) now implement a
transient four-field input, existing description normalization, construction
before one port call, receipt validation, all 13 typed failures, cancellation
and bounded unknown errors. Exact READY `22c6cc01` / immutable run
`33797480692` and exact implementation `55baae9d` / immutable run
`33799751617` passed. The dossier and both target leaves are `verified`; seven
focused tests plus review evidence satisfy `PDETAILUSE-TEST-001` through
`PDETAILUSE-TEST-009`, and immutable exact-implementation-SHA CI satisfies
`PDETAILUSE-TEST-010`. All 286 target tests in 61 suites, target controls,
repeatable generation and both staging builds pass locally and in CI.
Independent reviews caught and corrected a missing public initializer,
`@testable` access masking, lifecycle-status overstatement and stale gate
wording. Implementation review caught and corrected missing zero-revision
dispatch proof; both corrected-diff reviewers returned GO.
EditProjectModal, ProjectService/Protocol, Project model and
`update_project` MCP tool retain their prior statuses. Read/readiness/lifecycle,
dirty/no-op/UI, broader mutation, persistence, authorization, provider/schema/
RLS/Sync, app/MCP, migration, hosted and production behavior remain outside;
`EVID-PROJECT-DETAILS-UPDATE-USE-CASE-001`.

The next bounded candidate is the typed Project rename application boundary.
`project-rename-use-case-contracts` is `ready` with two comment-only leaves,
`SWIFT-5A812E7B8C95` and `TEST-E1BAA8DF70B4`, above the verified Project rename
operation and Client/Project display-value contracts. The frozen public intent
contains only Account, Project, expected revision and an already-validated
`ProjectDisplayName`; it accepts no raw String and adds no normalization rule.
The future use case constructs the verified draft/command before one rename-port
call, validates afterward, preserves all 12 typed failures and cancellation,
and bounds only unknown errors. The local READY gate passes 829/814 conversion
inventory, 395/174/45 residual control, all 286 existing tests in 61 suites,
repeatable generation and both staging builds; both independent corrected-diff
reviewers return GO and immutable exact-READY-SHA CI remains. All ten obligations remain planned until
exact implementation. EditProjectModal, ProjectService/Protocol, Project model,
ProjectFormValidation/tests, ProjectDetailView, ProjectDetailContainer and
`update_project` retain their prior statuses.
Initial READY review corrected mirrored reciprocal-proof risk, product/technical
authority attribution, ProjectDetailView status coverage and rejection-recovery
wording; the final corrected-diff reviews found no remaining P0-P3 issue.
Read/readiness/lifecycle/no-op/UI, broader mutation, persistence, authorization,
provider/schema/RLS/Sync, app/MCP, migration, hosted and production behavior
remain excluded; `EVID-PROJECT-RENAME-USE-CASE-001`.

This directory makes whole-application conversion progress durable across long
agent runs, context compaction, task handoffs, and restarts. Conversation memory
is never the authority for what has been covered or verified.

## Long-Running Goal Operating Model

Run the redesign as one coherent long-running goal, but never as one
conversation-memory-sized unit of work. The goal owns the overall outcome; the
repository owns authority, progress, evidence, and the next executable action.

- `AGENTS.md` is the always-loaded constitution: it names the boot sequence,
  prohibited work, required checks, and approval boundaries.
- This README and `execution-state.md` are the resumable execution plan. The
  latter must identify the current checkpoint, honest blockers, and exact next
  action rather than narrating what an agent remembers.
- `conversion-manifest.json`, generated audits, slice dossiers, and the evidence
  index are the machine-enforced state. Conversation summaries cannot advance
  them.
- `.github/workflows/supabase-conversion-control.yml` reruns the deterministic
  control checks for every pull request. Configure its `Conversion state and
  traceability` job as a required branch-protection check so an agent cannot
  merge stale coverage or invalid slice claims merely by skipping a local
  command.
- One active implementation slice is the normal unit of delivery. Its dossier
  is updated alongside requirements, code, migrations, tests, and evidence—not
  reconstructed only at the end of a long turn.
- Write-capable subagents follow
  `parallel-subagent-workflow.md` and `parallel-work-registry.json`: the primary
  agent remains the sole control-plane/integration writer, workers own one
  frozen slice in isolated worktrees, and the first two pilots receive complete
  primary-agent line review plus an independent adversarial review before
  integration or status promotion.
- A repo-local Codex hook at `.codex/hooks.json` runs after context compaction.
  It re-injects the persisted checkpoint and a fresh conversion-check result
  before the immediate continuation. The hook is recovery context, not product
  authority and not permission to proceed through a failed gate.
- Parallel tasks may research or test bounded, non-overlapping work. They must
  return durable repository artifacts, and two tasks must never write the same
  checkout or slice concurrently.
- The goal continues through routine checkpoints without asking the user to say
  “proceed.” It pauses only at the explicit decision, credential, spend,
  production, migration, release, or cutover boundaries recorded here.

Automatic compaction may happen in the middle of a bounded slice. The resumed
agent must inspect the slice dossier and working-tree diff, rerun the check, and
continue or repair the same slice. It must not infer completion from the compacted
summary or select a different slice merely because the prior reasoning is gone.

## Authority and Files

- `conversion-manifest.json` is the machine-readable coverage source of truth.
- `conversion-coverage.md` is generated from the manifest and must not be edited
  manually.
- `execution-state.md` records the exact safe resumption point.
- `evidence-index.md` defines and indexes acceptable proof.
- `current-backend-contract.md` is the reviewed description of the existing
  Firebase data, Auth, security, Functions, and media boundary.
- `current-query-contract.md` is the reviewed Firestore query/listener, offline
  expectation, pagination, and index contract.
- `capability-evolution-method.md` defines how observed source behavior and
  possibly stale specs become deliberate preserve/correct/improve/redesign/
  retire decisions before target design.
- `target-mapping-method.md` defines the required M2 owner/surface/security/
  sync/migration/verification record and honest status rules.
- `vertical-slice-implementation-method.md` defines the mandatory implementation
  lifecycle from exact spec sections and invariants through domain contracts,
  Postgres, grants/RLS, Sync Streams, offline behavior, app/MCP parity,
  migration, reconciliation, evidence and rollback.
- `../vertical-spike-protocol.md` defines the resumable S0–S9 evidence needed to
  resolve the remaining provider, Auth, optimistic-operation, offline-lease and
  physical-target architecture gates; prose alone closes none of them.
- `current-capability-register.md` groups the current service/MCP layer by user
  and operational outcome and owns the dossier review queue.
- `capability-surfaces.generated.json` and `.md` are the deterministic complete
  Swift service/Auth and MCP file/symbol assignment for that register.
- `query-contract.generated.json` and `.md` are deterministic line/symbol-level
  query occurrence artifacts; regenerate rather than editing them.
- `residual-decision-register.generated.json` and `.md` are the deterministic
  M2 queue of every target-relevant surface that is not yet mapped, grouped by
  its exact product, architecture, spike, or production-evidence blocker.
- `product-authority-crosswalk.json` maps every classification batch to its
  reviewed canonical-target, current-product, historical-evidence,
  decision-log, architecture, or conversion-control authorities.
- `product-authority-audit.generated.json` and `.md` prove that every stable
  surface resolves through its batch to an authority set and that all nine
  registered target specs remain represented. Generated artifacts must not be
  edited.
- `implementation-slices/*.json` contains one machine-readable dossier per
  active target slice. `_template.json` is ignored by validation and must be
  copied/renamed before use.
- `implementation-slice-audit.generated.json` and `.md` report slice ownership,
  requirements, verification obligations, blockers and surface coverage.
- `classification-batches/*.json` contains reviewable, bounded M0 decisions;
  `sync` applies them to the manifest without re-acknowledging later source
  changes.
- `scripts/supabase-conversion-ledger.mjs` discovers repository surfaces,
  merges them without discarding classifications, validates the ledger, and
  generates coverage. Discovery includes app/test source, rules, Functions,
  MCP, migration/repair tooling, and build/release/backend configuration; the
  manifest also carries cross-cutting surfaces that code scanning cannot prove.
- `scripts/generate-m2-residual-register.mjs` validates every residual blocker
  against the decision/architecture authorities and regenerates the grouped
  decision queue. Unknown blockers or stale generated output fail its check.

Product behavior remains authoritative in the canonical specs and decision log.
Architecture remains authoritative in `docs/architecture/redesign`. The
implementation tracker owns sequencing. This directory owns the answer to:
“Has every source surface been found, classified, mapped, implemented, tested,
rehearsed, and made ready for cutover?”

## Required Start/Resume Sequence

Before continuing conversion work, including immediately after context
compaction:

1. Read `AGENTS.md`.
2. Read the redesign program README and decision log.
3. Read this file and `execution-state.md`.
4. If target implementation is active, read
   `vertical-slice-implementation-method.md` and the entire active slice dossier.
5. Run `node scripts/supabase-conversion-ledger.mjs check`.
6. Inspect `git status --short` and preserve unrelated work.
7. Reconcile any partial diff with the active dossier; do not silently discard,
   reclassify, or claim it.
8. Resume only the `Next Action` recorded in `execution-state.md`, unless a new
   user instruction supersedes it.

## Checkpoint Rule

For every bounded work item:

1. identify the stable surface IDs being changed;
2. link the surface to its user or operational capability and document current
   behavior in a bounded classification batch;
3. complete or update the capability dossier: source evidence, governing specs,
   stale/contradictory spec concerns, and the explicit preserve/correct/improve/
   redesign/retire decision;
4. update the product-authority crosswalk when a batch's governing specs or
   authority roles change; canonical target specs and confirmed decisions must
   remain distinguishable from current or historical evidence;
5. map target ownership, schema/port/command/query, RLS, Sync Streams, migration,
   and verification before marking `target_mapped`;
6. before implementation, create/update the slice dossier with exact authority
   headings, invariants, contracts and verification obligations and make its
   `ready` gate pass;
7. implement and run applicable tests, advisors and reconciliation, attaching
   durable evidence before status advancement;
8. update the manifest and evidence index;
9. synchronize and validate the ledger; and
10. update `execution-state.md` with the next exact action before ending the turn.

No item becomes `verified`, `rehearsed`, or `cutover_ready` based on prose or a
successful compile alone.

## Commands

```bash
node scripts/supabase-conversion-ledger.mjs sync
node scripts/supabase-conversion-ledger.mjs check
node scripts/supabase-conversion-ledger.mjs report
node scripts/supabase-conversion-ledger.mjs gate M0
npm run conversion:queries:generate
npm run conversion:queries:check
npm run conversion:capabilities:generate
npm run conversion:capabilities:check
npm run conversion:residuals:generate
npm run conversion:residuals:check
npm run conversion:profiles:check-readonly
```

`sync` discovers new repository surfaces and preserves existing manual
classification fields, then applies reviewed classification batches. The first
application may acknowledge the exact current source hash; subsequent source
changes remain visible as drift. A previously discovered source that disappears
remains in the manifest and fails validation until its retirement is evidenced.

When a characterized source is deliberately changed, re-acknowledgment requires
an explicit `acknowledgeSourceHash` in exactly one reviewed classification batch;
the requested hash must equal the newly observed hash. `acknowledgeCurrentSource`
only acknowledges an automatic source the first time. Never edit a hash merely
to silence drift.

`check` validates structure, detects unrecorded surfaces and source drift, and
does not pretend that an incomplete milestone has passed. It also rejects a
missing/broken authority mapping, stale generated authority/slice audits, an
invalid slice dossier, or an implemented-or-later target surface without
exactly one correspondingly advanced slice.

`gate M0` through `gate M5` are cumulative and fail until that milestone and
every prerequisite milestone are satisfied.

The two production source profilers default to local preflight and refuse to
initialize Firebase without the exact reviewed project/account, an external
chmod-600 project-matching service-account key, the fixed gitignored artifact
directory, and an explicit read-only execution confirmation. See their `--help`
output and `evidence/EVID-PROFILER-001.md`. Never weaken those gates to make a
profile run convenient.

## Permanent Guardrails

- Do not implement the redesigned application in Firebase.
- Do not treat source mechanics, current bugs, or stale specs as parity
  requirements; resolve them through a capability dossier.
- Do not mutate production during discovery or rehearsal.
- Do not silently omit a source surface because it appears obsolete.
- Do not expose a target table without explicit grants, RLS, and Sync Stream
  review where applicable.
- Do not begin a target implementation slice until its machine-readable dossier
  passes the `ready` requirements in `vertical-slice-implementation-method.md`.
- Do not use user-editable Auth metadata for authorization.
- Do not put a service-role/secret key in the app.
- Do not mark a migrated record covered without source-to-target correlation or
  an approved omission/quarantine reason.
- Do not authorize cutover from percentage completion; every mandatory gate must
  pass.
- Do not merge target implementation while the required `Conversion state and
  traceability` pull-request check is absent or failing.
