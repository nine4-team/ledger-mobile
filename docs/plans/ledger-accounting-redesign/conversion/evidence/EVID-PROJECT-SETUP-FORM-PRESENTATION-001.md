# EVID-PROJECT-SETUP-FORM-PRESENTATION-001 — Project Setup Form Presentation

- Timestamp: 2026-09-02
- Class: verification / provider-free Project setup preparation and command derivation
- Source baseline: `fe018501d67cc84b6f140b2645b8a8149ea5c4f6` on `firebase`; the source worktree and released Firebase app remain unchanged
- Claimed target surfaces: `SWIFT-EC2117B393FB`, `TEST-38F09C637761`
- Slice dossier: `conversion/implementation-slices/project-setup-form-presentation-contracts.json`
- Verification state: verified after corrected implementation, full local gate, independent review and exact integration-commit CI

## Selection and Product Authority

Two read-only scouts independently reviewed the next candidate set after the
Project-browsing slice. One preferred a generic export renderer, while the
other identified a more complete Project-setup preparation outcome. The export
proposal cannot yet produce an approved named Transaction export profile, so it
remains a later infrastructure candidate rather than the next product slice.

The selected boundary composes three verified dependencies:

- `ProjectSetupOperation` owns stable existing/new Client input, exact nullable
  category allocation, one complete Project setup draft and the canonical
  `CreateProjectCommand`;
- `ProjectExistingClientSelectionSnapshot` owns ordered active-Client evidence,
  exact stable selection and authoritative-empty versus incomplete truth; and
- `BudgetCategoryReferenceSnapshot` owns Account-scoped category identity,
  lifecycle, system status, kind, presentation order and revision.

Canonical Projects authority permits zero enabled categories and requires one
durable Project/Client/category operation with separate media handling. Client
authority requires stable Client identity and prohibits treating display text
as identity. This slice therefore removes current-source free-text Client
ownership, preselect-all/at-least-one behavior, missing-allocation-as-zero,
on-the-fly reference mutation and silent independent writes from the target
boundary.

## Frozen Boundary

Exactly two target leaf files are claimed; both were comment-only at the READY
checkpoint and are now verified implementations:

- `LedgeriOS/LedgerTargetCore/ProjectSetupFormPresentation.swift`; and
- `LedgeriOS/LedgerTargetCoreTests/ProjectSetupFormPresentationTests.swift`.

The implementation produces one deterministic preparation snapshot over exact
Account-matching active-Client selection evidence and category-reference
evidence. It preserves Client upstream order, category presentation order and
both sources' exact represented local evidence plus their independent readiness
and completeness state. It exposes only configurable active, non-system
categories, but does not infer authorization or hidden counts.

One evidence-bound selection supports either an exact represented existing
Client or a validated preallocated new Client. Selected category allocations
are explicit and duplicate-free; their input order is non-semantic, zero
categories is valid, and selected null, zero and positive Money remain
distinct. A new Client ID already represented by an existing Client is refused
locally; unrepresented collision authority stays at server apply. Raw optional
Project description reuses `ProjectDescriptionReplacement`, so outer whitespace
is trimmed and nil, empty or whitespace-only input becomes nil. The only
command-producing call must
revalidate current preparation evidence before deriving the already-verified
`ProjectSetupDraft` and `CreateProjectCommand`. A changed source or substituted
sibling Client/category must fail before any command exists.

## Required Verification

The passing implementation tests cover:

1. Account scope, exact Client/category order, same-name Client identity,
   configurable category filtering and independent readiness/completeness;
2. existing and new Client selection plus unknown, archived, cross-Account and
   sibling-rebound refusal, including represented new-ID collision refusal;
3. zero categories and null/zero/positive allocations plus duplicate,
   negative, unknown, inactive and system-category refusal, while equivalent
   allocation input order canonicalizes identically and no Project-wide
   currency rule is invented;
4. nil/empty/whitespace/trimmed description normalization plus exact Project/
   Operation/actor/contract/time command derivation;
5. canonical restart and strict malformed-key, evidence-mutation and fingerprint
   tamper refusal; and
6. absence of automatic defaults, authorization, port invocation, physical
   persistence, provider and authoritative result claims.

The ready and implementation checkpoints must also pass conversion/capability/
query/residual controls, M0, target isolation and generated contracts, the full
target tests, repeatable XcodeGen, macOS and generic iOS Simulator staging
builds, clean artifacts, exact path scope and immutable CI on the recorded SHA.

## Local Ready Verification

The complete local ready gate passes with 811 recorded / 796 discovered
surfaces, zero errors and the three established retired-path warnings; 382
mapped / 167 residual / 44 blockers; M0; all 231 existing tests in 52 suites;
target isolation and generated contracts; two identical XcodeGen outputs;
macOS and generic iOS Simulator staging builds; and clean diff formatting.

The comment-only scaffold hashes are:

- `ProjectSetupFormPresentation.swift` — `606bd43ba122c00c596d4e55eb610a8c0bfa20da4f413c85eb8d158fe1b92cfe`; and
- `ProjectSetupFormPresentationTests.swift` — `625e9f61b0181e7c019f0d044f3b2e9da8e02bbe78e1373f1a57cc523afc4e15`.

Repeatable generated project/scheme hashes remain
`0657194a678ebbeb7d55e322303e2c5d63198f342e090d2f7072525b20ff9f53`
and `388303af0f4bd6641d70c669ff3754445ab4f59c1a5310cdfe69336827990ed8`.
Independent actual-ready-diff review is complete. Exact ready commit
`a4dd7cbdca3dcf7b31c386e4f451ad320b7c8e62` passed both jobs in immutable
Actions run `33726485780`. The temporary worker branch/worktree started at that
exact commit. Assignment-control commit
`10913c5761561ad9fdd0713627ae82396e9f3ff8` passed both jobs in immutable
Actions run `33726899284`; the worker received only the two frozen leaf paths.

The first actual-diff review rejected two ambiguities before commit: an
unsupported same-currency rule despite no Project-currency authority, and
underspecified creation-description normalization. The corrected boundary
removes mixed-currency refusal entirely, explicitly invents no Project-wide
currency rule, reuses the verified `ProjectDescriptionReplacement` behavior and
adds allocation-order equivalence plus represented new-Client-ID collision
tests. Correction re-review caught one remaining P2 phrase that could have
misrepresented partial evidence as complete; the phrase was corrected to bind
exact represented evidence and independent readiness/completeness state. Final
independent re-review returned GO with no remaining P0-P3 issue.

## Implementation Review and Local Gate

The first worker candidate, `7a881af2ff2ef86d1ef4ca4f08c7e604f0aacbe2`,
changed exactly the two allowlisted files and passed its six focused tests plus
the full package. Primary every-line review nevertheless rejected it for one P2
test-coverage gap: the restart test and frozen manifest promised every-field
evidence binding, but the test mutated only representative fields.

Corrected worker tip `37145ae3548e577469599ff2381c02258b01f130`
adds a table-driven mutation matrix that independently changes every named
preparation, Client snapshot/row, category snapshot/row and selection field.
Expected failures remain layer-specific, and the tests do not recompute hashes
or share production validation logic. Final primary and independent adversarial
review returned GO with no remaining P0-P3. The worker worktree was clean and
base-to-tip changes remain exactly the two allowlisted paths.

Integrated production and correction commits are `7365fbcb` and `bfac9f7a`.
The complete local gate passes conversion/capability/query/residual/M0 controls,
target isolation and generated contracts, six focused and all 237 tests in 53
suites, warnings-as-errors, repeatable XcodeGen with unchanged project/scheme
hashes, macOS and generic iOS Simulator staging builds, and clean formatting.
Implemented leaf hashes are:

- `ProjectSetupFormPresentation.swift` — `fff3eb39b4b178fc32e2578280d6f7b4f6d52a3b706266a0aa35829983e3ef67`; and
- `ProjectSetupFormPresentationTests.swift` — `243152d8833b1399e3b543bc91abf5fab7e86b89f91d702b572be3d6a6c5e496`.

Exact integration checkpoint
`147d22de801b15794d8ebb4786eaea86e4346940` passed both jobs in immutable
Actions run `33729967356`: conversion state and traceability completed in 10
seconds and the isolated target environment completed in 3 minutes 9 seconds.
The slice and both claimed surfaces are verified.

Promotion commit `5322adfca32ce5fd90f790f70ed584090ab5eee1`
passed both jobs in immutable Actions run `33730394704` (traceability 9 seconds;
isolated target 2 minutes 21 seconds). The worker worktree was clean at reviewed
tip `37145ae3548e577469599ff2381c02258b01f130` and was removed. Branch
`codex/supabase-slice-project-setup-form` and both worker candidate commits are
retained for audit and recovery.

## Rejected Alternatives

- Pinned-budget presentation was rejected even though its source surfaces were
  target-mapped: O-005 leaves negative-credit visuals open, and category
  visibility/missing/deleted pin behavior and card fallback are not settled.
- Project browsing shell duplicates the verified presentation contract and
  would require unresolved runtime routing, workspace, media and budget cards.
- Transaction list/card remains gated by O-029/O-032 lifecycle, amount,
  completeness and action semantics.
- General Space list lacks authoritative ordering/search/count semantics and is
  still affected by O-037 archive behavior.

No implementation or speculative scaffold was accepted for those candidates.

## Permanent Exclusions

The verified preparation/derivation structure remains valid, but the
new-Client branch currently consumes a provisional `ClientDisplayName`. O-043
must define and prove the raw-input submission boundary before provider
promotion; this evidence does not claim cross-runtime name validation. The
existing-Client branch is unaffected.

This evidence does not authorize SwiftUI layout, wording, step count, category
defaults, category creation, hero media, a Project-specific submission reducer,
actual operation invocation, authorization, physical local persistence,
Postgres, Data API, RLS, PowerSync, MCP, migration, hosted resources, production
access, release or cutover. O-023/O-024/O-025/O-026 and
A-003/A-004/A-007/A-015/A-016 remain open or outside this boundary.
