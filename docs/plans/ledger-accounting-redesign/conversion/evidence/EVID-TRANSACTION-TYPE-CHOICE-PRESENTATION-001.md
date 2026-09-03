# EVID-TRANSACTION-TYPE-CHOICE-PRESENTATION-001 — Transaction Type Choice Presentation

- Timestamp: 2026-09-02
- Class: ready gate / provider-free Transaction type-choice presentation
- Source baseline: `fe018501d67cc84b6f140b2645b8a8149ea5c4f6` on
  `firebase`; the source worktree and released Firebase app remain unchanged
- Claimed target surfaces: `SWIFT-F90B7B48C1F6`, `TEST-F66BBF1FC092`
- Slice dossier:
  `conversion/implementation-slices/transaction-type-choice-presentation-contracts.json`
- Verification state: ready only; executable implementation and tests are absent
- Ready scaffold hashes:
  - `TransactionTypeChoicePresentation.swift`:
    `ec01c3543c3c407f26d9a1fb6a5c1d716edd089e174d8757b1113ed6d814d629`
  - `TransactionTypeChoicePresentationTests.swift`:
    `448ec87f3d2d231fe69631e981d8403840790a1eb618cabfd328a713699f49e6`

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
- exact existing taxonomy failure coverage for malformed or invalid evidence.

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

## Permanent Limits

Ready status proves no executable presentation, offline physical durability,
authorization, database policy, synchronization, migration reconciliation,
app/MCP behavior, hosted resource, production behavior, release or cutover.
