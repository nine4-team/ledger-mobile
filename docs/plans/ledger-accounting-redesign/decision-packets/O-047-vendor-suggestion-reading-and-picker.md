# Decision Packet — O-047 Vendor-Suggestion Reading and Picker Behavior

Status: proposed recommendation; product decision not yet approved  
Last reviewed: 2026-09-06  
Owners: Item/Transaction/Expense entry, Shared Reference Data, Account Security

## Decision Requested

Approve or replace one explicit product contract for vendor-suggestion reads and
selection:

> Every active Account member who may edit an owning record can read the
> Account's active vendor suggestions. Archived suggestions are not offered for
> new selection; they remain resolvable only where historical or selected-value
> evidence requires them. The picker never requires a suggestion: users may
> enter arbitrary valid free text without silently adding it to the shared list.
> Incomplete or stale local data is labeled honestly and never becomes an
> authoritative empty list. Selection is bound to stable suggestion identity and
> clears if that row is no longer active or represented.

This proposal is not product authority and authorizes no implementation until
the decision log records approval.

## Why This Decision Is Separate from O-026

O-026 owns shared-reference administration and mutation capabilities. It does
not currently decide which members may download vendor suggestions, whether the
whole archived catalog is broadly synchronized, or whether the redesigned form
preserves an explicit Other/free-text path. Those choices affect privacy,
offline completeness, local retention, picker behavior, RLS, and Sync Streams
even in a read-only implementation.

## Options

### Option A — Broad Account catalog, including archived rows

Every active member downloads all active and archived suggestions. This is
simple and supports offline historical resolution, but may retain more old
counterparty text than a member's current work requires.

### Option B — Active catalog plus contextual historical resolution (recommended)

Authorized editors download the active selection catalog. Archived identities
are fetched/synchronized only when an authorized owning record references them
or when an explicit history view needs them. This minimizes disclosure while
preserving history.

### Option C — Suggestions-only picker

Require selection from the shared catalog and remove arbitrary free text. Reject:
vendor/source evidence is intentionally record-owned text, and a shared
suggestion must not become mandatory Vendor identity.

## Required Target Contract

- Read eligibility derives from trusted active membership plus the owning-form
  capability, never caller parameters or user-editable JWT metadata.
- Active selection rows have stable identity, exact Account scope, preserved
  display text, normalized comparison evidence, deterministic order, lifecycle,
  and revision.
- Free-text entry remains independent of shared-list mutation. Entering a new
  value does not implicitly call `SuggestVendor` unless that separate behavior is
  approved under O-026.
- Waiting, partial, stale, ready, authoritative-empty, and bounded failure remain
  distinguishable. A cached row may remain useful offline without claiming a
  complete catalog.
- Stable-ID selection resolves against the current represented active snapshot.
  Archive/removal/scope loss clears the identity selection but never erases an
  already-captured owning-record text snapshot.
- Fixed defaults, excluded suggestions, automatic seeding, and whether current
  typed text is offered as a new suggestion remain outside unless explicitly
  approved.

## Required Acceptance Evidence

- Owner, admin, eligible employee, ineligible employee, revoked, unmapped,
  ambiguous, expired-token, user-metadata-spoof, forged-Account, and cross-Account
  read/Sync cases;
- active versus archived catalog disclosure under the selected option;
- incomplete, stale, ready, authoritative-empty, and restart behavior;
- selection clearing on archive/removal/replacement without loss of captured
  source text;
- free-text entry with zero shared-list mutation and no Vendor/accounting
  identity manufacture; and
- app and MCP parity wherever an equivalent source-entry workflow exists.

## Unblocking Sequence

1. Record the selected behavior as confirmed product authority.
2. Reconcile it with O-026's writer/capability matrix.
3. Update the vendor-suggestion provider/picker dossier, RLS/Sync matrix, and
   migration retention rules.
4. Repeat independent READY review before adding executable SQL, provider, or
   application behavior.
