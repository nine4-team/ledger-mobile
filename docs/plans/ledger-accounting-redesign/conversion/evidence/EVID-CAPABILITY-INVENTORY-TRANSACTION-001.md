# EVID-CAPABILITY-INVENTORY-TRANSACTION-001 — Inventory Provenance, Transactions, Receipts, and Corrections

- Timestamp: 2026-08-31
- Class: static source/spec characterization and capability synthesis
- Repository baseline: `d83c64724fe4e92be27c62f425979bd30fcfc9bb`
  on `dev`; shared worktree was already dirty
- Production reads or mutations: none
- Target implementation/schema/RLS/Sync Stream changes: none
- Operator: Codex
- Primary artifact:
  `capability-dossiers/inventory-provenance-transactions-receipts-and-corrections.md`

## Sources Reviewed

- Full Swift Inventory operations, Transaction service/protocol, LineageEdge
  model/service and Transaction model/type/status definitions;
- New Transaction, Transaction detail/list/card/filter/edit/menu/audit,
  add-existing, Return picker, Inventory lists/context and sell/reassign UI
  call sites;
- MCP Transaction, inventory-operation, purchase-intent, lineage,
  whole-Transaction correction and deletion-preflight modules and granular
  tools;
- current Transaction/Item/lineage rules, derived Functions, query catalog and
  backend-contract characterization;
- Swift and MCP tests for movement/origin/price basis, atomic execution,
  return-to-project provenance, Transaction CRUD/display/validation,
  correction safety, deletion/tombstones and type normalization;
- canonical accounting, Item lifecycle, Client/Transfer, receipt-line,
  correction, inventory-store, lineage, add-existing and current Transaction
  specs; and
- migration/audit/repair scripts and source-profile plans that expose legacy
  type, relationship, completeness and provenance variants.

## Method and Result

Static source behavior and caller outcomes were reconciled against confirmed
D-001–D-027 product authority and every existing open decision. The review
split current combined operations into real money, physical placement, open
billing/credit, Transfer and correction stories; defined a target-neutral
offline history/readiness contract; specified migration/reconciliation rules;
and identified the source surfaces to classify in
`M0-INVENTORY-TRANSACTION-001`.

The review corrected one material spec conflict: the proposed fourth Vendor
Credit Transaction type is superseded for the redesign by D-001/D-007. Actual
vendor money returned is a scope-relative Return. O-028 now tracks vendor
cancellation/account credit when no money was received. O-029–O-032 capture
previously untracked Transaction lifecycle, receipt rounding/tax-basis and
canonical minimum-evidence decisions.

## Material Findings

- Current Inventory-to-Project and return-to-source operations create Project
  Purchases without Client money. Target placement creates an open Item charge
  and occurrence, not a Project Transaction.
- Current Project-to-Inventory movement can create a Return based on physical
  origin even when no Client refund occurred. Target uncollected removal, paid
  credit and actual cash refund are separate stories.
- Current same-Client Project movement always uses a two-hop Inventory
  Purchase/Return/Sale chain. The approved target uses one direct paired
  Transfer and never temporarily assigns Business Inventory.
- Current project-origin acquisition writes a project Sale, a retired target
  type. Target must represent the actual Inventory-side acquisition, placement
  and project demand/credit effects without inventing cash.
- Current origin is inferred from mutable Transaction membership, lineage,
  source-label suffixes and optional inventory snapshots. Useful fail-closed
  paths exist, but no one authoritative occurrence chain explains every cycle.
- Current LineageEdge fields are loose/optional and created by multiple app,
  MCP and Function writers. Auto IDs, optional timestamps, silent decode drops
  and no uniqueness/correlation contract make completeness unprovable.
- Current Transaction creation permits a type-only canonical record; the target
  needs a posted-versus-draft boundary before canonical accounting and import
  can be mapped safely.
- Accepted receipt-line direction replaces subtotal/tax/discount percentage
  completeness with physical Items plus stable signed non-item lines against
  final cents. One-cent rounding and Item tax-basis behavior were not yet in
  the central decision log.
- Generic Transaction edits cascade scope/category to Items, while the app edit
  form writes field names that do not match normal Codable persistence keys.
- iOS and MCP deletion/cancellation safety differ materially. MCP deletion's
  dependency preflight, serializable recheck, exact confirmation and immutable
  tombstone are useful safety outcomes, not approval of target hard deletion.
- Inventory lineage is currently fetched on demand. The target core Inventory
  and Project streams must contain enough immutable occurrence/provenance
  evidence to explain every current Item offline, with explicit readiness for
  extended history.

## Limitations

Production Transaction type/status/field distributions, missing amounts,
lineage duplicates/orphans/cycles, `itemIds` disagreement, inventory-entry
snapshot coverage, deleted/tombstoned records, receipt reconstruction, source
label variants and actual query/index behavior remain unconfirmed until the
fail-closed read-only production profile runs. Final target mapping depends on
O-002–O-015, O-023, O-028–O-032 and the Supabase/PowerSync vertical spike.

This evidence supports target-independent command, read-model, security,
offline, migration and test design only. It does not authorize Postgres DDL,
Supabase RLS/RPCs, PowerSync Streams, Firebase refactoring/adapters,
production reads/mutations, migration or cutover.
