# Decision Packet — O-044/O-045/O-046 Space Creation Boundary

Status: proposed recommendation; product decision not yet approved
Last reviewed: 2026-09-05
Owners: Spaces, Projects, App, MCP, Offline Operations, Security, Migration
Unlocks: provider-backed direct Space creation and later Space detail editing

Affected blockers: `O-044`, `O-045`, `O-046`

## Decisions Requested

Approve, reject, or revise these independent recommendations.

### O-044 — Shared Space text contracts

> Space-name submissions use the language-neutral single-line display-name
> algorithm already proposed for Client names, with a 512 UTF-8-byte maximum.
> Space-notes submissions use the same explicit edge-trim set, permit tab/LF/CR
> inside the canonical value, reject NUL and other unsafe controls, and permit
> at most 16,384 UTF-8 bytes. Neither performs Unicode normalization, case
> folding, whitespace collapsing, truncation, or channel-specific validation.

### O-045 — Direct-create authorization

> Any active Account member may directly create a Space in a Project or Business
> Inventory scope that the member can otherwise resolve. Space creation does not
> require financial visibility, Project-management authority, Client management,
> or shared-reference-data management. No new `can_manage_spaces` capability is
> introduced by this decision.

### O-046 — Archived Project parent

> A new Project-scoped Space requires an active same-Account Project parent.
> Archiving a Project continues to preserve and resolve its existing Spaces, but
> no new Space may be created beneath it until a separately authorized restore.
> Business Inventory creation is unaffected.

These are product recommendations only. They do not authorize implementation,
hosted provisioning, source migration, deployment, release, or cutover.

## Why Decisions Are Required

The canonical Space spec establishes stable identity, exact Project-or-Business-
Inventory scope, outer-whitespace normalization, duplicate-name validity,
offline acceptance, and exact parent validation. It does not define a runtime-
independent text boundary, command-specific writer role, or archived-parent
eligibility.

The verified Swift `SpaceDisplayName` and `SpaceCreationNotes` use Foundation's
whitespace tables and accept unbounded remaining text, including `U+0000`.
JavaScript trimming is not identical, and PostgreSQL `text`/`jsonb` cannot store
NUL. SQL-only rejection or MCP-only trimming would make the same user intent
behave differently by channel and would change canonical command fingerprints.

The security architecture requires every trusted handler to authorize the
specific command. Current Firebase lets ordinary members write Spaces, but the
conversion method correctly treats that as source evidence rather than target
product authority. Similarly, preserving existing children during Project
archive does not imply permission to create new children.

## Confirmed Constraints This Packet Cannot Reopen

- SpaceID, not display name or route text, is Account-scoped identity. Duplicate
  names remain valid.
- One Space has exactly one immutable Project-or-Business-Inventory creation
  scope. A Project parent must be exact and in the same Account.
- Direct creation owns only identity, scope, canonical name, and optional notes.
  It cannot create templates, checklists, attachments, review evidence, Item
  placement, archive state, Transactions, Invoices, budgets, or other accounting.
- Local validation and a represented parent never grant current authorization.
  The server re-derives Principal, membership, scope, parent, and lifecycle.
- App and MCP use one typed command and exact operation lifecycle. Source values
  remain lossless migration evidence and are never silently normalized,
  truncated, or replaced to satisfy a new-submission rule.

## O-044 Options and Recommended Algorithm

### Option A — Explicit name and notes contracts (recommended)

For both fields, require valid Unicode scalar input, trim only:
`U+0009–U+000D`, `U+0020`, `U+0085`, `U+00A0`, `U+1680`,
`U+2000–U+200A`, `U+2028`, `U+2029`, `U+202F`, `U+205F`, `U+3000`, and
`U+FEFF` from the two edges, and preserve all other accepted scalars exactly
without Unicode normalization.

For names, reject empty remainder; `U+0000`, `U+200B`, interior `U+FEFF`,
`U+2028/U+2029`, and `U+0001–U+001F` plus `U+007F–U+009F`; enforce a 512-byte
canonical UTF-8 maximum. This is a single-line display value.

For notes, nil or empty remainder means absent. Reject `U+0000`, `U+200B`,
interior `U+FEFF`, `U+0001–U+0008`, `U+000B–U+000C`, `U+000E–U+001F`, and
`U+007F–U+009F`; allow interior tab, LF, and CR; enforce a 16,384-byte canonical
UTF-8 maximum. Empty notes remain distinct from an invented placeholder.

### Option B — Preserve outer whitespace and only reject unrepresentable input

This is more literal, but changes current app behavior and allows accidental
outer whitespace to become canonical data.

### Option C — Native runtime trim/count functions

Reject. Foundation, JavaScript, and PostgreSQL use different whitespace and
length models, so exact app/MCP/server parity is impossible.

## O-045 Options

- **Any active member (recommended):** preserves the ordinary collaborative
  organizational workflow without coupling Space placement to money or project
  administration.
- **Project manager/owner only:** defensible if Space structure is controlled,
  but Ledger currently has no canonical Space-management capability.
- **New delegable Space capability:** most flexible, but adds role-management,
  migration, Sync-claim freshness, and UI work unsupported by current needs.

Authorization always precedes OperationID/Space/Project/result disclosure.
Forged actor, inactive/revoked membership, missing or foreign parent, and
cross-Account identity remain non-enumerating failures.

## O-046 Options

- **Active parent only (recommended):** archive freezes ordinary new child work
  while preserving existing Spaces and history.
- **Allow new children under archived Projects:** makes archive behave mostly as
  a browsing filter and requires archived-project creation affordances.
- **Elevated correction-only creation:** adds a second command and authorization
  path without an identified correction story.

The chosen rule must be identical in local admission, app/MCP presentation, and
the trusted server. Local Project evidence may improve feedback but cannot
replace the authoritative server check.

## Required Acceptance Tests

- Swift, TypeScript, and PostgreSQL accept/reject/canonicalize the same name and
  notes fixtures for every trim/control boundary, NUL, lone surrogate, Unicode
  composition, emoji, and 511/512/513 plus 16,383/16,384/16,385 UTF-8 bytes;
- invalid submission creates no local operation, command, pending Space, or RPC;
- authorized Project and Business Inventory creation succeeds for the approved
  member roles; inactive/revoked/anonymous/forged/cross-Account cases fail
  without revealing Space, Project, operation, or result existence;
- missing, foreign-Account, active, and archived Project parents follow one
  exact policy across local feedback, app, MCP, and the server;
- duplicate canonical names under distinct Space IDs succeed, while concurrent
  claims on one Space ID produce one deterministic winner and immutable result;
- exact replay returns the same result; changed reuse cannot rebind;
- accepted offline intent survives restart and appears only in the exact
  Account/scope directory as partial evidence until durable rejection or exact
  authoritative readback; and
- migration fixtures preserve source bytes/hash and quarantine any value that
  PostgreSQL cannot represent without silent trimming, normalization, truncation,
  substitution, or placeholder insertion.

## Approval Consequences

If approved:

1. add the chosen text, authorization, and Project-lifecycle rules to canonical
   Space/Project specs and record confirmed D decisions;
2. update the provider-free Space submission types if their admitted values are
   broader than the approved command boundary;
3. remove O-044/O-045/O-046 only from slices and surfaces whose exact tests pass;
4. return the direct Space-create provider dossier to independent READY review;
   and
5. retain A-003/A-004, hosted Auth/Sync, migration, release, and cutover as
   separate gates.

## Approval Checklist

- [ ] Approve O-044 Option A or select another text contract.
- [ ] Confirm 512-byte Space names and 16,384-byte Space notes.
- [ ] Approve O-045 any-active-member authorization or select another role.
- [ ] Approve O-046 active-parent-only creation or select another lifecycle rule.
- [ ] Confirm app, MCP, local admission, PostgreSQL, and migration fixtures must
  use the same decisions without channel-specific exceptions.
