# EVID-SPACE-CHECKLIST-EDITING-PRESENTATION-001 — Space Checklist Editing Presentation

- Timestamp: 2026-09-03
- Class: ready design / provider-free Space checklist editing and command derivation
- Source baseline: `fe018501d67cc84b6f140b2645b8a8149ea5c4f6` on `firebase`; the source worktree and released Firebase app remain unchanged
- Claimed target surfaces: `SWIFT-A9BCA70B7F9C`, `TEST-94F32F5E9219`
- Slice dossier: `conversion/implementation-slices/space-checklist-editing-presentation-contracts.json`
- Verification state: independently reviewed ready commit passed immutable CI; assignment-control CI pending before implementation

## Selection and Product Authority

A read-only scout compared decision-independent target candidates after the
Project-setup form slice. Checklist editing is the strongest complete user
workflow because canonical Space authority already specifies complete ordered
replacement, stable nested identity, normalization, duplicate-label validity,
checked state, empty states and atomic stale-revision conflict. Its two target
dependencies are already verified: `SpaceCoreDetailsUpdate` owns exact
Space/readiness/failure evidence and `ReviseSpaceChecklistsCommand` owns the complete
revision-aware operation. The generic export renderer remains possible later,
but it cannot yet expose a canonical named Transaction profile while O-029,
O-032 and O-036 remain unresolved.

The released Firebase modal is current-behavior evidence only. It establishes
that users can add/remove/rename checklists and add/remove/reorder/check items
within a checklist, then save a whole replacement array, but its index identity,
implicit/random IDs and last-write-wins save are not copied into the target.
Canonical target authority and the
reviewed Space dossier instead require stable IDs, explicit evidence and one
stale-revision conflict.

## Frozen Boundary

Exactly two comment-only target leaf files are claimed:

- `LedgeriOS/LedgerTargetCore/SpaceChecklistEditingPresentation.swift`; and
- `LedgeriOS/LedgerTargetCoreTests/SpaceChecklistEditingPresentationTests.swift`.

The presentation consumes `SpaceCoreDetailsUpdate`. A ready, complete,
represented row becomes editable-current. A retryable failure carrying one
cached snapshot becomes editable-stale only when it has quality ready,
isCompleteForQuery true and exactly one valid row; the enclosing retryable
failure is the sole reason it is stale. Waiting, partial/stale or ready-
incomplete snapshots, retryable failure with partial/stale/ready-incomplete/
empty/missing cache, authoritative absence, unavailable and required-update
remain noneditable truth rather than replace-all input. Project
and Business Inventory Space scope are both valid. Lifecycle is carried and
fingerprinted but does not decide whether an edit action is available.

The immutable draft has separate raw editor rows, so blank/whitespace
intermediate names and item text survive editing and restart. Only submission
normalizes and validates content. It supports checklist add/remove/rename/clear
and item add/remove/edit/set-checked/reorder inside the owning checklist.
Checklist reorder and cross-checklist movement are deliberately absent because
neither is established by the current workflow. Callers preallocate new node
IDs; only collisions in the represented collection or owning checklist are
refused, with no historical/global-ID claim.

Exact source order tokens are retained. Non-order edits and removal preserve
remaining tokens; append uses zero for an empty sibling list or max-plus-one
with explicit representational-overflow refusal; item reorder accepts a complete
ID permutation and reassigns that checklist's existing ascending token multiset.
An unchanged draft therefore produces the exact starting collection.

The only command-producing call reprojects allowed current Space-core update
evidence, revalidates the draft and exact semantic base, then creates the
already-verified
`SpaceChecklistRevisionDraft` and `ReviseSpaceChecklistsCommand` with caller-
supplied Operation, actor, contract and capture-time values. Changed scope,
lifecycle, revision or starting hierarchy fails before a command exists. A
later `localDataVersion`/`asOf` or otherwise equivalent harmless refresh does
not invalidate an edit, because refresh metadata is protected for serialized
integrity but excluded from command-eligibility identity. No merge or
authoritative apply occurs.

## Required Verification

The implementation tests must prove:

1. update-state projection across editable-current, editable-stale, waiting,
   partial/incomplete, absence, retryable-without-row, unavailable and
   required-update behavior;
2. raw blank intermediate state, stable-identity checklist/item edits,
   submission normalization, duplicate labels, valid empty states and exact
   represented-scope collision/unknown refusal;
3. absence of checklist reorder/cross-checklist movement, complete within-
   checklist item permutation and deterministic order-token behavior;
4. unchanged and edited complete-replacement command derivation with exact
   Space revision and caller operation metadata;
5. semantic-base refusal for scope/lifecycle/revision/hierarchy concurrency,
   harmless refresh-metadata acceptance, current-to-stale and stale-to-current
   eligibility when the semantic base is unchanged, and no merge;
6. canonical restart, strict keys, independent every-field mutation, separate
   integrity/semantic/draft fingerprints and tamper refusal; and
7. stable bounded diagnostics and absence of SwiftUI, authorization,
   persistence, provider or authoritative-result claims.

Ready and implementation checkpoints must also pass conversion/capability/
query/residual/M0 controls, target isolation and generated contracts, focused
and full tests, warnings-as-errors, repeatable XcodeGen, macOS and generic iOS
Simulator staging builds, clean artifacts, exact path scope and immutable CI.

## Local Ready Verification

The two leaf files are comment-only scaffolds. Independent adversarial preflight
rejected the first draft for four material issues: unsafe partial/stale replace-
all admission, command eligibility bound to harmless refresh metadata,
unsupported checklist reorder/cross-checklist movement, and inability to retain
blank intermediate form text. The corrected boundary above resolves each issue
without choosing a new product decision. Corrected-diff review then required an
exact ready-complete retryable-cache predicate and current/stale transition
tests; those corrections are applied. The complete local ready gate passes with
813 recorded / 798 discovered surfaces, zero errors and three established
warnings; 384 mapped / 167 residual / 44 blockers; M0; all 237 tests in 53
suites; warnings-as-errors; target isolation/contracts; repeatable project/
scheme hashes `0657194a` / `388303af`; both staging builds; valid JSON and clean
formatting. Comment-only leaf hashes are `7c0d14b243a0804df37e159218f1c28108780abb97eea850f96e3dda576b782f`
and `b89ca069c734cf651f0ad6e86a92436aa5726d68305ca159e354b362720a06d6`.
Final independent corrected-diff re-review found no remaining P0-P3. Exact
ready commit `5c2a185be15189bc8aa1606f838eee5a362780fc` passed both jobs in
immutable Actions run `33732917130` (traceability 8 seconds; isolated target 3
minutes 12 seconds). The temporary worker branch/worktree starts at that exact
commit; assignment-control CI remains before a worker may implement the leaves.

## Permanent Exclusions

This evidence does not decide archived-Space edit availability and does not
authorize template application/saving, attachment/media behavior, Item
assignment, review notes, Space archive/completion, accounting, SwiftUI,
operation-port invocation, physical local persistence, authorization,
Postgres, Data API, RLS, PowerSync, MCP, migration, hosted resources,
production access, release or cutover. O-023/O-026/O-032/O-037 and
A-003/A-004/A-007/A-015/A-016 remain open or outside the boundary.
