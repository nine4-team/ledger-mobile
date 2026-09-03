# EVID-PROJECT-SETUP-USE-CASE-001 — Project Setup Use Case

- Timestamp: 2026-09-03
- Class: ready design / provider-free Project setup selection-to-application dispatch
- Source baseline: `fe018501d67cc84b6f140b2645b8a8149ea5c4f6` on `firebase`; source worktree and released Firebase app unchanged
- Target-branch baseline: exact Space-checklist verification-promotion commit `ecd0ca9fc2f11c4a4bd02f3687b6ba76209cb649`; immutable Actions run `33789427209` passed both jobs
- Claimed target surfaces: `SWIFT-EE8576F5CD39`, `TEST-BB8C5679BA31`
- Preserved source surfaces: `SWIFT-58A14BD25578`, `SWIFT-038E6D4248AF`, `TEST-E591BE8A4B58` remain `target_mapped`; `SWIFT-E1A771F6A409` remains `characterized`
- Verified dependencies: `SWIFT-EC2117B393FB`, `TEST-38F09C637761`, `SWIFT-C1C5DFC81448`, `TEST-99B322EB971A`
- Slice dossier: `conversion/implementation-slices/project-setup-use-case-contracts.json`
- Verification state: comment-only READY package passes the complete local gate and two independent corrected-diff reviews; immutable exact-ready-commit CI remains required

## Selection and Authority

The prior verified Space-checklist slice was closed before this candidate was
activated. A root scout and a separate strict-authority preflight independently
selected the Project setup selection-to-application boundary above the existing
verified Project setup form-presentation and operation contracts. The candidate
IDs were independently recomputed from their canonical relative paths and are
absent from the pre-slice manifest.

Canonical Projects authority requires one observable setup that binds stable
Project identity, authoritative account-scoped Client identity, the complete
selected-category set and exact nullable allocations, while hero media follows
the separate durable attachment lifecycle. Canonical Client authority makes
`clientId`, never name, the Project relationship. Zero categories is valid.

The open O-023/O-024/O-025/O-026 decisions do not block this boundary because it
implements no media retention, Project lifecycle/delete, Client/Project
correction or shared-reference authorization. Those decisions remain open and
unadvanced.

## Frozen Boundary

Exactly two comment-only target leaves are claimed:

- `LedgeriOS/LedgerTargetCore/ProjectSetupUseCase.swift`;
- `LedgeriOS/LedgerTargetCoreTests/ProjectSetupUseCaseTests.swift`.

The future `ProjectSetupUseCase` consumes the existing
`ProjectSetupFormSelection` and current `ProjectSetupFormPreparation` plus
caller-supplied Project, Operation, Principal, contract-version and finite
capture-time values. It must derive the existing `CreateProjectCommand` before
calling `ProjectSetupOperating.create` exactly once, validate the receipt and
return that exact receipt and local operation state.

Matching represented evidence remains admissible when Client/category quality
is ready, partial or stale according to the already-verified preparation
contract. The use case cannot invent a ready-only, complete-only or online-only
gate. Any changed current preparation fingerprint is refused before dispatch.
Preparation/readiness evidence never enters the command; rebuilding equivalent
business intent against changed but still-valid evidence may produce the same
command.

The application error boundary preserves `CancellationError`, every
`ProjectSetupFormFailure` and every `ProjectSetupFailure`, including either
typed family deliberately returned by the port. Only unknown port errors map to
`ProjectSetupFailure.localAcceptanceFailed`. Derivation stays outside the port
catch so construction failures cannot be silently reclassified.

## Required Verification

Eight obligations freeze executable proof for:

1. existing/new Client setup and matching ready/partial/stale evidence with one call;
2. zero categories and exact absent/null/zero/large-positive mixed-currency allocation intent without defaults, a 32-bit cap or invented currency rule;
3. exhaustive changed-evidence and nonfinite-time refusal before any call;
4. all six exact receipt states and one-call receipt mismatch;
5. flattened reciprocal encoded-leaf deltas for every setup and operation input plus preparation-evidence non-leakage;
6. every one of the 12 form and 16 operation failures, structured cancellation and bounded unknown error;
7. complete diagnostic mapping and exact nested encoded-command topology with permanent exclusions; and
8. exact READY/implementation allowlists, complete controls/builds and immutable CI before promotion.

The planned test suite must use only existing typed values. Malformed
preparation/selection decoding remains proven by the verified dependency; this
use case cannot invent a raw decode API to manufacture impossible inputs.

## READY Package

The two comment-only leaf hashes are:

- `ProjectSetupUseCase.swift` — `8149206ded79f1de4ac0335602259bfcae59821a4425069a02e8989370282d80`;
- `ProjectSetupUseCaseTests.swift` — `6c6a19210a53baeb2b8b0303391f5f745d9ef27e0535f608882330fed124b542`.

The strict preflight found no authority contradiction or NO-GO condition. The
complete local gate passes with 825 recorded / 813 automatic-inventory entries
(810 currently discovered plus three retained missing-source warnings), zero
errors and only those three established warnings; 391 mapped-or-
later / 174 residual / 45 blockers; all 273 existing target tests in 59 suites
with warnings as errors; target environment isolation and generated contracts;
repeatable generated project/scheme hashes `0657194a` / `388303af`; macOS and
generic iOS Simulator staging builds; JSON validation and clean formatting.
Independent review first found a comment-only provider-coupling scanner false
positive. A separate adversarial review found an impossible explicit-null
allocation encoding assertion, inaccurate existing-to-new Client delta wording
and ambiguous automatic-versus-current discovery counts. The corrected package
uses generic exclusion language, binds nil allocation to omitted `allocation`,
states that Client `kind` changes while `displayName` is added, and distinguishes
813 automatic-inventory entries from 810 currently discovered sources plus the
three retained warnings. Both reviewers rechecked the exact 17-path package and
returned GO with no remaining P0-P3. Exact-ready-commit CI remains required
before implementation begins.

## Permanent Exclusions

This evidence does not authorize SwiftUI steps/copy/loading/validation display,
defaults, preselect-all, at-least-one-category, missing-as-zero, category
creation/mutation, hero attachment identity/bytes/upload/reference/removal/
retention, Project edit/archive/restore/delete, Client rename/archive/merge/
reassignment, lifecycle defaults, optimistic Project projection, physical local
durability, retry scheduling, authoritative handler/apply, membership or audit,
Postgres, Data API, RLS, PowerSync, provider/Auth, app/MCP wiring, Firebase
decoding or migration, hosted resources, production access, release or cutover.
O-023/O-024/O-025/O-026 and A-003/A-004/A-007/A-015/A-016 remain open or
outside this boundary.
