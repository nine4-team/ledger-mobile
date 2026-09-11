# EVID-SPACE-CHECKLIST-EDITING-PRESENTATION-001 — Space Checklist Editing Presentation

- Timestamp: 2026-09-03
- Class: implementation / local integration evidence for provider-free Space checklist editing and command derivation
- Source baseline: `fe018501d67cc84b6f140b2645b8a8149ea5c4f6` on `firebase`; the source worktree and released Firebase app remain unchanged
- Claimed target surfaces: `SWIFT-A9BCA70B7F9C`, `TEST-94F32F5E9219`
- Slice dossier: `conversion/implementation-slices/space-checklist-editing-presentation-contracts.json`
- Verification state: verified at exact integration commit `5a5c67b1319e3fcc41290469f7f39db9d515b284` by immutable Actions run `33739849778`; promotion commit `fd54f8c5db700af6ab8833e195da04256836ea58` passed run `33740343879`; clean temporary worktree removed and branch retained

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

The frozen implementation owns exactly two target leaf files:

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
commit. Assignment-control commit
`cc6faddf707694e0c4a7af00a770d8a2672b8151` passed both jobs in immutable
Actions run `33733387021` (traceability 10 seconds; isolated target 3 minutes).
At that ready checkpoint, the bounded worker was limited to the two frozen
leaves and primary every-line, independent adversarial and complete integration
verification still remained required.

## Implementation Review and Local Gate

The first worker candidate, `37714106e3fcc4271bcdc5ee93bb7a66c41eca23`,
changed exactly the two allowlisted files and passed six focused tests plus the
full target package. Primary every-line review nevertheless rejected it because
generic “some error occurred” assertions did not prove failure ownership and
the promised current/cached field, fingerprint, command-forwarding and token
matrices were incomplete.

The expanded candidate `d50cc9e383f42ffe8519fd27980dfa96ea59ada4`
closed those evidence gaps and exposed a real implementation defect: canonical
failed updates with no cache omit the optional `cached` key, but the strict
decoder required it. Review then found that an explicit `cached: null` would
still decode as canonical nil and fail byte-identical restart. Corrected worker
tip `272b705e246cf505007f38a3d3d386dd8fbc127a` accepts only an absent key for
nil or a present nonnull strict snapshot. Retryable, unavailable and required-
update nil-cache forms, Business Inventory scope and the reciprocal explicit-
null rejection are all covered. Final primary and independent adversarial
review report no remaining P0-P3.

The worker worktree is clean and base-to-tip changes remain exactly the two
allowlisted paths. The reviewed candidate was cherry-picked as implementation
commit `6859b59c`. The complete local integration gate passes conversion,
capability, query, residual and M0 controls; target isolation and generated
contracts; six focused and all 243 tests in 54 suites; warnings-as-errors;
repeatable XcodeGen with unchanged project/scheme hashes `0657194a` /
`388303af`; macOS and generic iOS Simulator staging builds; valid JSON and clean
formatting. Implemented leaf hashes are:

- `SpaceChecklistEditingPresentation.swift` — `81200d735ead79c8ab16f0c2f9a7185e97b801a41782ec2368d86d34b1f4f85a`; and
- `SpaceChecklistEditingPresentationTests.swift` — `86c5aeb3ffeca9177699df5bdf85abb24229dccc2f5a81ae3b2d419139b2951b`.

Exact integration commit `5a5c67b1319e3fcc41290469f7f39db9d515b284`
passed both jobs in immutable Actions run `33739849778` (conversion state and
traceability 12 seconds; isolated target environment 2 minutes 11 seconds).
The slice and both surfaces are verified. At that checkpoint, promotion CI and
clean temporary-worktree removal still remained before the delegated-work
record could be closed.

Promotion commit `fd54f8c5db700af6ab8833e195da04256836ea58`
passed both jobs in immutable Actions run `33740343879` (conversion state and
traceability 8 seconds; isolated target environment 2 minutes 51 seconds).
The temporary worktree was clean at reviewed tip
`272b705e246cf505007f38a3d3d386dd8fbc127a` before removal. Branch
`codex/supabase-slice-space-checklist-edit` and its candidate history remain
recoverable.

## Permanent Exclusions

This evidence does not decide archived-Space edit availability and does not
authorize template application/saving, attachment/media behavior, Item
assignment, review notes, Space archive/completion, accounting, SwiftUI,
operation-port invocation, physical local persistence, authorization,
Postgres, Data API, RLS, PowerSync, MCP, migration, hosted resources,
production access, release or cutover. O-023/O-026/O-032/O-037 and
A-003/A-004/A-007/A-015/A-016 remain open or outside the boundary.
