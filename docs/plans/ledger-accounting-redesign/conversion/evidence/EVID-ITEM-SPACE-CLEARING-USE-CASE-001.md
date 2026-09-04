# EVID-ITEM-SPACE-CLEARING-USE-CASE-001 — Item Space Clearing Use Case

- Timestamp: 2026-09-03
- Class: READY / provider-free typed Item Space-clear dispatch
- Source baseline: `fe018501d67cc84b6f140b2645b8a8149ea5c4f6` on
  `firebase`; source worktree and released Firebase app unchanged
- Prior conversion baseline:
  `31fd8881499ff6668b9abd14bfdd9284774ab302`
- Claimed target surfaces: `SWIFT-EEAC86485FF6`, `TEST-CA84B398990C`
- Preserved verified dependency: `SWIFT-4C7158974133`,
  `TEST-0AB198EB6935` at exact implementation
  `f5a7ac7598f77859239b66666bc703ee4639c233` / immutable run
  `33677087616`
- Slice dossier:
  `conversion/implementation-slices/item-space-clearing-use-case-contracts.json`
- Verification state: comment-only READY prepared; implementation remains
  unauthorized until primary and independent review plus exact-READY-SHA CI pass

## Selection and Authority

The bounded candidate is the application boundary above the already-verified
`ClearItemSpaceAssignments` operation. Canonical Space authority distinguishes
explicit placement clear from destination assignment and allows one nonempty
operation to carry Items whose caller-supplied current-Space claims name
different Spaces within one Project or Business Inventory scope. D-019 and
D-023 keep placement independent from accounting; stable typed Item identity is
inherited from the verified operation and domain contracts.

The verified operation remains sole owner of canonical duplicate-free Item
ordering, typed revisions and current-Space claims, exact scope/revision/
current-placement conflict preconditions, operation metadata, subject,
fingerprint, receipt validation, restart/refusal and all 15
`ItemSpaceClearingFailure` values. This slice may compose those contracts. It
may not restate or extend their semantic authority.

Caller-supplied scope and current-Space values are untrusted conflict evidence.
The operation proves that its command and preconditions are internally
consistent; neither it nor this future use case proves actual current placement,
membership, or authorization. Stale assigned-looking evidence may be accepted
locally and later conflict when a trusted handler revalidates authoritative
state.

O-037 does not block explicit user-requested clear because Space archive and
archive-driven Item behavior remain excluded. O-023 does not block this
boundary because the client submits no attachment reference, byte, or marker
list, and this slice neither derives nor mutates marker relationships. The
future trusted handler owns authoritative closure of affected green Item-linked
photo-checkmark relationships without deleting photos or bytes.

## Frozen Boundary

Exactly two comment-only target leaves are claimed:

- `LedgeriOS/LedgerTargetCore/ItemSpaceClearingUseCase.swift`;
- `LedgeriOS/LedgerTargetCoreTests/ItemSpaceClearingUseCaseTests.swift`.

The future public `ItemSpaceClearingIntent` is transient and non-Codable, with
exactly `accountId`, `scope`, and typed `ItemSpaceClearingCandidate` values.
Every candidate structurally carries Item identity, expected Item-placement
revision, and a current-Space conflict claim. Nil/no-current-Space intent is
unrepresentable. That shape does not assert the Item is actually assigned,
does not decide mixed assigned/unassigned UI admission or filtering, and does
not create a no-op receipt.

The future generic
`ItemSpaceClearingUseCase<C: ItemSpaceAssignmentClearing>` receives the intent
and exact Operation, Principal, contract-version and finite capture-time values.
It constructs `ItemSpaceClearingDraft` and
`ClearItemSpaceAssignmentsCommand` before the port-error boundary, invokes
`clearItemSpaceAssignments` exactly once, and validates the returned receipt
outside that boundary.

Construction failures make zero calls. Receipt mismatch follows one call. Every
one of the 15 `ItemSpaceClearingFailure` values thrown by the port remains
exact, `CancellationError` remains structured cancellation, and only an unknown
port error maps to `ItemSpaceClearingFailure.localAcceptanceFailed`.

## Preserved Surface Register

The verified clearing dependency remains unchanged:

- `SWIFT-4C7158974133` — `verified`;
- `TEST-0AB198EB6935` — `verified`.

The sibling assignment operation/use-case/destination leaves remain unchanged:

- `SWIFT-4B007A00C393` — `verified`;
- `TEST-51D893DD949E` — `verified`;
- `SWIFT-0540BE125F5A` — `verified`;
- `TEST-DA67EAC9C2EF` — `verified`;
- `SWIFT-164554FA1456` — `verified`;
- `TEST-A3D73145E3EC` — `verified`.

The exact clear-space source and integration surfaces retain these statuses:

- `SWIFT-0B434663295C` — `characterized`;
- `SWIFT-4C8A8E236450` — `characterized`;
- `SWIFT-BDF8928A5FC7` — `characterized`;
- `SWIFT-DDFAC91775DA` — `characterized`;
- `SWIFT-AB578AEF4330` — `characterized`;
- `SWIFT-F3BDD0968C6D` — `characterized`;
- `SWIFT-4D0D546A02D` — `target_mapped`;
- `SWIFT-236679C7D427` — `characterized`;
- `SWIFT-C0ABD9666AE7` — `target_mapped`;
- `SWIFT-C593225376EB` — `characterized`;
- `SWIFT-47AEDE21C63C` — `target_mapped`;
- `TEST-6297E07C65AA` — `target_mapped`;
- `TEST-8B555E151D8D` — `characterized`;
- `TEST-C1A3D3DA5E75` — `target_mapped`;
- `MCPMOD-82DC4C25B1B8` — `characterized`;
- `MCPMOD-155A4AB80AC9` — `target_mapped`.

## Required Verification

Ten planned obligations freeze proof for:

1. ordinary non-`@testable` import and exact public three-field transient,
   non-Codable intent shape;
2. Project and Business Inventory dispatch with literal Account/scope ownership,
   one Item and mixed-current-Space candidate sets;
3. canonical ordering, identical command/fingerprint for reordered equivalent
   input, boundary revisions and stale assigned-looking dispatch;
4. zero-call empty, duplicate and nonfinite-time construction failures, plus
   structurally unrepresentable nil/no-current-Space intent and no synthetic
   no-op receipt;
5. all shared receipt states and one-call receipt mismatch;
6. a reciprocal flattened encoded-leaf matrix over Account, scope, every Item/
   revision/current Space, Operation, actor, contract and time, with literal
   expectations independent of production builders and validators;
7. all 15 operation failures, `CancellationError`, unknown-error containment,
   and exact construction/port/receipt catch boundaries;
8. all 15 stable diagnostics, exact intent/command topology and permanent
   exclusion of destination/archive/media/marker/scope/accounting/UI/provider
   fields;
9. separate READY, executable implementation and later promotion allowlists,
   with every enumerated dependency/sibling/source status preserved; and
10. separate immutable READY and implementation CI over complete controls,
    warnings-as-errors tests, repeatable generation, both staging builds, JSON
    validation and clean artifacts.

The implementation test leaf will prove obligations 1–8. Conversion controls,
primary every-line review, independent actual-diff review and exact READY CI
will prove obligation 9. Only exact implementation CI can pass obligation 10
and authorize later promotion to `verified`.

## Excluded Claims

This READY package does not implement or prove:

- archive behavior or O-037 resolution;
- attachment reference removal, byte deletion, retention, or O-023 resolution;
- marker derivation, closure, persistence, or projection;
- actual Item current placement, membership, scope validity, or authorization;
- mixed assigned/unassigned selection admission or filtering;
- a nil/unassigned/no-op clear or synthetic no-op receipt;
- Item selection/read readiness, Set/Clear Space UI eligibility, error UX, or
  presentation composition;
- destination assignment or Item scope movement;
- Transaction, occurrence, Invoice, budget, payer, price, acquisition,
  accounting or provenance mutation;
- physical operation/Item/Space persistence, optimistic projection, retry or
  rejection recovery;
- Auth, Postgres, Data API, grants, RLS, PowerSync, provider or hosted behavior;
- app/MCP wiring, source decoding, migration, reconciliation, deployment,
  release, production access, or cutover.

## READY Gate

The READY change may contain the two comment scaffolds and named conversion
dossier/evidence/control artifacts only. A later executable implementation
commit may replace only the two exact target leaves. Promotion documentation is
a separate checkpoint after exact implementation CI. No READY prose or local
test result may promote either leaf to `implemented` or `verified`.
