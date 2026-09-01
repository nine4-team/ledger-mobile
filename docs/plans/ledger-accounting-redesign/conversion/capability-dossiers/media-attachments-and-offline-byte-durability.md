# Capability Dossier — Media, Attachments, and Offline Byte Durability

Status: reviewed static characterization; 15 of 19 target-relevant surfaces are
exactly target-mapped. The four reference-removal/destructive MCP surfaces are
honestly withheld on O-023 and the canonical production reference/object
profile; implementation and the bounded spike remain unauthorized

## Outcome

A user can capture an image, PDF, or supported file without connectivity, see
and continue using the local result immediately, and trust Ledger to retain the
bytes until an authorized upload is verified or the user explicitly discards
them. Attachments remain ordered, attributable, private, and usable across app
restart, account switching, MCP operations, migration, and later backend
replacement. Removing a reference never causes accidental loss of shared,
financial, or historical evidence.

## Source Surfaces

### Core iOS media lifecycle

| Surface ID | Source | Current responsibility |
|---|---|---|
| `SWIFT-6EB56A9100C3` | `Services/MediaService.swift` | Firebase upload/delete seam, fixed entity path convention, retry, and best-effort thumbnail upload |
| `SWIFT-8A935E590458` | `Services/MediaUploadQueue.swift` | Restart-durable local bytes/JSON, retry/discard UI state, Firebase destination checks, and dynamic Firestore writeback |
| `SWIFT-6AF81DAE53D0` | `Services/StorageURLResolver.swift` | Firebase `gs://` to token-URL resolution and process-memory cache |
| `SWIFT-A6162BC6046B` | `Services/ImageThumbnailGenerator.swift` | Pure 300px/800px JPEG derivative generation and `_sm`/`_md` path derivation |
| `SWIFT-06586B87FCA4` | `Services/ImageCache.swift` | 50 MB decoded-image memory cache and background decoding |
| `SWIFT-9F58549FBE25` | `Models/Shared/AttachmentRef.swift` | URL-shaped attachment value, derivatives, kind, filename/type, primary flag, upload flag, and image checkmarks |
| `SWIFT-F971A5B270E6` | `Models/Shared/AttachmentUpload.swift` | In-memory bytes plus filename/content-type/extension and generated storage filename |
| `SWIFT-54042738FD68` | `Logic/MediaGalleryCalculations.swift` | Primary-image selection, limits, gallery/navigation, and upload-overlay calculations |
| `SWIFT-1BE4CD10F963` | `Logic/PinnedImageCalculations.swift` | Image/PDF pin eligibility, normalized marks, Item-photo associations, zoom/pan, and photo-review progress |
| `SWIFT-EE7D53A3C3EA` | `Logic/PdfImageExtractor.swift` | Local extraction of PDF image regions used by invoice import |

### Presentation and local consumers

| Surface IDs | Source family | Current responsibility |
|---|---|---|
| `SWIFT-6E1F36B8E002`, `SWIFT-98FF74C056E9` | `FirebaseImage`, `MediaGallerySection` | Remote thumbnail/original loading, gallery fallback, camera/photo/file/PDF intake, upload UI, save, remove, primary and pin actions |
| `SWIFT-5CEBE17B0605`, `SWIFT-AA164CD97713`, `SWIFT-4AC6C92BBF6D`, `SWIFT-19A7638941BB` | Image/gallery/card/thumbnail components | Full-screen viewing, cards, mixed-media thumbnails, and PDF presentation |
| `SWIFT-3CEB22DD4642`, `SWIFT-4E1AF7AD4958`, `SWIFT-8D965719CF18`, `SWIFT-893FA8676E2C` | Pin/select/PDF components | Side-by-side visual reference, selection/grouping, authenticated PDF loading |
| `SWIFT-4E4F3BC46421` | `Platform/ShareHelper.swift` | Save, print, and share paths that download referenced media |
| `SWIFT-88C69E26FBA0` | `LedgerApp.swift` | URL caches, queue construction, launch processing, and connectivity-restored processing |
| `SWIFT-2D9222A4489A` | `RootView.swift` | Pending/failed upload banners, retry, discard, and logout-adjacent state |

The queue's `localImageURL` and `pendingUploadIds` APIs have no callers outside
the queue itself. Despite their comments, the current UI does not connect a
queued upload ID to an attachment shown by `FirebaseImage`. The documented
"show local file immediately" outcome is therefore not implemented uniformly.

### Parent shapes and feature callers

The parent models and screens below are linked here for media completeness but
retain their final manifest ownership in their Project, Item, Space,
Transaction, identity, or invoice-import dossiers:

| Parent / caller | Media behavior observed |
|---|---|
| `Account`, `AccountView` | One optional logo attachment; logo upload is a direct online operation |
| `Project`, `NewProjectView`, `EditProjectModal` | Fixed `mainImageUrl` plus small/medium thumbnail fields; create/edit uses the durable queue |
| `Item`, `NewItemView`, `ItemDetailView`, `ItemsTabView` | Attachment arrays, queued creation uploads, direct detail uploads, primary selection, transaction-image reuse, grouping, pinning, save/print |
| legacy `ProtoItem`, `ItemDraftCaptureSheet`, `ItemQuickDraftDetailView` | `photos` array, queued capture, direct later edits, promotion/copy semantics; target creation no longer writes proto records under D-018/D-025 |
| `Space`, `SpaceDetailView`, `SpaceReviewNote` | Image array, direct detail uploads, Item-linked checkmarks, note snapshots referencing existing bytes, pin/save/print |
| `Transaction`, `NewTransactionView`, `TransactionDetailView`, `ImportInvoiceModal` | Receipt/other/general attachment arrays; direct create/detail upload, queued imported PDF/crops, pin/save/remove/primary |

This split matters: a target media service can be correct while a parent screen
still bypasses it. Every caller must eventually use the same durable attachment
operation; parent domain behavior is not classified solely by this dossier.

### MCP/server media boundary

| Surface ID | Source | Current responsibility |
|---|---|---|
| `MCPMOD-D4D2CD9DBB10` | `mcp-server/src/storage.ts` | Hardcoded Firebase bucket, token URL generation/parsing, upload/size verification, copy, and delete |
| `MCPMOD-D7B37EA0483A` | `util/thumbnail.ts` | Best-effort server thumbnails at the same two dimensions |
| `MCPMOD-E72071DBC337` | `util/attachment-primary.ts` | Exact-one-primary normalization |
| `MCPMOD-BB34B27B541A` | `util/item-images.ts` | Ordering, primary selection, reference detach, and namespace-aware deletion partitioning |
| `MCPMOD-3330B6FD5A68` | `util/item-image-storage.ts` | Quick-draft copy/verification/cleanup into Item namespace |
| `MCPTOOL-648BE9A38A56`, `MCPTOOL-25AAB317BFEE`, `MCPTOOL-CF7AEAE1966B`, `MCPTOOL-35D04B60563F`, `MCPTOOL-608B84DDBEA5` | Item image tools | Attach, reorder, set primary, non-destructive detach, and explicit destructive deletion |
| `MCPTOOL-16839AD4EE69`, `MCPTOOL-EAA4B71CE0F5` | Space attachment tools | Attach and a detach operation that also attempts immediate object deletion |
| `MCPTOOL-19127C4032BD`, `MCPTOOL-9C8591F5294C` | Transaction attachment tools | Attach receipt/other files and a detach operation that also attempts immediate object deletion |

The attach tools accept either base64 or a remote URL. They fetch a URL before
enforcing the 10 MB post-download limit, rely on caller/header MIME claims, and
do not provide one shared redirect, private-address/SSRF, timeout, streaming,
filename, extension, or content-sniffing policy. Item paths randomize and
partially sanitize the filename; Space and Transaction paths use the supplied
filename directly. These are target security defects, not compatibility
requirements.

### Rules, tests, fixtures, and migration tools

- `MAN-STORAGE-001` and `firebase/storage.rules` establish that current
  production objects are globally readable and writable and that the actual
  production reference/object graph is still unprofiled.
- `MAN-LOCAL-001` owns device media, caches, keys, logout, and account-removal
  lifecycle across this dossier and the identity dossier.
- Swift tests cover upload metadata compatibility, the Firebase uploader seam,
  derivative size/no-upscale behavior, primary normalization, gallery
  calculations, image marks, and pin geometry. They do not exercise the
  file-backed queue through crash/restart/account switch or prove local display.
- MCP tests cover exact-one-primary, Item ordering/reorder, shared-versus-owned
  deletion partitioning, tool schemas, and quick-draft copy/cleanup. They do not
  cover private Storage policy, remote-file ingestion security, interrupted
  upload, Space/Transaction deletion consistency, or cross-account denial.
- `migration/src/media-migrator.ts`, `media-only-migrate.ts`,
  `migrate-images-only.ts`, `fix-thumbnails.ts`, `regen-thumbnails.ts`,
  `check-urls.ts`, and `migrate-missing.ts` are legacy Supabase-to-Firebase or
  one-off Firebase repair tools. They are source-only evidence and are not the
  Firebase-to-Supabase importer.
- `scripts/export-transaction-receipt-attachments.mjs` is a narrow read-only
  support exporter, not whole-account object reconciliation.
- Firebase emulator media fixtures are useful source-system evidence only; the
  target needs isolated private-bucket fixtures and negative policy tests.

## Current Observable Behavior

### Capture and upload

1. New Project hero images, new Item images, legacy quick-draft photos, and
   invoice-import PDFs/crops write local files to the queue after creating their
   parent records. Queue processing starts on app launch, explicit enqueue
   paths, and a connectivity-restored callback.
2. New Transaction receipt media and Account logos upload before the attachment
   becomes part of local domain state. Item, Space, Transaction, and quick-draft
   detail screens also use direct network uploads; Item and Space first write an
   empty-URL `isUploading` placeholder but do not retain the bytes in the durable
   queue.
3. Queue enqueue writes bytes and JSON as two files. Failure is printed, not
   thrown, and the method still returns the upload ID. A failure between the two
   writes can leave an orphan; a caller can believe capture succeeded without a
   durable receipt.
4. Processing uploads the original, attempts both derivatives, then dynamically
   updates a parent field or embedded array in Firestore. Missing local bytes
   silently remove the entry. Missing destination documents terminate it.
5. Attempts stop at ten and become user-retryable/discardable. There is no
   exponential backoff/scheduling at the queue level, OS background-transfer
   contract, byte/progress state, checksum, or durable applied/rejected receipt.
6. Queue files are app-global and plaintext at an ordinary Application Support
   path; account/principal is metadata rather than the storage boundary. Logout
   and account switch do not coordinate with them.

### Identity, presentation, and reuse

1. The canonical identity is normally the attachment URL. Arrays use URL for
   deduplication, primary selection, removal, note snapshot IDs, and Item-image
   reuse. Empty placeholder URLs and expiring/moved URLs cannot safely provide a
   stable identity.
2. Existing data may use Firebase token HTTPS URLs, `gs://` paths,
   `offline://` legacy placeholders, and historical non-Firebase URLs. The iOS
   resolver handles HTTP(S) and Firebase `gs://`; the MCP ownership parser
   recognizes only one hardcoded Firebase HTTPS form.
3. Remote images load a thumbnail first and fall back to the original, with a
   15-second attempt watchdog, a decoded-image memory cache, and shared URL disk
   cache. Uncached remote media is unavailable offline. Cache partitioning and
   account-removal cleanup are not observed.
4. Rich useful behavior exists above upload: mixed image/PDF galleries,
   original filename/type display, primary selection, ordering, pinning,
   normalized photo marks linked to Items, Space note visual snapshots,
   save/share/print, and transaction-image reuse on Items.
5. Exact-one-primary enforcement is inconsistent. Shared pure normalizers and
   several MCP paths repair arrays, while multiple iOS remove paths and the
   Transaction MCP detach path remove by URL without re-normalizing.

### Object ownership and removal

1. Current objects conventionally live under an account/entity/entity-ID path,
   but Storage rules enforce none of that.
2. iOS removal writes the parent array first and then best-effort deletes only
   the original URL, usually leaving derivative objects. It does not first prove
   whether another parent, review-note snapshot, or reused Item reference points
   at the same bytes.
3. MCP Item operations distinguish non-destructive detach from destructive
   delete and delete only paths parsed inside that Item's namespace. Space and
   Transaction "detach" operations immediately remove the reference and then
   best-effort delete original/derivatives.
4. Quick-draft promotion deliberately copies bytes and regenerates derivatives
   in the Item namespace while retaining the draft source. Item reuse of a
   Transaction image can instead share the same URL without copying. The source
   therefore contains both copied and shared ownership patterns.
5. Partial object/write failures can leave objects without references,
   references without usable objects, duplicated derivatives, or stale primary
   flags. There is no authoritative reference graph or retention journal.

## Product and Spec Reconciliation

| Authority | Assessment |
|---|---|
| `offline-first.md` | The offline outcome is authoritative, but Firebase-cache language and the assertion that local pending bytes are displayed were stale. The attachment section is updated to the target durable-receipt contract without choosing tables/paths |
| `items.md`, `proto-item-capture.md` | Preserve photo-first speed, one real target Item identity, Item media through Link, and legacy proto compatibility. Current background/direct Firebase upload mechanics are not target behavior |
| `data-model.md` | Corrected the legacy proto attachment field from `images` to the implemented `photos`; URL-shaped `AttachmentRef` remains current-state documentation, not target identity |
| `spaces.md`, `ui/image-pinning.md` | Preserve Space photos, checkmarks, note visual references, gallery/pin/save/print behaviors; private authenticated loading replaces URL assumptions |
| D-018/D-022/D-025 | One Item and one target Item writer must preserve local media through quick completion, Link, legacy import, and duplicate reconciliation |
| O-018/O-019/O-022 | Proto cutoff, deterministic media/evidence merge, and already-shipped offline Firebase writer recovery constrain migration and cutover |
| O-023 | Newly recorded: reference removal versus permanent byte deletion/retention must be decided consistently, especially for shared and financial evidence |
| A-003/A-004 | Supabase/PowerSync remain proposed until the vertical spike; this dossier does not approve production migration |
| A-006 | Structured sync carries attachment metadata, not bytes; a separate durable media queue owns local bytes and upload reconciliation |
| A-011/A-016 | Per-principal local encryption and the offline authorization lease govern pending media and protected caches |

No source behavior or old spec sentence becomes product authority merely because
it exists. The architecture package still does not authorize implementation.

## Behavior Decisions

| Classification | Decision |
|---|---|
| Preserve | Offline capture intent; immediate local visibility; images/PDFs/files where allowed; filename/type metadata; ordered galleries; exactly one primary for a non-empty applicable collection; thumbnail fallback; pin/save/share/print; Item-linked photo marks and Space note visual references; explicit retry/discard; source evidence during legacy promotion/reconciliation |
| Correct | Globally open objects; permanent bearer URL identity; unpartitioned plaintext pending files/caches; enqueue success without durable persistence; direct-upload bypasses; empty-URL identity; silent missing-byte removal; inconsistent primary repair; unverified MIME/filename/remote fetches; hardcoded bucket; delete-without-reference-check; thumbnail orphaning; public unauthenticated MCP instructions |
| Improve | One capture/enqueue path for every screen and MCP ingress; durable byte/progress/error receipts; resumable/idempotent transfers; checksum/size verification; explicit derivative state; per-account sync health; storage quotas/backpressure; reference-aware retention/reconciliation; observable cleanup and migration journals |
| Redesign | Stable attachment IDs and canonical object locators replace URL identity; private access is resolved at display time; local/upload/derivative status is explicit; legacy proto promotion and duplicate reconciliation operate on attachment evidence rather than copying Firebase URL mechanics |
| Retire | `FirebaseImage` naming and Firebase SDK leakage; token URLs as durable data; `gs://` runtime resolution after migration/compatibility closes; dynamic collection/field writeback; app-global `PendingUploads`; target proto namespace writes; old Supabase-to-Firebase media tools as target implementation |
| Open | O-023 deletion/retention UX; allowed type/size policy by parent; derivative format/quality/where generated; metadata/EXIF policy; local storage quota and disk-pressure behavior; final production shared-reference/object variants until profiling |

## Target Observable Contract — Backend Neutral

This is sufficient for port and test design, not target table or object layout:

1. Accepting a capture atomically produces a stable `AttachmentID`, protected
   local bytes, parent/account/principal/environment scope, metadata, and a
   durable receipt. If durability fails, the UI reports failure and does not
   claim the attachment was saved.
2. The parent and attachment are visible immediately from local state. Display
   resolves local source bytes first, then an authorized cached or remote
   source; a network URL is never the attachment's identity.
3. Every app screen and MCP operation uses the same attachment lifecycle and
   stable error taxonomy. No detail or create screen may bypass durability with
   an ad hoc direct upload.
4. Pending state survives process termination, device restart, connectivity
   changes, and transient identity refresh. It remains bound to its original
   principal/account/environment and cannot upload under another session.
5. Upload is idempotent by attachment/operation identity. Repetition,
   interruption, and resumed transfer produce one canonical original and one
   durable applied or rejected result rather than duplicate references.
6. Original readiness requires authorized-object verification and recorded
   size/checksum where supported. Derivative failure is explicit and retryable;
   it does not erase a verified original, and display can fall back safely.
7. Structured sync carries stable metadata/canonical object locators and status,
   never pending bytes or a long-lived bearer URL. Private read access is
   authorized against the current parent/account scope when requested.
8. Ordering and primary selection operate on stable IDs with transactional or
   conflict-aware semantics. A non-empty collection that supports a primary has
   exactly one after attach, reorder, detach, migration, retry, and concurrency.
9. Reference reuse/copy has explicit provenance. Removing a parent reference is
   distinct from physical deletion; deletion waits for O-023, authoritative
   reference checks, financial/audit retention, and a recoverable quarantine
   window.
10. Remote-file ingestion validates scheme, redirects, resolved network target,
    time/size while streaming, filename/path, sniffed content, and allowed type.
    Service and human actor are authorized and audited before attachment.
11. Logout, account switch, revocation, database repair, and environment switch
    follow the identity dossier's pending-work policy and securely partition or
    clear local media, signed access, caches, and keys only when permitted.
12. Migration correlates every required source reference and unique object to a
    target attachment/object or an explicit missing/quarantine/approved-omission
    result. Derivatives are rebuildable; missing originals are never silently
    treated as successful migration.

## Migration and Compatibility Contract

The Firebase-to-target media migrator must start from a canonical read-only
Firestore/Auth/Storage profile and immutable export, not the reverse-direction
legacy scripts. It must:

1. inventory Account logos, Project hero fields, Item images, legacy proto
   `photos`, Space images and review-note snapshots, Transaction receipt/other/
   general arrays, thumbnails, and every object namespace found in production;
2. normalize Firebase token HTTPS, `gs://`, `offline://`, historical Supabase,
   and other external references without printing bearer tokens;
3. build a many-reference-to-one-object graph before deciding copy, reuse,
   missing, external, derivative, orphan, or quarantine status;
4. hash/size/type each reachable original where access permits, copy into the
   isolated target idempotently, and journal source reference/object to target
   attachment/object identity;
5. regenerate derivatives under one versioned target policy instead of trusting
   every legacy derivative; preserve the source URL/path only in protected
   migration evidence, not as target application identity;
6. reconcile reference counts, unique originals, bytes, hashes, attachment
   order/primary, parent links, shared references, and all exceptions;
7. include device-only pending media in the O-022 source-freeze/pending-write
   disposition because a server export cannot contain bytes that never uploaded;
   and
8. never mutate or delete Firebase objects during rehearsal or initial cutover.

Production object counts, shared-reference frequency, missing objects, content
types, size distribution, legacy URL variants, and dangling objects remain
unconfirmed until the fail-closed read-only profiler runs.

## Required Tests

### Deterministic contract tests

- capture failure versus locally durable receipt; no false-success ID;
- every parent/caller uses the same enqueue contract;
- stable attachment identity independent of path, signed URL, filename, or
  derivative;
- exact-one-primary and stable ordering after attach/reorder/detach/concurrency;
- local-first display, thumbnail-to-original fallback, mixed image/PDF/file
  behavior, pin/save/share/print, and normalized annotation/checkmark behavior;
- allowed type, sniffed type, size, filename/path and checksum validation;
- duplicate idempotency key returns the same object/result;
- detach does not delete shared bytes; approved destructive removal observes
  retention/reference checks; and
- MCP and app return the same typed outcomes and enforce the same parent scope.

### Offline, lifecycle, and fault tests

- airplane-mode capture is immediately visible and survives force-quit, device
  restart, seven days offline, and repeated connectivity changes;
- interruption before/after byte save, metadata save, upload start, object
  completion, verification, metadata application, and derivative completion;
- resumable retry does not duplicate objects or attachment rows;
- a permanent authorization/validation rejection does not block unrelated
  uploads and preserves recoverable local evidence;
- account switch and routine logout cannot upload or delete pending bytes under
  another principal; destructive removal requires exact-count consent;
- local database corruption/key mismatch preserves or exports pending bytes
  before resync; disk-full/quota behavior is explicit and fail-closed;
- signed access expiry refreshes online, cached media remains governed by the
  approved offline lease, and logout clears access/cache only when permitted;
  and
- parent deletion during upload yields one explainable terminal result and
  retention state, not silent cleanup.

### Security tests

- unauthenticated, cross-account, guessed-path, removed-member, restricted-
  financial-access, stale-token, and cross-environment reads/writes/deletes fail;
- client-chosen object paths cannot escape the authorized attachment scope;
- content-type spoofing, oversized bodies, traversal names, redirect chains,
  private/link-local/metadata-service URLs, slow streams, and decompression/
  image bombs fail within bounded resources;
- public bucket/object access is absent unless separately approved; signed URLs
  are short-lived and never persisted to structured sync or logs; and
- service credentials are absent from the app and privileged MCP actions retain
  both service and human/agent attribution.

### Migration and reconciliation tests

- fixtures cover token HTTPS, `gs://`, `offline://`, historical external URLs,
  shared originals, copied draft originals, missing objects, corrupt files,
  orphan derivatives, duplicate primaries, and empty placeholders;
- rerunning an interrupted migration changes no already reconciled object or
  attachment identity;
- every required source reference maps exactly once or has an approved explicit
  exception, while unique-object hashes/bytes reconcile;
- staging contains no production credentials or reachable production writes;
  and
- rollback leaves source objects and protected migration evidence intact.

## Dossier Outcome

- **Ready for target-independent mapping:** attachment IDs/receipts, local-first
  display sources, queue/error state, primary/order behavior, object verification,
  reference-aware retention interfaces, security boundary, and test contracts.
- **Ready for a bounded spike:** protected per-principal local bytes, interrupted
  resumable upload, private authenticated rendering, derivative retry, and
  idempotent metadata reconciliation using synthetic data.
- **Blocked for final schema/object mapping:** O-023, production object/reference
  profile, allowed content/size and derivative policy, and final A-003/A-004
  vertical-spike approval.

No Firebase adapter, Supabase table/bucket policy, PowerSync Stream, target
object layout, production read, or migration is authorized by this dossier
alone.
