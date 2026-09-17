# Architecture Decision Register

Status: active

### 2026-09-16 — Repeated created-Invoice edits retain membership revisions

Extend the existing live membership key with `joined_at_revision`; do not add
a competing history table. A created-Invoice edit releases previous rows and
inserts the reviewed ordered membership at the new Invoice revision, atomically.
Released rows cannot be rewritten or deleted. Existing membership rows receive
revision 1 as their legacy storage baseline, not a claim about previously
unrecorded edit history. Original source identity, position and release time stay
intact. A trigger permits only first release, never changing source or position
in place; trusted writers must release-and-replace for reordering too.

Existing active-source/position uniqueness and active-only PowerSync projection
remain unchanged: historical rows do not duplicate offline current membership.
Tradeoff: retained rows grow with actual edits. This is simpler than a second
event/projection system and preserves remove/re-add provenance. No sending,
sent-membership, cancellation or collection policy is decided here. The writer
still needs current authorization, created-status/revision and ordered source
locks; this storage change alone does not implement editing. Verification is
owned by `invoice-build-edit` in the product checklist.
Architecture version: 0.2
Last reviewed: 2026-09-07

### Synced membership removal confirmation (2026-09-14)

The bootstrap stream excludes inactive memberships. Normal startup now observes
the selected membership and requests the existing authenticated access check when
that row changes, rather than waiting only for credential refresh or another
request. Missing rows never directly mean removal: only the existing exact server
denial locks the workspace and preserves encrypted pending work. Initial sync,
offline errors and expired credentials do not erase admission. The observation
uses the runtime's existing cancellation/drain ownership, without a timer or new
UI. Focused observation tests and live removal integration are required; reduced
financial scope remains governed by O-058, not decided here.
`/tmp/ledger-membership-observation-test.log` passed the real local-database
observation test0.206s: initial absence, insertion and removal all request server
confirmation, while an unavailable confirmation preserves runtime access; close
drains the watcher. Existing exact-denial/late-read/scope checks passed4tests0.808s
in `/tmp/ledger-normal-binding-removal-native.log`. Live server→sync→UI removal
remains unverified.
Live attempt `/tmp/ledger-normal-live-removal-exact-ui.log` reached the real
membership update. PowerSync reported the removal and closed the client stream,
but the locked-screen assertion failed after60s; the wrapper restored the exact
disposable membership to active. The normal workspace gate covered only navigation
root content, leaving pushed destinations outside it. The gate now surrounds the
whole navigation stack, with the runtime task outside the conditional contents.
This correction requires a new live test identity: do not clear a learned-removal
lock merely to reuse the old fixture's retained local work.
Live gate verification now passes: `/tmp/ledger-normal-removal-focused-ui.log`,
one actual normal-entry iPhone test33.663s. It opens a real downloaded Transaction,
then the external wrapper changes only the disposable local membership to removed.
The app shows Account Access Removed and no longer exposes the detail Back button
or Transaction row; the wrapper restores membership to active afterward. The
original device's removal-locked data is untouched. Search/PDF regression remains
a separate test, not a prerequisite for this access-removal scenario. This proves
local server→PowerSync→normal app removal, not hosted or pending-work recovery.
`/tmp/ledger-normal-removal-reopen-ui.log` then passed11.618s: normal process
relaunch with the same native keychain still denies the retained workspace after
Account selection, despite restored server membership. No local state was cleared.
This adds real device-keychain restart evidence, not crash-during-write proof.

### Normal workspace media transport binding (2026-09-14)

Normal sync startup previously wired uploads but left the shared media downloader
nil. It now binds the existing private downloader to the runtime's exact workspace
identity before starting sync. Item images, Transaction attachments and Account
logos reuse this transport; viewers are unchanged. Each network fetch revalidates
membership and the original signed-in identity; existing readers still recheck
local reference authority before admitting bytes. Actor-owned binding avoids
mutable shared-resource access and is released on close. Cached offline reads
remain available without online authorization. Verification:
`/tmp/ledger-normal-media-binding.log` passed five native scope/transport tests
in0.144s, including foreign Account/principal and closed-runtime binding denial.
`/tmp/ledger-normal-media-wired-ui.log` passed the actual local app-entry test
in27.336s: restored sign-in, selected Account, opened Inventory Transactions,
searched for the uploaded Transaction and rendered its one-page PDF. This uses
the normal runtime, not fixture-entry injection. Real-project data, Back/reentry,
withdrawal and on-screen pending→published continuity remain separate gaps.
Follow-up `/tmp/ledger-normal-media-reentry-ui.log`: normal-entry PDF→Back→same
Transaction→PDF passed37.772s; existing fixture-backed navigation/access-removal
regression passed27.716s. Both tests executed, zero failures. The latter proves
UI withdrawal behavior, not live server-driven revocation of this normal session.

### Workspace navigation lifetime correction (2026-09-14)

The normal-entry receipt test reached an authorized synced Transaction but its
destination became unavailable (`/tmp/ledger-normal-local-receipt-keyboard-ui.log`).
The workspace runtime task was attached to content inside the navigation stack;
navigating away could cancel it and close the database. The selected Account's
workspace now owns the navigation stack and attaches runtime lifetime to that
container, outside its pushed content. Cancellation/removal cleanup remains the
existing implementation. Diagnostics sit outside that stack in a disclosure;
Transaction, gallery and PDF components are unchanged. Verify the same normal
entry plus Back/reentry and withdrawal before claiming this integration complete.
The Account/sign-in branches retain their own scrolling container outside the
selected workspace. Offline picker→sign-in→downloaded picker→selection→restart
passed19.067s in `/tmp/ledger-account-entry-scroll-reviewed-ui.log`. The first
attempt failed on a test helper's workspace-only scroll assumption; both entry
scroll calls now name their actual container. No original form was rebuilt.

### Normal-entry local development configuration (2026-09-14)

Debug builds compiled with `LEDGER_TARGET_LOCAL` use the already-running local
services and a build-supplied `LedgerLocalPublishableKey` Info.plist value. The
environment is fixed at compilation, not selected at launch. This uses normal sign-in and workspace
composition, not a fixture entry or synthetic admission. Both endpoints are fixed
to loopback (Supabase54321, PowerSync5590); the key must be publishable. Release
builds ignore the override. Local manifests use targetLocal and a distinct local
storage/keychain namespace, leaving hosted sessions and data untouched. Hosted
configuration remains the default and still requires a PowerSync instance.
The initial runtime-selected draft was corrected after the environment checker
flagged its conflict with compile-time isolation; no sign-in/data mutation occurred.
This enables actual-app QA without creating paid resources or another UI. Build
and real sign-in/sync validation remain required; no production readiness claim.
Follow-up evidence: `/tmp/ledger-normal-local-plist-build.log` built successfully.
Normal simulator entry visibly reported targetLocal/targetLocalDevelopment, signed
in through Auth with the existing disposable upload-test user, and selected
Synthetic Primary Account; encrypted workspace opened. Full workspace sync and
publication UI inspection remain unverified. Build arguments are
`LEDGER_TARGET_COMPILATION_CONDITIONS=LEDGER_TARGET_LOCAL` and
`LEDGER_LOCAL_PUBLISHABLE_KEY=<local publishable key>`; the generated
`LedgerTargetInfo.plist` carries the build substitution, never a secret key.
Unsigned Release simulator compilation with the local flag also passed
(`/tmp/ledger-local-flag-release-build.log`); packaged version remains0.1.0/build1.
The local branch additionally requires DEBUG, so the flag alone cannot enable it
in Release. This is compilation/configuration evidence, not a release UI test.

### Attachment publication presentation follow-up (2026-09-14; A-036)

The Transaction viewer previously dismissed on any section revision change,
including successful publication of its own pending attachment. Presentation may
now rebind that pending selection to a newer, complete catalog only when scope,
Transaction, section, relationship ID and immutable byte identity match. It uses
the new reference for reads; strict `retains` checks for in-flight exports are
unchanged. Removal, replacement and unrelated revision changes still dismiss.
This adapts the existing viewer, not its UI or storage architecture. Focused
tests: `TransactionAttachmentCaptureAdmissionTests.publicationPresentation`;
The pinned panel also follows this transition and resolves PDFs from the current
catalog, rather than its original pending reference. A selected image must retain
its exact byte identity. Actual upload-to-open-viewer/pin continuity remains
unverified; the existing pin/withdrawal UI scenario is regression coverage only.
Verification: native identity/admission6 tests passed0.024s
(`/tmp/ledger-publication-identity-reviewed.log`); existing iPhone pin/withdrawal
passed39.384s (`/tmp/ledger-publication-pin-regression.log`). Actual local runtime
publication passed23.914s (`/tmp/ledger-publication-live.log`): two images and a
PDF each emitted pending evidence and a matching published replacement, denied
reuse of old export authority, and retained exact bytes after encrypted offline
restart. Test fixture `4b1e9766-5791-48a9-a7b1-15a541807e64` remains local.

This register records cross-cutting technical decisions. Product behavior remains
in the redesign product decision log. A proposed decision is not an
implementation authorization.

Significant technical changes must be recorded here as they are made (user
instruction, 2026-09-07). State what changed and why, intended behavior/history
preserved, tradeoffs, and links to verification evidence or remaining gaps.
Routine edits need no entry. This register records decisions, not a second
progress tracker; use the existing unified checklist for implementation status.

## Status Definitions

- **accepted** — architecture direction approved in principle;
- **proposed** — recommended, awaiting spike/review or explicit adoption;
- **blocked** — cannot close until a named product or technical decision closes;
- **superseded** — retained for history but no longer the target; and
- **rejected** — considered and deliberately not chosen.

## A-036 — Canonical Vendor Transaction Receipt Evidence

Status: accepted technical direction for D-016/D-030; implementation remains
partial. This does not approve unresolved product policy, hosted deployment or
production migration. A-003/A-004 retain their spike gates.

Capture metadata: extend the existing local capture/receipt, not its queue or
vault, with original media type, filename and Transaction section. Bind these
fields into the receipt fingerprint and pending/concurrent replay identity.
Restart must retain Receipts vs Other Images rather than infer it from bytes.
Media type syntax reuses downloaded-object validation; byte inspection and parent
write permission remain required at the capture/upload boundary. Filenames are
display metadata, never canonical storage locations. Metadata-bearing receipts
use v2 fingerprint material; absent metadata retains exact v1 material for
existing durable work. Older receipts remain readable but cannot be silently
assigned an upload type or section. TX-CAPTURE-METADATA owns focused proof. This
does not complete capture UI, parent linkage, upload, verification or deletion.
No extra queue, Firebase adapter or replacement UI is introduced.

Capture preparation uses the original bytes, not picker MIME/filename guesses.
`AttachmentCapturePreparation` shares `OriginalImageSource` with the existing
Item thumbnail generator, identifies actual image MIME through ImageIO, and
checks PDF parsing only when the calling flow permits PDFs. It retains original
bytes and filenames without re-encoding, decryption or extension-based routing.
The byte ceiling matches the existing 64MiB authenticated media transport.
Original thumbnail validation/recipe behavior remains covered by its existing
tests. Preparation alone is not acceptance or parent write authority.
TX-CAPTURE-BYTES records scoped tests.

`captureTransactionAttachment` now binds the capture to the runtime's principal,
Account/environment and current Transaction scope, preserving member media edits
under O-065 and current financial visibility, not adding an Owner/Admin gate.
It serializes local acceptance per Transaction section, counts synced and queued
attachment IDs once against the existing 50-file limit, refuses unknown section
coverage and incompatible identity reuse, and rechecks the parent immediately
before the existing queue commit. The durable receipt carries the parent/section
intent; no additional queue is introduced. Capacity reads use an indexed,
metadata-only parent query, not bulk byte decryption or orphan reconciliation.
Denied pre-commit attempts may leave protected orphan bytes but never a success
receipt; existing reconciliation owns those bytes. Learned removal after a
commit still follows existing lock/retention behavior rather than erasing work.
Other Images capture remains image-only as in its original add callbacks; this
does not remove PDF viewing/pinning for existing references. TX-CAPTURE-ADMISSION
owns local proof. Visible pending-reference integration, structured publication,
server authorization/verification and upload remain unfinished; none is inferred
from these local tests.

Pending Transaction attachments now project the existing durable capture receipt
into the same catalog and gallery, rather than a second media store/renderer.
The initial reference ID is the capture's stable attachment ID, not a vault
receipt fingerprint; publication must retain it. Receipt-backed references load
original encrypted bytes locally even when network downloads are disabled.
Current parent/financial visibility is checked before and after pending metadata
or bytes are read. One owned watch combines structured changes with metadata-only
queue changes; cancellation drains both. The existing thumbnail upload overlay
is shared for the queued clock indicator, which does not claim uploading or
completion. Matching authoritative object evidence suppresses duplicate pending
references; unknown legacy metadata remains incomplete, not invented.
TX-CAPTURE-PENDING records local projection/watch/restart/revocation proof.
New captures persist explicit section-local order and first-attachment primary
intent in the existing fingerprinted receipt metadata. The runtime allocates
these under its existing section capture lock; exact retries reuse the stored
intent. Older receipts remain compatible without invented historical order.
The local runtime test covers equal-time/reverse-ID two-file capture, watch,
original-byte reads, encrypted restart and exact retry. Publication must preserve
that intent; existing revision guards may still close the viewer on publication.
Do not expose a supposedly complete capture flow or retire queue records merely
because a Storage call succeeds. Structured result/readback and byte preservation
must govern publication/drainage.

Capture controls are extracted from `MediaGallerySection` into the shared
`MediaCapturePresentation` modifier, used by both that original wrapper and the
target Transaction section. CameraCapture, DocumentPicker, PhotosPicker, Files
and drop handling are reused, not recreated. AttachmentKind moves beside the
existing backend-independent AttachmentUpload value to avoid importing Firestore
models into the target. Target callbacks prepare original bytes off-main, then
use the existing authorized capture runtime; no second queue or picker screen.
Shared file reads now run off-main while security-scoped access remains held;
missing photo data/document failures are surfaced and picker cancellation is
silent. This improves error delivery, not permission or upload authority.
TX-CAPTURE-PENDING retains non-Photos/multiselect picker interaction, Camera overlap
and capacity feedback, publication/upload and viewer-continuity gaps. Both
platform builds alone do not verify those behaviors.

The explicit DEBUG capture UI route now seeds only synthetic downloaded records
in a UUID-scoped local workspace and opens the live encrypted runtime. It never
starts sync or contacts a configured endpoint; production environments refuse it.
The UI uses the normal Transaction section and system picker, with queue and
original-byte reopening performed by real providers. Seeded service completeness
is not live replication evidence. Existing in-memory browser fixtures remain
rendering-only proof. TX-CAPTURE-PENDING owns the focused picker/restart result.

D-031 Transaction Copy/Paste shares these same boundaries: the existing gallery
accepts an optional Copy callback, using AuthorizedMediaExport's revalidation
and original-byte loading before the shared Clipboard helper writes the image
representation (never a URL/token/path). The existing Add menu gains an opt-in
Paste Image action; clipboard inspection happens only after that explicit action.
Paste uses normal preparation, scope/capacity admission and the durable receipt,
creating a new relationship rather than reusing the source ID. The clipboard is
outside Ledger's protected store, as D-031 allows; learned removal cannot recall
an already authorized external copy. TX-COPY-PASTE records actual clipboard and
encrypted-restart proof plus remaining platform/denial gaps. Other media owners
must opt into their own authorized callbacks; Transaction proof does not certify
Item/Space integration.

Shared capture now holds one busy state for the entire selected batch, retaining
the first failure through later successes. CameraCapture's optional asynchronous
acceptance callback keeps shutter/Done disabled through processing and save,
increments its count only after acceptance, and displays failures/capacity.
The original synchronous callback remains available for existing creation-form
callers; the shared gallery supplies asynchronous acceptance. The existing camera
delegate delivers success/failure exactly once, including failed processing,
instead of leaving acceptance waiting forever. Camera JPEG preparation, preview,
zoom and focus UI are unchanged. macOS no longer offers the nonfunctional
UIKit-only Camera action. Simulator picker checks cannot prove hardware-camera
failure/capture behavior; physical-device verification remains required.

Server upload admission now reserves one immutable, Account-scoped Storage path
before any byte transfer. The reservation is owned by the authenticated capturing
principal, binds the Transaction section, checksum, byte count, media type,
filename and local ordering intent, and is readable only while that principal
retains current access to the parent Transaction. Exact retries return the same
path; conflicting identity reuse, hidden parents, removed members, foreign
Accounts, unsupported media and already-full sections are refused. The path is
content-addressed and does not expose a user filename. Authenticated clients may
insert a new object only at their exact visible reservation and may read it only
for authenticated verification; the reservation grants no overwrite, delete,
list or signed-URL route. No service-role key or broad service grant is added.

The reservation itself is admission, not publication. A reservation does not consume a final
50-file slot, prove that bytes arrived, make a gallery reference visible, or
permit the local durable receipt to drain. Final publication must independently
verify the stored bytes, MIME, size and SHA-256, atomically recheck capacity,
retain the capture's stable reference ID/order/primary intent, and write a durable
applied or rejected result. Concurrent offline reservations may therefore be
rejected at publication if other attachments fill the section first. The
reservation and unverified object are deliberately absent from PowerSync and the
published attachment catalog.

The upload implementation now uses resumable TUS transfers with six-MiB chunks
and the server's HEAD offset for recovery. The authenticated Edge verifier hashes
the stored bytes and invokes a service-only publication command. Publication
rechecks access and capacity, preserves the attachment identity, and records one
immutable result. Missing bytes remain retryable; concurrent verifiers re-read
the result after acquiring the upload lock. The native client checks publication
before retransferring after an ambiguous response. No local capture is deleted
by these transport methods. The existing encrypted local queue now persists TUS
checkpoints and publication results in one nullable local-only column (older
receipts need no rewrite). Terminal results cannot regress to pending; applied
and rejected captures retain their bytes and pending-work protection but no
longer block selection of the next upload. Native restart tests cover both
outcomes, exact retries, byte retention and offset bounds: 33 focused provider
and transport tests pass in `/tmp/ledger-attachment-queue-progress-tests.log`
(the real-service test is separately gated).

The runtime now connects publication to these saved checkpoints and rechecks
local Account/Transaction access between network phases. An interrupted runner
resumes its persisted checkpoint; terminal results do not invoke transport again.
After publication, the runtime reads the synced-only attachment catalog. Only a
complete matching section at or beyond the publication revision, with the exact
reference/content identity and no pending overlay, permits queue drainage.
Drainage atomically moves the original protected-file evidence into the existing
download cache and removes the pending row; it does not delete, copy or re-encrypt
the bytes. Cache evidence therefore also accepts its original Transaction-bound
encryption identity; live parent authorization is still required by every reader.
The cache/queue transition survives encrypted restart without an orphan. Focused
provider/transport/runtime checks pass36 tests in2.466s
(`/tmp/ledger-attachment-runner-drain-tests.log`), including stale/incomplete/
pending/wrong-section refusal and learned-removal denial before credentials.
The authenticated session now starts one runtime-owned attachment worker. Queue
and synced-reference changes plus SDK status updates wake a coalesced work pass;
a30-second retry wake handles transient failures even when SDK status is quiet.
Per-file cooldown prevents event bursts from hammering failed/incomplete uploads.
Only queue metadata is scanned; originals are decrypted when actually attempted.
Rejected publications retain protected pending work but are not retried; applied
ones await synced-only readback without repeating transport. One failed file
does not block later files. Close/removal cancels the worker and awaits all its
database/status observers before closing protected resources. The existing
session-bound credential provider prevents retargeting uploads after sign-in
changes. Native37 tests pass in2.480s
(`/tmp/ledger-attachment-scheduler-consumers.log`), including duplicate-start
coalescing, both-file attempts after a failure, retained receipts, close drainage,
and foreign-workspace denial. Initial scheduler compilation failures (missing
watch parameters/throw propagation) remain in the earlier scheduler logs.
Actual-service-to-runtime proof now passes in22.412s
(`/tmp/ledger-attachment-runtime-live.log`): real Supabase sign-in/authorization,
SDK-managed replication, two new captures after worker startup, automatic TUS and
independent publication, matching synced references, drained pending work, and
exact cached originals after an offline runtime restart. No rows or completeness
markers were injected into the native databases, and offline reads disallowed
network download. The script independently confirms two published references and
results. Local fixture76b49be4-401f-41a5-b28a-a8d2eafc54dc remains; the verifier
process was stopped afterward. A deterministic runtime clock test now proves
no retry at29seconds and both files retried at30seconds, followed by automatic
worker startup/close; six admission scenarios pass in1.069s
(`/tmp/ledger-attachment-retry-timing.log`). The delayed-sync provider test now
reopens after publication but before reference arrival: no reupload, no drainage
for empty/stale/incomplete/pending/wrong-section evidence, original bytes remain
readable, and later exact evidence transfers ownership into restart-safe cache
(`/tmp/ledger-attachment-delayed-sync.log`, PASS0.084s). This complements the real
SDK arrival test above; no extra live-service outage harness was introduced.
Rejected uploads now project their persisted outcome separately
from attachment identity: the existing overlay shows a warning, retains viewer
access, and explains how to export the saved original. Native33 checks pass
(`/tmp/ledger-attachment-rejection-native.log`), including restart, parent/section
isolation and unchanged viewer identity. The existing iPhone capture test passes
in45.893s (`/tmp/ledger-attachment-rejection-ui-reviewed.log`): synthetic rejection,
restart, original rendering, Copy/Paste recovery and byte equality. Its first
failure was the recovery-text selector; the captured screenshot proved the text
visible, and only the selector changed. No viewer/pinning rebuild, automatic
resubmission of a terminal rejection or deletion/discard behavior was introduced.

Photos investigation isolated a target-only navigation deviation. The identical
Transaction attachment section passes denial/OK/retry at the root (22.410s,
`/tmp/ledger-photos-without-detail-sheet.log`) but fails inside a plain sheet with
no browser/session involved (27.146s, `/tmp/ledger-photos-isolated-sheet.log`).
Thus browser invalidation is not necessary to reproduce the presentation failure.
The original Project and Inventory tabs navigate to Transaction details; the
target had introduced a sheet beneath the gallery. Restore navigation, retaining
the same detail controls, gallery and Photos callback. The destination owns a
live read using the existing TransactionBrowserSession while the list is offscreen;
it does not freeze the selected row or bypass withdrawal checks. This reuses the
existing list projection rather than introducing another read model; a dedicated
single-row watch can replace it later if measured cost warrants one.

The normal-route Photos denial/retry and save tests now pass (26.715s/18.705s,
`/tmp/ledger-photos-original-navigation.log`). The actual staging root and its
workspace fixture now supply the NavigationStack missing from their ScrollView
composition. Existing Project/Inventory entry, detail/back/reentry and Account
removal pass25.768s (`/tmp/ledger-workspace-navigation-root.log`); attachment
viewer/share/withdrawal passes33.908s (`/tmp/ledger-navigation-attachment-consumers-back.log`).
Initial consumer failures exposed obsolete Done-button selectors and then the
missing workspace stack; tests now use the observed native Back control on iOS.
Item pinning/withdrawal and Transaction-to-Item physical history additionally
pass39.631s/21.809s (`/tmp/ledger-navigation-item-consumers.log`). The unsigned Mac
build passes (`/tmp/ledger-navigation-macos-build.log`); this is not Mac UI proof.
Mac navigation and other shared-root consumers still need verification.
The browser preserves selection intent across detail navigation, but clears its
rows and restores only IDs present in the next authorized, filtered result.
Invalidation clears that intent. Existing session tests plus one focused case
pass7tests0.019s (`/tmp/ledger-navigation-selection-native.log`); actual workspace
selection/detail/back/reentry/removal passes27.899s
(`/tmp/ledger-navigation-selection-scoped.log`). Earlier selection UI failures
also reproduced with the change removed: the unscoped amount selector hit the
bulk total instead of the card. The test now binds amount label plus card ID.
Temporary isolation fixtures were removed; the
normal-route tests remain. Earlier scene/feedback/alert-selector/cover/wrapper
experiments did not solve this bug and are not retained. No gallery/pinning
replacement, delay workaround, database change or Photos API change was needed.

Migration20260914173810 now replays successfully in the CLI's fresh shadow
database and its local history is reconciled:19 journal statements match the
reviewed migration, including the publication function and no drops
(`/tmp/ledger-attachment-publication-journal{,-verified}.log`). The installed
publisher body matches the file exactly; trigger authority/search paths remain
as specified. The default comparison failed on a local-only replication role;
the alternative migra comparison completed
(`/tmp/ledger-attachment-publication-replay-migra.{log,sql}`). Its output still
contains pre-existing local-role grants, re-emitted read/admission functions and
private-trigger visibility/drop artifacts, not an empty schema diff. None of
that generated SQL was applied. No current schema/data reset or UI/retention
policy change was made.

Deferred attachment consistency checks run after the publishing function returns,
so they require their own database authority. The attachment consistency validator
and three routing triggers now use definer authority with an empty search path
and no API execution grants; the parent-propagation trigger remains an invoker.
These triggers derive or validate canonical relationships and grant no client
mutation capability. Exact privilege tests and local security advisors cover the
boundary. The shared SQL suite passes 1,380 assertions
(`/tmp/ledger-attachment-resume-sql-final.log`); six native transport/publication
tests pass (`/tmp/ledger-attachment-resume-native-final.log`, with the separate
real-service test skipped there). Later queue/runtime and fresh-replay evidence
is recorded above; these earlier scoped checks alone are not whole-app readiness.

The real local service test also passes missing-file verification before upload,
interruption after six MiB, HEAD resume, exact-byte readback, concurrent verifier
calls returning the same result, one published reference, and allowed/denied
member access (`/tmp/ledger-attachment-resume-local-service-final.log`). Its first
run exposed Storage's HTTP 400 / `NoSuchKey` / payload 404 convention; only that
specific response now means incomplete upload. Other failures remain errors.

Local pgTAP evidence is
`/tmp/ledger-upload-intent.ymUIoG/tests-final-39.log` (39 assertions), including
retry identity, cross-Account and financial visibility, membership removal,
capacity, Storage-path and privilege checks. The shared database suite passed
1,351 assertions before the four final guard assertions were added; those four
then passed in the focused file. Security advisors reported no issues. Migration
`20260914171121_transaction_attachment_upload_reservation.sql` is a reviewed,
upload-only replacement for an unsafe generated diff that was never executed;
the corrected local journal contains 16 statements and no table drop. Fresh
replay produced the known environment/private-function diff artifacts plus
function formatting, not an empty diff. Actual TUS transfer, server byte
verification, publication, result readback and queue drainage remain unfinished.

Transaction reference pinning (D-032): extract the original `PinnedImageLayout`
into `PinnedImageLayoutPresentation`, retaining its compact split, resize gesture
and regular-width sidebar. The original wrapper still supplies its original
panel; the target supplies authorized attachments to existing
`PinnedImagePresentation`, `DownloadedMediaPhotoView` and PDFKit. The original
PDF viewer's loading/error/rendering content is shared as
`PDFDocumentPresentation`. No second pin layout, zoom renderer, pin database or
Firebase adapter is introduced. The target's view-local selection watches the
original Transaction/catalog revision and closes when that evidence or access is
withdrawn. Image paging stays within that section's images; PDFs retain PDFKit
navigation and do not expose photo matching. Physical bytes remain the existing
protected reader's responsibility.

Initial pin UI failures in `/tmp/ledger-transaction-pin-ios.log` and
`/tmp/ledger-transaction-pin-ios-stable-watch.log` did not establish missing pins:
the latter hierarchy shows the panel, Unpin, image counter and detail. Its outer
identifier propagated over child control identifiers. Explicit accessibility
containment corrects that boundary; the earlier Group-to-ZStack change alone did
not solve it. Focused image/PDF pin and existing viewer verification is in
`/tmp/ledger-transaction-pin-pdf-ios.log`: existing viewer/share passed33.857s;
pin failed a helper targeting the workspace instead of the Transaction scroll.
The scoped/fixed-drag attempts retain resize assertion failures. Their hierarchy
showed image growth and 33→38 percent; the accessibility container's safe-area
height was offset by navigation-title collapse. The test now measures rendered
image growth, not that container. `/tmp/ledger-transaction-pin-pdf-ios-rendered.log`
passed the full pin scenario39.330s: image paging/resize, gallery reopen, PDF pin,
unpin and image-access withdrawal. `/tmp/ledger-transaction-pin-macos-build.log`
built successfully; this is not Mac UI proof. This integration does not complete annotations, mutations, actual-runtime
viewer delivery or the overall Transaction workflow.

Photos-save investigation remains unresolved. `/tmp/ledger-transaction-photos-ios.log`
passes existing Item denial/save but fails Transaction viewer continuity after
the expected notice. Native byte readback in `-byte-readback.log` matches the
synthetic Transaction PNG exactly (68 bytes), on disposable Simulator
00856A66-A552-41B8-B9DC-1E6EA1E6DBFC, never the user's library.

Outer/viewer alert relocation, a bound host, gallery feedback input, explicit
body reads, reference feedback, active-scene gating, local message transfer and
a separate presented export owner did NOT fix the new tests. All experimental
production changes and diagnostics were removed, restoring the pre-investigation
presentation/export code; only the new tests and evidence remain. Do not treat
those hypotheses as accepted architecture. Failed logs use the same prefix with
suffixes `-ios-{viewer-alert,bound-feedback,shared-alert-booted,observed-feedback,
feedback-owner,active-feedback,local-feedback,presented-owner-clean}.log`.
`-ios-shared-alert.log` instead failed runner UIKit bootstrap before tests;
`-ios-presented-owner.log` failed actor-isolation compilation, not UI behavior.

`-lifetime.log` proves live generation, selected image and nonnil export notice;
`-presentation.log` and `-alert-stack.log` show UIKit creating, hiding/re-showing
and dismissing a PlatformAlertController. Gating on active scene changed that
timing but did not prevent dismissal. The exact dismissal cause is not established.
Next diagnosis must trace dismissal/acknowledgment directly (including whether
automation triggers it), not repeat speculative structural patches or broad UI
runs.

The subsequent direct callback trace (`/tmp/ledger-transaction-photos-dismiss-callbacks.log`)
shows the full-screen selection cleared before the explicit OK action; neither
the gallery's isPresented setter nor section disappearance fired. Transaction Save
now calls the existing gallery's async `onSaveImage` contract, with the same
authorized operation extracted as `performExport`; errors return to the existing
gallery feedback instead of a new alert channel. This is reuse of the original
contract, not a new viewer. `-ios-existing-save-callback.log` still fails notice
visibility, so this is NOT a verified fix. All tracing code was removed. Manual
reproduction is gated on desktop unlock, requested non-blockingly; no password
or production access is needed.

D-031 Mac file save is now wired in both Item and Transaction galleries. Extract
`PDFDownloadHelper.selectDestination` from its existing NSSavePanel; the original
PDF wrapper calls the same picker. The target shares the existing native delivery
lock, suggests a basename with the MIME type's extension, treats cancellation as
non-error, revalidates after selection and byte loading, and hands original bytes
to an asynchronous atomic file write. UI stays responsive; completion/busy state
waits for the write, not just picker dismissal. External copies remain user-owned
after handoff. No image renderer, new cache, backend permission or PDF importer is
introduced.

`/tmp/ledger-image-file-save-native.log` passes13tests/2suites0.114s. The existing
export test now checks5phases with a real temporary destination: before/after
selection and after-load denial plus cancellation preserve existing file bytes;
success replaces them with the exact input. This injects the selection step and
does NOT prove NSSavePanel interaction. Project generation and iOS build passed;
final Mac build passed (`BUILD SUCCEEDED` in `/tmp/ledger-image-file-save-macos-final.log`). Actual picker,
overwrite/error feedback and signed/sandboxed release behavior remain unverified.
The staging project currently declares no app-sandbox entitlements; the original
app's entitlements are not target proof and were not imported or changed.

The existing `spike_transactions` table previously represented only immutable
imported client payments. Extend that same Transaction owner for ordinary vendor
Purchases/Returns in Project or Inventory scope. Keep embedded non-Item receipt
lines on the Transaction, with exact signed minor-unit evidence and source
wording/quantity. Do not turn client-payment amounts or project charge prices
into vendor purchase costs. Authority: `docs/plans/non-item-receipt-lines/design.md`
and `docs/specs/invoice-centered-project-accounting.md`.

`transaction_receipt_items` retains one relationship per Transaction/physical
Item, its receipt-basis amount (nullable when unknown), and linked/returned/sold
membership. This preserves historical receipt contributions without copying
physical Items or replacing placement/lineage. It is not a second generic history
system. Future writers and migration must supply authoritative amounts and retain
these relationships; this read implementation does not infer missing prices.

Transaction Item groups reuse the original `GroupedItemCard` with an injected
protected thumbnail and share the existing downloaded-Item grouping algorithm.
Recorded source plus SKU/name identifies presentation groups; current source is
only a display override. Membership sections remain separate, expansion keeps
every physical Item ID, and totals use exact receipt-basis amounts (unknown stays
unknown). The invoker receipt view and native/MCP snapshots expose existing source,
current Space and image-set count fields. The existing receipt stream also supplies
the active placement (including Items now elsewhere), its Space and image-set
marker under the same receipt/category/tenant authorization. No new tables or
write authority are introduced. Groups select the first Item with image evidence
without downloading every child's media; its existing protected image reader still
owns bytes and loading failures. Current Space labels never rewrite receipt costs.
Client-payment Item detail composition remains incomplete.
Verification is recorded under TX-GROUP in the unified checklist.

Payment contents use retained Item/payment connection intervals and the existing
sealed Invoice contents, not `currentItemCategories`. That current-only query
cannot establish historical paid membership after an Item leaves a Project.
The full-financial-member connection read policy now includes closed intervals;
existing physical reports continue filtering current links/placements explicitly.
Frozen Invoice reads reuse their existing invoker loader and RLS, with the needed
read columns granted to authenticated callers; no store/write permissions change.
`FrozenInvoiceStorageRecord` and its unchanged validation tests move from the
migration module into Core so migration and app reads share exact source, amount,
category and description decoding. `TransactionPaymentContents` binds that history
to the exact principal, Account, Project, Client and Purchase, deduplicating only
display Item IDs, never historical connections or frozen lines. It does not infer
vendor costs, apportion lump-sum cash or settle O-033.

The existing browser/detail RPC now composes that view. Its scoped PowerSync
stream includes closed connections and every sealed Invoice line (Item, Expense
and Fee), not only currently placed Item charges. Overlapping report streams use
identical full row projections; their current-eligibility filters remain unchanged.
Frozen amounts/revisions/source JSON travel as text; SQLite keeps its existing
exact integer source-revision column. The native reader joins these facts in the
same completed scope snapshot and reuses the Core decoder. MCP requires Node 24
to validate embedded Int64 JSON from its original numeric token, avoiding a lossy
JavaScript Number conversion. Native/MCP share a frozen-payment fixture and reject
scope, source and total mismatches. No new tables, writers or collection policy.
Actual local HTTP/PowerSync/native encrypted-reopen and removal evidence is under
TX-PAYMENT-CONTENTS. Current Item metadata is now a separate typed value shared
by vendor and payment cards. Its supplied membership must exactly match retained
links/frozen Item lines; missing metadata is not an empty Item list. The same
stream supplies current Item/Space/image-set metadata even after an Item moves
elsewhere, under full financial access. It uses existing table projections, not
another Item/history store. Payment counts use retained membership rather than
current category attachments. The existing ItemCard/GroupedItemCard and history
view serve both sources. Frozen descriptions and exact amounts appear in a
Collected Invoice section using existing detail rows; payment cash is never
apportioned into invented Item costs. iPhone flow and existing grouping checks
passed; the new Mac history-navigation check remains unverified after a system
security-dialog interruption. This does not complete the whole workflow.

Transaction Receipts and Other Images use section-specific current-set markers
and references (`transaction_attachment_sets` / `transaction_attachment_references`).
Those facts retain filenames, ordering and primary choice separately from immutable
byte identity. They reuse `item_image_objects` despite its compatibility name: it
already stores Account/object/hash/path, not an Item parent. Explicit PDF objects
now share the existing protected transport and encrypted cache; default image
callers and Item image-reference constraints remain image-only. This avoids another
object store, byte queue or PDF-specific vault. No capture, detach, deletion or
retention policy is decided by this read path.

Transaction RLS controls section/reference reads; only current references expose
objects and private authenticated Storage GET. The scope-wide Transaction stream
is configured for the same metadata and exact text revisions/byte counts, but
initial actual replication failed the pinned service's dynamic-parameter limit.
Diagnosis found existing physical Item/Space/category joins were also responsible,
not just the new attachment queries. The running service's own parser (0.40.0,
now also pinned for local checks) showed 6,555 raw bucket candidates / 1,489 parameter results
with only 50 additional Items. Rewriting JOIN as IN alone did not solve this.

**Scalability correction:** Reuse the existing Account-member physical read
authorization directly for Item labels, image-set counts, current placements and
active/still-used Spaces within the Transaction subscription. These are the same
explicit columns as `physical_account_items`, not all Account financial data or
image bytes. Eight separate vendor/payment metadata queries become four. Their
completed Transaction checkpoint still covers the required metadata, so callers
do not need to visit the Items tab first or coordinate another readiness flag.
Tradeoff: the subscription also downloads authorized physical metadata not linked
to its particular Transactions. It does not download their receipt relationships,
amounts, Invoice contents or attachment objects without financial authorization.
This supersedes the earlier receipt-filtered physical-metadata description above.

Project Item-category rows use their existing category/member RLS scope, including
retained attributions; the local current-category query still joins only active
placements. This avoids a parameter lookup for every Item merely to obtain its
category label. Payment-connection queries also remove a redundant placement join:
the exact composite FK and placement scope CHECK already guarantee that parent.
Closed payment intervals and frozen Invoice contents remain full-financial-only.
No schema, grants, monetary facts, Item identity or product policy changes here.

This follows PowerSync's documented [scope-key guidance](https://docs.powersync.com/sync/advanced/reducing-bucket-count#denormalizing-the-scope-key):
the partition key must exist on the source row; correlated joins and subqueries
do not change that. Ledger already has the authorized Account key on these rows.
The test-only service evaluator and existing local integration fixture now measure
both [service limits](https://docs.powersync.com/sync/streams/bucket-count#limits),
plus assert that all scaled Item/category/receipt rows remain selected. Earlier
700-Item and 7,000-Item budget estimates are superseded: the evaluator incorrectly
deduplicated equal parameter values from different source rows, and then captured
only selected test Accounts. Actual service storage preserves those source rows.
The corrected evaluator includes all explicit Sync source tables in the isolated
local database, retains duplicate parameter values, and separately deduplicates
bucket IDs. Small native/offline evidence remains valid only for its tested rules.
Explicit Account indexes, supported IFNULL for nullable Project matching and a
positive same-row origin CASE reduce needless compiler branch expansion while
preserving scope/origin checks. Cross-table permission CASE is unsupported and
was reverted; ordinary/full permission predicates remain intact. Latest rule
tuning requires actual-service proof as well as parser/raw-SQL checks. No new
shared native subscription or readiness coordinator has been implemented.

**Derived Space predicate:** `20260914115106_space_sync_current_item_count.sql`
adds a server-maintained count of current Item placements per Space. The existing
immutable placement history remains authority; this count only lets all three
Space streams include active or still-used archived Spaces without enumerating
every placement during subscription authorization. A locked transactional backfill
and statement-level invoker triggers maintain exact increments/decrements; sorted
Space updates avoid inconsistent lock order within a statement. Existing placement
guards prohibit reopening/reparenting/deletion. Ordinary user roles get no count
write permission, RLS remains placement-based, and the counter is neither projected
to native clients nor allowed to bump the user-visible Space revision. Tradeoff:
one derived column and trigger maintenance instead of per-Item parameter growth.
The local SQL suite, fresh migration replay, exact function-body review and
concurrent insert/close checks cover this boundary; exact results belong to
TX-ATTACHMENTS, not a new progress record.

Default category/allocation queries now resolve authorized Account/category sets
directly instead of enumerating unrelated category rows before authorization.
Their selected IDs are checked against actual RLS for full, restricted, foreign
and removed users. No financial policy changes. The corrected 10-Project/
7,000-Item simulation fits at 973 parameter rows / 131 unique buckets. Actual
service download subsequently completed all five checked Item/relationship
tables in 4.546s; the native offline/reopen/category-replay/removal test also
passed on these rules. This narrow shape has little headroom: spreading the same
Items across 100 vendor Transactions preserves row coverage but needs 1,423
parameter rows / 311 unique buckets, exceeding the 1,000 parameter limit.
That failure motivated the following routing correction; it is not erased by a
passing smaller fixture. The Invoice follow-up is recorded below. Do not raise
limits, omit required offline data, or claim release readiness.

**Scoped Transaction child routing:** `20260914122550_transaction_sync_routing.sql`
adds derived scope/Project/category fields to the existing receipt Item links,
attachment section markers and attachment references. Private invoker triggers
read the exact canonical Transaction under a shared row lock; parent changes
propagate in the same transaction. Current-reference eligibility derives from the
exact marker revision, including withdrawal of retained older references. No
original link, revision, amount, Item identity or attachment history is replaced.
Locked installation/backfill prevents a partially routed migration. Existing RLS
still checks canonical parents; no public writer, new permission policy or broader
financial download scope is introduced. Concurrent conflicting writes may abort
and need transaction retry; this does not implement an attachment write workflow.

References also carry the four immutable object descriptor values (hash, byte
count, media type and path) already authorized for that current reference. This
removes a second per-object lookup without another object store or byte cache.
The native attachment reader uses those fields to construct the same protected
object reference; missing/invalid descriptors remain incomplete, not empty or
downloadable. Item image streams and canonical object/Storage authorization stay
unchanged. Tradeoff: modest derived data on child rows plus four small maintenance
functions instead of unbounded Transaction/marker/object parameter enumeration.
Direct tampering is overwritten from canonical parents; immutable object guards
ensure descriptors cannot become stale through object edits.

Queries decrease from 19 to 17, and total outputs from 67 queries to 65 with the
same 29 source tables. With 7,000 Items, 1,000 vendor Transactions and 4,995 current
attachment descriptors, the corrected source evaluator retains every checked row
at 535 parameter results / 144 unique buckets, the same budget as the 100-Transaction
case. SQL1295 and focused native offline/reopen cases pass. The actual service
completed that heavy download in 23.135s; the native SDK's encrypted reopen,
category replay and removal check also passed. Separate database connections
proved both parent-first and child-first lock contention preserve child routing
and amounts. The following Invoice and byte checks extend this evidence; viewer
integration remains incomplete. Generated schema-diff drops caused
by the CLI role's limited visibility are not migration authority: reviewed SQL
retains existing tables/views/functions and excludes local service grants/roles.
**Frozen Invoice line routing:** the same 1,000-Invoice test initially required
1,535 parameter rows / 1,144 buckets. Migration
`20260914124147_invoice_line_sync_routing.sql` adds only a derived immutable
`sync_project_id` to frozen lines. It backfills under an exclusive table lock,
temporarily disabling only the immutable-line trigger inside that transaction,
and derives new values in the existing parent-locking insert guard. Committed
headers and lines cannot move or change, so no propagation function is needed.
The stream replaces its per-Invoice join with that Project field, preserving
Account, principal and full-financial-access checks. It relies on the existing
deferred completeness constraint: no unsealed header or incomplete Invoice can
commit. Thus removing the joined `sealed` predicate does not expose drafts in
committed replication. It does not introduce Invoice collection functionality.
The combined 7,000-Item / 1,000-vendor-Transaction / 4,995-attachment /
1,000-frozen-Invoice fixture retained all required rows and amounts with 514
parameter rows / 143 buckets; the actual local service completed in 3.583s.
SQL1298 includes derived-scope and still-enabled immutability tests. Fresh replay,
installed insert-guard body/invoker/search-path comparison and all55 migration
versions match. The existing Space performance warning remains; no generated
environment/function-visibility drops or grants were applied.

The native reader
reuses Transaction scope, category-overlay, membership and completed-stream checks
inside the same SQLite read as the attachment catalog. Missing markers or missing
objects are incomplete, never an empty gallery; retained old revisions cannot
become current evidence. The existing runtime owns the finite read lease and
Account-removal fence. The tradeoff is preserving a historical table/cache name
and reusing the full Transaction read check rather than adding another permission
implementation. Transaction byte loading now extracts and shares the existing
Item cache/download sequence, with its own finite runtime lease. Exact section
revision/reference, current Transaction/category/membership and removal fence are
checked around cache/network awaits. Revocation during a write may leave protected
cached bytes but never returns them; cached presence alone grants no access.
The unchanged real vault verifies hash/length and encrypted restart. Native tests
inject revision, reference, membership, category, parent-scope and access removal
at cache-read, download and cache-write boundaries in both Project and Inventory.
Existing Item original/thumbnail and encrypted-PDF tests pass after extraction.
No second byte store, transport or viewer was introduced. The live attachment
watch now owns the existing Transaction subscription and workspace stream task;
changes to references/markers, Transaction/category/membership and local category
operations invalidate the catalog. Nil withdraws displayed media; an incomplete
catalog remains explicitly incomplete. Native Project/Inventory watch tests cover
reference changes, revision withdrawal, Fee/General access restoration and removal;
runtime tests cover wrong-Account admission and cancellation before database close.

Presentation reuses `ThumbnailGrid.swift`, `PDFViewerSheet.swift` and
`ImageGalleryPresentation` by moving their backend-dependent inputs outside the
original layout. The legacy wrappers remain behind the same compilation boundary
used by the original card extractions. The existing decoded-image adapter in
`DownloadedItemImagesView.swift` is shared with Transaction images; no new image
decoder, gestures, PDF renderer, byte cache or transport. That file's inclusion in
this workflow covers this extraction, not acceptance of its inherited unfinished
Item gallery work. `TransactionAttachmentsSection` supplies current references and
protected bytes and withdraws an open selection on revision/access changes.
Sharing, saving, pinning and attachment mutation remain incomplete. Focused
iPhone read integration passed: decoded PDF, existing image gallery, close/reentry,
Other Images and withdrawal. Native watch/admission tests passed in both scopes.
The first iPhone run failed test selectors (PDFKit accessibility and counted header
labels); the corrected test asserts the real decoded PDF page count. macOS builds,
but its UI runner could not enable automation while the desktop was locked; no
macOS UI pass is claimed. Existing Item-gallery/browser consumer checks also
passed on iPhone after the shared extraction (145.837s and25.945s), including the
Item gallery's original zoom/navigation/pinning/close behavior. Exact runs remain
in the checklist/state; this is not whole-workflow or hosted readiness.
MCP attachment reads use an explicit paginated `get_transaction_attachments`
tool on the existing Transaction reader, rather than embedding all attachments
in every `get_transaction_detail` response as the earlier resume note proposed.
This implements the bounded-response/continuation requirements in
`docs/specs/mcp-interface.md` without a new backend, table or parallel reader.
The invoker RPC returns only public reference IDs, order, primary status, kind
and filename; it never returns Storage paths, object credentials or bytes.
Pages are limited to 100 references and the MCP reader caps decoded responses
at 2 MiB. Continuation requires the same exact revision; a changed revision
returns HTTP 409 so callers restart instead of combining different sets.
Unknown remains distinct from known-empty. Existing Transaction RLS remains
authority, including current-category visibility and membership removal.
`PT409`, not `40001`, expresses this product conflict: the latter can trigger
PostgREST transaction retries, rather than a caller-visible pagination conflict.
No schema, writer or Sync Stream expansion accompanies this read API.

Verification: `/tmp/ledger-transaction-attachment-page-sql.log` passes 44 files /
1,316 assertions; `-mcp.log` passes 18 MCP tests, and `-mcp-reviewed.log` passes
the six attachment tests after malformed-revision hardening. `-types-reviewed.log`
passes. `-http-access.log` proves actual HTTP metadata, empty sets, stale-revision
409, hidden/foreign denial, General restoration and same-token removal denial.
Migration `20260914132953_transaction_attachment_page.sql` replayed successfully
(`-fresh-schema.log`). Direct catalog comparison confirms its function body,
invoker/stable/empty-search-path properties and authenticated-only execute ACL.
The diff re-emits the identical function body plus existing environment/role
artifacts; it is not an empty schema diff and none of its suggested drops were
applied. The 56-version local migration journal matches the files. Advisors
retain only the existing Space policy warning. The initial multi-statement CLI
query failed before application; the existing local psql fallback succeeded.
TX-ATTACHMENTS retains actual runtime-to-viewer byte integration, protected
share/save/pin, capture/upload/detach and retention evidence as unfinished.
No UI replacement, hosted readiness or complete media workflow is claimed.

**Attachment delivery reuse:** Transaction image Share/Save now calls the same
native sharing/Photos adapters as Item images. `AuthorizedMediaExport` extracts
the existing permission → authorized-byte-read → destination sequence; each
caller validates its live selection before and after awaits. Item API/error names
remain compatible. PDF sharing uses `ProtectedReportDelivery`/`ReportScratchStore`,
not a second temporary-file implementation. It verifies the selected bytes' hash
and count, re-reads current Transaction attachment access after file creation,
and checks the visible selection immediately before system handoff. Completion,
not view disappearance or task cancellation, owns scratch cleanup. Pinning and
actual Photos permission/save UI evidence remain unfinished.

The iPhone integration exposed a pre-existing scratch-store Simulator limitation,
not a replacement PDF renderer defect. A small native Simulator syscall probe
isolated it: `F_SETPROTECTIONCLASS` accepts class A on directories but subsequent
file creation returns EPERM; setting class A on a regular file also returns EPERM
(`/tmp/ledger-transaction-attachment-scratch-syscalls{-rdwr,}.log`). The speculative
trusted-parent traversal edit did not fix it and was reverted. Simulator builds
now exercise real 0700/0600 ownership, authorization and completion cleanup without
claiming hardware Data Protection. Physical iOS builds still require class A with
no fallback; device lock/unlock proof remains a release prerequisite. Apple's
[complete-protection contract](https://developer.apple.com/documentation/foundation/fileprotectiontype/complete)
requires encrypted files to be inaccessible while locked; a Simulator UI pass
cannot prove that. Failure values now distinguish protection failures and retain
operation/errno context without exposing document contents or paths.

Focused final native delivery checks pass 22 tests / five suites in 0.132s
(`/tmp/ledger-transaction-attachment-delivery-final-native.log`): Item consumer,
Transaction permission/download withdrawal, PDF stale/denied/changed-byte rejection,
retention through cancellation/system failure, and scratch ownership/recovery.
Initial iPhone failures remain in `/tmp/ledger-transaction-attachment-delivery-ios*.log`;
the first supported-Simulator run also failed because the previous empty test
scratch root retained that setting. Only that exact empty generated directory
was removed (no app data or attachments). `-ios-recovered.log` then passed both
named tests: Transaction PDF/image Share and cancellation/reentry/Other Images/
withdrawal (33.319s), and existing report Share/Print cancellation (47.383s).
This proves synthetic Simulator interaction and shared file lifetime, not physical
Data Protection, actual Photos saving or production/hosted data integration.
The affected Mac target also builds (`-delivery-macos-build.log`); Mac interaction
verification remains separate from that build result.

The invoker read RPC returns one authorized snapshot, including current category
and complete Item membership. Category RLS controls visibility, including archived
categories and normal Fee-to-General visibility. Audit applicability follows
current kind; exact Item-plus-line arithmetic remains the existing domain helper.
No persisted completion flag, tax inference, draft/posting gate or new financial
write grant is introduced. Native and MCP readers bind the result to the requested
Account/principal/Transaction. Online snapshot completeness must not be assumed
for partial PowerSync delivery; local completeness and UI binding remain required.

Imported payment immutability remains intact. An additional Invoice link guard
rejects vendor Purchases as collection payments. Its currently allowed origin is
the implemented imported-payment origin; the future collection command must
explicitly add its own verified payment origin, not reuse `vendor_payment`.

Verification: the local schema passed 1,130 assertions across 37 SQL files,
including 35 receipt authorization/history assertions
(`/tmp/ledger-transaction-receipt-sql-policy-reviewed.log`). Real local HTTP/MCP
read, category visibility change and revocation passed
(`/tmp/ledger-transaction-receipt-local-http.log`). Advisors found only the existing
unrelated `spike_spaces` multiple-permissive-policy warning after the Transaction
policies were merged (`/tmp/ledger-transaction-receipt-advisors-reviewed.log`).
The `transaction_receipts` download is scoped to one Project or Inventory, not
one subscription per Transaction or an unconditional whole-Account financial
download. It includes receipt relationships after sale/return plus the category
and membership needed to authorize the read. `TransactionReceiptPowerSyncQuery`
reads those rows and the exact retained stream checkpoint in one transaction,
using the existing category projection for pending offline type edits. Shared
checkpoint and subscription-lifetime helpers are reused, with the original report
entry point retained for compatibility. No parallel completion registry is added.
The workspace runtime owns finite reads and live watches; removal/cancellation
uses its existing fencing and drainage. The SDK core-protocol test proves rows
without checkpoint completion cannot qualify, and completed Project/Inventory
evidence survives encrypted reopen. Live changes/rejection/unknown price/visibility
and removal pass with existing category/report consumers (21 tests,
`/tmp/ledger-transaction-receipt-offline-watch-consumers.log`). Actual checked-in
stream SQL scope/authorization/history cases pass locally
(`/tmp/ledger-transaction-receipt-stream-local-http.log`). These do not prove
hosted replication or UI integration. Initial compiler failures (generic helper
type inference and mutable non-Sendable capture) remain in
`/tmp/ledger-transaction-receipt-offline.log`; both were corrected without changing
the authorization/completeness requirements.

The original `TransactionAuditPanel` layout is extracted into provider-independent
presentation inputs, retaining its progress/detail/missing-Item structure and
original ProgressBar. Its source-only wrapper retains the legacy binding but is
not compiled into the target; this is UI reuse, not a Firebase backend adapter or
redesigned Firebase implementation. `TransactionReceiptAuditPresentation` supplies
the D-016 equation with exact Decimal-formatted money, history breakdowns and
explicit unknown values. General/Fee categories omit the audit panel; rounded bar
percentages never supply a verdict. Three pure presentation tests pass, including
one-cent residuals and amounts above Double's exact integer range
(`/tmp/ledger-transaction-audit-presentation.log`). The exact reused-panel/form
interaction test passes on Mac (1 test/24.072s) and iPhone (1 test/24.587s):
`/tmp/ledger-transaction-audit-ui-macos-fixed.log` and
`/tmp/ledger-transaction-audit-ui-ios-fixed.log`. Both initial runs failed only
the accessibility text assertion; the test now reads macOS `value` and iOS
`label`, without an app change. Initial failure logs retain the same names
without `-fixed`. The DEBUG interaction host is
component evidence only, not a replacement Transaction screen or proof that the
target's full Transaction route is complete. The live binding now connects the
existing runtime receipt watch to this same panel through a view-owned
`TransactionReceiptAuditSession`, without another cache or subscription owner.
Scope/principal/Transaction mismatches, incomplete reads, access withdrawal,
failure and cancellation clear prior financial values. SwiftUI identity includes
the runtime and full bound scope so switching detail inputs replaces local view
state. Four session tests pass in 0.008s
(`/tmp/ledger-transaction-audit-session.log`). The updated component fixture feeds
the same observing view through a synthetic stream; it does not prove hosted
replication. Its initial Mac run exposed observation attached to conditional
`Group` children: hiding General/Fee stopped later Itemized updates. Attaching
observation to a stable container fixes the real lifecycle issue; the unchanged
scenario passes Mac 1/21.322s
(`/tmp/ledger-transaction-audit-live-ui-macos-fixed.log`; failure preserved in
`/tmp/ledger-transaction-audit-live-ui-macos.log`). The same live-binding scenario
also passes iPhone 1/24.271s (`/tmp/ledger-transaction-audit-live-ui-ios.log`).
Actual Transaction routing still requires integration under its existing owner.

Item labels now travel with the authorized receipt snapshot rather than a second
caller-supplied lookup/dictionary. The RPC joins the permanent physical Item by
Account and Item ID; names/SKUs are current descriptive data, not frozen receipt
prices or a new Item/history store. Optional labels retain compatibility with
older snapshots; missing labels fall back to Item ID without inventing prices.
The receipt stream adds a fifth query for the existing `spike_items` projection,
identical to `physical_account_items` so overlapping subscriptions do not supply
competing partial rows. The native reader joins those downloaded records within
its existing authorized read transaction and observes Item changes. An initial
attempt to select joined-table label fields into receipt evidence was rejected
by the real PowerSync parser (`/tmp/ledger-receipt-labels-stream-parser.log`);
the corrected existing-table output passes six parser/projection checks
(`/tmp/ledger-receipt-labels-stream-parser-reviewed.log`). No new local table or
subscription owner is introduced. Security/index review retains same-account
joins, existing keyed Item lookup and unchanged invoker/RLS permissions.

Local evidence: 32 native tests/six suites pass in 3.833s, including encrypted
reopen, live rename/SKU changes, cross-account label refusal and unchanged
financial reconstruction (`/tmp/ledger-receipt-labels-native-reviewed.log`).
Six MCP tests and typecheck pass (`/tmp/ledger-receipt-labels-mcp.log`,
`/tmp/ledger-receipt-labels-mcp-types.log`). The same reused-panel scenario passes
Mac 1/21.980s and iPhone 1/24.084s (`/tmp/ledger-receipt-labels-ui-macos.log`,
`/tmp/ledger-receipt-labels-ui-ios.log`). At checkpoint501, revised SQL/HTTP
assertions were blocked by Docker's mount failure; earlier passes did not cover
these label changes. Recovery subsequently completed without data/configuration
deletion, coordinated with Boards after the normal restart timed out. Standing
user permission to restart Docker is recorded in AGENTS.md.

The revised RPC was applied locally (only its function/grants, not a blind full
migration replay). SQL37files/1130 assertions PASS
(`/tmp/ledger-receipt-labels-sql.log`); real local HTTP/category/receipt and all five
checked-in stream queries PASS (`/tmp/ledger-receipt-labels-local-http.log`).
Existing report-stream13projections/121captures PASS
(`/tmp/ledger-receipt-labels-report-stream.log`). Advisors exit0 with only the
pre-existing multiple-permissive-SELECT warning for `spike_spaces`
(`/tmp/ledger-receipt-labels-advisors.log`). A fresh shadow DB successfully applies
all checked-in migrations and has no public/ledger_private schema difference
from the working DB (`/tmp/ledger-category-migration-diff.log`). The subsequent
comparison includes `storage` and is also empty
(`/tmp/ledger-local-migration-storage-diff.log`); the existing attachments bucket
has its expected identity and remains private. Development history was missing
26 entries beginning20260908035218, predating this batch. After proving current
schema equivalence, `migration repair --local --status applied` repaired only
those local history entries, without replaying migrations or changing application
data (`/tmp/ledger-local-migration-history-repair.log`). All41 versions now match
(`/tmp/ledger-local-migration-history-verified.log`). `db pull --local` with
`--strict-coverage` over public/ledger_private/storage finds nothing to generate
(`/tmp/ledger-local-migration-pull-verified.log`): CLI exit1 carries
`LegacyDbPullInSyncError`/"No schema changes found", not a failed migration.
No migration file was created or rewritten by that check. This repairs the local
development journal; it neither claims historical execution timestamps nor
authorizes production migration.
The native authenticated HTTP adapter also preserves these labels and its
existing scope/denial handling (1 test/0.019s,
`/tmp/ledger-receipt-labels-native-http.log`). This uses intercepted HTTP, not the
local database (which has since recovered).

Local replication proof now uses `powersync/local-service.mjs` (Node24), pinned
PowerSync service1.24.0/digest, the checked-in streams, and only the verified
Ledger-local Docker network/database. It derives27 explicitly named source
tables from the installed stream parser. Separate replication/storage roles and
a separate local bucket database keep PowerSync's internal tables out of app
migrations. The service binds only127.0.0.1:5590; generated credentials/config
remain under ignored `tmp/ledger-powersync-local` with0700 directory/0600 files.
Existing resources are checked before reuse; no reset, hosted service, or
application-data migration is involved. Initial source validation rejected the
legitimate private-schema sources; the explicit allowlist now includes public
and ledger_private, never wildcard tables. Setup and repeat setup both pass
(`/tmp/ledger-local-powersync-start-reviewed.log`,
`/tmp/ledger-local-powersync-reentrant.log`).

Run the existing category local harness with Node24/tsx and
`--native-replication`. It now passes real service download, an offline type edit,
encrypted close/reopen, reconnect/upload, replicated operation acknowledgement
and authoritative receipt readback, then restoration of General classification.
No local rows/checkpoints are injected in this new native case. Existing
lost-response replay and Client/inline-category/Project checks also pass
(`/tmp/ledger-category-real-replication.log`); MCP typecheck completes without
errors (`/tmp/ledger-category-real-replication-mcp-types.log`). This closes the
split transport proof for this local category scenario, not hosted validation,
full Transaction routing, the complete authorization matrix, or batch acceptance.
A-003/A-004 remain proposed pending their complete vertical-spike requirements.

The same local replication case now also requests a populated foreign Account
directly through the SDK, intentionally bypassing the app scope guard, and waits
for the service checkpoint before asserting zero foreign rows in all five receipt
tables. A nonce-protected loopback test callback removes only the synthetic user's
membership; real replication withdraws its categories/Transactions/receipt links,
and native receipt reads and category edits fail closed. No privileged credential
is passed to Swift. This expanded single native case PASS
(`/tmp/ledger-category-live-access-boundary.log`), including the existing HTTP/SQL
checks in its parent harness. Fixture cleanup removes both exact synthetic Accounts.
`--native-replication` now selects only that case, avoiding order dependence on
the removed user's other SDK tests; `--native-auth-sdk` retains the separate
Client/Project/lost-response scenario and its earlier evidence. No production code
or stream policy changed for this security test.

Launcher review added rejection of Docker endpoint/context overrides and nonlocal
sockets before setup, plus exact checks of an existing container's loopback port,
Ledger-only network and read-only configuration mounts. Both override-denial
cases PASS (`/tmp/ledger-local-powersync-endpoint-guards.log`); normal local reuse
also PASS (`/tmp/ledger-local-powersync-reviewed-reentry.log`). No reset or
replacement container was needed.

Transaction Item links reuse the original `ItemCard` layout through explicit
presentation inputs and open the existing `DownloadedItemDetailView`; no second
Item detail or lineage store is introduced. Linked, returned and sold membership
selects the retained physical Item ID. Direct history entry owns the existing
authorized `physical_account_items` subscription, so visiting the Items tab first
is not a prerequisite. Downloaded evidence remains explicitly partial: missing
placements, labels and financial provenance are not invented or declared complete.
Cancellation drains late subscription cleanup; local offline/reopen and removal
proof lives with the Transaction workflow. Item mutation, grouping and full media
behavior retain their existing owners and unfinished acceptance.

Project Transactions use the existing workspace route model, including Back,
archived history and Project-evidence withdrawal. A NavigationLink alone did not
work in the workspace's non-NavigationStack composition. This adapts navigation,
not the shared screen layouts or financial authority.

Transaction CSV adaptation reuses the original serializer with backend-neutral
row/column inputs. Formatting is pure: it cannot authorize rows, determine
readiness, or fetch receipt assets. Exact integer formatting replaces Double
money conversion; user-text formula protection is separate from numeric cells.
The configured legacy overload delegates to the same serializer. Export delivery
still requires the complete authorized snapshot and existing protected-scratch
lifetime; the browser's current `partial` coverage is not export readiness.
Raw receipt URLs and unresolved column semantics must not bypass that boundary.
`TransactionExportSnapshot` binds the same display/receipt records to the complete
authorized source, principal, scope, ordered selection, as-of and source/authority
versions. Partial updates are rejected. Its delivery adapter reuses
`ProtectedReportDelivery` and requires fresh matching readback before handing
bytes to the system; no second scratch store or cleanup protocol is introduced.
The original `ExportFieldConfig` now separates its unchanged 20 field labels,
order and eight defaults from source-model extraction so the selector can be
reused. Target values preserve unknowns, exact money and ordered readable/JSON
receipt lines; unsupported legacy fields fail explicitly, not as blank exports.
This does not retire those fields or settle status/payable/receipt-sharing policy.
The export provider now reuses the existing auto-subscribed Project directory and
scoped receipt download. One SQLite read checks parent/Client identity, membership,
both retained checkpoints, categories and receipt facts; the financial checkpoint
cannot predate the directory/permission checkpoint, compared at SDK microsecond
precision. It rejects unexplained missing categories or unsupported local origins.
Runtime finite leases provide the existing Account/closure fencing. No new stream,
table, permission grant or generic completeness registry is introduced.
Completeness here means all authorized rows in the current server data contract,
not implemented future accounting writers. The local HTTP harness checks that the
validated origin constraint still allows exactly the two supported origins; adding
an origin requires updating native/MCP/stream coverage. Browser product coverage
continues to be labelled partial. Real local service export/readback and encrypted
offline reopen pass (`/tmp/ledger-transaction-export-live.log`), including processed
order and removal denial. Eight provider/checkpoint/runtime tests pass, including
the existing report consumer and one-microsecond negative ordering case
(`/tmp/ledger-transaction-export-provider-reviewed.log`). Full field-data coverage,
selector binding and actual system delivery remain unfinished.
The target overload now feeds the original serializer directly. Its rectangular
CSV has one tagged manifest row followed by ordered Transaction rows; mandatory
stable ID/currency columns preserve interpretation regardless of selected fields.
The manifest records scope, principal, as-of, source/snapshot/authority versions
and selections, including a genuinely empty or no-match export. Unavailable fields
fail even with zero rows, and no receipt URLs are generated. This format follows
the existing report convention of explicitly typed metadata rows, not a new export
product. A hostless Xcode unit-test target compiles the original CSV/field files
against the actual target core, avoiding duplicate implementations or UI automation
for file-content checks. Three tests pass in0.006s; regular CI includes that small
target independently of its UI selector. No new runtime module was introduced.

Project export now binds the original `ExportTransactionsModal` sheet body and
Project Options menu to the existing authorized reader and protected delivery.
The parent holds its download watch through system completion, not merely while
the selector is visible. Transactions captures its processed IDs and full source
rows; source-hash mismatch rejects stale or partial selections. Other Project
routes request all rows. Scope changes/cancellation fence late reads; OS completion
still owns scratch cleanup. Original fields/defaults remain, with additional
non-default receipt-evidence fields. Unimplemented field data is explicitly
rejected, not silently omitted or retired; the default export is not release-ready
until Receipt Images is implemented. Platform evidence and remaining gaps belong
to TX-EXPORT/TX-UI in the existing checklist.

Retained legacy subtotal and tax-rate metadata stays nullable on the same
Transaction, separate from receipt reconstruction. Subtotal uses exact minor units;
the rate uses finite Postgres numeric and text on the wire/local store, avoiding
floating-point loss. Missing metadata remains unknown: no back-solving from tax
lines, new tax policy, writer permission or stored audit flag. The invoker display
view and existing three stream projections expose the same authorized values.
The generated migration explicitly retains column grants and invoker security,
excluding local-only replication-role grants. Export and source-version hashing
consume these facts directly. Purchased By follows canonical scope ownership,
including Returns. Local SQL, native, MCP, shared CSV and actual replication
evidence is recorded in TX-DATA/TX-EXPORT/TX-SYNC, not a separate tracker.

Current Item-category export reads existing Project placements and category
attribution, joined to currently linked vendor receipt Items or active client-payment
connections. Historical receipt evidence stays intact; missing/hidden attribution
blocks that field instead of defaulting to the Transaction category. An invoker
view and one scope-wide local query share this meaning. Three existing relationship
projections join the Transaction stream, matching the physical-report outputs;
no stored category/history copy or report-sized financial subscription is added.
Live replication omitted generated connection type/role values. Both projections
now emit the exact `purchase`/`standalone` constants enforced by their generated
columns/composite FK. No write or visibility permissions change. Verification
and gaps remain in TX-EXPORT/TX-DATA/TX-SYNC.

Screen integration now proceeds under the Transactions record. One workspace-owned
watch supplies canonical display snapshots to the existing cards and selected
detail; there is no separate detail cache or duplicate Transaction entity. The
original hero and grouped-filter shell take display inputs, while the original
search bar, Notes/Details controls and audit panel remain shared. Project and
Inventory entry points bind the scope explicitly; Inventory never gains a synthetic
Project identity or Project-only select-all.

Scope-wide payment reads now separate financial authorization from Item context:
active full-financial Account members can read imported client payments without
requiring a currently placed Item. Otherwise standalone payments and history after
an Item leaves a Project would disappear. `financial-access-controls.md` owns this
authority; unclassified imported payments remain full-only, and O-060 is not
resolved for mixed collected visibility. Existing Item/payment connections and
placement/lineage evidence remain intact, with their own contextual queries.
Vendor reads still follow current category visibility. No writer grants, source
bytes or accounting locks change.

Browser rows now carry the same optional receipt evidence as the dedicated audit
reader. List/detail/audit RPCs share an explicit invoker receipt view; the local
browser loads scope-wide Item evidence once within its existing SQLite read
transaction and completed subscription, not once per card. Cards, audit filters
and selected detail use `TransactionReceiptSnapshot`'s existing exact calculation.
Selected detail therefore needs no separate receipt subscription or cache.
Embedded receipt identity, scope, amount and category revision must match its
display row; missing evidence is not a zero-Item or balanced receipt.

Card Item count preserves currently linked membership; returned/sold Items remain
in the audit and history. Receipt Audit filters/badges explicitly describe balance,
missing prices or missing download, not whole-Transaction completeness, posting
permission or Review-queue membership. O-029/O-032/O-063 still own those unresolved
behaviors. No persisted audit flag or second arithmetic implementation is added.
The extracted filter shell now supplies a concrete zero-size presentation anchor
instead of `EmptyView`. The focused Mac test reproduced a disabled window with no
sheet; the anchor fix passed the same open/select/dismiss/reset interaction. It
changes hosting, not the original menu controls or layout.

List/detail RPCs share one explicit security-invoker display view, preserving
underlying RLS and column grants. The existing scoped receipt download also carries
imported payments (identical projection to overlapping Item subscriptions), avoiding
a second download/cache for the browser. Vendor receipt evidence remains distinct;
imported payments do not acquire receipt Items or an invented category. Native
reads recheck local financial membership to suppress stale rows after downgrade.

This is still partial implementation: the current stream covers vendor Purchases,
Returns and imported client payments, so even zero downloaded rows remain a
**partial list**, not an authoritative empty Transaction workspace. New Invoice collection, Transfers,
remaining filters/actions, Item/media integration and full route verification are
unfinished. Unknown metadata stays unknown; date-sort fallback does not overwrite
the displayed Transaction date. Existing financial locks and Item/payment history
are unchanged. Component/model/local-query evidence belongs to the Transactions
record, not category-management completion. Continue the approved dependencies
without routine scope approval; retain the outstanding category integration checks.

Native/shared-contract evidence and remaining integration status belong to
`CATEGORY-ACCOUNTING` in the existing product checklist. The initially unrecorded
local draft now has the schema-equivalence, fresh migration and repaired-history
proof above; actual Transaction routing and the coherent batch gate remain open.

## Decision Summary

| ID | Status | Decision |
|---|---|---|
| A-036 | accepted | Canonical vendor Transaction receipt evidence, separate from collected client payments |
| A-001 | accepted | Use domain-oriented ports and backend adapters |
| A-002 | accepted | Separate commands from local queries |
| A-003 | proposed | Supabase Postgres becomes target server authority |
| A-004 | proposed | PowerSync SQLite becomes the target local data plane |
| A-005 | proposed | Complex mutations use durable idempotent operation envelopes |
| A-006 | proposed | Structured sync excludes attachment bytes |
| A-007 | accepted | Supabase Auth at target launch; identity migration and recovery require verification |
| A-008 | proposed | Do not use permanent or general-purpose dual writing |
| A-009 | proposed | Use expand–migrate–switch–contract |
| A-010 | proposed | Use internal principals independent of auth-provider subjects |
| A-011 | proposed | Encrypt the local PowerSync database with a Keychain-held key |
| A-012 | superseded | Do not implement the former Firebase-adapter proposal |
| A-013 | proposed | Mirror authorization in RLS and Sync Streams |
| A-014 | accepted | Backend SDK types are infrastructure-only |
| A-015 | blocked | Choose the optimistic projection mechanism for complex offline commands |
| A-016 | blocked | Approve the bounded offline-access lease |
| A-017 | accepted | Firebase is a migration source, not a redesigned application adapter |
| A-018 | accepted | Use one fail-closed OperationID ownership inventory across local command families |
| A-019 | accepted | Improve Item relationship storage while preserving meaning and useful history |
| A-020 | accepted | Persist imported client payments atomically with immutable source bytes |
| A-021 | accepted, local synthetic scope only | Replay bounded payment batches and acknowledge only verified committed data |
| A-022 | accepted, integration verification pending | Correct PowerSync cancellation lock inversion without weakening database cleanup |
| A-023 | accepted, provider/delivery verification pending | Share one concrete Property Management snapshot across report outputs |
| A-024 | accepted, local concurrent regression passed | Guard the pinned cipher library's concurrent database-open race |
| A-025 | accepted, standalone macOS launch checked | Resolve embedded frameworks using the platform's app-bundle layout |
| A-026 | accepted, integration verification pending | Keep PowerSync stream parameter encoding deterministic across reopen |
| A-027 | accepted, implementation verification pending | Reuse local vendor parsers without importing legacy accounting writes |
| A-028 | accepted, implementation verification pending | Compose Inventory with existing Account-scoped workspace readers |
| A-029 | accepted, integration verification pending | Clear Project setup presentation evidence before lifecycle drainage |
| A-030 | accepted, implementation verification pending | Preserve original Project notes as distinct detail content |
| A-031 | accepted, target integration pending | Preserve individual-note provenance without inventing missing metadata |
| A-032 | implementation in progress, integration unverified | Keep downloaded Account branding separate from pending uploads |
| A-033 | implementation in progress, integration unverified | Derive report eligibility from existing Item accounting relationships |
| A-034 | corrected locally, hosted validation pending | Preserve native table names in PowerSync query outputs |
| A-035 | implementation in progress, integration unverified | Apply category management as one shared revision-checked command family |

## A-035 — Shared Category Commands and Derived Visibility

Settings and inline Project creation share `CategoryManagementPayload` actions:
create, edit, archive, restore and reorder. Reuse the existing durable operation
queue and immutable result table; no separate category delivery service. A single
envelope carries the request, avoiding parallel arguments that can disagree.
Account-bound operation IDs and exact envelope hashes prevent replay collisions.
Account-visible results identify the Account category set, not a possibly hidden
Fee category. Payloads and their individual category IDs stay in the private local
command, so shared result reads need no new category-identity disclosure.
The handler locks current membership, then operation identity, then the Account
category set. This serializes names and ordering; a complete visible active order
swaps existing slots atomically, leaving hidden, archived and system slots alone.
The existing order uniqueness constraint is deferrable but initially immediate,
so swaps are legal while duplicates still fail at statement completion.
The case-insensitive name uniqueness key is NFC-normalized, matching Swift's
canonical-equivalence comparison without rewriting the user's display spelling.
The database unique index and command check use the same key; MCP validates
directories equivalently. This prevents composed/decomposed duplicate names.
Swift uses Foundation's context-sensitive lowercasing for that key, matching
JavaScript/Postgres for Greek final sigma and dotted-I expansion. The shared form
and domain directory/admission comparisons use the same rule.
For edits, display-name bytes are compared exactly before deciding whether to
advance revision. Canonical equivalence must not turn a byte-changing edit into
a local no-op when Postgres would advance it; subsequent offline edits need the
same expected revision. Exact-byte native/SQL and encrypted-reopen tests cover it.
Wire names must already have surrounding Unicode whitespace removed; the handler
rejects untrimmed input without changing the bytes covered by its operation hash.
Control rejection uses Unicode Cc/Cf categories: Swift reads scalar properties,
MCP uses Unicode property matching, and SQL spells out those ranges because its
locale-dependent POSIX class misses formatting controls. This also avoids the
local Foundation CharacterSet misclassifying supplementary variation selectors.
On 2026-09-13 the user delegated the length choice: at most 100 Unicode code
points after trimming, using Swift unicodeScalars, JavaScript string iteration
and Postgres char_length. This avoids a custom grapheme-segmentation subsystem.
Combining marks count separately; existing stored names are not rewritten.
Boundary verification is required across all three implementations.

Local acceptance atomically stores the existing operation row, changed-definition
JSON and one insert-only PowerSync command. It never overwrites downloaded rows.
The category reader and admission share one projection implementation; rejected
effects disappear while their original commands remain retained. Applied effects
yield to synced definitions at the resulting revision or later. Account-local
acceptance timestamps are monotonic so successive offline edits remain ordered
even when the device clock repeats. Pending edits cannot bypass learned financial
access loss. Existing operation identity and upload machinery now include this
command family; no second queue, history system or delivery service was introduced.

The 2026-09-13 review reproduced a withdrawal bug: after financial access is
downgraded, sync removes Fee rows entirely, but an edit overlay could recreate
the old row. The shared projection now requires a currently visible downloaded
baseline, except for an unreplicated local creation and its subsequent edits.
A matching terminal result downloaded through the existing operation-results
stream retires that operation's overlay; a historical applied creation cannot
then revive a withdrawn category. The reader observes operation-result changes
as well as categories and membership. No command/history is deleted, no new
table or sticky category permission is added, and a downloaded General row is
immediately ordinarily visible. If a result arrives before its category, absence
does not grant access; actual combined-stream delivery still needs hosted proof.
Local regressions cover withdrawal, offline create/edit, result-only notifications
and restart with retained commands (`CategoryManagementPowerSyncTests`).

The writer uses the existing workspace finite-operation lease, so close waits for
accepted work before closing SQLite and refuses new writes during drainage. Both
admission and the reference reader consult the exact auto-subscribed
`spike_projects` stream (which already contains categories), not a global sync
timestamp or a new stream. Offline use has no time-based expiry; the pinned SDK
restores exact stream completion from encrypted storage on reopen, verified with
synthetic persisted stream metadata and no connection. Settings and Project
setup bind the original list and form through `CategoryManagementSession`; it
retains request identity across uncertain retries. Inline creation does not submit
a Project or reset its draft, and selects the new category when locally observed.

Category status is read from those same local operation records as standard
`OperationSnapshot` values, not a second UI journal. The reader shares the existing
category watch cancellation/drainage mechanism, revalidates local command ownership
and current membership, and emits no category names or hidden category IDs.
Settings and Project setup distinguish locally saved, synced and rejected changes,
including results retained across restart. Scheduling now uses the existing
PowerSync SDK through workspace-owned `startSync`. The SDK callback enters the
same fenced, cancellable command-upload method used by explicit delivery; there
is no second queue, polling loop or command handler. Startup and uploads drain,
then the workspace disconnects before closing SQLite. Shared connection admission
stays held through database close to prevent a late-close/reconnect race.
The session owner still supplies Principal-bound credentials and command
transports; no authentication provider is selected and hosted setup is deferred.
Nil download credentials do not disable the SDK's independent upload loop.
Real-SDK tests with synthetic appliers cover pre/post-connect queued categories,
applied/rejected results retained after reopening, exclusivity and close/removal
drainage, including a delayed credential refresh during close. This is not
authentication proof. The pinned SDK shares a sync coordinator by database
filename and disconnects it when any associated database handle closes. Therefore
sync requires one runtime owner per workspace: all views reuse that runtime.
Existing offline-only multiple-handle behavior remains available, but handles
must close before one starts sync; no additional handle may open during sync.
The existing access fence counts pending/open handles, including failed bootstrap
cleanup, so initialization cannot race connection startup. Registration is released
only after the runtime closes. This avoids an extra reconnect coordinator or SDK
fork; the tradeoff is explicit single-runtime ownership during sync, not a limit
on how many views can use the same runtime. Same-file close/reopen ownership tests
and the 109-test workspace/Item-provider regression run pass. The real authenticated
app session still needs to supply correctly Principal-bound credentials/transports.

The MCP `manage_budget_categories` tool uses the same five-action envelope and RPC.
Its Account/principal come from the host's resolved context, never tool arguments;
its stable caller UUID becomes the same Account-bound operation namespace. Shared
Swift/MCP fixtures cover canonical bytes, hashes and decimal revision strings.
The server remains the transactional authorization authority for both clients.
`list_budget_categories` obtains visible IDs and revisions through a caller-RLS
RPC; it does not use elevated credentials or infer permission from a tool argument.

Under D-030, the existing category visibility projection is derived from current
kind on every write. It is not independent policy or a Fee-to-General transition
flag. Current ordinary readers therefore see General definitions automatically.
Existing category IDs/references survive edits and archive/restore; the command
does not rewrite Items, Transactions, paid Invoice snapshots or payment amounts.
This is target-only work; no Firebase implementation or production migration.

Verification and remaining gaps are recorded in the active `category-management`
checklist. HTTP request/response contracts, status replay/drainage and Swift/MCP
canonical parity now have focused proof. Local HTTP lookup/mutations, concurrent
name/revision conflicts and offline reopen pass. Database name length/control
parity, affected accounting consumers and remaining UI interaction need proof; this is
not acceptance of the whole batch or migration authorization.

## A-034 — PowerSync Output Names Must Match the Native Schema

PowerSync's primary `FROM ... AS alias` changes the downloaded table name,
not merely the SQL qualifier ([documented contract](https://docs.powersync.com/sync/advanced/multiple-client-versions)).
Our shorthand primary aliases therefore did not match the native `spike_*`
tables. `item` also aliased two different source tables. Remove primary aliases
and qualify fields with the original table names; keep ordinary join/subquery
aliases. This changes no product relationships, permissions or retained history.

The native schema now checks the output names of all 37 current stream queries.
Regression tests reject shorthand and cross-table output aliases. Existing exact
SQL expectation checks were updated without relaxing their predicates. Actual
report and physical-Item SQL authorization/projection tests pass after the rename.
The pinned `@powersync/service-sync-rules` 0.41.0 parser now also compiles the
checked-in YAML with zero errors and verifies all 18 native output-table names.
Its regression reproduces the original alias bug using the real compiler.
This tooling requires Node 24 (CI pins 24.14.0); it is not an app dependency.
Four parser/name tests and target environment checks pass. Source-column validation,
replication and hosted download validation remain required. Prior synthetic engine tests supplied
their own correct table names and could not establish this configuration contract.

## A-032 — Downloaded Account Branding Is Not Pending Work

Settings and report preview share the same profile presentation/model. PDF output
receives that Account-scoped profile instead of querying a second branding source;
it rejects foreign Account identity, and the UI reads current authorized local
profile data independently of any pending download before OS handoff. A screen
model comparison alone is insufficient while a download delays watch updates.
Failed/not-yet-downloaded retrieval status does not itself change branding;
Account/name, actual bytes and explicit logo absence remain significant.
Both presentations decode a maximum-1024-pixel thumbnail with
ImageIO instead of eagerly rendering the full original image. Original encrypted
bytes and their identity remain unchanged. PDF text/fallback/foreign-Account tests
pass. The oversized-logo test verifies 2048×1024→1024×512 decoding and all30 report
rows. Main inspected all five Poppler-rendered synthetic PDF pages without logo
overlap/clipping. Native interaction and authenticated end-to-end retrieval remain
unverified.

The read-only Account profile uses the existing Account name plus a separate
authorized logo-reference row. A missing row is unknown evidence; an explicit
null logo is known absence. Logo fields do not enter Account discovery. The
selected-workspace stream and private Storage GET require active membership.
Immutable logo paths bind Account, attachment identity and SHA-256; no profile
write, upload, signing, listing or deletion policy is introduced.

Downloaded bytes reuse the encrypted attachment vault. Their actual persisted
evidence lives in a local-only cache table, not the pending capture/upload queue.
The orphan inventory includes retained download references, and a populated
cache cannot initialize a missing scope binding. This preserves existing upload
receipts and offline bytes without fabricating locally accepted operations.

Corrupt downloaded bytes may be atomically replaced only by verified bytes for
the same persisted reference and only when no upload receipt owns that object.
Normal capture persistence remains exclusive and never opts into replacement;
link substitution still fails closed. The replacement is staged and synchronized
before rename. Focused repair/refusal tests pass; concurrency and interruption
review is still pending.

Tradeoffs and unfinished verification: download
drainage before logout/orphan observation, current-reference revalidation after
network work, Settings/report integration and actual Storage HTTP behavior remain
required. The local cache is not itself authorization to display a logo. Do not
claim profile completion from metadata tests or schema checks. Product authority:
`account-profile-readback` in the unified checklist and Account Business Profile
in `docs/specs/account-discovery-and-workspace-selection.md`; O-068/O-023 still
gate the separate editing/retention operations.

## A-031 — Historical Note Facts Do Not Imply Authenticated Authors

Individual-note migration preserves original creator identifiers, display names,
source channels, text and available creation/update timestamps. A source creator
such as `mcp-agent` is not an authenticated human; missing creator/time fields do
not authorize assigning the importer or import time. An update timestamp without
an editor remains that fact, not a reconstructed edit event. Source snapshots
cannot reconstruct physically deleted notes or previous text versions.

This follows [Notes and Quick Note](../../specs/projects.md#notes-and-quick-note).
The source `ProjectNote` model permits absent dates and blank creators;
`ProjectContext.updateNote` records an update time without an editor. The existing
target note row/snapshot instead requires a principal and creation time, couples
edit time to editor identity, and reduces timestamps to milliseconds. Those
assumptions must be corrected in the existing note read/import path, not worked
around with fabricated users, dates, or a second history subsystem.

The pure source converter retains complete immutable source evidence, exact
optional strings and original timestamp seconds/nanoseconds. Missing and explicit
null remain distinguishable in that evidence. Reconciled target identities are
supplied by the caller; conversion is not identity reconciliation or permission
to load data. Malformed known fields remain unresolved, with their source intact.
O-039 governs new create/edit validation, not lossless historical preservation.

Historical creator display names may be empty or whitespace-only: the source
model defaults this field to an empty string. Preserve that exact value, distinct
from null, across storage, shared reads and MCP. Reject NUL (not representable in
Postgres text), but do not apply new-name validation to historical facts. This
removes the target's unsupported nonblank-name assumption without changing
principal attribution, permissions or new-note policy.

Tradeoff: historical metadata must represent uncertainty explicitly, while new
writes can still require authenticated authors. Timestamp display/index projections
must not replace original precision or silently reorder history. The existing
database, cursor, PowerSync, app and MCP contracts need coordinated verification
before these source facts become usable target notes. A converter alone is not
migration readiness. Implementation/test evidence belongs to the unified
checklist's `project-initial-notes-preservation` outcome.

Exact note time is represented by integer seconds/nanoseconds in the shared
contract; `Date` is only a display projection. Storage retains its existing
integer millisecond component and adds a 0–999999 nanosecond remainder within
that millisecond. Existing millisecond records have remainder zero. A missing
millisecond component remains an unknown date even when the compatibility default
remainder is zero; a nonzero remainder without a date is invalid. Paging uses
both components, then stable note identity, with undated records last. Server
and local cursor encodings must move together; the old millisecond-only cursor
must not silently skip submillisecond records.

Local compatibility uses `coalesce(remainder, 0)` so old downloaded rows remain
usable offline. The SDK's column index still narrows Account/Project scope, but
SQLite can require a temporary sort inside that scope; the query-plan test checks
the actual exact-time query and indexed scope rather than claiming sort-free
paging. Postgres has a matching expression index. Do not add a second timestamp
copy or custom SDK index lifecycle solely to avoid this compatibility sort.

The private individual-note importer reuses the existing atomic import pattern:
lock the exact existing Project, insert the note and immutable source evidence
together, and accept an identical retry without updating either. Source identity,
full source bytes and the original imported row projection are retained; changed
input or a changed target fails rather than overwriting later work. API roles
cannot invoke it. This is an operator primitive, not a new-note command or load
authorization. UTC is pinned when comparing timestamp-bearing JSON projections
so caller timezone cannot turn an identical retry into a conflict.

The parameter exporter verifies its projection against retained source bytes and
accepts only an explicitly supplied reconciled principal. Historical values the
current target cannot represent remain unsupported, never normalized to make an
import pass. The existing synthetic runner now includes individual notes in the
same transaction and journal as payments and legacy Project notes, with separate
counts and fresh byte-exact source/row readback before acknowledgement. This
avoids introducing a second migration runner or recovery journal. Resolving the
historical compatibility gap, database execution and recovery verification remain
required; these primitives alone do not establish complete note migration.

## A-030 — Legacy Project Notes Are Not Individual Note Records

The existing Project detail contract carries a separate nullable `legacyNotes`
value for original `Project.notes` content. It does not reuse description or
manufacture an individual note with a guessed author, timestamp or source type.
This implements [Notes and Quick Note](../../specs/projects.md#notes-and-quick-note),
not a new note-writing policy. The existing Account/Project detail lifetime and
authorization remain responsible for visibility and cleanup.

Preserve text exactly, including multiline content, empty strings and whitespace.
Migration must retain source correlation and immutable source evidence separately;
replay must not append duplicate notes or overwrite individual note history.
Keep legacy text out of directory-card presentation. The synchronized Project
row carries it consistently across existing streams; a separate notes stream
would duplicate ownership without a demonstrated need. The Notes screen composes a
read-only legacy card with the existing individual-note list, without adding a
second history or persistence system.

Tradeoff: this adds one explicit detail field rather than coercing two distinct
source shapes into one model. Older encoded detail fixtures may omit the field;
that compatibility does not prove legacy-note migration or download completeness.

Verification: core encoding and model lifecycle tests preserve exact text and
clear it on selection/denial/stop. Provider tests preserve text through archive
overlays and encrypted reopen, and deny removed membership. The source transform
retains the entire original document and leaves nontext/NUL values unresolved
rather than silently changing them. Full local Swift tests pass; SQL authorization
and native legacy-only/both/neither presentation await exact-commit CI. A pure
source transform is not a persisted import: durable source loading, replay and
reconciliation remain required for `project-initial-notes-preservation` in the
unified checklist. No production data has been accessed.

The follow-on private import primitive locks the existing Project and atomically
stores exact text with immutable source bytes, derived SHA-256 and source/target
correlation. Exact replay is a no-op; changed evidence, changed text or conflicting
mapping fails rather than overwriting. API roles receive no grants. The existing
local synthetic payment runner also imports its parent Project's legacy notes
in the same transaction and tracks both entities in its existing journal. This
reuses endpoint guards, retained artifacts and recovery/readback rather than
adding another migration runner. Previously persisted runs remain bound to their
original binary and plan; this does not upgrade or rewrite them.

Parameter validation and committed-note readback compare UTF-8 bytes explicitly:
Swift's canonically equivalent String equality is insufficient for exact source
preservation. Payment and note exporters share the same canonical source-envelope
encoder, with existing payment fixtures guarding byte compatibility. SQL tests
and the expanded cross-process recovery harness require execution; building the
runner and unit tests alone do not prove durable migration readiness.

## A-029 — Project Setup Closure Clears Presentation, Not Accepted Work

`ProjectSetupStagingExercise.stop()` now clears draft fields, reference snapshots,
category/budget choices, diagnostics and displayed submission evidence before
awaiting cancellation/drainage. Previously those values remained readable on the
retained model after workspace closure. Existing generation guards prevent late
callbacks from restoring them; cleanup occurs before suspension so an older stop
cannot erase a subsequently restarted form.

This changes only the form's in-memory lifetime. It does not delete, cancel or
rewrite an accepted durable operation, or change ordinary failed-submission retry
behavior. Account-removal recovery and logout policy remain their existing
authority; O-049/O-052 still gate full Project creation. No new provider or
retention mechanism is introduced.

Verification: `ProjectSetupStagingExerciseTests` covers cleared draft/reference
fields, all displayed receipt states, late stream delivery, and immediate erasure
during a suspended submission followed by restart. Runtime persistence is not
proved by its command-recording test double; existing durable-runtime evidence
remains separately required. Native lifecycle integration is not yet claimed.

## A-028 — Inventory Is an Account Workspace, Not a Synthetic Project

**Change and reason:** The Project directory opens Inventory through an explicit
route. Items use the existing downloaded placement reader with business-Inventory
scope; Spaces use the existing scoped browser and exact Space detail/checklist
coordinator. The same detail view serves Project and Inventory Spaces. No fake
Project ID, duplicated database, or Inventory-only accounting implementation is
introduced. The device remembers only a section name under an Account-specific
preference key; unknown values fall back to Items, and no downloaded records are
stored in that preference.

**Preserved behavior and tradeoff:** This implements the navigation contract in
[Project List](../../specs/projects.md#project-list), preserving Items,
Transactions and Spaces without changing Item identity, transaction links or
history. Items still disclose incomplete physical-only downloads. Transactions
explicitly remain unavailable: A-020's imported Project payments are not an
Inventory financial reader, and no financial Sync policy is silently authorized.
Existing checklist admission and durable command authority remain unchanged;
navigation does not grant mutation rights.

**Verification:** Focused coordinator tests cover Active-only entry, exact
Account/Inventory query scope, invalid preference fallback, exact Space detail
and checklist readback, back/stop cleanup and no Project query. Deterministic
section-switch regressions and preference isolation pass. Full local suite:
892 tests/133 suites passed. Native UI and exact-commit integration verification
remain pending. This is not a claim
that the full Item or Transaction browser is complete.

## A-027 — Local Vendor PDF Review Boundary

The target app compiles the existing pure Amazon/Wayfair text parsers, their
money/date helpers, and PDFKit text extractor through five explicit source-file
entries in `LedgerTargetProject.yml`. The files remain unchanged; the production
app project and checkout are untouched. There is no copied parser fork, new
runtime package, remote parsing service, or legacy import/writer dependency.
This implements the local-review part of
[Invoice Import](../../specs/invoice-import.md#target-import-contract), not its
unresolved accounting-confirmation policies.

`LocalVendorDocumentReview` owns an Account-scoped document digest and immutable
extracted rows, with separate editable review values. Original row ordinals
remain stable when rows are excluded. A replaced/closed document rejects late
extraction and stale edits. Missing unit prices remain missing; a line total
does not become a unit price and a missing date does not become today.
Review is not durable acceptance of an Item, receipt, or payment.

The workspace application model owns the review session. Closing/dismissing it or
leaving the authorized workspace permanently closes that instance; delayed
picker results cannot reopen it. Presenting the system file picker is not itself
a close event. Navigation, Project-evidence removal and workspace stop close it
through the model, not a SwiftUI `onDisappear` modifier on list content. This
replaces the initial view-owned lifetime after CI exposed a missing PDF sheet;
the callback cause is an inference awaiting native confirmation. Focused model
tests prove terminal closure on Back, removal and stop. Category choices reuse the existing visible Account-category
stream, matching the shipped import picker rather than adding a new category
query or restricting it silently to enabled Project allocations.

Tradeoff: parser heuristics (including source money normalization) remain
best-effort extraction suggestions, never financial authority. Their existing
limitations must stay visible in review. The old import helper's index-based
thumbnail attachment and filtered/unfiltered upload zip are not reused. Target
thumbnails use actual PDF Image XObject placements and unique source SKU anchors,
keyed by original row ID, with encoded bytes and page/range/bounds evidence kept
on immutable source rows. This supports simple unrotated, unclipped layouts, not
arbitrary PDFs: ambiguous anchors/images, unsupported graphics state/forms and
page geometry return no thumbnail. Extraction is bounded to 100 pages, 1500-point
page dimensions and 500 image placements per page; text review remains available.
Geometry proves spatial association only, not product identity; a source crop can
include overlaid content or a nearby logo. Real vendor-template coverage is still
unproven. Debug
disclosure remains explicit, local and scoped, not telemetry.

Verification: the existing four Foundation parser files typecheck together in
Swift 6. Focused review tests cover preserved originals, exclusion identity,
stale edit rejection, cancel/late extraction and malformed row provenance.
Synthetic PDFKit fixtures now exercise both actual vendor parsers, all mapped
row details, corrupt/image-only/unsupported/ambiguous inputs and source-preserving
review edits (`scripts/test-local-vendor-pdf-parser.sh`). They expose an existing
limitation: unpriced rows are omitted by the parsers, not returned for editing.
Focused model/diagnostic tests cover explicit redaction, immutable row provenance,
category scope and both explicit-clear and task-cancel late completions. Actual
illustrated PDF fixtures pass through parser and editable review with distinct
row thumbnails. Independently reviewed extractor tests verify source pixels,
crop orientation, nested transforms, missing/competing images and rejected
unsupported geometry. Native review interaction, integrated category revocation
and exact-commit CI remain pending; no workflow completion is claimed.

## A-026 — Deterministic PowerSync Stream Parameter Encoding

CI `34204717358` exposed intermittent report unavailability after encrypted
reopen. A focused local reproduction showed two `ps_stream_subscriptions` rows:
one completed row encoded `project_id` before `account_id`; a second incomplete
row encoded the same fields in the opposite order. The pinned SDK's shared
default JSONEncoder allowed dictionary ordering to change the stored identity.

Set `.sortedKeys` on that SDK encoder, which is shared by subscription commands,
stream startup and subscription updates. This changes object-key order only;
arrays, values, scope and authorization remain unchanged. Reuse the pinned SDK
correction rather than introducing a second subscription layer or accepting
ambiguous report readiness. The 32-registration test requires one stored identity;
the real encrypted reopen test retains completed contents without transport.
Main and independent stream_identity_review found no blocking issue; exact
integrated CI remains required. The new registration test fails with the old
encoder and passes with sorted keys. Six focused readiness tests and the full
local suite (878 tests, 130 suites) passed after the fix.

This prevents new identity drift, not migration of preexisting unsorted or
duplicated development-cache metadata. Keep those ambiguous rows fail-closed;
do not fabricate completion, merge history, or erase pending work to repair them.
Any retained pre-release cache requiring recovery needs explicit handling before
it can be considered covered by an upgrade path. Production Firebase data and
its worktree are untouched. The patch is tracked in `vendor/powersync-swift/LEDGER-PATCH.md`
and must be revalidated when replacing the pinned dependency.

## A-025 — Platform-Correct Embedded Framework Lookup

Standalone synthetic macOS launch failed before app initialization: the database
framework was correctly embedded in `Contents/Frameworks`, but the generated
cross-platform target searched only the iOS-style executable-relative directory.
Add `@executable_path/../Frameworks` for macOS SDKs in `LedgerTargetProject.yml`
and regenerate the Xcode project. Keep inherited/iOS paths unchanged; do not use
environment overrides or copy libraries into the wrong bundle directory.
The rebuilt binary contains that runtime search path and starts standalone with
the synthetic fixture flag. No data model, history, backend or security policy
changes. Screen-locked native interaction and release/iOS packaging are separate
verification requirements, not proven by this launch check.

## A-024 — Narrow Guard for Concurrent Encrypted Database Opening

**Evidence:** The 16-worker unique-path encrypted-open reproduction failed with
`unknown cipher 'chacha20'` inside `sqlite3_open_v2`, before Ledger supplied a key.
Main independently inspected pinned CSQLite 3.51.2's amalgamation:
`sqlite3mc_cipher_name` returns a single static mutable buffer, and
`sqlite3mcConfigureFromUri` compares that buffer after another open can overwrite
it. Its only implementation callsite is URI/open configuration; this is not a
one-time registry initialization problem. Disk pressure was observed but is not
the established cause of this reproduced failure.

**Decision:** Guard only `sqlite3_open_v2` in the existing vendored PowerSync
connection factory with a process-wide synchronous mutex. Do not serialize
ordinary queries, key configuration, whole pool startup, or the tests; do not
retry away the failure. Current Ledger structured, principal and attachment
databases use this opening path. Preserve SQLite's detailed error before closing
any nonnil failed-open handle, avoiding both opaque diagnostics and handle leaks.
No encryption key or cipher policy changes are authorized by this fix.

**Limits and verification:** A future independent CSQLite opening or ATTACH path
would need the same protection or an upstream library correction. This is a
bounded workaround for the pinned dependency, not a claim that SQLite generally
requires serialized access. Keep the concurrent reproduction and integrated
report/runtime tests as regression evidence in the active workflow. Before/after
results and any remaining failures must be recorded there before acceptance as
verified; no broader hosted or cutover readiness follows from this patch.

The same 16-worker reproduction passed after the guard. Main independently
reviewed the C callsites and Swift patch, then ran the combined 67-test report,
runtime, Item-watch and concurrent-open set with normal test concurrency: all
passed. Exact logs remain linked in the active workflow; full integration/CI
verification remains required for the uncommitted report batch.

## A-023 — One Property Management Report Snapshot

**Verified native checkpoint:** automatic CI `34201884298` for
`7919298c5b623b71e0b0ee28e172a8ad1f757d71` passed 877 native tests in
130 suites, nine macOS UI tests, both platform builds and three iPhone report
interaction tests. Native macOS Copy executed (not skipped), delivered usable
PDF and CSV content after cleanup, and repeated Share cancellation plus the
visible Print dialog's Cancel passed. The corrected iPhone toolbar, report
availability states, final-read export denial/retry and refresh/dismiss passed.
This resolves those specific pending checks below; iOS native destination/print
handoff, hardware protection and hosted behavior are not established by this run.

**Owned macOS sharing payload (2026-09-08):** exact CI `34200048685` executed
the native Copy test and exposed a real lifetime defect: AppKit copied a URL into
Ledger's scratch directory, then successful-service cleanup deleted its target.
The macOS picker now receives a named `NSItemProvider` with PDF/CSV data
representations (and UTF-8 text for CSV), not the scratch URL. Destinations can
request bytes or a system-created file copy. Existing scoped authorization,
content, completion waiting and scratch cleanup remain unchanged. This keeps
Copy available without retaining private scratch indefinitely or guessing a
cleanup delay. The tradeoff is retaining report bytes in memory for the
provider's lifetime; a recipient's copy is outside Ledger's deletion authority.
Focused tests remove source scratch before requesting both bytes and a file
representation. A small Swift 6 executable using the actual helper passed both
requests for PDF, CSV and UTF-8 CSV after source deletion; independent read-only
review found no blocking defect. The package regression tests and actual native
Copy remain pending CI verification; the previous successful service callback
alone did not establish delivery.

The same CI still failed Print cancellation with application-modal printing.
Its accessibility tree contains a visible Print Dialog and a second offscreen
Cancel. The interaction test now clicks the visible dialog's own Cancel after
it becomes hittable and requires that dialog to disappear. This is not evidence
that the print issue is fixed; retain the runtime gate and investigate if it fails.

**macOS print lifetime (2026-09-08):** use AppKit's application-modal
`NSPrintOperation.run()` instead of attaching a document-modal print sheet to
the SwiftUI report sheet. Two CI attempts opened the nested print panel but did
not dismiss it through Cancel or Escape; nesting is observed, not conclusively
proven to be the cause. Independent review and the SDK contract support this
simpler alternative: retain the PDF/operation until `run()` returns, preserve
PrintCore cancellation/error handling, then permit the existing owned scratch
cleanup. The print delegate/continuation class is removed. The tradeoff is that
other app windows cannot be used during the native print operation. Real native
cancellation still must pass before accepting the fix; no history or accounting
changes are involved.

The CI-only Copy test now uses xcodebuild's documented `TEST_RUNNER_` environment
forwarding rather than assuming the runner inherits `GITHUB_ACTIONS`. Only the
exact disposable-clipboard flag is allowed by the existing CI safety check;
local runs still skip clipboard mutation, and removal or alteration of that flag
is tested. A skipped test is not usable-delivery evidence.

**Native report controls (2026-09-08):** iOS places PDF Share, Print and CSV Share
in a bottom toolbar, with Refresh and Done in the navigation bar. The first
isolated iPhone UI run exposed Refresh being pushed into automatic overflow by
the combined toolbar. This is a platform layout correction, not a new action or
authorization path: the same buttons, readiness checks, snapshot and delivery
implementation are reused. macOS retains its grouped toolbar. The tradeoff is a
dedicated bottom bar on iOS in exchange for discoverable controls on a narrow
screen. Corrected-layout verification is pending. The existing CI runner will
run the three synthetic iPhone report interaction tests after its iOS build;
its timeout increases from 20 to 30 minutes to include simulator startup/testing.
No new job, service or hosted backend is introduced. Local retesting remains
limited by disk space. See the unified checklist for current evidence.

**Online transport boundary:** The MCP reader uses a publishable key and caller
JWT, rejects Account/Project/Principal/currency mismatches, requires HTTPS except
loopback development, forbids redirects, bounds request time, and sanitizes
failures. Credential-shape checks are not authentication; server JWT verification,
current membership and a coherent RLS-protected RPC remain required. This changes
no history or product policy.

The online RPC now uses `STABLE SECURITY INVOKER` with an empty search path:
membership and all report facts share the calling statement's database snapshot
and caller RLS. It derives Principal from Auth identity, retains referenced
archived Spaces and rejects unreadable parents. Account/Project currently store
no currency setting; the explicit requested unit must match every known Item
value, with no conversion or default inference. The adapter verifies the native
scope fingerprint and exact authority version. Independent read-only review found
no blocking schema/RLS issue; 15 local pgTAP checks and nine TS projection/adapter
tests pass.

**Target MCP host:** A separate Node stdio entrypoint registers only the report
tool, using pinned existing-stack SDK/Zod versions and no Firebase imports. The
launcher supplies `LEDGER_TARGET_SUPABASE_URL`, `LEDGER_TARGET_PUBLISHABLE_KEY`,
`LEDGER_TARGET_ACCOUNT_ID`, and `LEDGER_TARGET_ACCESS_TOKEN`; launch from
`LedgerTargetMCP` with `npm run start:stdio`. Principal is resolved through
caller-JWT RLS, and every report rechecks membership. Tokens are neither persisted
nor refreshed here: expiry requires relaunch with a fresh user session. This is
not hosted OAuth or complete MCP migration. Independent review found no blocking
auth flaw. The local stdio-to-HTTP-to-Postgres smoke passes for an empty Project,
rejects identity arguments and bad JWT signatures, and sanitizes unavailable
Project errors. The same real MCP/HTTP path now also verifies populated reports
(archived Space parent, No Space, Unicode, known zero, unknown and above-2^53
amounts) and membership removal/restoration within one open session. The fixed
synthetic fixture reuses immutable history and leaves its membership removed
after testing. Full local database tests pass (543 checks), as do 36 MCP tests,
schema lint and security advisors. CI now includes report stream and real MCP
checks. Hosted behavior and native Share/Print interaction remain unverified.
The combined native batch passes 874 tests. Integrated checks also found the
note-history Project projection missing the report address: it now selects the
same named fields as report/bootstrap, with a direct regression comparison.
Older Space-policy tests now assert the exact two authenticated SELECT policies,
not an obsolete one-policy count; no write grants or broad read policy were added.
Final lifecycle review found recovery was invoked only before export. App startup
now also invokes the same protected scratch recovery, with a visible cleanup
failure alert. The focused recovery/handoff tests pass (seven tests), including
startup cleanup retaining active sessions and deleting abandoned owned bytes.
No new retention policy or original-document deletion is introduced.
The native reader and real MCP RPC now match over the same synthetic source rows
(fields, totals and source-set hash; source-specific provenance is excluded).
CI transfers this generated, same-commit fixture from the existing local database
job to the existing native job; missing artifacts fail, and retention is one day.
This introduces a job dependency rather than another test job or maintained
fixture. Main independently reviewed the test and reproduced its pass. Updated
macOS and iOS builds pass after the startup hook; OS dialog interaction is still
not inferred from compilation or callback simulations.

**Physical read integration:** Store nullable Item name, SKU and exact signed
market value separately from description; add an optional Project address without
inferring it from description. Preserve current placements' archived Space parents
with narrowly scoped read access. Overlapping report and ordinary streams must
select identical expressions for the same table/ID; do not rely on partial-row
merging. No additional tables or report receipt system are introduced. These are
read fields, not permission to edit Items. Local SQL and SQLite tests cover the
new fields and access boundaries; scoped download completeness and hosted
replication still require verification in the active workflow.

Market-value cents remain Postgres bigint but sync as decimal text into SQLite,
then parse strictly into Int64. A focused falsification test found that an INTEGER
PowerSync view silently coerced a fractional local value to an integer before
the reader could reject it. Text prevents that loss; fractional, exponent and
out-of-range values are rejected rather than rounded. The local report reader
checks membership, Project, current placements and parent Spaces in one read
transaction. Its query checks exact scoped retained sync metadata in that same
transaction; synthetic metadata tests do not prove core eviction/re-subscription
semantics, which remain an integration requirement before report readiness is
accepted. Existing Item display-name fallback is presentation only, never a
rewrite of stored name or description.

**Pinned-core local evidence:** A fresh unseeded SQLite test now drives real
core checkpoint/data processing. Expiry removes completion metadata while the
bucket row can still exist; a later withdrawal checkpoint removes the row;
re-subscription has no completed checkpoint. The SQL gate rejects both incomplete
boundaries, even when public status briefly retains old stream information.
This supports checking retained metadata with report inputs in one transaction,
not relying solely on cached status. Runtime reads reuse the existing finite
workspace lease; encrypted restart and foreign/closed/removed-access tests pass.
This synthetic single-bucket sequence is not hosted replication proof or full
report delivery verification; see the existing workflow's test evidence.

**Live presentation:** Item and report watches now share a small owned-subscription
task-group helper, preserving local-first emission and awaited cleanup. The
runtime retains the report task until cleanup completes and suppresses updates
after access lock. The preview consumes only the typed snapshot's precomputed
groups/totals; incomplete or stopped watches clear visible report data. No new
subscription registry or alternate UI accounting implementation is introduced.
The macOS preview compiles; full integration and export verification remain open.

Preview, PDF/print, CSV and MCP use `PropertyManagementReportSnapshot`, reusing
the existing protected-artifact reference rather than a second export system.
It preserves physical Item and placement identities, Project/Space revisions,
SKU, nullable address/value, deterministic grouping, and exact known subtotals
with unknown counts. Missing prices never become known zero. JSON encodes cents
and revisions as decimal strings to avoid JavaScript precision loss.

The owning provider must establish current access, complete exact-scope stream
readiness and one coherent SQL snapshot. Public construction only checks internal
coherence; it cannot authenticate a checkpoint or authorize an export. No new
receipt/manifest service or arbitrary offline time expiry is introduced.
Seven focused tests pass in `PropertyManagementReportTests`; real provider,
rendering and protected handoff remain unverified. See the existing
`property-management-report-delivery` workflow record for implementation evidence.

The initial HTML renderer is pure snapshot presentation: escaped user text,
no asset fetches or eligibility/total calculations, and no external resources.
Known cents retain integer precision; unknown totals remain labelled subtotals.
String-level tests are not visual/PDF or system-handoff proof.

**Native PDF and temporary-file lifetime:** Use CoreText pagination directly from
the same immutable snapshot, without a browser, asset fetches or recalculated
accounting. Ordinary Item records and totals stay together; oversized user text
can continue across pages instead of being truncated. Stable Item IDs and snapshot
provenance remain in the output. This is presentation, not another data model.

`ReportScratchStore` owns exclusively created files in a dedicated private temp
directory (0700 directories, 0600 files, iOS complete protection). Session locks
keep recovery from deleting active handoffs; explicit removal follows system
completion/cancel/failure, while abandoned sessions are cleaned on recovery.
Descriptor-relative no-follow operations reject symlinks, foreign artifacts and
unexpected files. Only the trusted OS temp parent is canonicalized with realpath;
Foundation's /var abbreviation otherwise prevents secure path traversal. Saved
exports and original evidence are outside cleanup scope. No persistent receipt
registry is added, and a snapshot/hash reference never grants access.

Main reviewed the delegated store and its correction. Seven focused native tests
pass for PDF content/pagination and scratch retention/failure/recovery. All nine
pages of the synthetic 80-Item PDF were visually inspected after fixing split
records. iOS protection, current-access checks at handoff, actual OS completion
callbacks and app/MCP integration still require verification; see the existing
workflow record. This does not claim completed export delivery.

**Handoff authorization:** After rendering, the delivery coordinator re-reads
through the authorized report port using the displayed as-of value. A changed
snapshot or rejected access requires refresh instead of exporting stale content.
The preview also checks its live state immediately before opening the OS dialog.
Once disclosed to the system, content cannot be recalled; cancellation of an app
task is therefore not proof that the system stopped reading its file. Cleanup
waits for the native completion callback. Focused tests cover denied/changed reads
and file retention through successful, canceled-task and failed handoffs. Actual
native-dialog integration remains an additional verification requirement.

**CSV projection:** A pure renderer emits typed metadata, Space, Item, group-total
and report-total rows from the existing snapshot. It quotes cells and neutralizes
formula-like user text without changing canonical data; numeric minor-unit fields
remain exact signed decimal strings. Spreadsheet importers must retain large
integers as text to avoid their own precision loss. This renderer does not supply
authorization or a delivery host. Target MCP currently has tool/adaptor exports,
not a running report connection; canonical JSON and CSV formatting alone do not
close that integration gap.

PDF and CSV now share the same owned-file/handoff implementation. The scratch
store accepts only these two explicit formats; startup cleanup rejects other
extensions and still never touches user-saved exports. CSV sharing uses the same
fresh authorized read and completion-driven cleanup as PDF, not a separate
authorization or retention path.

**Online versus downloaded provenance:** The shared report content now carries
an explicit source variant. Downloaded reports require their local version and
exact stream checkpoint; authoritative online reports carry neither. Both bind
the scoped principal, as-of time, source-row revisions/content hash and report
authority. Online reads therefore do not fabricate a PowerSync sync time or
local version. Renderers label the source; the downloaded app watch rejects an
online result. The source variant participates in the snapshot hash while equal
source facts still produce equal groups, totals and source-set hashes.

Node MCP retains the existing caller-JWT RPC architecture. Its report projection
must match Swift using the shared canonical JSON fixture, including exact money,
No Space identity and string escaping; passing projection tests is not proof of
live authenticated RPC/transport delivery. No Firebase server import or native
subprocess bridge is introduced.

## A-001 — Domain-Oriented Ports and Backend Adapters

**Decision:** Views and application use cases depend on Ledger-specific ports.
Supabase/PowerSync is the initial production implementation; test adapters and
any future replacement conform to the same ports.

**Reason:** The current protocols still expose Firebase listeners, dynamic field
maps, paths, and write batches. Those types make a backend replacement spread
through the application.

**Consequences:**

- domain/application modules contain no vendor SDK imports;
- mapping code is explicit;
- adapter construction is centralized; and
- adding a backend requires behavioral contract conformance.

**Rejected alternative:** A generic CRUD repository shared by all layers. It
hides business atomicity and collapses different consistency semantics into a
misleading interface.

## A-002 — Command/Query Separation

**Decision:** Mutations are typed domain operations. Reads are local query ports
returning read models and streams.

**Reason:** Ledger requires local reactive reads but server-authoritative
multi-record writes. One repository interface cannot express both honestly.

**Consequences:** Read models may be denormalized and screen-specific. Commands
may be implemented with different backend mechanics while preserving the same
receipt and result lifecycle.

## A-003 — Supabase Postgres as Target Authority

**Decision:** Subject to the vertical spike, Postgres is the canonical target
for structured Ledger data and accounting invariants.

**Reason:** Relational constraints, transactions, functions, joins, audit
queries, and explicit migrations match the redesigned accounting model.

**Evidence required:** RLS performance, command latency, migration rehearsal,
backup/restore, and current-account capacity tests.

**Evidence protocol:** Run S0/S1/S8/S9 and the mandatory DB/RLS/restore/
performance/cost tests in the
[isolated vertical-spike protocol](../../plans/ledger-accounting-redesign/vertical-spike-protocol.md).

**Consequence:** This does not make the Supabase client library part of the
domain. Postgres is replaceable behind ports and exported data contracts.

## A-004 — PowerSync as Target Local Data Plane

**Decision:** Subject to the vertical spike, PowerSync supplies encrypted local
SQLite, reactive queries, partial synchronization, and durable uploads.

**Reason:** Plain Supabase client calls do not provide Ledger's required durable
offline database and upload queue.

**Evidence required:** Seven-day offline behavior, app termination, auth refresh,
conflict handling, revocation, cold sync, storage footprint, and cost metrics.

**Evidence protocol:** Run S0/S3–S9 and every mandatory local/sync/offline/media/
evolution/physical/cost test in the
[isolated vertical-spike protocol](../../plans/ledger-accounting-redesign/vertical-spike-protocol.md).

**Consequence:** Supabase Realtime is not used for rows already synchronized by
PowerSync. Realtime may be considered separately for ephemeral presence only.

## A-005 — Durable Idempotent Operation Envelopes

**Decision:** Complex operations have an operation ID, contract version, actor,
scope, payload, creation time, preconditions, and observable result.

**Reason:** Offline queues and network retries provide at-least-once delivery.
Accounting effects require exactly-once observable outcomes.

**Consequence:** The server stores operation results and returns the prior result
for a repeated idempotency key. A validation rejection is a durable domain
result, not a transport failure that stalls the queue.

## A-006 — Attachment Bytes Outside Structured Sync

**Decision:** PowerSync synchronizes target attachment metadata and canonical
object paths only. A separate durable media queue uploads bytes.

**Reason:** Binary data would inflate sync cost, local databases, and initial
sync time. Object storage supports purpose-built upload and delivery behavior.

**Consequence:** A parent entity and attachment can be locally visible before
the object upload completes. Object upload and metadata reconciliation require
their own idempotency and failure state.

## A-007 — Target Authentication Choice

**Decision (user, 2026-09-13):** Use Supabase Auth for the target launch.
Do not implement a temporary Firebase Auth bridge. The provider choice is
settled; existing-user identity migration, linking, invitations, recovery and
PowerSync authorization still require implementation and verification.

**Reason:** The user selected Supabase Auth to consolidate the target backend
and remove the Firebase identity dependency.

**Consequence:** Ledger uses an internal principal ID and an issuer/subject
identity mapping so a later Auth migration does not rewrite domain ownership.
This choice does not authorize production identity access/migration, hosted or
paid resource provisioning, or cutover. Preserve existing email/password and
Google entry capabilities and approved offline access behavior.

**Evidence protocol:** Validate the selected Supabase Auth path against S2's
security, migration and recovery requirements. Historical provider-comparison
instructions do not require building or testing a Firebase alternative now.
Provider selection is not evidence that migration or hosted integration works.

**Implementation checkpoint (2026-09-13):** Pin official `supabase-swift`
2.55.2 and use its Auth product for session persistence/refresh rather than
implementing token rotation in Ledger. The category RPC accepts the shared
`AuthClient`, bound to the Auth user UUID selected for its workspace; it rejects
a missing, changed or anonymous identity before sending queued work. The UUID
check is a transport safeguard, not authority to read an Account: server
principal/membership checks and local workspace-removal fencing remain required.
Online refresh failure does not authorize deletion of offline data.

Eight focused HTTP/Auth tests (including expired-token refresh, session reopen,
identity switch, sign-out and anonymous denial) pass in0.283s:
`/tmp/ledger-category-auth-identity-refresh-tests.log`. The existing local
category integration launcher now also supports `--native-auth-sdk`: a unique
local test user signs in and refreshes through real Supabase Auth, uploads the
encrypted/restarted queue through PowerSync scheduling, retries a lost response,
and verifies authoritative category rows before cleaning the exact fixtures.
Both cases pass: `/tmp/ledger-category-real-auth-explicit-transport.log`.

The initial real-network run crashed in the SDK's default async HTTP callback
(`swift_task_dealloc`; `/tmp/ledger-category-real-auth-local.log`). Passing the
same real `URLSession` transport explicitly via `fetch` avoids the observed
crash. Use that configuration during app integration; this is a verified local
workaround, not a proven SDK/compiler root cause or an upstream SDK patch.
Mock HTTP tests did not reveal it. Actual app login/startup, platform Keychain
behavior, Google configuration and hosted replication remain unverified.
API reference: [Swift sign-in](https://supabase.com/docs/reference/swift/auth-signinwithpassword)
and the pinned SDK's `AuthClient.session`/`Configuration.fetch` source.

**Presentation reuse:** `Views/AuthView.swift` now contains the original form as
`AuthFormPresentation`, with three injected provider actions and diagnostic text.
The original binding is a conditional thin wrapper; the target compiles the
same form and existing `SegmentedControl` without Firebase. Layout, mode changes,
confirmation, loading and error handling are preserved. Successful sign-in does
not activate an Account. The target root now routes through
`TargetOnlineAccountEntryView`, the original forms, and explicit selection.
`spike_authorize_workspace` separately checks current membership under RLS;
`SupabaseWorkspaceAuthorization` checks returned Account/Principal and credential
identity. The workspace receives those IDs instead of hardcoded test IDs. It no
longer opens a synthetic Project or Transfer source at launch. The target's
public configuration identifies the single approved Ledger project in PPM.
No hosted schema/data deployment or production migration has occurred.

Before any workspace readers start, downloaded membership must match the
server-confirmed role and financial scope. Missing, removed or changed scope
withholds presentation and retains local data; it does not rewrite PowerSync
membership from an HTTP response or approve an O-058 recovery/reduction policy.
The entry path now starts the existing runtime's SDK connection before waiting
on its category-directory stream and checking downloaded membership. The
connection checks the physical workspace's environment/Account/Principal before
any credentials or downloads, then binds Client, Project and category uploads to
the selected Auth user through `SupabaseWorkspaceCommandRPC`. This maps existing
commands; validation, durable delivery and result handling remain in their
existing owners. The real PowerSync URL is still unconfigured, so the app reports
that setup requirement and retains local work rather than claiming downloads.
Offline reopening now uses persisted local admission independent of SDK refresh
(A-016 below). Account creation and safe sign-out are visibly disabled until
implemented. Google/callback and actual entry interaction still require
verification. Reauthorization/removal during an already-running sync connection
is not yet connected; do not call this release-ready.

Authenticated Account discovery now uses `spike_read_authenticated_accounts`,
a security-invoker RPC that resolves the signed-in user's existing Ledger
principal and active memberships under RLS. An unlinked identity is an error,
not an empty Account list; the lookup creates nothing and selects no Account.
`SupabaseAuthenticatedSession` binds SDK credentials to one Auth user, and
`SupabaseAuthenticatedAccountLookup` checks that identity again before returning
the existing Account-selection snapshot. Neither grants offline workspace access.
Local evidence: 14 lookup SQL assertions and the full 1,083-assertion SQL suite
passed (`/tmp/ledger-auth-account-lookup-sql.log`,
`/tmp/ledger-auth-account-lookup-full-sql.log`); 10 native HTTP/Auth tests passed
(`/tmp/ledger-authenticated-account-lookup-native.log`). Real local Auth lookup
and category upload/restart/replay integration also passed
(`/tmp/ledger-auth-account-directory-local-integration.log`). These are dirty-tree
local results, not hosted deployment, fresh migration-history, Keychain or
integrated app-startup proof.

Native Keychain coverage now verifies that the SDK restores an expired session
from a uniquely scoped Keychain service without a network request, does not read
it through another service, and removes only the test credential. The focused
test passed in 0.055s (`/tmp/ledger-category-auth-keychain-fixed.log`). Its initial
failure was a test assumption: the SDK throws `errSecItemNotFound` for missing
items instead of returning nil; absence assertions now check the exact Security
framework status. No custom credential store is needed. This proves same-process
client reconstruction using real Keychain storage, not device/app-process restart,
Account activation, or authorization to open offline data.

`SupabaseOnlineSignIn` now provides email sign-in, signup (including the
email-confirmation/no-session result), Google OAuth through the SDK, and the
authenticated directory lookup. It serializes entry requests and exposes safe
errors; a failed directory lookup retains the signed-in session and does not
become an empty directory. Native live configuration uses SDK Keychain storage
namespaced by target data namespace and Supabase origin; it is not a new session
store. Tests cover password/directory behavior (12 passed,
`/tmp/ledger-online-sign-in-native.log`) and signup/provider errors (2 tests,
including both confirmation cases, `/tmp/ledger-online-sign-up-native.log`).
The existing real local category integration now uses this entry binding and
passes normal/replay cases (`/tmp/ledger-online-entry-category-integration.log`).
Google provider/callback interaction and end-to-end app entry remain unverified.

`Views/AccountGateView.swift` now exposes the same picker/empty/loading form as
`AccountGatePresentation`, using callbacks for selection, creation and sign-out.
The original conditional wrapper retains original discovery/selection behavior;
the target presentation never automatically selects an Account. Both platform
builds pass (`/tmp/ledger-account-gate-macos-build.log`,
`/tmp/ledger-account-gate-ios-build.log`); these are compilation checks, not
interaction/activation proof. Account creation, explicit authorized activation,
session-ending safeguards and offline reopening still need their actual app
bindings before this is a complete entry workflow. The online activation RPC
passed12 SQL assertions and the full local SQL suite1095. Native authorization
response/denial checks passed1 test, and cached-permission admission passed5 cases
(matching, missing, reduced, removed, foreign). Real local Auth/category replay
integration passed with the new authorization call. Logs:
`/tmp/ledger-workspace-authorization-sql.log`,
`/tmp/ledger-workspace-authorization-full-sql.log`,
`/tmp/ledger-workspace-authorization-native.log`,
`/tmp/ledger-workspace-activation-cached-scope.log`,
`/tmp/ledger-workspace-authorization-live.log`.
Both guarded-root builds pass (`/tmp/ledger-authenticated-root-guarded-macos.log`,
`/tmp/ledger-authenticated-root-guarded-ios.log`); no root UI-interaction pass is
claimed. Environment checks now accept the reviewed pinned Auth SDK and require
the unreleased-build banner instead of mandating synthetic startup IDs. The
existing vendor-parser source-list and excluded image-view checks still fail
separately; overall conversion/CI is not green.

Connection follow-up: Client/Project request mapping passes1 native test
(`/tmp/ledger-workspace-transports-native-fixed.log`); startup readiness,
cancellation/close, changed financial scope and foreign database rejection pass
7 cases across2 tests (`/tmp/ledger-category-startup-readiness.log`). The app's
real local Auth/category upload binding passes restart and replay
(`/tmp/ledger-workspace-sync-category-live.log`). Both updated platform builds
pass (`/tmp/ledger-startup-sync-macos-build.log`,
`/tmp/ledger-startup-sync-ios-build.log`). These prove transport/startup behavior
locally, not live PowerSync replication or offline app-entry completion.

**Client/Project timestamp compatibility:** The combined category-to-Project
integration exposed `project_setup_envelope_mismatch`: these new command
constructors retained submillisecond `Date()` values although their existing
RPCs require integer milliseconds and the queue stores integer milliseconds.
New Client/Project commands now floor the timestamp before constructing their
draft/envelope/fingerprint, matching the category command's existing convention.
The shared codec and stored-command decoders are unchanged: previously accepted
envelopes/fingerprints are not rewritten or silently repaired. Existing malformed
pending commands still need explicit recovery; this change only prevents new
ones. Ten focused contract tests pass, including fractional input and preserved
legacy fractional-envelope decoding (`/tmp/ledger-create-command-timestamp-fixed.log`).
Initial legacy tests incorrectly treated scalar fingerprints as JSON objects;
both test fixtures were corrected, with the failed log retained.
The real local Auth/SDK test then passed queued Client/category/Project creation
across encrypted restart, verified the Project's Client/new-category links in
Postgres, and retained category replay coverage
(`/tmp/ledger-inline-category-project-timestamps-fixed.log`). The52 existing
Client/Project storage and Project form tests also pass in2.385s
(`/tmp/ledger-client-project-timestamp-consumers.log`). No schema change, hosted
deployment, or new Project allocation policy was required.

### Live Invoice source-edit serialization (2026-09-16)

Current Item-price and Expense edits lock an existing live Invoice before its
source, then recheck membership after obtaining the source lock. This matches
Invoice revision ordering and prevents accepted source edits from independently
validating the same old total. Live totals remain derived, not duplicated in a
new stored aggregate. Validation runs inside the mutation's rollback boundary;
failure retains the existing durable rejected-operation response. Expense
receipt handling, source identity and frozen accounting are unchanged. The
Expense overflow regression failed before the change and passes afterward.
The final empty-application-schema migration replay and concurrency run passed,
including competing Item/Expense edits in both orders, collection races, and
rollback recovery (`/tmp/ledger-price-final-replay-races-20260916.log`). The local
security advisor reported no warning/error issues. Native offline restart,
upload, and PowerSync readback also passed; see the existing Item-editing
checklist evidence. These are local results, not hosted deployment or cutover
authorization.

### Account onboarding boundary (2026-09-16, implementation in progress)

Account creation requires READ COMMITTED, matching existing transactional
commands: after locking the existing Principal, membership and retry-receipt
reads must see the preceding creator's commit. Reject other isolation modes
rather than permit a stale empty-membership snapshot. The real concurrency
harness verifies this rejection and same/different-request-key serialization.

Account onboarding implementation (2026-09-16): preserve the existing zero-Account
gate's `My account` action and source defaults (Furnishings, Install, Design Fee,
Storage & Receiving), but make Account, owner membership, categories and canonical
Furnishings identity one transaction. A private authenticated command serializes
submissions on the Principal row and records an identity-scoped request UUID;
matching retries return the same Account, changed payloads fail, and a new request
cannot create another Account while active membership exists. Clients cannot
supply owner/role/Account IDs. Existing RLS controls readback; private receipts
are not readable by clients. This replaces the source's separate preset seeding,
not its UI. Explicit Account selection remains required. Initial implementation
uses a separate explicit identity-bootstrap RPC before read-only discovery when
needed. It inserts only an Auth-subject-bound Principal, preserves an existing
binding under concurrent retry, and grants no Account membership. The native
creation port carries a typed request UUID and Account name; its provider checks
identity again after each response. Durable retry, real local readback/concurrency
and the targeted iPhone creation flow are verified in the owning checklist;
hosted rollout and broader entry/recovery acceptance remain separate. Entry stores a per-user,
per-environment request UUID in the existing protected admission record before
the network write; timeout/reconstruction reuses it, and a confirmed response
clears only the matching request. Cleanup does not silently erase these retry IDs.
Only exact server `identity_not_linked` failure triggers explicit preparation and
one new read; generic lookup failures never imply empty Accounts or new identity.
The original Create Account action requires authoritative emptiness, creates the
fixed original `My account` name, then refreshes the picker without activation.
Never infer identity linking from email or treat an unmapped user as authoritative
zero membership. O-057 migration/linking questions remain distinct from this flow.

### Session-ending shutdown boundary (2026-09-16, implementation in progress)

Account-entry follow-up: the existing coordinator also accepts an explicitly
persisted empty workspace plan for an identity with no downloaded Accounts.
The admission store checks its complete local directory before saving that plan;
an empty server membership response is not evidence of no local work. Recovery
distinguishes an approved empty plan from a missing plan, performs cache/provider
cleanup without database fences, and clears the identity marker last. The entry
action refuses downloaded (including removed) Accounts and directs review through
Settings; it does not authorize discarding retained work. This reuses the original
Account gate and sign-out coordinator, not a second Auth-only bypass. Targeted
native and UI verification are required before accepting this entry path.

The existing target Settings now binds ordinary Sign Out to the live workspace's
`SupabaseOnlineSignIn.sessionEnding` adapter. The workspace owner reuses its
presentation stop path and the existing report scratch cleanup; successful
completion returns to the existing entry form. Pending work refuses ordinary
logout. Settings reuses Pending Local Work for sync-first and exact-summary
discard confirmation. Sync-first refreshes local evidence while existing sync
runs; cancellation/disappearance stops waiting. Discard binds the displayed
counts to the existing policy request; other Accounts still must be clean.
Startup and Retry invoke saved-plan recovery before Account entry. UI evidence
and remaining end-to-end gaps belong to the existing session stories.

Session cleanup uses the existing `recoverStartupScratch` helper with strict
active-session checking. Ordinary report startup still skips locked exports;
logout/recovery instead throws while another export owns its scratch session,
preserving the file and durable cleanup intent until that handoff finishes.
This avoids declaring cache cleanup complete merely because active files were
skipped. It does not forcibly cancel OS sharing or delete its in-use files.
ReportScratchStoreTests covers refusal, byte preservation, and later success.

Late export generation is now covered by the runtime's existing finite-operation
drain: Property, Client Summary and Invoice previews hold one report activity
from generation through completed OS handoff. Shutdown refuses new activities
and waits for admitted ones before cleanup. This is not a new job registry.
The tradeoff is that sign-out may wait for a sharing/printing interaction to end;
it must not delete files the OS still uses. The delivery helper recognizes the
live LedgerOfflineClientRuntime reader; pure fixture readers have no runtime to
drain. Any future live reader wrapper/provider must carry this lifetime too,
not silently rely on the fixture path. Native drain and late-admission tests
cover the live helper. Targeted iPhone Property/Client Summary/Invoice handoff
regression and both platform builds pass; macOS interaction evidence remains.

Real multi-Account owner tests exposed unconditional iOS file protection in the
database directory creator: on this macOS host the resulting directory rejected
file creation (SQLite CANTOPEN). It now follows the attachment vault's platform
guard, retains complete protection on iOS/tvOS/watchOS, and creates owner-only
0700 directories on all platforms. SQLCipher and scoped Keychain keys remain
unchanged. Native live-secondary-Account cleanup/recovery passes all four cases;
the changed iOS branch still needs targeted build/runtime verification.

The runtime now reuses its existing close/drain path for a final session-ending
policy check. A temporary workspace fence excludes other handles and new opens;
admitted writes finish, watches/uploads drain, and replication disconnects before
the exact pending summary is checked again. Cleanup is called only after both
databases close successfully and the final policy evaluation permits teardown.
The fence remains held during cleanup. This is not the permanent membership-
removal fence: voluntary logout must not prevent a later authorized sign-in.

A changed summary refuses cleanup and preserves the databases and captured work.
That race leaves the runtime closed, so the caller must reopen it to resume work.
Already-pending sync-first requests are rejected before shutdown instead of
stopping the sync needed to settle them. No collection, history, or retention
policy changes. The internal callback is not a feature-screen signout API.

`LedgerWorkspaceSessionCleanup` now stores the approved request and exact
resolved workspace binding in device-local Keychain before deleting the owned
workspace directory and its two exact encryption-key records. Recovery reuses
that intent, never a newly generated empty summary. It is idempotent after
partial deletion. Bootstrap checks for pending cleanup before loading keys and
again before exposing the runtime; malformed intent also denies access. The
marker cannot be cleared while the workspace directory or either key remains.
A changed configuration/location is refused rather than deleting another path.

The existing offline-admission record also retains an identity-level ending flag
and all affected Account admissions until cleanup succeeds. Existing version-1
records decode without that optional flag. A changed Account directory refuses
the transition. A flagged identity cannot restore offline access, select itself,
remember another admission, load online Accounts, or reuse a bound access-check
closure. Other identities remain separate. This is a recovery directory and
access lock, not approval to delete any Account's pending work. The shared
`SupabaseAuthenticatedSession` credential path checks the local flag both before
and after token refresh. OnlineSignIn binds that check to all its derived
identities. This also stops previously created RPC readers without adding a
network membership check to each call; the RPC's 403-only revalidation callback
alone was insufficient for this purpose.

The provider final step uses `AuthClient.signOut(scope: .local)`, not its global
default. The pinned SDK removes its stored session before its network request;
the wrapper distinguishes SDK request completion from local-only completion on
network failure and refuses a changed identity. Neither result claims immediate
invalidation of already issued access tokens. Current Swift reference checked
2026-09-16: https://supabase.com/docs/reference/swift/auth-signout (saved privately
in `.firecrawl/supabase-swift-signout-20260916.md`); pinned AuthClient/SessionStorage
source establishes ordering. Coordinator cleanup remains responsible for durable
admission/intent completion and must not bypass protected-storage errors.

`LedgerSessionEndCoordinator` preflights every supplied Account before closing
any, then nests the existing guarded shutdowns to hold every open fence through
cleanup. It orders durable identity intent, all per-Account intents, physical
cleanup, cache/provider cleanup, per-Account completion, then identity completion.
Another Account's pending work refuses the whole attempt before deletion.
Locations come from the opened runtimes, not caller-reconstructed paths.

The coordinator now calls the real admission store directly: one atomic record
write saves every approved `SessionEndRequest` with the identity ending flag
before any per-Account intent or deletion. Missing/duplicate Account requests,
changed directories and attempts to replace a saved decision are refused.
Recovery can retrieve the full set even if per-Account setup was interrupted.
This replaces the placeholder identity-persistence/completion callbacks.
The same atomic plan includes each runtime's physical cleanup binding (a digest
of its resolved database/media paths, key namespaces and stable scope). Recovery
must verify that binding before deletion; matching only Account/Principal IDs
would incorrectly permit a different manifest or application-support root to
retarget consent. Older/incomplete ending records without a matching binding
remain locked rather than being upgraded into destructive authority.

`SupabaseOnlineSignIn.sessionEnding` now returns the concrete AccountSessionEnding
adapter. It gathers saved Accounts, refuses missing/differently-versioned local
databases rather than creating clean substitutes, opens other downloaded Accounts
for a clean-only disposition, and binds the coordinator to the existing Auth owner.
Caller-supplied cache cleanup precedes the actual device-scoped provider signout.
Pending work in another Account is not implicitly approved for discard.

Remaining implementation: wire the existing Settings action/cache owners and
invoke the Auth owner's `recoverPendingSessionEnd` from startup/retry. That method
discovers pending identities, resolves their originally bound locations, invokes
the coordinator and preserves any different current provider identity. It reports
recovery failure without unlocking saved Accounts. `LedgerSessionEndCoordinator.recover`
validates every saved request and original physical binding, fences all closed
workspaces, then reuses normal cleanup. Missing per-Account markers are recreated
only from the complete approved plan; failures retain that plan for retry. It
does not open a database or infer consent from empty/new data. Bootstrap denies
pending cleanup; automatic startup invocation and complete app signout are not
yet delivered. Focused real-database evidence belongs to the existing
session-ending checklist stories.

## A-008 — No General-Purpose Dual Writing

**Decision:** Do not make clients permanently write Firebase and Supabase for
the same business operation.

**Reason:** Two offline queues can apply in different orders, reject differently,
and make authority ambiguous.

**Allowed exceptions:** Read-only shadow calculations and deterministic
migration correlation. Neither exception is an application dual writer.

## A-009 — Expand–Migrate–Switch–Contract

**Decision:** Additive structures precede data migration; authority switches
only after reconciliation; destructive cleanup follows the rollback window.

**Reason:** Old clients and offline pending writes cannot safely consume a
destructive in-place change.

## A-010 — Provider-Independent Principals

**Decision:** Domain membership references a Ledger principal, not a Firebase UID
or Supabase Auth UUID directly.

**Reason:** Authentication providers issue different subject formats and may
change. Membership and audit identity must remain stable.

**Evidence required:** RLS helper and PowerSync Sync Stream join performance.

## A-011 — Encrypted Local Database

**Decision:** Encrypt the local structured database and store its key in the
platform Keychain.

**Reason:** Offline operation places account and financial data on the device.

**Consequence:** Key creation, rotation, pending-work disposition before logout
deletion, restore behavior, and multi-account storage are explicit lifecycle
responsibilities. Routine logout cannot silently destroy queued operations or
unuploaded media.

## A-012 — Superseded Firebase-Adapter Proposal

**Status:** superseded by A-017. Do not implement.

**Original proposal:** Wrap current Firebase behavior behind the new ports
before replacing it.

## A-013 — RLS and Sync Stream Authorization Symmetry

**Decision:** RLS authorizes writes and direct API reads. Sync Streams separately
authorize downloads. Both derive access from the same principal/membership and
financial-access facts.

**Reason:** PowerSync download rules do not authorize uploaded changes, and RLS
alone does not prevent the sync service from downloading rows selected by an
over-broad stream.

**Consequence:** Every access-control change has paired RLS and Sync Stream tests.

## A-014 — SDK Types Are Infrastructure-Only

**Decision:** Vendor timestamps, user objects, snapshots, rows, errors, storage
references, listeners, and upload entries are mapped before crossing a port.

**Reason:** SDK types are the most common source of accidental infrastructure
coupling.

## A-015 — Complex-Command Optimistic Projection

**Status:** blocked pending vertical spike.

The chosen implementation must satisfy all of these semantics:

- one local atomic acceptance;
- durable survival across restart;
- immediate useful UI projection;
- one server command and one idempotency key;
- clean rollback/reconciliation on rejection; and
- no stuck global upload queue for a permanent validation failure.

Candidates are a pending-operation overlay, tagged optimistic row mutations, or
a hybrid. The spike must compare query complexity, PowerSync upload grouping,
rollback behavior, and cross-screen consistency before this decision closes.
The exact S5 fixtures and hard failures are defined in the
[isolated vertical-spike protocol](../../plans/ledger-accounting-redesign/vertical-spike-protocol.md).

## A-016 — Offline-Access Lease

**Status:** no-expiry, device-unlock and learned Account-removal behavior approved on 2026-09-07; financial access reduction and recovery procedure remain open.

A disconnected device cannot receive membership revocation. The user chose no
offline time limit for previously downloaded work and the device's normal
unlock with no additional Ledger biometric/passcode/PIN prompt. Do not add a
finite authorization lease or treat provider-token expiry as local-data expiry.
This choice does not authorize new downloads or override revocation learned
online. On learned Account removal, immediately lock normal Account reads/edits
and stop uploads under the removed Principal's permissions. Retain unsynced
operations and media encrypted for a separately approved recovery process; no
automatic upload, export, reassignment or recovery access is implied. These
approved rules can be implemented without choosing a recovery procedure.
Financial scope reduction short of Account removal and the recovery procedure
remain open under O-058; full hosted activation/security readiness is not proved
by this product decision.

**Local admission binding (2026-09-13):** `OfflineWorkspaceAdmissionStore` keeps
previously downloaded Account summaries and their authorized identity/scope in
a separate Keychain service, namespaced by target build and Supabase origin.
It contains no bearer credential, expiry or extra unlock prompt. The existing
Keychain wrapper stores these records separately from encryption keys. iOS uses
WhenUnlockedThisDeviceOnly; macOS uses its login Keychain (the macOS tests do not
claim proof of iOS lock-state enforcement). Supabase token expiry or loss alone
does not revoke local admission. Switching signed-in identity hides the former
identity's admissions without deleting its data. Future session ending must
revoke admission as part of its coordinated cleanup; sign-out remains disabled.

`rememberDownloadedWorkspace` requires current Auth identity, complete category
download evidence, matching physical workspace and matching downloaded
membership before persistence. The reused Account picker offers downloaded
Accounts first, without an online round trip; selection rechecks the saved grant,
the existing monotonic removal registry and local membership. Missing/corrupt
records, unavailable protection and mismatched permissions fail closed. A
missing database cannot become authorized merely because its record survived.
Sign-in/refresh remains separate and cannot manufacture a downloaded grant.

An exact authenticated `workspace_access_denied` response during online
selection now enters the existing shared removal coordinator: fence all open
handles, persist denial, then drain/close while retaining pending work. Token
failure, malformed response, unrelated403 and outage do not become revocation.
Selection must match the last directory's identity/fingerprint, preventing a
later signed-in user from using an old selection to revoke the former Principal.
**Active-sync removal binding (2026-09-13):** the app's bound provider now
revalidates the existing workspace through `spike_authorize_workspace` before
each PowerSync credential grant. Client/Project/category upload transports
revalidate after HTTP403, not after every successful operation. Only the exact
authenticated membership denial records removal; expiry, outage, malformed or
unrelated denial, and changed signed-in identity cannot manufacture it. A changed
role/financial scope withholds new credentials but is not Account removal;
O-058 still owns the local-data disposition. This is event-driven detection, not
an immediate remote-revocation claim or a new polling service.

Removal reporting now fences all registered handles and persists the existing
monotonic marker **without awaiting database drainage inside the SDK callback**.
The existing workspace removal stream wakes the app-owned cleanup task, which
locks presentation and completes the coordinator's existing drain/close outside
that callback. It subscribes before initial sync; its lifetime belongs to the
workspace root rather than a child view removed by the access gate. Cleanup
errors remain visible outside the locked content. Finalization requires an
already-reported fence, so the public completion method cannot initiate a fresh
removal. Persistence failure still fences in-process; finalization retries the
marker and must not claim durable success if persistence/close fails. No pending
operations, media, keys or databases are deleted, and recovery remains gated.

Provider checks and real SDK credential-callback drainage pass in20 tests
(`/tmp/ledger-sync-removal-provider-reviewed.log`,2.593s). The targeted runtime
run passes3 tests/11 cases (`/tmp/ledger-sync-reported-removal-fixed.log`,0.495s):
two upload-callback removal cases include initial persistence failure, immediate
read denial, no self-drain, database close, denied normal reopening and retained
encrypted queued work/media; the run also includes revalidation cases and the
existing persistence-retry test. The provider run adds wrong-denial-code coverage.
Initial test failures were incorrect fixture email/helper names, corrected without
weakening assertions; `/tmp/ledger-sync-access-revalidation.log` and
`/tmp/ledger-sync-reported-removal-runtime.log` preserve those failures.
Both platforms build with the final root-lifetime/cleanup-error wiring
(`/tmp/ledger-sync-removal-macos-reviewed.log`, `/tmp/ledger-sync-removal-ios-reviewed.log`).
Actual hosted removal propagation and root-to-service integration remain unverified.

Evidence:6 local admission/Auth tests passed (`/tmp/ledger-offline-admission-verified.log`),
including expired/missing sessions, user switching, removal/protection failure,
corrupt storage and real Keychain reconstruction. Runtime admission passes3 cases
(`/tmp/ledger-offline-admission-runtime-fixed.log`): incomplete/reduced access
cannot grant; allowed admission survives a queued category edit and encrypted
reopen. Its download-complete signal is injected, not hosted replication proof.
Exact-denial/identity/callback-failure test passes
(`/tmp/ledger-online-denial-identity-bound.log`). Both offline-entry builds pass
(`/tmp/ledger-offline-entry-macos-build.log`, `/tmp/ledger-offline-entry-ios-build.log`);
the later denial-binding change is native-tested. The actual reused Account and
Auth forms now pass the offline-entry interaction on macOS (1 test/23.108s,
`/tmp/ledger-offline-entry-ui-macos.log`) and iPhone (1 test/17.266s,
`/tmp/ledger-offline-entry-ui-ios-signed.log`): explicit selection, Sign In/back,
no stored online session, and protected admission across app termination/relaunch.
The DEBUG fixture seeds only a synthetic admission under a unique Keychain
namespace and uses an `.invalid` endpoint; its destination asserts selection,
not database readiness or replication. The initial iOS selector ran zero tests;
the corrected unsigned run failed Keychain access (-34018). Ad-hoc signing
resolved that prerequisite without a storage bypass; CI now requests it too.
Device restart/lock and actual hosted first-download behavior remain unverified.
No hosted provisioning or schema change occurred.

The implementation may not claim immediate offline revocation. Logout and local
account removal must follow the pending-work disposition policy, then clear the
database and encryption key regardless of the lease choice. Explicit destructive
discard is permitted only with the confirmation and cleanup semantics defined in
the offline architecture.

S3/S4 of the
[isolated vertical-spike protocol](../../plans/ledger-accounting-redesign/vertical-spike-protocol.md)
collect enforcement evidence. They must honor the approved no-expiry/device-unlock
choices and cannot decide remaining recovery policy or copy without approval.

## A-017 — Firebase Is a Migration Source Only

**Decision:** Leave the released Firebase application operational and
substantially untouched while the Supabase/PowerSync app is built and tested in
isolation. Firebase-specific work is limited to read-only export, migration
mapping, final pending-write disposition, write freeze, backup, and retained
rollback evidence. No Firebase repository, listener, writer, Function, rule, or
Storage implementation is made to conform to the redesigned application ports.

**Reason:** A Firebase adapter would be throwaway implementation work and would
risk implementing the redesign twice. Target port contracts are proven by the
Supabase/PowerSync implementation and deterministic test adapters.

**Consequence:** The cutover is a rehearsed data migration plus authority
switch. The old Firebase binary may continue to exist on devices, but the frozen
Firebase backend rejects post-cutover writes and the new app uses only the target
data implementation.

## A-018 — One Fail-Closed Local OperationID Ownership Inventory

**Decision:** `OperationID` is one global idempotency namespace, not a namespace
per Account, device, payload, or command family. Within one encrypted Account
database, `local_operations.id` is the normal ownership claim and every
operation-bearing local relation participates in one centralized integrity
inventory before any command admission or replay.

**Reason:** An insert-only command view's `ps_crud` entry, synchronized result,
forbidden local result-table queue mutation, pending projection, or overlay can
outlive or become detached from the generic operation
row. Checking only one family view or only the generic row allows malformed
evidence to be silently rebound to another family and makes later replay,
upload, and reconciliation ambiguous. The pinned PowerSync insert-only trigger
writes the queue entry without persisting a second backing command row, so the
inventory follows that actual storage contract.

**Consequences:**

- one typed same-family owner may proceed only to state-aware exact provider
  validation; a terminal row may stand alone only where that family's existing
  lifecycle drains auxiliary evidence, while incomplete nonterminal or untyped
  rows fail closed and no new cleanup is implied;
- a different family or changed payload returns a stable mismatch;
- orphaned, malformed, ambiguous, or multi-family evidence reserves the ID and
  fails closed without repair or deletion;
- claim, inspection, and family writes share one serialized local transaction;
- schema/source controls reject an unregistered operation-bearing relation or
  accepting provider; and
- local enforcement covers one physical Account database, while globally unique
  generation and the authoritative server result key cover separate devices.

This decision adds no second local registry table and chooses no cleanup or
retention behavior. It does not advance A-003, A-004, A-015, A-016, hosted
resources, migration execution, or production authority.

## A-019 — Preserve Meaning, Improve Item Relationship Storage

**Decision:** D-028 permits replacing legacy structures where a concrete
correctness, simplicity or maintainability benefit exists. Acquisition,
placement, billing and payment use explicit relationships; history is read from
those facts rather than a second competing accounting authority. Existing
Transaction links and lineage already represent important history. They are
source evidence to preserve and reconcile, not missing functionality or a reason
to discard relationships.

**Reason/tradeoff:** Explicit relationships support database constraints and the
confirmed accounting redesign, but require careful migration and may need more
tables. Prefer shared existing contracts; avoid a universal event store or
speculative generality. Improve concrete table details during implementation.

**Preservation and evidence:** The existing
[Item relationship note](../../plans/ledger-accounting-redesign/decision-packets/O-007-O-015-item-accounting-and-provenance.md#verified-source-relationships)
records inspected source fields, settlement links and lineage writers. Preserve
stable Item identity, historical amounts and relationships, original source
correlation and unresolved evidence. It is source inspection, not proof of a
completed target or migration. Target cycle/readback/reconciliation tests remain
required in the unified checklist's `accounting-relationship-provenance` and
`item-cycle-provenance` outcomes. Financial policy, information loss and
production/hosted actions retain their separate approval boundaries.

**Source reconciliation boundary:** Resolve historical links from exact
`accounts/{account}/items|transactions|projects/{id}` paths, not current Item
membership or exporter classification labels. Preserve every input document;
duplicate, malformed or foreign-Account records cannot satisfy references.
Lineage document faults also prevent that edge from advancing to semantic
mapping. This deliberately quarantines uncertain history instead of choosing a
plausible relationship. `FirebaseLineageSourceReview` connects these checks to
the existing validated fixture reader; source-shaped cycle tests are separate
from the frozen v1 fixture, whose simplified movements do not prove shipped
lineage coverage. Neither structural reconciliation nor a `returned` label
establishes a client refund, paid occurrence or completed target import.

The shipped `InvoiceLine` stores Item identity but no explicit occurrence or
lineage-edge identity. A historical Invoice/line ID remains valid billing
evidence; it is not proof of a specific sale/return edge. Do not manufacture that
link from the Item's current Transaction/Project or timestamps. Unproved cycle
correlations remain migration gaps rather than blocking independent target work.

`FrozenInvoiceContents` is the shared immutable value representation for the
positive-Invoice paid-history path. It retains exact source identities/revisions,
Item occurrence and explicit price-basis snapshot, category, label and signed
money under one Invoice and Purchase reference. Scope, duplicate billing,
currency, total/category overflow and decoded values are validated. Current Item
placement is not a field or lookup dependency. The writer must still prove
source/price/category eligibility and actual payment, and enforce database
immutability and authorization; this value alone does not collect an Invoice.
Manual adjustments and nonpositive settlement remain separate product decisions.

**Frozen-content storage under implementation (2026-09-08):** Private collected
Invoice headers and ordered lines retain frozen allocations against one existing
Purchase with exact Account/Project/Client/currency linkage. Invoice allocation
total and actual payment amount remain distinct facts pending O-033; the storage
boundary does not decide payment equality. Deferred validation requires a
nonempty, contiguous ordered line set, exact signed Invoice total and in-range
category totals. An internal assembly/seal flag prevents later additions—even
net-zero lines—as well as edits/deletions. This flag is not a new product phase.

The tables reuse existing Purchase and physical Item identities without changing
the Firebase-import-only Purchase origin or opening API grants. This is not a
collection command: referenced occurrence/Expense/Fee eligibility and runtime/concurrent
verification remain required. The private idempotent writer returns ordered source
records; the Swift transport reconstructs the existing typed frozen contract,
keeps money/revisions as exact decimal strings, and compares indexed source links
by UTF-8 bytes rather than Swift's Unicode-equivalent string equality. Focused
transport tests pass; an actual database-to-Swift round trip remains required.
Retaining a source JSON object is not proof that
its referenced business event exists. Tests are in
`supabase/tests/collected_invoice_contents.test.sql`; local execution is pending
the unavailable Docker engine. No payment, migration or cutover is authorized.

The downloaded Item location-history view (2026-09-08) reads the existing placement
intervals through the same authorized local runtime; it does not add a second
history store or start a broader subscription. Missing historical labels and
older downloads remain explicitly partial. Physical locations never imply a
sale, payment or refund. Ordering compares whole seconds and retained fractional
precision, rather than SQLite's rounded date arithmetic; malformed dates and
overlapping occupied intervals fail closed. Reader tests cover access removal,
exact boundaries and encrypted reopen. Native interaction and full financial
history remain separate verification obligations.

**Physical storage (2026-09-07):** `spike_items` owns permanent physical identity;
`spike_item_placements` owns Inventory/Project/optional Space intervals. Composite
foreign keys preserve exact tenant/scope relationships. A Postgres GiST exclusion
constraint prevents overlapping intervals, including concurrent writes; a partial
unique index also bounds active placement to one. Closing a placement is its only
ordinary update; ended history cannot be rewritten, deleted or truncated. The
security-invoker current-placement view derives location without any stored
accounting-status flag or payment inference. This uses PostgreSQL's supported
`btree_gist` extension rather than an application-only overlap check.

This is required storage, not a completed movement API. RLS is forced and no
app/service-role grants are issued. The future typed command must check actor and
Item revision, atomically close/open placement plus required accounting facts,
and handle rapid offline transitions with ordered timestamps. The schema permits
unplaced Items/history gaps; its current-location view cannot certify inventory
completeness. Creation validation, write permissions, correction/removal policy
and financial visibility retain their product gates. Local cycle/rollback/scope/
immutability tests live in `supabase/tests/physical_item_placement_history.test.sql`;
actual authorized app/MCP/Sync movement and paid-history joins remain unproved.

The local PowerSync schema now represents those physical tables;
`CurrentItemPlacementLocalReader` validates membership and exact parent/scope
evidence in one SQLite snapshot. It returns downloaded physical rows only, with
Item revision and placement identity separate. It must not turn Item revision
into an assignment precondition until movement and assignment share a proven
revision contract. Missing/contradictory downloaded parents fail closed; unseen
rows remain unknowable without a scoped stream-completion contract. No new
Sync Stream, grants, accounting classification or inventory-completeness claim
is introduced by registering local table shapes.

**Physical read authorization:** The subsequent member-read migration grants
authenticated callers SELECT on named physical columns only, constrained by
current Account membership. No Item writes, private-view/service-role access or
financial facts are opened. Column-level grants and explicit Sync projections
prevent future financial columns from inheriting this permission. The manually
subscribed `physical_account_items` stream binds both requested Account and
authenticated Principal to active membership; it includes physical placement
intervals and active Spaces, not payment/Invoice evidence. Existing bootstrap
provides Projects. An archived or undownloaded Space remains missing evidence,
not an invented unassigned location. Local RLS and source-SQL checks plus review
do not prove hosted stream parsing, revocation propagation or completeness.

**App read boundary:** `DownloadedItemPlacements` is a backend-neutral, read-only
physical projection, not a second history authority or a movement precondition.
The existing Account runtime owns its database and admits reads through its
finite-operation lifecycle gate: normal close drains them; learned removal
suppresses their results. The Project workspace uses that same runtime, with no
synthetic Items or separate database owner. The presenter rejects foreign scope,
canceled and superseded results and clears on disappearance. Focused runtime,
reader and presentation tests pass (45 tests); real stream subscription and UI
interaction proof remain pending. This partial view deliberately reports only
downloaded data, not zero inventory or accounting completeness.

The read port also exposes continuous downloaded snapshots so the screen can
follow local database changes without polling or requiring Refresh. It reuses
the same physical projection and scope checks; it does not add an independent
cache or history model. The runtime must retain the watch task through local
query cancellation and owned subscription cleanup before closing the database.
Reactive lifecycle tests cover delayed subscription, cancellation during setup,
held cleanup during workspace close/removal, and separate concurrent handles.
An additional test uses the real SDK's local subscription registration and
confirms that removing local membership terminates the read. None of this proves
hosted revocation propagation or download completeness. The macOS UI test runner
could not initialize automation, so interaction acceptance remains unverified.

**Explicit client-payment translation:** A non-canceled legacy `paymentToBusiness` record
means actual client payment (`InvoiceService.markCollected` writes category-specific
payment records). Under D-001/D-002 it maps to the target Project Purchase
classification, retaining its exact integer cents and entire source document.
Do not merge historical payments or infer full Invoice settlement from this
classification; the source can represent partial or category-level collection.
`FirebaseClientPaymentConversion` requires a reconciled source→target Project
scope supplied by the migration caller. Other source transaction types, unclear
payers, nonpositive amounts and non-integer money remain unresolved here. This
is a domain transform, not the completed scope-mapping/import pipeline or proof
that historical Invoice allocations reconcile.

Cancellation is checked before active money is mapped. Source `canceled` and
`cancelled` (case-insensitive) remain retained but require historical cancellation
mapping; they cannot export active Purchase parameters. Absent/null status and
known legacy `pending`/`completed` retain the source's non-cancellation meaning.
Other status strings or types remain explicit mapping gaps instead of inheriting
the shipped decoder's unknown-string-as-active fallback. Tests cover the transform,
batch counts/source retention and parameter-export rejection.

`InvoiceService.voidInvoicePayment` leaves settlement links on canceled payments
and Invoice lines. Those links establish history, not current payment or paid
status. Invoice reconciliation must inspect cancellation state; surviving links
must never resurrect money or erase the correction history.

`FirebaseInvoiceCancellationEvidence` resolves explicit `paymentCanceled`
paid-to-sent source events to exact canceled settlement documents. All supplied
records remain retained; duplicate paths/references, missing records, invalid
scope/shape and unclaimed canceled payments stay visible. Recollection remains
separate. This proves source relationships only, not canceled amounts, target
refunds, paid-state reconstruction or permission to import.

`FirebaseInvoiceSettlementReview` checks a narrower prerequisite than collection
mapping: one explicit non-canceled payment covers the exact stable signed source
lines and total. It retains the complete Invoice and every supplied payment;
partial/category-grouped, canceled/mixed, missing-ID, duplicate, dangling-link,
scope and money inconsistencies remain explicit. Line identity comparisons use
UTF-8 bytes, not Unicode-normalized equality. It never generates missing legacy
line IDs, groups payments by timestamp, or creates target paid state. Complete
export coverage, cancellation events, Item occurrence/source resolution and
approved target allocation are still required before importing a collected Invoice.

The same review resolves line source identity against all supplied document
paths: Account-scoped Items/Transactions and Project-nested `feeInstallments`.
Duplicate copies and mismatched scopes remain explicit; all supplied evidence
is retained. An Item's current Project is not substituted for its historical
Invoice occurrence. Resolved Item/Transaction/Fee identities still carry the
unresolved occurrence/economic-mapping obligation; manual adjustments remain
explicitly unmapped. Semantic export labels (`entityCode`) are retained, not
treated as collection names—paths and validated source fields establish identity.

`FirebaseClientPaymentBatch` binds that transform to an exact source Project
snapshot and an explicit target Project/Client assignment, plus stable supplied
Transaction IDs. The source has only `clientName`; equal names never establish
ownership. Duplicate source paths/target identities, changed or missing Project
evidence and sum overflow prevent affected payments or totals from reconciling.
The batch retains one result per input and does not merge category payments.
Mappings may cover a larger import plan: unused entries create no payment and
are not approved by a successful subset. Import approval, complete export
coverage, target persistence and final settlement reconciliation remain separate
requirements.

## A-022 — PowerSync Cancellation Lock Inversion

**Evidence:** Automatic CI run 34173547450 canceled during real failed-bootstrap
cleanup. Its `native-test-stall-diagnostics` artifact and sampled stacks show
PowerSync 1.16.1 (`e6c356aea078dff9cf9cb12b3d1aa3f583ddc98b`)
`MergeItemSequence` resuming a continuation under its state mutex while another
thread cancels that consumer: each waits for a lock held by the other. Main and
independent review confirmed the inversion against the pinned source. Upstream
HEAD and latest release were checked and contain the same defect; PRs 171 and
177 are already included and do not fix this lock ordering.

**Required correction:** Extract the continuation and result while atomically
transitioning state under the mutex; resume only after unlocking. Cancellation
must claim a continuation exactly once, and terminal state must remain terminal
against late events/errors. Preserve real close, watch notifications, encrypted
database paths and data retention; neither test skipping nor delayed shutdown
fixes this defect.

**Scope/tradeoff:** The checked-in `vendor/powersync-swift` copy preserves the
1.16.1 manifest, license, source, tests and required demo sources. Only the two
Swift files named in `LEDGER-PATCH.md` change. The target app's existing local
LedgerTarget package and its tests share this local SDK dependency. Transitive
pins are unchanged. This costs a temporary vendored dependency, but avoids
cache-only patches and per-build patch scripts. Restore an exact upstream pin
when a reviewed upstream correction passes the same tests. No remote fork or
upstream publication is authorized by this note.

**Verification:** Independent review found no continuation-ownership or
lock-order blocker. The corrected SDK passed 600 event/finish/error cancellation
races plus terminal-state regression and the real failed-bootstrap cleanup
matrix. Root tests also exercise normal events, active errors and buffered
errors (vendored dependency tests do not automatically run with root tests).
Integrated native verification and full exact-commit automatic CI remain
required. The canceled run is diagnostic evidence, not passed verification or
cutover readiness.

## A-020 — Imported Client Payment Storage

**Decision:** Begin canonical `spike_transactions` storage with the verified
imported Project Purchase path. Atomically insert its exact integer amount,
explicit currency and Account/Project/Client identity with one private source
record. Composite foreign keys enforce the existing Project's Client and Account.
The source is stored as bytes with a database-derived digest: tagged Firebase
values, NULs and unknown fields must not be coerced into lossy PostgreSQL JSON.

**Retry and retention:** Stable target identity and unique source Account/document
identity prevent duplicate money. An identical retry succeeds; different amounts,
scopes, currency or source bytes conflict and roll back the entire call. Updates,
deletes and truncation of these imported records are rejected. Future approved
corrections must preserve original evidence instead of rewriting history.

**Security/tradeoff:** The import function uses invoker rights in `ledger_private`.
No app/API role, including `service_role`, receives function or table privileges;
both tables enforce RLS. This deliberately leaves app/PowerSync financial reads
unavailable until the relevant policy is resolved. Import-run authorization is a
separate requirement, not something inferred from this SQL primitive. Current
execution requires a trusted operator with direct privileges and RLS bypass;
granting function execution alone is neither sufficient nor a restricted writer
boundary. Any dedicated migration role needs separate security review. The row
immutability trigger is conditional on imported origin so future ordinary
Transaction behavior is not inadvertently frozen.
Current database constraints support only this implemented payment path; normal writes,
Return/Transfer and additional Transaction behavior are not claimed complete.

**Evidence and remaining work:** Local migration `20260907233804` and
`supabase/tests/imported_client_payment_storage.test.sql` verify atomic conflict
rollback, exact cents/source bytes, retry, tenant/Client integrity, immutability
and denied API access. `scripts/test-local-imported-payment-concurrency.mjs`
observes actual lock waits for identical and conflicting concurrent imports and
checks committed results from new database sessions. A shared synthetic parameter
fixture connects the real Swift batch exporter to SQL, preserving cents beyond
JavaScript's safe integer range and the complete tagged source envelope as bytes.
This proves the serialization boundary, not an operational import runner.
The local test also terminates its own PostgreSQL session before and after commit:
fresh-client retries converge to one complete payment/source pair in both cases.
That covers uncertain commit outcomes, not database-server restart or durable
operator-journal recovery. Migration-run journals, complete settlement
allocations and hosted verification remain required. No production access or
cutover is authorized.
Grants and RLS follow the current
[Supabase security guidance](https://supabase.com/docs/guides/database/postgres/row-level-security).

## A-021 — Local Payment Import Execution and Recovery

**Decision:** A separate macOS Swift executable uses the existing payment
conversion, exact parameter exporter, and migration plan/journal types. It does
not introduce a second accounting transform or repurpose the old, opposite-direction
Supabase-to-Firebase migration CLI. Raw source construction and the necessary
migration methods are package-scoped; validated-fixture and public app boundaries
remain unchanged.

**Recovery contract:** Persist immutable source/mapping/plan artifacts and the
load-started journal before SQL. Import one bounded batch in a single transaction,
then compare committed payment/source facts through a new connection before
recording load completion. An uncertain commit is recovered by replaying the same
batch, using A-020 idempotency, not by guessing which rows were inserted. Existing
journal events and applied totals must not be regenerated or incremented on retry.
Use a run-directory lock and synchronized atomic journal replacement. This avoids
adding per-record cursor machinery to the aggregate migration journal.

**Authority and limits:** Initial execution accepts only fixed synthetic input
and an independently checked local Docker destination. The existing dry-run
`MigrationEnvironmentGuard` remains unchanged; its evidence-only receipt never
authorizes writes. There is no hosted/production switch. This is not yet a general
export importer, an approved Client mapping, or whole-account migration readiness.

**Verification:** Local separate-process recovery checks passed for both sides
of commit, repeated completed resume, changed source/mapping/plan artifacts,
valid terminal blocked/failed journals, atomic batch conflicts, and remote Docker
denial. Main independently reviewed the delegated executable and required terminal
journal rejection before SQL and private run-directory ownership/permissions.
macOS Swift CI compiles the tool; existing Linux CI tests
the SQL boundary. Actual executable-to-Docker recovery is a local macOS check,
not claimed as end-to-end CI or hosted validation. Database-server restart and
full source/settlement reconciliation remain separate requirements.

The target-only Swift package and local executable are checked by active workflow
and environment checks, not frozen Firebase-source hashes. Correcting that scope
removed one target configuration entry from the passive source audit; it did not
remove or re-audit any shipped product behavior.

## A-033 — Report Eligibility Reuses Item Accounting Evidence

**Decision (implementation in progress):** Physical report rows use the existing
`ProjectItemAccountingRow` relationship-derived resolution. Do not persist a
second report-eligibility flag or infer accounting from placement, category,
price, or an arbitrary historical Invoice. Canonical
`docs/specs/proto-item-capture.md` requires Unaccounted For Items to contribute
nothing to reports or exports.

**Preserved behavior:** Accounted For Items keep their physical identity, Space,
and report detail. Proven Unaccounted For rows are excluded. Unknown relationship
evidence prevents completed export, rather than becoming an empty result or
silently included value. Report identity binds the accounting evidence used for
inclusion and exclusion, without exposing excluded physical detail in the output.

**Tradeoff and remaining work:** A completed physical download alone cannot now
make a nonempty report ready. The provider must read current scoped accounting
relationships coherently with physical rows. Native readers and the invoker
online report RPC now supply positive Client-payment evidence. Business-paid
relationships and complete absence evidence remain missing. This is
an implementation gap, not authorization to settle open posting or writer-role
decisions. No source relationship or historical fact is deleted.

The first source relationship is private
`ledger_private.item_client_payment_connections`: a scoped placement-to-real-
Purchase link, with fixed classification foreign keys and retained closure
history. It creates no payment or allocation and grants no app/MCP access.
Connection timestamps are relationship history, not a claim that every historic
link interval equals a custody interval. Trusted Link writers must separately
enforce current-placement and Unaccounted-For preconditions. Business-paid
occurrences and full source completeness remain separate
unfinished implementation—not implied by the presence of this table.

The physical-report stream and both native readers now consume active links
for the exact current placement, Project, Client and Account. The read is one
bulk query in the physical snapshot's transaction, not one query per Item.
Until restricted provenance policy is resolved, only active full-financial-access
members receive link evidence. A local downgrade immediately stops using retained
links; watches observe membership and link changes. Missing links remain unknown,
never proof of Unaccounted For status. This does not resolve O-060 or authorize
broader financial disclosure. Six actual stream SQL projections, native positive/
closed/old/malformed-link checks, live closure invalidation and encrypted-reopen
checks pass. The online RPC uses column-only SELECT grants and the same full/
active/current-placement restrictions in RLS, not a SECURITY DEFINER bypass.
Actor history and all writes remain ungranted. Its 29 SQL checks, real local
MCP/HTTP read and native differential comparison of actual stream rows pass;
the comparison includes accounting-bound source hashes. Security advisors report
no issues. Private-schema replication/publication access is still unverified.

Current physical category attribution uses `spike_item_project_categories`,
keyed by exact Project placement and referencing the existing Account category.
It is separate from immutable custody rows so a permitted category correction
need not invent physical movement. It is not a Project budget allocation or a
replacement for frozen financial category snapshots. Closed-placement attribution
is retained and cannot be rewritten. Corrections lock the placement row to
serialize with departure; a rollback-only two-session local test verifies that
departure blocks while correction owns the lock. Missing attribution is incomplete source/
download evidence, not an approved uncategorized Project Item state. The future
ordinary writer still must assign enabled Furnishings and preserve atomic batch
correction, prior accounting snapshots and correction evidence; no writer grants
are added here. Inventory placements cannot satisfy the non-null Project FK.
Association and label follow existing category visibility, including retained
local data after access reduction. Archived labels remain resolvable. Native
Client Summary watches both sources; a rename changes report identity. Twelve
SQL checks, positive native readiness/access checks, eight stream projections
and actual stream-to-native readback pass. Business-paid source completion and
live hosted replication remain separate work.

Both concrete report delivery boundaries reuse one internal protected scratch
lifetime helper. Each requires its own exact-source revalidation callback before
OS handoff; the helper introduces no new authorization source. Incomplete Client
Summary snapshots cannot enter delivery. UI branding revalidation and actual
provider wiring remain required before that report is usable end to end.
The concrete Client reader now shares the physical report stream and runtime
lease instead of introducing another sync lifetime. The stream includes the
Project's exact Client (including archived Clients); the Client read ignores
money and reads metadata plus its retained checkpoint in one transaction.
Missing accounting/category evidence still blocks completed export. Focused
query, encrypted runtime restart/access, and actual stream-SQL scope tests pass;
hosted delivery and UI composition are not established by those checks.

**Verification:** Focused Client Summary and Property Management eligibility
tests cover unknown evidence, exclusion from counts/value/output, evidence-bound
identity and mismatched relationships. The private Client-payment relationship
migration executed atomically on the isolated local database; all 23 focused
pgTAP checks passed, and local Supabase security advisors reported no issues.
Provider/Sync/MCP and full native UI
verification remain required; earlier green CI predates this correction.

## Charge Collection Serialization and Report Evidence

The positive Item charge source and Item frozen-line insertion share a
transaction-scoped advisory lock keyed by an unambiguous namespaced
Account/occurrence tuple. These writes require Read Committed. Volatile PL/pgSQL
triggers acquire the lock and then run separate validation queries, so a waiter
checks committed state after its predecessor finishes. Read-only report
snapshots retain their existing stable read contract.

This avoids a second paid-membership field: the immutable frozen Invoice line
remains the membership authority. Collection verifies an existing charge's
Project, Item, category, amount, currency and source revision and rejects a
withdrawn charge. Later corrections and withdrawals reject frozen membership.
The same lock covers absent sources: retained generic legacy frozen evidence
cannot be followed by a newly editable charge with that identity. Migration
must import canonical charge sources before their frozen membership; unresolved
legacy sources need explicit reconciliation, not invented charges.

Tradeoffs: these writes reject Repeatable Read and Serializable transactions;
future multi-Item writers must use deterministic lock ordering or retry database
deadlock failures. No public writer, financial policy or production migration is
authorized. This constraint preserves the lifecycle's distinct unpaid removal
and paid credit stories, physical identity and immutable paid history.

Verification: independent design review and 20 rollback-only pgTAP checks pass.
`scripts/test-local-item-charge-concurrency.mjs` additionally passed nine real
two-session races and six isolation-mode rejection cases; the main agent reviewed
and independently reran it. Each competing operation was observed waiting on
its predecessor's advisory lock. The disposable local clone was removed and
the source database stayed unchanged. Authorized source creation, acquisition
evidence and user-facing mutation integration remain required; these checks do
not prove a complete Link or collection command. The integrated read now uses
one invoker SQL accounting projection for both reports and one bulk native
reader merging Client Purchases and charges. Three actual source tables sync
only to active full-financial members; raw snapshots, actor metadata and Invoice
totals are not granted. Exact frozen membership supplies paid phase, while
missing charge sources never establish absence. Live-Invoice membership must
extend these readers before that future workflow ships. Typed readers reject
an incomplete frozen header rather than presenting it as an open charge.

Local integration passed803 database checks,1002 native tests/148 suites,
97 scoped stream captures and the real PowerSync parser (40queries/21outputs).
Actual Supabase/MCP and11stream tables into native SQLite produce identical
complete report snapshots for Client-paid, open and frozen-paid charges,
including amounts above JavaScript's safe-integer limit. Hosted replication
and the new exact-commit CI remain separate verification requirements.
PostgreSQL's documented volatile-function snapshot
behavior is cached in `.firecrawl/postgres-function-volatility.md` from
https://www.postgresql.org/docs/17/xfunc-volatility.html.

### Atomic Project Item presentation

Project Item lists now consume physical placements and derived accounting in
one SQLite read transaction through `DownloadedProjectItemsReading`. Joining
independent UI streams could show a new placement with a previous visit's
accounting. The reader reuses the existing physical and accounting readers and
scoped report subscription; it adds no backend state or duplicate history.
All physical Items remain visible. Incomplete or restricted accounting stays
unknown, never Unaccounted For; Inventory retains its physical-only query.
The small combined snapshot replaces two independently timed UI reads, while
the existing accounting domain model remains authority. Scope, old/new visits,
limited/removed access and runtime close are tested; full native tests pass.
Actual UI CI and hosted stream behavior remain separate required evidence.

### Item source labels and presentation groups

Keep original vendor (`source`) and immediate-origin label (`current_source`)
as distinct nullable Item metadata. Grouping uses original vendor and normalized
SKU, with name fallback only when the full unfiltered location identifies one
SKU group. Cards and Source filters use immediate origin before original vendor;
an explicit blank is not null. Structured group keys replace delimiter-concatenated
keys, avoiding collisions in vendor/SKU text. Groups retain all physical Item IDs;
selection and expansion are presentation state, never new inventory identities.

Current placements cannot reconstruct these labels: Inventory can mean either
direct acquisition or return, and scope alone does not explain a sale. Imports
must preserve both source fields without guessed backfills. This is retained
presentation evidence, not a new Transaction-derived history or accounting
authority. Future authorized create/move commands must maintain immediate origin
atomically: initial acquisition uses its vendor; inventory sale/return and the
specified inventory-mediated project sale use the Account inventory label;
within-project reassignment preserves it. Moves never overwrite original vendor.
Those writers and Item import conversion are not implemented by this read batch.

The shared downloaded reader and Core grouping serve Project, Inventory and
Space views. Fixed Space scope limits candidate resolution before dynamic filters;
filtering out a competing SKU cannot make an ambiguous Item merge into another
group. Tests cover this distinction, raw/blank/null labels, cross-Account denial,
encrypted restart, source updates and selection pruning. Native interaction and
hosted verification remain separate; thumbnails and financial group totals still
require their authorized readers. Authority: `docs/specs/items.md` Target Everyday
Workspace and Source facet, with the reviewed source grouping/Item model semantics.

### Current Item-linked Purchase read facts

The existing physical Item history reader now includes available canonical
Purchase facts for its current Project placement. Reuse the existing relationship
reader, workspace subscription, encrypted database and authorization checks; no
new UI, payment writer or second history system. Grant authenticated SELECT only
for active full-financial members with a current Item/placement/payment connection.
Limited financial visibility remains gated by O-060; source bytes and API writes
remain inaccessible. This is a conservative full-access read, not approval of the
unresolved mixed-payment visibility matrix.

Sync money as text and parse exact positive Int64 cents, validating scope,
classification, currency and currently supported imported-payment origin locally.
Malformed evidence cannot supply money; missing rows never mean unpaid. A returned
amount belongs to the whole Purchase, not an Item allocation or an additive Item
total. Preserve immutable source/payment identity. Ended connections/placements
and learned financial-access loss remove current read eligibility.

Focused evidence: CurrentItemPlacementLocalReaderTests (including encrypted
reopen, changes, malformed currency/origin and access loss),
DownloadedItemPlacementsTests, item_linked_purchase_read.test.sql,
imported_client_payment_storage.test.sql and actual stream SQL captures. Hosted
replication, complete Transaction destinations and restricted-role reads are not
claimed. Existing checklist record `item-linked-purchase-read` owns verification.

### Read-only Item images reuse the protected media path

Item image objects carry immutable Account/Attachment/hash/length/type/path
identity. Separate versioned Item references own order and primary choice. A
current-set revision and expected count distinguish a fully downloaded empty
gallery from missing metadata; partial local rows never prove No Image. Composite
ownership constraints, current-set validation and a unique primary index protect
the source. Old reference versions remain retained evidence, not current access.
This is not approval for upload, reference edits, detach, purge or a retention
period: O-065 and O-023 still gate those outcomes.

The existing logo HTTP transport and encrypted downloaded-byte cache now share
`DownloadedImageObjectReference` with the Item reader. The compatibility-named
local logo cache table is reused; no second vault or upload queue is introduced.
Account-parent encryption identifies the cache namespace, not permission to any
Item. Pending upload receipts remain separate and cannot be rebound as downloaded
cache entries. Length/hash, safe image MIME, private authenticated GET, no redirects,
bounded bytes, collision exclusion and orphan accounting remain enforced.

The workspace owns the Item image subscription and finite byte-read leases.
Every cache/download await is followed by exact current-reference and membership
validation; removal fences prevent return/display after access is lost. Storage
GET requires a current authorized Item reference to the exact immutable path,
independently of logo access. The gallery loads only its selected image and uses
bounded decoded previews, avoiding an eager download for every listed Item.

Focused tests cover incomplete/empty/mixed references, tenant denial, encrypted
cache reuse, metadata changes during download, removal, and stale UI results.
Actual native gallery interaction, hosted Storage/replication and transport wiring
through the approved sign-in composition remain required. List thumbnails, Image
filtering, complete zoom/pan/pinning, media editing and import are not complete.
Authority remains `docs/specs/items.md` and `docs/specs/ui/image-pinning.md`; this
read batch changes no product deletion or accounting policy.

### Item image export uses the existing authorization and native handoff boundary

Save/share requests capture one exact Item image reference. The gallery model
checks its live scope, reference and load generation before destination preparation,
after permission prompts and after loading original bytes through the existing
authorized image reader. Clear/reload, reference removal, missing bytes and
pre-handoff cancellation prevent delivery; duplicate requests remain blocked
until the destination finishes. No separate export writer, public Storage URL,
byte cache or scratch-file store is introduced.

iOS saving requests add-only Photos permission and submits the original resource.
Native sharing reuses the report delivery lock and completion lifetime with an
in-memory platform image; the OS chooses its exported representation. Once the
OS accepts the handoff, access changes cannot recall a destination's copy, and
caller cancellation does not mean the destination has finished reading it.
Model tests cover these preparation/lifetime boundaries. Native Photos permission,
save success and image share completion still require device evidence; this is
not authorization for background exports, production access or hosted resources.

### Original gallery presentation is shared; image authority remains outside it

September 11: the approved gallery reuse batch extracts the original gallery and
pinned-panel presentation plus pure geometry helpers. Both app builds use those
components and the original native ZoomableScrollView. Original AttachmentRef/URL
loading remains in wrappers excluded from the target. The target injects scoped
image identity, authorized decoded pixels and its existing pin/export callbacks;
it does not grant the presentation a public URL, cache or backend service.

The native view handles pixels arriving before layout, cancels replaced loads and
clears pixels on teardown. AppKit zoom bounds change in a valid order even for
tiny images; programmatic zoom animation samples do not overwrite the requested
zoom. Both Reset and double-click reset use that guarded binding path. These
fixes address a reproduced tiny-image crash and a reset that stopped above fit.
Selected-page loading, exact reference authorization,
offline cache checks and export handoff lifetime remain target responsibilities.
This preserves retained image/Item history and changes no accounting or product
policy. The obsolete target zoom view is excluded from the target build, not deleted.

Tradeoff: shared presentation changes require both platform/consumer verification.
Original iOS app compilation and43focused target model/media tests passed; iPhone
Photos success/denial, gallery controls and native gestures passed. macOS target
build and direct CUA interaction checks passed, including the two reproduced
zoom failures after their fixes. XCTest automation initialization failed; direct
Mac checks are not a successful XCTest run. Original Mac wrapper compilation also
passed without launching Firebase. Scoped evidence belongs to the existing four
Item image checks; this does not establish whole-app or cutover readiness.

### Item cards use explicit pre-generated derivatives, not inferred image URLs

Small card images reuse the immutable image-object store and protected byte cache.
An immutable same-Account link identifies the original, derivative and versioned
`item-card-300-jpeg-v1` recipe. The producer verifies the original hash/length,
applies orientation and encodes a JPEG no larger than300px without upscaling.
It reports actual output digest/length/dimensions; recipe identity does not promise
byte-identical ImageIO encoding across OS versions. Retry-safe publication must
reuse the first verified object. Original bytes, Item identity and history remain
unchanged; derivative links are not additional Item image references.

This avoids an unapproved dependency on hosted, usage-billed image transformations
and avoids full-size photo downloads for list rendering. Reads follow the current
original reference and active membership, including Storage GET; orphaned or old
references cannot independently authorize a thumbnail. The database checks JPEG
metadata, while trusted publication must verify actual encoded bytes/dimensions.
No public URL, new write grant or retention/purge policy is introduced.

Focused producer tests and original/derivative SQL authorization tests pass;
independent review informed the JPEG metadata check. Publication, Sync integration,
viewport-bounded loading and native card evidence remain required before this
design constitutes working thumbnails. Track that work only in the existing
`ITEM-CARD-THUMBNAILS` checklist entry.

## Real-source lineage compatibility — 2026-09-14

The authorized private project copy exposed two overly strict source-reader
assumptions: 407 lineage records omit the duplicate `accountId` field, and 55
use slash-containing historical author labels. A validated Account document path
now establishes source scope when the duplicate field is absent; a conflicting
embedded Account still fails. `createdBy` is retained as provenance text, never
promoted to a target principal or authorization claim. Missing references still
prevent semantic mapping, including for records without embedded `accountId`.

Nested Project notes/categories remain preserved source documents, but the
lineage reviewer no longer misclassifies them as malformed Project records.
The typed REST reader feeds existing reconciliation without rewriting source
facts or granting import eligibility. It preserves integer money and timestamp
nanoseconds; raw private snapshots remain the original evidence. This does not
authorize invented missing records, target accounting mappings, or cutover.

Focused regression coverage is in `FirebaseRESTSnapshotReaderTests` and the
existing lineage reader/reconciliation suites; live-copy review remains an
incomplete migration rehearsal, not production readiness.

## Imported current location is not a dated move — 2026-09-14

Retain one placement model, adding immutable `start_evidence` to distinguish a
recorded move from an `import_observation`. For an observation, `started_at` is
when the source location was imported into the target, not a claim about when
the Item physically arrived. Original source evidence and unresolved earlier
history remain preserved by migration; Item creation/edit timestamps are not
substituted for move dates. Later real moves close the observation normally.

The existing history view labels observations as imported source locations with
unknown move dates. Older local rows with unavailable start evidence also avoid
claiming a known move date. Native schema/readers and all three placement Sync
projections carry the distinction. Existing Account RLS is unchanged; only the
new read column is granted, and no client write capability is added. This is a
representation correction, not authorization to invent placement history or
declare a migration complete.

## Vendor-purchase import reuses Transaction storage — 2026-09-14

The authorized real-data QA copy is explicitly separate from migration acceptance.
`LedgerLocalPaymentImport --apply-partial-qa-copy` creates a private, clearly labeled
local Account for the existing isolated QA principal. Its private manifest records
excluded Transactions and intentionally unloaded fields/history/media; original
snapshot bytes and the executed SQL are retained before commit. Client identities
are Project-specific QA mappings, not approved production Client consolidation.
Accounting completeness, migration recovery and cutover remain unproven. Partial
QA data may exercise covered reads/UI/offline behavior, not validate omitted
accounting workflows. An existing copy is never overwritten by rerunning the loader.

Compatibility correction: the frozen Swift app's `Transaction.itemIds` is optional
and existing calculations use `itemIds ?? []` (baseline `ca68d793`,
`Models/Transaction.swift` and `Logic/BillingSummaryCalculations.swift`). Omitted
or null lists therefore do not, by themselves, make a source purchase invalid.
The reader retains the raw distinction and still rejects malformed lists,
duplicates, reverse-link disagreements and unresolved history. An empty declared
list does not establish export completeness. Source/conversion/parameter tests
cover this compatibility rule.

The private `import_vendor_purchase` operation reuses `spike_transactions`,
`transaction_receipt_items`, and immutable `imported_transaction_sources`.
It does not add a Receipt entity or route vendor spending through the imported
client-payment operation. The caller supplies reconciled payer-derived money
scope, category, Item relationships and nonphysical lines. Unknown Item costs
remain null; source history is not replaced with current prices or placements.
Swift parameter conversion requires all current and historical Item identities
in the reviewed acquisition plan, unique target mappings, and decimal-text money.

Transaction, relationships and original source bytes commit atomically. Identical
replays succeed; conflicting scope, amounts, source bytes or relationship sets
fail without overwriting existing facts. This is invoker-rights, operator-only
code, with no app/API execution grant and no new financial-read permission.
Ordinary target editing policy remains unchanged. Migration replay after a target
edit must be investigated, not used to overwrite that edit.

Local SQL integrity/security tests pass, including the shared database suite.
End-to-end source loading, cross-session concurrency/recovery and actual app/sync
readback still need proof. The operation does not settle ambiguous payer, tax,
refund, collection or source-history decisions or authorize production cutover.

### Hosted Ledger replication connection — 2026-09-14

Under the user's explicit authorization, hosted Ledger Supabase uses a separate
Ledger project in the existing PowerSync nine4-team organization. Boards is not
shared or modified. The dedicated `ledger_powersync_replication` login has
replication/BYPASSRLS and SELECT only on the 29 source tables compiled from the
existing Sync Streams; publication `powersync` names those exact tables. It has
no application-table writes or reads of raw imported-source evidence. Replication
necessarily reads across Accounts; existing stream authorization, not Postgres
RLS alone, must restrict what each client downloads. Connection TLS is
`verify-full`; secrets remain outside source control and client builds.

The hosted connection test passed and grants/publication were read back. Supabase
client authentication is configured with development tokens disabled. Deployment
`6aa89c2002481fb31b969564` completed on service 1.26.1; active rules version 3
finished initial replication of all 29 tables with no reported table/stream errors.
The deployed YAML exactly matches `powersync/sync-streams.yaml` SHA-256
`d345bdf2544872f02612206225394645c0480540e3dd6ce072c11b2535d74324`.

CLI 0.9/0.10 validated the rules but returned HTTP 500 when publishing with the
dashboard-created password reference. Resubmitting the existing replication
password through the management client's supported `{secret: ...}` field worked;
no password, permissions, auth settings or rules were changed. This isolates a
credential-reference compatibility issue, not a reason to weaken authorization.
The retained CLI token stays in secure storage; the private replication credential
stays outside source/app builds. Do not repeat blind failed deployments or rotate
credentials merely to publish rules.

Actual hosted app/offline/account-isolation tests remain required. Initial
replication of the empty hosted Account dataset is not those proofs, real-data
migration acceptance, or cutover approval.

### Project Item sync routing — 2026-09-14

The real 623-Item hosted Project fails with PowerSync `PSYNC_S2305` (1,000
parameter results). Compilation reveals per-Item buckets and placement lookups,
including for image markers with no image data. Successful SQL filtering and
initial server replication did not test this client-subscription limit.

Use the existing database-derived routing pattern: Item and image-marker
`sync_project_id` values follow the canonical current placement. They are not
editable location/history facts. Triggers derive incoming values, propagate
movement transactionally, preserve Item edit revisions and retain all placement
history. The stream retains Account membership authorization and exact selected
Project filtering; routing fields are not added to its downloaded projection.
Payment connections, category assignments and charges also copy current-placement
eligibility; frozen Invoice lines derive eligibility from their charge. Existing
canonical guards still run for canonical edits, deletion and no-op writes. Only
actual derived-only changes bypass those UPDATE guards, after early triggers
replace caller-supplied flags. Frozen source contents and revisions remain intact.
Invoice-line derivation takes the existing source lock before lookup, including
an absent legacy source. Category visibility and full financial membership checks
remain in the stream. Categories, payment headers and Invoice headers still have
their own identity-level lookups; this removes per-Item multiplication, not every
possible subscription size limit.

This trades six derived columns and their maintenance for project-sized Item,
payment-link, charge and Invoice-line buckets without broader downloads or a
second history model. Migrations `20260915015741` and `20260915015830` include
backfills and no new API grants. The local pull's unrelated drops/local grants
were excluded. Fresh shadow migration application passed; SQL suite passed
1,424 assertions, compiler/projection suite passed 9 tests, and the report's
13-query/121-capture authorization test passed. Additional frozen-line tests
prove routing cannot rewrite contents or a frozen charge revision. Security
advisors reported no warnings/errors. Both migrations are deployed to hosted
Ledger; PowerSync operation `6aa8a6efa77ca1231d284192` completed with rules v4.
The exact formerly failing hosted subscription now returns 200/NDJSON; hosted
SQL verifies 623 Project routes and zero Item-routing mismatches. The existing
hosted-entry iPhone test now displays all 623 Items and passes in 20.484 seconds
(`/tmp/ledger-hosted-entry-ui-lazy-items.log`). Its initial rerun stalled in
XCTest accessibility enumeration; changing the Item container from VStack to
LazyVStack fixed that scale issue without replacing row UI. Media, offline and
whole-app completion are not established by this result.

### Hosted authenticated media download compatibility — 2026-09-14

Hosted Storage requires `object.get_authenticated_info` as well as
`object.get_authenticated` for private downloads. The previous exact operation
filter rejected hosted reads even though the QA user could read the same object
metadata under RLS. Use Supabase's exact normalized operation helper for those
two operations in the existing logo, referenced-media and reserved-upload
policies. Preserve their account/reference/uploader predicates; no listing,
signed URL, public bucket or broader write authority is introduced.

Migration `20260915030749_authenticated_media_download_info.sql` captures the
change. Hosted imported media readback passed for96sections/115references with
authorized byte checks and anonymous denial. The existing native interrupted
TUS test passed against hosted Ledger in27.386s; concurrent/replayed verifier
calls produced one attachment reference (`/tmp/ledger-hosted-native-attachment-retry.log`).
Local SQL:1426checks/48files passed in4s; advisors found no issues. This is
upload/read compatibility evidence, not full app or migration readiness.

### Item-image subscription scale — 2026-09-14

Keep the existing schema, history, native reader and viewer. Add explicit
Account/Item subscription predicates to the four joined `item_image_sets`
lookups in `item_images`. Inferring those equalities through joins exceeded
PowerSync's1000-parameter-result limit on the authorized real copy, even for
one selected Item. Explicit predicates avoid that intermediate expansion;
current-revision and membership checks remain unchanged.

Hosted rules5 operation6aa8b981a77ca1231d28456b completed03:21:46UTC.
The exact formerly failing subscription returned200,8buckets,1set,2references,
4original/thumbnail objects and2thumbnail links.10compiler/projection checks
pass. This narrowly fixes the observed subscription; it is not an unlimited
scale claim or evidence for unrelated workflows.

### Inventory sale price and immutable basis — 2026-09-14

Pending placement presentation (2026-09-15): derive an explicit pending move
from the retained sale command; do not mutate downloaded placements or append
invented history intervals. Preserve Item identity/descriptive fields, clear the
old Space assignment in the destination presentation, and retain the marker
until matching destination placement downloads. Rejection restores authoritative
presentation; a later physical cycle takes precedence over the old command.
Physical readback alone does not establish charge or Invoice completeness.
`InventorySalePendingPlacement` implements the resolution rule. The local
placement reader derives it from scope/digest-validated retained commands and
the original authorized placement; no extra projection table is written.
Inventory, Project and history watches observe local operation changes.47focused
tests pass; explicit history/readback-gap/revocation proof is in
`/tmp/ledger-sale-history-readback.log`. Actual native local PowerSync sale
convergence passed in `/tmp/ledger-sale-native-live.log`: offline acceptance,
restart/retry, RPC upload, downloaded destination and unchanged two-interval
history, one exact charge and zero sale payment Transactions. This is one
synthetic Item, not bulk/mixed-origin or pending UI interaction proof.

Offline acquisition projection (2026-09-15): use the derived private
`item_acquisition_reviews` table for PowerSync, not an independently cached HTTP
response. Each physical Item has explicit absent/known/unavailable evidence
computed from existing purchase receipts across scopes. Receipt writes refresh
it atomically; existing Transaction→receipt propagation is reused. Category
visibility changes refresh its access requirement, and the stream requires
active membership plus full financial access for protected rows. A missing local
row remains unavailable, never zero. No application role writes the projection;
it is rebuildable and cannot replace acquisition receipts or paid history.
Tradeoff: one derived table and receipt/Item/category triggers. Local
SQL1492checks,10parser checks and52actual-query captures pass. Actual service
withdrawal passed in /tmp/ledger-acquisition-live-sync-asserted.log. Concurrent
receipt insertion passed in /tmp/ledger-sale-acquisition-concurrency.log: the
second writer waits, then sees both acquisitions and publishes unavailable;
removing one synthetic receipt restores the remaining cost. This does not prove
every category/receipt interleaving or completed offline UI behavior.

Offline review clarification (2026-09-15): price/cost input distinguishes known
amount, confirmed absence, and unavailable evidence. Transaction receipt streams
are scope-filtered; an empty local receipt query cannot prove no acquisition
exists. `InventorySalePrice.review` rejects unavailable evidence even when the
other amount is positive. Only confirmed absence of both positive values permits
the existing price-entry step. Reuse the existing SellToProjectModal controls;
do not infer zero cost or fetch only the Item's current-scope Transactions.
The required complete acquisition projection/read remains unfinished; this rule
does not itself prove that projection or authorize changing acquisition history.

Implementation direction for the approved Inventory→Project lifecycle:
keep the Item's editable project price separate from acquisition receipt amounts
and frozen inventory-entry/paid-line amounts. Add a revisioned per-Item price
fact; do not derive the destination price from a Transaction's mutable total or
overwrite `transaction_receipt_items` to record a markup. The sale command must
compare the reviewed price revision and current placement, persist the approved
price floor, close Inventory placement, and create the destination placement and
new positive charge occurrence in one transaction with one replay result.

Reuse `spike_item_placements`, `item_charge_occurrences`, exact `Money`, and the
existing operation-result identity contract. A missing Return-only source
snapshot does not prevent a valid independent Sell. Returning to source instead
uses an immutable inventory-entry amount/category and never this price rule.
Acquisition links, old occurrences, credits, and collected records remain intact;
no synthetic payment Transaction is created.

This introduces one mutable price fact, not a competing history subsystem.
The tradeoff is explicit price revision validation at command acceptance rather
than read-time fallback. Canonical lifecycle and routing specs remain authority.
`InventorySalePriceTests` proves only pure normalization; persistence, command
atomicity/security/replay, app/MCP and offline verification remain unimplemented.

Price persistence evidence: migration `20260915062051_inventory_sale_price.sql`
matches the DDL applied locally; its journal is registered. Ten focused checks
and all 1,436 local SQL checks pass; advisors report no issues. Filtered automatic
diff failed on a pre-existing local replication-role dependency, so the CLI-created
migration contains only the reviewed price table/guard, not replication changes.
Hosted deployment and the sale command remain pending.

Canonical category binding: `spike_accounts.furnishings_category_id` identifies
the D-013 category independently of mutable display name, type and transaction
default. Its Account-scoped foreign key prevents cross-tenant assignment; once
assigned it cannot be silently cleared/repointed. Existing Accounts remain null
until reviewed setup/import supplies the identity: no name-based backfill.
This preserves the confirmed category-edit clarification (type edits cannot
disable Item accounting). Migration20260915062338 is local-only; commands and
setup/import integration must handle unresolved identity explicitly.

## Item detail owns its current financial subscription — 2026-09-15

Direct Item detail now retains the existing `property_management_report` stream
for its current Project alongside `physical_account_items`. Previously its reader
queried charge/payment tables without owning their download subscription, making
financial detail depend on which Project screen had been visited earlier.
Changing location releases the old Project subscription; closing or cancellation
awaits cleanup before the runtime closes the database. Local physical information
is emitted before requesting financial data. No history, financial access rules,
or UI components are replaced. This reuses the existing stream rather than adding
a second financial projection. Its broader Project working set is a tradeoff;
only the current Project is retained by this detail watcher.

Evidence: authorized live offline/restart/sale/charge readback passed in
`/tmp/ledger-sale-native-charge-authorized.log`; subscription switching and delayed
cleanup are tested in `DownloadedItemPlacementWatchTests` and
`/tmp/ledger-history-financial-lifetime.log`. The earlier charge assertion against
a user with no financial access was invalid and was corrected, not used to weaken
authorization. This does not complete the separate Invoicing workspace.

### Expense receipts reuse existing byte transfer — 2026-09-15

D-009 keeps an Expense separate from a client-payment Transaction. The existing
capture receipt already supports an Expense parent, so that identity must remain
intact through upload. Do not create a Transaction just to satisfy the current
Transaction attachment reservation/publication endpoints.

`SupabaseTransactionAttachmentUpload.uploadReservedBytes` now holds the existing
TUS implementation independently of Transaction admission. The Transaction adapter
delegates after validating its reservation; a forthcoming Expense adapter must
validate its own reservation before calling the same transport. Bucket, immutable
Account/attachment/hash path, media type, byte count, hash, upload origin, offsets
and resumable checkpoints remain checked. Bytes are hashed once, not once per
adapter plus once per transport. No viewer or second upload engine is introduced.

The historical class/checkpoint names remain for compatibility; this avoids an
unnecessary broad rename while separating the concrete dependency. Expense
reservation/publication and durable-byte reconciliation are still required.
`SupabaseTransactionAttachmentUploadTests` covers the reused transport and its
existing Transaction consumers; a passing transport test is not evidence of an
end-to-end Expense receipt upload.

Expense receipt reservation and verified media publication precede final Expense
creation; the existing creation command atomically attaches the published objects.
Publication alone creates no Expense, Transaction, Invoice or payment. The private
claims keep the intended Expense/Project identity. A service-only publication
wrapper rechecks the capturing user, current full financial membership and active
Project/Client, then compares observed bytes and the immutable media identity on
every retry. Its definer boundary avoids granting service_role access to the
private schema; no client can invoke publication with invented byte observations.
The Edge byte reader is extracted to `_shared/observe-attachment.ts` for reuse,
retaining bounded downloads and hashing. Receipt reference reconciliation and the
Expense Edge/native adapter remain required; this does not settle editing policy.

The native creation queue may use its durable Expense verifier result as receipt
readiness evidence before a synced reference exists. That evidence is bound to the
capturing principal, Account, Expense, Project and immutable capture identity;
the server still requires the canonical media object when inserting the Expense
reference. This removes the circular wait between receipt reference download and
Expense creation without inventing a synced row or treating uploaded bytes alone
as verified. Existing downloaded-object readiness remains available for already
synced receipts. Pending bytes are retained until separate reference readback;
this readiness check does not clear the media queue or change retention policy.

Expense receipt browsing reuses the existing image gallery and PDF presentation.
The Transaction-specific PDF byte-loading wrapper is extracted as
`AuthorizedPDFViewer` for both consumers; rendering and gestures are unchanged.
Expense reads include available immutable object metadata without dropping receipt
references whose metadata has not downloaded. Metadata is not read authority:
byte access still uses the existing runtime's scoped, revalidated loader, and an
open Expense viewer owns a live watch that closes it when access or references
change. This does not add capture/edit/delete/export policy or a second media cache.

Expense entry keeps form inputs in the existing submission session; receipt picker
callbacks return only after the existing attachment store acknowledges durable
bytes. Deselecting a receipt removes its draft reference, not its protected file.
Closing with saved files requires an explicit warning; complete recovery of an
unsubmitted form remains unfinished, so file retention is not claimed as recovery.

Pending Expense presentation reads accepted envelopes from the existing local
operation ledger, scoped to the current Account and principal under the same
financial authorization as downloaded Expenses. It does not insert pretend Expense
facts or accounting revisions. Queued/applying, applied-awaiting-download, and
rejected entries remain visibly distinct; a downloaded Expense replaces its pending
row without deleting command history. The existing encrypted-restart test covers
pending readback and replacement with/without receipt references
(`/tmp/ledger-pending-expense-read-tests.log`). Rejection correction and unsubmitted
form recovery still require implementation; this is not whole-workflow acceptance.

Pending Expense receipt reads now resolve bytes from the existing protected capture
store only when the current principal's retained Expense command references that
attachment. Financial/project authorization and the pending command are checked
again after reading bytes. No downloaded object or server URL is invented. The
existing Expense viewer selects its existing PDF/image presentation from those
bytes and closes when the pending reference is withdrawn or replaced by download.
Local Auth/PowerSync integration proves reopening and reading the pending receipt
before sync, refusal under a different Expense, and normal post-sync receipt reads
(`/tmp/ledger-pending-expense-local-bytes.log`). Unsubmitted captures remain a
separate unfinished recovery case.

Unsubmitted Expense capture now has one local-only recovery record in the existing
encrypted structured database (`spike_expense_entry_recovery`). It stores raw form
fields, stable Expense/operation/line IDs and receipt IDs, never receipt bytes or
an accounting fact. The form is persisted before receipt capture is acknowledged;
closing explicitly retains current details. Invoicing reads it under financial
authorization and principal scope. Accepted commands hide it without deleting
history; recovery refuses to overwrite an accepted command. Receipt restoration
reuses the protected attachment store and rechecks the current recovery record
after reading. Missing bytes block submission rather than dropping references.
This is a concrete Expense capture requirement, not a generic draft framework.
Crash/restart, UI reopening, session-ending counts and stale concurrent editor
behavior still need verification before acceptance.

Recovery verification: actual encrypted-runtime reopening restores the form and
original capture, submission preserves identity and hides the unfinished entry,
and accepted intent cannot be overwritten (`/tmp/ledger-expense-unfinished-restart-normalized.log`).
The existing item-bound form opens retained fields and uses **Save for later** to
persist before closing (`/tmp/ledger-expense-unfinished-ui-save-later.log`). The
earlier close-warning approach is superseded: retention is non-destructive, so no
confirmation dialog is needed. Uncertain capture IDs remain in recovery state
rather than disappearing after a different file succeeds; their correction path,
session-ending counting and stale concurrent editors remain unfinished.

Session-ending summaries now count unfinished Expense forms separately from queued
commands and attachment uploads. The existing stable-observation hash includes
their content, so an edited form invalidates prior cleanup evidence. Ordinary
logout is blocked even before receipt bytes exist; accepted Expense commands
replace the unfinished responsibility rather than double-counting it. Zero-count
fingerprints retain the previous format. Policy/provider/model checks passed
(`/tmp/ledger-unfinished-session-protection-final.log`); the actual runtime test
proves count persistence through restart and transition on submission
(`/tmp/ledger-expense-unfinished-count-runtime.log`). Concurrent-editor and
missing-receipt recovery work is still incomplete.

Expense form updates and initial submission now compare the exact previously
loaded local recovery record inside the same database write transaction. A stale
editor cannot overwrite newer saved content or queue an Expense over it. Identical
save retries remain idempotent, and a previously accepted command still follows
its existing immutable retry path. This uses the existing record as a comparison
token, not another revision ledger or conflict service. Actual runtime tests refuse
stale save and stale submission, then accept the current saved version
(`/tmp/ledger-expense-stale-editor-runtime.log`). Create/reopen UI checks pass
(`/tmp/ledger-expense-recovery-and-create-ui.log`); stale-error UI interaction
itself remains unverified.

### 2026-09-15 — Keep business-paid General costs out of the acquisition importer

`FirebaseAcquisitionConversion` previously planned an inventory Purchase for a
business-paid General Project cost. D-009 requires Expense/Invoicing instead.
That path now returns `businessExpenseRequiresMapping`; the existing QA-copy
manifest records the exclusion and retains the original source. It does not
guess outstanding debt, erase historical Item links, or create a new Expense
before settlement/history mapping exists. Client-paid General purchases and
business-paid itemized acquisitions retain their separate mappings. Six focused
migration tests pass in `/tmp/ledger-expense-migration-classification.log`.
Actual Expense migration remains unfinished, and existing copied data was not
modified or retrospectively certified by this correction.

Source inspection at `fe018501d67cc84b6f140b2645b8a8149ea5c4f6` confirms
`Invoice.lines` owns signed source amounts (`sourceType=transaction`, `sourceId`)
and `transactionIds` is a membership index. Payment Transactions own
`settlementInvoiceId`/`settlementInvoiceLineIds`; line
`settlementTransactionIds` is only a reverse lookup. Migration must reconcile
these with Invoice status and retained source amounts before declaring an
Expense unpaid or collected. `Transaction.status` is cancellation-only, and
`purchaseHandling` is separate from payer identity. Do not use missing settlement
fields on the original cost, current category, or an incomplete invoice export
as proof of unpaid debt. This is source evidence for the unfinished mapping,
not a new product policy or approval to replay legacy per-category collection.

The Expense-only paid-source migration now reuses `store_collected_invoice`
inside an operator-only, invoker-rights transaction. It verifies the exact
existing imported payment, inserts reconciled Expense rows, freezes Invoice
contents and retains the source envelopes atomically. A relational source-ID
uniqueness constraint prevents the same original cost being imported twice
under different target IDs/Invoices; retained request data rejects changed
retries. No app/API role receives access. Source inspection confirms the
original Swift Transaction has optional `createdAt` and no creator field.
Imported Expenses preserve unknown creation metadata as null, not migration
time/operator identity. A deferred constraint requires durable import provenance
when creation metadata is unknown; native creation still supplies the
authenticated actor and server time. Existing read/sync projections do not
consume these metadata columns. Source timestamps retain full original precision
in the envelope, with microsecond precision in the Postgres projection.
This is not live collection policy or a completed migration runner. Source
media/mixed histories and synced paid-state evidence remain incomplete.
The full local SQL suite passed1612assertions in54files; local advisors found
no issues (`/tmp/ledger-expense-invoice-import-full-sql.log`,
`/tmp/ledger-expense-invoice-import-advisors.log`).

Expense paid reads reuse complete `FrozenInvoiceContents`, not a second status
flag. The Expense stream includes complete Project Invoice contents for the
already-required full-financial member; the local reader validates the whole
Invoice and its exact Expense scope/revision/amount. Missing paid evidence means
unknown, not available/unpaid: live Invoice coverage remains separate. Encrypted
SQLite read/restart/revocation proof passed in
`/tmp/ledger-expense-paid-local-read-fixed.log`; actual service download and UI
status wiring remain to be verified.

Follow-up verification: actual local Auth/RPC/PowerSync paid Expense download
and offline restart passed (`/tmp/ledger-expense-paid-live-reloaded.log`), and
the two focused iPhone status/filter scenarios passed
(`/tmp/ledger-expense-paid-ui.log`). The existing row and filter were adapted,
not replaced. Missing membership evidence still means unknown. The live RPC
test caught a deferred metadata trigger permission error; native known metadata
now returns without querying private tables after the definer context ends.
No API grants were widened; all1616SQLassertions passed afterward.

Expense receipt migration now composes the existing source-media copier,
reference validator and protected Storage transport with the Swift converter.
`--receipt-media` binds copied media to the exact private snapshot digest. Only
sources accepted by complete Expense-only Invoice validation proceed to target
byte verification. Check mode never uploads; apply can upload missing originals
without upsert. Object catalog, ordered receipt links and financial rows share
one database transaction. If later SQL fails, protected unreferenced bytes may
remain for deterministic retry; no automatic deletion policy is introduced.
Original references/metadata remain in source evidence; legacy primary/name
presentation, other media and mixed histories are not thereby fully mapped.
The existing synthetic copy-runner test verifies PDF/image Storage bytes,
financial fields, ordered links, missing/corrupt media rejection and rollback
(`/tmp/ledger-expense-receipt-bridge-e2e.log`). No new downloader or UI.

Invoice display metadata now belongs to the same immutable collected Invoice:
optional original number, notes and issued/sent/paid/canceled/voided timestamps.
Older missing metadata stays unknown, with no generated name/import-time default.
Timestamps travel as exact millisecond strings within the source Timestamp date
range; original nanosecond evidence remains in the migration envelope. This is
not new Invoice lifecycle authority. One constrained nullable JSONB column avoids
a separately mutable metadata record; existing financial RLS applies, with only
the new column added to the existing authenticated column-read grant. Exact retry
comparison includes metadata, and existing immutability blocks subsequent edits.
The same contract flows through native storage/sync, Expense and Transaction
readers, MCP and source conversion. Invoice rows reuse the original date fallback
(paid, then sent, then issued). Metadata validation, migration reconciliation and
live/UI evidence are recorded in the Invoicing workflow; preview/live lifecycle
coverage and older-record backfill remain separate unfinished work.

The collected-Invoice preview reuses `InvoiceReportView`, not a new renderer.
Its pure `InvoiceReportData`/line types are extracted from legacy aggregation;
Decimal minor units preserve exact section totals even when charges and credits
separately exceed Int64 but the net fits. Existing integer callers retain their
initializer. The target maps sealed descriptions, signs and purchase-cost basis,
never current Item prices. A scoped watch owns the open preview and clears it on
withdrawal/error. Date fallback and logo loading are injectable so unknown dates
are not presented as today and protected bytes can use the existing asset reader.
Project/Client names use the existing workspace context. Business branding now
uses the existing authorized profile watch and bounded logo decoder; absent,
unavailable and stale branding remain explicit. PDF download is still unconnected;
hiding download is not feature completion. Focused accounting and preview interaction evidence belong to the
existing Invoicing checklist, not a separate report tracker.

Invoice export work now belongs to the existing checklist's
`invoice-report-readback` execution record. The original HTML layout remains;
its target boundary excludes unrelated legacy report models, escapes display
fields/provenance and disables network content through CSP. `renderData` extends
the original PDF helper with per-call ownership, native pagination and thrown
errors instead of its global one-page crop. Download completion extends the
existing native helper; the existing protected report store still owns delivered
scratch bytes and cleanup, and Invoice/profile reads revalidate at handoff.
These changes are in progress, not accepted: native delivery unit checks pass,
but long-document rendering, actual save/cancel, macOS temporary-render crash
recovery, generation cancellation, filenames and visual output need evidence.
No separate report design, accounting writer or download service is introduced.

Invoice download filenames now use the existing protected scratch store's optional
name hint: at most 60 ASCII letters/digits/hyphens, followed by a UUID and the
validated format extension. Unsupported characters become hyphens. Recovery
accepts this bounded shape as well as existing UUID-only files; ownership,
descriptor-based access, permissions, active-session locks and completion-owned
cleanup are unchanged. This supplies a readable iPhone filename without another
plaintext copy or another save UI. The UUID remains visible to preserve unique
names. Native scratch/delivery tests and actual iPhone Save passed; evidence is
in `invoice-report-readback`. Mac render-only crash recovery remains separate
and unfinished. No accounting relationships or source data change.

Mac PDF generation uses AppKit's document-modal completion API with its printing
thread enabled. A retained, unshown window provides the print context; this is
not a new user-facing save interface. WebKit's synchronous preview path can
return an unknown page count before pagination, which caused the observed
unbounded spool. AppKit's completion callback runs on the print thread, so the
callback is nonisolated and explicitly returns to MainActor for state cleanup.
The original HTML and WebKit renderer remain shared. Actual 80-line, four-page
Invoice output now passes content checks and visual review on Mac; interruption
and render-file crash recovery are still incomplete, not waived by this result.

The target Mac Invoice adapter now supplies an output URL reserved by the existing
`ReportScratchStore.generatePDF` operation. The shared renderer remains independent
of PowerSync. The store holds its existing session lock through native completion,
handles native atomic replacement, and removes output after completion or error.
Cancellation and WebKit failure during printing defer completion until the writer
finishes; tests verify complete native output exists before the error returns.
Startup recovery permits read-only group/other bits on abandoned native output
only inside verified private, unlocked sessions; it still rejects unsafe ownership,
links, executable or writable-by-others files. Normal generated output is normalized
to 0600. Actual renderer/store integration and modeled abandoned-file tests pass;
these do not claim an end-to-end forced-process-crash rehearsal.

### Collected Invoice report read evidence (2026-09-15)

The Invoice report now requests frozen contents and download provenance through
the existing Invoicing read boundary. Its provider checks access, reads the
retained stream checkpoint and hashes the selected frozen Invoice within one
local database transaction. It reuses the existing report provenance value;
there is no second sync tracker or new stored accounting history. The content
version describes frozen Invoice data, not separately loaded branding/category
labels, which retain their own final export checks.

The original preview and HTML receive the read timestamp, source version,
completed-sync timestamp and accounting authority identifier. Native handoff
revalidates contents and visibility; a later checkpoint alone does not invalidate
unchanged contents. No timestamp is an offline expiry. Provider restart and
denial checks pass; app wiring and final rendered evidence remain under the
existing Invoice report checklist, not a separate completion claim.

### 2026-09-15 — Expense edits share the collected source lock

Pre-collection Expense editing reuses the existing entry model and wire encoding,
with an expected revision rather than a new Expense identity. Database triggers
lock the Expense row for receipt changes and frozen-line insertion; collected
sources and their receipt facts cannot be rewritten. Existing source-only
historical Invoice snapshots remain supported without fabricating Expenses.
This adds no API grants, delivery/resend requirement, or accounting history store.

Migration `20260916003710_expense_collected_source_guards.sql` and the imported
Expense tests establish paid-write rejection; all 1,649 local SQL assertions
passed. The existing two-session race runner also passed edit-first,
collection-first and collection-rollback Expense cases with observed lock waits;
local database advisors reported no issues. The edit
RPC, revision comparison, local queue, MCP and existing-form integration are
unfinished; these guards alone do not establish an editable workflow.

### 2026-09-15 — Expense receipt edits reuse capture and publication

Receipt addition before collection uses the existing Expense form, encrypted
capture store, upload worker and verified Storage publication. An edit retains
the original ordered receipt IDs and appends only receipts reserved and verified
for that same Account, Project, Expense and actor. The revision-checked database
command links them atomically under the same Expense lock used by collection.
No replacement uploader, receipt history or presentation component is introduced.

The existing recovery record optionally carries the source revision and retained
receipt IDs. Older creation records still decode without these fields. Unsubmitted
edit recovery remains distinct from accepted pending operations and authoritative
accounting; stale drafts retain their bytes but cannot overwrite a newer source.
Acceptance checks the exact saved recovery in its local transaction. A consumed
record can be replaced by a later edit; an unfinished draft cannot be silently
overwritten. Receipt removal/reordering and post-collection editing are not enabled.

Actual native upload/readback and encrypted restart tests passed, as did the local
SQL authorization/verified-receipt cases. The Expense lifecycle checklist owns
the precise evidence and remaining UI, migration and integration checks. These
local results are not hosted or cutover-readiness claims.

### 2026-09-15 — Live Invoice membership separates selection from settlement

Live Invoice headers and ordered memberships identify Item charge occurrences,
Expenses and Fee installments. They do not copy source amounts or category values:
live reads resolve those facts, while the existing frozen Invoice tables remain
the paid authority. A reviewed selection carries revision and amount evidence
for the command to revalidate, not another stored accounting balance.

An active-source unique index prevents competing Invoice membership. Released
membership can retain provenance; paid membership remains reserved because a later
Item return/resale uses a different occurrence. This storage capability does not
decide cancellation, sent-membership changes or credit/zero settlement policy.
The initial schema has no API grants. The writer still needs source existence,
Project scope, eligibility, authorization and lock-order checks, and Fee source
integration remains unfinished. Existing CreateInvoiceModal presentation is the
reuse boundary; no replacement Invoice wizard is authorized by these tables.

### 2026-09-16 — Uninvoiced returns retain links, not a second monetary ledger

For Inventory lifecycle Story 2, `uninvoiced_item_returns` links the original
Item charge to its successor Inventory placement. The charge retains its exact
amount, category and Project placement and becomes withdrawn; the same physical
Item remains. No negative charge, Invoice, credit or Transaction is created.
An immutable return fact identifies which sale cycle was reversed without copying
its monetary values. The writer requires proven Inventory-origin placement,
current revision and no live or collected Invoice membership, and rejects the
entire selection on any conflict. Imported cycles without sufficient evidence
remain unsupported rather than receiving invented provenance.

The private writer has no client grants yet. Focused SQL checks cover replay,
atomic rejection, live/paid membership, missing origin and identity collisions;
concurrency, authorized API exposure, offline queue, sync history and reused UI
integration remain required in the existing `item-remove-before-invoice` record.

### 2026-09-16 — Return review uses non-monetary projections of existing facts

The existing charge/Invoice streams require full financial access. Ordinary-category
Item returns must not inherit that restriction. `item_return_review` projects
existing charge identities/revisions and active/collected source membership into
three explicitly named client tables. It includes no money, Invoice identity,
payment identity or contents; category visibility and active Account membership
still authorize every source. These are sync projections, not new server tables,
accounting events or balances. The server command remains authoritative on replay.

Separate membership projections allow removal/release to update eligibility
without maintaining a second server eligibility cache. The actual PowerSync parser
accepts the queries. Queue integration must require complete scoped downloads;
real replication, revocation, query fanout and source-history tests remain required
before deployment. Parser success alone does not establish offline correctness.

Capacity verification correction: the initial no-server-projection approach is
not approved for hosted deployment. The repeatable
`scripts/test-local-return-sync-capacity.mjs` fixture (10 Projects × 700 charges)
fails inside the pinned PowerSync `BucketParameterQuerier.js` result aggregation
for both membership queries. The charge query remains bounded. This is evidence
against the current query implementation, not authority to weaken membership or
category checks. Refine the membership delivery to avoid per-charge parameter
expansion, retaining current category authorization and source history; require
the capacity fixture, revocation and actual replication to pass before replacing
this proposed implementation. Any derived server fields must be maintained from
the existing facts, not become independently editable accounting state.

The local replacement now uses private `item_return_reviews`: charge references,
current category/revision, withdrawal and live/collected membership booleans only.
Triggers refresh it under the existing charge-source lock when charges or Invoice
membership change; the migration backfills existing charges. No amounts or
Invoice/payment identity are copied, and API roles have no table privileges.
Sync still checks current category visibility and active membership. This avoids
loosening immutable charge/collected-record guards merely to store sync metadata.
The same three client table shapes are retained, so app behavior is unchanged.
The 10×700 evaluator now passes (six parameter rows per query); 48 focused SQL
checks pass. Actual replication, concurrent refresh, source truncation handling,
fresh migration and category-withdrawal checks remain required before acceptance.

## 2026-09-16 — Imported Fee creation metadata

Extend the existing Expense import-evidence pattern to Fees: preserve unknown
creation time/creator as null rather than inventing an operator identity or time.
Normal Fee creation still supplies both fields. A deferred constraint permits
missing metadata only with an immutable, operator-only source-evidence row linked
to the imported Invoice in the same target Account/Project. Original Fee identity
is scoped by source Account, Project and document, because Fee documents are
Project-nested. Raw source bytes retain unknown fields and timestamp precision.

This does not expose another app API, change Fee billing or waive paid locks.
The local migration and ordinary-write denial checks pass the 59-file SQL suite
(1874 assertions). The mixed atomic importer, positive evidence/retry/rollback
tests, clean replay and advisors remain required; no hosted deployment occurred.

The shared `import_invoice_sources` writer now accepts ordered complete Expense
and Fee records. The legacy Expense entry point delegates to it, preserving its
stored retry payload; there is one implementation of payment binding, insertion
and freezing. Fee identity retains its original Project namespace. Mapping does
not run live collection or create new payment evidence. Unsupported Item/manual
and unresolved settlement histories remain excluded, not silently subtotaled.
The synthetic Swift-to-SQL rollback bridge, duplicate-source denial, three
observed concurrent retry/rollback cases and 104-migration clean replay pass;
local advisors report no issues. These are local evidence, not production
migration approval or full historical migration coverage.

## 2026-09-16 — Historical paid Item amounts during migration

The frozen source baseline `ca68d793f193463fd191d272891d02cf85b7c5c4`,
`Invoice.swift`'s `InvoiceLine`, stores stable line/Item identity, signed amount,
category, label and settlement links. It does not store the historical Item
price calculation. Current Item purchase/project prices and current placement
must not be used to fabricate that missing basis.

For a fully reconciled positive paid Item line, represent its recorded amount
as imported paid-line evidence, retaining the original Invoice/Item envelopes
and source-line identity. This needs an explicit imported-amount price basis
in the existing frozen snapshot contract, rather than labeling it project price
or introducing a self-referential paid-line lookup. Only the operator migration
may introduce that basis; ordinary app commands retain their existing rules.
Stable imported occurrence identity must derive from the source Invoice line,
not today's placement. Do not fabricate a historical placement date or move the
physical Item during import. Negative lines remain unresolved until their exact
reversed occurrence can be demonstrated. This is a technical representation
under D-028, not approval to drop history or guess a financial policy.

Local verification now covers Swift/MCP persisted decoding, operator-only SQL
admission, raw evidence binding, exact reconciliation, encrypted reopen and
historical billing after the Item has moved. Mixed Item/Expense/Fee rollback,
retry concurrency, clean migration replay and targeted iPhone history checks
pass. This is not hosted deployment, full migration coverage or cutover approval.

Item history exposes downloaded frozen billing lines independently of current
placement through `DownloadedItemInvoiceLine`, reusing `FrozenInvoiceLine` and
the existing full-Invoice decoder. These are billing amounts, not allocations
of the entire client payment and not synthetic physical intervals. The reader
requires active full financial access and omits incomplete Invoice evidence
while retaining explicitly partial physical history. The existing History section
shows these facts without replacing the screen or changing current accounting.

The history watch owns an on-demand `item_invoice_history` subscription scoped
to Account and Item. It downloads complete Invoices containing that Item so the
shared decoder can validate totals, rather than treating a partial line subset
as a complete Invoice. Active full financial membership is required. Its row
projections match existing Project subscriptions; it does not depend on current
placement or download all Account Invoices. Cancellation uses the existing owned
subscription cleanup. The pinned local service resolves 7,000 synthetic lines
within capacity and denies foreign/removed/limited access. Live replication
delivers imported records and withdraws them after financial access changes.
The temporary copier apply guard is removed; actual source copying still needs
the existing explicit scope and isolation checks.

### 2026-09-16 — Market-value edits reuse the Item-details operation

Market value is the existing physical-report estimate, not acquisition cost,
project charge, or payment evidence. Reuse the Item-details command, local queue,
revision lock, receipt and editor rather than introduce another operation family.
Commands containing an explicit market-value set/clear use `item-details-edit-v2`;
commands without it retain v1 and their exact replay bytes. Keep v1 decoding and
server handling for pending offline work. This requires corresponding native,
MCP and Postgres changes before enabling the control; a Core type alone is not
delivery. Nonnegative new values follow items.md; absence differs from zero,
and readers preserve signed legacy evidence without silently repairing it.
The existing market-value stream/read entitlement stays unchanged. Purchase,
project-price and frozen accounting facts are never modified by this operation.
Evidence and unfinished layers belong to `item-everyday-editing` in the checklist.

### 2026-09-16 — Inventory pricing extends the existing price-edit path

The current-price floor applies to Inventory as well as Project Items. Extend
the existing price command/provider/editor, preserving the exact v1 Project
payload and wire encoding. Inventory uses `item-inventory-price-edit-v2`, an
exact placement and price revision, no Project/charge identity, and explicit
clear intent distinct from zero. A requested clear still respects a known
positive cost floor; absence of downloaded evidence never means zero cost.
Keep the existing positive-value requirement for sale/charge creation.

Clearing a stored price must retain its revision identity rather than delete
the row and reset the next review to revision zero. Implement that representation
and update all readers before enabling Inventory submission. Reuse existing
access, queue, replay and receipt boundaries; no acquisition, frozen Invoice,
inventory-entry amount or historical payment is rewritten. The tradeoff is a
versioned scope in the existing operation, not a new screen or parallel history.
Contract groundwork is not delivery: database concurrency, local admission,
MCP, UI and actual sync evidence remain required in `item-everyday-editing`.

### 2026-09-17 — Paid returns retain the frozen charge and add linked credit

Implement lifecycle Story4 under `item-credit-after-payment`: retain the
positive collected charge, Invoice line and payment unchanged, and create a
separate negative credit linked uniquely to that frozen line and the physical
return. The server derives amount/category from frozen evidence; the command
contains identities, not caller-authored money. Return and credit creation must
commit together, with existing placement/source locks and replay receipts.
This avoids weakening the positive-charge and paid-history constraints merely
to encode a return. Reuse existing return controls, queue and transport.

The tradeoff is a distinct credit fact in the existing accounting projections,
not a second physical Item/history system or a synthetic refund Transaction.
Do not automatically create a credit-only Invoice or settle a credit: those
policies remain separate. Proven imported facts use the same validation;
ambiguous legacy paid basis must not be guessed. Typed-intent tests pass;
database, budget/read/sync, offline, app/MCP and concurrency proof remain pending
in the owning checklist record.

Inventory history uses the existing on-demand `item_invoice_history` stream for
paid-return credit links, alongside frozen Invoice contents; the account physical
stream supplies placement history. These links remain Item-scoped after a move
or resale and require active full-financial membership. The existing history
reader joins the credit to its exact frozen line/occurrence and Inventory
placement, and the existing Invoice-line UI displays the resulting credit without
implying a cash refund. Incomplete downloaded history remains explicitly partial.
This does not require retaining every Project's financial stream in Inventory.
Invoicing list identity includes charge/credit polarity plus the raw source ID:
the separate tables may legitimately reuse a raw ID. This changes only combined
read/display identity; persisted command, charge and credit IDs remain unchanged.

The 10-Project/700-Item capacity check exposed per-charge bucket expansion in
the Project credit join and category lookup. Credits now carry a derived,
immutable `project_id`, populated/validated against their charge by the database;
the migration backfills under a transaction/table lock without changing money or
provenance. Project credit routing filters this column directly. Category labels
use the already-authorized Account/full-financial reference scope rather than
looking up a category once per charge. The tradeoff is one verified routing
column, not another accounting source. The pinned service evaluator now uses
one bucket per Project credit query; combined ten-Project input stays bounded.

### 2026-09-17 — Budget composition reuses accounting facts

`ProjectBudgetCalculation` combines existing frozen Invoice lines, live/unassigned
Invoice candidates, explicit Item credits and direct Transaction snapshots into
the existing paid/unpaid category segments. Collected lines replace their live
Invoice; the associated lump-sum payment is verified but never added again.
There is no new stored budget ledger. The provider must establish one authorized,
complete local snapshot; this pure calculation cannot establish download or
provenance completeness itself. Unknown Transfers and missing source/category
evidence are not zero. Provider/runtime/MCP/UI and Transfer/overlay integration
remain required in `project-budget-progress`; the first mixed-source tests are
calculation evidence, not complete budget delivery.

The MCP read uses `spike_read_project_budget`, a read-only `STABLE` Postgres
function over those existing facts. Authorization and amounts therefore share
the calling statement's snapshot instead of combining separate RPC responses
across collection. Its private definer checks authenticated full-financial
Account membership and exact Project scope; the public invoker wrapper grants
only authenticated execution, not table access. Amounts are Int64 decimal text;
the MCP adapter validates category/overall sums with BigInt and rejects mismatched
scope, overflow and false completeness. This duplicates the offline calculation
at the server boundary, not its storage; parity remains a required test obligation.
The current result explicitly excludes complete Transfer/Additional Requests
coverage and cannot include unsynced device edits. Local SQL collection/return
and permission tests plus MCP contract tests exist; hosted and complete parity
acceptance remain open in the existing workflow record.

The actual-service parity test exposed a cross-priority readiness gap: a prior
financial checkpoint could yield 900 while a newer directory state required
another 200 of direct payments. Budget now applies the existing Transaction
export rule to all consumed streams: their completed microsecond checkpoints
must be at least the directory checkpoint. Until then the watch emits incomplete,
not a partial total. This is a reuse of the existing readiness mechanism, not a
new sync subsystem. The same real-service fixture subsequently matched native,
RPC and MCP amounts and retained those amounts through encrypted offline reopen.

### Source movement interpretation (2026-09-17)

Migration distinguishes physical custody from legacy movement labels before
constructing target intervals. `FirebasePhysicalMovementEvidence` interprets
the audited Swift app writer shapes (baseline `fe018501`,
`InventoryOperationsService` and `ItemsService`), retaining original lineage
records. A same-Project `returned` edge is not a physical return; explicit
correction scopes can change custody. Missing correction scopes, unknown writer
sources, invalid references and unsupported shapes remain unresolved. No cash,
Invoice credit or paid status is inferred from these interpretations.

The private QA manifest consumes these results with `targetHistoryImported=false`.
This is not interval reconstruction: atomic same-time two-hop moves must retain
both source edges without inventing a positive-duration Inventory stay, and an
unknown initial custody time must remain unknown. Target import/reconciliation
is still required. Focused interpretation tests cover these per-edge distinctions;
they do not prove complete historical migration.

Imported movement envelopes are retained in private, immutable
`imported_item_movement_sources`, bound to the exact target Account/Item and
unique original Account/document identity. The copier uses the existing
`canonicalEvidenceData()` encoding and reconciles retained counts in its import
transaction. This table is source provenance, not a second current-location
authority: it grants no credit eligibility, contains no calculated balances and
has no app/service API grants or Sync publication. Known target intervals remain
the responsibility of the history importer; unknown initial start times are not
fabricated. Local storage/grant tests pass; no hosted deployment or real copy of
this extension has yet been performed.

The copier now emits known placement intervals from validated transitions,
retaining its existing current-placement identity for downstream import links.
Historical intervals start at actual source movements and end at the next known
movement; only the current interval receives the current Space assignment.
Source records explicitly reference their resulting placement through an
Account/Item-scoped foreign key. Unknown initial custody is omitted, not dated;
unresolved chains retain an `import_observation` instead. Sub-microsecond source
timestamps are retained but not converted to Postgres intervals by rounding.
These changes have compilation/unit/storage evidence, not a completed import
rehearsal or imported paid-return eligibility proof.

Reviewed paid-line placement mappings use the operator-only atomic
`import_invoice_sources_with_placements` wrapper. It creates the exact charge
before freezing the Invoice, preserving the existing prohibition on adding a
charge behind an already-frozen line. Every Item line needs an explicitly named,
same-Account/Project/Item recorded placement; current location and date proximity
are never selectors. Review bytes and reviewer identity are retained immutably;
conflicting retries fail. Imported prices retain `imported_invoice_amount`, not
`project_price`. Unmapped legacy paid lines remain retained evidence without
invented custody or return eligibility. This is a local operator boundary, not
authorization to migrate data; Swift mapping input and imported paid-return
end-to-end verification remain unfinished.

## 2026-09-17 — Space assignment is not a new billing/custody cycle

The existing physical placement guard allowed only closing an interval. Reusing
that interval model by closing/reopening on every Space edit would incorrectly
separate current Items from charge/Invoice links attached to the Project cycle.
Set Space instead changes only the open interval's Space, retaining the physical
Item, Project/Inventory interval identity, start evidence and accounting links.
Closed intervals remain immutable; Project/Inventory movement still creates a
successor. A private immutable `item_space_changes` fact records old/new Space,
actor, server time and placement revision. This is Space-change provenance, not
a competing purchase/payment history or a fabricated prior assignment timeline.

`item_placement_versions` provides a per-Item optimistic concurrency token,
separate from descriptive Item revision. Inserts, closures and Space changes
advance it, so leaving and returning to the same Project cannot revive a stale
assignment intent. Existing Items start with token1; that value is not a claim
about the number of historical moves. Derived Space counts use old/new net
membership changes rather than assuming every placement update is a closure.

The internal atomic handler reuses operation receipts and exact-byte replay;
it checks actor, active membership, scope, destination revision and each selected
placement revision. Clear also checks each old Space. Neither the handler nor
its tables permit direct app writes. Local tests cover assignment/clear/history,
rollback, replay and denied input. Pending before exposure: concurrent races,
photo-checkmark closure, app/MCP transport and reused-picker interactions.
O-053 also gates the final role/capability policy; internal active-membership
checks are not approval to expose these commands to every Employee.
No hosted deployment or cutover is implied.

The token includes its current placement/Space and derived Project routing.
The local reader only offers it when the downloaded placement and Space match;
partial replication cannot pair a fresh token with an older location. Missing,
malformed or out-of-range tokens remain unavailable, not a guessed revision.
Existing Project and Inventory subscriptions carry the same projection, without
per-Item subscription fan-out. Encrypted local reopen and actual local
Auth/PowerSync Inventory→Project movement tests pass; assignment upload itself
is not yet integrated.

## 2026-09-17 — Transaction descriptive edits have a separate revision

Preserved source/notes/payment-method/email-receipt edits use the existing
operation/result protocol, not a new Transaction entity or accounting writer.
`spike_transactions.details_revision` advances when these fields change; it
does not claim to version cash, placement or the entire receipt. This avoids
silently overwriting another descriptive edit without conflating category or
attachment revisions. Unchanged values do not manufacture a revision.

The private handler locks current membership, the Transaction and its category,
checks exact scope and visibility before replay, and retains the imported-payment
immutable guard. No amount/date/type, receipt-line, Item or frozen-Invoice field
is writable through this command. Existing imported payments remain outside
this edit route; this does not settle their correction workflow.

Local SQL tests and observed competing-edit/retry/rollback/revocation races pass;
the workflow checklist owns the exact evidence. The existing read projection
now carries the revision, and an authenticated invoker RPC exposes the checked
handler for local integration. Native/MCP wire fingerprints agree; actual MCP
HTTP edits and immutable-payment denial pass. The native offline queue and reused
Notes/Details controls are now connected. Encrypted restart, exact retry, real
local upload/readback and focused iPhone interactions pass. Reopening an edit
recovers its pending or rejected values; applied work is released after a newer
authoritative revision arrives. Rejected-operation resolution policy is unchanged.
Focused Mac Notes/retry/reopen and Details/Cancel/clear/rejection interactions
also pass. Exact-commit integration acceptance remains outstanding; the workflow
checklist owns that gap. No hosted deployment is implied.

## 2026-09-17 — Receipt-line edits compare the reviewed line values

Transaction receipt-line editing has a separate narrow command from descriptive
editing. It replaces only the ordered non-Item lines and carries the reviewed
lines as its concurrency precondition. The server must compare those values
under the Transaction lock before replacement, after current authorization and
the existing immutable-payment guard. Missing optional quantity and explicit
null mean the same absent quantity; ordering, IDs, wording, amounts and effects
remain significant. A return to identical values is not a conflict: this command
does not assert that no intervening edit occurred. Exact operation replay still
uses the existing durable receipt protocol.

This avoids another revision column and sync projection solely for this array.
It does not version Item membership, cash, billing allocations or frozen Invoice
facts, none of which this command may change. D-016/D-030/O-032 permit saving
incomplete receipt details; exact audit mismatch remains visible rather than
blocking Save. O-008 billability is not resolved here. The shared input parser
is extracted from Expense editing with saved-draft compatibility tests, not a
second parser or replacement UI. Command tests are in progress; server, offline
queue, app/MCP integration and their risk evidence remain required.

### Receipt editor local recovery implementation

Descriptive and receipt-line edits share the existing Transaction local store,
upload terminalization, access fence and watch lifecycle. An internal two-case
`TransactionEditWork` keeps their payloads, operation namespaces, reviewed-value
checks and result codes distinct; this is not a generic command framework.
The existing Expense line fields are extracted without behavioral changes and
used by both forms. Saved Expense draft encoding remains unchanged.

Receipt edit readback must not depend on the current array still matching the
submitted array: a later legitimate edit may already have replaced it. The first
local implementation compared Transaction and Operation-result stream checkpoints.
Review rejected that approach: subsequent result-stream progress can make an
already-confirmed operation appear pending again. Its passing same-checkpoint
test did not prove stable recovery; the priority-interleaving fixture also failed.

Replace that provisional implementation with a receipt-specific revision on the
Transaction and the applied revision on its immutable Operation result. Confirm
readback only when the downloaded Transaction revision reaches or exceeds that
validated result revision. This adds sync fields but avoids persistent checkpoint
bookkeeping and handles later edits without array equality. It supersedes the
earlier choice to avoid a revision column; reviewed-line value comparison remains
the command's concurrency policy, and descriptive edits remain independent.
Implemented by migration `20260917193630`, the existing stream projections and
`TransactionEditWork.hasReadback`. The result revision is canonical decimal text
at cross-language boundaries; the Transaction counter is a checked Postgres
bigint. Missing readback metadata cannot confirm an edit. SQL proves retry,
rejection and overflow behavior; SDK-fed tests prove result-first, later-edit and
restart recovery. Live-runtime/UI verification remains in the workflow checklist.
Rejected operations remain retained; no user correction policy changes.

The live receipt test exposed a pre-existing operation-result projection defect:
Postgres keys results by `operation_id`, while native PowerSync queries use `id`.
The wildcard-only stream evaluated to an empty downloaded ID. Explicitly alias
`operation_id AS id` after the wildcard, preserving each immutable result's
identity and all existing fields. The service-evaluator regression exercises two
distinct operation IDs and receipt revision evidence. The local live-runtime
test passed after reloading this correction, including offline save, encrypted
restart, upload and replicated readback. No product policy or UI replacement is involved.
