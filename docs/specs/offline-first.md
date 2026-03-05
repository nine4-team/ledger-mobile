# Offline-First Architecture

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

## How the Database Enables This

The database SDK provides automatic offline support:

1. **Persistent local cache**: All data read from the database is cached locally on the device. Subsequent reads serve from cache first, then update when the server responds.

2. **Offline writes**: Writes are queued locally when offline. The SDK automatically syncs when connectivity returns. The app does not need to implement its own queue.

3. **Real-time listeners**: Snapshot listeners fire immediately with cached data (marked as from-cache), then fire again when server data arrives. The UI stays responsive regardless of connectivity.

## Write Patterns

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

## Attachment Lifecycle

Attachments have a multi-stage lifecycle because actual bytes require connectivity.

### Stage 1: Local Capture

User takes a photo or selects a file. The file is stored locally on the device.

### Stage 2: Metadata Write

An attachment reference (`AttachmentRef`) is written to the parent document (transaction, item, or space). AttachmentRef fields:

- `url` (string): the download URL — empty or placeholder until upload completes
- `kind` (string): "image", "pdf", or "file"
- `fileName` (string, optional): original file name
- `contentType` (string, optional): MIME type
- `isPrimary` (boolean, optional): whether this is the primary/hero image

This write is fire-and-forget and works offline.

### Stage 3: Upload

The actual bytes are uploaded to cloud storage. This requires connectivity.

- If online: upload starts immediately
- If offline: upload is queued and retried when connectivity returns

### Stage 4: URL Update

Once upload completes, the attachment reference's `url` field is updated with the public download URL from cloud storage.

### Offline Display

- If `url` is populated: display from the URL (or from image cache)
- If `url` is empty but local file exists: display from local file
- If neither: show a placeholder with upload-pending indicator

## Sync Status Indicators

The app should communicate sync state to users without blocking them:

| State | Indicator | User Action |
|-------|-----------|-------------|
| Online, synced | No indicator (or subtle green dot) | Normal operation |
| Online, syncing | Subtle sync animation | Normal operation — data is being sent |
| Offline | Yellow banner: "Offline — changes will sync when connected" | Normal operation — all features work |
| Sync error | Red banner: "Sync error — retrying..." | Normal operation — SDK auto-retries |

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
| Upload images | No | Bytes require connectivity, queued |
| Sign in/out | No | Auth requires connectivity |
| Invoice import (PDF parsing) | No | Requires server-side processing |
| Request document processing | Partial | Document created offline, processed when online |

## Conflict Resolution

The database uses last-write-wins for conflict resolution. When two clients modify the same field offline and then sync:

- The write with the later timestamp wins
- No merge — the entire field value is replaced

This is acceptable for this app because:

1. Most edits are by a single user on a single device
2. Multi-user scenarios are rare and typically on different entities
3. The cost of occasional lost edits (last-write-wins) is much lower than the complexity of merge conflict UI

## Design Decisions

### Why not await writes?

Awaiting database writes in UI code creates a bad offline experience: the user would see a spinner until connectivity returns (which could be hours). By treating writes as fire-and-forget, the UI stays responsive regardless of connectivity.

### Why not custom sync queues?

The database SDK already provides robust offline persistence and sync. Building a custom sync layer on top would add complexity without benefit. The SDK handles retry, ordering, and conflict resolution automatically.

### Why local cache over server-first?

Interior designers and project managers frequently work in locations with poor connectivity (construction sites, warehouses, remote properties). A server-first architecture would make the app unusable in these scenarios. Cache-first ensures data is always available.
