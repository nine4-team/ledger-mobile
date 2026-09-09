# Architecture Decision Register

Status: active
Architecture version: 0.2
Last reviewed: 2026-09-07

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

## Decision Summary

| ID | Status | Decision |
|---|---|---|
| A-001 | accepted | Use domain-oriented ports and backend adapters |
| A-002 | accepted | Separate commands from local queries |
| A-003 | proposed | Supabase Postgres becomes target server authority |
| A-004 | proposed | PowerSync SQLite becomes the target local data plane |
| A-005 | proposed | Complex mutations use durable idempotent operation envelopes |
| A-006 | proposed | Structured sync excludes attachment bytes |
| A-007 | proposed | Choose Supabase Auth at launch or a temporary Firebase Auth integration |
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

**Proposal:** Either migrate to Supabase Auth for the target launch or keep
Firebase Auth temporarily through Supabase Third-Party Auth and PowerSync token
validation, then migrate identity as a separate release. The vertical spike and
release-risk review must close this choice.

**Reason:** Supabase and PowerSync can validate Firebase-issued JWTs, which may
lower simultaneous cutover risk, while migrating to Supabase Auth at launch
would remove a legacy dependency earlier.

**Consequence:** Ledger uses an internal principal ID and an issuer/subject
identity mapping so a later Auth migration does not rewrite domain ownership.
The temporary identity integration, if selected, does not require a Firestore,
Firebase Storage, or Firebase application-data adapter.

**Evidence protocol:** S2 compares Supabase Auth with an isolated identity-only
Firebase contingency under the same disqualifying security tests and weighted
migration/recovery criteria. No provider is selected by the protocol itself.

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
