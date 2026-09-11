# Decision Packet — O-002/O-011–O-014 Transfer Edge Policy

Status: proposed recommendation; product decision not yet approved
Last reviewed: 2026-08-31
Owners: Transfer, Invoicing, Item Placement, Tags, Credits, Corrections
Unlocks: 6 unique residual surfaces (O-002: 4; O-011/O-012/O-013/O-014: 6 each)
Residual register: [generated M2 queue](../conversion/residual-decision-register.generated.md)

## Decision Requested

Approve or reject these five coordinated rules for a same-Client direct Transfer:

1. A Transfer may remove an Item's open source from a sent-but-unpaid source
   Invoice atomically. That creates a new Invoice revision and blocks collection
   until the revised Invoice is delivered/attested under O-034; the user does not
   need a separate pre-recall step.
2. **Additional Requests** is Project-contextual and clears by default. Transfer
   may explicitly reselect it for the destination; it never carries silently.
3. Destination Space is optional per Item in the Transfer command. The default is
   no Space; every supplied Space must be active in the destination Project and
   validated atomically.
4. Completed Transfers are never deleted or edited. A dependency-safe
   `ReverseTransfer` appends a new paired reversal and moves the exact Items back.
   If later immutable/dependent activity makes that impossible, use a new forward
   Transfer or a separately approved administrative correction—not partial
   deletion of the original pair.
5. A later paid-Item Client credit belongs to the Item's current Project. Its
   amount/category basis is traced through the Transfer chain to the original
   frozen paid line. This reduces the Project that currently carries the Client's
   reallocated value while preserving the original paid history.

These rules do not change the confirmed same-Client-only, direct placement,
paired-record, no-cash and Client-wide-net-zero Transfer model.

## Confirmed Constraints

- Source and destination Projects share the exact non-null `client_id`; names do
  not authorize.
- Transfer never passes through Business Inventory and never creates a Purchase,
  Return, sale, charge, credit, Invoice payment or refund merely because of the
  move.
- One operation creates exactly one source/destination pair and all selected Item
  effects or nothing.
- Open demand moves to destination under the same economic identity; paid value
  is reallocated with equal/opposite paired paid contributions.
- Current physical placement changes while acquisition/paid history remains.
- Project Space and Additional Requests are contextual, not Client ownership or
  accounting identity.
- App and MCP call one trusted idempotent command.

## Coordinated Options

| Decision | Alternatives | Recommendation |
|---|---|---|
| O-002 sent Invoice | require separate recall; mutate silently; remove atomically and require a delivered revision | Atomic removal plus revise/resend; never silent |
| O-011 Additional Requests | always carry; always clear; clear by default with explicit destination reselect | Clear by default, permit explicit reselect |
| O-012 destination Space | always none; require a Space; optional validated per-Item/bulk assignment | Optional, default none |
| O-013 completed correction | edit/delete original pair; append reversal when dependency-safe; only forward movement | Append paired reversal when safe, otherwise a new forward/correction story |
| O-014 later paid credit | original Project; current Project; Client-wide unassigned pool | Current Project with original frozen basis traced through Transfer chain |

These choices are mutually exclusive within each row. Approving the packet
approves the recommendation column as one coordinated contract; reviewers may
approve individual rows only if they explicitly reopen all dependent tests and
schema consequences.

## O-002 — Sent Invoice Membership

### O-002 Detail

- **Require recall/removal first:** simple Transfer handler, but forces a separate
  online-sensitive workflow and adds a race between recall and Transfer.
- **Allow silent mutation:** rejected; Client may retain a delivered version that
  no longer matches collectible content.
- **Atomic Transfer plus revision required (recommended):** remove the source in
  the Transfer transaction, preserve prior delivered revision, advance working
  revision and require revised delivery before collection.

The Transfer confirmation shows affected Invoice number/revision, removed line/
amount and “Revised Invoice must be resent.” The server result returns the new
revision/delivery-required state. A failed/rejected Transfer changes neither
Invoice nor Item.

The moved open occurrence becomes available in the destination Project's
Invoicing queue; it is not automatically inserted into a destination Invoice.

## O-011 — Additional Requests Tag

Additional Requests represents Project-specific request/report context. It is
not physical Item identity and not the Furnishings accounting category.

- Transfer clears the source Project tag in current destination context.
- The command may include `destinationAdditionalRequest = true` per Item or as
  an explicit bulk choice.
- Omitted means false/cleared, never “copy current.”
- Source historical report/Invoice snapshots retain their tag state/as-of
  evidence where relevant.
- Tag choice adds no contribution and cannot change amount/category basis.

## O-012 — Destination Space

- Default destination Space is `none`.
- The confirmation may assign one destination Space to all eligible Items or
  choose per Item.
- Every Space is identified by stable ID, belongs to destination Project, is
  active, visible to the actor and matches expected revision.
- Partial/stale Space readiness disables selection or submits `none`; client-
  supplied name/ID cannot bypass server validation.
- Source current Space assignment closes as part of placement movement. Historical
  placement retains source Space evidence.
- All space assignments and Item moves commit atomically with Transfer pair.

## O-013 — Reversal and Correction

### Simple dependency-safe reversal

`ReverseTransfer` is available when every selected original Transfer Item:

- is still in the original destination Project under the same Client;
- has not participated in a later Transfer/cross-Client movement;
- has no conflicting pending placement/Invoice/credit operation;
- has an open-demand state that can move back atomically, or a paid allocation
  whose current reallocation basis can be reversed without rewriting frozen
  source history; and
- matches the exact dependency plan/revisions.

The operation appends one reversal aggregate plus source/destination paired
entries linked to the original, moves current placement back, moves open demand
or appends equal/opposite paid reallocations, applies explicit destination tag/
Space defaults for the returning Project, and preserves both original records.

### When simple reversal is unsafe

If an Item was resold, transferred again, collected under changed source state,
credited/refunded, moved across Client ownership, or otherwise has immutable
downstream dependencies, the original cannot be “undone.” The system returns an
exact dependency explanation and offers only:

- a new current-state `TransferItems` action where still same-Client/legal; or
- a separately authorized accounting/placement correction plan that appends all
  required evidence.

Neither Transfer half has an independent cancel/delete/status patch. A preview
plan is explanatory; execution re-locks/revalidates everything.

## O-014 — Credit After One or More Transfers

When a paid Item is removed and creates Client credit:

- owning Project is the Item's current Project at credit creation;
- amount/sign/category originate from the exact frozen paid Item line;
- Transfer chain proves how that paid allocation reached the current Project;
- credit occurrence/ClientCredit references original paid line plus intervening
  Transfer entry chain/current placement;
- current Project gets the open negative contribution; original paid Project
  history remains frozen with Transfer reallocation evidence; and
- Client-wide accounting remains correct under any later approved credit
  application/cash refund.

If provenance cannot prove one unbroken same-Client chain and exact basis, credit
creation blocks/quarantines rather than choosing the oldest/recent Project by
timestamp or text.

## Conceptual Target Shape

The O-007/O-015 packet's Transfer aggregate/paired entries remain authority,
augmented conceptually by:

| Family | Responsibility |
|---|---|
| Transfer Item lines | Exact Item, paid/open mode, amount/category/occurrence basis, source/destination Space/tag choices |
| Invoice revision cause | Transfer operation/item/source IDs and delivery-required result |
| Transfer reversal correlation | Original/reversal aggregate and exact paired entries |
| placement/tag history | Source closed and destination opened context, independent from accounting identity |
| credit provenance chain | Current Project, original paid line and ordered Transfer-entry correlations |
| operation/results | Idempotency, payload/dependency-plan hash, expected revisions and durable outcomes |

Use stable client-generated IDs, `bigint` cents, explicit roles/modes, foreign
keys and checks for pair cardinality/same Client/distinct Projects. Index every
foreign key/RLS key, Transfer by Project/time, Item chain, original/reversal,
Invoice cause and credit provenance. Lock Items and related rows in stable ID
order; use keyset history cursors.

## Atomicity and Locking

Transfer/reversal locks:

1. operation and Transfer/original rows;
2. source/destination Project/Client and affected Invoice headers/revisions;
3. Items in stable ID order;
4. current placements/Spaces/tags/open occurrences/source links/paid allocations;
5. Transfer entries/provenance/contributions; and
6. events/projections/results.

It revalidates same Account/Client, active Projects, exact source placement,
Invoice/source revisions, destination Spaces, tag input, paid/open basis and all
dependencies before writing every effect atomically. No render/delivery/media/
external call occurs while locks are held; revised Invoice delivery uses its
outbox after commit.

Concurrent Invoice collection/edit, Transfer/Transfer, Transfer/reversal, Item
return/credit, Space archive, Client correction and price edit serialize or
return a typed conflict with no half-pair/partial movement.

## Authorization, RLS, Sync, and Offline

- Active membership plus source/destination Project, Transfer and financial
  capabilities are required. Same-Client relationship is re-read from trusted
  rows. Payload names/IDs/role do not grant access.
- Financially restricted users may see authorized physical placement while paid/
  open amounts, Invoice effects, credit provenance, counts and operation details
  remain protected.
- Direct writes to placements, Transfer pairs, Invoice membership/revisions,
  paid reallocations, credit chains and reversal evidence are revoked. App/MCP
  call the same handlers.
- Source/destination Project streams include authorized pair summaries,
  placements, open source move, Invoice revision requirement, paid reallocation,
  operation result and history readiness needed offline.
- Offline submission is durable. Optimistic UI may show a pending move plan, but
  cannot claim Invoice revision delivered, paired records accepted, budgets
  final or credit provenance complete before server result.

## Migration and Reconciliation

Existing Firebase movement/lineage/Sale/Return chains are source evidence, not
automatic target Transfer. Map a historical event to same-Client Transfer only
when authoritative target Client resolution, direct source/destination Item
chain, no cash, exact basis and paired effects are proven. Otherwise map to the
appropriate movement/credit/purchase/return facts or quarantine.

Preserve source/destination Space/tag, Invoice membership/snapshots, paid/open
basis, corrections and later return/credit evidence. Generate deterministic
pair/reversal/chain IDs and record source correlation. Never infer same Client
from matching text or delete an original movement after finding a later reverse.

Reconcile pair cardinality, Client/Project IDs, Item current placement, Space/tag
context, open occurrence movement, Invoice revision/delivery requirement, paid
equal/opposite contributions, reversal chain, later credit Project/basis and
Client-wide net zero.

## Required Acceptance Tests

- sent source Invoice Transfer advances revision/removes exact source atomically,
  preserves prior delivered version and blocks collection until resend;
- default tag clears, explicit destination tag applies, and neither changes
  Furnishings/category/amount;
- default Space clears, valid per-Item destination assignment succeeds, and
  archived/cross-Project/stale Space fails all-or-nothing;
- simple reversal appends one exact pair/equal-opposite effects and preserves
  original; independent half cancel/delete/direct patch fails;
- later immutable dependency blocks reversal with exact reason and no partial
  movement;
- multi-Transfer paid Item credit belongs to current Project and traces exact
  frozen basis through the complete chain;
- ambiguous/broken/cross-Client chain blocks credit rather than guessing;
- mixed paid/open bulk Transfer remains Client-wide net zero;
- concurrency and retry never create duplicate/half pairs or double contribution;
- cross-account/name-match/restricted financial attempts fail without leakage;
- offline submission/restart/reconnect converges with explicit Invoice/history
  readiness; and
- migration fixtures distinguish real same-Client no-cash Transfer from legacy
  sale/return/cash/cross-Client movement deterministically.

## Approval Consequences

If approved:

1. update canonical Transfer/Invoice/Item/Space/credit specs and record confirmed
   decisions;
2. promote these edge rules into architecture 02/03/04/05/06/07/08 and the
   O-007/O-015 relationship packet;
3. remap the six affected surfaces while retaining O-007/O-015/O-023/O-025/O-034
   and other independent blockers;
4. specify reviewed constraints/indexes, RLS/Sync profiles, lock graph, command
   schemas and migration fixtures; and
5. include sent-Invoice, tag/Space, reversal, multi-Transfer credit and conflict
   cases in the target spike.

## Approval Checklist

- [ ] Transfer can revise a sent Invoice atomically but requires resend before
  collection.
- [ ] Additional Requests clears by default and is explicitly reselected.
- [ ] Destination Space defaults none but can be explicitly assigned/validated
  per Item atomically.
- [ ] Reversal appends a paired reversal and never deletes/edits original halves.
- [ ] Unsafe downstream dependencies require forward action or typed correction.
- [ ] Later paid-Item credit belongs to current Project and traces original frozen
  basis through the Transfer chain.
