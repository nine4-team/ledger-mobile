# Decision Packet — O-051 Rejected Offline-Operation Recovery

Status: proposed recommendation; product decision not yet approved  
Last reviewed: 2026-09-07  
Owners: Offline Operations, Account Session Ending, Product UI, Audit

## Decision Requested

Choose when a terminally rejected offline operation stops counting as unresolved
work, how a corrective retry is linked to it, and whether the user may explicitly
acknowledge that they will not retry while Ledger retains the complete rejection
evidence.

This packet is not product authority. Until the choice is approved, Ledger may
recover and show an exact rejected command from its encrypted local journal, but
must not mark it resolved, dismiss it durably, delete it, or imply that editor
Cancel abandons an already accepted operation.

## Constraints That Are Already Authoritative

- Durable local acceptance means the operation and its exact intent survive
  process and device restart until an explicit terminal outcome is handled.
- A terminal rejection remains visible and blocks ordinary logout while its
  recovery is unresolved.
- Destructive Account removal is a separately confirmed, exact-confirmation path
  that may discard local pending work; it is not a normal feature-level action.
- Closing a recovery view, navigating away, or canceling edits performs no
  operation and cannot erase the original rejected payload or rejection.
- Original command, result and rejection evidence is immutable audit data.

## Options

### Option A — Transfer responsibility at durable local acceptance (recommended)

When Ledger durably accepts exactly one corrective replacement operation, it
atomically records an immutable `replaced_by_operation_id` resolution fact on
the original rejection and transfers unresolved-work responsibility to the new
operation. The original command and rejection stay queryable. If the replacement
rejects, that replacement becomes the actionable rejection. Retry chains remain
acyclic and every step is auditable.

This matches the offline-first promise: once the replacement is durably local,
the user's corrective intent no longer depends on network availability. It also
avoids counting both the original and its replacement as separate unresolved
responsibilities.

### Option B — Transfer responsibility only after authoritative apply

Keep the original rejection unresolved until the replacement is confirmed by
authoritative readback. This is more conservative, but represents one user
responsibility twice while the replacement is queued/applying and can make
logout messaging confusing.

### Option C — No replacement linkage

Treat every retry as unrelated and require separate resolution of the original.
Reject this option: it permits duplicate unresolved counts and loses the causal
answer to “what corrected this rejected change?”

## Separate Acknowledgment Choice

Product must also explicitly choose whether recovery offers **Do Not Retry**.
If approved, it records an immutable resolution event with actor, time and a
bounded reason code while retaining the original command and rejection. It does
not delete data or rewrite the rejection. If not approved, only a successful
responsibility transfer or separately authorized destructive Account removal
can clear the unresolved responsibility.

## Required Target Contract

- Recovery is scoped by environment, Account, Principal, operation family and
  subject identity; foreign, malformed, fingerprint-mismatched or non-rejected
  rows fail closed.
- Review reconstructs the exact canonical command, including stable nested IDs,
  text, checked state and order for checklist replacement.
- The newest actionable rejection is deterministic; older unresolved rejections
  remain discoverable and counted.
- Retry is enabled only with fresh, complete, exact, active-subject evidence and
  accepts one new operation ID. Duplicate taps cannot create duplicates.
- Resolution is append-only or immutable-link evidence. It never mutates the
  original command/rejection bytes and never deletes audit history.
- Ordinary logout counts the active unresolved responsibility exactly once
  through a replacement chain.

## Required Acceptance Evidence

1. Reject, close the encrypted database/runtime, reopen a fresh runtime and
   coordinator, and recover the exact command and rejection.
2. Refuse foreign environment/Account/Principal/subject/contract/fingerprint,
   malformed, non-rejected and already-resolved candidates.
3. Show exact stable identities, values and order in review.
4. Preserve review but disable retry for missing, incomplete, archived,
   mismatched or stale authoritative subject evidence.
5. Admit exactly one revision-bound replacement and prevent duplicate taps.
6. Prove close, Cancel, navigation and app stop send zero operations and recovery
   remains visible after another restart.
7. Prove the approved replacement-resolution point is atomic, restart-safe,
   idempotent and acyclic; a rejected replacement becomes the next actionable
   responsibility.
8. Prove ordinary logout remains blocked until the approved resolution and that
   counts do not double-count one replacement chain.
9. If acknowledgment is approved, prove actor/time/reason audit retention and no
   command/result/rejection deletion. If it is not approved, prove no such
   feature-level control exists.

## Approval Checklist

- [ ] Choose Option A, B, or a replacement contract with equally explicit
      durability and counting semantics.
- [ ] Approve or reject the evidence-retaining **Do Not Retry** acknowledgment.
- [ ] Record the choice as confirmed product authority and update the offline and
      session-ending specs.
- [ ] Update operation-journal schema/ports, pending-work counting, UI language,
      app/MCP parity where applicable, and migration/reconciliation rules.
- [ ] Re-run independent design review before implementing resolution writes.
