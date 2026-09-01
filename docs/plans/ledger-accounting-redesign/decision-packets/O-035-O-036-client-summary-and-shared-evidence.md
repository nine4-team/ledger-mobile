# Decision Packet — O-035/O-036 Client Summary and Shared Evidence

Status: proposed recommendation; product decision not yet approved
Last reviewed: 2026-08-31
Owners: Reporting, Budget Projection, Client Delivery, Attachments, Security
Unlocks: 11 unique residual surfaces (O-035: 9; O-036: 7; overlap: 5)
Residual register: [generated M2 queue](../conversion/residual-decision-register.generated.md)

## Decision Requested

Approve or reject this reporting contract:

> Replace the ambiguous Client Summary “Total Spent” with three explicit signed
> values from the canonical contribution projection: **Client paid**, **Open
> charges & credits**, and **Recognized project value** (`paid + open`). Show the
> same values per Project and category. Same-Client Transfers reallocate between
> Projects but remain net zero in the Client aggregate. Current physical Item
> value, if shown, is a separate nonfinancial inventory section and never part of
> paid/recognized accounting.

> Client-shared reports omit vendor receipt evidence by default. A financial-
> authorized user may explicitly select eligible evidence after preview/redaction.
> Ledger renders the chosen evidence into or alongside one immutable standalone
> report package with a manifest and delivery audit. The package contains no raw
> Storage path, token URL, expiring link, or internal-only metadata. The initial
> release offers no dynamic receipt link/portal. Once a standalone file is shared
> outside Ledger it cannot be remotely revoked, and the UI must say so.

The decisions are coupled because the report's financial meaning determines
which evidence is relevant and safe to expose.

## Confirmed Constraints

- Current active Item project prices are not proof of Client payment and exclude
  Expenses, Fees, credits, collections and Transfers.
- The canonical budget has signed paid and unpaid/open contribution segments.
  Collection changes segment ownership without changing recognized value.
- A collection Purchase face amount and its frozen source allocations cannot
  both contribute to spend.
- Same-Client Transfer is client-wide net zero while changing Project attribution.
- Reports consume canonical projections; screen/PDF/print/MCP do not recalculate
  business rules from mutable entities.
- Financial authorization is enforced before download. Counts/totals/omissions
  cannot leak hidden data.
- Attachments use stable IDs/private access. Signed URLs and raw object paths are
  never durable report content.

## Options

### Option A — Keep active Item prices as “Total Spent” and embed receipt links

Reject. It mislabels uncollected estimates as payment, omits other sources, and
can leak private or expiring Storage access.

### Option B — Show only cash paid and never permit supporting evidence

Reject as incomplete. It hides open obligations/credits and prevents a user from
deliberately sharing eligible supporting material.

### Option C — Paid/open/recognized snapshot plus explicit immutable evidence
package (recommended)

Use canonical signed contributions with distinct labels, keep physical Item
estimates separate, omit receipts by default, and include only explicitly
selected/redacted evidence in one standalone audited package with no remote
tokens or paths.

## Client Summary Financial Model

For Client `c`, Project `p`, and category `k`:

```text
client_paid(c,p,k) = signed accepted paid contribution allocations
open(c,p,k)        = signed active uncollected contribution allocations
recognized(c,p,k)  = client_paid(c,p,k) + open(c,p,k)
```

Paid contributions include:

- direct Client-paid Project Purchase/Return allocations;
- frozen source allocations from collected Invoices (using the one collection
  Purchase only as payment/correlation evidence); and
- approved signed Transfer reallocation for the Project.

Open contributions include:

- active Item charges/credits;
- Expenses, Fees and typed ClientAdjustments; and
- reserved/applied Client credit effects while still uncollected.

Rules:

- credits/refunds remain signed and visible; they are not clamped to zero;
- paid + open equals recognized at every Project/category and Client aggregate;
- collection, credit offset and cash refund preserve recognized immediately
  before/after while changing paid/open provenance;
- Transfer entries may change Project rows but their sum across the authoritative
  Client ID is zero;
- unresolved/migrating/partial projection state blocks a “complete” Client report;
  and
- all Projects are grouped by stable `client_id`, never normalized name text.

## Labels and Layout

The report uses these labels:

- **Client paid** — actual Client-paid/refunded value allocated to the work;
- **Open charges & credits** — current uncollected amount expected from or owed
  to the Client; and
- **Recognized project value** — signed net of paid and open.

It does not label any of these “Total Spent” without a qualifier. A compact
summary shows all three, report as-of time, currency, included Projects and data
readiness. Project/category tables use the same fields and stable contribution
snapshot. Credit labels include minus/credit text, not color alone.

Optional nonfinancial sections are explicitly separate:

- current physical Items/counts/placement;
- current estimated or approved project-price value, labeled as an estimate;
- Space/property grouping; and
- activity/provenance milestones.

No physical Item estimate participates in financial totals or category
reconciliation.

## Report Snapshot Contract

`ClientSummarySnapshot` is immutable input to screen, HTML, PDF, print, CSV and
MCP rendering and contains:

- Account/Client IDs and approved display snapshot;
- included Project IDs/display snapshots;
- paid/open/recognized signed cents by Client/Project/category;
- stable contribution/version/hash references and as-of time;
- currency/locale and projection-contract/accounting-authority versions;
- readiness, integrity warnings and authorized omission reasons;
- optional nonfinancial sections with their distinct value basis; and
- evidence-selection eligibility metadata without remote URLs.

All renderers format this snapshot only. They cannot query mutable Items/
Transactions, substitute status for payment, or recompute totals. MCP receives
the same named projection profile and safe cursor/version semantics.

## Receipt Evidence Sharing Policy

### Default

Client Summary, Invoice copies and other client-shared reports omit vendor
receipt images/PDFs and internal evidence unless the user explicitly enters
**Include supporting documents** and selects each eligible Attachment.

### Eligibility

The trusted selector/handler requires:

- Attachment belongs to an included authorized Project/source and has verified
  original bytes/checksum/type;
- actor can view the underlying financial source and share client evidence;
- evidence is not internal-only, another Client/Project's material, payment-
  credential/card data, staff note, migration/quarantine data, or otherwise
  restricted;
- any required redaction has a verified derivative and review receipt;
- selected evidence matches the report source revision/as-of boundary; and
- O-023 retention/reference holds are established for the resulting artifact.

Eligibility is deny-by-default. A filename or gallery visibility does not grant
sharing permission.

### Artifact form

The initial release supports:

1. embedded sanitized pages/images in the standalone PDF; or
2. a standalone report package containing the report PDF plus explicitly
   selected sanitized files and a manifest.

The manifest records stable source Attachment/revision IDs, safe display names,
hashes/sizes/types, redaction version, report snapshot/version/hash, actor,
creation time and delivery events. Client files contain no internal IDs unless
needed, raw bucket paths, signed/token URLs, secrets or hidden metadata/EXIF.

Dynamic authorized receipt links/portals are deferred. A standalone file works
offline and does not expire, but Ledger cannot revoke a copy after external
delivery. The confirmation UI must state that limitation and show exactly what
will be shared.

## Rendering and Delivery

- Report generation starts only from a complete authorized snapshot and locally
  available/verified selected evidence bytes. Offline generation is allowed when
  every required input is complete; otherwise it returns a missing-input result.
- Sanitization/redaction strips EXIF and nonessential metadata, enforces allowed
  types/page/resource limits, and produces versioned derivatives. The original
  remains private/retained under O-023.
- Rendering uses unique protected temporary paths, deterministic content input,
  bounded resources and a typed result. Concurrent renders cannot overwrite one
  another.
- Delivery/share records actor, report/artifact hash, recipient/method if known,
  time and success/attestation. It never records a bearer URL.
- Temporary local artifacts have explicit protected cleanup. Durable server
  artifacts are private and held according to report/financial retention.

## Conceptual Target Shape

| Family | Responsibility |
|---|---|
| contribution projection/snapshot | Signed paid/open/recognized values by Client/Project/category and version |
| `report_snapshots` | Immutable scope, values, readiness, as-of and contract versions |
| `report_evidence_selections` | Exact selected source Attachment/revision, eligibility/redaction result and actor |
| `report_artifacts` | Private immutable report/package metadata, hash, size, type and retention |
| sanitized evidence derivatives | Versioned redacted/metadata-stripped bytes tied to source identity |
| report delivery events | Immutable share/download/manual-delivery evidence |
| operation/results | Idempotent generation/delivery, failures and retry state |

Use stable IDs, `bigint` cents, `timestamptz`, explicit currency/readiness/type
checks and foreign keys. Index every foreign key/RLS key, Client/Project/category
snapshot lookup, artifact/evidence relation and delivery history. Use keyset
cursors for large contribution/evidence lists; do not deep-offset or include
hidden rows in counts.

## Authorization, RLS, Sync, and Offline

- Report snapshot authorization is the intersection of Client/Project access,
  financial category visibility, evidence access and share capability. Mixed
  hidden content fails closed; the system does not silently produce a plausible
  partial Client report.
- Direct writes to projection/snapshot/evidence eligibility/artifact/delivery
  authority are revoked. Trusted handlers produce immutable snapshots/results.
- Selected local workspace streams include only authorized report inputs and
  explicit readiness/version. A report cannot use stale cached membership to
  regain server access or share newly revoked evidence.
- Restricted users receive no hidden totals/counts/category names/evidence
  eligibility hints/file metadata or error details.
- Offline report generation never extends the approved offline authorization
  lease. Logout/revocation/pending artifact cleanup follows the durable local-
  data policy and cannot silently leak files to another Principal.

## Migration and Reconciliation

- Preserve current Client Summary rows/totals, active Item price inputs, report
  versions if any, PDF/receipt inclusion, source IDs and generated artifacts as
  source evidence—not target financial authority.
- Rebuild target snapshots from migrated Client IDs and canonical contribution
  rows. Compare current “Total Spent” only as a named legacy metric; do not force
  target paid/open/recognized values to match it.
- Classify every difference by omitted Expenses/Fees/credits, collection state,
  Transfer, inactive/current Item, source correction, visibility, or migration
  issue. Unknown differences block parity.
- Migrate a client-shared receipt only with proven artifact/delivery/reference
  evidence and approved eligibility. Raw token URLs/paths remain protected source
  evidence and never target report content.
- Existing externally shared files are immutable historical artifacts; inability
  to revoke them must be recorded, not hidden.

Reconcile contribution IDs/cents by Client/Project/category/segment, Client-wide
Transfer net zero, report snapshot hashes/versions, evidence selections, object
hashes, delivery events, restricted-view results and every semantic-difference/
quarantine reason.

## Required Acceptance Tests

### Financial semantics

- direct paid, open Item/Expense/Fee/adjustment, credit, collection, offset,
  refund and Transfer fixtures produce exact paid/open/recognized values;
- collection/settlement changes segment ownership with unchanged recognized;
- per-Project Transfer changes sum to zero across Client;
- physical Item value never enters financial totals;
- Project card/report/PDF/CSV/MCP render identical snapshot cents/labels; and
- partial/integrity-blocked/restricted scope cannot render as complete/zero.

### Evidence and artifacts

- default report contains no receipt evidence or hidden metadata;
- explicit selection requires exact authorization/source revision and preview;
- internal/cross-Client/restricted/unverified/unredacted evidence rejects without
  existence leakage;
- embedded/package outputs contain no raw path, signed URL, token, EXIF, formula
  payload or secret metadata;
- offline generation succeeds only with complete local snapshot/bytes;
- concurrent generation uses unique files and deterministic hashes/results;
- delivery audit binds the exact immutable artifact and states non-revocability;
  and
- O-023 holds prevent selected source/artifact deletion.

### Migration and security

- legacy active-Item “Total Spent” differences are fully classified rather than
  made a false target parity requirement;
- token URL/raw path/external artifact fixtures never leak into target reports;
- full/limited/none financial roles and cross-account attempts reveal no hidden
  totals/counts/evidence; and
- repeat/interrupted snapshot/artifact migration is idempotent and reconciled.

## Approval Consequences

If approved:

1. update canonical report/budget/financial-access/attachment specs and record
   confirmed decisions;
2. promote snapshot/label/evidence/artifact contracts into architecture 03/04/
   05/06/07/08;
3. remap the 11 affected surfaces while retaining O-003–O-015/O-023/O-029–O-034
   and other independent blockers;
4. specify reviewed query/index/RLS/Sync profiles, renderer/artifact manifest,
   redaction policy and migration parity fixtures; and
5. include signed-value, Transfer-net-zero, offline artifact and data-leak tests
   in the target spike.

## Approval Checklist

- [ ] Replace “Total Spent” with Client paid, Open charges & credits, and
  Recognized project value.
- [ ] Same signed values appear per Project/category and Client aggregate.
- [ ] Same-Client Transfers are Client-wide net zero.
- [ ] Physical Item value is a separate nonfinancial estimate.
- [ ] Receipt evidence is omitted by default and selected explicitly after
  eligibility/redaction preview.
- [ ] Initial sharing uses immutable standalone files/packages, not dynamic or
  expiring receipt links.
- [ ] Shared artifacts contain no raw paths/tokens/internal metadata and cannot
  be claimed remotely revocable after external delivery.
