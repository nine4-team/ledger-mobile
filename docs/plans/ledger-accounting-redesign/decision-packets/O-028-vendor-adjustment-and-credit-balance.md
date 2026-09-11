# Decision Packet — O-028 Vendor Adjustment and Credit Balance

Status: proposed recommendation; product decision not yet approved
Last reviewed: 2026-08-31
Owners: Transactions, Inventory, Invoicing, Vendor Evidence, Reporting
Unlocks: 2 residual surfaces; both also retain other independent blockers
Residual register: [generated M2 queue](../conversion/residual-decision-register.generated.md)

## Decision Requested

Approve or reject this model:

> A vendor cancellation, price adjustment, or vendor account credit for which
> the scope owner has not received money is a typed non-Transaction commercial
> adjustment. It may create or change an exact vendor credit balance, cancel an
> unreceived acquisition line, or reclassify acquisition basis, but it never
> creates a Purchase, Return, Transfer, Client credit, or physical movement.

> If the vendor later sends actual money to the scope owner, record one
> scope-relative Return linked to the adjustment and consume the corresponding
> unsettled vendor credit. If the vendor credit is instead applied to a later
> purchase, record an exact application against that purchase; the Purchase
> records only the additional money actually paid.

If no money ever moved and the source Purchase is still a capture draft, correct
or discard that draft under O-029/O-032 instead of posting a vendor adjustment.
If a canonical Purchase already records actual money paid, preserve it and use
the adjustment/balance lifecycle rather than rewriting cash history.

## Confirmed Constraints

- Target Transactions remain exactly Purchase, Return, and project-only
  Transfer.
- Purchase and Return represent actual scope-owner money movement. A Return is
  not a generic negative adjustment or physical-return label.
- The economic owner is the Client in project scope and 1584 in Business
  Inventory scope.
- Vendor refund, physical Item movement, Client credit, acquisition correction,
  and vendor account credit are distinct stories even when one user action
  initiates more than one of them.
- One physical Item identity and its acquisition/placement/Invoice occurrences
  remain explainable across cancellation, later fulfillment, application, and
  refund.
- Exact integer cents, source evidence, idempotent commands, and immutable paid
  or posted history are required.

## Options

### Option A — Add a fourth `Credit` Transaction type

Recommendation: reject. It contradicts D-001 and makes cash and non-cash events
indistinguishable in budgets, reports, reconciliation, and migration.

### Option B — Record every vendor credit as a Return

Recommendation: reject. A Return asserts actual money received under D-007. It
would overstate refunds and could also confuse physical disposition with cash.

### Option C — Rewrite or reduce the original Purchase

Recommendation: reject after posting. It destroys the evidence of money that
actually left the owner, races downstream Invoice/acquisition history, and makes
later cash refund or credit application double-counting difficult to detect.
Dependency-safe correction of a draft or an erroneous posting remains governed
by O-029/O-032.

### Option D — Typed adjustment plus conserved vendor credit balance
(recommended)

Preserve cash Transactions, record the commercial event separately, and require
every credited cent to remain open, be applied once, be realized as one actual
Return, or be explicitly corrected/expired with evidence.

Recommendation: approve. This preserves the three-type taxonomy, explains what
the vendor owes or has provided, and supports later settlement without pretending
money moved early.

## Event Taxonomy

The command must name one source-supported event:

| Event | Required source | Item/acquisition effect | Balance effect |
|---|---|---|---|
| `cancel_unreceived_lines` | Posted Purchase/acquisition lines plus vendor cancellation evidence | Marks selected acquisition occurrences canceled/not received; no physical Return | Creates exact unsettled vendor credit only when the vendor owes reusable credit or cash |
| `price_adjustment` | Posted Purchase plus vendor adjustment evidence | Reclassifies exact approved basis components without changing the posted cash Transaction | Creates exact unsettled credit when not already settled |
| `courtesy_credit` | Vendor-issued evidence | No source acquisition or Item movement required | Creates exact unsettled credit owned by the evidenced scope owner |
| `correct_vendor_adjustment` | Prior adjustment plus reason/evidence | Append-only supersession; never edits frozen facts silently | Reverses/replaces only the still-unsettled or explicitly corrected effects |

An order canceled before any actual payment is not a zero-dollar Purchase plus
credit. It remains or becomes a nonfinancial draft/cancellation. A vendor
preauthorization is evidence, not a posted Purchase, unless money actually
settled under the canonical posting rules.

Physical disposition is independent:

- an Item never received may have its acquisition occurrence canceled;
- an Item received and later sent back uses the physical vendor-return workflow;
- actual money received from that vendor creates the scope-relative Return; and
- none of these facts implies the others without explicit evidence.

## Balance and Settlement Model

Every vendor credit balance is scoped by Account, economic owner, vendor, and
currency. It cannot be applied across Accounts, owners, vendors, or currencies.
Project context is retained for provenance and reporting; any later same-owner
cross-Project application is explicit and never relabeled as an Item Transfer.

For one credit origin:

```text
issued_cents
  = open_cents
  + applied_cents
  + cash_refunded_cents
  + expired_or_corrected_cents
```

All terms are nonnegative exact cents. The trusted transaction enforces the
identity across active applications, linked Returns, and corrections. A cent
cannot be both applied and refunded.

`ApplyVendorCredit` consumes exact open cents and links them to the later vendor
purchase evidence. Any additional cash paid is the canonical Purchase amount;
the application is non-cash consideration and remains separately visible. The
later acquisition/basis projection uses the approved treatment of cash plus
credit application without re-counting the source adjustment.

`RecordVendorCreditCashRefund` posts one scope-relative Return for the exact cash
received and atomically consumes the same balance cents. A partial refund leaves
the remainder open. A Return received before the adjustment was captured may be
linked during reviewed reconciliation, but the same cash event is never posted
twice.

## Accounting and Presentation

Canonical projections keep these measures separate:

- cash paid/received: Purchase and Return Transactions only;
- open vendor credit: unsettled non-cash asset/claim by owner/vendor/currency;
- acquisition or recognized cost: source acquisition basis after approved
  adjustment and application allocations; and
- physical status: received, canceled-before-receipt, at project/inventory, or
  returned to vendor.

A vendor adjustment must not reduce a label that means “cash paid” or render as
“refund received.” Reports may show gross cash, vendor adjustments, open credit,
applied credit, cash refund, and net recognized cost as separate named values.
Project budget treatment consumes the canonical contribution/readiness contract;
it cannot hide open credit inside a negative Transaction or infer settlement
from status alone.

Client Invoicing is not settled by a vendor credit. If a 1584-paid Item charge
must be removed or a paid Client amount credited, that separate Item/Invoice
story runs in addition to the vendor adjustment. The two records may share an
operation correlation but never substitute for each other.

## Conceptual Target Shape

| Family | Responsibility |
|---|---|
| vendor adjustment origins | Stable owner/vendor/currency/reason/source amount, source Purchase/acquisition links, evidence, revision, status |
| canceled acquisition relationships | Exact affected Item/acquisition occurrences and basis components; no fake movement |
| vendor credit balances/lots | Issued/open/applied/refunded/corrected cents and deterministic conservation |
| vendor credit applications | Exact balance-lot cents consumed by a later Purchase/acquisition |
| linked Return realization | Actual money Transaction plus exact credit cents consumed |
| adjustment correction events | Append-only supersession/reversal with actor, reason, plan, and source evidence |
| operation/results | Idempotency, payload/plan hash, expected revisions, result and conflict evidence |

Use stable client-generated IDs, `bigint` cents, explicit currency, immutable
Account/owner/vendor keys, foreign keys and checks. Index every foreign key/RLS
key plus open balance by owner/vendor/currency, source Purchase/acquisition,
application Purchase, linked Return and operation. A partial index may serve
positive open balances. Constraint triggers or trusted handlers validate exact
cross-row conservation; projections are rebuildable and never a second writer.

## Commands, Atomicity, and Concurrency

- `PreviewVendorAdjustment` returns exact eligible source lines, current balance
  effects, conflicts, evidence requirements, and a dependency-plan hash.
- `RecordVendorAdjustment` locks operation, owner/vendor, source Purchase and
  affected acquisition/Item rows in stable ID order; revalidates the plan; then
  writes origin, cancellation/basis effects, balance lot, event, and result.
- `ApplyVendorCredit` locks selected credit lots and destination Purchase/
  acquisition, prevents over-application, and writes all applications/result in
  one short transaction.
- `RecordVendorCreditCashRefund` atomically posts the Return, consumes exact lots,
  links evidence, and returns one idempotent result.
- `CorrectVendorAdjustment` appends a superseding event and is allowed only for
  effects whose downstream application/refund/history can be preserved. It
  rejects when a bespoke forward correction is required.

External receipt parsing, upload, and vendor lookup occur before the database
transaction. App and MCP call the same trusted handlers; no generic Transaction,
balance, acquisition, or Item patch can compose these stories.

## Authorization, RLS, Sync, and Offline

- Adjustment amounts, balances, applications, purchase evidence, and linked
  Returns are financial data. RLS/Sync require active membership and the named
  financial capability; physical Item access alone leaks neither rows nor counts.
- Payload Account/owner/vendor IDs never grant scope. Handlers derive and
  revalidate scope from authenticated Principal and authoritative relationships.
- Direct adjustment/balance/application/conservation writes are revoked. Result
  projections expose only authorized identifiers and safe conflict detail.
- Project/Inventory streams include the authorized current adjustment/balance
  summaries needed to explain visible acquisition status. Full source evidence
  may use a bounded on-demand stream with explicit completeness/readiness.
- Offline capture is a durable pending operation with source revisions, exact
  cents, currency, evidence references, and dependency-plan hash. The UI may
  preview effects but cannot treat pending credit as settled or spendable.
- Concurrent application/refund/correction or source-Purchase correction
  serializes or returns a typed conflict with no partial consumption.

## Migration and Reconciliation

For legacy vendor-credit-like evidence:

1. preserve every Transaction label, amount, vendor, Project/Inventory scope,
   Item membership, movement/reimbursement field, status, note, attachment,
   timestamp, deletion/correction record, and source ID/hash;
2. never convert a legacy Return to an adjustment merely because notes mention
   cancellation, and never assume cash was received from the `return` label;
3. classify only when source evidence proves actual cash, non-cash credit,
   cancellation, application, or duplicate/error; otherwise quarantine for
   review with the raw source retained;
4. map proven cash to scope-relative Return, proven open/non-cash credit to the
   adjustment/balance model, and never-paid drafts to draft correction; and
5. preserve ambiguous cents and ownership without fabricating application,
   refund, Item movement, or acquisition basis.

Reconcile source-to-target IDs, owner/vendor/currency, cash Transactions,
adjustment origins, selected acquisition lines, balance conservation,
applications, linked Returns, Item physical state, acquisition basis, budget/
report contributions, evidence references, correction chains, and quarantines.
Repeat/interrupted import must be idempotent.

## Required Acceptance Tests

- cancellation before any money moves produces no canonical Transaction and no
  vendor balance unless vendor evidence actually grants one;
- posted cash remains immutable when later non-cash cancellation/price credit is
  recorded;
- vendor adjustment creates no fourth Transaction and cannot masquerade as a
  Return, Client credit, or Item movement;
- selected unreceived lines cancel without changing unrelated fulfilled lines;
- balance conservation holds through partial/multiple applications, partial cash
  refund, correction, expiry, stable retry, and one-cent boundaries;
- credit application plus new Purchase records exact non-cash consideration and
  actual cash without double-counting acquisition/recognized cost;
- cash refund posts exactly one scope-relative Return and consumes the same cents;
- cross-Account/owner/vendor/currency application rejects; explicit same-owner
  cross-Project use remains traceable and creates no Transfer;
- client Invoicing/credit behavior remains separate from the vendor event;
- concurrent apply/refund/correct/source-change writes serialize or conflict with
  zero partial effects;
- restricted users cannot infer balances, adjustment counts, sources, or cents
  through RLS, Sync, search, reports, errors, or operation results;
- offline submit/restart/reconnect exposes pending/accepted/rejected truth and
  never makes pending credit spendable; and
- migration fixtures distinguish proven cash refund, non-cash credit, never-paid
  cancellation, ambiguous legacy Return, and duplicate evidence deterministically.

## Approval Consequences

If approved:

1. update canonical Transaction, vendor-credit, acquisition, budget/report, and
   migration specs and record the confirmed decision;
2. promote the adjustment/balance/application/Return-link contracts into
   architecture 02/03/04/05/06/07/08;
3. remap the two O-028 surfaces while retaining their O-003–O-015/O-029–O-036,
   target-profile, and other independent blockers;
4. specify reviewed constraints/indexes, RLS/Sync profiles, conservation
   fixtures, migration classifications, and projection arithmetic; and
5. include balance-consumption concurrency, offline pending truth, data-leakage,
   and cash-versus-noncash reconciliation in the target spike.

## Approval Checklist

- [ ] Non-cash vendor events use a typed non-Transaction adjustment.
- [ ] Only actual money received creates a scope-relative Return.
- [ ] Posted cash history is preserved; never-paid drafts use draft correction.
- [ ] Vendor credit cents are conserved through open, applied, cash-refunded, or
  explicitly corrected/expired states.
- [ ] Credit application records non-cash consideration separately from the
  actual-cash Purchase.
- [ ] Vendor, Client/1584 owner, currency, physical Item state, Client Invoicing,
  and acquisition basis remain explicit and non-interchangeable.
