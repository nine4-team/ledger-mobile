# EVID-TRANSACTION-TYPE-CHOICE-PRESENTATION-001 — Transaction Type Choice Presentation

- Timestamp: 2026-09-02
- Class: implementation checkpoint / provider-free Transaction type-choice presentation
- Source baseline: `fe018501d67cc84b6f140b2645b8a8149ea5c4f6` on
  `firebase`; the source worktree and released Firebase app remain unchanged
- Claimed target surfaces: `SWIFT-F90B7B48C1F6`, `TEST-F66BBF1FC092`
- Slice dossier:
  `conversion/implementation-slices/transaction-type-choice-presentation-contracts.json`
- Verification state: verified after corrected primary and independent review,
  complete central gates and immutable exact-integration-commit CI
- Ready scaffold hashes:
  - `TransactionTypeChoicePresentation.swift`:
    `ec01c3543c3c407f26d9a1fb6a5c1d716edd089e174d8757b1113ed6d814d629`
  - `TransactionTypeChoicePresentationTests.swift`:
    `448ec87f3d2d231fe69631e981d8403840790a1eb618cabfd328a713699f49e6`
- Reviewed implementation hashes:
  - `TransactionTypeChoicePresentation.swift`:
    `45f0312f910a20007363f7443b76dbb7f0201a4840ffd224051bc2b9002a3f20`
  - `TransactionTypeChoicePresentationTests.swift`:
    `81022ad90925ebce0cd34c5e0c639eb59f69deb15a5db4a830402379e34ee77e`

## Selection and Scope

The read-only scout selected the smallest decision-independent Transaction
presentation leaf disjoint from the active Project existing-Client selection
worker. Canonical target authority already fixes the three global types, exact
scope owners and exact economic meanings. The verified
`transaction-taxonomy-and-transfer-identity` slice already owns classification,
scope and role validity.

This boundary therefore adds no Transaction model, command or query. It exposes
literal unordered type membership by owner kind and derives a small descriptor
from an already-valid `TransactionClassification`.

Exactly two target-only comment scaffolds are claimed. No executable behavior
or test exists at this checkpoint.

## Independent Adversarial Preflight

The first scout proposal risked creating another aggregate carrying type, full
scope and role and used noncanonical “Business owner” vocabulary. Independent
review narrowed the boundary before freeze:

1. `TransactionClassification` remains the sole aggregate. The descriptor may
   carry only canonical type, owner kind and economic meaning plus exact derived
   titles; it has no public fieldwise initializer or persisted representation.
2. Membership is a literal `Set`, never array/declaration/filter/UI order:
   Project has Purchase, Return and Transfer; Business Inventory has Purchase
   and Return.
3. Exact owner titles are `Client` and `1584`. `Business Inventory` may name a
   scope elsewhere but cannot replace the canonical owner.
4. Transfer has one presentation and one non-cash meaning. Source and
   destination roles must project identically; direction is not a choice.
5. The three informing source presentation surfaces remain target-mapped rather
   than promoted because they also own unresolved filters, legacy vocabulary,
   badges, colors, status, calculations and other excluded behavior.

After those corrections, independent review returned GO with no P0-P2 blocker
or product decision required.

Independent review of the actual ready diff then found one P3 test-spec
precision problem: the draft could accidentally freeze `CaseIterable` order,
described restart across five semantic pairs without explicitly covering both
Transfer roles, and ambiguously called display titles the whole public
vocabulary. The corrected dossier requires literal `Set(allCases)` plus an
exact count of three while forbidding array/order equality, restart of all six
valid classification shapes with equal restored Transfer descriptors, and an
exact display-title string set. After regeneration the reviewer returned GO
with no remaining P0-P3 finding; conversion validation reports 805 recorded /
790 discovered surfaces, zero errors and only the three established retired-
path warnings.

## Ready-Gate Contract

The dossier freezes six requirements and seven future test obligations:

- literal unordered scope membership with Inventory Transfer excluded;
- exact `Purchase`, `Return`, `Transfer`, `Client` and `1584` vocabulary;
- all six valid classification shapes (four standalone Purchase/Return shapes
  plus both project Transfer roles), covering all five owner/type pairs and
  their existing canonical economic meaning;
- equal source/destination Transfer presentation and no role/direction field;
- canonical restart of all six shapes through the verified classification only,
  with exact emitted classification/scope key allowlists and equal restored
  Transfer descriptors; and
- exact existing taxonomy failure coverage for well-formed invalid evidence,
  plus explicit raw `DecodingError` behavior for malformed JSON and test-
  consumer normalization to `invalidEncodedClassification` with no descriptor.

The recommended domain surface is deliberately small:

- `TransactionTypeChoiceDescriptor` — canonical type and owner enums, their
  exact titles and existing `TransactionEconomicMeaning`;
- `TransactionTypeChoiceCatalog.membership(for:)` — literal unordered set; and
- `TransactionTypeChoicePresentationProjector.descriptor(for:)` — total,
  nonthrowing projection over one valid classification.

The descriptor is not Codable. A restart encodes and decodes the already
verified classification, then re-derives presentation. Unknown forward keys
remain governed by the existing decoder; tests require exact emitted keys and
do not invent unknown-key rejection.

## Open Decisions and Exclusions

O-002, O-011–O-015 and O-028–O-032 remain outside because the leaf contains no
amount, source, custody, posting, receipt, correction, legacy mapping or command
behavior. A-003/A-004/A-015/A-016 and all provider, identity, synchronization,
hosted-resource and migration gates also remain outside.

The slice contains no Transaction ID, amount/sign/currency/date/vendor/source,
category, Item count, receipt, readiness/lifecycle/status, badge/color/action,
search/filter ordering, pagination, visibility, Transfer route, Invoice, Space,
budget, correction, app/MCP wiring, schema, handler, grant, RLS, Sync Stream,
persistence, provider adapter, legacy decoding, migration, release or
production behavior.

## Ready Verification

The two target paths contain comments only. The complete ready gate must pass:

- conversion sync/check/report with no structural error;
- current capability/query/residual controls and M0;
- every existing target test and generated target contract;
- repeatable XcodeGen output and both staging builds;
- clean diff formatting; and
- an untouched Firebase source checkout.

Immutable CI on the exact ready commit is mandatory before any isolated worker
may begin. Passing the ready gate proves only that the frozen authority,
coverage and isolation are coherent; it does not prove the planned
presentation behavior.

Original exact ready commit `5e79d83d672b44f320ebe686222e55f8158a8fdf`
passed immutable Actions run `33706147469`. After the prior disjoint Project
slice was verified, exact assignment base
`8cf4bec690345eacfe77b954d8deddabda0ec128` passed immutable run
`33707620621` with all 218 then-existing tests, generated contracts, both
staging builds and clean tracked artifacts. Isolated branch/worktree
`codex/supabase-slice-transaction-type-choice` /
`/Users/benjaminmackenzie/Dev/ledger_mobile_supabase_transaction_type_choice`
exists at that exact base. `SUBAGENT-WORK-007` owns only the two named target
paths. Assignment-control commit
`49289922cbfcc345c223d7589064df3519268349` passed immutable CI run
`33707949029`; the worker may now write only those two paths.

## Permanent Limits

Implemented status proves no offline physical durability,
authorization, database policy, synchronization, migration reconciliation,
app/MCP behavior, hosted resource, production behavior, release or cutover.

## Implementation Review

`SUBAGENT-WORK-007` produced candidates `0170ac0a`, `f38258a5` and final
`c22fac22` from exact base `8cf4bec6`; every candidate changed only the two
registered paths. Primary every-line review found no implementation defect.
Independent review rejected the first candidate for one P3 test-obligation gap:
well-formed invalid aggregate shapes did not exercise syntactically malformed
JSON. The next correction was too ambiguous because a helper normalized the raw
parser failure as though the codec emitted a taxonomy failure. Final correction
`c22fac22` directly proves raw `DecodingError`, explicitly not
`TransactionTaxonomyFailure`, and separately proves the test-only consumer
normalizes it to rejected `invalidEncodedClassification` without a descriptor.
Replacement independent final review found no code P0-P3 issue and required the
matching dossier correction above. Worker/root focused runs pass all six tests;
the complete central gate passes all 224 tests in 50 suites, conversion/M0 and
target isolation/generated-contract controls, two identical generated-project
hashes, both staging builds and clean artifacts. Exact integration commit
`fcff5b854b16d289dfcf159b31fcd45a973c7402` passed immutable
Actions run `33717396519`: conversion traceability passed in 14 seconds and the
isolated target job passed in 3 minutes 8 seconds with all 224 tests, generated
contracts, repeatable project generation, both staging builds and clean tracked
artifacts. The slice is verified.
