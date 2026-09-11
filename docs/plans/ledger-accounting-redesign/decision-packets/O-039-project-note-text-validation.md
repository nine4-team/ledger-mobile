# Decision Packet — O-039 Project Note Text Validation

Status: proposed recommendation; product decision not yet approved
Last reviewed: 2026-09-03
Owners: Project Notes, App, MCP, Offline Operations, Migration
Unlocks: shared Project-note submission and entry-point integration
Residual register: [generated M2 queue](../conversion/residual-decision-register.generated.md)

Affected blocker: `O-039`

Affected conversion surfaces: `SWIFT-A3E38557F13F`, `SWIFT-7DC1AEC51D21`,
`SWIFT-1DA3D2CE9B31`, `SWIFT-A3AB0F29E150`, `SWIFT-5B59D74F6B13`,
`MCPMOD-7774C2CE6D09`, `MCPTOOL-D7FEF2D5FE3B`, and
`MCPMOD-DAB760104CEE`.

## Decision Requested

Approve or reject this policy:

> New and edited Project-note submissions trim one explicit language-neutral
> edge-scalar set, preserve all other accepted Unicode scalars without NFC/NFKC
> rewriting, reject a defined unsafe-control set, require a nonempty remainder,
> and permit at most 16,384 UTF-8 bytes. App and MCP use the same fixtures and
> validation. Existing imported notes retain their original text bytes as
> migration evidence unless a separately reviewed repair/quarantine is required.

This is a product recommendation. It is not implementation, schema, migration,
provider, production, release or cutover approval.

## Why a Decision Is Required

Current entry points disagree:

- `QuickNoteModal` and `NotesTabView` trim outer whitespace/newlines before
  submitting and accept any nonempty remainder;
- the MCP `requireNonEmptyNote` helper rejects trimmed text shorter than three
  characters but passes the caller's original string onward; and
- the provider-free `ProjectNoteText` representation rejects blank-only text
  while preserving every accepted byte, so it can represent either policy but
  must not silently choose the shared submission rule.

These are user-visible differences. A conversion dossier, architecture port or
existing implementation cannot decide which behavior the redesigned app and MCP
share.

## Confirmed Constraints

- Project-note text cannot be blank after whatever outer-whitespace rule is
  approved.
- App and MCP must converge on one target application command path; a transport
  cannot own alternate product validation.
- Stable Account, Project, note and Operation identities remain independent of
  display text.
- Client-supplied actor, capture time and requested source remain intent; trusted
  server handling owns authoritative audit and final source.
- Existing source note text is migration evidence and must not be silently
  rewritten merely to satisfy a new-submission rule.

## Options

All options use valid Unicode scalar input, reject the same unsafe controls,
apply the same 16,384 UTF-8-byte new-create/edit maximum, preserve accepted
scalars without Unicode normalization, and keep lossless source migration
separate. They differ only in edge trimming and minimum content.

### Option A — Exact edge trim; nonempty; 16 KiB maximum (recommended)

This matches the app's practical behavior, removes the MCP-only arbitrary
three-character floor, preserves meaningful interior formatting and Unicode
spelling, and gives app, MCP and offline retries one cross-runtime rule.

### Option B — Preserve every accepted scalar; reject blank-only

This is maximally lossless for new input but permits accidental outer blank
lines/spaces to become canonical content and changes current app behavior.

### Option C — Exact edge trim; require three Unicode scalars

This aligns with the MCP's current minimum but would newly reject valid
one- or two-character notes in the app without a demonstrated product need.

## Proposed Target Contract

If Option A is approved, `ProjectNoteSubmissionText` uses this exact algorithm:

- reject malformed Unicode/lone-surrogate input, then trim from both ends only
  these scalar values:
  `U+0009–U+000D`, `U+0020`, `U+0085`, `U+00A0`, `U+1680`,
  `U+2000–U+200A`, `U+2028`, `U+2029`, `U+202F`, `U+205F`, `U+3000`, and
  `U+FEFF`;
- reject `U+0000`, `U+200B`, interior `U+FEFF`, and control scalars
  `U+0001–U+0008`, `U+000B–U+000C`, `U+000E–U+001F`, and
  `U+007F–U+009F`; horizontal tab, line feed and carriage return remain allowed
  inside text;
- perform no Unicode normalization or case folding;
- reject an empty scalar sequence after edge trimming; one or two remaining
  Unicode scalars are valid and no UTF-16/code-unit or grapheme-count minimum is
  used;
- reject canonical output above 16,384 UTF-8 bytes; and
- preserve every accepted remaining scalar and its UTF-8 encoding exactly.

Then:

- app and MCP call the same application use case and cannot add channel-specific
  minimums;
- create and edit use the same text conversion and stable validation result;
- retries preserve the normalized text and OperationID exactly; and
- authoritative creator, time and final source remain server-owned and outside
  this decision.

The broader `ProjectNoteText` storage/read value may remain capable of preserving
legacy bytes. Submission normalization and stored historical representation do
not need to be the same type or migration policy.

## Conceptual Target Ownership

| Family | Responsibility |
|---|---|
| submission input/value | Apply the one approved outer-whitespace and minimum rule |
| note-create application use case | Validate before dispatch and construct one typed command |
| note operation/result | Preserve stable IDs, exact canonical submitted text, replay and rejection |
| trusted handler | Authorize parent scope and assign authoritative creator/time/final source |
| migration transform | Preserve original source text and correlation without pretending it was new target input |

## Domain, Schema, Command, and Query Consequences

- The domain separates source/stored `ProjectNoteText` representation from the
  user-submission normalization rule if needed to preserve legacy bytes.
- `AddProjectNoteCommand` carries exactly the canonical submitted text; there is
  no parallel MCP payload rule or generic note-field patch.
- The trusted create/edit handler repeats the canonical validity check inside
  its transaction before changing a note and durable operation result. A database
  constraint may enforce nonblank canonical text only if it exactly matches the
  approved Unicode/whitespace semantics; otherwise the handler and generated
  contract own the rule and the table stores bounded text without a divergent
  SQL approximation.
- Note reads/search return stored text without applying submission normalization
  again. Search normalization, indexing and matching remain separate contracts.
- Migration rows carry original text plus correlation/review state and never run
  through the new-submission command merely to force normalization.

## Authorization, Sync, Offline, and Concurrency

- Text validity never authorizes Account membership or Project visibility.
- Invalid text creates no local operation or optimistic note and reaches no
  provider. Valid offline input queues one durable idempotent operation only
  after the separately gated physical local-store contract exists.
- App and MCP must return the same stable validation classification without
  echoing rejected text into logs or diagnostics.
- Reusing an OperationID with differently normalized text is a payload mismatch;
  concurrent retries of the same canonical input resolve through the shared
  operation lifecycle rather than creating duplicate notes.
- Server rejection for authorization, parent absence, stale capability or final
  source policy remains distinct from local text validation.

## Migration and Reconciliation

- Do not rewrite Firebase note text merely to match the new submission rule.
- Preserve original valid-Unicode, non-NUL source text even when it exceeds the
  new-submission limit or contains controls disallowed for new edits; tag its
  legacy provenance so later editing must pass the approved submission rule.
- A source value containing invalid Unicode bytes or `U+0000` cannot enter a
  PostgreSQL `text` value. Preserve its exact bytes/hash and source correlation
  in the migration quarantine/evidence artifact; do not truncate, substitute or
  claim a canonical note row.
- Quarantine structurally invalid or unscoped source records under the separately
  approved migration contract.
- The Firebase app and MCP remain unchanged before hard cutover.
- Reconcile source and target note ID, parent, exact source-text hash, canonical
  new-submission text, actor/time provenance and every quarantine disposition.

## Required Acceptance Tests

- app and MCP create/edit accept or reject the same empty, one-scalar,
  two-scalar, padded, multiline, emoji and composed/decomposed Unicode fixtures;
- shared vectors cover every trim scalar and boundary, `U+200B`, edge/interior
  `U+FEFF`, NUL, lone surrogates, each rejected control range, allowed tab/LF/CR,
  16,384 and 16,385 UTF-8 bytes, and a supplementary scalar whose UTF-8/UTF-16
  sizes differ;
- accepted outer whitespace/newlines follow the approved normalization rule and
  interior formatting remains exact;
- invalid input creates no local operation, optimistic row or provider call;
- replay/restart retains the exact approved canonical text and OperationID;
- source Firebase notes with outer whitespace, fewer than three characters,
  disallowed controls or more than 16,384 bytes import or quarantine according
  to the exact lossless rule without silent rewriting; and
- validation errors expose no note content, Account/Project identity, provider
  payload or credential.

## Approval Consequences

If approved:

1. add the chosen rule to a canonical Project-note target-spec heading and
   record a confirmed D decision;
2. update the shared note submission dossier and exact app/MCP contracts;
3. remove O-039 only from surfaces whose implementation and tests prove the
   approved behavior; and
4. retain separate migration fixtures proving legacy text preservation.

## Approval Checklist

- [ ] Choose Option A, B or C and approve the exact scalar/count/byte semantics.
- [ ] Confirm the explicit trim and rejected-control scalar sets.
- [ ] Confirm the 16,384 UTF-8-byte new-create/edit maximum.
- [ ] Confirm app and MCP must share the exact same rule.
- [ ] Confirm create and edit use the exact same rule.
- [ ] Confirm existing imported note text is preserved rather than normalized.
