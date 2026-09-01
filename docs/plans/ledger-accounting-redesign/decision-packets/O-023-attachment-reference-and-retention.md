# Decision Packet — O-023 Attachment Reference and Retention

Status: proposed recommendation; product decision not yet approved
Last reviewed: 2026-08-31
Owners: Attachments, Offline Durability, Financial Evidence, Storage, Migration
Unlocks: 22 residual surfaces; five still require the canonical production
reference/object profile after this product decision closes
Residual register: [generated M2 queue](../conversion/residual-decision-register.generated.md)

## Decision Requested

Approve or reject this policy:

> Removing an attachment from a parent removes or supersedes that typed
> reference; it never immediately deletes object bytes. A trusted retention
> worker may physically purge an original and its derivatives only after the
> authoritative reference graph has no live references or holds, a recoverable
> 30-day quarantine has elapsed, and a final transactional eligibility check
> succeeds. Financial, audit, migration, and delivered-artifact evidence remains
> held for the life of its retained parent/evidence policy. The ordinary app and
> MCP expose no immediate permanent-delete command for uploaded bytes.

Locally captured bytes that never uploaded may be explicitly discarded sooner,
but only after durable confirmation that no parent reference, pending operation,
retry, or export depends on them.

This packet is a proposed product/architecture contract. It is not legal-
retention advice, DDL, bucket-policy implementation, provider approval,
production profiling/migration authorization, or permission to delete Firebase
objects.

## Confirmed Constraints

- Offline capture is successful only after protected local bytes and metadata
  are durable. Pending media must survive process death and reconnect.
- Attachment identity is stable and independent of URL, object path, filename,
  derivative, or signed access token.
- One original may be referenced by multiple parents, including Item reuse of a
  Transaction image and Space review-note visual snapshots.
- Posted Transactions, collected Invoices, corrections, reports and provenance
  may rely on attachment evidence after it disappears from an editable gallery.
- Structured sync carries attachment metadata/references, not raw media bytes or
  long-lived bearer URLs.
- App and MCP must use the same lifecycle. Current Item detach/delete and Space/
  Transaction immediate-delete divergence is not target behavior.
- The production Firebase reference/object graph is not yet proven. Migration
  must profile shared, dangling, missing, orphaned, external and derivative
  variants before making purge decisions.

## Options

### Option A — Delete bytes when a UI reference is removed

Recommendation: reject. A client cannot prove that no other parent, immutable
financial record, device operation, migration row, or derivative depends on the
same original. Best-effort object deletion also creates irreconcilable partial
states.

### Option B — Detach, hold, quarantine, trusted purge (recommended)

Use stable typed references. Editable parents detach reversibly. Immutable
evidence supersedes rather than erases. A worker purges only zero-reference,
zero-hold objects after a quarantine and final recheck.

Recommendation: approve. This preserves user intent while preventing accidental
loss and creates an observable cleanup path instead of indefinite orphan growth.

### Option C — Never delete uploaded objects

Recommendation: reject as the default. It is safe against accidental loss but
creates unbounded storage/privacy liabilities and gives account removal no
principled completion path. Retention holds should be explicit, not accidental.

## Reference Lifecycle

An Attachment and its parent reference have independent lifecycles.

```text
local capture -> pending upload -> verified original -> active references
      |                 |                    |
 explicit discard      |                    +--detach/supersede reference
 (only if unreferenced) |                                  |
                        +--retry/reject                     v
                                               zero live refs + zero holds
                                                            |
                                                  30-day quarantine
                                                            |
                                                   final eligibility check
                                                            |
                                                       physical purge
```

### Mutable parent reference

For a draft or otherwise editable parent, `RemoveAttachmentReference`:

- verifies the exact parent/reference revision and caller capability;
- marks the reference detached with actor, reason and time;
- repairs stable ordering and exact-one-primary in the same transaction;
- creates or refreshes a deletion candidate only if the Attachment now has zero
  live references and zero retention holds; and
- returns a durable result. It never calls object deletion inline.

Detachment is recoverable during the quarantine through
`RestoreAttachmentReference` if the parent remains mutable and authorized.

### Immutable or retained evidence

For a posted Transaction, collected Invoice, correction, migration receipt,
delivered report, audit event, or other retained evidence:

- ordinary detach is rejected;
- the owning typed correction command may supersede the presentation reference;
- the original reference remains retained and auditable, with the replacement
  correlation where applicable; and
- the Attachment carries a retention hold as long as the parent/evidence policy
  requires it.

The UI may stop showing superseded evidence in the default gallery without
claiming the bytes or historical relationship were deleted.

### Explicit local discard

`DiscardLocalAttachmentCapture` is allowed only when the Attachment has never
produced a verified server object and a trusted local transaction proves:

- zero active parent references, or the one draft reference is being discarded
  atomically with the parent/draft;
- no pending post/upload/retry/export operation;
- no shared local-byte reference; and
- exact user confirmation for the identified capture.

If any check fails, discard rejects with a stable dependency reason. Logout,
account switching, revocation, key rotation, storage pressure, or a missing
parent does not silently substitute for explicit discard.

## Purge Eligibility and Quarantine

An uploaded original becomes a deletion candidate only when all are true:

1. its upload is verified and it is not in an ambiguous/missing/corrupt state;
2. no active or retained `attachment_reference` exists;
3. no financial, audit, migration, legal/account, export, pending-operation or
   rollback hold exists;
4. no copy/reconciliation/import operation is in progress;
5. the last reference removal/result is durably accepted; and
6. the owning Account/environment is known and matches the object locator.

The recommended quarantine is 30 full days from the latest eligibility event.
Any new reference/hold cancels the candidate and restarts eligibility from
scratch. The worker must run a final database transaction that locks the
Attachment/candidate, rechecks reference and hold counts, and records an
idempotent purge lease before deleting external objects.

Object deletion is an external side effect and cannot be atomic with Postgres.
Use an outbox/state machine:

```text
eligible -> leased -> original delete attempted -> derivatives delete attempted
         -> verified absent -> purged
         -> retryable failure / permanent-review failure
```

The metadata/evidence row remains as a non-secret purge receipt containing
Attachment ID, safe locator hash, sizes/checksums, actor/system reason,
eligibility/lease/purge times, attempts and result. Never persist signed URLs.

Account deletion and statutory/legal retention require a separate approved
account-retention policy. They may shorten or extend the 30-day operational
quarantine only through an explicit higher-authority workflow; ordinary parent
detach cannot.

## Conceptual Target Shape

| Family | Responsibility |
|---|---|
| `attachments` | Stable original identity, Account/environment, safe object locator, verified size/checksum/type, upload and purge state |
| `attachment_references` | Typed parent ID/kind, role, order, primary, active/superseded/detached state, revision and audit |
| `attachment_retention_holds` | Typed parent/evidence/policy hold with creation/release authority and reason |
| `attachment_derivatives` | Rebuildable versioned derivative status/locator; never canonical identity |
| `attachment_deletion_candidates` | Eligibility time, quarantine deadline, lease, attempts and terminal result |
| local attachment receipts | Protected bytes, checksum, parent/principal/environment, progress and pending/rejected/applied result |
| operation/results | Idempotent attach/detach/restore/discard/purge coordination |

Core relationships use foreign keys and indexed stable IDs, not URL scans or
polymorphic JSON. If parent diversity requires a registry, every allowed parent
kind is enumerated and enforced by trusted commands plus reconciliation; an
arbitrary client-supplied table/ID pair is prohibited.

Indexes include every foreign key and policy key, live references by
`(account_id, attachment_id)` and parent/order, active holds by Attachment,
eligible candidates by `(state, quarantine_until, id)`, and pending local/server
operations by Account/age. Partial indexes cover live references, active holds,
and purge-ready candidates. Validate plans with production-scale staging.

## Commands and Queries

| Contract | Effect |
|---|---|
| `CaptureAttachment` | Atomically persist protected local bytes/metadata/receipt before success |
| `AttachVerifiedObject` | Authorize parent, verify object evidence, create one stable reference and normalize primary/order |
| `RemoveAttachmentReference` | Reversible reference detach for mutable parents; no inline object deletion |
| `RestoreAttachmentReference` | Restore an eligible detached reference during quarantine |
| typed parent correction | Supersede/replace retained evidence without erasing history |
| `DiscardLocalAttachmentCapture` | Explicitly remove never-uploaded, dependency-free local bytes |
| retention worker | Lease, purge and verify only eligible zero-reference/zero-hold objects |
| `AttachmentDisplaySource` | Resolve authorized local/cached/remote display without exposing durable token URL identity |
| retention status query | Explain live references, holds, quarantine and purge result without leaking protected parent details |

Only the retention worker can delete uploaded Storage objects. App and MCP
roles cannot call bucket delete directly.

## Authorization, RLS, and Storage

- RLS authorization derives from trusted Account membership, parent access and
  attachment role. A payload Account/parent/path never grants access.
- Financially restricted members cannot infer protected attachment existence,
  filename, size, reference count, hold reason, signed URL, or operation result.
- Direct table writes to verified object locators, holds, purge state and audit
  are revoked. Trusted handlers own transitions.
- Private Storage policies bind the immutable Account/Attachment locator and
  permitted operation. Upload and read are separately authorized; client delete
  is denied.
- Signed display access is short-lived, scoped, never structured-sync data, and
  never logged. Cache/local-byte access follows the current Principal and
  approved offline lease.
- Remote ingestion enforces scheme, DNS/address, redirect, timeout, streamed
  size, sniffed type, filename/path and decompression/image-resource limits
  before the verified object can be attached.
- Worker credentials are server-only and least privilege. Every purge retains a
  safe audit receipt and is reconciled against Storage absence.

## Offline and Failure Behavior

- Attach/detach/restore are durable local operations with stable IDs. Pending
  detach may hide a mutable reference optimistically, but rejected/conflicted
  operations restore authoritative presentation and explain why.
- Removing the last local reference does not erase local bytes while its detach,
  upload, parent post, export, or retry result is unresolved.
- Upload interruption at any byte/object/verification/reference/derivative step
  resumes idempotently and never creates a second canonical Attachment.
- A permanent upload rejection leaves explicit recoverable local evidence until
  the user resolves or discards it.
- Purge failure does not resurrect a reference or claim success. The candidate
  remains retryable/reviewable; verified absence is required for `purged`.
- Account switch and environment switch partition bytes, metadata, cache, keys
  and operations. No pending media can upload/delete under a new Principal.

## Migration and Reconciliation

Before importing objects, build an immutable many-reference-to-one-object graph
from the canonical Firebase export and Storage inventory:

- normalize token HTTPS, `gs://`, external and legacy placeholder references
  without exposing tokens;
- identify original/derivative groups by safe locator plus content hash where
  possible;
- preserve every Account/Project/Item/proto/Space/review-note/Transaction/
  Invoice/report reference with order/primary/role;
- classify shared, copied, orphaned, dangling, missing, corrupt, external and
  ambiguous cases; and
- assign deterministic target Attachment/reference IDs and journal all source
  correlations.

No Firebase object is deleted during rehearsal, initial cutover, rollback, or
the protected evidence window. Imported orphan objects enter migration review,
not the ordinary 30-day purge queue, until source completeness and retention
disposition are approved. Missing originals remain explicit missing evidence;
derivatives do not substitute silently.

Reconcile reference counts, unique object hashes/bytes, parent order/primary,
shared fan-out, retained financial evidence, candidate/hold state, derivatives,
missing/corrupt/external exceptions and source-to-target coverage. Purge jobs
remain disabled until this reconciliation and rollback-retention gate pass.

## Required Acceptance Tests

### Reference and retention semantics

- detach one of multiple references and prove the shared original/derivatives
  remain readable from other authorized parents;
- detach the last mutable reference, restore within quarantine, and prove no
  object delete was attempted;
- new reference/hold racing the purge lease cancels or blocks deletion;
- posted Transaction/collected Invoice evidence rejects ordinary detach and is
  superseded only through the typed correction command;
- primary/order normalize atomically after detach/restore/concurrency;
- local-only explicit discard succeeds only with zero dependencies; and
- ordinary app/MCP/direct Data API/Storage attempts cannot permanently delete
  uploaded bytes.

### Worker and failure behavior

- quarantine is a full 30 days from latest eligibility and restarts after a
  reference/hold transition;
- repeated/parallel worker attempts obtain one lease and one terminal receipt;
- original success plus derivative failure remains retryable until all required
  objects are verified absent;
- crash before/after lease, external delete and database receipt converges to
  one explainable state;
- object-not-found is verified and reconciled idempotently; authorization/
  locator mismatch fails closed to review; and
- safe receipt/log output contains no signed URL, secret, raw private path or
  protected parent data.

### Offline, security, and migration

- capture, display, detach, force-quit, restart, reconnect and conflict preserve
  bytes and correct reference state;
- logout/revocation/account switch cannot silently discard or cross-upload bytes;
- cross-account, restricted-role, guessed-path and stale-token reads/writes/
  counts/deletes fail without existence leakage;
- malicious remote ingestion and filename/path/type/size variants fail within
  bounded resources;
- production-like fixtures cover shared/copy/orphan/dangling/missing/corrupt/
  external/duplicate-primary variants; and
- repeat/interrupted migration produces identical identities, hashes,
  references, holds and explicit exceptions without touching Firebase.

## Approval Consequences

If approved:

1. record the confirmed retention/reference behavior in the decision log and
   canonical attachment/offline/financial specs;
2. promote it into architecture documents 04/05/06/07;
3. map the O-023-dependent residual surfaces, retaining the canonical production
   profile and any parent-lifecycle blocker on each surface;
4. design reviewed RLS/Storage policies, reference/hold/candidate schema,
   operation contracts and synthetic migration fixtures; and
5. prove crash-safe local capture, private access and purge-race behavior in the
   A-003/A-004 vertical spike before enabling implementation.

## Approval Checklist

- [ ] UI removal means detach/supersede reference, never immediate object delete.
- [ ] Uploaded bytes have no ordinary user/MCP permanent-delete command.
- [ ] Last-reference removal starts a recoverable 30-day quarantine.
- [ ] New references/holds cancel purge eligibility.
- [ ] Financial/audit/migration/delivered evidence retains a typed hold.
- [ ] Never-uploaded dependency-free local capture may be explicitly discarded.
- [ ] A trusted worker performs final recheck, external purge and absence
  verification through an idempotent outbox/state machine.
- [ ] Account deletion/legal retention remains a separate higher-authority policy.
- [ ] Firebase objects are never deleted during profiling, rehearsal or initial
  cutover/rollback retention.
- [ ] The canonical production reference/object profile remains required.
