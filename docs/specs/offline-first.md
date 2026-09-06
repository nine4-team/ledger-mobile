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

Navigate and update state immediately after a write. Don't wait for server confirmation before showing the result. When a user saves a transaction, they should see the updated data and be navigated to the next screen instantly.

### Rule 3: Only Block on Actual Uploads

The only operations that require connectivity are:

- **File uploads**: Actual file bytes (images, PDFs) need a network connection
- **Authentication operations**: Sign-in, sign-out, token refresh

All database reads and writes must work offline.

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
| Offline | Yellow banner: "Offline — changes will sync when connected" | Normal operation — all features work |
| Sync error | Red banner: "Sync error — retrying..." | Normal operation — SDK auto-retries |
| Attachment queued | Pending-media count/progress | Continue working; retry or inspect when needed |
| Attachment rejected | Actionable failed-media state | Retry after correction, export, or explicitly discard |

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
| Invoice import (PDF parsing) | No | Requires server-side processing |
| Request document processing | Partial | Document created offline, processed when online |

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

Awaiting database writes in UI code creates a bad offline experience: the user would see a spinner until connectivity returns (which could be hours). By treating writes as fire-and-forget, the UI stays responsive regardless of connectivity.

### Why separate structured and media queues?

The target structured data plane owns durable row/operation synchronization.
Attachment bytes remain outside structured sync and therefore require one
separate, adapter-independent durable media queue. Product/domain code observes
stable local receipts and outcomes rather than Firebase, Supabase, or PowerSync
SDK callbacks.

### Why local cache over server-first?

Interior designers and project managers frequently work in locations with poor connectivity (construction sites, warehouses, remote properties). A server-first architecture would make the app unusable in these scenarios. Cache-first ensures data is always available.
