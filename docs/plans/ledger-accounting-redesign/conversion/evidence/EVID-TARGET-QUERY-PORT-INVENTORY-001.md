# EVID-TARGET-QUERY-PORT-INVENTORY-001 — Target Query-Port Inventory Control

- Timestamp: 2026-09-03
- Class: READY / deterministic target query-port conversion control
- Source baseline: `fe018501d67cc84b6f140b2645b8a8149ea5c4f6` on
  `firebase`; source worktree and released Firebase app unchanged
- Prior conversion baseline:
  `3c7c52e07646236d0a9bb38298c1fcc5bf44fcc8`
- Claimed target surfaces: `CONFIG-9B16CFCB67A4`,
  `CONFIG-C1C61B2D6569`
- Deliberately changed preserved control: `FILE-208B7E9D7F47` remains
  `verified` under `M0-CAPABILITY-CONTROL-001`
- Slice dossier:
  `conversion/implementation-slices/target-query-port-inventory-control.json`
- Product decisions: none; A-003/A-004: not applicable
- Production reads or mutations: none
- Hosted Supabase/PowerSync resources contacted: none
- Verification state: comment-only READY passed primary every-line and
  independent actual-diff review; generator, generated artifacts, package
  commands and CI hook remain unauthorized until exact-READY-SHA CI passes

## Operational Outcome and Authority

CI must deterministically refuse stale, ambiguous or unparseable inventory of
every direct instance-method requirement in every public `LedgerTargetCore`
protocol whose name ends exactly `Querying`. This is shared conversion control,
not a product feature, provider adapter, logical access design or physical index
design.

The slice applies the required synchronized lifecycle from
`vertical-slice-implementation-method.md`: authority and test obligations are
frozen before code; exact READY, implementation and promotion checkpoints remain
separate; and generated output is a mandatory human-review surface. Machine
freshness cannot claim that a human approved a new query, signature or index.

Architecture requires commands and queries to remain separate, ports to express
Ledger capability instead of provider mechanics, dependencies to point inward,
and future implementations to satisfy reviewed contracts. The existing
`current-query-contract.md` supplies an analogous reproducible-inventory method
and explicit warning that lexical evidence does not establish runtime activity
or index sufficiency. It does not make Firestore shapes target authority.

## Frozen Baseline

Repository inspection at the prior verified checkpoint found exactly 16 public
exact-suffix `Querying` protocols on 16 verified owning surfaces and exactly 18
direct instance-method requirements. All 18 current selectors begin with
`watch`; therefore all are observations at this baseline. The exact owners are:

- `SWIFT-C1B994920894` — `AccountQuerying` —
  `watchAuthorizedAccounts`;
- `SWIFT-8351FACDBE06` — `BudgetCategoryReferenceQuerying` —
  `watchBudgetCategories`;
- `SWIFT-D7F3D08FA568` — `ClientCoreDetailsQuerying` —
  `watchClientCoreDetails`;
- `SWIFT-401EBD892749` — `ClientProjectDirectoryQuerying` —
  `watchClients`, `watchProjects`;
- `SWIFT-A3B756DA1382` — `OperationQuerying` — `watchOperation`,
  `watchUnresolvedOperations`;
- `SWIFT-42C7BDDCD714` — `ProjectBudgetSegmentQuerying` —
  `watchProjectBudgetSegments`;
- `SWIFT-E084EBB4EBFF` — `ProjectCategoryConfigurationQuerying` —
  `watchProjectCategoryConfiguration`;
- `SWIFT-4C4690368BEC` — `ProjectCoreDetailsQuerying` —
  `watchProjectCoreDetails`;
- `SWIFT-008B49A474D1` — `ProjectItemAccountingQuerying` —
  `watchProjectItemAccountingSections`;
- `SWIFT-B3DBE3375ACE` — `ProjectNoteQuerying` — `watchNotes`;
- `SWIFT-C6AE96622805` — `ProjectPreferenceQuerying` —
  `watchProjectPreferences`;
- `SWIFT-164554FA1456` — `SpaceAssignmentDestinationQuerying` —
  `watchEligibleDestinations`;
- `SWIFT-02BF0EA3C433` — `SpaceCoreDetailsQuerying` —
  `watchSpaceCoreDetails`;
- `SWIFT-77F812A8F463` — `SpaceTemplateQuerying` —
  `watchSpaceTemplates`;
- `SWIFT-1A05F36246B4` — `TransferDestinationSelectionQuerying` —
  `watchTransferDestinations`; and
- `SWIFT-111A94B464D5` — `VendorSuggestionQuerying` —
  `watchVendorSuggestions`.

All 16 remain `verified` and retain their existing product or platform slice
ownership. The only multi-method protocols are
`ClientProjectDirectoryQuerying` and `OperationQuerying`, with two methods each.

## Frozen Scanner Contract

The future `scripts/generate-target-query-port-inventory.mjs` is a
dependency-free Node lexical state machine. It recursively scans target-core
Swift sources, masks line/block comments and strings, tracks braces,
parentheses and generic delimiters, and supports multiline declarations,
attributes, nested generics, `async`, `throws`, return clauses and `where`
clauses.

It includes every direct instance `func` requirement in a public protocol whose
name ends exactly `Querying`; requirements need no redundant `public` keyword.
It excludes implementations, extensions, comments, strings, private/internal
protocols and non-exact names. `watch*` selectors classify as `observation`;
future non-watch selectors classify as `request_response`.

Unsupported direct functions, malformed or ambiguous declarations, duplicate
selectors/overloads, empty Querying protocols, missing or ambiguous manifest
ownership and invalid owner lifecycle status reject the complete inventory.
Nothing is silently skipped.

Each row receives a stable TQUERY ID derived only from owner surface ID,
protocol and selector. A separate normalized signature hash detects parameter
label/type, generic, attribute, async/throws, return and where-clause drift.
Output is sorted, timestamp-free and normalized across CRLF, harmless
whitespace and masked comments/strings.

## Frozen Artifact and CI Topology

Implementation may create exactly these generated review artifacts:

- `docs/plans/ledger-accounting-redesign/conversion/target-query-port-inventory.generated.json`;
- `docs/plans/ledger-accounting-redesign/conversion/target-query-port-inventory.generated.md`.

Root package commands will be exactly `target:query-ports:generate`,
`target:query-ports:check` and `target:query-ports:test`. The Ubuntu
conversion-control job will run inventory test/check, and the macOS
target-environment job will explicitly depend on that job succeeding. Target
Swift tests and builds therefore cannot start after an inventory failure.
`check` computes both artifacts in memory, byte-compares them and never writes.
`generate` followed by `check` must be clean.

No generated JSON/Markdown, package script or workflow hook exists in READY.
Creating false generated output before the parser exists would defeat the
control.

The synchronized READY ledger records 837 surfaces / 822 currently discovered,
393 target-mapped-or-later surfaces, 184 residuals and 46 blockers. Sixty-five
slices claim 155 surfaces; 138 surfaces are implementation-advanced. The only
conversion warnings are the three established retired-path warnings.

## Deliberate Conversion-Discoverer Re-Acknowledgment

`scripts/supabase-conversion-ledger.mjs` (`FILE-208B7E9D7F47`) deliberately
changes so normal synchronization assigns the two exact stable CONFIG IDs to
the two READY leaves. It also excludes those named target controls from the
Firebase audit/repair discovery group, even though their contract prose names
Firestore as an exclusion. Without that exact exclusion the same generator
would be falsely duplicated as a Firebase-tool surface.

The classification batch must acknowledge the exact reviewed new discoverer
hash. Its `verified` status, preserve disposition, conversion-control ownership
and existing implementation evidence remain unchanged. This is an explicit
extension of repository discovery, not silent blessing of unrelated drift.

## Required Tests

Eight planned obligations freeze proof for:

1. exact 16-owner / 16-protocol / 18-method baseline, all observation, with the
   two exact multi-method sets;
2. deterministic IDs, hashes, sorted JSON/Markdown and normalization;
3. stale detection for protocol/method additions, removals, renames and every
   signature axis;
4. supported multiline/attribute/generic/where syntax plus exact exclusions;
5. every malformed, ambiguous, duplicate, empty or invalid-owner fail-closed
   case;
6. missing/stale artifacts, read-only check and generate-then-check behavior;
7. exact READY/implementation/promotion allowlists and preservation of existing
   query-owner/control surfaces; and
8. Ubuntu inventory CI gating the macOS target job, plus a separately recorded
   human generated-diff review.

The implementation test suite must use synthetic fixtures for mutations and
negative cases. It may not alter existing Swift port declarations to make the
scanner easier to write.

## Exact Change Allowlists

READY may contain only:

- the two comment-only script leaves;
- the slice dossier and this evidence file;
- classification, crosswalk, evidence-index, tracker and execution-state
  metadata;
- synchronized generated conversion audits/coverage/manifest; and
- the deliberate `discoverConfiguration()` plus Firebase-tool exclusion change
  in `scripts/supabase-conversion-ledger.mjs`.

Implementation may replace only the two script leaves, add only the exact JSON
and Markdown generated artifacts, and add the exact package commands, Ubuntu
conversion-control hook and macOS target-environment job dependency. The
implementation checkpoint synchronizes hashes/status/evidence as required by
the lifecycle method. Promotion is a later documentation/control-only checkpoint
after immutable implementation CI.

`CONFIG-7AE45AD102EA` (`package.json`) remains `characterized`,
`CONFIG-1FC6F8A5DFA5` (workflow) remains `target_mapped`,
`FILE-063B0E6EC659` and `MAN-INDEX-001` remain `target_mapped`, all 16 owners
remain `verified`, and `FILE-208B7E9D7F47` remains `verified`. None is claimed
by this slice.

## Explicit Downstream Slices

The generated TQUERY inventory is input to two later bounded slices:

1. a logical access/index crosswalk reviewing every generated TQUERY before
   physical Postgres or local SQLite index work; and
2. reconciliation of the full target TQUERY set against all 386 `QUERY-*`
   source occurrences in `query-contract.generated.json`.

Neither downstream obligation is advanced here.

## Excluded Claims

This READY package does not define or prove query predicates, filtering,
ordering, pagination, readiness, snapshots, result semantics, source-query
completeness, runtime usage, Firestore mapping, logical access design, Postgres
or SQLite physical indexes, SQL/EXPLAIN, RLS, Sync Streams, PowerSync, provider
adapters, hosted resources, production behavior, a runtime Swift manifest,
product UI/stories, app/MCP transport, migration, reconciliation, release or
cutover. It does not advance `FILE-063B0E6EC659`, `MAN-INDEX-001`, any existing
query owner, package/workflow/discoverer support surface, or A-003/A-004.

## READY Gate

Both claimed leaves remain comment-only and `target_mapped`. Syntax checks can
prove only valid comment-only modules. Exact baseline enumeration, generated
artifacts, package commands, CI integration and every negative parser/freshness
case remain planned until implementation. Primary every-line review and
independent actual-diff review passed with no remaining P0-P2 findings. Immutable
exact-READY-SHA CI must still pass before executable work begins.

## Local READY Verification

The complete local READY gate passed on 2026-09-03:

```bash
node --check scripts/supabase-conversion-ledger.mjs
node --check scripts/generate-target-query-port-inventory.mjs
node --check scripts/tests/generate-target-query-port-inventory.test.mjs
npm run conversion:check
npm run conversion:report
npm run conversion:gate:m0
npm run conversion:capabilities:check
npm run conversion:queries:check
npm run conversion:residuals:check
npm run target:environment:check
npm run target:contracts:check
swift test --package-path LedgeriOS -Xswiftc -warnings-as-errors
npm run target:project:generate
npm run target:staging:build:macos
npm run target:staging:build:ios
git diff --check
```

Results:

- all three Node syntax checks pass while both new leaves remain comment-only;
- conversion checking/reporting and M0 pass with zero errors and only the three
  established retired-path warnings;
- capability, 386-occurrence source-query and 393-mapped/184-residual/46-blocker
  artifacts are current;
- target isolation and generated contract controls pass;
- all 316 existing Swift tests in 65 suites pass with warnings as errors;
- repeatable target project generation plus macOS and generic iOS Simulator
  staging builds pass;
- the two future target query-port generated artifacts are absent as required;
  package/workflow support files and all Swift query owners have no diff; and
- tracked diff formatting and JSON parsing pass.

These local results do not pass any planned generator obligation. They prove
only that the synchronized READY package is internally valid and does not break
the existing target foundation. Immutable exact-READY-SHA CI remains pending.
