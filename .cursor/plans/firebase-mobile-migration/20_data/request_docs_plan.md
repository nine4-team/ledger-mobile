# Request Docs: Canonical Contract (Build It Right)

This doc is a **spec-first plan** to eliminate “request-doc helper drift” while we are still designing the new app.

It defines:
- A **canonical RequestDoc contract** (fields, scope semantics, status semantics)
- A **single pathing model** (account-level collection; scope encoded in payload)
- A **stable error taxonomy** (so UI and Functions agree)
- A **build checklist** for the client + Functions + UI

---

## Goals

- **One request-doc model** used by all “write via Functions” workflows (inventory ops, invoice import, billing-gated creates, etc.).
- **Deterministic UI semantics** for progress + failure + entitlement denial.
- **Idempotent server behavior** for retries and offline replays.
- **Clear Firestore locations** so rules, Functions, and client subscriptions don’t diverge.

## Non-goals

- Finalizing every `payload` schema for every feature here (those belong in feature specs / `data_contracts.md`).
- Designing the entire sync engine.

---

## Reference: what exists today (not a constraint)

`src/data/requestDocs.ts` currently provides:
- **Scopes**: project + inventory only
  - `accounts/{accountId}/projects/{projectId}/requests/*`
  - `accounts/{accountId}/inventory/requests/*`
- **Status**: `'pending' | 'applied' | 'failed'`
- **Doc shape**: `type`, `status`, timestamps, `errorCode`, `errorMessage`, `payload`
- **Subscribe**: can subscribe by **explicit doc path** (`subscribeToRequestPath`)

This plan treats today’s helper as **an implementation detail**, not a spec constraint.

---

## Canonical scope (what we will build)

Request docs use **one collection path**:

1) **Account-scoped (single path)**
- Path: `accounts/{accountId}/requests/{requestId}`
- Scope is encoded in `payload` (e.g. `payload.projectId` where applicable).
- Use for all operations (project, inventory, and account-global). The Function applies scope rules based on payload fields.

### Rule

For any request doc, **the scope is determined by the payload**, since the path is shared.

---

## Idempotency (what makes retries safe): `opId`

`opId` is a **required top-level field** on RequestDoc (not only inside `payload`).

- **`requestId`** (doc id) = attempt id (each retry can create a new doc)
- **`opId`** = stable idempotency key for at-most-once server application

### What Functions must do

For each request `type`, the Function must enforce:
- At-most-once application per `(scopePath, type, opId)` (or equivalent canonical key)
- If a duplicate arrives, it returns/records the already-applied outcome deterministically

### What the client must do

- Client generates an `opId` such that “same intent” → “same `opId`”
- Retries reuse the same `opId` but get a new `requestId` (new Firestore doc id)
- Best practice: generate a UUID at intent start and persist it locally for retries.

---

## Status + denial semantics (what UI can rely on)

### Preferred: persist `denied`

Expand status to:
- `pending | applied | failed | denied`

Rules:
- **`denied`** means “request was valid but policy/entitlement prevents execution”.
- `failed` means “unexpected error, validation error, transient infra error, or conflict”.

UI consequences:
- `denied` maps to **upgrade/paywall/permissions** UX, not “try again” UX.

### Acceptable fallback: encode denial via `errorCode`

Keep stored status as:
- `pending | applied | failed`

But make denial semantics canonical via:
- `errorCode = "ENTITLEMENT_DENIED"` (single canonical code)

UI treats:
- `status="failed" && errorCode==="ENTITLEMENT_DENIED"` as **denied semantics**

### Hard rule (either way)

**Do not allow multiple denial codes** (`DENIED` vs `ENTITLEMENT_DENIED`). Pick one canonical value:
- `ENTITLEMENT_DENIED`

---

## Canonical RequestDoc shape (this is the contract)

Minimum shape:

- `type: string`
- `status: "pending" | "applied" | "failed" | "denied"`
- `opId: string`
- `createdAt`, `createdBy`
- `appliedAt?`
- `errorCode?`, `errorMessage?`
- `payload: object` (type-specific)

Notes:
- `errorMessage` is **safe to show** (no internal details).
- `errorCode` is **stable** and is what the UI branches on.

---

## Error codes (tiny set, stable forever)

Define a small canonical set so the UI stays consistent across features:

- `ENTITLEMENT_DENIED` (paywall / upgrade / no access)
- `VALIDATION_FAILED` (bad input; fix form)
- `CONFLICT` (stale expected values; refresh + retry)
- `RETRYABLE` (transient error; “Try again”)
- `UNKNOWN` (fallback)

Feature-specific codes are allowed only if they map to one of the above UI categories.

---

## Build checklist (client + Functions + UI)

### Client helper (one “right” module)

Implement one request-doc helper that:
- Can create request docs in the **single account-level collection**
- Requires `opId`
- Subscribes by **explicit doc path** (so the API is uniform across scopes)

### Cloud Functions

For each request `type` Function:
- Read the request doc
- Validate `payload`
- Enforce idempotency on `(scopePath, type, opId)`
- Write back:
  - `status="applied"` + `appliedAt` on success, or
  - `status="denied"` + `errorCode="ENTITLEMENT_DENIED"` for entitlement/policy, or
  - `status="failed"` + an appropriate `errorCode` for everything else

### UI

UI maps strictly by status + errorCode:
- `pending`: show progress state
- `applied`: show success / navigate
- `denied` or `errorCode="ENTITLEMENT_DENIED"`: show paywall/upgrade UX
- `failed` + retryable codes: show “Try again”
- `failed` + validation/conflict: show corrective action

---

## Guardrails (“don’t let drift happen again”)

- **Specs must not reference a helper file** as the source-of-truth. Specs reference the **contract** (this doc + `data_contracts.md`).
- **A request’s scope is determined by the payload**, since the path is shared for all requests.
- **All “denied” semantics use the same `errorCode`** (`ENTITLEMENT_DENIED`).
- **All retries reuse `opId`**; new Firestore doc ids represent attempts, not intent.

---

## Open questions to resolve explicitly (before coding)

- Do we always persist `denied`, or do we keep `failed` + `ENTITLEMENT_DENIED` for some edge cases?
- What is the canonical idempotency key namespace:
  - `opId` globally unique UUID, or
  - deterministic hash of intent (with collision strategy)?
- Should `type` be standardized as an enum string set in `20_data` now?

