# Offline-First Architecture

> **Target-state notice (2026-08-31):** The offline product requirement in this
> document remains authoritative, but its Firebase cache/listener implementation
> describes the current system. The redesigned implementation, operation
> lifecycle, conflict classes, local encryption, and PowerSync data plane are
> defined in the
> [Ledger Redesign Architecture](../architecture/redesign/03-data-sync-and-offline.md).

## Core Principle

The app must be usable without internet connectivity. Users working on job sites, in warehouses, or traveling should never be blocked by a spinner waiting for server acknowledgment.

## Three Rules

### Rule 1: No Spinners of Doom

Never block the UI on server acknowledgment. If local or cached data exists, show it immediately. The user should never stare at a loading indicator waiting for a network round-trip to complete before they can interact with data.

### Rule 2: Optimistic UI

Update the UI after durable local acceptance, without waiting for server
confirmation. A failed local save is a visible failure, not optimistic success.
Accepted work survives restart and remains visibly pending until its
authoritative outcome arrives. Navigation must not race ahead of local storage.

### Rule 3: Only Block on Actual Uploads

Connectivity is required for remote effects such as:

- **File uploads**: Actual file bytes (images, PDFs) need a network connection
- **Authentication operations**: First sign-in, provider recovery and server
  token refresh; local unlock and session ending follow their separate policies
- **Server processing**: Authoritative command execution and remote parsing

The required working set and supported edits must be usable offline through
authorized local reads and durable queued intent. Uncached data cannot be read
without downloading it, and queued intent is not a completed server effect.
Neither case permits presenting missing/partial data as authoritative empty
state. Offline authorization remains gated by the approved access lease.

## Current Firebase Database Behavior

This section characterizes the shipped source system. It is not the target
implementation contract.

The database SDK provides automatic offline support:

1. **Persistent local cache**: All data read from the database is cached locally on the device. Subsequent reads serve from cache first, then update when the server responds.

2. **Offline writes**: Writes are queued locally when offline. The SDK automatically syncs when connectivity returns. The app does not need to implement its own queue.

3. **Real-time listeners**: Snapshot listeners fire immediately with cached data (marked as from-cache), then fire again when server data arrives. The UI stays responsive regardless of connectivity.

## Current Firebase Write Patterns

### Fire-and-Forget (Most Writes)

```
write_to_database(data)    // SDK queues if offline
  on_error: log(error)     // Log but don't block
navigate_to_next_screen()  // Immediately, don't await the write
```

The write call returns a future/promise, but UI code MUST NOT await it before navigating or updating local state. The SDK handles offline queueing and sync automatically.

### Request Documents (Multi-Document Operations)

Even request documents (see write-tiers.md) work offline:

1. Client creates the request document (fire-and-forget write)
2. When connectivity returns, the request document syncs to the server
3. A server-side function trigger processes it
4. Status updates flow back through the real-time listener

The user sees the request as "pending" until connectivity returns and the server-side function processes it.

## Target Attachment Lifecycle

Attachments have a multi-stage lifecycle because actual bytes require connectivity.

### Stage 1: Local Capture

The user takes a photo or selects a file. Ledger accepts the capture only after
protected local bytes, a stable attachment ID, parent/account scope, metadata,
and a durable receipt have been stored. A failure to persist locally is shown as
a save failure; it must not return a success-shaped upload ID.

The locally accepted attachment appears immediately, including after process
termination and restart. This guarantee applies consistently to every create
and detail screen, not only selected flows.

### Stage 2: Local Metadata and Structured Sync

Attachment metadata and the parent relationship enter local structured state.
Structured synchronization carries metadata, ordering, primary selection,
canonical object location, and lifecycle status—not the file bytes.

An attachment ID, not a URL, is canonical identity. Empty URLs and long-lived
bearer URLs are not target placeholders or identifiers.

### Stage 3: Upload

The actual bytes are uploaded to private object storage when connectivity and
authorization permit. Uploads are resumable/idempotent and remain bound to the
capturing principal, account, and environment.

- If online, transfer may start immediately without blocking unrelated work.
- If offline, protected bytes remain queued and visible.
- Interruption or retry must not create duplicate attachment identity or
  duplicate canonical objects.

### Stage 4: Verification and Reconciliation

Ledger marks the original ready only after authorized-object verification and
records size/checksum where supported. Derivative generation has separate,
visible retry state and cannot erase a verified original. The server result is
durably observable as applied or rejected rather than inferred from a completed
SDK call.

Private media is rendered through an authenticated request or short-lived
access URL resolved at use time. That access URL is not stored as attachment
identity in synchronized data.

### Offline Display

- If protected local source bytes exist, display them immediately.
- Otherwise, display an authorized cached derivative/original if permitted by
  the offline-access policy.
- Media never cached on the device requires connectivity to download.
- Missing local bytes for a supposedly pending capture are an explicit
  recoverable error, not a silently completed or discarded upload.

Removing a parent reference is distinct from deleting object bytes. Permanent
deletion requires the approved O-023 retention behavior, authoritative
reference checks, and a recoverable quarantine window.

## Sync Status Indicators

The app should communicate sync state to users without blocking them:

| State | Indicator | User Action |
|-------|-----------|-------------|
| Online, synced | No indicator (or subtle green dot) | Normal operation |
| Online, syncing | Subtle sync animation | Normal operation — data is being sent |
| Offline | Offline/pending status | Continue supported cached work; uncached data and remote effects remain visibly unavailable/pending |
| Transient sync error | Actionable retry status | Continue unrelated work while bounded retries preserve operation identity |
| Permanent operation rejection | Explicit rejected-work state | Review exact retained intent; recovery/resolution follows O-051, not endless retry or silent discard |
| Attachment queued | Pending-media count/progress | Continue working; retry or inspect when needed |
| Attachment rejected | Actionable failed-media state | Preserve bytes and evidence; correction/export/removal must follow approved recovery, retention and session-ending rules |

## What Works Offline

| Operation | Offline? | Notes |
|-----------|----------|-------|
| Read any cached data | Yes | Served from local cache |
| Create/edit transactions | Yes | Queued, synced on reconnect |
| Create/edit items | Yes | Queued, synced on reconnect |
| Create/edit spaces | Yes | Queued, synced on reconnect |
| Link/unlink items | Yes | Queued, synced on reconnect |
| Budget calculations | Yes | Computed from cached data |
| Transaction audit | Yes | Computed from cached data |
| Search | Yes | Searches cached data |
| Capture images/PDFs/files | Yes | Saved and displayed locally; byte transfer waits for connectivity |
| Download never-cached media | No | Requires authorized network access |
| Sign in/recover account | No | First sign-in and provider recovery require connectivity |
| Log out/remove local account | Conditional | Pending-work disposition applies before destructive local cleanup |
| Invoice import | Conditional | Supported Amazon/Wayfair text-PDF parsing and review work locally; remote OCR/parsing, uploads and authoritative application require connectivity |
| Complex command processing | Partial | Target durable intent is accepted offline; authoritative processing waits for connectivity. Request documents are source mechanics only |

## Current Firebase Conflict Behavior

The database uses last-write-wins for conflict resolution. When two clients modify the same field offline and then sync:

- The write with the later timestamp wins
- No merge — the entire field value is replaced

This is current behavior, not blanket target approval. The redesigned system
uses the conflict classes and operation preconditions in the offline
architecture. In particular, attachment membership/order/primary state uses
stable attachment IDs and conflict-aware operations rather than whole-array
last-write-wins.

The historical rationale was:

1. Most edits are by a single user on a single device
2. Multi-user scenarios are rare and typically on different entities
3. The cost of occasional lost edits (last-write-wins) is much lower than the complexity of merge conflict UI

## Design Decisions

### Why not await writes?

Waiting for a remote acknowledgment can block for hours offline. The target
awaits only durable local acceptance before showing success-shaped pending
state; it must not copy the source fire-and-forget pattern that hides local
failures. Remote application/rejection remains observable independently.

### Why separate structured and media queues?

The target structured data plane owns durable row/operation synchronization.
Attachment bytes remain outside structured sync and therefore require one
separate, adapter-independent durable media queue. Product/domain code observes
stable local receipts and outcomes rather than Firebase, Supabase, or PowerSync
SDK callbacks.

### Why local cache over server-first?

Interior designers and project managers work in locations with poor
connectivity. Local-first access keeps downloaded, authorized working data
available under the approved lease; it does not guarantee that uncached media
or incomplete history already exists on the device.
