# EVID-BUDGET-CATEGORY-REFERENCE-POWERSYNC-PROVIDER-001 — Local Budget-Category Reference Provider

- Status: corrected comment-only READY candidate; exact independent review GO,
  immutable CI pending
- Date: 2026-09-05
- Environment: isolated target worktree and synthetic local fixtures only
- Production/Firebase impact: none
- Slice: `budget-category-reference-powersync-provider`

## Selected Outcome

The next bounded slice supplies the missing real local
`BudgetCategoryReferenceQuerying` implementation needed to replace the target
Project-setup shell's hardcoded category. It observes only category rows already
materialized in one encrypted Principal/Account workspace and exposes them
through the existing close-aware runtime facade.

This is an incomplete-first local projection, not final category authorization.
O-026 remains open for category administration and download visibility. The
adapter cannot inspect or interpret `visibility_class`, `financial_access`,
role, hidden rows, or hidden counts.

## Selection Audit

Three candidate directions were independently checked after the Account
workspace runtime passed immutable CI:

- physical session ending/workspace activation is blocked by A-007, A-016,
  O-023 and absent hosted synchronization/authorization proof;
- a direct Transfer-destination provider was rejected before implementation
  because the current Project directory merges caller-owned pending Projects
  into the same `ProjectSummary` shape as authoritative rows, while canonical
  Transfer eligibility requires authoritative Client identity; and
- the local budget-category provider is decision-independent when it consumes
  only the already-materialized subset, remains incomplete by default, and
  makes no visibility decision.

The rejected Transfer comment scaffolds were removed before classification or
commit. No executable Transfer behavior or durable false ownership remains.

## Frozen READY Boundary

Primary comment-only surfaces:

- `LedgeriOS/LedgerTargetPowerSync/BudgetCategoryReferencePowerSyncQuery.swift`;
- `LedgeriOS/LedgerTargetPowerSyncTests/BudgetCategoryReferencePowerSyncQueryTests.swift`.

Future implementation may also modify these shared surfaces under their
existing primary owners:

- `LedgerOfflineClientRuntime.swift` for one Account-bound public watch;
- `AccountWorkspacePendingWorkRuntime.swift` for exactly-one construction and
  the existing stream lease;
- `AccountWorkspacePendingWorkRuntimeTests.swift` for construction, close,
  cancellation and post-close proof; and
- deterministic public-symbol and target-environment controls.

That future touch set is frozen by exact manifest identity and the source hash
at this READY boundary:

| Manifest identity | Exact path | READY source hash | Permitted change |
| --- | --- | --- | --- |
| `SWIFT-548A8A928FAE` | `LedgeriOS/LedgerTargetPowerSync/LedgerOfflineClientRuntime.swift` | `20ccef5cbb04e905d113135b87b2bd22c38d75e0aa990021e7ba80faa4012b61` | Account-bound category-watch facade only |
| `SWIFT-75CFE285AF37` | `LedgeriOS/LedgerTargetPowerSync/AccountWorkspacePendingWorkRuntime.swift` | `608d3d9319cbcc3082dc750e36545f00da43825702d4639b3311ee38038da987` | exactly-one provider construction and existing stream lease only |
| `TEST-8D6A15063B2D` | `LedgeriOS/LedgerTargetPowerSyncTests/AccountWorkspacePendingWorkRuntimeTests.swift` | `f70ed4ea57e30cbc8287b097644b56881b19627b8dd453be92cd85045df47137` | category construction/facade/close/restart proof only |
| `CONFIG-81235587F306`, `FILE-A6E49E3815F4` | `scripts/check-target-environment.mjs` | `af4ccc5b6401059f2d26326127a7d482b265cf5383ad18d2008bf542dff965bd` | exact facade/provider/completeness source and build-graph rejection only |

The two control identities intentionally describe the same physical script.
Any other executable path or any mismatch from these READY hashes requires a
new review before implementation; listing these touchpoints does not transfer
their existing primary ownership to this slice.

Existing Supabase migrations, RLS policies, Data API grants,
`powersync/sync-streams.yaml`, the target staging app, MCP, and Firebase source
remain byte-unchanged and outside this READY package.

## Authority and Safety Result

The verified category-reference contract already defines stable category
identity, kind, lifecycle, system/exclusion flags, order, revision, visible-row
privacy, and partial/stale/ready distinctions. The provider may materialize
those values without deciding who may view or administer them.

The exact READY design requires:

- Account mismatch rejection before database observation;
- active same-Principal local membership only as a scope sentinel;
- no local category visibility or hidden-count logic;
- every materialized ordinary- and restricted-class row preserved;
- query-specific completeness false by default and independent of generic
  PowerSync status;
- authoritative empty only after explicit current-process completeness;
- atomic malformed/duplicate-row refusal;
- content-bound local versions and deterministic query identity;
- database/completeness reactivity, cancellation and restart proof; and
- live active-to-inactive/revoked-to-deleted membership changes immediately
  clear previously emitted rows as incomplete even when the independent
  completeness source remains true;
- a reciprocal literal-field and content-version matrix over every category,
  scope, completeness and quality axis; and
- runtime close cancellation/drainage before either database closes.

## Required Evidence Before Implementation

The independent reviewer inspected the corrected exact comment-only surfaces,
dossier, classification, affected shared files and test matrix and returned GO
with no remaining P0-P3 finding. Before executable work begins, the synchronized
READY commit must still pass all three immutable workflow jobs.

Implementation remains separate from verification promotion. It cannot advance
A-003/A-004/A-007/A-016/O-026, authorize hosted resources, access production,
read or modify Firebase, migrate data, release, or cut over.

## Independent Review Correction

The first exact-package review returned NO-GO before executable work. It found
that generic prose did not freeze shared touchpoints, static membership cases
did not prove same-watch retraction, this enabling provider was incorrectly
classified as a product outcome, field/version proof was not reciprocal, the
compiler-symbol claim exceeded the repository's tooling, and one source token
caused conservative Firebase-coupling metadata. This corrected candidate:

- records exact shared manifest IDs, hashes, permitted responsibility and
  unchanged primary ownership;
- adds same-watch active-to-revoked/deleted clearing with stale-completeness
  rejection;
- classifies the provider as a technical control inheriting the verified
  category-reference contract;
- adds a literal-field, version and fingerprint matrix;
- narrows compiler-boundary proof to explicit compile-time assertions and exact
  checks added to the frozen environment script; and
- removes the misleading source token from the test scaffold.

Final independent re-review returned GO with no remaining P0-P3 finding.
Immutable READY CI remains required.
