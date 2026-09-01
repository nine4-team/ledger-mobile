# Decision Packet — O-016/O-017/O-027 Item Capture and Acquisition Readiness

Status: proposed recommendation; product decision not yet approved
Last reviewed: 2026-08-31
Owners: Item Creation, Link, Attachments, Inventory Acquisition, Offline Capture
Unlocks: 11 unique residual surfaces (O-016: 2; O-017: 1; O-027: 10)
Residual register: [generated M2 queue](../conversion/residual-decision-register.generated.md)

## Decision Requested

Approve or reject these coordinated Item-capture rules:

1. A real Item may be saved when at least one of trimmed nonempty **name**,
   durably retained **photo**, or trimmed nonempty **note** exists. Price, payer,
   vendor, SKU, category detail and acquisition evidence are not minimum identity.
2. The creation wizard stores no payer hint. A UI-local, disposable suggestion is
   permitted, but it cannot sync, authorize, categorize, route migration or
   change Unaccounted For state. Link remains the only authoritative Client-paid/
   Business-paid choice.
3. Business-paid Link without a selected Inventory Purchase creates an explicit
   unresolved acquisition-evidence association/readiness state, not a fabricated
   Purchase or fake zero basis. The Item still receives one open billable
   occurrence and becomes Accounted For. A later typed command links proven
   acquisition evidence or records real money through the ordinary posting path.

## Confirmed Constraints

- One wizard creates one real Item identity; target creates no ProtoItem/draft
  object or later promotion step.
- Saving the minimum and continuing optional detail preserves the same Item ID.
- Unaccounted For/Accounted For depends only on Client-paid Purchase relationship
  or billable Item occurrence, not field completeness, Space or payer hint.
- Client-paid Link requires the real current-Project Purchase. Business-paid Link
  creates an open Item charge and no Project Transaction before collection.
- Selecting an Inventory Purchase for Business-paid Link is optional.
- Offline capture must survive process death; photo success requires durable
  protected local bytes/receipt, not a placeholder URL.
- App, MCP, import repair and retry use the same Item validation/Link commands.

## Options

| Decision | Rejected alternatives | Recommended option |
|---|---|---|
| O-027 minimum identity | require name; require name or photo; retain contradictory Quick/full-form rules | Any one durable trimmed name, retained photo, or trimmed note |
| O-017 payer hint | persist/sync a hint; let a hint affect accounting or migration | No persisted hint; a disposable UI suggestion is permitted and Link remains authority |
| O-016 missing Business acquisition | require Purchase selection; fabricate zero/estimated Purchase; treat missing as complete | Explicit unresolved acquisition evidence/readiness with later typed resolution |

The option in each row is independent but its recommendation is exact. A
different selection must update shared `CreateItem`/Link/import validation and
the corresponding offline/migration tests before approval.

## Minimum Identifying Evidence

`CreateItem` normalizes:

- `name`: Unicode-aware trim; must contain at least one meaningful non-whitespace
  character after normalization;
- `note`: same nonempty rule, preserving original user text; and
- `photo`: stable Attachment ID backed by an atomic durable local capture receipt
  or verified server original in the same authorized Item operation.

At least one must pass. A remote URL string, empty upload placeholder, failed
queue ID, deleted/detached Attachment, whitespace-only text or extraction
suggestion does not count.

Photo-only offline creation is valid after protected bytes plus Attachment/Item
metadata are durably committed locally. Server acceptance may precede completed
object upload, but the Item carries `photo_verification_pending` readiness until
the original is verified. Permanent media rejection does not delete the real
Item; it moves the Item to an explicit identifying-evidence work queue until the
user adds valid evidence or restores/retries the photo.

MCP cannot claim a photo without verified uploaded/ingested bytes. Import can
map source media only when reference/object evidence meets the approved migration
confidence; otherwise another name/note must satisfy identity or the record
enters migration review.

## Payer Hint

The target schema and synced Item contain no `payerHint`, `assignmentHint`,
`likelyPayer`, or equivalent pre-Link authority.

- Wizard may display a transient default/suggestion computed from navigation
  context to reduce taps.
- Dismissing/restarting loses it without changing the Item.
- Analytics may record that the Link branch was chosen only after the choice;
  they do not persist pre-choice financial inference in domain data.
- Legacy proto/current hints are migration evidence/suggestions and never map
  directly to Client-paid/Business-paid authority.

This keeps Unaccounted For as the honest persisted state when payer is unknown.

## Unresolved Acquisition Evidence

When `LinkItemAsBusinessPaid` has no selected proven Inventory Purchase, it
atomically creates:

- the approved open positive Item occurrence in the Project;
- explicit placement/provenance under O-007/O-015;
- an `UnresolvedAcquisitionEvidence` association tied to Item/Account/operation
  with reason `business_paid_source_not_selected`;
- acquisition-basis readiness `missing` or `partial`; and
- a work-queue action to link/record evidence later.

It creates no Inventory Purchase, vendor refund, zero-dollar Transaction,
estimated cost, copied payer hint or synthetic acquisition date.

Conceptual unresolved evidence carries:

- stable ID, Item/Account and optional source Project/Inventory context;
- reason/state, actor/time and Link operation;
- optional nonauthoritative vendor/date/amount/reference suggestions clearly
  marked as suggestions; and
- resolved-by acquisition/Purchase/review correlation and immutable resolution
  receipt.

`ResolveItemAcquisitionEvidence` may:

1. link the Item acquisition to an existing proven Inventory Purchase/component;
2. link/import another already-proven acquisition record; or
3. launch `PostTransaction` for a real Inventory Purchase after complete actual-
   money evidence, then link its acquisition role.

It may not create money from suggestions. Resolution revalidates Item, existing
acquisition, Purchase scope/owner/membership/cents/currency and expected revisions
and writes one idempotent result. The open Client billing price remains its own
explicit occurrence amount; later acquisition basis does not silently reprice a
sent/paid Invoice.

## Conceptual Target Shape

| Family | Responsibility |
|---|---|
| `items` | One physical identity, normalized descriptive fields, identification readiness and revision |
| attachment references/local receipts | Stable photo evidence and upload verification state under O-023 |
| acquisition associations | Proven Item acquisition relationship/basis source |
| unresolved acquisition evidence | Explicit missing/backfillable association/reason/resolution receipt |
| Item work-queue projection | Identification/acquisition readiness and exact remedy |
| operation/results | Idempotent create/Link/resolve, payload hash, expected revisions and outcomes |

Use stable client-generated text IDs, immutable Account ownership, foreign keys,
checks for evidence/readiness/resolution state and indexed active review queues.
Do not store provider URLs or JSON polymorphic money relationships. Partial
indexes cover unresolved acquisition/identification work; every FK/RLS predicate
is indexed.

## Commands and Offline Behavior

- `CreateItem` accepts one minimum evidence set and optional fields, returning a
  durable local operation receipt immediately after local atomic persistence.
- `ReviseItemDetails` adds/changes optional identification detail with expected
  revision; it does not change accounting Link.
- `LinkItemAsClientPaid` and `LinkItemAsBusinessPaid` remain distinct typed
  commands; payer cannot be a generic Item field patch.
- `ResolveItemAcquisitionEvidence` is separate from Link and from posting money.
- Local Item/photo state survives restart/account partition. Pending photo upload
  or Link is explicit; server rejection never silently deletes Item/bytes.
- An Item with unresolved acquisition remains usable in its approved Project
  workflow, but cost-basis/reporting functions expose partial readiness and
  cannot substitute zero.

## Authorization, RLS, and Sync

- Item create/detail requires active Account/Project capability; acquisition
  money/evidence requires applicable financial capability. A member who may see
  physical Item/Project price need not receive protected Business acquisition
  cost/vendor data.
- Direct writes to ownership, placement, occurrences, acquisition links,
  unresolved resolution and readiness authority are revoked. App/MCP call the
  same handlers.
- Project stream includes Item identification readiness, authorized attachment
  status, accounting state and safe unresolved-acquisition summary. Inventory/
  financial detail is included only for authorized users and cannot leak through
  counts/error messages.
- Server validation uses trusted current Project/Purchase/Item rows and resulting
  scope; request `accountId`/payer/source cannot grant authorization.

## Migration and Reconciliation

- Preserve legacy real Item/proto name, note(s), photos, attachment state,
  quantity, hints, intended Project/Space, candidate/acquisition Transaction,
  extraction, timestamps and conversion correlations.
- Apply the same name/photo/note rule to proposed target Item, but missing/failed
  media and empty text enter migration review rather than dropping the source.
- Never promote payer/assignment hints to Link authority. Use proven Purchase,
  Invoice/occurrence, lineage and reviewed source evidence.
- Business-paid linked source with no proven acquisition maps to explicit
  unresolved evidence; it does not fabricate Purchase/cost/date/vendor.
- Deterministically reconcile duplicate proto/Item identity under O-019 before
  creating multiple physical Items.

Reconcile every source capture to one target Item or explicit quarantine/merge,
minimum evidence/readiness, attachment bytes/reference status, accounting Link,
acquisition association/unresolved reason and source correlation. Repeat import
must be idempotent.

## Required Acceptance Tests

- name-only, note-only and durable-photo-only create one real Item; all-empty,
  whitespace, placeholder URL and failed-byte capture reject;
- photo-only survives force-quit/restart and permanent upload rejection yields
  explicit identification work without deleting Item/bytes;
- app/MCP/import repair share normalization/error codes and cannot claim missing
  photo bytes;
- pre-Link transient payer suggestion never persists or changes accounting;
- legacy hint alone does not authorize migration Link;
- Business-paid Link with selected acquisition links exact evidence; without it
  creates one occurrence plus unresolved association and no Purchase;
- later resolution links exact existing/posted real acquisition once under retry
  and never silently reprices paid/live billing;
- restricted user can work with physical Item without Business cost/vendor/count
  leakage;
- concurrent create/attachment/Link/resolve/move produces one Item/occurrence/
  association or typed conflict; and
- migration preserves/merges every proto/Item/media/hint/acquisition source with
  no fabricated money or lost evidence.

## Approval Consequences

If approved:

1. update canonical Item creation/Link/offline/attachment/acquisition specs and
   record confirmed decisions;
2. promote minimum-evidence/hint/unresolved-acquisition contracts into
   architecture 02/03/04/05/06/07;
3. remap the 11 affected surfaces while retaining O-007/O-015/O-018/O-019/O-023/
   A-015 and production-evidence blockers;
4. specify reviewed constraints/indexes, RLS/Sync profiles, operation contracts
   and migration fixtures; and
5. include offline photo-only, unresolved acquisition and privacy cases in the
   target spike.

## Approval Checklist

- [ ] Any one durable name, photo or note is sufficient minimum evidence.
- [ ] Failed/placeholder photo does not count; photo-only pending verification is
  explicit and recoverable.
- [ ] No payer hint persists in target domain/sync; Link remains authority.
- [ ] Business-paid Link without acquisition creates explicit unresolved
  evidence, not a fabricated Purchase or zero basis.
- [ ] Resolution links/posts real evidence through typed commands and never
  silently reprices billing history.
